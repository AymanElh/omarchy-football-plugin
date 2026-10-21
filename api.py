#!/usr/bin/env python3
"""Small ESPN soccer-data client used by the Football bar widget."""
import concurrent.futures
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

BASE = "https://site.api.espn.com/apis/site/v2/sports/soccer"
HEADERS = {"User-Agent": "AymanFootballWidget/1.0 (Linux)"}
LEAGUES = {
    "esp.1": "La Liga", "eng.1": "Premier League", "fra.1": "Ligue 1",
    "ger.1": "Bundesliga", "ita.1": "Serie A", "uefa.champions": "UEFA Champions League",
    "caf.champions": "CAF Champions League", "uefa.europa": "Europa League",
    "uefa.europa.conf": "Conference League", "esp.copa_del_rey": "Copa del Rey",
    "eng.fa": "FA Cup", "ita.coppa_italia": "Coppa Italia", "ger.dfb_pokal": "DFB-Pokal",
}
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


def fetch_team_next(league, team_id):
    data = fetch_json(f"{BASE}/{league}/teams/{team_id}")
    if not data or not data.get("team"):
        return []
    return data["team"].get("nextEvent") or []


def cmd_next(team_id, primary_league, selected_leagues):
    if not team_id:
        print("null")
        return
    leagues = []
    for league in [primary_league, *selected_leagues]:
        if league and league not in leagues:
            leagues.append(league)
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
                "league": event.get("league", {}).get("name") or LEAGUES.get(league, league),
                "leagueId": league, "venue": competition.get("venue", {}).get("fullName", ""),
            }))
            if event_id:
                seen.add(event_id)
    candidates.sort(key=lambda item: item[0])
    print(json.dumps(candidates[0][1] if candidates else None))


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
            "league": event.get("league", {}).get("name") or LEAGUES.get(league, league),
            "date": event.get("date") or competition.get("date"),
            "state": status.get("state", "pre"),
            "detail": status.get("shortDetail") or status.get("detail") or "",
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
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, len(selected))) as pool:
        futures = [pool.submit(fetch_scoreboard, league, date_text) for league in selected]
        results = [future.result() for future in futures]
    output, seen = [], set()
    for batch in results:
        for match in batch:
            match_id = match["id"]
            if match_id in seen:
                continue
            seen.add(match_id)
            output.append(match)
    output.sort(key=lambda match: match.get("date") or "")
    print(json.dumps(output))


def fetch_teams(league):
    data = fetch_json(f"{BASE}/{league}/teams?limit=100")
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
                           "leagueId": league, "league": LEAGUES.get(league, league)})
    return output


def cmd_teams(leagues):
    selected = [league for league in leagues if league] or ["esp.1", "eng.1", "uefa.champions"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, len(selected))) as pool:
        batches = list(pool.map(fetch_teams, selected))
    by_id = {}
    for batch in batches:
        for team in batch:
            by_id.setdefault(team["id"], team)
    print(json.dumps(sorted(by_id.values(), key=lambda team: team["name"].lower())))


def main():
    args = sys.argv[1:]
    if not args:
        print(json.dumps({"error": "No command specified"}))
        return
    command = args[0]
    if command == "next":
        team_id = args[1] if len(args) > 1 else ""
        primary = args[2] if len(args) > 2 else "esp.1"
        selected = args[3].split(",") if len(args) > 3 else []
        cmd_next(team_id, primary, selected)
    elif command == "matches":
        leagues = args[1].split(",") if len(args) > 1 else []
        date_text = args[2] if len(args) > 2 else datetime.now().strftime("%Y%m%d")
        favorite_id = args[3] if len(args) > 3 else ""
        cmd_matches(leagues, date_text, favorite_id)
    elif command == "teams":
        cmd_teams(args[1].split(",") if len(args) > 1 else [])
    else:
        print(json.dumps({"error": "Unknown command: " + command}))


if __name__ == "__main__":
    main()
