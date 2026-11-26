# Football Matches

A native Omarchy status-bar widget for live football scores, fixtures, tables and real-time alerts for the teams you follow.

Your teams' next kick-off or live score sits in the bar (e.g. `● Barcelona 2-1 Villarreal 63'`). Click it to open a match browser with a match centre that shows the timeline, stats and lineups drawn on a pitch.

---

## Features

* **Follow several teams:** clubs and national teams, as many as you like. The bar shows whichever plays next, and a live match always takes priority.
* **Every competition a team plays in:** league, domestic cups, continental cups, friendlies and national-team qualifiers (for example Morocco in AFCON Qualifying) all come from one cross-competition schedule.
* **Five tabs:**
  * **Matches:** step through days with the ‹ › arrows (or ← → keys), click the date for a calendar, and filter to *Live*. Games are grouped by competition, with live games first.
  * **Week:** the next 7 days across your competitions.
  * **My teams:** upcoming fixtures and recent results (with W/D/L), for all followed teams or one at a time.
  * **Fixtures:** every remaining scheduled match of a competition up to the end of the season, 10 match days at a time with *Show more*.
  * **Table:** standings with qualification and relegation zones, and your teams highlighted.
* **Match centre:** score and scorers, a goals/cards/substitutions timeline, statistics, and **lineups on a pitch** with formation, shirt numbers, goals, cards and substitutions, plus a **TV** tab with where to watch by region (your region first, guessed from the system timezone; the USA row comes live from ESPN, the others are the usual rights holders for that competition).
* **55 curated competitions:** grouped into Europe, Africa (Botola Pro, AFCON and its qualifiers, CAF Champions League, CAF Confederation Cup…), Asia, the Americas and international tournaments. Other ESPN competitions are found by searching.
* **Real-time alerts:** kick-off, goals (with scorer), disallowed goals, red cards, half-time and full-time for your teams, plus kick-off reminders. Notifications show the team crest (or a football glyph in your theme colours). Alerts for other matches in your competitions are optional. The widget polls every 30 seconds while a followed match is live, and every few minutes otherwise.
* **Fast:** every response is cached on disk for a short time, other tabs are prefetched in the background, and team schedules take 2 requests instead of a 35-day scoreboard scan, and fixtures read the season calendar instead of scanning day by day.
* **No dependencies:** QML plus Python 3's standard library.

---

## Installation

### Option 1: Via the Omarchy CLI (Recommended)

```sh
omarchy plugin add https://github.com/AymanElh/omarchy-football-plugin.git --enable right
```

### Option 2: Manual Installation

```sh
git clone https://github.com/AymanElh/omarchy-football-plugin.git ~/.config/omarchy/plugins/ayman.football-matches
omarchy-shell shell rescanPlugins
omarchy plugin enable ayman.football-matches right
```

---

## How to Use

| Action | Result |
| :--- | :--- |
| **Left click** | Open / close the panel |
| **Middle click** | Refresh now |
| **Esc** | Back (from settings or the match centre), then close |

**First-time setup:** open the panel and click the gear icon. Follow teams from the popular list or search for any team, pick your competitions, and choose your alert settings.

---

## Configuration & Defaults

Settings are saved in Omarchy's settings store (`~/.config/omarchy/shell.json`):

| Key | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `selectedLeagues` | `array` | `["esp.1", "eng.1", "uefa.champions", "caf.champions", "caf.nations_qual", "mar.1"]` | Competitions used by the Matches, Week, Fixtures and Table tabs. |
| `favoriteTeams` | `array` | `[]` | Followed teams (`id`, `name`, `short`, `logo`, `leagueId`, `national`). A v1 `favoriteTeam` is migrated automatically. |
| `alertsEnabled` | `boolean` | `true` | Background polling and desktop notifications. |
| `remindersEnabled` | `boolean` | `true` | Kick-off reminders for followed teams. |
| `reminderMinutes` | `number` | `15` | Minutes before kick-off for the reminder. |
| `leagueAlertMode` | `string` | `"goals"` | Alerts for non-followed matches in your competitions: `off`, `goals` (goals & results) or `all`. |

---

## Privacy & network

* Data comes from fixed HTTPS endpoints: ESPN's public soccer API (scores, schedules, standings, search, match details) and FotMob (Botola Pro, plus lineups ESPN lacks).
* While alerts are enabled, the widget checks for score changes in the background, even when the panel is closed. Turn **Desktop notifications** off in settings to stop it.
* Cached responses and alert state are kept in `~/.cache/ayman-football/`. Nothing is sent about you: requests carry only team, league and match IDs.
* Everything downloaded is treated as untrusted: responses are capped at 6 MB (compressed and decompressed), each request has a 10 s end-to-end limit and each command a hard 25 s limit (45 s for the alert check), the number of requests, collection sizes, text lengths and the printed output (2 MB) are capped, all text is drawn as plain text, notification text has markup neutralised, and only HTTPS crests are downloaded. If a helper process still hangs, the shell kills it and carries on.
* TV information: the USA row comes live from ESPN's match data; the other regions are the usual rights holders for each competition, kept in `api.py` (`TV_BY_LEAGUE`). They can miss one-off deals, so check local listings.

---

## Requirements

* **Omarchy Linux** (Quickshell / Qt Quick)
* **Python 3** (standard library only)
* **`notify-send`** (libnotify, installed on Omarchy by default)

---

## Architecture

* `BarWidget.qml`: the bar pill; it loads the panel.
* `Panel.qml`: the panel UI and its state, with an in-memory cache that renders the last answer instantly while a refresh runs.
* `MatchCard.qml`, `PitchView.qml`, `Chip.qml`, `TeamLogo.qml`, `PText.qml`: UI components. All network text is rendered as plain text.
* `Fetcher.qml`: a request queue around `api.py`; only the newest pending request runs, a child that runs too long is killed, and a child that exits without answering never leaves the queue busy.
* `Model.js`: the competition catalogue, popular teams and formatting helpers.
* `tests/test_api.py`: regression tests for the data client (markup-shaped names, download limits).
* `api.py`: the data client and disk cache. Its `pulse` command computes each team's live or next match and sends notifications by comparing scores against `~/.cache/ayman-football/alerts-state.json`.

---

## Development

```sh
omarchy plugin validate .                 # manifest check
python3 -m unittest discover -s tests -v  # regression tests
omarchy restart shell                     # QML changes need a shell restart to reload
```

The panel's text is English only for now; strings are not yet in `i18n/` catalogs.

---

## License

This project is licensed under the [MIT License](LICENSE).
