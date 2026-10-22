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
  property date calendarMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
  property bool calendarOpen: false
  property var matches: []
  property var availableTeams: []
  property var nextMatch: null
  property string label: Model.formatBarLabel(nextMatch, favoriteTeam)
  property bool showingSettings: false
  property string teamSearchFilter: ""
  property string teamSearchRequested: ""
  property string teamSearchCompleted: ""
  property bool isSearchingTeams: false
  property bool teamSearchPending: false
  property string leagueSearchFilter: ""
  property string leagueSearchRequested: ""
  property string leagueSearchCompleted: ""
  property var discoveredLeagues: []
  property bool leagueCatalogLoaded: false
  property bool isLoadingLeagues: false
  property string matchScope: "day"
  property string leagueMatchesId: selectedLeagues.length ? selectedLeagues[0] : ""
  property bool matchesRefreshPending: false
  property bool teamsRefreshPending: false
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
  function filteredLeagues() {
    var q = leagueSearchFilter.trim().toLowerCase(), result = [], seen = {}
    var all = q ? Model.leagues.concat(discoveredLeagues) : Model.leagues
    for (var i = 0; i < all.length; i++) {
      var item = all[i]
      if (seen[item.id]) continue
      seen[item.id] = true
      if (!q || item.name.toLowerCase().indexOf(q) >= 0 || item.id.toLowerCase().indexOf(q) >= 0) result.push(item)
    }
    return result
  }
  function searchLeagues() {
    var query = leagueSearchFilter.trim()
    if (query.length < 2) return
    if (leagueCatalogLoaded) { leagueSearchCompleted = query; return }
    if (isLoadingLeagues) return
    leagueSearchRequested = query
    isLoadingLeagues = true
    leagueProc.command = ["python3", scriptPath, "leagues", "200"]
    leagueProc.running = true
  }
  function onLeaguesFinished(raw) {
    isLoadingLeagues = false; leagueCatalogLoaded = true; leagueSearchCompleted = leagueSearchFilter.trim()
    try { var data = JSON.parse(raw); discoveredLeagues = Array.isArray(data) ? data : [] }
    catch (e) { discoveredLeagues = [] }
  }
  function toggleLeague(id) {
    var next = []
    for (var i = 0; i < selectedLeagues.length; i++) if (selectedLeagues[i] !== id) next.push(selectedLeagues[i])
    if (next.length === selectedLeagues.length) next.push(id)
    if (next.length === 0) next = [id]
    selectedLeagues = next
    if (selectedLeagues.indexOf(leagueMatchesId) < 0) leagueMatchesId = selectedLeagues[0]
    teamSearchCompleted = ""
    persistSettings(); fetchTeams(); fetchMatches(); fetchNextMatch()
  }
  function isLeagueSelected(id) { return selectedLeagues.indexOf(id) >= 0 }
  function selectFavoriteTeam(team) {
    if (favoriteTeam && String(favoriteTeam.id) === String(team.id)) { favoriteTeam = null; nextMatch = null; matchScope = "day" }
    else favoriteTeam = { id: String(team.id), name: team.name, short: team.short || team.name,
                         leagueId: team.leagueId || selectedLeagues[0] || "esp.1" }
    persistSettings(); fetchNextMatch(); fetchMatches()
  }
  function clearFavoriteTeam() { favoriteTeam = null; matchScope = "day"; nextMatch = null; persistSettings(); updateLabel(); fetchMatches() }
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
  function setMatchScope(scope) {
    matchScope = scope; matches = []; matchesError = ""; isLoadingMatches = true
    fetchMatches()
  }
  function selectLeagueMatches(id) {
    if (!id || id === leagueMatchesId) return
    leagueMatchesId = id; matches = []; matchesError = ""; isLoadingMatches = true
    fetchMatches()
  }
  function fetchMatches() {
    if (matchesProc.running) { matchesRefreshPending = true; return }
    isLoadingMatches = true; matchesError = ""
    var leagues = selectedLeagues.slice(0)
    if (matchScope === "league") {
      if (!leagueMatchesId || leagues.indexOf(leagueMatchesId) < 0) {
        leagueMatchesId = leagues.length ? leagues[0] : ""
      }
      if (!leagueMatchesId) { matches = []; isLoadingMatches = false; return }
      matchesProc.command = ["python3", scriptPath, "league-matches", leagueMatchesId, "30"]
      matchesProc.running = true
      return
    }
    if (matchScope === "team") {
      if (!favoriteTeam || !favoriteTeam.id) { matches = []; isLoadingMatches = false; return }
      if (favoriteTeam.leagueId && leagues.indexOf(favoriteTeam.leagueId) < 0) leagues.push(favoriteTeam.leagueId)
      matchesProc.command = ["python3", scriptPath, "team-matches", String(favoriteTeam.id), favoriteTeam.leagueId || "esp.1", leagues.join(","), "10"]
      matchesProc.running = true
      return
    }
    var dateParam = Model.formatDateParam(selectedDate)
    if (matchScope === "upcoming") {
      var start = new Date(); start.setHours(0, 0, 0, 0)
      var end = new Date(start); end.setDate(end.getDate() + 6)
      dateParam = Model.formatDateParam(start) + "-" + Model.formatDateParam(end)
    }
    matchesProc.command = ["python3", scriptPath, "matches", leagues.join(","), dateParam,
                          ""]
    matchesProc.running = true
  }
  function onMatchesFinished(raw) {
    if (matchesRefreshPending) {
      matchesRefreshPending = false; isLoadingMatches = true; fetchMatches(); return
    }
    isLoadingMatches = false
    try { var data = JSON.parse(raw); matches = Array.isArray(data) ? data : [] }
    catch (e) { matches = []; matchesError = "Could not read match data" }
  }
  function fetchTeams() {
    if (teamsProc.running) { teamsRefreshPending = true; return }
    isLoadingTeams = true
    teamsProc.command = ["python3", scriptPath, "teams", selectedLeagues.join(",")]
    teamsProc.running = true
  }
  function onTeamsFinished(raw) {
    isLoadingTeams = false
    try { var data = JSON.parse(raw); availableTeams = Array.isArray(data) ? data : [] }
    catch (e) { availableTeams = [] }
    if (teamsRefreshPending) { teamsRefreshPending = false; fetchTeams() }
  }
  function filteredTeams() {
    var result = [], filter = teamSearchFilter.trim().toLowerCase()
    for (var i = 0; i < availableTeams.length; i++) {
      var team = availableTeams[i]
      if (!filter) {
        if (Model.isPopularTeam(team) || (favoriteTeam && String(favoriteTeam.id) === String(team.id))) result.push(team)
      } else if (Model.matchesTeamSearch(team, filter)) result.push(team)
    }
    return result
  }
  function searchTeamsIfNeeded() {
    var query = teamSearchFilter.trim()
    if (query.length < 2 || filteredTeams().length > 0 || teamSearchCompleted === query) return
    if (teamSearchProc.running) { teamSearchPending = true; return }
    teamSearchRequested = query; isSearchingTeams = true
    teamSearchProc.command = ["python3", scriptPath, "search-teams", selectedLeagues.join(","), query]
    teamSearchProc.running = true
  }
  function onTeamSearchFinished(raw) {
    isSearchingTeams = false; teamSearchCompleted = teamSearchRequested
    try {
      var found = JSON.parse(raw), combined = availableTeams.slice(0), seen = {}
      for (var i = 0; i < combined.length; i++) seen[String(combined[i].id)] = true
      if (Array.isArray(found)) for (var j = 0; j < found.length; j++)
        if (!seen[String(found[j].id)]) combined.push(found[j])
      availableTeams = combined
    } catch (e) {}
    if (teamSearchPending) { teamSearchPending = false; searchTeamsIfNeeded() }
  }
  function changeDay(amount) {
    var d = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate())
    d.setDate(d.getDate() + amount); selectedDate = d
    calendarMonth = new Date(d.getFullYear(), d.getMonth(), 1); matches = []; isLoadingMatches = true; fetchMatches()
  }
  function goToToday() { selectedDate = new Date(); calendarMonth = new Date(selectedDate.getFullYear(), selectedDate.getMonth(), 1); matches = []; isLoadingMatches = true; fetchMatches() }
  function calendarDays() {
    var first = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth(), 1)
    var start = new Date(first); start.setDate(first.getDate() - ((first.getDay() + 6) % 7))
    var cells = []
    for (var i = 0; i < 42; i++) {
      var date = new Date(start); date.setDate(start.getDate() + i)
      cells.push({ date: date, inMonth: date.getMonth() === calendarMonth.getMonth() })
    }
    return cells
  }
  function shiftCalendarMonth(amount) { calendarMonth = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth() + amount, 1) }
  function isTodaySelected() {
    var now = new Date()
    return selectedDate.getFullYear() === now.getFullYear() && selectedDate.getMonth() === now.getMonth() && selectedDate.getDate() === now.getDate()
  }
  function isFavTeamMatch(match) {
    if (!favoriteTeam) return false
    return String(match.homeId) === String(favoriteTeam.id) || String(match.awayId) === String(favoriteTeam.id)
  }
  function checkReminder() {
    if (!favoriteTeam || !remindersEnabled || !nextMatch || reminderProc.running) return
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
  Process { id: teamSearchProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onTeamSearchFinished(String(text || "").trim()) }
  }
  Timer { id: teamSearchTimer; interval: 400; repeat: false; onTriggered: root.searchTeamsIfNeeded() }
  Process { id: leagueProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onLeaguesFinished(String(text || "").trim()) }
  }
  Timer { id: leagueSearchTimer; interval: 400; repeat: false; onTriggered: root.searchLeagues() }
  Process { id: reminderProc }
  Timer {
    interval: 120000; running: true; repeat: true
    onTriggered: { root.fetchNextMatch(); if (root.opened && root.matchScope === "day") root.fetchMatches() }
  }
  Timer { interval: 60000; running: true; repeat: true; onTriggered: { root.updateLabel(); root.checkReminder() } }
  Component.onCompleted: { fetchNextMatch(); fetchMatches() }

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
                  text: root.nextMatch ? root.nextMatch.league + (root.nextMatch.round ? " · " + root.nextMatch.round : "") + " · " + Model.formatDayLabel(new Date(root.nextMatch.date)) + " at " + Model.formatMatchTime(root.nextMatch.date) : ""
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
            Flow {
              width: parent.width
              spacing: Style.space(6)
              Button { text: "By day"; selected: root.matchScope === "day"; bordered: true; onClicked: root.setMatchScope("day") }
              Button { text: "Next 7 days"; selected: root.matchScope === "upcoming"; bordered: true; onClicked: root.setMatchScope("upcoming") }
              Button { text: root.favoriteTeam ? (root.favoriteTeam.short || root.favoriteTeam.name) + " · Next 10" : "Favourite · Next 10"; enabled: !!root.favoriteTeam; selected: root.matchScope === "team"; bordered: true; onClicked: root.setMatchScope("team") }
              Button { text: "By league"; selected: root.matchScope === "league"; bordered: true; onClicked: root.setMatchScope("league") }
            }
            QQC.ComboBox {
              visible: root.matchScope === "league"
              width: parent.width
              model: root.selectedLeagues.map(function(id) { return Model.leagueName(id) })
              currentIndex: Math.max(0, root.selectedLeagues.indexOf(root.leagueMatchesId))
              onActivated: function(index) { root.selectLeagueMatches(root.selectedLeagues[index]) }
            }
            Text {
              visible: root.matchScope === "league"
              text: "Scheduled matches over the next 30 days"
              color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
            }
            Row {
              visible: root.matchScope === "day"
              width: parent.width; spacing: Style.space(8)
              Button { text: "◀"; bordered: true; onClicked: root.changeDay(-1) }
              Text { width: parent.width - 120; text: Model.formatDayLabel(root.selectedDate); color: Commons.Color.foreground
                font.family: Style.font.family; font.pixelSize: Style.font.body; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
              Button { text: "▶"; bordered: true; onClicked: root.changeDay(1) }
              Button { visible: !root.isTodaySelected(); text: "Today"; bordered: true; onClicked: root.goToToday() }
            }
            Row {
              visible: root.matchScope === "day"
              width: parent.width; spacing: Style.space(8)
              Text { text: "Selected: " + Model.formatDayLabel(root.selectedDate); color: Commons.Color.muted
                font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
              Button { text: root.calendarOpen ? "Close calendar" : "Choose date"; bordered: true
                onClicked: { root.calendarMonth = new Date(root.selectedDate.getFullYear(), root.selectedDate.getMonth(), 1); root.calendarOpen = !root.calendarOpen } }
            }
            Column {
              visible: root.matchScope === "day" && root.calendarOpen
              width: parent.width; spacing: Style.space(6)
              Row {
                width: parent.width
                Button { text: "◀"; bordered: true; onClicked: root.shiftCalendarMonth(-1) }
                Text { width: parent.width - Style.space(100); text: Model.formatMonthLabel(root.calendarMonth); color: Commons.Color.foreground
                  font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                Button { text: "▶"; bordered: true; onClicked: root.shiftCalendarMonth(1) }
              }
              Row {
                width: parent.width
                Repeater {
                  model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                  delegate: Text { required property string modelData; width: parent.width / 7; text: modelData
                    color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignHCenter }
                }
              }
              Grid {
                id: calendarGrid
                columns: 7; width: parent.width; spacing: Style.space(3)
                Repeater {
                  model: root.calendarDays()
                  delegate: Button {
                    required property var modelData
                    width: (calendarGrid.width - Style.space(18)) / 7
                    height: Style.space(34)
                    text: String(modelData.date.getDate())
                    opacity: modelData.inMonth ? 1.0 : 0.42
                    selected: Model.sameLocalDay(modelData.date, root.selectedDate)
                    bordered: true
                    onClicked: {
                      root.selectedDate = modelData.date
                      root.calendarMonth = new Date(modelData.date.getFullYear(), modelData.date.getMonth(), 1)
                      root.calendarOpen = false; root.matches = []; root.isLoadingMatches = true; root.fetchMatches()
                    }
                  }
                }
              }
            }
            Text { visible: root.isLoadingMatches; text: "Loading matches…"; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body }
            Text {
              visible: !root.isLoadingMatches && root.matches.length === 0
              text: root.matchesError || (root.matchScope === "team" ? "No upcoming matches were found for " + (root.favoriteTeam ? root.favoriteTeam.name : "your favourite team") + "." : root.matchScope === "upcoming" ? "No upcoming matches in the next seven days." : root.matchScope === "league" ? "No scheduled matches were found for this league in the next 30 days." : "No matches found for this day in the selected leagues.")
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
                color: favourite ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12) : Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.78)
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
                    id: matchMetaRow
                    Rectangle {
                      id: leaguePill
                      width: Math.min(leagueText.implicitWidth + Style.space(14), parent.width * 0.55)
                      height: leagueText.implicitHeight + Style.space(8); radius: Style.cornerRadius
                      color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.13)
                      border.width: 1; border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35)
                      Text { id: leagueText; anchors.centerIn: parent; width: parent.width - Style.space(10); text: modelData.league + (modelData.round ? " · " + modelData.round : ""); elide: Text.ElideRight
                        color: Commons.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
                    }
                    Item { width: Math.max(0, matchMetaRow.width - leaguePill.width - matchTimePill.width - Style.space(16)); height: 1 }
                    Rectangle {
                      id: matchTimePill
                      readonly property bool live: modelData.state === "in"
                      height: timeText.implicitHeight + Style.space(8); width: timeText.implicitWidth + Style.space(14); radius: Style.cornerRadius
                      color: Qt.rgba((live ? Commons.Color.urgent : Commons.Color.foreground).r, (live ? Commons.Color.urgent : Commons.Color.foreground).g, (live ? Commons.Color.urgent : Commons.Color.foreground).b, live ? 0.16 : 0.07)
                      border.width: 1; border.color: Qt.rgba((live ? Commons.Color.urgent : Commons.Color.muted).r, (live ? Commons.Color.urgent : Commons.Color.muted).g, (live ? Commons.Color.urgent : Commons.Color.muted).b, 0.32)
                      Text { id: timeText
                        text: (root.matchScope === "upcoming" || root.matchScope === "team" || root.matchScope === "league" ? Model.formatDayLabel(new Date(modelData.date)) + " · " : "") + (modelData.state === "in" ? "LIVE · " + modelData.detail : modelData.state === "post" ? "FT" : Model.formatMatchTime(modelData.date))
                        color: parent.live ? Commons.Color.urgent : Commons.Color.foreground
                        font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: parent.live
                        anchors.centerIn: parent }
                    }
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
            Text { text: "Popular competitions are ready immediately. Search to find others; teams follow your selected leagues."; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap }
            TextField { width: parent.width; placeholderText: "Search leagues by name…"; text: root.leagueSearchFilter
              onTextChanged: { root.leagueSearchFilter = text; root.leagueSearchCompleted = ""; root.leagueSearchTimer.restart() } }
            Text { visible: root.isLoadingLeagues; text: "Searching leagues…"; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Flow {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: root.filteredLeagues()
                delegate: Button {
                  required property var modelData
                  text: modelData.name
                  selected: root.isLeagueSelected(modelData.id)
                  bordered: true
                  onClicked: root.toggleLeague(modelData.id)
                }
              }
            }
            Text { visible: root.leagueSearchFilter.trim().length >= 2 && root.leagueSearchCompleted === root.leagueSearchFilter.trim() && root.filteredLeagues().length === 0; text: "League not found. Try its full competition name."; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            Text { text: "Favourite team (one team)"; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
            Text { text: root.favoriteTeam ? "Selected: " + root.favoriteTeam.name : "Search and select one team below."; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            TextField { width: parent.width; placeholderText: "Search team by name…"; text: root.teamSearchFilter
              onTextChanged: { root.teamSearchFilter = text; root.teamSearchCompleted = ""; root.teamSearchTimer.restart() } }
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
                    model: root.filteredTeams()
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
              Text { visible: root.isSearchingTeams; anchors.centerIn: parent; text: "Searching ESPN for teams…"; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
              Text { visible: root.teamSearchFilter.trim().length >= 2 && root.teamSearchCompleted === root.teamSearchFilter.trim() && root.filteredTeams().length === 0 && !root.isSearchingTeams
                anchors.centerIn: parent; text: "Team not found. Try the full team name."; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            }
            Button {
              text: root.remindersEnabled ? "Reminders: On" : "Reminders: Off"
              selected: root.remindersEnabled; bordered: true
              onClicked: { root.remindersEnabled = !root.remindersEnabled; root.persistSettings() }
            }
            Text { text: "When enabled, a desktop notification is sent once before your favourite team’s next match. The default lead time is 15 minutes."; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap }
          }
        }
      }
    }
  }
}
