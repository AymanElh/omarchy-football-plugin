# Football Matches

A native Omarchy bar widget for following selected football competitions and one favourite team. The bar shows that team's upcoming opponent and local kickoff time; clicking opens the fixture list and settings.

## Features

- Twenty popular competitions are shown first, sorted by popularity. Search matches competition names against ESPN's capped catalog; selecting a competition loads its teams for the favourite-team picker. Searches that return no match show an explicit not-found message.
- One favourite team, with its next match shown in the bar.
- Match scopes for one selected day (with a direct calendar picker) or the next seven days, with each upcoming fixture showing its local date and kickoff time.
- A dedicated favourite-team schedule with the next ten fixtures, filled from the team's schedule and upcoming league scoreboards when needed.
- A league schedule view for configured competitions, showing the next 30 days of fixtures and round information when ESPN provides it.
- The favourite-team picker shows popular clubs first; name search can look across popular leagues, MLS, and Morocco's Botola Pro, with explicit not-found feedback.
- Favourite-match highlighting and optional desktop reminders.

Kickoff timestamps are formatted in the computer's local timezone. The bar's next-match summary refreshes every two minutes. Day schedules refresh every two minutes while the popup is open; the seven-day and favourite-team schedules refresh when opened or manually refreshed. Team search first filters loaded teams and searches the popular club-league catalog only when there are no matches. Reminders are one-time desktop notifications before the favourite team's next match (15 minutes by default). ESPN's competition coverage can vary by season.

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

Validate the manifest with `omarchy plugin validate ~/.config/omarchy/plugins/ayman.football`. Confirm the plugin loads on a clean supported Omarchy release; check competition coverage, empty/offline data, long names, local time display, round availability, and notifications; then add a license and follow the community repository's submission requirements.
