# Football Matches

A native Omarchy status-bar widget for tracking live soccer scores, fixture schedules, and your favourite team.

Pin your team's next kickoff or live score directly to your top bar (e.g. `Barça vs Real Madrid · LIVE 2-1`), and click to open a full match browser with calendar navigation, multi-league filtering, and desktop reminders.

---

## Features

* **Status Bar Integration:** Shows your favourite club's next upcoming match or live score directly in the Omarchy bar.
* **4 Match Browsing Modes:**
  * **By Day:** View all matches for any date, with a built-in calendar picker and daily chevrons.
  * **Next 7 Days:** See the upcoming week of fixtures across all your selected leagues.
  * **By Team:** Track your favourite club's next 10 fixtures across all competitions (domestic league, domestic cups, and continental tournaments like UEFA Champions League or CAF Champions League).
  * **By League:** Browse 30 days of upcoming fixtures for any single selected competition, including round numbers.
* **Smart Team & League Search:**
  * Search across dozens of domestic leagues and tournaments (La Liga, Premier League, Bundesliga, Serie A, Ligue 1, Botola Pro, MLS, and more).
  * Fast team search with popular club priority and aliases (e.g. searching `barca`, `real`, `wac`, or `raja`).
* **Match Reminders:** Sends a desktop notification via `notify-send` before your favourite team kicks off (customizable, defaults to 15 minutes).
* **Local Timezone Aware:** All match times automatically convert to your local system time.
* **Zero External Dependencies:** Built with QML and Python 3 standard library only — no `pip` packages required.

---

## Installation

### Option 1: Via the Omarchy CLI (Recommended)

```sh
omarchy plugin add https://github.com/AymanElh/omarchy-football-plugin.git --enable right
```

### Option 2: Manual Installation

1. Clone or copy the repository into your Omarchy plugins directory:
   ```sh
   git clone https://github.com/AymanElh/omarchy-football-plugin.git ~/.config/omarchy/plugins/ayman.football-matches
   ```

2. Reload plugins and enable the widget:
   ```sh
   omarchy-shell shell rescanPlugins
   omarchy plugin enable ayman.football-matches right
   ```

---

## How to Use

### Mouse Controls

| Action | Result |
| :--- | :--- |
| **Left Click** | Open / close the match panel |
| **Middle Click** | Force an immediate data refresh |

### First-Time Setup
1. Click the **Football** widget in your bar to open the popup.
2. Click the **Gear icon (⚙)** in the top right to open settings.
3. Select your favourite leagues (or search for competitions).
4. Search for your **Favourite team** and click it to pin it to your bar.
5. (Optional) Toggle **Match reminders** and choose how many minutes before kickoff you'd like a desktop notification.

---

## Configuration & Defaults

Settings are saved automatically through Omarchy's settings store (`~/.config/omarchy/shell.json`):

| Setting Key | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `selectedLeagues` | `array` | `["esp.1", "eng.1", "fra.1", "ger.1", "uefa.champions", "caf.champions"]` | Leagues displayed in matchday views. |
| `favoriteTeam` | `object` | `null` | The chosen club shown on the bar pill (`id`, `name`, `short`, `leagueId`). |
| `remindersEnabled` | `boolean` | `true` | Send a desktop notification before your favourite team plays. |
| `reminderMinutes` | `number` | `15` | Minutes before kickoff to trigger the reminder notification. |

---

## Requirements

* **Omarchy Linux** (with Quickshell / Qt Quick)
* **Python 3** (standard library only)
* **`libnotify` / `notify-send`** (installed by default on Omarchy for desktop reminders)

---

## Architecture & Data Source

* **UI Layer:** Written in QML (`BarWidget.qml`, `Panel.qml`) running in Quickshell, following Omarchy design system styles and tokens.
* **Data Layer:** `api.py` fetches match scoreboards and team calendars asynchronously from ESPN's public soccer endpoints using Python's standard `urllib` and `concurrent.futures`. No background daemon or web server needed.

---

## License

This project is licensed under the [MIT License](LICENSE).
