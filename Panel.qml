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
    return p !== "" ? decodeURIComponent(p) : (Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.moduleName + "/api.py")
  }

  // ---------------------------------------------------------------- settings
  property var selectedLeagues: Model.selectedValues(setting("selectedLeagues", Model.defaultSelected()))
  property var favoriteTeams: Model.favoriteTeams(setting("favoriteTeams", []), setting("favoriteTeam", null))
  property bool alertsEnabled: setting("alertsEnabled", true) !== false
  property bool remindersEnabled: setting("remindersEnabled", true) !== false
  property int reminderMinutes: Math.max(5, Math.min(120, Number(setting("reminderMinutes", 15)) || 15))
  property string leagueAlertMode: ["off", "goals", "all"].indexOf(String(setting("leagueAlertMode", "goals"))) >= 0 ? String(setting("leagueAlertMode", "goals")) : "goals"
  readonly property var favoriteIds: favoriteTeams.map(function(t) { return t.id })

  // ---------------------------------------------------------------- ui state
  property string view: "main"            // main | settings | match
  property string tab: "today"             // today | week | teams | fixtures | table
  // Midnight of the current local day.  Updated by the clock timer so the
  // panel (which lives for the whole shell session) never keeps showing
  // yesterday as "Today" after midnight.
  property date today: Model.startOfToday()
  property date selectedDate: Model.startOfToday()
  property date calendarMonth: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
  property bool calendarOpen: false
  property bool liveOnly: false
  property string teamFilter: ""
  property string fixturesLeague: selectedLeagues.length ? selectedLeagues[0] : ""
  property string tableLeague: selectedLeagues.length ? selectedLeagues[0] : ""
  property int clockTick: 0

  // cache: key -> { data, time }
  property var cache: ({})
  property int cacheVersion: 0
  property var errors: ({})
  property var teamMatches: ({})
  property bool pulseLoaded: false

  // match center
  property var currentMatchItem: null
  property string matchTab: "timeline"
  readonly property string matchKey: currentMatchItem ? "md|" + currentMatchItem.leagueId + "|" + currentMatchItem.id : ""
  readonly property var matchDetails: { cacheVersion; return matchKey && cache[matchKey] ? cache[matchKey].data : null }
  readonly property var activeMatch: (matchDetails && matchDetails.id) ? matchDetails : currentMatchItem
  readonly property var activeLineup: (matchDetails && matchDetails.lineup) ? matchDetails.lineup : null
  readonly property bool hasLineup: Boolean(activeLineup && activeLineup.available)

  // settings view
  property string teamQuery: ""
  property var teamResults: []
  property string teamResultsQuery: ""
  property string leagueQuery: ""
  property var extraLeagues: []

  property string label: {
    clockTick
    if (!pulseLoaded && favoriteTeams.length) return favoriteTeams[0].short
    return Model.formatBarLabel(teamMatches, favoriteTeams)
  }
  readonly property bool opened: root.controller.open

  // ---------------------------------------------------------------- open/close
  function openFromHotkey() { open() }
  function open() {
    root.controller.open = true
    checkDayRollover()
    refreshCurrent()
    prefetch()
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }
  function close() { root.controller.open = false; view = "main"; calendarOpen = false }
  function toggle() { opened ? close() : open() }
  function closeForPopoutSwitch() { close() }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }
  function setView(v) { view = v; Qt.callLater(function() { bodyFlick.contentY = 0 }) }

  function persistSettings() {
    var entry = { id: moduleName, selectedLeagues: selectedLeagues, favoriteTeams: favoriteTeams, favoriteTeam: null,
                  alertsEnabled: alertsEnabled, remindersEnabled: remindersEnabled, reminderMinutes: reminderMinutes,
                  leagueAlertMode: leagueAlertMode }
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
  }

  // ---------------------------------------------------------------- data keys
  function weekRange() {
    var start = new Date(); start.setHours(0, 0, 0, 0)
    var end = new Date(start); end.setDate(end.getDate() + 6)
    return Model.formatDateParam(start) + "-" + Model.formatDateParam(end)
  }
  function keyFor(t) {
    if (t === "today") return "day|" + selectedLeagues.join(",") + "|" + Model.formatDateParam(selectedDate)
    if (t === "week") return "week|" + selectedLeagues.join(",") + "|" + weekRange()
    if (t === "teams") return "teams|" + Model.teamSpecs(favoriteTeams)
    if (t === "fixtures") return "fix|" + fixturesLeague
    if (t === "table") return "table|" + tableLeague
    return ""
  }
  function argsFor(key) {
    var parts = key.split("|")
    if (parts[0] === "day" || parts[0] === "week") return ["matches", parts[1], parts[2], ""]
    if (parts[0] === "teams") return ["team-matches", parts[1], "6", "10"]
    if (parts[0] === "fix") return ["league-matches", parts[1], "21"]
    if (parts[0] === "table") return ["standings", parts[1]]
    if (parts[0] === "md") return ["match-details", parts[1], parts[2]]
    return []
  }
  readonly property string currentKey: keyFor(tab)
  readonly property var currentEntry: { cacheVersion; return cache[currentKey] || null }
  readonly property var currentData: currentEntry && Array.isArray(currentEntry.data) ? currentEntry.data : []
  readonly property bool currentLoading: currentEntry === null && (listFetcher.busy || tableFetcher.busy)
  readonly property bool refreshing: listFetcher.busy || tableFetcher.busy || detailsFetcher.busy

  function store(key, data) {
    var c = cache
    c[key] = { data: data, time: Date.now() }
    // keep the cache bounded
    var keys = Object.keys(c)
    if (keys.length > 60) {
      keys.sort(function(a, b) { return c[a].time - c[b].time })
      for (var i = 0; i < keys.length - 60; i++) delete c[keys[i]]
    }
    cache = c
    cacheVersion++
  }
  function isFresh(key, maxAgeMs) {
    var e = cache[key]
    return e && (Date.now() - e.time) < maxAgeMs
  }
  function request(key, force) {
    if (!key || key.split("|")[1] === "") return
    if (!force && isFresh(key, 15000)) return
    var fetcher = key.indexOf("table|") === 0 ? tableFetcher : (key.indexOf("md|") === 0 ? detailsFetcher : listFetcher)
    fetcher.request(key, argsFor(key))
  }
  function refreshCurrent(force) {
    if (view === "match") { request(matchKey, true); return }
    if ((tab === "today" || tab === "week") && selectedLeagues.length === 0) return
    if (tab === "teams" && favoriteTeams.length === 0) return
    request(currentKey, force === true)
  }
  function refreshAll() { refreshCurrent(true); runPulse() }
  function prefetch() {
    // Warm the other common tabs in the background so switching is instant.
    var keys = []
    if (favoriteTeams.length) keys.push(keyFor("teams"))
    if (selectedLeagues.length) keys.push(keyFor("today"))
    for (var i = 0; i < keys.length; i++) {
      if (keys[i] !== currentKey && !isFresh(keys[i], 60000)) { warmFetcher.request(keys[i], argsFor(keys[i])); break }
    }
  }

  // Parse in this context so arrays stay real JS arrays.
  function parse(text) {
    try {
      var data = JSON.parse(text)
      if (data === null || data === undefined || (typeof data === "object" && !Array.isArray(data) && data.error)) return null
      return data
    } catch (e) { return null }
  }
  function onFetched(key, text) {
    var data = parse(text)
    if (data !== null) {
      store(key, data)
      if (errors[key]) { var e = errors; delete e[key]; errors = e }
    } else if (!cache[key]) {
      var e2 = errors; e2[key] = true; errors = e2
      cacheVersion++
    }
  }

  Fetcher { id: listFetcher; scriptPath: root.scriptPath; onDone: function(key, text) { root.onFetched(key, text) } }
  Fetcher { id: tableFetcher; scriptPath: root.scriptPath; onDone: function(key, text) { root.onFetched(key, text) } }
  Fetcher { id: detailsFetcher; scriptPath: root.scriptPath; onDone: function(key, text) { root.onFetched(key, text) } }
  Fetcher {
    id: warmFetcher; scriptPath: root.scriptPath
    onDone: function(key, text) { var d = root.parse(text); if (d !== null) root.store(key, d); root.prefetch() }
  }
  Fetcher {
    id: searchFetcher; scriptPath: root.scriptPath
    onDone: function(key, text) {
      if (key !== root.teamQuery.trim()) return
      var d = root.parse(text)
      root.teamResults = Array.isArray(d) ? d : []
      root.teamResultsQuery = key
    }
  }
  Fetcher {
    id: leaguesFetcher; scriptPath: root.scriptPath
    onDone: function(key, text) { var d = root.parse(text); root.extraLeagues = Array.isArray(d) ? d : [] }
  }
  Fetcher {
    id: pulseFetcher; scriptPath: root.scriptPath
    onDone: function(key, text) {
      var data = root.parse(text)
      if (!data) { pulseTimer.interval = 60000; pulseTimer.restart(); return }
      root.teamMatches = data.teams || {}
      root.pulseLoaded = true
      var secs = Math.max(20, Math.min(600, Number(data.nextPoll) || 300))
      pulseTimer.interval = secs * 1000
      pulseTimer.restart()
    }
  }

  function runPulse() {
    var opts = JSON.stringify({ alerts: alertsEnabled, reminders: remindersEnabled, reminderMinutes: reminderMinutes,
                                leagueMode: alertsEnabled ? leagueAlertMode : "off" })
    pulseFetcher.request("pulse", ["pulse", Model.teamSpecs(favoriteTeams), selectedLeagues.join(","), opts])
  }

  Timer { id: pulseTimer; interval: 300000; repeat: false; running: true; onTriggered: root.runPulse() }
  Timer { interval: 60000; running: true; repeat: true; onTriggered: { root.checkDayRollover(); root.clockTick++ } }
  Timer {
    // Keep what is on screen fresh while the panel is open.
    interval: root.view === "match" ? 30000 : (root.hasLiveOnScreen() ? 30000 : 120000)
    running: root.opened && (root.view !== "match" || (root.activeMatch && root.activeMatch.state === "in"))
    repeat: true
    onTriggered: root.refreshCurrent(true)
  }
  Timer { id: teamSearchTimer; interval: 350; onTriggered: root.searchTeams() }
  Component.onCompleted: Qt.callLater(runPulse)

  function hasLiveOnScreen() {
    var d = currentData
    for (var i = 0; i < d.length; i++) if (d[i] && d[i].state === "in") return true
    return false
  }

  // ---------------------------------------------------------------- actions
  function setTab(t) {
    tab = t
    calendarOpen = false
    refreshCurrent()
  }
  function pickDate(d) {
    selectedDate = new Date(d.getFullYear(), d.getMonth(), d.getDate())
    calendarMonth = new Date(d.getFullYear(), d.getMonth(), 1)
    calendarOpen = false
    refreshCurrent()
  }
  function checkDayRollover() {
    var now = Model.startOfToday()
    if (Model.sameLocalDay(now, today)) return
    var followToday = Model.sameLocalDay(selectedDate, today)
    today = now
    if (followToday) selectedDate = now
    if (opened) refreshCurrent()
  }
  function shiftDay(n) {
    pickDate(new Date(selectedDate.getFullYear(), selectedDate.getMonth(), selectedDate.getDate() + n))
  }
  // "Today" / "Tomorrow" / "Yesterday", otherwise the weekday name.
  function dayTitle(d) {
    var rel = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - today) / 86400000)
    if (rel === 0) return "Today"
    if (rel === 1) return "Tomorrow"
    if (rel === -1) return "Yesterday"
    return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][d.getDay()]
  }
  readonly property bool selectedIsToday: Model.sameLocalDay(selectedDate, today)
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
  function setFixturesLeague(id) { fixturesLeague = id; refreshCurrent() }
  function setTableLeague(id) { tableLeague = id; refreshCurrent() }

  function isFavorite(id) { return favoriteIds.indexOf(String(id)) >= 0 }
  function toggleFavorite(team) {
    var list = favoriteTeams.slice(0), idx = -1
    for (var i = 0; i < list.length; i++) if (list[i].id === String(team.id)) idx = i
    if (idx >= 0) list.splice(idx, 1)
    else {
      if (list.length >= 12) return
      var clean = Model.cleanTeam(team)
      if (clean) list.push(clean)
    }
    favoriteTeams = list
    if (teamFilter && !isFavorite(teamFilter)) teamFilter = ""
    persistSettings()
    runPulse()
  }
  function moveFavorite(index, delta) {
    var list = favoriteTeams.slice(0), j = index + delta
    if (j < 0 || j >= list.length) return
    var t = list[index]; list[index] = list[j]; list[j] = t
    favoriteTeams = list
    persistSettings()
  }
  function toggleLeague(id) {
    var next = selectedLeagues.filter(function(l) { return l !== id })
    if (next.length === selectedLeagues.length) next.push(id)
    selectedLeagues = next
    if (next.indexOf(fixturesLeague) < 0) fixturesLeague = next.length ? next[0] : ""
    if (next.indexOf(tableLeague) < 0) tableLeague = next.length ? next[0] : ""
    persistSettings()
  }
  function searchTeams() {
    var q = teamQuery.trim()
    if (q.length < 2) { teamResults = []; teamResultsQuery = ""; return }
    searchFetcher.request(q, ["search-teams", q])
  }
  function combinedTeamResults() {
    var q = teamQuery.trim(), out = [], seen = {}
    var local = Model.popularMatching(q)
    for (var i = 0; i < local.length; i++) { seen[local[i].id] = true; out.push(local[i]) }
    if (teamResultsQuery === q) for (var j = 0; j < teamResults.length; j++) {
      var t = teamResults[j]
      if (!seen[t.id]) { seen[t.id] = true; out.push(t) }
    }
    return out
  }
  function leagueSearch() {
    var q = leagueQuery.trim()
    if (q.length >= 3 && extraLeagues.length === 0 && !leaguesFetcher.busy) leaguesFetcher.request("leagues", ["leagues", "300"])
  }
  function extraLeagueResults() {
    var q = leagueQuery.trim().toLowerCase(), out = []
    if (q.length < 3) return out
    for (var i = 0; i < extraLeagues.length && out.length < 20; i++) {
      var l = extraLeagues[i]
      if (Model.findLeague(l.id)) continue
      if (l.name.toLowerCase().indexOf(q) >= 0 || l.id.indexOf(q) >= 0) out.push(l)
    }
    return out
  }

  function openMatch(match) {
    if (!match || !match.id) return
    currentMatchItem = {
      id: String(match.id), leagueId: match.leagueId || "all",
      leagueName: Model.findLeague(match.leagueId) ? Model.leagueName(match.leagueId) : (match.league || match.leagueName || ""),
      round: match.round || "", state: match.state || "pre", date: match.date || "",
      detail: match.detail || "", clock: match.clock || "",
      home: match.home || "Home", away: match.away || "Away",
      homeId: match.homeId || "", awayId: match.awayId || "",
      homeLogo: match.homeLogo || "", awayLogo: match.awayLogo || "",
      homeScore: match.homeScore !== undefined ? String(match.homeScore) : "",
      awayScore: match.awayScore !== undefined ? String(match.awayScore) : "",
      venue: match.venue || ""
    }
    matchTab = currentMatchItem.state === "pre" ? "lineup" : "timeline"
    setView("match")
    request(matchKey, true)
  }

  // ---------------------------------------------------------------- derived
  function visibleDayMatches() {
    var d = currentData
    if (!liveOnly) return d
    return d.filter(function(m) { return m.state === "in" })
  }
  function liveCount() {
    var n = 0, d = currentData
    for (var i = 0; i < d.length; i++) if (d[i].state === "in") n++
    return n
  }
  function teamTabMatches(group) {
    var d = currentData, out = []
    for (var i = 0; i < d.length; i++) {
      var m = d[i]
      if (teamFilter && String(m.homeId) !== teamFilter && String(m.awayId) !== teamFilter) continue
      var g = m.group === "result" ? "result" : "upcoming"
      if (g === group) out.push(m)
    }
    if (group === "result") out.reverse()
    // With several teams, keep both sections short so recent results stay in view.
    if (!teamFilter && favoriteTeams.length > 1) out = out.slice(0, 6)
    return out
  }
  function zoneLegend() {
    var seen = {}, out = [], d = tab === "table" ? currentData : []
    for (var i = 0; i < d.length; i++) {
      var r = d[i]
      if (r.note && r.noteColor && !seen[r.note]) { seen[r.note] = true; out.push({ note: r.note, color: r.noteColor }) }
    }
    return out
  }

  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color liveColor: "#ef4444"
  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // ======================================================================== UI
  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    centerOnBar: false
    contentWidth: popup.fittedContentWidth(Style.space(560))
    contentHeight: popup.fittedContentHeight(header.height + Style.space(10) + bodyColumn.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.view !== "main") root.setView("main")
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0 && root.view === "main" && root.tab === "today") root.shiftDay(dx)
      }

      // ------------------------------------------------------------ header
      Item {
        id: header
        width: parent.width
        height: Style.space(34)

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)
          Button {
            visible: root.view !== "main"
            iconText: "󰁍"
            tooltipText: "Back"
            bordered: true
            onClicked: root.setView("main")
            anchors.verticalCenter: parent.verticalCenter
          }
          PText {
            visible: root.view === "main"
            text: "\uf1e3"
            color: root.accent
            font.pixelSize: Style.font.heading
            anchors.verticalCenter: parent.verticalCenter
          }
          PText {
            text: root.view === "settings" ? "Settings" : (root.view === "match" ? "Match centre" : "Football")
            font.pixelSize: Style.font.heading
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
          PText {
            visible: root.refreshing
            text: "updating…"
            font.pixelSize: Style.font.caption
            color: Commons.Color.muted
            anchors.verticalCenter: parent.verticalCenter
          }
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          Button {
            iconText: "󰑐"
            tooltipText: "Refresh"
            bordered: true
            iconSpinning: root.refreshing
            onClicked: root.refreshAll()
          }
          Button {
            visible: root.view !== "settings"
            iconText: "󰒓"
            tooltipText: "Teams, competitions and alerts"
            bordered: true
            onClicked: root.setView("settings")
          }
        }
      }

      Flickable {
        id: bodyFlick
        anchors.top: header.bottom
        anchors.topMargin: Style.space(10)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: bodyColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        Column {
          id: bodyColumn
          width: bodyFlick.width - Style.space(6)
          spacing: Style.space(12)

          // ================================================== MAIN VIEW
          Column {
            visible: root.view === "main"
            width: parent.width
            spacing: Style.space(12)

            // ---- My teams strip ----
            Rectangle {
              visible: root.favoriteTeams.length === 0
              width: parent.width
              implicitHeight: emptyFav.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: root.tint(root.accent, 0.08)
              border.width: 1
              border.color: root.tint(root.accent, 0.35)
              Row {
                id: emptyFav
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                spacing: Style.space(10)
                PText { text: "⭐"; font.pixelSize: Style.font.heading; anchors.verticalCenter: parent.verticalCenter }
                Column {
                  width: bodyColumn.width - Style.space(150)
                  anchors.verticalCenter: parent.verticalCenter
                  PText { text: "Follow your teams"; font.bold: true; width: parent.width }
                  PText { text: "Next matches in the bar and live goal alerts."; color: Commons.Color.muted; font.pixelSize: Style.font.bodySmall; width: parent.width }
                }
                Button { text: "Add teams"; bordered: true; onClicked: root.setView("settings"); anchors.verticalCenter: parent.verticalCenter }
              }
            }

            Flickable {
              visible: root.favoriteTeams.length > 0
              width: parent.width
              height: favRow.height
              contentWidth: favRow.width
              contentHeight: favRow.height
              clip: true
              flickableDirection: Flickable.HorizontalFlick
              boundsBehavior: Flickable.StopAtBounds
              interactive: contentWidth > width
              Row {
                id: favRow
                spacing: Style.space(8)
                Repeater {
                  model: root.favoriteTeams
                  delegate: Rectangle {
                    id: favCard
                    required property var modelData
                    readonly property var m: { root.clockTick; return root.teamMatches[modelData.id] || null }
                    readonly property bool live: !!m && m.state === "in"
                    readonly property bool single: root.favoriteTeams.length === 1
                    width: single ? bodyColumn.width : Math.max(Style.space(168), Math.min(Style.space(210), (bodyColumn.width - Style.space(8)) / 2))
                    height: Style.space(single ? 74 : 70)
                    radius: Style.cornerRadius
                    color: favHover.containsMouse ? root.tint(root.fg, 0.08) : (live ? root.tint(root.liveColor, 0.10) : root.tint(root.accent, 0.07))
                    border.width: 1
                    border.color: live ? root.tint(root.liveColor, 0.6) : root.tint(root.accent, 0.30)

                    MouseArea {
                      id: favHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (favCard.m) root.openMatch(favCard.m)
                        else { root.teamFilter = favCard.modelData.id; root.setTab("teams") }
                      }
                    }
                    Row {
                      anchors.fill: parent
                      anchors.margins: Style.space(8)
                      spacing: Style.space(8)
                      TeamLogo {
                        size: Style.space(favCard.single ? 40 : 30)
                        source: favCard.modelData.logo
                        name: favCard.modelData.name
                        anchors.verticalCenter: parent.verticalCenter
                      }
                      Column {
                        width: parent.width - Style.space(favCard.single ? 48 : 38)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Row {
                          width: parent.width
                          spacing: Style.space(5)
                          Rectangle {
                            visible: favCard.live
                            width: Style.space(7); height: width; radius: width / 2; color: root.liveColor
                            anchors.verticalCenter: parent.verticalCenter
                          }
                          PText {
                            width: parent.width - (favCard.live ? Style.space(12) : 0)
                            text: favCard.modelData.short || favCard.modelData.name
                            font.bold: true
                          }
                        }
                        PText {
                          width: parent.width
                          text: {
                            var m = favCard.m
                            if (!m) return root.pulseLoaded ? "No upcoming match" : "Loading…"
                            if (m.state === "pre") return (m.isHome ? "vs " : "@ ") + m.opponent
                            return m.home + " " + m.homeScore + "–" + m.awayScore + " " + m.away
                          }
                          font.pixelSize: Style.font.bodySmall
                          font.bold: favCard.live
                          color: favCard.live ? root.liveColor : root.fg
                        }
                        PText {
                          width: parent.width
                          text: {
                            var m = favCard.m
                            if (!m) return ""
                            var lg = Model.findLeague(m.leagueId) ? Model.leagueShort(m.leagueId) : m.league
                            if (m.state === "in") return Model.liveLabel(m) + " · " + lg
                            if (m.state === "post") return "Full time · " + lg
                            var c = Model.countdown(m.date)
                            return Model.shortWhen(m.date) + (c && favCard.single ? " (" + c + ")" : "") + " · " + lg
                          }
                          font.pixelSize: Style.font.caption
                          color: Commons.Color.muted
                        }
                      }
                    }
                  }
                }
              }
            }

            // ---- tabs ----
            Row {
              width: parent.width
              spacing: Style.space(4)
              Repeater {
                model: [
                  { id: "today", label: "Matches", icon: "󰃭" },
                  { id: "week", label: "Week", icon: "󰸗" },
                  { id: "teams", label: "My teams", icon: "" },
                  { id: "fixtures", label: "Fixtures", icon: "󰒻" },
                  { id: "table", label: "Table", icon: "󰓫" }
                ]
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool active: root.tab === modelData.id
                  width: (bodyColumn.width - Style.space(16)) / 5
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: active ? root.tint(root.accent, 0.20) : (tabMouse.containsMouse ? root.tint(root.fg, 0.08) : root.tint(root.fg, 0.035))
                  border.width: 1
                  border.color: active ? root.accent : root.tint(root.fg, 0.10)
                  Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                  Row {
                    anchors.centerIn: parent
                    spacing: Style.space(5)
                    PText { text: modelData.icon; color: active ? root.accent : Commons.Color.muted; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
                    PText { text: modelData.label; color: active ? root.accent : root.fg; font.pixelSize: Style.font.bodySmall; font.bold: active; anchors.verticalCenter: parent.verticalCenter }
                  }
                  MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setTab(modelData.id) }
                }
              }
            }

            // ---- tab: today (‹ day › navigator) ----
            Column {
              visible: root.tab === "today"
              width: parent.width
              spacing: Style.space(8)
              Row {
                width: parent.width
                spacing: Style.space(6)
                Button {
                  id: prevDay
                  iconText: "󰅁"
                  tooltipText: "Previous day (←)"
                  bordered: true
                  width: Style.space(42)
                  height: Style.space(42)
                  onClicked: root.shiftDay(-1)
                }
                Rectangle {
                  width: parent.width - prevDay.width - nextDay.width - parent.spacing * 2
                  height: Style.space(42)
                  radius: Style.cornerRadius
                  color: root.calendarOpen ? root.tint(root.accent, 0.22)
                         : (dayMouse.containsMouse ? root.tint(root.fg, 0.08) : root.tint(root.fg, 0.035))
                  border.width: 1
                  border.color: root.calendarOpen || root.selectedIsToday ? root.accent : root.tint(root.fg, 0.10)
                  Behavior on color { ColorAnimation { duration: Style.duration(120) } }
                  Column {
                    anchors.centerIn: parent
                    PText {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: { root.today; return root.dayTitle(root.selectedDate) }
                      font.pixelSize: Style.font.body
                      font.bold: true
                      color: root.selectedIsToday ? root.accent : root.fg
                    }
                    PText {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: Model.shortDays[root.selectedDate.getDay()] + " " + root.selectedDate.getDate() + " "
                            + Model.shortMonths[root.selectedDate.getMonth()] + "  󰃭"
                      font.pixelSize: Style.font.caption
                      color: Commons.Color.muted
                    }
                  }
                  MouseArea {
                    id: dayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.calendarMonth = new Date(root.selectedDate.getFullYear(), root.selectedDate.getMonth(), 1); root.calendarOpen = !root.calendarOpen }
                  }
                }
                Button {
                  id: nextDay
                  iconText: "󰅂"
                  tooltipText: "Next day (→)"
                  bordered: true
                  width: Style.space(42)
                  height: Style.space(42)
                  onClicked: root.shiftDay(1)
                }
              }

              Column {
                visible: root.calendarOpen
                width: parent.width
                spacing: Style.space(6)
                Item {
                  width: parent.width
                  height: Style.space(30)
                  Button { anchors.left: parent.left; iconText: "󰁍"; bordered: true; onClicked: root.calendarMonth = new Date(root.calendarMonth.getFullYear(), root.calendarMonth.getMonth() - 1, 1) }
                  PText { anchors.centerIn: parent; text: Model.formatMonthLabel(root.calendarMonth); font.bold: true }
                  Button { anchors.right: parent.right; iconText: "󰁔"; bordered: true; onClicked: root.calendarMonth = new Date(root.calendarMonth.getFullYear(), root.calendarMonth.getMonth() + 1, 1) }
                }
                Grid {
                  id: calGrid
                  columns: 7
                  width: parent.width
                  spacing: Style.space(3)
                  Repeater {
                    model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                    delegate: PText {
                      required property string modelData
                      width: (calGrid.width - Style.space(18)) / 7
                      horizontalAlignment: Text.AlignHCenter
                      text: modelData
                      font.pixelSize: Style.font.caption
                      color: Commons.Color.muted
                    }
                  }
                  Repeater {
                    model: root.calendarOpen ? root.calendarDays() : []
                    delegate: Rectangle {
                      required property var modelData
                      readonly property bool active: Model.sameLocalDay(modelData.date, root.selectedDate)
                      readonly property bool isToday: Model.sameLocalDay(modelData.date, root.today)
                      width: (calGrid.width - Style.space(18)) / 7
                      height: Style.space(30)
                      radius: Style.cornerRadius
                      opacity: modelData.inMonth ? 1 : 0.4
                      color: active ? root.tint(root.accent, 0.25) : (cellMouse.containsMouse ? root.tint(root.fg, 0.08) : "transparent")
                      border.width: isToday ? 1 : 0
                      border.color: root.accent
                      PText { anchors.centerIn: parent; text: String(modelData.date.getDate()); font.pixelSize: Style.font.bodySmall; font.bold: active }
                      MouseArea { id: cellMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pickDate(modelData.date) }
                    }
                  }
                }
              }

              Row {
                spacing: Style.space(6)
                Chip { text: "All"; selected: !root.liveOnly; onClicked: root.liveOnly = false }
                Chip {
                  text: "Live" + (root.liveCount() ? " (" + root.liveCount() + ")" : "")
                  dot: root.liveCount() > 0
                  selected: root.liveOnly
                  onClicked: root.liveOnly = true
                }
                Chip {
                  visible: !root.selectedIsToday
                  text: "Back to today"
                  trailing: "󰁯"
                  onClicked: root.pickDate(root.today)
                }
              }
            }

            // ---- tab: teams (filter) ----
            Flow {
              visible: root.tab === "teams" && root.favoriteTeams.length > 1
              width: parent.width
              spacing: Style.space(6)
              Chip { text: "All teams"; selected: root.teamFilter === ""; onClicked: root.teamFilter = "" }
              Repeater {
                model: root.favoriteTeams
                delegate: Chip {
                  required property var modelData
                  text: modelData.short
                  logo: modelData.logo
                  showLogo: true
                  selected: root.teamFilter === modelData.id
                  onClicked: root.teamFilter = modelData.id
                }
              }
            }

            // ---- tab: fixtures / table (league picker) ----
            Flow {
              visible: (root.tab === "fixtures" || root.tab === "table") && root.selectedLeagues.length > 0
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: root.selectedLeagues
                delegate: Chip {
                  required property string modelData
                  text: Model.leagueShort(modelData)
                  logo: Model.leagueLogo(modelData)
                  selected: (root.tab === "fixtures" ? root.fixturesLeague : root.tableLeague) === modelData
                  onClicked: root.tab === "fixtures" ? root.setFixturesLeague(modelData) : root.setTableLeague(modelData)
                }
              }
            }

            // ---- empty / loading states ----
            Rectangle {
              id: stateBox
              readonly property string message: {
                if (root.tab === "teams" && root.favoriteTeams.length === 0) return "Follow a team to see its results and fixtures."
                if (root.tab !== "teams" && root.selectedLeagues.length === 0) return "Pick some competitions in settings."
                if (root.currentLoading) return "Loading…"
                if (root.errors[root.currentKey] && root.currentData.length === 0) return "Couldn't reach the football data service. Check your connection and refresh."
                if (root.currentEntry === null) return "Loading…"
                if (root.tab === "today" && root.visibleDayMatches().length === 0)
                  return root.liveOnly ? "No live matches right now." : "No matches on this day in your competitions."
                if (root.tab === "week" && root.currentData.length === 0) return "No matches in the next 7 days."
                if (root.tab === "teams" && root.teamTabMatches("upcoming").length === 0 && root.teamTabMatches("result").length === 0) return "No matches found."
                if (root.tab === "fixtures" && root.currentData.length === 0) return "No fixtures in the next 3 weeks."
                if (root.tab === "table" && root.currentData.length === 0) return "No table for this competition (cups and knockouts have none)."
                return ""
              }
              visible: message !== ""
              width: parent.width
              height: Style.space(72)
              radius: Style.cornerRadius
              color: root.tint(root.fg, 0.035)
              border.width: 1
              border.color: root.tint(root.fg, 0.08)
              PText {
                anchors.centerIn: parent
                width: parent.width - Style.space(24)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: stateBox.message
                color: Commons.Color.muted
              }
            }

            // ---- today: grouped by competition ----
            Repeater {
              model: root.tab === "today" ? Model.groupMatchesByLeague(root.visibleDayMatches(), root.selectedLeagues) : []
              delegate: Column {
                required property var modelData
                width: bodyColumn.width
                spacing: Style.space(4)
                Item {
                  width: parent.width
                  height: Style.space(26)
                  Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)
                    TeamLogo { size: Style.space(18); source: modelData.leagueLogo; name: modelData.leagueName; anchors.verticalCenter: parent.verticalCenter }
                    PText { text: modelData.leagueName; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    PText { visible: !!modelData.round; text: modelData.round; color: Commons.Color.muted; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                  }
                  PText {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.live > 0 ? "● " + modelData.live + " live" : String(modelData.matches.length)
                    color: modelData.live > 0 ? root.liveColor : Commons.Color.muted
                    font.pixelSize: Style.font.caption
                    font.bold: modelData.live > 0
                  }
                }
                Repeater {
                  model: modelData.matches
                  delegate: MatchCard {
                    required property var modelData
                    width: bodyColumn.width
                    match: modelData
                    favoriteIds: root.favoriteIds
                    onActivated: root.openMatch(modelData)
                  }
                }
              }
            }

            // ---- week & fixtures: grouped by day ----
            Repeater {
              model: root.today && (root.tab === "week" || root.tab === "fixtures") ? Model.groupByDay(root.currentData) : []
              delegate: Column {
                required property var modelData
                width: bodyColumn.width
                spacing: Style.space(4)
                PText { text: modelData.label; font.bold: true; color: root.accent; font.pixelSize: Style.font.bodySmall; topPadding: Style.space(2) }
                Repeater {
                  model: modelData.matches
                  delegate: MatchCard {
                    required property var modelData
                    width: bodyColumn.width
                    match: modelData
                    showLeague: root.tab === "week"
                    favoriteIds: root.favoriteIds
                    onActivated: root.openMatch(modelData)
                  }
                }
              }
            }

            // ---- my teams: upcoming + results ----
            Column {
              visible: root.tab === "teams" && root.currentData.length > 0
              width: parent.width
              spacing: Style.space(6)
              PText { visible: root.teamTabMatches("upcoming").length > 0; text: "Upcoming"; font.bold: true; color: root.accent; font.pixelSize: Style.font.bodySmall }
              Repeater {
                model: root.tab === "teams" ? root.teamTabMatches("upcoming") : []
                delegate: MatchCard {
                  required property var modelData
                  width: bodyColumn.width
                  match: modelData
                  showDate: true
                  showLeague: true
                  favoriteIds: root.favoriteIds
                  onActivated: root.openMatch(modelData)
                }
              }
              PText { visible: root.teamTabMatches("result").length > 0; text: "Recent results"; font.bold: true; color: root.accent; font.pixelSize: Style.font.bodySmall; topPadding: Style.space(6) }
              Repeater {
                model: root.tab === "teams" ? root.teamTabMatches("result") : []
                delegate: MatchCard {
                  required property var modelData
                  width: bodyColumn.width
                  match: modelData
                  showDate: true
                  showLeague: true
                  favoriteIds: root.favoriteIds
                  perspectiveTeamId: root.teamFilter || String(modelData.teamId || "")
                  onActivated: root.openMatch(modelData)
                }
              }
            }

            // ---- table ----
            Rectangle {
              visible: root.tab === "table" && root.currentData.length > 0
              width: parent.width
              implicitHeight: tableCol.implicitHeight + Style.space(12)
              radius: Style.cornerRadius
              color: root.tint(root.fg, 0.03)
              border.width: 1
              border.color: root.tint(root.fg, 0.08)

              Column {
                id: tableCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(6)
                spacing: 1
                readonly property real numW: Style.space(28)
                readonly property real clubW: width - Style.space(30) - numW * 5 - Style.space(36) - Style.space(36)

                Row {
                  height: Style.space(24)
                  spacing: 0
                  PText { width: Style.space(30); text: "#"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Style.font.caption; color: Commons.Color.muted; anchors.verticalCenter: parent.verticalCenter }
                  PText { width: tableCol.clubW; text: "Team"; font.pixelSize: Style.font.caption; color: Commons.Color.muted; anchors.verticalCenter: parent.verticalCenter }
                  Repeater {
                    model: ["P", "W", "D", "L", "GD"]
                    delegate: PText { required property string modelData; width: tableCol.numW; text: modelData; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Style.font.caption; color: Commons.Color.muted; anchors.verticalCenter: parent.verticalCenter }
                  }
                  PText { width: Style.space(36); text: "GF:GA"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Style.font.caption; color: Commons.Color.muted; anchors.verticalCenter: parent.verticalCenter }
                  PText { width: Style.space(36); text: "Pts"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Style.font.caption; font.bold: true; color: Commons.Color.muted; anchors.verticalCenter: parent.verticalCenter }
                }

                Repeater {
                  model: root.tab === "table" ? root.currentData : []
                  delegate: Column {
                    id: rowCol
                    required property var modelData
                    required property int index
                    readonly property bool fav: root.isFavorite(modelData.teamId)
                    width: tableCol.width
                    PText {
                      visible: !!modelData.group && (index === 0 || root.currentData[index - 1].group !== modelData.group)
                      text: modelData.group
                      font.bold: true
                      color: root.accent
                      font.pixelSize: Style.font.bodySmall
                      topPadding: Style.space(8)
                      bottomPadding: Style.space(4)
                    }
                    Rectangle {
                      width: parent.width
                      height: Style.space(28)
                      radius: Style.cornerRadius
                      color: rowCol.fav ? root.tint(root.accent, 0.18) : (rowCol.index % 2 ? root.tint(root.fg, 0.03) : "transparent")
                      Rectangle {
                        visible: !!modelData.noteColor
                        width: 3; height: parent.height - 6
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 1.5
                        color: modelData.noteColor || "transparent"
                      }
                      Row {
                        anchors.fill: parent
                        PText { width: Style.space(30); text: modelData.rank; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Style.font.bodySmall; font.bold: rowCol.fav; anchors.verticalCenter: parent.verticalCenter }
                        Row {
                          width: tableCol.clubW
                          spacing: Style.space(6)
                          anchors.verticalCenter: parent.verticalCenter
                          TeamLogo { size: Style.space(18); source: modelData.logo; name: modelData.name; anchors.verticalCenter: parent.verticalCenter }
                          PText { width: parent.width - Style.space(24); text: modelData.short || modelData.name; font.pixelSize: Style.font.bodySmall; font.bold: rowCol.fav; color: rowCol.fav ? root.accent : root.fg; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Repeater {
                          model: [modelData.played, modelData.wins, modelData.ties, modelData.losses, modelData.gd]
                          delegate: PText {
                            required property var modelData
                            required property int index
                            width: tableCol.numW
                            text: String(modelData)
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: Style.font.bodySmall
                            color: index === 4 ? (String(modelData).indexOf("+") === 0 ? "#22c55e" : (String(modelData).indexOf("-") === 0 ? "#f87171" : root.fg)) : root.fg
                            anchors.verticalCenter: parent.verticalCenter
                          }
                        }
                        PText { width: Style.space(36); text: modelData.gf + ":" + modelData.ga; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Style.font.caption; color: Commons.Color.muted; anchors.verticalCenter: parent.verticalCenter }
                        PText { width: Style.space(36); text: modelData.points; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Style.font.bodySmall; font.bold: true; color: rowCol.fav ? root.accent : root.fg; anchors.verticalCenter: parent.verticalCenter }
                      }
                    }
                  }
                }
              }
            }
            Flow {
              visible: root.tab === "table" && root.zoneLegend().length > 0
              width: parent.width
              spacing: Style.space(12)
              Repeater {
                model: root.zoneLegend()
                delegate: Row {
                  required property var modelData
                  spacing: Style.space(5)
                  Rectangle { width: Style.space(10); height: width; radius: 2; color: modelData.color; anchors.verticalCenter: parent.verticalCenter }
                  PText { text: modelData.note; font.pixelSize: Style.font.caption; color: Commons.Color.muted; anchors.verticalCenter: parent.verticalCenter }
                }
              }
            }
          }

          // ================================================== SETTINGS VIEW
          Column {
            visible: root.view === "settings"
            width: parent.width
            spacing: Style.space(12)

            // ---- followed teams ----
            PText { text: "Teams you follow"; font.bold: true; font.pixelSize: Style.font.body }
            PText {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.favoriteTeams.length ? "Shown in the bar and the My teams tab, with live alerts. Click × to unfollow." : "Follow clubs and national teams — as many as you like."
              color: Commons.Color.muted
              font.pixelSize: Style.font.bodySmall
            }
            Flow {
              visible: root.favoriteTeams.length > 0
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: root.favoriteTeams
                delegate: Chip {
                  required property var modelData
                  required property int index
                  text: modelData.short
                  logo: modelData.logo
                  showLogo: true
                  selected: true
                  trailing: "×"
                  onClicked: root.toggleFavorite(modelData)
                }
              }
            }
            TextField {
              width: parent.width
              placeholderText: "Search any team — e.g. Morocco, Wydad, Liverpool…"
              text: root.teamQuery
              onTextChanged: { root.teamQuery = text; teamSearchTimer.restart() }
            }
            PText {
              visible: root.teamQuery.trim().length >= 2 && searchFetcher.busy
              text: "Searching…"
              color: Commons.Color.muted
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.teamQuery.trim() === "" ? [{ title: "Popular clubs", national: false }, { title: "National teams", national: true }] : [{ title: "", national: null }]
              delegate: Column {
                required property var modelData
                width: bodyColumn.width
                spacing: Style.space(6)
                PText { visible: modelData.title !== ""; text: modelData.title; color: Commons.Color.muted; font.pixelSize: Style.font.caption; font.bold: true }
                Flow {
                  width: parent.width
                  spacing: Style.space(6)
                  Repeater {
                    model: modelData.national === null ? root.combinedTeamResults() : Model.popularMatching("", modelData.national)
                    delegate: Chip {
                      required property var modelData
                      text: modelData.short || modelData.name
                      subText: root.teamQuery.trim() !== "" ? (modelData.league || "") : ""
                      logo: modelData.logo || ""
                      showLogo: true
                      selected: root.isFavorite(modelData.id)
                      trailing: root.isFavorite(modelData.id) ? "✓" : "+"
                      onClicked: root.toggleFavorite(modelData)
                    }
                  }
                }
                PText {
                  visible: modelData.national === null && root.teamResultsQuery === root.teamQuery.trim() && root.combinedTeamResults().length === 0
                  text: "No team found. Try another spelling."
                  color: Commons.Color.muted
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Rectangle { width: parent.width; height: 1; color: root.tint(root.fg, 0.10) }

            // ---- competitions ----
            PText { text: "Competitions"; font.bold: true; font.pixelSize: Style.font.body }
            PText {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Used by the Matches, Week, Fixtures and Table tabs, and for league alerts. " + root.selectedLeagues.length + " selected."
              color: Commons.Color.muted
              font.pixelSize: Style.font.bodySmall
            }
            TextField {
              width: parent.width
              placeholderText: "Filter competitions…"
              text: root.leagueQuery
              onTextChanged: { root.leagueQuery = text; root.leagueSearch() }
            }
            Repeater {
              model: Model.regions
              delegate: Column {
                id: regionCol
                required property string modelData
                readonly property var items: Model.leaguesInRegion(modelData, root.leagueQuery)
                visible: items.length > 0
                width: bodyColumn.width
                spacing: Style.space(6)
                PText { text: modelData; color: Commons.Color.muted; font.pixelSize: Style.font.caption; font.bold: true }
                Flow {
                  width: parent.width
                  spacing: Style.space(6)
                  Repeater {
                    model: regionCol.items
                    delegate: Chip {
                      required property var modelData
                      text: modelData.name
                      logo: modelData.logo
                      showLogo: true
                      selected: root.selectedLeagues.indexOf(modelData.id) >= 0
                      onClicked: root.toggleLeague(modelData.id)
                    }
                  }
                }
              }
            }
            Column {
              visible: root.extraLeagueResults().length > 0
              width: parent.width
              spacing: Style.space(6)
              PText { text: "More from ESPN"; color: Commons.Color.muted; font.pixelSize: Style.font.caption; font.bold: true }
              Flow {
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: root.extraLeagueResults()
                  delegate: Chip {
                    required property var modelData
                    text: modelData.name
                    selected: root.selectedLeagues.indexOf(modelData.id) >= 0
                    onClicked: root.toggleLeague(modelData.id)
                  }
                }
              }
            }
            // custom (non-catalogue) leagues already selected
            Flow {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: root.selectedLeagues.filter(function(id) { return !Model.findLeague(id) })
                delegate: Chip {
                  required property string modelData
                  text: Model.leagueName(modelData)
                  selected: true
                  trailing: "×"
                  onClicked: root.toggleLeague(modelData)
                }
              }
            }

            Rectangle { width: parent.width; height: 1; color: root.tint(root.fg, 0.10) }

            // ---- alerts ----
            PText { text: "Live alerts"; font.bold: true; font.pixelSize: Style.font.body }
            Item {
              width: parent.width
              height: Math.max(alertsText.implicitHeight, alertsSwitch.height)
              Column {
                id: alertsText
                width: parent.width - alertsSwitch.width - Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                PText { text: "Desktop notifications"; width: parent.width }
                PText {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  text: "Checks every 30 seconds while a followed match is live (every few minutes otherwise) and notifies kick-off, goals, red cards, half-time and full-time."
                  color: Commons.Color.muted
                  font.pixelSize: Style.font.caption
                }
              }
              ToggleSwitch {
                id: alertsSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.alertsEnabled
                onToggled: { root.alertsEnabled = !root.alertsEnabled; root.persistSettings(); root.runPulse() }
              }
            }
            Item {
              width: parent.width
              opacity: root.alertsEnabled ? 1 : 0.45
              height: Math.max(remText.implicitHeight, remSwitch.height)
              Column {
                id: remText
                width: parent.width - remSwitch.width - Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                PText { text: "Kick-off reminders for my teams"; width: parent.width }
              }
              ToggleSwitch {
                id: remSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.remindersEnabled
                onToggled: { root.remindersEnabled = !root.remindersEnabled; root.persistSettings(); root.runPulse() }
              }
            }
            Row {
              visible: root.remindersEnabled
              opacity: root.alertsEnabled ? 1 : 0.45
              spacing: Style.space(8)
              PText { text: "Remind me"; color: Commons.Color.muted; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
              ButtonGroup {
                options: [{ value: "5", label: "5 min" }, { value: "15", label: "15 min" }, { value: "30", label: "30 min" }, { value: "60", label: "1 h" }]
                value: String(root.reminderMinutes)
                fontSize: Style.font.bodySmall
                onChanged: function(v) { root.reminderMinutes = Number(v); root.persistSettings(); root.runPulse() }
              }
            }
            Column {
              width: parent.width
              opacity: root.alertsEnabled ? 1 : 0.45
              spacing: Style.space(6)
              PText { text: "Alerts for my competitions"; width: parent.width }
              PText {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Matches of your teams always alert. For other matches in your selected competitions:"
                color: Commons.Color.muted
                font.pixelSize: Style.font.caption
              }
              ButtonGroup {
                options: [{ value: "off", label: "Off" }, { value: "goals", label: "Goals & results" }, { value: "all", label: "Everything" }]
                value: root.leagueAlertMode
                fontSize: Style.font.bodySmall
                onChanged: function(v) { root.leagueAlertMode = v; root.persistSettings(); root.runPulse() }
              }
            }
            Item { width: 1; height: Style.space(4) }
          }

          // ================================================== MATCH CENTRE
          Column {
            visible: root.view === "match"
            width: parent.width
            spacing: Style.space(12)

            Rectangle {
              width: parent.width
              implicitHeight: hero.implicitHeight + Style.space(24)
              radius: Style.cornerRadius
              color: root.tint(root.fg, 0.04)
              border.width: 1
              border.color: (root.activeMatch && root.activeMatch.state === "in") ? root.tint(root.liveColor, 0.6) : root.tint(root.fg, 0.10)

              Column {
                id: hero
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(12)
                spacing: Style.space(10)

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(6)
                  TeamLogo {
                    size: Style.space(16)
                    source: root.activeMatch ? Model.leagueLogo(root.activeMatch.leagueId) : ""
                    name: root.activeMatch ? (root.activeMatch.leagueName || "") : ""
                    visible: source !== ""
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  PText {
                    text: root.activeMatch ? ((root.activeMatch.leagueName || "") + (root.activeMatch.round ? " · " + root.activeMatch.round : "")) : ""
                    font.pixelSize: Style.font.caption
                    color: Commons.Color.muted
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Item {
                  width: parent.width
                  height: Math.max(homeHero.implicitHeight, awayHero.implicitHeight, scoreHero.implicitHeight)
                  Column {
                    id: homeHero
                    width: (parent.width - scoreHero.width) / 2
                    anchors.left: parent.left
                    spacing: Style.space(6)
                    TeamLogo { size: Style.space(48); source: root.activeMatch ? root.activeMatch.homeLogo : ""; name: root.activeMatch ? root.activeMatch.home : ""; anchors.horizontalCenter: parent.horizontalCenter }
                    PText {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      wrapMode: Text.WordWrap
                      text: root.activeMatch ? root.activeMatch.home : ""
                      font.bold: true
                      color: root.activeMatch && root.isFavorite(root.activeMatch.homeId) ? root.accent : root.fg
                    }
                  }
                  Column {
                    id: scoreHero
                    width: Style.space(130)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: homeHero.verticalCenter
                    spacing: Style.space(4)
                    PText {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      text: {
                        var m = root.activeMatch
                        if (!m) return ""
                        if (m.state === "pre") return Model.formatMatchTime(m.date)
                        return (m.homeScore || "0") + "  -  " + (m.awayScore || "0")
                      }
                      font.pixelSize: Style.font.heading * 1.6
                      font.bold: true
                      color: (root.activeMatch && root.activeMatch.state === "in") ? root.liveColor : root.fg
                    }
                    Rectangle {
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: statusText.implicitWidth + Style.space(14)
                      height: statusText.implicitHeight + Style.space(6)
                      radius: height / 2
                      color: (root.activeMatch && root.activeMatch.state === "in") ? root.tint(root.liveColor, 0.18) : root.tint(root.fg, 0.07)
                      PText {
                        id: statusText
                        anchors.centerIn: parent
                        text: {
                          var m = root.activeMatch
                          if (!m) return ""
                          if (m.state === "in") return "● LIVE " + (m.detail === "HT" ? "HT" : (m.detail || ""))
                          if (m.state === "post") return m.detail && m.detail !== "Scheduled" ? m.detail : "Full time"
                          var d = new Date(m.date)
                          if (isNaN(d.getTime())) return "Scheduled"
                          var c = Model.countdown(m.date)
                          return Model.formatDayLabel(d) + (c ? " · " + c : "")
                        }
                        font.pixelSize: Style.font.caption
                        font.bold: root.activeMatch && root.activeMatch.state === "in"
                        color: (root.activeMatch && root.activeMatch.state === "in") ? root.liveColor : root.fg
                      }
                    }
                  }
                  Column {
                    id: awayHero
                    width: (parent.width - scoreHero.width) / 2
                    anchors.right: parent.right
                    spacing: Style.space(6)
                    TeamLogo { size: Style.space(48); source: root.activeMatch ? root.activeMatch.awayLogo : ""; name: root.activeMatch ? root.activeMatch.away : ""; anchors.horizontalCenter: parent.horizontalCenter }
                    PText {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      wrapMode: Text.WordWrap
                      text: root.activeMatch ? root.activeMatch.away : ""
                      font.bold: true
                      color: root.activeMatch && root.isFavorite(root.activeMatch.awayId) ? root.accent : root.fg
                    }
                  }
                }

                // goal scorers under the score
                Row {
                  visible: !!root.matchDetails && !!root.matchDetails.events
                  width: parent.width
                  Column {
                    width: parent.width / 2 - Style.space(14)
                    Repeater {
                      model: root.matchDetails && root.matchDetails.events ? root.matchDetails.events.filter(function(e) { return e.type === "goal" && e.side === "home" }) : []
                      delegate: PText { required property var modelData; width: parent.width; horizontalAlignment: Text.AlignRight; text: modelData.player + " " + modelData.clock; font.pixelSize: Style.font.caption; color: Commons.Color.muted }
                    }
                  }
                  PText { width: Style.space(28); horizontalAlignment: Text.AlignHCenter; text: root.matchDetails && root.matchDetails.events && root.matchDetails.events.some(function(e) { return e.type === "goal" }) ? "⚽" : ""; font.pixelSize: Style.font.caption }
                  Column {
                    width: parent.width / 2 - Style.space(14)
                    Repeater {
                      model: root.matchDetails && root.matchDetails.events ? root.matchDetails.events.filter(function(e) { return e.type === "goal" && e.side === "away" }) : []
                      delegate: PText { required property var modelData; width: parent.width; text: modelData.player + " " + modelData.clock; font.pixelSize: Style.font.caption; color: Commons.Color.muted }
                    }
                  }
                }

                PText {
                  visible: !!(root.activeMatch && root.activeMatch.venue)
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: root.activeMatch ? "📍 " + root.activeMatch.venue + (root.matchDetails && root.matchDetails.attendance && root.matchDetails.attendance !== "0" ? " · " + root.matchDetails.attendance + " fans" : "") : ""
                  font.pixelSize: Style.font.caption
                  color: Commons.Color.muted
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(4)
              Repeater {
                model: [{ id: "timeline", label: "Timeline", icon: "󰔟" }, { id: "lineup", label: "Lineups", icon: "󰋑" }, { id: "stats", label: "Stats", icon: "󰄨" }]
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool active: root.matchTab === modelData.id
                  width: (bodyColumn.width - Style.space(8)) / 3
                  height: Style.space(32)
                  radius: Style.cornerRadius
                  color: active ? root.tint(root.accent, 0.20) : (mtMouse.containsMouse ? root.tint(root.fg, 0.08) : root.tint(root.fg, 0.035))
                  border.width: 1
                  border.color: active ? root.accent : root.tint(root.fg, 0.10)
                  Row {
                    anchors.centerIn: parent
                    spacing: Style.space(5)
                    PText { text: modelData.icon; color: active ? root.accent : Commons.Color.muted; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
                    PText { text: modelData.label; color: active ? root.accent : root.fg; font.bold: active; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
                  }
                  MouseArea { id: mtMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.matchTab = modelData.id }
                }
              }
            }

            Rectangle {
              id: matchState
              readonly property string message: {
                if (!root.matchDetails) return detailsFetcher.busy ? "Loading match details…" : (root.errors[root.matchKey] ? "Couldn't load match details." : "Loading match details…")
                var d = root.matchDetails, pre = root.activeMatch && root.activeMatch.state === "pre"
                if (root.matchTab === "timeline" && (!d.events || d.events.length === 0)) return pre ? "The match hasn't started yet. Goals, cards and substitutions will appear here." : "No key events recorded."
                if (root.matchTab === "stats" && (!d.stats || d.stats.length === 0)) return pre ? "Statistics appear once the match kicks off." : "No statistics for this match."
                if (root.matchTab === "lineup" && !root.hasLineup) return "Lineups are usually announced about an hour before kick-off."
                return ""
              }
              visible: message !== ""
              width: parent.width
              height: Style.space(72)
              radius: Style.cornerRadius
              color: root.tint(root.fg, 0.035)
              border.width: 1
              border.color: root.tint(root.fg, 0.08)
              PText {
                anchors.centerIn: parent
                width: parent.width - Style.space(24)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: matchState.message
                color: Commons.Color.muted
              }
            }

            // ---- timeline ----
            Item {
              visible: root.matchTab === "timeline" && !!root.matchDetails && !!root.matchDetails.events && root.matchDetails.events.length > 0
              width: parent.width
              height: timelineCol.implicitHeight
              Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 2; height: parent.height; color: root.tint(root.fg, 0.12) }
              Column {
                id: timelineCol
                width: parent.width
                spacing: Style.space(8)
                Repeater {
                  model: root.matchDetails && root.matchDetails.events ? root.matchDetails.events : []
                  delegate: Item {
                    required property var modelData
                    readonly property bool home: modelData.side !== "away"
                    readonly property string icon: modelData.type === "goal" ? "⚽" : (modelData.type === "red-card" ? "🟥" : (modelData.type === "yellow-card" ? "🟨" : "🔁"))
                    width: timelineCol.width
                    height: Math.max(Style.space(26), evText.implicitHeight)
                    Rectangle {
                      id: minute
                      anchors.centerIn: parent
                      width: Math.max(Style.space(40), minText.implicitWidth + Style.space(12))
                      height: Style.space(22)
                      radius: height / 2
                      color: modelData.type === "goal" ? root.tint(root.accent, 0.25) : Commons.Color.background
                      border.width: 1
                      border.color: modelData.type === "goal" ? root.accent : root.tint(root.fg, 0.2)
                      PText { id: minText; anchors.centerIn: parent; text: modelData.clock || "–"; font.pixelSize: Style.font.caption; font.bold: true }
                    }
                    Row {
                      id: evText
                      layoutDirection: home ? Qt.RightToLeft : Qt.LeftToRight
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.right: home ? minute.left : undefined
                      anchors.left: home ? undefined : minute.right
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(10)
                      width: (parent.width - minute.width) / 2 - Style.space(14)
                      spacing: Style.space(6)
                      PText { text: icon; font.pixelSize: Style.font.body; anchors.verticalCenter: parent.verticalCenter }
                      Column {
                        width: parent.width - Style.space(28)
                        anchors.verticalCenter: parent.verticalCenter
                        PText {
                          width: parent.width
                          horizontalAlignment: home ? Text.AlignRight : Text.AlignLeft
                          text: modelData.player + (modelData.type === "goal" && modelData.typeLabel && modelData.typeLabel !== "Goal" ? " (" + modelData.typeLabel + ")" : "")
                          font.pixelSize: Style.font.bodySmall
                          font.bold: modelData.type === "goal"
                          color: modelData.type === "substitution" ? "#22c55e" : root.fg
                        }
                        PText {
                          visible: !!modelData.assist
                          width: parent.width
                          horizontalAlignment: home ? Text.AlignRight : Text.AlignLeft
                          text: modelData.type === "substitution" ? "↓ " + modelData.assist : "Assist: " + modelData.assist
                          font.pixelSize: Style.font.caption
                          color: modelData.type === "substitution" ? "#f87171" : Commons.Color.muted
                        }
                      }
                    }
                  }
                }
              }
            }

            // ---- stats ----
            Column {
              visible: root.matchTab === "stats" && !!root.matchDetails && !!root.matchDetails.stats && root.matchDetails.stats.length > 0
              width: parent.width
              spacing: Style.space(10)
              Repeater {
                model: root.matchDetails && root.matchDetails.stats ? root.matchDetails.stats : []
                delegate: Column {
                  required property var modelData
                  readonly property bool homeLead: modelData.homePct > 50
                  readonly property bool awayLead: modelData.homePct < 50
                  width: parent.width
                  spacing: Style.space(4)
                  Item {
                    width: parent.width
                    height: Style.space(20)
                    PText { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: modelData.home; font.bold: homeLead; color: homeLead ? root.accent : root.fg; font.pixelSize: Style.font.bodySmall }
                    PText { anchors.centerIn: parent; text: modelData.name; color: Commons.Color.muted; font.pixelSize: Style.font.caption }
                    PText { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: modelData.away; font.bold: awayLead; color: awayLead ? "#f97316" : root.fg; font.pixelSize: Style.font.bodySmall }
                  }
                  Row {
                    width: parent.width
                    spacing: Style.space(4)
                    Item {
                      width: (parent.width - Style.space(4)) / 2
                      height: Style.space(6)
                      Rectangle { anchors.fill: parent; radius: 3; color: root.tint(root.fg, 0.08) }
                      Rectangle { anchors.right: parent.right; height: parent.height; radius: 3; width: parent.width * modelData.homePct / 100; color: homeLead ? root.accent : root.tint(root.accent, 0.45) }
                    }
                    Item {
                      width: (parent.width - Style.space(4)) / 2
                      height: Style.space(6)
                      Rectangle { anchors.fill: parent; radius: 3; color: root.tint(root.fg, 0.08) }
                      Rectangle { anchors.left: parent.left; height: parent.height; radius: 3; width: parent.width * modelData.awayPct / 100; color: awayLead ? "#f97316" : Qt.rgba(0.976, 0.451, 0.086, 0.45) }
                    }
                  }
                }
              }
            }

            // ---- lineups ----
            Column {
              visible: root.matchTab === "lineup" && root.hasLineup
              width: parent.width
              spacing: Style.space(10)

              PitchView {
                width: parent.width
                height: implicitHeight
                homeRows: root.activeLineup ? (root.activeLineup.homeRows || []) : []
                awayRows: root.activeLineup ? (root.activeLineup.awayRows || []) : []
                homeName: root.activeMatch ? root.activeMatch.home : ""
                awayName: root.activeMatch ? root.activeMatch.away : ""
                homeFormation: root.activeLineup ? root.activeLineup.homeFormation : ""
                awayFormation: root.activeLineup ? root.activeLineup.awayFormation : ""
              }

              Row {
                visible: !!(root.activeLineup && (root.activeLineup.homeCoach || root.activeLineup.awayCoach))
                width: parent.width
                PText { width: parent.width / 2; text: root.activeLineup && root.activeLineup.homeCoach ? "Coach: " + root.activeLineup.homeCoach : ""; font.pixelSize: Style.font.caption; color: Commons.Color.muted }
                PText { width: parent.width / 2; horizontalAlignment: Text.AlignRight; text: root.activeLineup && root.activeLineup.awayCoach ? "Coach: " + root.activeLineup.awayCoach : ""; font.pixelSize: Style.font.caption; color: Commons.Color.muted }
              }

              PText { text: "Substitutes"; font.bold: true; font.pixelSize: Style.font.bodySmall; color: root.accent }
              Row {
                width: parent.width
                spacing: Style.space(10)
                Repeater {
                  model: ["home", "away"]
                  delegate: Column {
                    required property string modelData
                    width: (bodyColumn.width - Style.space(10)) / 2
                    spacing: 2
                    Repeater {
                      model: root.activeLineup ? (root.activeLineup[modelData + "Bench"] || []) : []
                      delegate: Row {
                        required property var modelData
                        width: parent.width
                        spacing: Style.space(6)
                        PText { width: Style.space(22); text: modelData.number || "–"; horizontalAlignment: Text.AlignRight; font.pixelSize: Style.font.caption; color: Commons.Color.muted }
                        PText {
                          width: parent.width - Style.space(28)
                          text: (modelData.subbedOn ? "↑ " : "") + modelData.name + ((modelData.goals || 0) > 0 ? " ⚽" : "") + ((modelData.red || 0) > 0 ? " 🟥" : ((modelData.yellow || 0) > 0 ? " 🟨" : ""))
                          font.pixelSize: Style.font.caption
                          color: modelData.subbedOn ? "#22c55e" : root.fg
                        }
                      }
                    }
                  }
                }
              }
            }
            Item { width: 1; height: Style.space(4) }
          }
        }
      }
    }
  }
}
