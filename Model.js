.pragma library

var leagues = [
  { id: "esp.1", name: "La Liga", short: "LL" },
  { id: "eng.1", name: "Premier League", short: "PL" },
  { id: "fra.1", name: "Ligue 1", short: "L1" },
  { id: "ger.1", name: "Bundesliga", short: "BL" },
  { id: "uefa.champions", name: "UEFA Champions League", short: "UCL" },
  { id: "caf.champions", name: "CAF Champions League", short: "CAF CL" },
  { id: "ita.1", name: "Serie A", short: "SA" },
  { id: "uefa.europa", name: "Europa League", short: "UEL" },
  { id: "esp.copa_del_rey", name: "Copa del Rey", short: "CDR" }
]

function defaultSelected() {
  return ["esp.1", "eng.1", "fra.1", "ger.1", "uefa.champions", "caf.champions"]
}

function selectedValues(value) {
  if (!value || !value.length) return defaultSelected()
  var out = []
  for (var i = 0; i < value.length; i++) {
    for (var j = 0; j < leagues.length; j++) {
      if (value[i] === leagues[j].id && out.indexOf(value[i]) < 0) out.push(value[i])
    }
  }
  return out.length ? out : defaultSelected()
}

function leagueName(id) {
  for (var i = 0; i < leagues.length; i++) if (leagues[i].id === id) return leagues[i].name
  return id || "Competition"
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
