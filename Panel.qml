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
  moduleName: "ayman.football-matches"
  ipcTarget: "ayman.football-matches"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property string scriptPath: {
    var p = Qt.resolvedUrl("api.py").toString().replace(/^file:\/\//, "")
    return p !== "" ? p : (Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.moduleName + "/api.py")
  }

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
  property var standings: []
  property string standingsLeagueId: selectedLeagues.length ? selectedLeagues[0] : "esp.1"
  property bool isLoadingStandings: false
  property bool standingsRefreshPending: false
  property string standingsError: ""
  property bool matchesRefreshPending: false
  property bool showingMatchCenter: false
  property string matchCenterTab: "timeline"
  property var currentMatchItem: null
  property string selectedMatchId: ""
  property var selectedMatchDetails: null
  property bool isLoadingMatchDetails: false
  readonly property var activeMatch: root.selectedMatchDetails || root.currentMatchItem || null
  readonly property var activeLineup: (root.selectedMatchDetails && root.selectedMatchDetails.lineup) ? root.selectedMatchDetails.lineup : null
  readonly property bool hasActiveLineup: Boolean(activeLineup && activeLineup.available)
  property bool teamsRefreshPending: false
  property bool isLoadingMatches: false
  property bool isLoadingTeams: false
  property bool isLoadingNextMatch: false
  property bool nextRefreshPending: false
  property string matchesError: ""
  readonly property bool opened: root.controller.open

  function openFromHotkey() { open() }
  function open() {
    root.controller.open = true
    refreshAll()
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }
  function close() { root.controller.open = false; showingSettings = false; showingMatchCenter = false }
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
  function refreshAll() {
    fetchNextMatch()
    if (matchScope === "table") fetchStandings()
    else fetchMatches()
    if (showingSettings || availableTeams.length === 0) fetchTeams()
  }
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
    if (selectedLeagues.indexOf(standingsLeagueId) < 0) standingsLeagueId = selectedLeagues[0]
    teamSearchCompleted = ""
    persistSettings(); fetchTeams(); if (matchScope === "table") fetchStandings(); else fetchMatches(); fetchNextMatch()
  }
  function clearSelectedLeagues() {
    selectedLeagues = []
    leagueMatchesId = ""
    standingsLeagueId = ""
    teamSearchCompleted = ""
    persistSettings()
    fetchTeams()
    matches = []
    matchesError = ""
    standings = []
    standingsError = ""
    if (matchScope === "table") fetchStandings()
    else {
      if (matchesProc.running) matchesRefreshPending = true
      else fetchMatches()
    }
    fetchNextMatch()
  }
  function isLeagueSelected(id) { return selectedLeagues.indexOf(id) >= 0 }
  function selectFavoriteTeam(team) {
    if (favoriteTeam && String(favoriteTeam.id) === String(team.id)) { favoriteTeam = null; nextMatch = null; matchScope = "day" }
    else favoriteTeam = { id: String(team.id), name: team.name, short: team.short || team.name,
                         leagueId: team.leagueId || selectedLeagues[0] || "esp.1" }
    persistSettings(); fetchNextMatch(); fetchMatches()
  }
  function clearFavoriteTeam() { favoriteTeam = null; matchScope = "day"; nextMatch = null; persistSettings(); updateLabel(); fetchNextMatch(); fetchMatches() }
  function fetchNextMatch() {
    if (nextProc.running) { nextRefreshPending = true; return }
    if (!favoriteTeam || !favoriteTeam.id) { isLoadingNextMatch = false; nextMatch = null; updateLabel(); return }
    isLoadingNextMatch = true
    nextProc.command = ["python3", scriptPath, "next", String(favoriteTeam.id),
                        favoriteTeam.leagueId || "esp.1", selectedLeagues.join(",")]
    nextProc.running = true
  }
  function onNextMatchFinished(raw) {
    if (nextRefreshPending) {
      nextRefreshPending = false; isLoadingNextMatch = true; fetchNextMatch(); return
    }
    isLoadingNextMatch = false
    try { var data = JSON.parse(raw); nextMatch = data && data.opponent ? data : null }
    catch (e) { nextMatch = null }
    updateLabel(); checkReminder()
  }
  function updateLabel() { label = Model.formatBarLabel(nextMatch, favoriteTeam) }
  function setMatchScope(scope) {
    matchScope = scope
    if (scope === "table") {
      standings = []
      standingsError = ""
      fetchStandings()
    } else {
      matches = []
      matchesError = ""
      isLoadingMatches = true
      fetchMatches()
    }
  }
  function selectLeagueMatches(id) {
    if (!id || id === leagueMatchesId) return
    leagueMatchesId = id; matches = []; matchesError = ""; isLoadingMatches = true
    fetchMatches()
  }
  function selectStandingsLeague(id) {
    if (!id || id === standingsLeagueId) return
    standingsLeagueId = id; standings = []; standingsError = ""; isLoadingStandings = true
    fetchStandings()
  }
  function fetchStandings() {
    if (!standingsLeagueId && selectedLeagues.length) standingsLeagueId = selectedLeagues[0]
    if (!standingsLeagueId) { standings = []; isLoadingStandings = false; return }
    if (standingsProc.running) { standingsRefreshPending = true; return }
    isLoadingStandings = true; standingsError = ""
    standingsProc.command = ["python3", scriptPath, "standings", standingsLeagueId]
    standingsProc.running = true
  }
  function onStandingsFinished(raw) {
    if (standingsRefreshPending) {
      standingsRefreshPending = false; isLoadingStandings = true; fetchStandings(); return
    }
    isLoadingStandings = false
    try {
      var data = JSON.parse(raw)
      standings = Array.isArray(data) ? data : []
      if (standings.length === 0) standingsError = "No standings available for this competition"
    } catch (e) {
      standings = []
      standingsError = "Could not read standings data"
    }
  }
  function fetchMatches() {
    if ((matchScope === "day" || matchScope === "upcoming") && selectedLeagues.length === 0) {
      matches = []; matchesError = ""; isLoadingMatches = false
      return
    }
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

  function openMatchCenter(match) {
    if (!match) return
    var normMatch = {
      id: String(match.id || ""),
      leagueId: match.leagueId || "esp.1",
      leagueName: match.leagueName || match.league || "",
      round: match.round || "",
      state: match.state || "pre",
      date: match.date || "",
      detail: (match.detail && match.detail.indexOf("EST") < 0 && match.detail.indexOf("EDT") < 0) ? match.detail : (match.state === "pre" ? "Scheduled" : (match.detail || "")),
      home: match.home || match.homeName || match.homeTeam || "Home",
      away: match.away || match.awayName || match.awayTeam || "Away",
      homeLogo: match.homeLogo || "",
      awayLogo: match.awayLogo || "",
      homeScore: (match.homeScore !== undefined && match.homeScore !== null) ? String(match.homeScore) : "",
      awayScore: (match.awayScore !== undefined && match.awayScore !== null) ? String(match.awayScore) : "",
      venue: match.venue || ""
    }
    currentMatchItem = normMatch
    selectedMatchId = normMatch.id
    selectedMatchDetails = null
    isLoadingMatchDetails = true
    matchCenterTab = (normMatch.state === "pre") ? "lineup" : "timeline"
    showingMatchCenter = true
    showingSettings = false
    matchDetailsProc.command = ["python3", scriptPath, "match-details", normMatch.leagueId, normMatch.id]
    matchDetailsProc.running = true
  }

  function toggleMatchDetails(leagueId, matchId) {
    openMatchCenter({ id: matchId, leagueId: leagueId })
  }
  function onMatchDetailsFinished(raw) {
    isLoadingMatchDetails = false
    try {
      var data = JSON.parse(raw)
      if (data && data.id) {
        if (!data.date && currentMatchItem && currentMatchItem.date) {
          data.date = currentMatchItem.date
        }
        selectedMatchDetails = data
      } else {
        selectedMatchDetails = null
      }
    } catch (e) {
      selectedMatchDetails = null
    }
  }

  Process { id: matchDetailsProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onMatchDetailsFinished(String(text || "").trim()) }
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
  Process { id: standingsProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onStandingsFinished(String(text || "").trim()) }
  }
  Process { id: reminderProc }
  Timer {
    interval: 120000; running: true; repeat: true
    onTriggered: {
      root.fetchNextMatch()
      if (root.opened) {
        if (root.matchScope === "table") root.fetchStandings()
        else if (root.matchScope === "day") root.fetchMatches()
      }
    }
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
              width: parent.width - (root.showingMatchCenter ? refreshButton.width + Style.space(16) : settingsButton.width + refreshButton.width + Style.space(24))
              text: root.showingMatchCenter ? "Match Center" : (root.showingSettings ? "Football settings" : "Football")
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
            Button { id: settingsButton; text: root.showingSettings ? "Matches" : "Settings"; bordered: true
              visible: !root.showingMatchCenter
              onClicked: { root.showingSettings = !root.showingSettings; if (root.showingSettings) root.fetchTeams() } }
            Button { id: refreshButton; text: "↻"; bordered: true
              onClicked: {
                if (root.showingMatchCenter && root.currentMatchItem) {
                  root.openMatchCenter(root.currentMatchItem)
                } else {
                  root.refreshAll()
                }
              }
            }
          }

          Column {
            visible: !root.showingSettings && !root.showingMatchCenter
            width: parent.width
            spacing: Style.space(10)
            Rectangle {
              width: parent.width
              implicitHeight: favColumn.implicitHeight + Style.space(18)
              radius: Style.cornerRadius
              color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.10)
              border.color: Commons.Color.accent
              border.width: 1

              MouseArea {
                anchors.fill: parent
                cursorShape: root.nextMatch ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.nextMatch) {
                    root.openMatchCenter({
                      id: root.nextMatch.id,
                      leagueId: root.nextMatch.leagueId || (root.favoriteTeam ? root.favoriteTeam.leagueId : "esp.1"),
                      league: root.nextMatch.league || "",
                      home: root.nextMatch.homeName || root.nextMatch.homeTeam,
                      away: root.nextMatch.awayName || root.nextMatch.awayTeam,
                      homeLogo: root.nextMatch.homeLogo || "",
                      awayLogo: root.nextMatch.awayLogo || "",
                      homeScore: root.nextMatch.homeScore || "",
                      awayScore: root.nextMatch.awayScore || "",
                      state: root.nextMatch.state || "pre",
                      detail: root.nextMatch.detail || root.nextMatch.time || "",
                      round: root.nextMatch.round || "",
                      venue: root.nextMatch.venue || ""
                    })
                  }
                }
              }
              Column {
                id: favColumn
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(6)
                Text {
                  width: parent.width
                  text: root.favoriteTeam ? root.favoriteTeam.name + " · Next match" : "Choose a favourite team in Settings"
                  color: Commons.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true
                }
                Row {
                  width: parent.width
                  visible: root.nextMatch !== null
                  spacing: Style.space(6)

                  Row {
                    width: (parent.width - heroScore.width - Style.space(12)) / 2
                    spacing: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    Image {
                      source: (root.nextMatch && root.nextMatch.homeLogo) ? root.nextMatch.homeLogo : ""
                      width: Style.space(28); height: Style.space(28)
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      mipmap: true
                      smooth: true
                      sourceSize.width: Style.space(96)
                      sourceSize.height: Style.space(96)
                      visible: source != ""
                      anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                      width: parent.width - ((root.nextMatch && root.nextMatch.homeLogo) ? Style.space(34) : 0)
                      text: root.nextMatch ? root.nextMatch.homeName : ""
                      color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.heading; font.bold: true
                      elide: Text.ElideRight
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  Text {
                    id: heroScore; width: Style.space(50)
                    text: root.nextMatch ? (root.nextMatch.state === "pre" ? "vs" : root.nextMatch.homeScore + " - " + root.nextMatch.awayScore) : ""
                    color: (root.nextMatch && root.nextMatch.state === "in") ? Commons.Color.urgent : Commons.Color.foreground
                    font.family: Style.font.family; font.pixelSize: Style.font.heading; font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Row {
                    width: (parent.width - heroScore.width - Style.space(12)) / 2
                    spacing: Style.space(6)
                    layoutDirection: Qt.RightToLeft
                    anchors.verticalCenter: parent.verticalCenter
                    Image {
                      source: (root.nextMatch && root.nextMatch.awayLogo) ? root.nextMatch.awayLogo : ""
                      width: Style.space(28); height: Style.space(28)
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      mipmap: true
                      smooth: true
                      sourceSize.width: Style.space(96)
                      sourceSize.height: Style.space(96)
                      visible: source != ""
                      anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                      width: parent.width - ((root.nextMatch && root.nextMatch.awayLogo) ? Style.space(34) : 0)
                      text: root.nextMatch ? root.nextMatch.awayName : ""
                      color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.heading; font.bold: true
                      elide: Text.ElideRight; horizontalAlignment: Text.AlignRight
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }
                }
                Row {
                  width: parent.width
                  visible: root.nextMatch !== null
                  spacing: Style.space(6)
                  Image {
                    source: (root.nextMatch && root.nextMatch.leagueLogo) ? root.nextMatch.leagueLogo : ""
                    width: Style.space(18); height: Style.space(18)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    mipmap: true
                    smooth: true
                    sourceSize.width: Style.space(64)
                    sourceSize.height: Style.space(64)
                    visible: source != ""
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    width: parent.width - ((root.nextMatch && root.nextMatch.leagueLogo) ? Style.space(24) : 0)
                    text: root.nextMatch ? root.nextMatch.league + (root.nextMatch.round ? " · " + root.nextMatch.round : "") + " · " + Model.formatDayLabel(new Date(root.nextMatch.date)) + " at " + Model.formatMatchTime(root.nextMatch.date) : ""
                    color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
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
              spacing: Style.space(6)
              Button { width: (parent.width - parent.spacing * 4) / 5; text: "Day"; selected: root.matchScope === "day"; bordered: true; onClicked: root.setMatchScope("day") }
              Button { width: (parent.width - parent.spacing * 4) / 5; text: "7 Days"; selected: root.matchScope === "upcoming"; bordered: true; onClicked: root.setMatchScope("upcoming") }
              Button { width: (parent.width - parent.spacing * 4) / 5; text: "Table"; selected: root.matchScope === "table"; bordered: true; onClicked: root.setMatchScope("table") }
              Button { width: (parent.width - parent.spacing * 4) / 5; text: root.favoriteTeam ? "Team" : "Fav"; enabled: !!root.favoriteTeam; selected: root.matchScope === "team"; bordered: true; onClicked: root.setMatchScope("team") }
              Button { width: (parent.width - parent.spacing * 4) / 5; text: "League"; selected: root.matchScope === "league"; bordered: true; onClicked: root.setMatchScope("league") }
            }
            QQC.ComboBox {
              id: leagueMatchesCombo
              visible: root.matchScope === "league"
              width: parent.width
              model: root.selectedLeagues.map(function(id) { return Model.leagueName(id) })
              currentIndex: Math.max(0, root.selectedLeagues.indexOf(root.leagueMatchesId))
              onActivated: function(index) { root.selectLeagueMatches(root.selectedLeagues[index]) }

              contentItem: Text {
                leftPadding: Style.space(12)
                rightPadding: Style.space(24)
                text: leagueMatchesCombo.displayText
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                color: "#FFFFFF"
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
              }

              background: Rectangle {
                implicitHeight: Style.space(34)
                radius: Style.cornerRadius
                color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.85)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.20)
              }

              delegate: QQC.ItemDelegate {
                width: leagueMatchesCombo.width
                contentItem: Text {
                  text: modelData
                  color: "#FFFFFF"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: leagueMatchesCombo.currentIndex === index
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                }
                background: Rectangle {
                  color: highlighted ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.30) : "transparent"
                }
              }

              popup: QQC.Popup {
                y: leagueMatchesCombo.height + Style.space(2)
                width: leagueMatchesCombo.width
                implicitHeight: contentItem.implicitHeight + Style.space(8)
                padding: Style.space(4)
                contentItem: ListView {
                  clip: true
                  implicitHeight: contentHeight
                  model: leagueMatchesCombo.popup.visible ? leagueMatchesCombo.delegateModel : null
                  currentIndex: leagueMatchesCombo.highlightedIndex
                  QQC.ScrollIndicator.vertical: QQC.ScrollIndicator { }
                }
                background: Rectangle {
                  color: Commons.Color.menu.background
                  border.color: Qt.rgba(1, 1, 1, 0.20)
                  border.width: 1
                  radius: Style.cornerRadius
                }
              }
            }
            Text {
              visible: root.matchScope === "league"
              text: "Scheduled matches over the next 30 days"
              color: "#FFFFFF"
              opacity: 0.8
              font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
            }

            Column {
              visible: root.matchScope === "table"
              width: parent.width
              spacing: Style.space(8)

              QQC.ComboBox {
                id: standingsCombo
                width: parent.width
                model: root.selectedLeagues.map(function(id) { return Model.leagueName(id) })
                currentIndex: Math.max(0, root.selectedLeagues.indexOf(root.standingsLeagueId))
                onActivated: function(index) { root.selectStandingsLeague(root.selectedLeagues[index]) }

                contentItem: Text {
                  leftPadding: Style.space(12)
                  rightPadding: Style.space(24)
                  text: standingsCombo.displayText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: "#FFFFFF"
                  verticalAlignment: Text.AlignVCenter
                  elide: Text.ElideRight
                }

                background: Rectangle {
                  implicitHeight: Style.space(34)
                  radius: Style.cornerRadius
                  color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.85)
                  border.width: 1
                  border.color: Qt.rgba(1, 1, 1, 0.20)
                }

                delegate: QQC.ItemDelegate {
                  width: standingsCombo.width
                  contentItem: Text {
                    text: modelData
                    color: "#FFFFFF"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: standingsCombo.currentIndex === index
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                  }
                  background: Rectangle {
                    color: highlighted ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.30) : "transparent"
                  }
                }

                popup: QQC.Popup {
                  y: standingsCombo.height + Style.space(2)
                  width: standingsCombo.width
                  implicitHeight: contentItem.implicitHeight + Style.space(8)
                  padding: Style.space(4)
                  contentItem: ListView {
                    clip: true
                    implicitHeight: contentHeight
                    model: standingsCombo.popup.visible ? standingsCombo.delegateModel : null
                    currentIndex: standingsCombo.highlightedIndex
                    QQC.ScrollIndicator.vertical: QQC.ScrollIndicator { }
                  }
                  background: Rectangle {
                    color: Commons.Color.menu.background
                    border.color: Qt.rgba(1, 1, 1, 0.20)
                    border.width: 1
                    radius: Style.cornerRadius
                  }
                }
              }

              Text {
                visible: root.isLoadingStandings
                text: "Loading standings…"
                color: "#FFFFFF"
                opacity: 0.85
                font.family: Style.font.family; font.pixelSize: Style.font.body
              }

              Text {
                visible: !root.isLoadingStandings && root.standings.length === 0
                text: root.standingsError || "No standings available for this competition."
                color: "#FFFFFF"
                opacity: 0.85
                font.family: Style.font.family; font.pixelSize: Style.font.body
              }

              Rectangle {
                visible: !root.isLoadingStandings && root.standings.length > 0
                width: parent.width
                implicitHeight: tableColumn.implicitHeight + Style.space(12)
                radius: Style.cornerRadius
                color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.70)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.18)

                Column {
                  id: tableColumn
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  spacing: Style.space(2)

                  Rectangle {
                    width: parent.width
                    height: Style.space(26)
                    radius: Style.cornerRadius
                    color: Qt.rgba(1, 1, 1, 0.08)
                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(6)
                      anchors.rightMargin: Style.space(6)
                      spacing: Style.space(4)

                      Text { width: Style.space(24); text: "#"; color: "#FFFFFF"; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                      Text { width: parent.width - Style.space(24 + 28*4 + 36 + 36 + 24); text: "Club"; color: "#FFFFFF"; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                      Text { width: Style.space(28); text: "P"; color: "#FFFFFF"; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                      Text { width: Style.space(28); text: "W"; color: "#FFFFFF"; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                      Text { width: Style.space(28); text: "D"; color: "#FFFFFF"; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                      Text { width: Style.space(28); text: "L"; color: "#FFFFFF"; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                      Text { width: Style.space(36); text: "GD"; color: "#FFFFFF"; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                      Text { width: Style.space(36); text: "PTS"; color: "#FFFFFF"; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                    }
                  }

                  Repeater {
                    model: root.standings
                    delegate: Column {
                      id: standingsRowCol
                      required property var modelData
                      required property int index
                      readonly property bool isFav: root.favoriteTeam && String(root.favoriteTeam.id) === String(modelData.teamId)
                      readonly property int rankNum: parseInt(modelData.rank) || (index + 1)
                      readonly property bool isUclZone: rankNum <= 4
                      width: tableColumn.width
                      spacing: Style.space(2)

                      Rectangle {
                        visible: !!modelData.group && (index === 0 || root.standings[index - 1].group !== modelData.group)
                        width: parent.width
                        height: Style.space(22)
                        color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25)
                        radius: Style.cornerRadius
                        Text {
                          anchors.centerIn: parent
                          text: modelData.group
                          color: "#FFFFFF"
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }

                      Rectangle {
                        width: parent.width
                        height: Style.space(28)
                        radius: Style.cornerRadius
                        color: standingsRowCol.isFav ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25) : (index % 2 === 1 ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                        border.width: standingsRowCol.isFav ? 1 : 0
                        border.color: Commons.Color.accent

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(6)
                          anchors.rightMargin: Style.space(6)
                          spacing: Style.space(4)

                          Text {
                            width: Style.space(24)
                            text: modelData.rank
                            color: standingsRowCol.isFav ? Commons.Color.accent : (standingsRowCol.isUclZone ? Commons.Color.accent : "#FFFFFF")
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                            font.bold: standingsRowCol.isFav || standingsRowCol.isUclZone
                            horizontalAlignment: Text.AlignHCenter
                            anchors.verticalCenter: parent.verticalCenter
                          }

                          Row {
                            width: parent.width - Style.space(24 + 28*4 + 36 + 36 + 24)
                            spacing: Style.space(6)
                            anchors.verticalCenter: parent.verticalCenter
                            Image {
                              source: modelData.logo || ""
                              width: Style.space(18); height: Style.space(18)
                              fillMode: Image.PreserveAspectFit
                              asynchronous: true
                              mipmap: true
                              smooth: true
                              sourceSize.width: Style.space(64)
                              sourceSize.height: Style.space(64)
                              visible: source != ""
                              anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                              width: parent.width - (modelData.logo ? Style.space(24) : 0)
                              text: modelData.short || modelData.name
                              color: standingsRowCol.isFav ? Commons.Color.accent : "#FFFFFF"
                              font.family: Style.font.family
                              font.pixelSize: Style.font.bodySmall
                              font.bold: standingsRowCol.isFav
                              elide: Text.ElideRight
                              anchors.verticalCenter: parent.verticalCenter
                            }
                          }

                          Text { width: Style.space(28); text: modelData.played; color: "#FFFFFF"; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                          Text { width: Style.space(28); text: modelData.wins; color: "#FFFFFF"; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: true; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                          Text { width: Style.space(28); text: modelData.ties; color: "#FFFFFF"; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                          Text { width: Style.space(28); text: modelData.losses; color: "#FFFFFF"; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                          Text {
                            width: Style.space(36); text: modelData.gd
                            color: modelData.gd.indexOf("+") === 0 ? "#4ade80" : (modelData.gd.indexOf("-") === 0 ? "#f87171" : "#FFFFFF")
                            font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
                            horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter
                          }
                          Text { width: Style.space(36); text: modelData.points; color: standingsRowCol.isFav ? Commons.Color.accent : "#FFFFFF"; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: true; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }
                        }
                      }
                    }
                  }
                }
              }
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
              Text { text: "Selected: " + Model.formatDayLabel(root.selectedDate); color: "#FFFFFF"; opacity: 0.8
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
                    color: "#FFFFFF"; opacity: 0.75; font.family: Style.font.family; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignHCenter }
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
            Text { visible: root.matchScope !== "table" && root.isLoadingMatches; text: "Loading matches…"; color: "#FFFFFF"; opacity: 0.85; font.family: Style.font.family; font.pixelSize: Style.font.body }
            Text {
              visible: root.matchScope !== "table" && !root.isLoadingMatches && root.matches.length === 0
              text: root.matchesError || (root.matchScope === "team" ? "No upcoming matches were found for " + (root.favoriteTeam ? root.favoriteTeam.name : "your favourite team") + "." : root.matchScope === "upcoming" ? "No upcoming matches in the next seven days." : root.matchScope === "league" ? "No scheduled matches were found for this league in the next 30 days." : "No matches found for this day in the selected leagues.")
              color: "#FFFFFF"; opacity: 0.85; font.family: Style.font.family; font.pixelSize: Style.font.body
            }

            Component {
              id: matchCardComponent
              Rectangle {
                id: cardRect
                required property var modelData
                readonly property bool favourite: root.isFavTeamMatch(modelData)
                width: mainColumn.width
                implicitHeight: matchColumn.implicitHeight + Style.space(16)
                radius: Style.cornerRadius
                color: favourite ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12) : Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.78)
                border.width: favourite ? 2 : 1
                border.color: favourite ? Commons.Color.accent : Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.25)

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openMatchCenter(modelData)
                }
                Column {
                  id: matchColumn
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(5)
                  Item {
                    width: parent.width
                    height: Math.max(leftMetaRow.height, matchTimePill.height)
                    id: matchMetaRow
                    Row {
                      id: leftMetaRow
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(6)
                      Rectangle {
                        id: roundPill
                        visible: !!modelData.round
                        height: roundText.implicitHeight + Style.space(8); width: roundText.implicitWidth + Style.space(14); radius: Style.cornerRadius
                        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.08)
                        border.width: 1; border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.18)
                        Text { id: roundText; anchors.centerIn: parent; text: modelData.round || ""
                          color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
                      }
                      Rectangle {
                        id: leaguePill
                        visible: root.matchScope !== "day"
                        width: Math.min(leagueText.implicitWidth + Style.space(14), parent.width * 0.38)
                        height: leagueText.implicitHeight + Style.space(8); radius: Style.cornerRadius
                        color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.13)
                        border.width: 1; border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35)
                        Text { id: leagueText; anchors.centerIn: parent; width: parent.width - Style.space(10); text: modelData.league; elide: Text.ElideRight
                          color: Commons.Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true }
                      }
                    }
                    Rectangle {
                      id: matchTimePill
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
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
                    spacing: Style.space(6)

                    Row {
                      width: (parent.width - score.width - Style.space(12)) / 2
                      spacing: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      Image {
                        source: modelData.homeLogo || ""
                        width: Style.space(22); height: Style.space(22)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        mipmap: true
                        smooth: true
                        sourceSize.width: Style.space(64)
                        sourceSize.height: Style.space(64)
                        visible: source != ""
                        anchors.verticalCenter: parent.verticalCenter
                      }
                      Text {
                        width: parent.width - ((modelData.homeLogo && modelData.homeLogo !== "") ? Style.space(28) : 0)
                        text: modelData.home; color: Commons.Color.foreground
                        font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }

                    Text { id: score; width: Style.space(60); text: modelData.state === "pre" ? "vs" : modelData.homeScore + " - " + modelData.awayScore
                      color: (modelData.state === "in") ? Commons.Color.urgent : Commons.Color.foreground
                      font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: modelData.state !== "pre"
                      horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter }

                    Row {
                      width: (parent.width - score.width - Style.space(12)) / 2
                      spacing: Style.space(6)
                      layoutDirection: Qt.RightToLeft
                      anchors.verticalCenter: parent.verticalCenter
                      Image {
                        source: modelData.awayLogo || ""
                        width: Style.space(22); height: Style.space(22)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        mipmap: true
                        smooth: true
                        sourceSize.width: Style.space(64)
                        sourceSize.height: Style.space(64)
                        visible: source != ""
                        anchors.verticalCenter: parent.verticalCenter
                      }
                      Text {
                        width: parent.width - ((modelData.awayLogo && modelData.awayLogo !== "") ? Style.space(28) : 0)
                        text: modelData.away; color: Commons.Color.foreground
                        font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                      }
                    }
                  }
                }
              }
            }

            Repeater {
              model: root.matchScope === "day" ? Model.groupMatchesByLeague(root.matches, root.selectedLeagues) : []
              delegate: Column {
                required property var modelData
                width: mainColumn.width
                spacing: Style.space(6)

                Rectangle {
                  width: parent.width
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.08)
                  border.width: 1
                  border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25)
                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(8)
                    Image {
                      id: grpLeagueLogo
                      source: modelData.leagueLogo || Model.leagueLogo(modelData.leagueId)
                      width: Style.space(22); height: Style.space(22)
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      mipmap: true
                      smooth: true
                      sourceSize.width: Style.space(64)
                      sourceSize.height: Style.space(64)
                      visible: source != ""
                      anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                      text: modelData.leagueName + (modelData.round ? " · " + modelData.round : "")
                      color: Commons.Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                      width: parent.width - (grpLeagueLogo.visible ? Style.space(30) : 0) - badgeRect.width - Style.space(16)
                      anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                      id: badgeRect
                      height: badgeText.implicitHeight + Style.space(4)
                      width: badgeText.implicitWidth + Style.space(10)
                      radius: Style.cornerRadius
                      color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.15)
                      anchors.verticalCenter: parent.verticalCenter
                      Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: modelData.matches.length + (modelData.matches.length === 1 ? " match" : " matches")
                        color: Commons.Color.accent
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                  }
                }

                Column {
                  width: parent.width
                  spacing: Style.space(6)
                  Repeater {
                    model: modelData.matches
                    delegate: matchCardComponent
                  }
                }
              }
            }

            Repeater {
              model: (root.matchScope === "upcoming" || root.matchScope === "team" || root.matchScope === "league") ? root.matches : []
              delegate: matchCardComponent
            }
          }

          Column {
            visible: root.showingSettings && !root.showingMatchCenter
            width: parent.width
            spacing: Style.space(12)
            Text { text: "Favourite leagues"; color: Commons.Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true }
            Text { text: "Popular competitions are ready immediately. Search to find others; teams follow your selected leagues."; color: Commons.Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap }
            Row {
              width: parent.width
              spacing: Style.space(8)
              TextField {
                width: parent.width - clearLeaguesButton.implicitWidth - parent.spacing
                placeholderText: "Search leagues by name…"
                text: root.leagueSearchFilter
                onTextChanged: { root.leagueSearchFilter = text; root.leagueSearchCompleted = ""; root.leagueSearchTimer.restart() }
              }
              Button {
                id: clearLeaguesButton
                text: "Clear"
                bordered: true
                enabled: root.selectedLeagues.length > 0
                onClicked: root.clearSelectedLeagues()
              }
            }
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

          // Dedicated Single Page Match Center View
          Column {
            id: matchCenterView
            visible: root.showingMatchCenter
            width: parent.width
            spacing: Style.space(12)

            // Navigation bar: Back button + League/Round badge
            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: "◀ Back to Matches"
                bordered: true
                onClicked: { root.showingMatchCenter = false }
              }

              Item { width: Style.space(2); height: 1 }

              Rectangle {
                visible: Boolean(root.activeMatch && root.activeMatch.round)
                radius: Style.cornerRadius
                height: Style.space(24)
                width: roundCenterText.implicitWidth + Style.space(14)
                color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.15)
                border.color: Commons.Color.accent
                border.width: 1
                Text {
                  id: roundCenterText
                  anchors.centerIn: parent
                  text: root.activeMatch ? ((root.activeMatch.leagueName ? (root.activeMatch.leagueName + " · ") : (root.activeMatch.league ? (root.activeMatch.league + " · ") : "")) + (root.activeMatch.round || "")) : ""
                  color: Commons.Color.accent
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            // Scoreboard Hero Card
            Rectangle {
              width: parent.width
              height: heroCardCol.implicitHeight + Style.space(24)
              radius: Style.cornerRadius
              color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.85)
              border.color: (root.activeMatch && root.activeMatch.state === "in") ? "#22C55E" : Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.25)
              border.width: (root.activeMatch && root.activeMatch.state === "in") ? 2 : 1

              Column {
                id: heroCardCol
                width: parent.width - Style.space(24)
                x: Style.space(12)
                y: Style.space(12)
                spacing: Style.space(10)

                // Top state & venue
                Item {
                  width: parent.width
                  height: Style.space(22)

                  Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: Style.space(20)
                    radius: Style.cornerRadius
                    width: heroStatusBadge.implicitWidth + Style.space(12)
                    color: (root.activeMatch && root.activeMatch.state === "in") ? Qt.rgba(0.13, 0.77, 0.36, 0.18) : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.08)
                    border.color: (root.activeMatch && root.activeMatch.state === "in") ? "#22C55E" : "transparent"
                    border.width: 1
                    Text {
                      id: heroStatusBadge
                      anchors.centerIn: parent
                      text: {
                        if (!root.activeMatch) return "Upcoming"
                        if (root.activeMatch.state === "in") {
                          return "● LIVE · " + (root.activeMatch.detail || "")
                        }
                        if (root.activeMatch.state === "post") {
                          return "🏁 " + (root.activeMatch.detail || "Full Time")
                        }
                        if (root.activeMatch.date) {
                          var d = new Date(root.activeMatch.date)
                          if (!isNaN(d.getTime())) {
                            return "⏱ " + Model.formatDayLabel(d) + " · " + Model.formatMatchTime(root.activeMatch.date)
                          }
                        }
                        return "⏱ " + (root.activeMatch.detail && root.activeMatch.detail.indexOf("EST") < 0 && root.activeMatch.detail.indexOf("EDT") < 0 ? root.activeMatch.detail : "Upcoming")
                      }
                      color: (root.activeMatch && root.activeMatch.state === "in") ? "#22C55E" : Commons.Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Boolean(root.activeMatch && root.activeMatch.venue)
                    text: root.activeMatch ? ("📍 " + (root.activeMatch.venue || "")) : ""
                    color: Commons.Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideLeft
                    width: Math.min(implicitWidth, parent.width * 0.5)
                  }
                }

                // Teams and Score Row
                Item {
                  width: parent.width
                  height: Math.max(homeTeamCol.implicitHeight, awayTeamCol.implicitHeight, centerScoreArea.implicitHeight)

                  // Home team
                  Column {
                    id: homeTeamCol
                    width: (parent.width - centerScoreArea.width - Style.space(16)) / 2
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Image {
                      source: (root.activeMatch && root.activeMatch.homeLogo) ? root.activeMatch.homeLogo : ""
                      width: Style.space(42); height: Style.space(42)
                      anchors.horizontalCenter: parent.horizontalCenter
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      mipmap: true
                      smooth: true
                      visible: source != ""
                    }
                    Text {
                      width: parent.width
                      text: root.activeMatch ? (root.activeMatch.home || "") : ""
                      color: Commons.Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      horizontalAlignment: Text.AlignHCenter
                      wrapMode: Text.Wrap
                    }
                  }

                  // Center Score / VS
                  Column {
                    id: centerScoreArea
                    width: Style.space(90)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(4)

                    Text {
                      width: parent.width
                      visible: root.activeMatch && root.activeMatch.state !== "pre" && (root.activeMatch.homeScore !== undefined && root.activeMatch.homeScore !== "")
                      text: root.activeMatch ? ((root.activeMatch.homeScore || "0") + " - " + (root.activeMatch.awayScore || "0")) : ""
                      color: (root.activeMatch && root.activeMatch.state === "in") ? "#22C55E" : Commons.Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.heading * 1.4
                      font.bold: true
                      horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                      width: parent.width
                      visible: !root.activeMatch || root.activeMatch.state === "pre" || (root.activeMatch.homeScore === undefined || root.activeMatch.homeScore === "")
                      text: (root.activeMatch && root.activeMatch.state === "pre" && root.activeMatch.date) ? Model.formatMatchTime(root.activeMatch.date) : "VS"
                      color: (root.activeMatch && root.activeMatch.state === "pre" && root.activeMatch.date) ? Commons.Color.accent : Commons.Color.muted
                      font.family: Style.font.family
                      font.pixelSize: (root.activeMatch && root.activeMatch.state === "pre" && root.activeMatch.date) ? (Style.font.heading * 1.3) : Style.font.heading
                      font.bold: true
                      horizontalAlignment: Text.AlignHCenter
                    }
                  }

                  // Away team
                  Column {
                    id: awayTeamCol
                    width: (parent.width - centerScoreArea.width - Style.space(16)) / 2
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Image {
                      source: (root.activeMatch && root.activeMatch.awayLogo) ? root.activeMatch.awayLogo : ""
                      width: Style.space(42); height: Style.space(42)
                      anchors.horizontalCenter: parent.horizontalCenter
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      mipmap: true
                      smooth: true
                      visible: source != ""
                    }
                    Text {
                      width: parent.width
                      text: root.activeMatch ? (root.activeMatch.away || "") : ""
                      color: Commons.Color.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                      horizontalAlignment: Text.AlignHCenter
                      wrapMode: Text.Wrap
                    }
                  }
                }
              }
            }

            // Tab Buttons: Timeline, Stats, Lineups
            Row {
              width: parent.width
              spacing: Style.space(6)

              readonly property var tabDefs: [
                { id: "timeline", label: "⚽ Timeline" },
                { id: "stats", label: "📊 Stats" },
                { id: "lineup", label: "👥 Lineups" }
              ]

              Repeater {
                model: parent.tabDefs
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool active: root.matchCenterTab === modelData.id
                  width: (mainColumn.width - Style.space(12)) / 3
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: active ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.22) : Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.6)
                  border.color: active ? Commons.Color.accent : Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.25)
                  border.width: active ? 2 : 1

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.matchCenterTab = modelData.id
                  }

                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: active ? Commons.Color.accent : Commons.Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: active
                  }
                }
              }
            }

            // Loading indicator
            Rectangle {
              visible: root.isLoadingMatchDetails
              width: parent.width
              height: Style.space(60)
              radius: Style.cornerRadius
              color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.5)
              border.color: Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.15)
              border.width: 1
              Text {
                anchors.centerIn: parent
                text: "Loading match events, statistics & lineups…"
                color: Commons.Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }

            // Tab 1: Timeline with Central Vertical Line
            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: !root.isLoadingMatchDetails && root.matchCenterTab === "timeline"

              // Empty state
              Rectangle {
                visible: !root.selectedMatchDetails || !root.selectedMatchDetails.events || root.selectedMatchDetails.events.length === 0
                width: parent.width
                height: Style.space(80)
                radius: Style.cornerRadius
                color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.5)
                border.color: Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.2)
                border.width: 1
                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(4)
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (root.activeMatch && root.activeMatch.state === "pre") ? "Match has not started yet" : "No key events recorded yet"
                    color: Commons.Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (root.activeMatch && root.activeMatch.state === "pre") ? "Goals and cards will appear on the timeline during live match play." : "No goals or cards were logged for this fixture."
                    color: Commons.Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              // Timeline Container with vertical bar in center
              Item {
                visible: root.selectedMatchDetails && root.selectedMatchDetails.events && root.selectedMatchDetails.events.length > 0
                width: parent.width
                height: timelineColumn.implicitHeight + Style.space(20)

                // Central Vertical Line Bar
                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: 2
                  color: Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.3)
                }

                // Events Column
                Column {
                  id: timelineColumn
                  width: parent.width
                  spacing: Style.space(12)
                  anchors.horizontalCenter: parent.horizontalCenter

                  Repeater {
                    model: (root.selectedMatchDetails && root.selectedMatchDetails.events) ? root.selectedMatchDetails.events : []
                    delegate: Item {
                      required property var modelData
                      width: timelineColumn.width
                      height: Math.max(minuteBadge.height, Math.max(homeSideContent.implicitHeight, awaySideContent.implicitHeight))

                      readonly property bool isHome: modelData.side === "home"
                      readonly property bool isAway: modelData.side === "away"

                      // Center Minute Badge
                      Rectangle {
                        id: minuteBadge
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(minuteText.implicitWidth + Style.space(12), Style.space(44))
                        height: Style.space(22)
                        radius: Style.cornerRadius
                        color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.95)
                        border.color: modelData.type === "goal" ? Commons.Color.accent : (modelData.type === "red-card" ? "#EF4444" : "#EAB308")
                        border.width: 1

                        Text {
                          id: minuteText
                          anchors.centerIn: parent
                          text: modelData.clock || "-"
                          color: Commons.Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }

                      // Home Side (Left of center badge)
                      Row {
                        id: homeSideContent
                        visible: isHome
                        anchors.right: minuteBadge.left
                        anchors.rightMargin: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        width: (parent.width - minuteBadge.width) / 2 - Style.space(16)
                        spacing: Style.space(6)
                        layoutDirection: Qt.RightToLeft

                        // Event Icon
                        Text {
                          text: modelData.type === "goal" ? "⚽" : (modelData.type === "red-card" ? "🟥" : "🟨")
                          font.pixelSize: Style.font.body
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        // Player details
                        Column {
                          width: parent.width - Style.space(28)
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: 1

                          Text {
                            width: parent.width
                            text: modelData.player
                            color: Commons.Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignRight
                          }
                          Text {
                            visible: Boolean(modelData.assist)
                            width: parent.width
                            text: "Assist: " + modelData.assist
                            color: Commons.Color.muted
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignRight
                          }
                        }
                      }

                      // Away Side (Right of center badge)
                      Row {
                        id: awaySideContent
                        visible: isAway
                        anchors.left: minuteBadge.right
                        anchors.leftMargin: Style.space(10)
                        anchors.verticalCenter: parent.verticalCenter
                        width: (parent.width - minuteBadge.width) / 2 - Style.space(16)
                        spacing: Style.space(6)

                        // Event Icon
                        Text {
                          text: modelData.type === "goal" ? "⚽" : (modelData.type === "red-card" ? "🟥" : "🟨")
                          font.pixelSize: Style.font.body
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        // Player details
                        Column {
                          width: parent.width - Style.space(28)
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: 1

                          Text {
                            width: parent.width
                            text: modelData.player
                            color: Commons.Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignLeft
                          }
                          Text {
                            visible: Boolean(modelData.assist)
                            width: parent.width
                            text: "Assist: " + modelData.assist
                            color: Commons.Color.muted
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignLeft
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            // Tab 2: Statistics
            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: !root.isLoadingMatchDetails && root.matchCenterTab === "stats"

              Rectangle {
                visible: !root.selectedMatchDetails || !root.selectedMatchDetails.stats || root.selectedMatchDetails.stats.length === 0
                width: parent.width
                height: Style.space(80)
                radius: Style.cornerRadius
                color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.5)
                border.color: Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.2)
                border.width: 1
                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(4)
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No statistics available"
                    color: Commons.Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (root.activeMatch && root.activeMatch.state === "pre") ? "Live statistics will appear once the game kicks off." : "Statistical metrics are not provided for this fixture."
                    color: Commons.Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Rectangle {
                visible: root.selectedMatchDetails && root.selectedMatchDetails.stats && root.selectedMatchDetails.stats.length > 0
                width: parent.width
                implicitHeight: statsColDetails.implicitHeight + Style.space(20)
                radius: Style.cornerRadius
                color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.75)
                border.color: Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.25)
                border.width: 1

                Column {
                  id: statsColDetails
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(12)

                  Repeater {
                    model: (root.selectedMatchDetails && root.selectedMatchDetails.stats) ? root.selectedMatchDetails.stats : []
                    delegate: Column {
                      required property var modelData
                      width: parent.width
                      spacing: Style.space(3)

                      Row {
                        width: parent.width
                        Text {
                          width: Style.space(50)
                          text: modelData.home
                          color: Commons.Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                          horizontalAlignment: Text.AlignLeft
                        }
                        Text {
                          width: parent.width - Style.space(100)
                          text: modelData.name
                          color: Commons.Color.muted
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                          width: Style.space(50)
                          text: modelData.away
                          color: Commons.Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          font.bold: true
                          horizontalAlignment: Text.AlignRight
                        }
                      }

                      Rectangle {
                        width: parent.width
                        height: Style.space(6)
                        radius: 3
                        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.12)

                        Rectangle {
                          width: Math.max(0, Math.min(parent.width, parent.width * (modelData.homePct / 100)))
                          height: parent.height
                          radius: 3
                          color: Commons.Color.accent
                        }
                      }
                    }
                  }
                }
              }
            }

            // Tab 3: Lineups
            Column {
              width: parent.width
              spacing: Style.space(10)
              visible: !root.isLoadingMatchDetails && root.matchCenterTab === "lineup"

              // Lineups not announced empty state
              Rectangle {
                visible: !root.hasActiveLineup
                width: parent.width
                height: Style.space(80)
                radius: Style.cornerRadius
                color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.5)
                border.color: Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.2)
                border.width: 1
                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(4)
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Lineups not announced yet"
                    color: Commons.Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Official starting lineups and substitutes are typically published ~60 minutes before kickoff."
                    color: Commons.Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              // Formations & Managers Header
              Rectangle {
                visible: root.hasActiveLineup
                width: parent.width
                implicitHeight: formRowHeader.implicitHeight + Style.space(14)
                radius: Style.cornerRadius
                color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.7)
                border.color: Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.2)
                border.width: 1

                Row {
                  id: formRowHeader
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(8)

                  // Home Formation & Coach
                  Column {
                    width: (parent.width - Style.space(8)) / 2
                    spacing: 2
                    Text {
                      text: (root.activeLineup ? (root.activeLineup.homeFormation ? ("Formation: " + root.activeLineup.homeFormation) : "Starting XI") : "")
                      color: Commons.Color.accent
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    Text {
                      visible: Boolean(root.activeLineup && root.activeLineup.homeCoach)
                      text: "Coach: " + (root.activeLineup ? root.activeLineup.homeCoach : "")
                      color: Commons.Color.muted
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: parent.width
                    }
                  }

                  // Away Formation & Coach
                  Column {
                    width: (parent.width - Style.space(8)) / 2
                    spacing: 2
                    Text {
                      text: (root.activeLineup ? (root.activeLineup.awayFormation ? ("Formation: " + root.activeLineup.awayFormation) : "Starting XI") : "")
                      color: Commons.Color.accent
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      horizontalAlignment: Text.AlignRight
                      width: parent.width
                    }
                    Text {
                      visible: Boolean(root.activeLineup && root.activeLineup.awayCoach)
                      text: "Coach: " + (root.activeLineup ? root.activeLineup.awayCoach : "")
                      color: Commons.Color.muted
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      horizontalAlignment: Text.AlignRight
                      width: parent.width
                    }
                  }
                }
              }

              // Starting XI Label
              Text {
                visible: root.hasActiveLineup
                text: "STARTING XI"
                color: Commons.Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              // Starting XI: 2 Columns
              Row {
                visible: root.hasActiveLineup
                width: parent.width
                spacing: Style.space(8)

                // Home Starters
                Column {
                  width: (parent.width - Style.space(8)) / 2
                  spacing: Style.space(4)

                  Repeater {
                    model: (root.activeLineup && root.activeLineup.homeStarters) ? root.activeLineup.homeStarters : []
                    delegate: Rectangle {
                      required property var modelData
                      width: parent.width
                      height: Style.space(26)
                      radius: Style.cornerRadius
                      color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.6)
                      border.color: Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.15)
                      border.width: 1

                      Row {
                        anchors.fill: parent
                        anchors.margins: Style.space(4)
                        spacing: Style.space(4)

                        Rectangle {
                          width: Style.space(20); height: Style.space(18)
                          radius: 3
                          color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.15)
                          anchors.verticalCenter: parent.verticalCenter
                          Text {
                            anchors.centerIn: parent
                            text: modelData.number || "-"
                            color: Commons.Color.accent
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            font.bold: true
                          }
                        }

                        Text {
                          width: parent.width - Style.space(48)
                          text: modelData.name
                          color: Commons.Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          visible: Boolean(modelData.pos)
                          text: modelData.pos
                          color: Commons.Color.muted
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          anchors.verticalCenter: parent.verticalCenter
                        }
                      }
                    }
                  }
                }

                // Away Starters
                Column {
                  width: (parent.width - Style.space(8)) / 2
                  spacing: Style.space(4)

                  Repeater {
                    model: (root.activeLineup && root.activeLineup.awayStarters) ? root.activeLineup.awayStarters : []
                    delegate: Rectangle {
                      required property var modelData
                      width: parent.width
                      height: Style.space(26)
                      radius: Style.cornerRadius
                      color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.6)
                      border.color: Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.15)
                      border.width: 1

                      Row {
                        anchors.fill: parent
                        anchors.margins: Style.space(4)
                        spacing: Style.space(4)

                        Rectangle {
                          width: Style.space(20); height: Style.space(18)
                          radius: 3
                          color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.1)
                          anchors.verticalCenter: parent.verticalCenter
                          Text {
                            anchors.centerIn: parent
                            text: modelData.number || "-"
                            color: Commons.Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            font.bold: true
                          }
                        }

                        Text {
                          width: parent.width - Style.space(48)
                          text: modelData.name
                          color: Commons.Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          visible: Boolean(modelData.pos)
                          text: modelData.pos
                          color: Commons.Color.muted
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          anchors.verticalCenter: parent.verticalCenter
                        }
                      }
                    }
                  }
                }
              }

              // Substitutes / Bench Section
              Text {
                visible: root.hasActiveLineup && Boolean((root.activeLineup.homeBench && root.activeLineup.homeBench.length > 0) || (root.activeLineup.awayBench && root.activeLineup.awayBench.length > 0))
                text: "SUBSTITUTES / BENCH"
                color: Commons.Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Row {
                visible: root.hasActiveLineup && Boolean((root.activeLineup.homeBench && root.activeLineup.homeBench.length > 0) || (root.activeLineup.awayBench && root.activeLineup.awayBench.length > 0))
                width: parent.width
                spacing: Style.space(8)

                // Home Bench
                Column {
                  width: (parent.width - Style.space(8)) / 2
                  spacing: Style.space(3)

                  Repeater {
                    model: (root.activeLineup && root.activeLineup.homeBench) ? root.activeLineup.homeBench : []
                    delegate: Rectangle {
                      required property var modelData
                      width: parent.width
                      height: Style.space(24)
                      radius: Style.cornerRadius
                      color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.4)
                      border.color: Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.1)
                      border.width: 1

                      Row {
                        anchors.fill: parent
                        anchors.margins: Style.space(3)
                        spacing: Style.space(4)

                        Text {
                          width: Style.space(18)
                          text: modelData.number || "-"
                          color: Commons.Color.muted
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          horizontalAlignment: Text.AlignHCenter
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          width: parent.width - Style.space(22)
                          text: modelData.name
                          color: Commons.Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                          anchors.verticalCenter: parent.verticalCenter
                        }
                      }
                    }
                  }
                }

                // Away Bench
                Column {
                  width: (parent.width - Style.space(8)) / 2
                  spacing: Style.space(3)

                  Repeater {
                    model: (root.activeLineup && root.activeLineup.awayBench) ? root.activeLineup.awayBench : []
                    delegate: Rectangle {
                      required property var modelData
                      width: parent.width
                      height: Style.space(24)
                      radius: Style.cornerRadius
                      color: Qt.rgba(Commons.Color.menu.r, Commons.Color.menu.g, Commons.Color.menu.b, 0.4)
                      border.color: Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, 0.1)
                      border.width: 1

                      Row {
                        anchors.fill: parent
                        anchors.margins: Style.space(3)
                        spacing: Style.space(4)

                        Text {
                          width: Style.space(18)
                          text: modelData.number || "-"
                          color: Commons.Color.muted
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          horizontalAlignment: Text.AlignHCenter
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                          width: parent.width - Style.space(22)
                          text: modelData.name
                          color: Commons.Color.foreground
                          font.family: Style.font.family
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                          anchors.verticalCenter: parent.verticalCenter
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
