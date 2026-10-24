#!/usr/bin/env python3
"""Small ESPN soccer-data client used by the Football bar widget."""
import concurrent.futures
import json
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

BASE = "https://site.api.espn.com/apis/site/v2/sports/soccer"
CORE_BASE = "https://sports.core.api.espn.com/v2/sports/soccer"
HEADERS = {"User-Agent": "AymanFootballWidget/1.0 (Linux)"}
LEAGUES = {
    "esp.1": "La Liga", "eng.1": "Premier League", "fra.1": "Ligue 1",
    "ger.1": "Bundesliga", "ita.1": "Serie A", "uefa.champions": "UEFA Champions League",
    "caf.champions": "CAF Champions League", "uefa.europa": "Europa League",
    "uefa.europa.conf": "Conference League", "esp.copa_del_rey": "Copa del Rey",
    "eng.fa": "FA Cup", "ita.coppa_italia": "Coppa Italia", "ger.dfb_pokal": "DFB-Pokal",
    "fifa.world": "FIFA World Cup", "uefa.nations": "UEFA Nations League",
    "uefa.euro": "UEFA European Championship", "caf.nations": "Africa Cup of Nations",
    "afc.asian.cup": "AFC Asian Cup", "conmebol.america": "Copa América", "mar.1": "Botola Pro",
    "por.1": "Primeira Liga (Portugal)", "ned.1": "Eredivisie (Netherlands)",
    "tur.1": "Turkish Süper Lig", "esp.copa_del_rey": "Copa del Rey",
    "esp.super_cup": "Spanish Super Cup", "uefa.super_cup": "UEFA Super Cup",
    "fifa.cwc": "FIFA Club World Cup", "eng.fa": "FA Cup",
    "eng.league_cup": "EFL Cup", "ita.coppa_italia": "Coppa Italia",
    "ger.dfb_pokal": "DFB-Pokal", "fra.coupe_de_france": "Coupe de France",
    "ned.cup": "KNVB Cup", "por.cup": "Taça de Portugal", "tur.cup": "Turkish Cup",
    "usa.1": "Major League Soccer", "mex.1": "Liga MX", "arg.1": "Argentine Primera División",
    "bra.1": "Brasileirão", "sco.1": "Scottish Premiership", "bel.1": "Belgian Pro League",
    "ksa.1": "Saudi Pro League", "conmebol.libertadores": "Copa Libertadores",
    "conmebol.sudamericana": "Copa Sudamericana", "afc.champions": "AFC Champions League",
}
TEAM_SEARCH_LEAGUES = [
    "esp.1", "eng.1", "ita.1", "fra.1", "ger.1", "uefa.champions",
    "uefa.europa", "caf.champions", "mar.1", "usa.1",
]
TEAM_ALIASES = {
    "barca": ("barcelona",), "barça": ("barcelona",),
    "real": ("real madrid",),
    "wac": ("wydad",), "wydad": ("wac",),
    "raja": ("raja casablanca",), "inter miami": ("inter miami",),
}
TEAM_COMPETITIONS = {
    "esp.1": ["esp.copa_del_rey", "esp.super_cup", "uefa.champions", "uefa.europa", "uefa.europa.conf", "fifa.cwc"],
    "eng.1": ["eng.fa", "eng.league_cup", "uefa.champions", "uefa.europa", "uefa.europa.conf", "fifa.cwc"],
    "ita.1": ["ita.coppa_italia", "uefa.champions", "uefa.europa", "uefa.europa.conf", "fifa.cwc"],
    "ger.1": ["ger.dfb_pokal", "uefa.champions", "uefa.europa", "uefa.europa.conf", "fifa.cwc"],
    "fra.1": ["fra.coupe_de_france", "uefa.champions", "uefa.europa", "uefa.europa.conf", "fifa.cwc"],
    "por.1": ["por.cup", "uefa.champions", "uefa.europa", "uefa.europa.conf", "fifa.cwc"],
    "ned.1": ["ned.cup", "uefa.champions", "uefa.europa", "uefa.europa.conf", "fifa.cwc"],
    "tur.1": ["tur.cup", "uefa.champions", "uefa.europa", "uefa.europa.conf", "fifa.cwc"],
    "mar.1": ["caf.champions"],
    "usa.1": ["fifa.cwc"],
}


def display_league_name(league):
    return LEAGUES.get(league, league.replace(".", " ").replace("_", " ").title())


def cmd_leagues(limit):
    # ESPN's catalog can be large; cap it and only fetch when the user searches.
    limit = max(1, min(int(limit), 200))
    data = fetch_json(f"{CORE_BASE}/leagues?limit={limit}&page=1")
    output = []
    for item in (data or {}).get("items", []):
        ref = item.get("$ref", "")
        marker = "/leagues/"
        if marker not in ref:
            continue
        league_id = ref.split(marker, 1)[1].split("?", 1)[0].strip("/")
        if league_id:
            output.append({"id": league_id, "name": display_league_name(league_id), "short": league_id})
    output.sort(key=lambda league: league["name"].lower())
    print(json.dumps(output))
def fetch_json(url):
    request = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            return json.loads(response.read().decode("utf-8"))
    except (OSError, ValueError, urllib.error.URLError):
        return None


def event_parts(event):
    competitions = event.get("competitions") or [{}]
    competition = competitions[0] if competitions else {}
    return competition, competition.get("competitors", []), competition.get("status", {}).get("type", {})


def competitors_for(competitors):
    home = next((c for c in competitors if c.get("homeAway") == "home"), {})
    away = next((c for c in competitors if c.get("homeAway") == "away"), {})
    return home, away, home.get("team", {}), away.get("team", {})


def event_round(event, competition=None):
    """Read round/matchday metadata when ESPN includes it for a fixture."""
    competition = competition or {}
    for source in (event, competition):
        for key in ("round", "matchday", "week"):
            value = source.get(key)
            if isinstance(value, dict):
                label = value.get("displayValue") or value.get("text") or value.get("name")
                if label:
                    return str(label)
                number = value.get("number") or value.get("value")
                if number is not None:
                    return f"Round {number}"
            elif value is not None:
                return f"Round {value}"
        notes = source.get("notes", [])
        if isinstance(notes, list):
            for note in notes:
                if not isinstance(note, dict):
                    continue
                label = str(note.get("headline") or note.get("text") or "").strip()
                if label and re.search(r"\b(round|match\s*day|week)\b|\b(final|semi[- ]final|quarter[- ]final|last\s+\d+)\b", label, re.I):
                    return label
    return ""


def fetch_team_next(league, team_id):
    data = fetch_json(f"{BASE}/{league}/teams/{team_id}")
    if not data or not data.get("team"):
        return []
    return data["team"].get("nextEvent") or []


def cmd_next(team_id, primary_league, selected_leagues):
    if not team_id:
        print("null")
        return
    leagues = related_team_leagues(primary_league, selected_leagues)
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, len(leagues))) as pool:
        batches = list(pool.map(lambda league: (league, fetch_team_next(league, team_id)), leagues))

    now = datetime.now(timezone.utc)
    candidates = []
    seen = set()
    for league, events in batches:
        for event in events:
            event_id = str(event.get("id", ""))
            if event_id and event_id in seen:
                continue
            competition, competitors, status = event_parts(event)
            date_text = event.get("date") or competition.get("date")
            if not date_text:
                continue
            try:
                date = datetime.fromisoformat(date_text.replace("Z", "+00:00"))
                if date.tzinfo is None:
                    date = date.replace(tzinfo=timezone.utc)
            except ValueError:
                continue
            state = status.get("state", "pre")
            if state == "post" and date < now - timedelta(hours=3):
                continue
            if date < now - timedelta(hours=3) and state != "in":
                continue
            home, away, home_team, away_team = competitors_for(competitors)
            home_id, away_id = str(home_team.get("id", "")), str(away_team.get("id", ""))
            if str(team_id) not in (home_id, away_id):
                continue
            opponent = away_team if home_id == str(team_id) else home_team
            opponent_name = opponent.get("shortDisplayName") or opponent.get("displayName") or "Opponent"
            candidates.append((date, {
                "id": event_id, "date": date_text, "state": state,
                "detail": status.get("shortDetail") or status.get("detail") or "Scheduled",
                "opponent": opponent_name,
                "homeName": home_team.get("shortDisplayName") or home_team.get("displayName") or "Home",
                "awayName": away_team.get("shortDisplayName") or away_team.get("displayName") or "Away",
                "homeScore": home.get("score", ""), "awayScore": away.get("score", ""),
                "league": event.get("league", {}).get("name") or display_league_name(league),
                "leagueId": league, "venue": competition.get("venue", {}).get("fullName", ""),
                "round": event_round(event, competition),
            }))
            if event_id:
                seen.add(event_id)
    candidates.sort(key=lambda item: item[0])
    print(json.dumps(candidates[0][1] if candidates else None))


def fetch_team_schedule(league, team_id):
    data = fetch_json(f"{BASE}/{league}/teams/{team_id}/schedule")
    events = (data or {}).get("events", [])
    if isinstance(events, dict):
        events = events.get("items") or events.get("next") or events.get("events") or []
    return league, events if isinstance(events, list) else []


def related_team_leagues(primary_league, selected_leagues):
    # A team may have been selected from a continental competition (for
    # example, Barcelona from the Champions League), so its saved primary
    # league is not necessarily its domestic league. Include selected domestic
    # leagues and their cups/continental competitions when searching the team's
    # schedule. Only domestic leagues have an entry in TEAM_COMPETITIONS; this
    # avoids querying every selected cup as a separate source.
    domestic_leagues = [league for league in selected_leagues if league in TEAM_COMPETITIONS]
    seeds = [primary_league, *domestic_leagues]
    related = []
    for league in seeds:
        if league:
            related.extend([league, *TEAM_COMPETITIONS.get(league, [])])
    return list(dict.fromkeys(league for league in related if league))


def domestic_first(leagues):
    """Prefer a club's domestic league when the same team appears in cups."""
    unique = list(dict.fromkeys(league for league in leagues if league))
    return ([league for league in unique if league in TEAM_COMPETITIONS]
            + [league for league in unique if league not in TEAM_COMPETITIONS])


def cmd_team_matches(team_id, primary_league, selected_leagues, limit=10):
    if not team_id:
        print("[]")
        return
    leagues = related_team_leagues(primary_league, selected_leagues)
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, len(leagues))) as pool:
        schedules = list(pool.map(lambda league: fetch_team_schedule(league, team_id), leagues))
    now = datetime.now(timezone.utc)
    candidates, seen = [], set()
    max_results = max(1, min(int(limit), 10))

    def collect(league, events):
        for event in events:
            if not isinstance(event, dict):
                continue
            event_id = str(event.get("id", ""))
            if event_id and event_id in seen:
                continue
            normalized = "homeId" in event and "awayId" in event
            competition, competitors, status = ({}, [], {}) if normalized else event_parts(event)
            date_text = event.get("date") or competition.get("date")
            if not date_text:
                continue
            try:
                date = datetime.fromisoformat(date_text.replace("Z", "+00:00"))
                if date.tzinfo is None:
                    date = date.replace(tzinfo=timezone.utc)
            except ValueError:
                continue
            state = event.get("state", "pre") if normalized else status.get("state", "pre")
            if state == "post" or (date < now and state != "in"):
                continue
            if normalized:
                home_id, away_id = str(event.get("homeId", "")), str(event.get("awayId", ""))
                home_name, away_name = event.get("home", "?"), event.get("away", "?")
                home_score, away_score = event.get("homeScore", ""), event.get("awayScore", "")
            else:
                home, away, home_team, away_team = competitors_for(competitors)
                home_id, away_id = str(home_team.get("id", "")), str(away_team.get("id", ""))
                home_name = home_team.get("shortDisplayName") or home_team.get("displayName") or "?"
                away_name = away_team.get("shortDisplayName") or away_team.get("displayName") or "?"
                home_score, away_score = home.get("score", ""), away.get("score", "")
            if str(team_id) not in (home_id, away_id):
                continue
            candidates.append((date, {
                "id": event_id, "leagueId": league,
                "league": (event.get("league", {}).get("name") if isinstance(event.get("league"), dict) else event.get("league")) or display_league_name(league),
                "date": date_text, "state": state,
                "detail": event.get("detail") or status.get("shortDetail") or status.get("detail") or "Scheduled",
                "round": event.get("round") or event_round(event, competition),
                "homeId": home_id, "awayId": away_id,
                "home": home_name, "away": away_name,
                "homeScore": home_score, "awayScore": away_score,
            }))
            if event_id:
                seen.add(event_id)

    for league, events in schedules:
        collect(league, events)

    # Team schedule feeds can contain only played fixtures. Fill from future
    # scoreboards a week at a time and stop when ten upcoming team games exist.
    if len(candidates) < max_results:
        relevant = leagues
        today = datetime.now().date()
        for offset in range(0, 120, 7):
            dates = [(today + timedelta(days=offset + day)).strftime("%Y%m%d") for day in range(7)]
            requests = [(league, date) for league in relevant for date in dates]
            with concurrent.futures.ThreadPoolExecutor(max_workers=min(12, len(requests))) as pool:
                batches = list(pool.map(lambda item: fetch_scoreboard(*item), requests))
            for (league, _), events in zip(requests, batches):
                collect(league, events)
            if len(candidates) >= max_results:
                break
    candidates.sort(key=lambda item: item[0])
    print(json.dumps([match for _, match in candidates[:max_results]]))


def fetch_scoreboard(league, date_text):
    data = fetch_json(f"{BASE}/{league}/scoreboard?dates={date_text}")
    if not data:
        return []
    result = []
    for event in data.get("events", []):
        competition, competitors, status = event_parts(event)
        home, away, home_team, away_team = competitors_for(competitors)
        result.append({
            "id": str(event.get("id", "")), "leagueId": league,
            "league": event.get("league", {}).get("name") or display_league_name(league),
            "date": event.get("date") or competition.get("date"),
            "state": status.get("state", "pre"),
            "detail": status.get("shortDetail") or status.get("detail") or "",
            "round": event_round(event, competition),
            "homeId": str(home_team.get("id", "")), "awayId": str(away_team.get("id", "")),
            "home": home_team.get("shortDisplayName") or home_team.get("displayName") or "?",
            "away": away_team.get("shortDisplayName") or away_team.get("displayName") or "?",
            "homeScore": home.get("score", ""), "awayScore": away.get("score", ""),
        })
    return result


def cmd_matches(leagues, date_text, favorite_id):
    selected = [league for league in leagues if league]
    if not selected:
        selected = ["esp.1", "eng.1", "uefa.champions"]
    dates = [date_text]
    if "-" in date_text:
        try:
            start_text, end_text = date_text.split("-", 1)
            start = datetime.strptime(start_text, "%Y%m%d").date()
            end = datetime.strptime(end_text, "%Y%m%d").date()
            day_count = min(max((end - start).days, 0), 13)
            dates = [(start + timedelta(days=offset)).strftime("%Y%m%d") for offset in range(day_count + 1)]
        except ValueError:
            dates = [date_text]
    requests = [(league, date) for league in selected for date in dates]
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(12, len(requests))) as pool:
        futures = [pool.submit(fetch_scoreboard, league, date) for league, date in requests]
        results = [future.result() for future in futures]
    output, seen = [], set()
    for batch in results:
        for match in batch:
            if favorite_id and str(favorite_id) not in (match["homeId"], match["awayId"]):
                continue
            match_id = match["id"]
            if match_id in seen:
                continue
            seen.add(match_id)
            output.append(match)
    output.sort(key=lambda match: match.get("date") or "")
    print(json.dumps(output))


def cmd_league_matches(league, days=30):
    """Return this league's scheduled fixtures over the next month."""
    if not league:
        print("[]")
        return
    days = max(1, min(int(days), 60))
    today = datetime.now().date()
    dates = [(today + timedelta(days=offset)).strftime("%Y%m%d") for offset in range(days)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(12, len(dates))) as pool:
        batches = list(pool.map(lambda date: fetch_scoreboard(league, date), dates))
    output, seen = [], set()
    for batch in batches:
        for match in batch:
            if match["id"] and match["id"] in seen:
                continue
            if match["id"]:
                seen.add(match["id"])
            output.append(match)
    output.sort(key=lambda match: match.get("date") or "")
    print(json.dumps(output))


def fetch_teams(league, limit=100):
    data = fetch_json(f"{BASE}/{league}/teams?limit={limit}")
    if not data:
        return []
    sports = data.get("sports", [])
    if not sports:
        return []
    leagues = sports[0].get("leagues", [])
    if not leagues:
        return []
    output = []
    for item in leagues[0].get("teams", []):
        team = item.get("team", item)
        team_id, name = str(team.get("id", "")), team.get("displayName")
        if team_id and name:
            output.append({"id": team_id, "name": name,
                           "short": team.get("shortDisplayName") or name,
                           "leagueId": league, "league": display_league_name(league)})
    return output


def cmd_teams(leagues):
    selected = [league for league in leagues if league] or ["esp.1", "eng.1", "uefa.champions"]
    selected = domestic_first(selected)
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, len(selected))) as pool:
        batches = list(pool.map(fetch_teams, selected))
    by_id = {}
    for batch in batches:
        for team in batch:
            by_id.setdefault(team["id"], team)
    print(json.dumps(sorted(by_id.values(), key=lambda team: team["name"].lower())))


def cmd_search_teams(leagues, query):
    selected = domestic_first([*leagues, *TEAM_SEARCH_LEAGUES])
    if not selected or not query:
        print("[]")
        return
    needle = query.strip().casefold()
    aliases = TEAM_ALIASES.get(needle, ())
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, len(selected))) as pool:
        batches = list(pool.map(lambda league: fetch_teams(league, 1000), selected))
    by_id = {}
    for batch in batches:
        for team in batch:
            searchable = (team["name"] + " " + team["short"]).casefold()
            if needle in searchable or any(alias in searchable for alias in aliases):
                by_id.setdefault(team["id"], team)
    print(json.dumps(sorted(by_id.values(), key=lambda team: team["name"].casefold())))


def main():
    args = sys.argv[1:]
    if not args:
        print(json.dumps({"error": "No command specified"}))
        return
    command = args[0]
    if command == "leagues":
        cmd_leagues(args[1] if len(args) > 1 else 200)
    elif command == "next":
        team_id = args[1] if len(args) > 1 else ""
        primary = args[2] if len(args) > 2 else "esp.1"
        selected = args[3].split(",") if len(args) > 3 else []
        cmd_next(team_id, primary, selected)
    elif command == "team-matches":
        team_id = args[1] if len(args) > 1 else ""
        primary = args[2] if len(args) > 2 else "esp.1"
        selected = args[3].split(",") if len(args) > 3 else []
        cmd_team_matches(team_id, primary, selected, args[4] if len(args) > 4 else 10)
    elif command == "matches":
        leagues = args[1].split(",") if len(args) > 1 else []
        date_text = args[2] if len(args) > 2 else datetime.now().strftime("%Y%m%d")
        favorite_id = args[3] if len(args) > 3 else ""
        cmd_matches(leagues, date_text, favorite_id)
    elif command == "league-matches":
        league = args[1] if len(args) > 1 else ""
        cmd_league_matches(league, args[2] if len(args) > 2 else 30)
    elif command == "teams":
        cmd_teams(args[1].split(",") if len(args) > 1 else [])
    elif command == "search-teams":
        leagues = args[1].split(",") if len(args) > 1 else []
        query = " ".join(args[2:]) if len(args) > 2 else ""
        cmd_search_teams(leagues, query)
    else:
        print(json.dumps({"error": "Unknown command: " + command}))


if __name__ == "__main__":
    main()
