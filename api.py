#!/usr/bin/env python3
"""Football data client for the Omarchy Football bar widget.

Data sources (fixed HTTPS endpoints only):
  * ESPN public site API  - scores, schedules, standings, match details, search
  * FotMob public API     - Moroccan Botola Pro (not covered by ESPN)

Every HTTP response is cached on disk (``$XDG_CACHE_HOME/ayman-football``)
with a short, per-endpoint TTL.  The QML panel starts a fresh Python process
for every request, so the disk cache is what makes switching tabs fast.  When
the network fails the last cached copy is served instead.
"""
import concurrent.futures
import gzip
import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

# Prefer IPv4: some networks advertise an unreachable IPv6 default route,
# which makes every request wait for the IPv6 connect timeout first.
try:
    _orig_getaddrinfo = socket.getaddrinfo

    def _v4_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
        try:
            return _orig_getaddrinfo(host, port, socket.AF_INET, type, proto, flags)
        except socket.gaierror:
            return _orig_getaddrinfo(host, port, family, type, proto, flags)

    socket.getaddrinfo = _v4_getaddrinfo
except Exception:
    pass

BASE = "https://site.api.espn.com/apis/site/v2/sports/soccer"
STANDINGS_BASE = "https://site.api.espn.com/apis/v2/sports/soccer"
CORE_BASE = "https://sports.core.api.espn.com/v2/sports/soccer"
SEARCH_URL = "https://site.web.api.espn.com/apis/search/v2"
FOTMOB = "https://www.fotmob.com/api/data"
HEADERS = {"User-Agent": "OmarchyFootballWidget/2.0 (Linux)", "Accept-Encoding": "gzip"}
FOTMOB_HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36",
    "Referer": "https://www.fotmob.com/",
    "Accept-Encoding": "gzip",
}
MAX_BYTES = 6 * 1024 * 1024
FAILURES = []  # URLs that failed with no cached copy during this run

CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "ayman-football")
HTTP_CACHE = os.path.join(CACHE_DIR, "http")
LOGO_CACHE = os.path.join(CACHE_DIR, "logos")
STATE_FILE = os.path.join(CACHE_DIR, "alerts-state.json")

# Botola Pro is served from FotMob; its team ids are FotMob ids.
BOTOLA = "mar.1"
BOTOLA_FOTMOB_ID = 530

LEAGUES = {
    "eng.1": "Premier League", "esp.1": "La Liga", "ita.1": "Serie A", "ger.1": "Bundesliga",
    "fra.1": "Ligue 1", "por.1": "Primeira Liga", "ned.1": "Eredivisie", "tur.1": "Süper Lig",
    "sco.1": "Scottish Premiership", "bel.1": "Belgian Pro League", "eng.2": "Championship",
    "uefa.champions": "Champions League", "uefa.europa": "Europa League",
    "uefa.europa.conf": "Conference League", "uefa.super_cup": "UEFA Super Cup",
    "uefa.nations": "UEFA Nations League", "uefa.euro": "EURO", "uefa.euroq": "EURO Qualifying",
    "fifa.worldq.uefa": "World Cup Qualifying (UEFA)",
    "eng.fa": "FA Cup", "eng.league_cup": "Carabao Cup", "esp.copa_del_rey": "Copa del Rey",
    "esp.super_cup": "Supercopa de España", "ita.coppa_italia": "Coppa Italia",
    "ita.super_cup": "Supercoppa Italiana", "ger.dfb_pokal": "DFB-Pokal",
    "fra.coupe_de_france": "Coupe de France", "ned.cup": "KNVB Beker", "por.taca.portugal": "Taça de Portugal",
    "mar.1": "Botola Pro", "caf.champions": "CAF Champions League", "caf.confed": "CAF Confederation Cup",
    "caf.nations": "Africa Cup of Nations", "caf.nations_qual": "AFCON Qualifying",
    "fifa.worldq.caf": "World Cup Qualifying (CAF)", "caf.championship": "CHAN", "rsa.1": "South African Premiership",
    "ksa.1": "Saudi Pro League", "ksa.kings.cup": "King's Cup", "afc.champions": "AFC Champions League Elite",
    "afc.asian.cup": "AFC Asian Cup", "fifa.worldq.afc": "World Cup Qualifying (AFC)",
    "jpn.1": "J1 League", "chn.1": "Chinese Super League", "aus.1": "A-League Men",
    "usa.1": "MLS", "mex.1": "Liga MX", "bra.1": "Brasileirão", "arg.1": "Liga Profesional",
    "conmebol.libertadores": "Copa Libertadores", "conmebol.sudamericana": "Copa Sudamericana",
    "conmebol.america": "Copa América", "fifa.worldq.conmebol": "World Cup Qualifying (CONMEBOL)",
    "concacaf.gold": "Gold Cup", "concacaf.champions": "Concacaf Champions Cup",
    "concacaf.nations.league": "Concacaf Nations League", "fifa.worldq.concacaf": "World Cup Qualifying (Concacaf)",
    "fifa.world": "FIFA World Cup", "fifa.friendly": "International Friendly", "fifa.cwc": "FIFA Club World Cup",
    "fifa.intercontinental_cup": "FIFA Intercontinental Cup", "club.friendly": "Club Friendly",
}
KNOWN_LEAGUE_LOGOS = {
    "mar.1": "https://images.fotmob.com/image_resources/logo/leaguelogo/dark/530.png",
}

# Competitions where national teams play.  Used to tell clubs and national
# teams apart when a team is picked from search.
NATIONAL_COMPETITIONS = {
    "fifa.world", "fifa.friendly", "caf.nations", "caf.nations_qual", "fifa.worldq.caf", "uefa.nations",
    "uefa.euro", "uefa.euroq", "fifa.worldq.uefa", "afc.asian.cup", "fifa.worldq.afc", "conmebol.america",
    "fifa.worldq.conmebol", "concacaf.gold", "concacaf.nations.league", "fifa.worldq.concacaf", "caf.championship",
}


# --------------------------------------------------------------------------
# HTTP + cache
# --------------------------------------------------------------------------

def _cache_path(url):
    return os.path.join(HTTP_CACHE, hashlib.sha1(url.encode("utf-8")).hexdigest() + ".json")


def _read_cache(url, ttl):
    path = _cache_path(url)
    try:
        age = time.time() - os.path.getmtime(path)
        if ttl is not None and age > ttl:
            return None
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def _write_cache(url, data):
    try:
        os.makedirs(HTTP_CACHE, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=HTTP_CACHE, suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle)
        os.replace(tmp, _cache_path(url))
    except OSError:
        pass


def _download(url, headers, timeout):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        raw = response.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            raise ValueError("response too large")
        if response.headers.get("Content-Encoding") == "gzip" or raw[:2] == b"\x1f\x8b":
            raw = gzip.decompress(raw)
        return json.loads(raw.decode("utf-8"))


def fetch_json(url, ttl=60, headers=None, timeout=6):
    """GET JSON with a disk cache.  ttl=None never expires; stale copies are
    returned when the network request fails."""
    cached = _read_cache(url, ttl)
    if cached is not None:
        return cached
    try:
        data = _download(url, headers or HEADERS, timeout)
    except (OSError, ValueError, urllib.error.URLError):
        stale = _read_cache(url, None)
        if stale is None:
            FAILURES.append(url)
        return stale
    if isinstance(data, dict) and data.get("code") == 400:
        data = {}
    _write_cache(url, data)
    return data


def parallel(func, items, workers=16):
    items = list(items)
    if not items:
        return []
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(workers, len(items))) as pool:
        return list(pool.map(func, items))


def parse_date(text):
    if not text:
        return None
    try:
        date = datetime.fromisoformat(str(text).replace("Z", "+00:00"))
    except ValueError:
        return None
    return date if date.tzinfo else date.replace(tzinfo=timezone.utc)


def scoreboard_ttl(date_text):
    today = datetime.now().strftime("%Y%m%d")
    if date_text == today:
        return 20
    if date_text < today:
        return 3600
    return 900


# --------------------------------------------------------------------------
# Normalisation helpers
# --------------------------------------------------------------------------

def display_league_name(league):
    return LEAGUES.get(league, str(league).replace(".", " ").replace("_", " ").title())


def prefer_dark_logo(url):
    if not url or not isinstance(url, str):
        return ""
    if "espncdn.com" in url and "/500/" in url and "/teamlogos/" in url:
        return url.replace("/500/", "/500-dark/")
    return url


def logo_from(obj):
    if not isinstance(obj, dict):
        return ""
    logos = obj.get("logos") or []
    if isinstance(logos, list):
        for item in logos:
            if isinstance(item, dict) and "dark" in (item.get("rel") or []) and item.get("href"):
                return item["href"]
        for item in logos:
            if isinstance(item, dict) and item.get("href"):
                return prefer_dark_logo(item["href"])
    return prefer_dark_logo(obj.get("logo") or "")


def score_text(value):
    if isinstance(value, dict):
        value = value.get("displayValue", value.get("value", ""))
    if value is None:
        return ""
    text = str(value)
    if text.endswith(".0"):
        text = text[:-2]
    return text


def clean_detail(state, status_type):
    detail = status_type.get("shortDetail") or status_type.get("detail") or ""
    if state == "pre" or re.search(r"\b(EST|EDT|CST|PST|ET)\b", detail):
        name = status_type.get("name", "")
        if name in ("STATUS_POSTPONED", "STATUS_CANCELED", "STATUS_ABANDONED", "STATUS_SUSPENDED"):
            return status_type.get("description") or "Postponed"
        return "Scheduled"
    return detail


def event_round(event, competition):
    for source in (event, competition):
        for key in ("round", "matchday", "week"):
            value = source.get(key)
            if isinstance(value, dict):
                label = value.get("displayValue") or value.get("text") or value.get("name")
                if label and not re.search(r"\b(19|20)\d\d\b", str(label)):
                    return str(label)
                number = value.get("number") or value.get("value")
                if number is not None:
                    return f"Round {number}"
            elif value is not None and value != "":
                return f"Round {value}"
        for note in source.get("notes") or []:
            if isinstance(note, dict):
                label = str(note.get("headline") or note.get("text") or "").strip()
                if label and len(label) < 60 and not re.search(r"\b(19|20)\d\d\b", label):
                    return label
    season_type = event.get("seasonType")
    if isinstance(season_type, dict):
        name = season_type.get("name") or season_type.get("abbreviation") or ""
        if name and name.lower() not in ("regular season", "season") and not re.search(r"\b(19|20)\d\d\b", name):
            return name
    return ""


def parse_details(details, home_id, away_id):
    """Scoring plays and red cards from a scoreboard competition."""
    goals, reds = [], []
    for item in details or []:
        if not isinstance(item, dict):
            continue
        team_id = str((item.get("team") or {}).get("id", ""))
        side = "home" if team_id == home_id else ("away" if team_id == away_id else "")
        athletes = item.get("athletesInvolved") or []
        player = athletes[0].get("displayName", "") if athletes and isinstance(athletes[0], dict) else ""
        clock = (item.get("clock") or {}).get("displayValue", "")
        type_text = str((item.get("type") or {}).get("text", ""))
        if item.get("scoringPlay"):
            label = player
            if item.get("ownGoal") or "own goal" in type_text.lower():
                label += " (OG)"
            elif item.get("penaltyKick") or "penalty" in type_text.lower():
                label += " (P)"
            goals.append({"side": side, "player": label.strip(), "clock": clock})
        elif item.get("redCard"):
            reds.append({"side": side, "player": player, "clock": clock})
    return goals, reds


def normalize_event(event, league_hint=""):
    """Convert an ESPN event (scoreboard or schedule flavour) to a match dict."""
    if not isinstance(event, dict):
        return None
    competition = (event.get("competitions") or [{}])[0] or {}
    competitors = competition.get("competitors") or []
    home = next((c for c in competitors if c.get("homeAway") == "home"), competitors[0] if competitors else {})
    away = next((c for c in competitors if c.get("homeAway") == "away"), competitors[1] if len(competitors) > 1 else {})
    home_team, away_team = home.get("team") or {}, away.get("team") or {}
    status = competition.get("status") or event.get("status") or {}
    status_type = status.get("type") or {}
    state = status_type.get("state", "pre")
    league = event.get("league") if isinstance(event.get("league"), dict) else {}
    league_id = league.get("slug") or league_hint
    date_text = event.get("date") or competition.get("date") or ""
    home_id, away_id = str(home_team.get("id", "")), str(away_team.get("id", ""))
    goals, reds = parse_details(competition.get("details"), home_id, away_id)
    clock = status.get("displayClock", "")
    detail = clean_detail(state, status_type)
    if status_type.get("name") == "STATUS_HALFTIME":
        detail = "HT"
    return {
        "id": str(event.get("id", "")),
        "leagueId": league_id,
        "league": LEAGUES.get(league_id) or league.get("name") or display_league_name(league_id),
        "leagueLogo": logo_from(league) or KNOWN_LEAGUE_LOGOS.get(league_id, ""),
        "date": date_text,
        "state": state,
        "statusName": status_type.get("name", ""),
        "detail": detail,
        "clock": clock,
        "round": event_round(event, competition),
        "homeId": home_id,
        "awayId": away_id,
        "home": home_team.get("shortDisplayName") or home_team.get("displayName") or "?",
        "away": away_team.get("shortDisplayName") or away_team.get("displayName") or "?",
        "homeLogo": logo_from(home_team),
        "awayLogo": logo_from(away_team),
        "homeScore": score_text(home.get("score")) if state != "pre" else "",
        "awayScore": score_text(away.get("score")) if state != "pre" else "",
        "homeWinner": bool(home.get("winner")),
        "awayWinner": bool(away.get("winner")),
        "venue": (competition.get("venue") or {}).get("fullName", ""),
        "goals": goals,
        "redCards": reds,
    }


def strip_internal(match):
    return {k: v for k, v in match.items() if not k.startswith("_")}


# --------------------------------------------------------------------------
# FotMob (Botola Pro)
# --------------------------------------------------------------------------

def fotmob_logo(team_id):
    return f"https://images.fotmob.com/image_resources/logo/teamlogo/{team_id}.png" if team_id else ""


def fetch_botola_data(ttl=300):
    return fetch_json(f"{FOTMOB}/leagues?id={BOTOLA_FOTMOB_ID}", ttl=ttl, headers=FOTMOB_HEADERS) or {}


def parse_botola_match(m):
    status = m.get("status") or {}
    home_score = away_score = ""
    score_str = status.get("scoreStr")
    if score_str and "-" in score_str:
        home_score, away_score = [part.strip() for part in score_str.split("-", 1)]
    cancelled = status.get("cancelled", False)
    if cancelled or status.get("finished"):
        state = "post"
    elif status.get("started"):
        state = "in"
    else:
        state = "pre"
    if cancelled:
        detail = "Cancelled"
    elif state == "in":
        detail = (status.get("liveTime") or {}).get("short") or (status.get("reason") or {}).get("short") or "LIVE"
    elif state == "post":
        detail = (status.get("reason") or {}).get("short") or "FT"
    else:
        detail = "Scheduled"
    round_name = m.get("roundName") or m.get("round") or ""
    home_obj, away_obj = m.get("home") or {}, m.get("away") or {}
    home_id, away_id = str(home_obj.get("id", "")), str(away_obj.get("id", ""))
    return {
        "id": str(m.get("id", "")), "leagueId": BOTOLA, "league": "Botola Pro",
        "leagueLogo": KNOWN_LEAGUE_LOGOS[BOTOLA], "date": status.get("utcTime", ""),
        "state": state, "statusName": "", "detail": detail, "clock": "",
        "round": f"Round {round_name}" if str(round_name).isdigit() else str(round_name),
        "homeId": home_id, "awayId": away_id,
        "home": home_obj.get("shortName") or home_obj.get("name") or "?",
        "away": away_obj.get("shortName") or away_obj.get("name") or "?",
        "homeLogo": fotmob_logo(home_id), "awayLogo": fotmob_logo(away_id),
        "homeScore": home_score if state != "pre" else "", "awayScore": away_score if state != "pre" else "",
        "homeWinner": False, "awayWinner": False, "venue": "", "goals": [], "redCards": [],
    }


def fetch_botola_matches(date_text=None, ttl=300):
    data = fetch_botola_data(ttl)
    result = []
    for m in (data.get("fixtures") or {}).get("allMatches", []) or []:
        parsed = parse_botola_match(m)
        if date_text:
            local = parse_date(parsed["date"])
            if not local or local.astimezone().strftime("%Y%m%d") != date_text:
                continue
        result.append(parsed)
    return result


def fetch_botola_standings():
    data = fetch_botola_data(900)
    tables = data.get("table") or []
    if not tables:
        return []
    rows = ((tables[0].get("data") or {}).get("table") or {}).get("all", []) or []
    output = []
    for item in rows:
        team_id = str(item.get("id", ""))
        gf = ga = "0"
        scores = item.get("scoresStr") or "0-0"
        if "-" in scores:
            gf, ga = [p.strip() for p in scores.split("-", 1)]
        output.append({
            "rank": str(item.get("idx", len(output) + 1)), "teamId": team_id,
            "name": item.get("name", "?"), "short": item.get("shortName") or item.get("name", "?"),
            "logo": fotmob_logo(team_id), "group": "", "played": str(item.get("played", 0)),
            "wins": str(item.get("wins", 0)), "ties": str(item.get("draws", 0)), "losses": str(item.get("losses", 0)),
            "gf": gf, "ga": ga, "gd": str(item.get("goalConDiff", 0)), "points": str(item.get("pts", 0)),
            "noteColor": hex_color(item.get("qualColor")), "note": "",
        })
    return output


def fetch_botola_teams():
    return [{"id": s["teamId"], "name": s["name"], "short": s["short"], "logo": s["logo"],
             "leagueId": BOTOLA, "league": "Botola Pro", "national": False} for s in fetch_botola_standings()]


# --------------------------------------------------------------------------
# Scoreboards
# --------------------------------------------------------------------------

def fetch_scoreboard(league, date_text, ttl=None):
    if league == BOTOLA:
        return fetch_botola_matches(date_text, ttl=60 if date_text == datetime.now().strftime("%Y%m%d") else 600)
    data = fetch_json(f"{BASE}/{league}/scoreboard?dates={date_text}",
                      ttl=scoreboard_ttl(date_text) if ttl is None else ttl)
    if not data:
        return []
    league_info = (data.get("leagues") or [{}])[0]
    league_logo = logo_from(league_info)
    result = []
    for event in data.get("events", []) or []:
        match = normalize_event(event, league)
        if not match:
            continue
        match["leagueId"] = league
        match["league"] = LEAGUES.get(league) or league_info.get("name") or match["league"]
        match["leagueLogo"] = league_logo or match["leagueLogo"]
        result.append(match)
    return result


def date_range(start, days):
    return [(start + timedelta(days=offset)).strftime("%Y%m%d") for offset in range(days)]


def cmd_matches(leagues, date_text, favorite_ids):
    selected = [league for league in leagues if league] or ["esp.1", "eng.1", "uefa.champions"]
    dates = [date_text]
    if "-" in date_text:
        try:
            start_text, end_text = date_text.split("-", 1)
            start = datetime.strptime(start_text, "%Y%m%d").date()
            end = datetime.strptime(end_text, "%Y%m%d").date()
            dates = date_range(start, min(max((end - start).days, 0), 13) + 1)
        except ValueError:
            pass
    favs = {f for f in favorite_ids if f}
    batches = parallel(lambda item: fetch_scoreboard(*item), [(lg, d) for lg in selected for d in dates])
    output, seen = [], set()
    for batch in batches:
        for match in batch:
            if favs and not favs.intersection((match["homeId"], match["awayId"])):
                continue
            if match["id"] in seen:
                continue
            seen.add(match["id"])
            output.append(match)
    output.sort(key=lambda m: m.get("date") or "")
    print(json.dumps(output))


def cmd_league_matches(league, days=21):
    if not league:
        print("[]")
        return
    days = max(1, min(int(days), 45))
    now = datetime.now(timezone.utc)
    if league == BOTOLA:
        limit = now + timedelta(days=days)
        matches = [m for m in fetch_botola_matches()
                   if (d := parse_date(m["date"])) and now - timedelta(hours=3) <= d <= limit]
    else:
        today = datetime.now().date()
        batches = parallel(lambda d: fetch_scoreboard(league, d), date_range(today - timedelta(days=1), days + 1))
        matches, seen = [], set()
        for batch in batches:
            for m in batch:
                if m["id"] in seen:
                    continue
                d = parse_date(m["date"])
                if m["state"] == "post" and d and d < now - timedelta(hours=12):
                    continue
                seen.add(m["id"])
                matches.append(m)
    matches.sort(key=lambda m: m.get("date") or "")
    print(json.dumps(matches))


# --------------------------------------------------------------------------
# Teams: schedules, search
# --------------------------------------------------------------------------

def parse_team_specs(text):
    """'83:esp.1,2869:caf.nations_qual' -> [('83', 'esp.1'), ...]"""
    specs = []
    for part in (text or "").split(","):
        part = part.strip()
        if not part:
            continue
        team_id, _, league = part.partition(":")
        if re.fullmatch(r"[0-9]{1,9}", team_id):
            specs.append((team_id, league.strip()))
    return specs


def fetch_team_events(team_id, league, upcoming, ttl=600):
    """All competitions for one team, from ESPN's cross-competition feed."""
    if league == BOTOLA:
        return [m for m in fetch_botola_matches(ttl=ttl) if team_id in (m["homeId"], m["awayId"])]
    url = f"{BASE}/all/teams/{team_id}/schedule" + ("?fixture=true" if upcoming else "")
    data = fetch_json(url, ttl=ttl) or {}
    events = data.get("events") or []
    if isinstance(events, dict):
        events = events.get("items") or []
    out = []
    for event in events:
        match = normalize_event(event, league)
        if match and team_id in (match["homeId"], match["awayId"]):
            out.append(match)
    return out


def team_schedule(team_id, league, past=5, upcoming=10, ttl=600):
    fixtures, results = parallel(lambda up: fetch_team_events(team_id, league, up, ttl), [True, False], 2)
    now = datetime.now(timezone.utc)
    by_id = {}
    for match in fixtures + results:
        by_id.setdefault(match["id"], match)
    finished, ahead = [], []
    for match in by_id.values():
        date = parse_date(match["date"])
        if not date:
            continue
        match["_date"] = date
        if match["state"] == "post" or (match["state"] == "pre" and date < now - timedelta(hours=3)):
            if match["state"] == "post":
                finished.append(match)
        else:
            ahead.append(match)
    finished.sort(key=lambda m: m["_date"])
    ahead.sort(key=lambda m: m["_date"])
    return finished[-past:] if past else [], ahead[:upcoming]


def cmd_team_matches(specs_text, past=5, upcoming=10):
    specs = parse_team_specs(specs_text)
    if not specs:
        print("[]")
        return
    past, upcoming = max(0, min(int(past), 15)), max(0, min(int(upcoming), 20))
    results = parallel(lambda spec: team_schedule(spec[0], spec[1], past, upcoming), specs, 8)
    output, seen = [], set()
    for (team_id, _), (finished, ahead) in zip(specs, results):
        for group, items in (("result", finished), ("upcoming", ahead)):
            for match in items:
                if match["id"] in seen:
                    continue
                seen.add(match["id"])
                item = strip_internal(match)
                item["group"] = group
                item["teamId"] = team_id
                output.append(item)
    output.sort(key=lambda m: m.get("date") or "")
    print(json.dumps(output))


def search_espn_teams(query):
    params = urllib.parse.urlencode({"query": query, "limit": 25, "type": "team", "sport": "soccer"})
    data = fetch_json(f"{SEARCH_URL}?{params}", ttl=86400) or {}
    out = []
    for result in data.get("results") or []:
        for item in result.get("contents") or []:
            if item.get("sport") != "soccer" or item.get("type") != "team":
                continue
            uid = str(item.get("uid", ""))
            match = re.search(r"~t:(\d+)", uid)
            if not match:
                continue
            league = str(item.get("defaultLeagueSlug") or "")
            subtitle = str(item.get("subtitle") or "")
            name = str(item.get("displayName") or "")
            # Skip youth and women's teams unless they were asked for.
            lowered = (name + " " + subtitle + " " + league).lower()
            if re.search(r"\bu-?(1[5-9]|2[0-3])\b|women|\.w\.|wworld|femenina", lowered) and not re.search(r"u-?\d|women", query.lower()):
                continue
            image = item.get("image") or {}
            out.append({
                "id": match.group(1), "name": name, "short": name,
                "logo": image.get("defaultDark") or image.get("default") or "",
                "leagueId": league, "league": LEAGUES.get(league) or subtitle or display_league_name(league),
                "national": league in NATIONAL_COMPETITIONS or "soccer team" in subtitle.lower(),
            })
    return out


def cmd_search_teams(query):
    query = (query or "").strip()[:60]
    if len(query) < 2:
        print("[]")
        return
    espn, botola = parallel(lambda f: f(), [lambda: search_espn_teams(query), fetch_botola_teams], 2)
    needle = fold(query)
    found = [t for t in botola if needle in fold(t["name"] + " " + t["short"])]
    seen = {("b", t["id"]) for t in found}
    for team in espn:
        key = ("e", team["id"])
        if key not in seen:
            seen.add(key)
            found.append(team)
    print(json.dumps(found[:30]))


def fetch_teams(league, limit=200):
    if league == BOTOLA:
        return fetch_botola_teams()
    data = fetch_json(f"{BASE}/{league}/teams?limit={limit}", ttl=86400) or {}
    try:
        teams = data["sports"][0]["leagues"][0]["teams"]
    except (KeyError, IndexError, TypeError):
        return []
    out = []
    for item in teams:
        team = item.get("team", item)
        if team.get("id") and team.get("displayName"):
            out.append({"id": str(team["id"]), "name": team["displayName"],
                        "short": team.get("shortDisplayName") or team["displayName"],
                        "logo": logo_from(team), "leagueId": league, "league": display_league_name(league),
                        "national": league in NATIONAL_COMPETITIONS})
    return out


def cmd_teams(league):
    print(json.dumps(sorted(fetch_teams(league), key=lambda t: t["name"].casefold())))


def fold(text):
    text = unicodedata.normalize("NFD", str(text or ""))
    return "".join(c for c in text if unicodedata.category(c) != "Mn").casefold()


# --------------------------------------------------------------------------
# Standings
# --------------------------------------------------------------------------

def fetch_standings(league):
    if not league:
        return []
    if league == BOTOLA:
        return fetch_botola_standings()
    data = fetch_json(f"{STANDINGS_BASE}/{league}/standings", ttl=900) or {}
    groups = []
    children = data.get("children") or []
    if children:
        for child in children:
            name = child.get("name", "") if len(children) > 1 else ""
            groups.append((name, (child.get("standings") or {}).get("entries", []) or []))
    elif data.get("standings"):
        groups.append(("", data["standings"].get("entries", []) or []))
    output = []
    for group_name, entries in groups:
        for idx, entry in enumerate(entries):
            team = entry.get("team") or {}
            stats = {s.get("name"): s.get("displayValue", "") for s in entry.get("stats", []) if isinstance(s, dict)}
            note = entry.get("note") or {}
            name = team.get("displayName") or team.get("name") or "?"
            output.append({
                "rank": str(stats.get("rank") or idx + 1), "teamId": str(team.get("id", "")),
                "name": name, "short": team.get("shortDisplayName") or team.get("abbreviation") or name,
                "logo": logo_from(team), "group": group_name,
                "played": str(stats.get("gamesPlayed", "0")), "wins": str(stats.get("wins", "0")),
                "ties": str(stats.get("ties", "0")), "losses": str(stats.get("losses", "0")),
                "gf": str(stats.get("pointsFor", "0")), "ga": str(stats.get("pointsAgainst", "0")),
                "gd": str(stats.get("pointDifferential", "0")), "points": str(stats.get("points", "0")),
                "noteColor": hex_color(note.get("color")), "note": str(note.get("description") or "")[:60],
            })
    return output


def hex_color(value):
    text = str(value or "").lstrip("#")
    return "#" + text if re.fullmatch(r"[0-9A-Fa-f]{6}", text) else ""


def cmd_standings(league):
    print(json.dumps(fetch_standings(league)))


def cmd_leagues(limit):
    limit = max(1, min(int(limit), 500))
    data = fetch_json(f"{CORE_BASE}/leagues?limit={limit}&page=1", ttl=7 * 86400) or {}
    output = []
    for item in data.get("items", []) or []:
        ref = item.get("$ref", "")
        if "/leagues/" in ref:
            league_id = ref.split("/leagues/", 1)[1].split("?", 1)[0].strip("/")
            if league_id:
                output.append({"id": league_id, "name": display_league_name(league_id), "short": league_id, "region": "Other"})
    output.sort(key=lambda league: league["name"].lower())
    print(json.dumps(output))


# --------------------------------------------------------------------------
# Match details (stats, timeline, lineups on a pitch)
# --------------------------------------------------------------------------

def last_name(name):
    parts = str(name or "").split()
    if len(parts) <= 1:
        return str(name or "")
    if parts[-2].lower() in ("de", "van", "da", "di", "dos", "el", "ben", "al", "le", "von", "der"):
        return " ".join(parts[-2:])
    return parts[-1]


POSITION_DEPTH = [
    (r"^(G|GK)$", 0), (r"^(SW|CD|CB|CD-L|CD-R|LCB|RCB)$", 1), (r"^(LB|RB)$", 1.1), (r"^(LWB|RWB)$", 1.6),
    (r"^(DM|CDM|DM-L|DM-R|LDM|RDM)$", 2), (r"^(CM|CM-L|CM-R|LCM|RCM|M)$", 3), (r"^(LM|RM)$", 3.1),
    (r"^(AM|CAM|AM-L|AM-R|LAM|RAM)$", 4), (r"^(LW|RW|LF|RF)$", 4.5), (r"^(CF|ST|F|CF-L|CF-R|SS|LS|RS)$", 5),
    (r"^(D|DF)$", 1), (r"^(MF)$", 3), (r"^(FW)$", 5),
]


def position_depth(pos):
    pos = str(pos or "").upper()
    for pattern, depth in POSITION_DEPTH:
        if re.match(pattern, pos):
            return depth
    return 3


def position_lateral(pos):
    """Negative = player's left, positive = player's right."""
    pos = str(pos or "").upper()
    if pos in ("LB", "LWB", "LM", "LW", "LF"):
        return -2
    if pos in ("RB", "RWB", "RM", "RW", "RF"):
        return 2
    if pos.endswith("-L") or pos.startswith("L"):
        return -1
    if pos.endswith("-R") or pos.startswith("R"):
        return 1
    return 0


def build_rows(starters, formation):
    """Arrange starters into lines from goalkeeper to attack."""
    if not starters:
        return []
    keeper = [p for p in starters if position_depth(p.get("pos")) == 0][:1]
    outfield = [p for p in starters if p not in keeper]
    if not keeper and outfield:
        keeper, outfield = [outfield[0]], outfield[1:]
    try:
        lines = [int(x) for x in re.findall(r"\d+", formation or "")]
    except ValueError:
        lines = []
    if sum(lines) != len(outfield):
        lines = []
        groups = {}
        for p in outfield:
            groups.setdefault(round(position_depth(p.get("pos"))), []).append(p)
        rows = [keeper] + [groups[k] for k in sorted(groups)]
    else:
        ordered = sorted(enumerate(outfield), key=lambda ip: (position_depth(ip[1].get("pos")), ip[0]))
        ordered = [p for _, p in ordered]
        rows, index = [keeper], 0
        for count in lines:
            rows.append(ordered[index:index + count])
            index += count
    for row in rows:
        row.sort(key=lambda p: position_lateral(p.get("pos")))
    return [row for row in rows if row]


def annotate_players(players, events, side):
    names = {}
    for event in events:
        if event.get("side") != side:
            continue
        for key, badge in (("player", event["type"]),):
            names.setdefault(fold(event.get(key, "")), []).append(badge)
        if event["type"] == "substitution" and event.get("assist"):
            names.setdefault(fold(event["assist"]), []).append("sub-off")
    for player in players:
        badges = names.get(fold(player.get("name", "")), [])
        player["goals"] = badges.count("goal")
        player["yellow"] = 1 if "yellow-card" in badges else 0
        player["red"] = 1 if "red-card" in badges else 0
        player["subbedOff"] = player.get("subbedOff") or ("sub-off" in badges)


def empty_lineup():
    return {"available": False, "source": "", "homeFormation": "", "awayFormation": "", "homeCoach": "",
            "awayCoach": "", "homeStarters": [], "awayStarters": [], "homeBench": [], "awayBench": [],
            "homeRows": [], "awayRows": []}


def finish_lineup(lineup, events):
    if not lineup or not lineup.get("available"):
        return empty_lineup()
    for side in ("home", "away"):
        annotate_players(lineup[side + "Starters"], events, side)
        annotate_players(lineup[side + "Bench"], events, side)
        lineup[side + "Rows"] = build_rows(list(lineup[side + "Starters"]), lineup[side + "Formation"])
    return lineup


def parse_espn_lineups(rosters, home_id, away_id):
    if not isinstance(rosters, list):
        return None
    home = next((r for r in rosters if str((r.get("team") or {}).get("id")) == home_id), {})
    away = next((r for r in rosters if str((r.get("team") or {}).get("id")) == away_id), {})

    def players(roster, starter):
        out = []
        for p in roster.get("roster", []) or []:
            if bool(p.get("starter")) != starter:
                continue
            name = (p.get("athlete") or {}).get("displayName", "")
            out.append({"name": name, "short": last_name(name), "number": str(p.get("jersey", "")),
                        "pos": (p.get("position") or {}).get("abbreviation", ""),
                        "subbedOff": bool(p.get("subbedOut")), "subbedOn": bool(p.get("subbedIn"))})
        return out

    hs, as_ = players(home, True), players(away, True)
    if len(hs) < 11 or len(as_) < 11:
        return None
    return {"available": True, "source": "espn",
            "homeFormation": home.get("formation") or "", "awayFormation": away.get("formation") or "",
            "homeCoach": "", "awayCoach": "", "homeStarters": hs, "awayStarters": as_,
            "homeBench": players(home, False), "awayBench": players(away, False)}


def parse_fotmob_lineup(lineup):
    if not isinstance(lineup, dict):
        return None
    kind = str(lineup.get("lineupType") or "").lower()
    if kind in ("laststarting11", "predicted"):
        return None
    pos_map = {0: "GK", 1: "DF", 2: "MF", 3: "FW"}

    def side(team):
        def conv(p):
            name = p.get("name", "")
            return {"name": name, "short": last_name(name), "number": str(p.get("shirtNumber", "")),
                    "pos": pos_map.get(p.get("usualPlayingPositionId"), "MF"), "subbedOff": False, "subbedOn": False}
        coach = team.get("coach")
        return (team.get("formation", ""), [conv(p) for p in team.get("starters", []) or []],
                [conv(p) for p in team.get("subs", []) or []],
                coach.get("name", "") if isinstance(coach, dict) else str(coach or ""))

    hf, hs, hb, hc = side(lineup.get("homeTeam") or {})
    af, as_, ab, ac = side(lineup.get("awayTeam") or {})
    if not hs or not as_:
        return None
    return {"available": True, "source": "fotmob", "homeFormation": hf, "awayFormation": af,
            "homeCoach": hc, "awayCoach": ac, "homeStarters": hs, "awayStarters": as_,
            "homeBench": hb, "awayBench": ab}


def fotmob_match_for(date_text, home_name, away_name):
    if not date_text:
        return None
    data = fetch_json(f"{FOTMOB}/matches?date={date_text.replace('-', '')[:8]}", ttl=600, headers=FOTMOB_HEADERS) or {}

    def norm(s):
        return re.sub(r"[^a-z0-9]", "", fold(s).replace("fc", "").replace("cf", ""))

    h, a = norm(home_name), norm(away_name)
    if not h or not a:
        return None
    for lg in data.get("leagues", []) or []:
        for m in lg.get("matches", []) or []:
            mh, ma = norm((m.get("home") or {}).get("name", "")), norm((m.get("away") or {}).get("name", ""))
            if mh and ma and (h in mh or mh in h) and (a in ma or ma in a):
                return m.get("id")
    return None


def fetch_espn_match_details(league, match_id):
    data = fetch_json(f"{BASE}/{league}/summary?event={match_id}", ttl=15)
    if not data:
        return None
    header = data.get("header") or {}
    comp = (header.get("competitions") or [{}])[0]
    competitors = comp.get("competitors", [])
    home_c = next((c for c in competitors if c.get("homeAway") == "home"), {})
    away_c = next((c for c in competitors if c.get("homeAway") == "away"), {})
    home_id, away_id = str(home_c.get("id", "")), str(away_c.get("id", ""))
    home_team, away_team = home_c.get("team") or {}, away_c.get("team") or {}
    status = comp.get("status") or {}
    status_type = status.get("type") or {}
    state = status_type.get("state", "pre")

    teams = (data.get("boxscore") or {}).get("teams", [])
    hstats = {s.get("name"): s.get("displayValue") for s in next((t for t in teams if str((t.get("team") or {}).get("id")) == home_id), {}).get("statistics", [])}
    astats = {s.get("name"): s.get("displayValue") for s in next((t for t in teams if str((t.get("team") or {}).get("id")) == away_id), {}).get("statistics", [])}
    stat_defs = [("possessionPct", "Possession", "%"), ("totalShots", "Shots", ""), ("shotsOnTarget", "Shots on target", ""),
                 ("wonCorners", "Corners", ""), ("totalPasses", "Passes", ""), ("passPct", "Pass accuracy", ""),
                 ("foulsCommitted", "Fouls", ""), ("offsides", "Offsides", ""), ("yellowCards", "Yellow cards", ""),
                 ("redCards", "Red cards", ""), ("saves", "Saves", "")]
    stats = []
    for key, label, unit in stat_defs:
        if key not in hstats and key not in astats:
            continue
        hr, ar = str(hstats.get(key) or "0"), str(astats.get(key) or "0")
        if key == "passPct":
            hr, ar = pct_text(hr), pct_text(ar)
            unit = ""
        stats.append(stat_row(label, hr + unit, ar + unit))

    events = []
    for ev in data.get("keyEvents", []) or []:
        type_info = ev.get("type") or {}
        t_type, t_text = str(type_info.get("type", "")).lower(), str(type_info.get("text", ""))
        is_goal = bool(ev.get("scoringPlay")) or "goal" in t_type
        is_card = "card" in t_type or "card" in t_text.lower()
        is_sub = "substitution" in t_type or "substitution" in t_text.lower()
        if not (is_goal or is_card or is_sub):
            continue
        team_id = str((ev.get("team") or {}).get("id", ""))
        side = "home" if team_id == home_id else ("away" if team_id == away_id else "neutral")
        parts = ev.get("participants", []) or []
        names = [(p.get("athlete") or {}).get("displayName", "") for p in parts]
        player, assist = (names[0] if names else ""), ""
        text = str(ev.get("text", ""))
        if is_sub:
            replaced = re.search(r"(?:\.|^)\s*([^.]+?) replaces ([^.]+?)(?:\s+because[^.]*)?\.", text)
            if replaced:
                player, assist = replaced.group(1).strip(), replaced.group(2).strip()
            elif len(names) > 1:
                assist = names[1]
            kind = "substitution"
        elif is_goal:
            assist = names[1] if len(names) > 1 else ""
            kind = "goal"
            if "own" in t_type or "own goal" in text.lower():
                t_text = "Own goal"
            elif "penalty" in t_type or "penalty" in text.lower():
                t_text = "Penalty"
        else:
            kind = "red-card" if "red" in t_type or "red" in t_text.lower() else "yellow-card"
        events.append({"clock": (ev.get("clock") or {}).get("displayValue", ""), "type": kind, "typeLabel": t_text,
                       "player": player or ev.get("shortText", ""), "assist": assist, "side": side})

    date_text = comp.get("date") or ""
    lineup = parse_espn_lineups(data.get("rosters"), home_id, away_id)
    if not lineup:
        start = parse_date(date_text)
        if state != "pre" or (start and start - datetime.now(timezone.utc) <= timedelta(hours=2)):
            fm_id = fotmob_match_for(date_text[:10], home_team.get("displayName", ""), away_team.get("displayName", ""))
            if fm_id:
                fm = fetch_json(f"{FOTMOB}/matchDetails?matchId={fm_id}", ttl=60, headers=FOTMOB_HEADERS) or {}
                lineup = parse_fotmob_lineup((fm.get("content") or {}).get("lineup"))
    lineup = finish_lineup(lineup, events)

    game_info = data.get("gameInfo") or {}
    attendance = game_info.get("attendance")
    detail = clean_detail(state, status_type)
    if status_type.get("name") == "STATUS_HALFTIME":
        detail = "HT"
    return {
        "id": str(match_id), "leagueId": league,
        "leagueName": LEAGUES.get(league) or (header.get("league") or {}).get("name") or display_league_name(league),
        "round": event_round(header, comp), "date": date_text, "state": state, "detail": detail,
        "home": home_team.get("shortDisplayName") or home_team.get("displayName") or "Home",
        "away": away_team.get("shortDisplayName") or away_team.get("displayName") or "Away",
        "homeId": home_id, "awayId": away_id,
        "homeLogo": logo_from(home_team), "awayLogo": logo_from(away_team),
        "homeScore": score_text(home_c.get("score")) if state != "pre" else "",
        "awayScore": score_text(away_c.get("score")) if state != "pre" else "",
        "venue": (game_info.get("venue") or {}).get("fullName", ""),
        "attendance": str(attendance) if attendance else "",
        "stats": stats, "events": events, "lineup": lineup,
    }


def pct_text(value):
    try:
        number = float(str(value).replace("%", ""))
    except ValueError:
        return str(value)
    if number <= 1:
        number *= 100
    return f"{round(number)}%"


def stat_row(label, home, away):
    def num(text):
        try:
            return float(str(text).split()[0].replace("%", ""))
        except (ValueError, IndexError):
            return None
    hv, av = num(home), num(away)
    if hv is None or av is None or hv + av <= 0:
        hp = 50
    else:
        hp = round(hv / (hv + av) * 100)
    return {"name": label, "home": str(home), "away": str(away), "homePct": hp, "awayPct": 100 - hp}


def fetch_fotmob_match_details(match_id):
    data = fetch_json(f"{FOTMOB}/matchDetails?matchId={match_id}", ttl=20, headers=FOTMOB_HEADERS) or {}
    if not data:
        return None
    general, header = data.get("general") or {}, data.get("header") or {}
    teams = header.get("teams") or [{}, {}]
    home_t, away_t = (teams + [{}, {}])[:2]
    status = header.get("status") or {}
    content = data.get("content") or {}
    periods = (((content.get("stats") or {}).get("Periods") or {}).get("All") or {}).get("stats") or []
    raw = [s for g in periods if g.get("title") in ("Top stats", "Discipline") for s in g.get("stats", [])]
    stats = []
    for s in raw:
        vals = s.get("stats") or []
        if len(vals) == 2 and None not in vals:
            stats.append(stat_row(s.get("title", ""), vals[0], vals[1]))
    events = []
    for ev in ((content.get("matchFacts") or {}).get("events") or {}).get("events") or []:
        kind = str(ev.get("type") or "").lower()
        side = "away" if ev.get("isAway") else "home"
        clock = str(ev.get("timeStr") or ev.get("time") or "")
        if clock and not clock.endswith("'"):
            clock += "'"
        if kind == "goal":
            events.append({"clock": clock, "type": "goal", "typeLabel": "Goal",
                           "player": (ev.get("player") or {}).get("name", ""), "assist": ev.get("assistStr", "") or "", "side": side})
        elif kind == "card":
            red = "red" in str(ev.get("card") or "").lower()
            events.append({"clock": clock, "type": "red-card" if red else "yellow-card", "typeLabel": "Red card" if red else "Yellow card",
                           "player": (ev.get("player") or {}).get("name", ""), "assist": "", "side": side})
        elif kind == "substitution":
            swap = ev.get("swap") or []
            on = swap[0].get("name", "") if len(swap) > 0 and isinstance(swap[0], dict) else ""
            off = swap[1].get("name", "") if len(swap) > 1 and isinstance(swap[1], dict) else ""
            events.append({"clock": clock, "type": "substitution", "typeLabel": "Substitution",
                           "player": on, "assist": off, "side": side})
    finished, started = status.get("finished", False), status.get("started", False)
    state = "post" if finished else ("in" if started else "pre")
    date_text = status.get("utcTime") or general.get("matchTimeUTC") or ""
    start = parse_date(date_text)
    lineup = None
    if state != "pre" or (start and start - datetime.now(timezone.utc) <= timedelta(hours=2)):
        lineup = parse_fotmob_lineup(content.get("lineup"))
    lineup = finish_lineup(lineup, events)
    stage = str(general.get("tournamentStage") or "").strip()
    h_id, a_id = home_t.get("id"), away_t.get("id")
    return {
        "id": str(match_id), "leagueId": BOTOLA, "leagueName": "Botola Pro",
        "round": f"Round {stage}" if stage.isdigit() else stage, "date": date_text, "state": state,
        "detail": (status.get("reason") or {}).get("short", "") or ("FT" if finished else ("LIVE" if started else "Scheduled")),
        "home": home_t.get("name", "Home"), "away": away_t.get("name", "Away"),
        "homeId": str(h_id or ""), "awayId": str(a_id or ""),
        "homeLogo": fotmob_logo(h_id), "awayLogo": fotmob_logo(a_id),
        "homeScore": str(home_t.get("score", "")) if state != "pre" else "",
        "awayScore": str(away_t.get("score", "")) if state != "pre" else "",
        "venue": (general.get("venue") or {}).get("name", "") if isinstance(general.get("venue"), dict) else "",
        "attendance": "", "stats": stats, "events": events, "lineup": lineup,
    }


def cmd_match_details(league, match_id):
    if not re.fullmatch(r"[0-9]{1,12}", str(match_id or "")):
        print("{}")
        return
    if league == BOTOLA:
        result = fetch_fotmob_match_details(match_id)
    else:
        result = fetch_espn_match_details(league or "all", match_id)
    print(json.dumps(result or {}))


# --------------------------------------------------------------------------
# Live pulse: favourite teams' next/live match + real-time notifications
# --------------------------------------------------------------------------

def load_state():
    try:
        with open(STATE_FILE, "r", encoding="utf-8") as handle:
            state = json.load(handle)
            if isinstance(state, dict):
                return state
    except (OSError, ValueError):
        pass
    return {}


def save_state(state):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=CACHE_DIR, suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(state, handle)
        os.replace(tmp, STATE_FILE)
    except OSError:
        pass


def cached_logo(url):
    """Download a team logo once for use as a notification icon."""
    if not url or not url.startswith("https://"):
        return ""
    path = os.path.join(LOGO_CACHE, hashlib.sha1(url.encode()).hexdigest() + ".png")
    if os.path.exists(path):
        return path
    try:
        os.makedirs(LOGO_CACHE, exist_ok=True)
        fetch_url = url
        if "a.espncdn.com/i/" in url:
            fetch_url = "https://a.espncdn.com/combiner/i?img=" + urllib.parse.quote(url.split("a.espncdn.com", 1)[1]) + "&w=96&h=96"
        request = urllib.request.Request(fetch_url, headers={"User-Agent": HEADERS["User-Agent"]})
        with urllib.request.urlopen(request, timeout=3) as response:
            raw = response.read(512 * 1024)
        if not raw.startswith(b"\x89PNG"):
            return ""
        with open(path, "wb") as handle:
            handle.write(raw)
        return path
    except (OSError, ValueError, urllib.error.URLError):
        return ""


PLUGIN_ICON = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "football-icon.png")


def notify(title, body, urgency="normal", icon=""):
    # Omarchy's toast shows the image-path hint as the picture; a file path
    # given as the app icon (-i) is ignored there and falls back to a letter.
    # Use the team crest when there is one, otherwise the plugin icon.
    image = icon if icon and os.path.exists(icon) else PLUGIN_ICON
    command = ["notify-send", "-a", "Football", "-u", urgency]
    if os.path.exists(image):
        command += ["-h", "string:image-path:" + image]
    command += ["--", title[:120], body[:300]]
    try:
        subprocess.run(command, timeout=5, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        pass


def score_line(match):
    return f"{match['home']} {match['homeScore'] or 0}–{match['awayScore'] or 0} {match['away']}"


def int_or_zero(value):
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return 0


def cmd_pulse(specs_text, leagues_text, options_text):
    """Return each favourite team's live/next match and send notifications.

    options: {"alerts": bool, "reminders": bool, "reminderMinutes": int,
              "leagueMode": "off"|"goals"|"all", "dry": bool}
    """
    try:
        options = json.loads(options_text or "{}")
        if not isinstance(options, dict):
            options = {}
    except ValueError:
        options = {}
    alerts = options.get("alerts", True) is not False
    reminders = options.get("reminders", True) is not False
    reminder_minutes = max(1, min(int_or_zero(options.get("reminderMinutes")) or 15, 180))
    league_mode = options.get("leagueMode", "goals")
    dry = bool(options.get("dry"))

    specs = parse_team_specs(specs_text)
    fav_ids = {team_id for team_id, _ in specs}
    leagues = [lg for lg in (leagues_text or "").split(",") if re.fullmatch(r"[a-z0-9._]{2,40}", lg)]
    now = datetime.now(timezone.utc)
    today = datetime.now().strftime("%Y%m%d")
    yesterday = (datetime.now() - timedelta(days=1)).strftime("%Y%m%d")

    schedules = parallel(lambda spec: team_schedule(spec[0], spec[1], past=1, upcoming=3, ttl=900), specs, 8)

    # Scoreboards that need live accuracy: followed leagues (today, plus
    # yesterday for late kick-offs) and the competitions of any favourite
    # team match close to kick-off or in play.
    boards = set()
    if league_mode != "off" and alerts:
        for lg in leagues:
            boards.add((lg, today))
            if datetime.now().hour < 4:
                boards.add((lg, yesterday))
    for finished, ahead in schedules:
        for match in finished[-1:] + ahead[:2]:
            date = match.get("_date")
            if date and now - timedelta(hours=3) <= date <= now + timedelta(hours=2):
                boards.add((match["leagueId"] or "all", date.astimezone().strftime("%Y%m%d")))
    board_results = parallel(lambda item: (item, fetch_scoreboard(item[0], item[1], ttl=15)), sorted(boards))
    live_by_id = {}
    for (league, _), matches in board_results:
        for match in matches:
            live_by_id[match["id"]] = match

    teams_out = {}
    next_kickoff = None
    any_live = False
    for (team_id, league), (finished, ahead) in zip(specs, schedules):
        candidates = [live_by_id.get(m["id"], m) for m in (finished[-1:] + ahead)]
        chosen = None
        for match in candidates:
            date = parse_date(match["date"])
            if match["state"] == "in":
                chosen = match
                break
            if match["state"] == "post" and date and now - date < timedelta(hours=2, minutes=30):
                chosen = match  # just finished: keep showing the result for a while
                break
        if not chosen:
            chosen = next((m for m in candidates if m["state"] == "pre"), None)
        if chosen:
            any_live = any_live or chosen["state"] == "in"
            if chosen["state"] == "pre":
                date = parse_date(chosen["date"])
                if date and (next_kickoff is None or date < next_kickoff):
                    next_kickoff = date
            item = strip_internal(chosen)
            item["teamId"] = team_id
            item["isHome"] = item["homeId"] == team_id
            item["opponent"] = item["away"] if item["isHome"] else item["home"]
            teams_out[team_id] = item

    # ----- notifications -----
    state = load_state()
    seen = state.get("matches", {})
    reminded = state.get("reminded", [])
    first_run = not state
    sent = []

    def emit(title, body, urgency, logo=""):
        sent.append({"title": title, "body": body})
        if not dry:
            notify(title, body, urgency, cached_logo(logo) if logo else "")

    tracked = dict(live_by_id)
    for item in teams_out.values():
        tracked.setdefault(item["id"], item)

    if alerts:
        for match_id, match in tracked.items():
            is_fav = bool(fav_ids.intersection((match["homeId"], match["awayId"])))
            in_league = match["leagueId"] in leagues
            if not is_fav and (league_mode == "off" or not in_league):
                continue
            urgency = "normal" if is_fav else "low"
            prev = seen.get(match_id)
            hs, as_ = int_or_zero(match["homeScore"]), int_or_zero(match["awayScore"])
            date = parse_date(match["date"])

            if is_fav and reminders and match["state"] == "pre" and date and match_id not in reminded:
                minutes = (date - now).total_seconds() / 60
                if 0 <= minutes <= reminder_minutes + 0.5:
                    emit(f"⏰ {match['home']} vs {match['away']}",
                         f"Kick-off in {max(1, round(minutes))} min · {match['league']}", "normal",
                         match["homeLogo"] if match["homeId"] in fav_ids else match["awayLogo"])
                    reminded.append(match_id)

            if prev is not None and not first_run:
                ps, ph, pa = prev.get("s"), int_or_zero(prev.get("h")), int_or_zero(prev.get("a"))
                want_all = is_fav or league_mode == "all"
                if ps == "pre" and match["state"] == "in" and want_all:
                    emit(f"▶ Kick-off: {match['home']} vs {match['away']}", match["league"], urgency)
                if match["state"] in ("in", "post") and (hs > ph or as_ > pa):
                    scorers = [g for g in match.get("goals", []) if g.get("player")]
                    scorer = scorers[-1] if scorers else None
                    side = "home" if hs > ph else "away"
                    team_name = match["home"] if side == "home" else match["away"]
                    who = f" · {scorer['player']} {scorer['clock']}".rstrip() if scorer and scorer.get("side") == side else ""
                    emit(f"⚽ GOAL! {team_name}", f"{score_line(match)}{who}\n{match['league']}", urgency,
                         match["homeLogo"] if side == "home" else match["awayLogo"])
                elif match["state"] == "in" and (hs < ph or as_ < pa):
                    emit("❌ Goal disallowed", f"{score_line(match)} · {match['league']}", urgency)
                if is_fav and len(match.get("redCards", [])) > int_or_zero(prev.get("r")):
                    card = match["redCards"][-1]
                    team_name = match["home"] if card.get("side") == "home" else match["away"]
                    emit(f"🟥 Red card · {team_name}", f"{card.get('player', '')} {card.get('clock', '')}\n{score_line(match)}", urgency)
                if want_all and match.get("statusName") == "STATUS_HALFTIME" and prev.get("n") != "STATUS_HALFTIME":
                    emit(f"⏸ Half-time", score_line(match), "low")
                if ps == "in" and match["state"] == "post":
                    emit(f"🏁 Full-time", f"{score_line(match)}\n{match['league']}", urgency)
            seen[match_id] = {"s": match["state"], "h": hs, "a": as_, "r": len(match.get("redCards", [])),
                              "n": match.get("statusName", ""), "t": int(time.time())}

    cutoff = time.time() - 3 * 86400
    state = {"matches": {k: v for k, v in seen.items() if v.get("t", 0) > cutoff}, "reminded": reminded[-60:]}
    save_state(state)

    # Poll fast while anything we follow is live or about to start.
    league_live = any(m["state"] == "in" and m["leagueId"] in leagues for m in live_by_id.values()) and league_mode != "off"
    if any_live or league_live:
        next_poll = 30
    elif next_kickoff is not None:
        until = (next_kickoff - now).total_seconds() - reminder_minutes * 60
        next_poll = int(max(30, min(300, until)))
    else:
        next_poll = 300
    if league_mode != "off" and any(m["state"] == "pre" and (d := parse_date(m["date"])) and 0 <= (d - now).total_seconds() < 600
                                    for m in live_by_id.values()):
        next_poll = min(next_poll, 60)
    if FAILURES:
        next_poll = min(next_poll, 45)
    print(json.dumps({"teams": teams_out, "nextPoll": next_poll, "notified": sent, "failed": len(FAILURES)}))


# --------------------------------------------------------------------------

def main():
    args = sys.argv[1:]
    if not args:
        print(json.dumps({"error": "No command specified"}))
        return
    command, rest = args[0], args[1:]

    def arg(index, default=""):
        return rest[index] if len(rest) > index else default

    if command == "matches":
        cmd_matches(arg(0).split(","), arg(1, datetime.now().strftime("%Y%m%d")), arg(2).split(","))
    elif command == "league-matches":
        cmd_league_matches(arg(0), arg(1, 21))
    elif command == "team-matches":
        cmd_team_matches(arg(0), arg(1, 5), arg(2, 10))
    elif command == "pulse":
        cmd_pulse(arg(0), arg(1), arg(2, "{}"))
    elif command == "standings":
        cmd_standings(arg(0, "esp.1"))
    elif command == "match-details":
        cmd_match_details(arg(0), arg(1))
    elif command == "search-teams":
        cmd_search_teams(" ".join(rest))
    elif command == "teams":
        cmd_teams(arg(0))
    elif command == "leagues":
        cmd_leagues(arg(0, 300))
    else:
        print(json.dumps({"error": "Unknown command: " + command}))


if __name__ == "__main__":
    main()
