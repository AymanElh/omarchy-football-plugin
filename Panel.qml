import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "ayman.football"
  ipcTarget: "ayman.football"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property string scriptPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/ayman.football/api.py"

  property var selectedLeagues: Model.selectedValues(setting("selectedLeagues", Model.defaultSelected()))
  property var favoriteTeam: setting("favoriteTeam", null)
  property bool remindersEnabled: setting("remindersEnabled", true) === true
  property int reminderMinutes: Math.max(5, Number(setting("reminderMinutes", 15)))
  property date selectedDate: new Date()
  property var matches: []
  property var availableTeams: []
  property var nextMatch: null
  property string label: Model.formatBarLabel(nextMatch, favoriteTeam)
  property bool showingSettings: false
  property string teamSearchFilter: ""
  property bool isLoadingMatches: false
  property bool isLoadingTeams: false
  property bool isLoadingNextMatch: false
  property string matchesError: ""
  readonly property bool opened: root.controller.open

  function openFromHotkey() { open() }
  function open() {
    root.controller.open = true
    refreshAll()
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }
  function close() { root.controller.open = false; showingSettings = false }
  function toggle() { opened ? close() : open() }
  function closeForPopoutSwitch() { close() }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function persistSettings(extra) {
    var entry = { id: moduleName, selectedLeagues: selectedLeagues, favoriteTeam: favoriteTeam,
                  remindersEnabled: remindersEnabled, reminderMinutes: reminderMinutes }
    if (extra) for (var k in extra) entry[k] = extra[k]
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
  }
  function refreshAll() { fetchNextMatch(); fetchMatches(); if (showingSettings || availableTeams.length === 0) fetchTeams() }
  function toggleLeague(id) {
    var next = []
    for (var i = 0; i < selectedLeagues.length; i++) if (selectedLeagues[i] !== id) next.push(selectedLeagues[i])
    if (next.length === selectedLeagues.length) next.push(id)
    if (next.length === 0) next = [id]
    selectedLeagues = next
    persistSettings(); fetchTeams(); fetchMatches(); fetchNextMatch()
  }
  function isLeagueSelected(id) { return selectedLeagues.indexOf(id) >= 0 }
  function selectFavoriteTeam(team) {
    if (favoriteTeam && String(favoriteTeam.id) === String(team.id)) favoriteTeam = null
    else favoriteTeam = { id: String(team.id), name: team.name, short: team.short || team.name,
                         leagueId: team.leagueId || selectedLeagues[0] || "esp.1" }
    persistSettings(); fetchNextMatch(); fetchMatches()
  }
  function clearFavoriteTeam() { favoriteTeam = null; nextMatch = null; persistSettings(); updateLabel() }
  function fetchNextMatch() {
    if (!favoriteTeam || !favoriteTeam.id) { nextMatch = null; updateLabel(); return }
    if (nextProc.running) return
    isLoadingNextMatch = true
    nextProc.command = ["python3", scriptPath, "next", String(favoriteTeam.id),
                        favoriteTeam.leagueId || "esp.1", selectedLeagues.join(",")]
    nextProc.running = true
  }
  function onNextMatchFinished(raw) {
    isLoadingNextMatch = false
    try { var data = JSON.parse(raw); nextMatch = data && data.opponent ? data : null }
    catch (e) { nextMatch = null }
    updateLabel(); checkReminder()
  }
  function updateLabel() { label = Model.formatBarLabel(nextMatch, favoriteTeam) }
  function fetchMatches() {
    if (matchesProc.running) return
    isLoadingMatches = true; matchesError = ""
    matchesProc.command = ["python3", scriptPath, "matches", selectedLeagues.join(","),
                          Model.formatDateParam(selectedDate), favoriteTeam && favoriteTeam.id ? String(favoriteTeam.id) : ""]
    matchesProc.running = true
  }
  function onMatchesFinished(raw) {
    isLoadingMatches = false
    try { var data = JSON.parse(raw); matches = Array.isArray(data) ? data : [] }
    catch (e) { matches = []; matchesError = "Could not read match data" }
  }
  function fetchTeams() {
    if (teamsProc.running) return
    isLoadingTeams = true
    teamsProc.command = ["python3", scriptPath, "teams", selectedLeagues.join(",")]
    teamsProc.running = true
  }
  function onTeamsFinished(raw) {
    isLoadingTeams = false
    try { var data = JSON.parse(raw); availableTeams = Array.isArray(data) ? data : [] }
    catch (e) { availableTeams = [] }
  }
  function changeDay(amount) {
    var d = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate())
    d.setDate(d.getDate() + amount); selectedDate = d; fetchMatches()
  }
  function goToToday() { selectedDate = new Date(); fetchMatches() }
  function isTodaySelected() {
    var now = new Date()
    return selectedDate.getFullYear() === now.getFullYear() && selectedDate.getMonth() === now.getMonth() && selectedDate.getDate() === now.getDate()
  }
  function isFavTeamMatch(match) {
    if (!favoriteTeam) return false
    return String(match.homeId) === String(favoriteTeam.id) || String(match.awayId) === String(favoriteTeam.id)
  }
  function checkReminder() {
    if (!remindersEnabled || !nextMatch || reminderProc.running) return
    var minutes = (new Date(nextMatch.date).getTime() - Date.now()) / 60000
    if (minutes < 0 || minutes > reminderMinutes + 1) return
    var notified = setting("notifiedMatchIds", [])
    if (notified.indexOf(nextMatch.id) >= 0) return
    reminderProc.command = ["notify-send", "-u", "normal", "-a", "Football", "Match reminder",
      favoriteTeam.name + " vs " + nextMatch.opponent + " starts in " + Math.max(1, Math.ceil(minutes)) + " minutes"]
    reminderProc.running = true
    persistSettings({ notifiedMatchIds: notified.concat([nextMatch.id]).slice(-20) })
  }

  Process { id: nextProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onNextMatchFinished(String(text || "").trim()) }
  }
  Process { id: matchesProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onMatchesFinished(String(text || "").trim()) }
  }
  Process { id: teamsProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onTeamsFinished(String(text || "").trim()) }
  }
  Process { id: reminderProc }
  Timer {
    interval: 120000; running: true; repeat: true
    onTriggered: { root.fetchNextMatch(); if (root.opened) root.fetchMatches() }
  }
  Timer { interval: 60000; running: true; repeat: true; onTriggered: { root.updateLabel(); root.checkReminder() } }
  Component.onCompleted: { fetchNextMatch(); fetchMatches(); fetchTeams() }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    centerOnBar: false
    contentWidth: popup.fittedContentWidth(Style.space(520))
    contentHeight: popup.fittedContentHeight(mainColumn.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }
        Column {
          id: mainColumn
          width: parent.width
          spacing: Style.space(12)
          Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
              width: parent.width - settingsButton.width - refreshButton.width - Style.space(24)
              text: root.showingSettings ? "Football settings" : "Football"
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
            Button { id: settingsButton; text: root.showingSettings ? "Matches" : "Settings"; bordered: true
              onClicked: { root.showingSettings = !root.showingSettings; if (root.showingSettings) root.fetchTeams() } }
            Button { id: refreshButton; text: "↻"; bordered: true; onClicked: root.refreshAll() }
          }

          Column {
            visible: !root.showingSettings
            width: parent.width
            spacing: Style.space(10)
            Rectangle {
              width: parent.width
              implicitHeight: favColumn.implicitHeight + Style.space(18)
              radius: Style.cornerRadius
              color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.10)
              border.color: Commons.Color.accent
              border.width: 1
              Column {
                id: favColumn
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(5)
                Text {
                  width: parent.width
                  text: root.favoriteTeam ? root.favoriteTeam.name + " · Next match" : "Choose a favourite team in Settings"
                  color: Commons.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true
                }
                Text {
                  width: parent.width
                  visible: root.nextMatch !== null
                  text: root.nextMatch ? root.nextMatch.homeName + " vs " + root.nextMatch.awayName : ""
                  color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.heading; font.bold: true
                }
                Text {
                  width: parent.width
                  visible: root.nextMatch !== null
                  text: root.nextMatch ? root.nextMatch.league + " · " + Model.formatDayLabel(new Date(root.nextMatch.date)) + " at " + Model.formatMatchTime(root.nextMatch.date) : ""
                  color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
                }
                Text {
                  width: parent.width
                  visible: root.favoriteTeam !== null && root.nextMatch === null
                  text: root.isLoadingNextMatch ? "Looking up the next match…" : "No upcoming match was returned by the schedule."
                  color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
                }
              }
            }
            Row {
              width: parent.width
              spacing: Style.space(8)
              Button { text: "◀"; bordered: true; onClicked: root.changeDay(-1) }
              Text { width: parent.width - 120; text: Model.formatDayLabel(root.selectedDate); color: Commons.Color.foreground
                font.family: Style.font.family; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
              Button { text: "▶"; bordered: true; onClicked: root.changeDay(1) }
              Button { visible: !root.isTodaySelected(); text: "Today"; bordered: true; onClicked: root.goToToday() }
            }
            Text { visible: root.isLoadingMatches; text: "Loading matches…"; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body }
            Text {
              visible: !root.isLoadingMatches && root.matches.length === 0
              text: root.matchesError || "No matches found for this day in the selected leagues."
              color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body
            }
            Repeater {
              model: root.matches
              delegate: Rectangle {
                required property var modelData
                readonly property bool favourite: root.isFavTeamMatch(modelData)
                width: mainColumn.width
                implicitHeight: matchColumn.implicitHeight + Style.space(16)
                radius: Style.cornerRadius
                color: favourite ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.10) : Qt.rgba(1, 1, 1, 0.03)
                border.width: favourite ? 2 : 1
                border.color: favourite ? Commons.Color.accent : Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.25)
                Column {
                  id: matchColumn
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(5)
                  Row {
                    width: parent.width
                    spacing: Style.space(8)
                    Text { text: modelData.league; color: Commons.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
                    Text {
                      text: modelData.state === "in" ? "LIVE · " + modelData.detail : modelData.state === "post" ? "FT" : Model.formatMatchTime(modelData.date)
                      color: modelData.state === "in" ? Commons.Color.accent : Commons.Color.muted
                      font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: modelData.state === "in"
                    }
                    Text { visible: favourite; text: "★ FAVOURITE"; color: Commons.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  }
                  Row {
                    width: parent.width
                    Text { width: (parent.width - score.width - Style.space(12)) / 2; text: modelData.home; color: Commons.Color.foreground
                      font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight }
                    Text { id: score; width: Style.space(60); text: modelData.state === "pre" ? "vs" : modelData.homeScore + " - " + modelData.awayScore
                      color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignHCenter }
                    Text { width: (parent.width - score.width - Style.space(12)) / 2; text: modelData.away; color: Commons.Color.foreground
                      font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }
                  }
                }
              }
            }
          }

          Column {
            visible: root.showingSettings
            width: parent.width
            spacing: Style.space(12)
            Text { text: "Favourite leagues"; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
            Text { text: "Choose the competitions to show in your match list."; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Flow {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: Model.leagues
                delegate: Button {
                  required property var modelData
                  text: modelData.name
                  selected: root.isLeagueSelected(modelData.id)
                  bordered: true
                  onClicked: root.toggleLeague(modelData.id)
                }
              }
            }
            Text { text: "Favourite team (one team)"; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
            Text { text: root.favoriteTeam ? "Selected: " + root.favoriteTeam.name : "Search and select one team below."; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            TextField { width: parent.width; placeholderText: "Search teams…"; text: root.teamSearchFilter; onTextChanged: root.teamSearchFilter = text }
            Rectangle {
              width: parent.width; height: Style.space(190); radius: Style.cornerRadius; clip: true
              color: Qt.rgba(0, 0, 0, 0.20); border.color: Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.25)
              Text { visible: root.isLoadingTeams; anchors.centerIn: parent; text: "Loading teams…"; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
              Flickable {
                anchors.fill: parent; anchors.margins: Style.space(8); contentWidth: width; contentHeight: teamFlow.implicitHeight
                clip: true; boundsBehavior: Flickable.StopAtBounds; flickableDirection: Flickable.VerticalFlick
                QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }
                Flow {
                  id: teamFlow; width: parent.width; spacing: Style.space(6)
                  Repeater {
                    model: {
                      var result = [], filter = root.teamSearchFilter.trim().toLowerCase()
                      for (var i = 0; i < root.availableTeams.length; i++)
                        if (!filter || root.availableTeams[i].name.toLowerCase().indexOf(filter) >= 0) result.push(root.availableTeams[i])
                      return result
                    }
                    delegate: Button {
                      required property var modelData
                      text: modelData.name
                      selected: root.favoriteTeam && String(root.favoriteTeam.id) === String(modelData.id)
                      bordered: true
                      onClicked: root.selectFavoriteTeam(modelData)
                    }
                  }
                }
              }
            }
            Button {
              text: root.remindersEnabled ? "Reminders: On" : "Reminders: Off"
              selected: root.remindersEnabled; bordered: true
              onClicked: { root.remindersEnabled = !root.remindersEnabled; root.persistSettings() }
            }
            Text { text: "Match notifications appear before kickoff when desktop notifications are available."; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
          }
        }
      }
    }
  }
}
