.pragma library

var leagues = [
  { id: "eng.1", name: "Premier League", short: "PL", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/23.png" },
  { id: "esp.1", name: "La Liga", short: "LL", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/15.png" },
  { id: "uefa.champions", name: "UEFA Champions League", short: "UCL", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2.png" },
  { id: "ita.1", name: "Serie A", short: "SA", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/12.png" },
  { id: "ger.1", name: "Bundesliga", short: "BL", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/10.png" },
  { id: "fra.1", name: "Ligue 1", short: "L1", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/9.png" },
  { id: "uefa.europa", name: "Europa League", short: "UEL", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/2254.png" },
  { id: "por.1", name: "Primeira Liga (Portugal)", short: "Portugal", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/14.png" },
  { id: "ned.1", name: "Eredivisie (Netherlands)", short: "Eredivisie", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/11.png" },
  { id: "tur.1", name: "Süper Lig (Türkiye)", short: "Süper Lig", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/18.png" },
  { id: "esp.copa_del_rey", name: "Copa del Rey", short: "Copa del Rey", logo: "" },
  { id: "esp.super_cup", name: "Spanish Super Cup", short: "Super Cup", logo: "" },
  { id: "uefa.super_cup", name: "UEFA Super Cup", short: "UEFA Super Cup", logo: "" },
  { id: "fifa.cwc", name: "FIFA Club World Cup", short: "Club World Cup", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/20.png" },
  { id: "fifa.world", name: "FIFA World Cup", short: "World Cup", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/4.png" },
  { id: "conmebol.america", name: "Copa América", short: "Copa América", logo: "" },
  { id: "uefa.nations", name: "UEFA Nations League", short: "Nations", logo: "" },
  { id: "caf.nations", name: "Africa Cup of Nations", short: "AFCON", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2390.png" },
  { id: "caf.champions", name: "CAF Champions League", short: "CAF CL", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2391.png" },
  { id: "mar.1", name: "Botola Pro (Morocco)", short: "Botola", logo: "https://images.fotmob.com/image_resources/logo/leaguelogo/dark/530.png" }
]

var popularTeamTerms = [
  "barcelona", "real madrid", "atletico madrid", "atlético madrid", "arsenal", "chelsea", "liverpool",
  "manchester city", "manchester united", "tottenham", "bayern munich", "borussia dortmund",
  "bayer leverkusen", "ac milan", "inter milan", "inter", "juventus", "napoli", "paris saint-germain",
  "psg", "marseille", "lyon", "raja", "wydad", "inter miami"
]

function isPopularTeam(team) {
  var name = String(team.name || "").toLowerCase()
  var shortName = String(team.short || "").toLowerCase()
  for (var i = 0; i < popularTeamTerms.length; i++)
    if (name.indexOf(popularTeamTerms[i]) >= 0 || shortName.indexOf(popularTeamTerms[i]) >= 0) return true
  return false
}

function matchesTeamSearch(team, query) {
  var q = String(query || "").trim().toLowerCase()
  var name = String(team.name || "").toLowerCase()
  var shortName = String(team.short || "").toLowerCase()
  if (!q || name.indexOf(q) >= 0 || shortName.indexOf(q) >= 0) return true
  if (q === "wac" && name.indexOf("wydad") >= 0) return true
  if (q === "wydad" && shortName.indexOf("wac") >= 0) return true
  if (q === "inter miami" && (name.indexOf("miami") >= 0 || shortName.indexOf("miami") >= 0)) return true
  return false
}

function defaultSelected() {
  return ["esp.1", "eng.1", "fra.1", "ger.1", "uefa.champions", "caf.champions"]
}

function selectedValues(value) {
  if (!value || !value.length) return defaultSelected()
  var out = []
  for (var i = 0; i < value.length; i++) {
    var id = String(value[i] || "")
    if (id && out.indexOf(id) < 0) out.push(id)
  }
  return out.length ? out : defaultSelected()
}

function leagueName(id) {
  for (var i = 0; i < leagues.length; i++) if (leagues[i].id === id) return leagues[i].name
  return id || "Competition"
}

function leagueLogo(id) {
  for (var i = 0; i < leagues.length; i++) {
    if (leagues[i].id === id && leagues[i].logo) return leagues[i].logo
  }
  return ""
}

function groupMatchesByLeague(matches, selectedLeagues) {
  if (!matches || !matches.length) return []
  var groupsMap = {}
  var leagueOrder = []

  if (selectedLeagues && selectedLeagues.length) {
    for (var i = 0; i < selectedLeagues.length; i++) {
      var lId = selectedLeagues[i]
      if (lId && !groupsMap[lId]) {
        groupsMap[lId] = {
          leagueId: lId,
          leagueName: leagueName(lId),
          leagueLogo: leagueLogo(lId),
          matches: []
        }
        leagueOrder.push(lId)
      }
    }
  }

  for (var m = 0; m < matches.length; m++) {
    var match = matches[m]
    var id = match.leagueId || "other"
    if (!groupsMap[id]) {
      groupsMap[id] = {
        leagueId: id,
        leagueName: match.league || leagueName(id),
        leagueLogo: match.leagueLogo || leagueLogo(id),
        matches: []
      }
      leagueOrder.push(id)
    }
    if (match.leagueLogo && !groupsMap[id].leagueLogo) {
      groupsMap[id].leagueLogo = match.leagueLogo
    }
    if (match.league && (groupsMap[id].leagueName === id || !groupsMap[id].leagueName)) {
      groupsMap[id].leagueName = match.league
    }
    groupsMap[id].matches.push(match)
  }

  var result = []
  for (var k = 0; k < leagueOrder.length; k++) {
    var grp = groupsMap[leagueOrder[k]]
    if (grp && grp.matches.length > 0) {
      result.push(grp)
    }
  }
  return result
}

function sameLocalDay(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

function formatBarLabel(match, team) {
  if (!team || !team.id) return "Football"
  var name = team.short || team.name || "Team"
  if (!match || !match.opponent) return name + " · No match"
  var start = new Date(match.date)
  if (match.state === "in") {
    var score = match.homeScore !== "" && match.awayScore !== "" ? " " + match.homeScore + "-" + match.awayScore : ""
    return name + " vs " + match.opponent + " · LIVE" + score
  }
  if (isNaN(start.getTime())) return name + " vs " + match.opponent
  var now = new Date()
  var today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  var tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
  var day = new Date(start.getFullYear(), start.getMonth(), start.getDate())
  var hh = start.getHours(), mm = start.getMinutes()
  var time = (hh < 10 ? "0" : "") + hh + ":" + (mm < 10 ? "0" : "") + mm
  if (sameLocalDay(start, today)) return name + " vs " + match.opponent + " · Today " + time
  if (sameLocalDay(start, tomorrow)) return name + " vs " + match.opponent + " · Tomorrow " + time
  var days = Math.round((day - today) / 86400000)
  var weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  if (days >= 0 && days < 7) return name + " vs " + match.opponent + " · " + weekdays[start.getDay()] + " " + time
  return name + " vs " + match.opponent + " · " + start.getDate() + " " + months[start.getMonth()] + " " + time
}

function formatDayLabel(date) {
  var now = new Date()
  var today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  var tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
  var yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  var label = date.getDate() + " " + months[date.getMonth()]
  if (sameLocalDay(date, today)) return "Today (" + label + ")"
  if (sameLocalDay(date, tomorrow)) return "Tomorrow (" + label + ")"
  if (sameLocalDay(date, yesterday)) return "Yesterday (" + label + ")"
  return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][date.getDay()] + ", " + label
}

function formatMonthLabel(date) {
  var months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
  return months[date.getMonth()] + " " + date.getFullYear()
}

function formatMatchTime(value) {
  var date = new Date(value)
  if (!value || isNaN(date.getTime())) return "—"
  var h = date.getHours(), m = date.getMinutes()
  return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
}

function formatDateParam(date) {
  var y = date.getFullYear(), m = date.getMonth() + 1, d = date.getDate()
  return "" + y + (m < 10 ? "0" : "") + m + (d < 10 ? "0" : "") + d
}
