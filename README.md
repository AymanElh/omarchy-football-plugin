# Football Matches

A native Omarchy bar widget for following selected football competitions and one favourite team. The bar shows that team's upcoming opponent and local kickoff time; clicking opens the fixture list and settings.

## Features

- Default competitions: La Liga, Premier League, Ligue 1, Bundesliga, UEFA Champions League, and CAF Champions League.
- One favourite team, with its next match shown in the bar.
- Match list for the selected local calendar day, with live scores/status when supplied by the data source.
- Date navigation, team search, favourite-match highlighting, and optional desktop reminders.

Kickoff timestamps are formatted in the computer's local timezone. The popup and favourite-team schedule refresh every two minutes. Match requests use only the selected competitions; the favourite-team lookup uses its competition plus the selected competitions. CAF Champions League is requested with ESPN's `caf.champions` identifier; availability may vary, so verify it on your system.

## Files and technologies

| File | Purpose |
| --- | --- |
| `manifest.json` | Plugin identity, defaults, and bar-widget entry point. |
| `BarWidget.qml` | The bar button and popup host, written in QML. |
| `Panel.qml` | Popup interface, settings, and backend process orchestration, written in QML. |
| `Model.js` | League definitions and local date/time formatting in JavaScript. |
| `api.py` | Python 3 standard-library client for ESPN soccer JSON endpoints. |

QML runs inside Qt Quick/Quickshell. The UI launches `api.py` through Quickshell's process support, reads JSON from stdout, and updates the bar/panel. No third-party Python packages are needed. ESPN's site API is not a documented public API and can change.

## Install and enable

Place this directory at `~/.config/omarchy/plugins/ayman.football/`, then run:

```sh
omarchy-shell shell rescanPlugins
omarchy plugin enable ayman.football right
```

Open **Football** in the bar, select competitions, and search for your favourite team. `notify-send` and a desktop notification service are needed for reminders.

## Before community publication

Validate the manifest with `omarchy plugin validate ~/.config/omarchy/plugins/ayman.football`. Confirm the plugin loads on a clean supported Omarchy release; check competition coverage, empty/offline data, long names, local time display, and notifications; then add a license and follow the community repository's submission requirements.
