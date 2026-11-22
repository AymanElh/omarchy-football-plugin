.pragma library

// Curated competitions, grouped by region.  Ids are ESPN league slugs, except
// mar.1 (Botola Pro) which the backend serves from FotMob.
var regions = ["Europe", "Africa", "Asia", "Americas", "International"]

var leagues = [
  { id: "eng.1", name: "Premier League", short: "PL", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/23.png" },
  { id: "esp.1", name: "La Liga", short: "LaLiga", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/15.png" },
  { id: "ita.1", name: "Serie A", short: "Serie A", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/12.png" },
  { id: "ger.1", name: "Bundesliga", short: "BL", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/10.png" },
  { id: "fra.1", name: "Ligue 1", short: "L1", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/9.png" },
  { id: "uefa.champions", name: "Champions League", short: "UCL", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2.png" },
  { id: "uefa.europa", name: "Europa League", short: "UEL", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2310.png" },
  { id: "uefa.europa.conf", name: "Conference League", short: "UECL", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/20296.png" },
  { id: "por.1", name: "Primeira Liga", short: "Liga PT", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/14.png" },
  { id: "ned.1", name: "Eredivisie", short: "Eredivisie", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/11.png" },
  { id: "tur.1", name: "Süper Lig", short: "Süper Lig", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/18.png" },
  { id: "sco.1", name: "Scottish Premiership", short: "SPFL", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/45.png" },
  { id: "bel.1", name: "Belgian Pro League", short: "Pro League", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/6.png" },
  { id: "eng.2", name: "Championship", short: "EFL", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/24.png" },
  { id: "eng.fa", name: "FA Cup", short: "FA Cup", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/40.png" },
  { id: "eng.league_cup", name: "Carabao Cup", short: "EFL Cup", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/41.png" },
  { id: "esp.copa_del_rey", name: "Copa del Rey", short: "Copa", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/80.png" },
  { id: "esp.super_cup", name: "Supercopa de España", short: "Supercopa", region: "Europe", logo: "" },
  { id: "ita.coppa_italia", name: "Coppa Italia", short: "Coppa", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500/2192.png" },
  { id: "ger.dfb_pokal", name: "DFB-Pokal", short: "Pokal", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2061.png" },
  { id: "fra.coupe_de_france", name: "Coupe de France", short: "CdF", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/182.png" },
  { id: "uefa.super_cup", name: "UEFA Super Cup", short: "Super Cup", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/1272.png" },
  { id: "uefa.nations", name: "UEFA Nations League", short: "UNL", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2395.png" },
  { id: "uefa.euro", name: "EURO", short: "EURO", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/74.png" },
  { id: "uefa.euroq", name: "EURO Qualifying", short: "EURO Q", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/56.png" },
  { id: "fifa.worldq.uefa", name: "World Cup Qualifying (UEFA)", short: "WCQ UEFA", region: "Europe", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/67.png" },

  { id: "mar.1", name: "Botola Pro", short: "Botola", region: "Africa", logo: "https://images.fotmob.com/image_resources/logo/leaguelogo/dark/530.png" },
  { id: "caf.nations", name: "Africa Cup of Nations", short: "AFCON", region: "Africa", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/76.png" },
  { id: "caf.nations_qual", name: "AFCON Qualifying", short: "AFCON Q", region: "Africa", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/76.png" },
  { id: "fifa.worldq.caf", name: "World Cup Qualifying (CAF)", short: "WCQ CAF", region: "Africa", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/63.png" },
  { id: "caf.champions", name: "CAF Champions League", short: "CAF CL", region: "Africa", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2391.png" },
  { id: "caf.confed", name: "CAF Confederation Cup", short: "CAF CC", region: "Africa", logo: "" },
  { id: "caf.championship", name: "African Nations Championship", short: "CHAN", region: "Africa", logo: "" },
  { id: "rsa.1", name: "South African Premiership", short: "PSL", region: "Africa", logo: "" },

  { id: "ksa.1", name: "Saudi Pro League", short: "SPL", region: "Asia", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2488.png" },
  { id: "afc.champions", name: "AFC Champions League Elite", short: "ACL", region: "Asia", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2200.png" },
  { id: "afc.asian.cup", name: "AFC Asian Cup", short: "Asian Cup", region: "Asia", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2243.png" },
  { id: "fifa.worldq.afc", name: "World Cup Qualifying (AFC)", short: "WCQ AFC", region: "Asia", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/62.png" },
  { id: "jpn.1", name: "J1 League", short: "J1", region: "Asia", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2199.png" },
  { id: "aus.1", name: "A-League Men", short: "A-League", region: "Asia", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/1308.png" },

  { id: "usa.1", name: "MLS", short: "MLS", region: "Americas", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/19.png" },
  { id: "mex.1", name: "Liga MX", short: "Liga MX", region: "Americas", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/22.png" },
  { id: "bra.1", name: "Brasileirão", short: "Brasileirão", region: "Americas", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/85.png" },
  { id: "arg.1", name: "Liga Profesional", short: "LPF", region: "Americas", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/1.png" },
  { id: "conmebol.libertadores", name: "Copa Libertadores", short: "Libertadores", region: "Americas", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/58.png" },
  { id: "conmebol.sudamericana", name: "Copa Sudamericana", short: "Sudamericana", region: "Americas", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/1208.png" },
  { id: "conmebol.america", name: "Copa América", short: "Copa América", region: "Americas", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/83.png" },
  { id: "fifa.worldq.conmebol", name: "World Cup Qualifying (CONMEBOL)", short: "WCQ CONMEBOL", region: "Americas", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/65.png" },
  { id: "concacaf.gold", name: "Gold Cup", short: "Gold Cup", region: "Americas", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/59.png" },
  { id: "concacaf.champions", name: "Concacaf Champions Cup", short: "CCC", region: "Americas", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2298.png" },
  { id: "concacaf.nations.league", name: "Concacaf Nations League", short: "CNL", region: "Americas", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/2406.png" },

  { id: "fifa.world", name: "FIFA World Cup", short: "World Cup", region: "International", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/4.png" },
  { id: "fifa.friendly", name: "International Friendlies", short: "Friendlies", region: "International", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/53.png" },
  { id: "fifa.cwc", name: "FIFA Club World Cup", short: "Club WC", region: "International", logo: "https://a.espncdn.com/i/leaguelogos/soccer/500-dark/1932.png" },
  { id: "fifa.intercontinental_cup", name: "FIFA Intercontinental Cup", short: "Intercontinental", region: "International", logo: "" }
]

// Ready-made teams so the most followed clubs and national teams can be
// picked without a network search.  Ids are ESPN team ids.
var popularTeams = [
  { id: "86", name: "Real Madrid", short: "Real Madrid", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/86.png", leagueId: "esp.1", national: false },
  { id: "83", name: "Barcelona", short: "Barcelona", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/83.png", leagueId: "esp.1", national: false },
  { id: "1068", name: "Atlético Madrid", short: "Atlético", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/1068.png", leagueId: "esp.1", national: false },
  { id: "382", name: "Manchester City", short: "Man City", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/382.png", leagueId: "eng.1", national: false },
  { id: "360", name: "Manchester United", short: "Man Utd", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/360.png", leagueId: "eng.1", national: false },
  { id: "364", name: "Liverpool", short: "Liverpool", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/364.png", leagueId: "eng.1", national: false },
  { id: "359", name: "Arsenal", short: "Arsenal", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/359.png", leagueId: "eng.1", national: false },
  { id: "363", name: "Chelsea", short: "Chelsea", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/363.png", leagueId: "eng.1", national: false },
  { id: "367", name: "Tottenham Hotspur", short: "Spurs", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/367.png", leagueId: "eng.1", national: false },
  { id: "132", name: "Bayern Munich", short: "Bayern", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/132.png", leagueId: "ger.1", national: false },
  { id: "124", name: "Borussia Dortmund", short: "Dortmund", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/124.png", leagueId: "ger.1", national: false },
  { id: "131", name: "Bayer Leverkusen", short: "Leverkusen", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/131.png", leagueId: "ger.1", national: false },
  { id: "111", name: "Juventus", short: "Juventus", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/111.png", leagueId: "ita.1", national: false },
  { id: "110", name: "Internazionale", short: "Inter Milan", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/110.png", leagueId: "ita.1", national: false },
  { id: "103", name: "AC Milan", short: "Milan", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/103.png", leagueId: "ita.1", national: false },
  { id: "114", name: "Napoli", short: "Napoli", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/114.png", leagueId: "ita.1", national: false },
  { id: "160", name: "Paris Saint-Germain", short: "PSG", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/160.png", leagueId: "fra.1", national: false },
  { id: "176", name: "Marseille", short: "Marseille", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/176.png", leagueId: "fra.1", national: false },
  { id: "1929", name: "Benfica", short: "Benfica", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/1929.png", leagueId: "por.1", national: false },
  { id: "437", name: "FC Porto", short: "FC Porto", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/437.png", leagueId: "por.1", national: false },
  { id: "2250", name: "Sporting CP", short: "Sporting", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/2250.png", leagueId: "por.1", national: false },
  { id: "139", name: "Ajax Amsterdam", short: "Ajax", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/139.png", leagueId: "ned.1", national: false },
  { id: "432", name: "Galatasaray", short: "Galatasaray", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/432.png", leagueId: "tur.1", national: false },
  { id: "436", name: "Fenerbahce", short: "Fenerbahce", logo: "https://a.espncdn.com/i/teamlogos/soccer/500/436.png", leagueId: "tur.1", national: false },
  { id: "20232", name: "Inter Miami CF", short: "Miami", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/20232.png", leagueId: "usa.1", national: false },
  { id: "817", name: "Al Nassr", short: "Al Nassr", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/817.png", leagueId: "ksa.1", national: false },
  { id: "929", name: "Al Hilal", short: "Al Hilal", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/929.png", leagueId: "ksa.1", national: false },
  { id: "2276", name: "Al Ittihad", short: "Al Ittihad", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/2276.png", leagueId: "ksa.1", national: false },
  { id: "8392", name: "Zamalek", short: "Zamalek", logo: "", leagueId: "caf.champions", national: false },
  { id: "20220", name: "Pyramids FC", short: "Pyramids FC", logo: "", leagueId: "caf.champions", national: false },
  { id: "7084", name: "Mamelodi Sundowns", short: "M Sundowns", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/7084.png", leagueId: "caf.champions", national: false },
  { id: "819", name: "Flamengo", short: "Flamengo", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/819.png", leagueId: "bra.1", national: false },
  { id: "10207", name: "Al Ahly", short: "Al Ahly", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/10207.png", leagueId: "caf.champions", national: false },
  { id: "21801", name: "AS FAR", short: "AS FAR", logo: "", leagueId: "caf.champions", national: false },
  { id: "8618", name: "Raja Casablanca", short: "Raja", logo: "", leagueId: "caf.champions", national: false },
  { id: "8625", name: "Wydad AC", short: "Wydad", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/8625.png", leagueId: "caf.champions", national: false },
  { id: "2029", name: "Palmeiras", short: "Palmeiras", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/2029.png", leagueId: "bra.1", national: false },
  { id: "5", name: "Boca Juniors", short: "Boca", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/5.png", leagueId: "arg.1", national: false },
  { id: "16", name: "River Plate", short: "River Plate", logo: "https://a.espncdn.com/i/teamlogos/soccer/500-dark/16.png", leagueId: "arg.1", national: false },
  { id: "2869", name: "Morocco", short: "Morocco", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/mar.png", leagueId: "fifa.friendly", national: true },
  { id: "164", name: "Spain", short: "Spain", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/esp.png", leagueId: "fifa.friendly", national: true },
  { id: "478", name: "France", short: "France", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/fra.png", leagueId: "fifa.friendly", national: true },
  { id: "205", name: "Brazil", short: "Brazil", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/bra.png", leagueId: "fifa.friendly", national: true },
  { id: "202", name: "Argentina", short: "Argentina", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/arg.png", leagueId: "fifa.friendly", national: true },
  { id: "448", name: "England", short: "England", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/eng.png", leagueId: "fifa.friendly", national: true },
  { id: "481", name: "Germany", short: "Germany", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/ger.png", leagueId: "fifa.friendly", national: true },
  { id: "482", name: "Portugal", short: "Portugal", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/por.png", leagueId: "fifa.friendly", national: true },
  { id: "162", name: "Italy", short: "Italy", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/ita.png", leagueId: "fifa.friendly", national: true },
  { id: "449", name: "Netherlands", short: "Netherlands", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/ned.png", leagueId: "fifa.friendly", national: true },
  { id: "459", name: "Belgium", short: "Belgium", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/bel.png", leagueId: "fifa.friendly", national: true },
  { id: "477", name: "Croatia", short: "Croatia", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/cro.png", leagueId: "fifa.friendly", national: true },
  { id: "2620", name: "Egypt", short: "Egypt", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/egy.png", leagueId: "fifa.friendly", national: true },
  { id: "654", name: "Senegal", short: "Senegal", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/sen.png", leagueId: "fifa.friendly", national: true },
  { id: "624", name: "Algeria", short: "Algeria", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/alg.png", leagueId: "fifa.friendly", national: true },
  { id: "659", name: "Tunisia", short: "Tunisia", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/tun.png", leagueId: "fifa.friendly", national: true },
  { id: "657", name: "Nigeria", short: "Nigeria", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/nga.png", leagueId: "fifa.friendly", national: true },
  { id: "4789", name: "Ivory Coast", short: "Ivory Coast", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/civ.png", leagueId: "fifa.friendly", national: true },
  { id: "627", name: "Japan", short: "Japan", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/jpn.png", leagueId: "fifa.friendly", national: true },
  { id: "655", name: "Saudi Arabia", short: "Saudi Arabia", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/ksa.png", leagueId: "fifa.friendly", national: true },
  { id: "451", name: "South Korea", short: "South Korea", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/kors.png", leagueId: "fifa.friendly", national: true },
  { id: "660", name: "United States", short: "USA", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/usa.png", leagueId: "fifa.friendly", national: true },
  { id: "203", name: "Mexico", short: "Mexico", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/mex.png", leagueId: "fifa.friendly", national: true },
  { id: "212", name: "Uruguay", short: "Uruguay", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/uru.png", leagueId: "fifa.friendly", national: true },
  { id: "208", name: "Colombia", short: "Colombia", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/col.png", leagueId: "fifa.friendly", national: true },
  { id: "4398", name: "Qatar", short: "Qatar", logo: "https://a.espncdn.com/i/teamlogos/countries/500-dark/qat.png", leagueId: "fifa.friendly", national: true }
]

function defaultSelected() {
  return ["esp.1", "eng.1", "uefa.champions", "caf.champions", "caf.nations_qual", "mar.1"]
}

function selectedValues(value) {
  if (!value || !value.length) return defaultSelected()
  var out = []
  for (var i = 0; i < value.length && out.length < 40; i++) {
    var id = String(value[i] || "")
    if (/^[a-z0-9._]{2,40}$/.test(id) && out.indexOf(id) < 0) out.push(id)
  }
  return out.length ? out : defaultSelected()
}

function cleanTeam(team) {
  if (!team || !team.id || !/^[0-9]{1,9}$/.test(String(team.id))) return null
  return {
    id: String(team.id),
    name: String(team.name || "Team").slice(0, 60),
    short: String(team.short || team.name || "Team").slice(0, 30),
    logo: /^https:\/\//.test(String(team.logo || "")) ? String(team.logo) : "",
    leagueId: /^[a-z0-9._]{2,40}$/.test(String(team.leagueId || "")) ? String(team.leagueId) : "",
    national: team.national === true
  }
}

// Reads favouriteTeams, migrating the single favoriteTeam of v1.x.
function favoriteTeams(list, legacy) {
  var out = [], seen = {}
  var source = (list && list.length) ? list : (legacy ? [legacy] : [])
  for (var i = 0; i < source.length && out.length < 12; i++) {
    var team = cleanTeam(source[i])
    if (!team || seen[team.id]) continue
    if (!team.logo) team.logo = popularLogo(team.id)
    seen[team.id] = true
    out.push(team)
  }
  return out
}

function popularLogo(id) {
  for (var i = 0; i < popularTeams.length; i++) if (popularTeams[i].id === String(id)) return popularTeams[i].logo
  return ""
}

function teamSpecs(teams) {
  var out = []
  for (var i = 0; i < teams.length; i++) out.push(teams[i].id + ":" + (teams[i].leagueId || ""))
  return out.join(",")
}

function findLeague(id) {
  for (var i = 0; i < leagues.length; i++) if (leagues[i].id === id) return leagues[i]
  return null
}

function leagueName(id) {
  var league = findLeague(id)
  return league ? league.name : String(id || "Competition").replace(/[._]/g, " ")
}

function leagueShort(id) {
  var league = findLeague(id)
  return league ? league.short : leagueName(id)
}

function leagueLogo(id) {
  var league = findLeague(id)
  return league ? league.logo : ""
}

function leaguesInRegion(region, query) {
  var q = String(query || "").trim().toLowerCase(), out = []
  for (var i = 0; i < leagues.length; i++) {
    var l = leagues[i]
    if (l.region !== region) continue
    if (q && l.name.toLowerCase().indexOf(q) < 0 && l.id.indexOf(q) < 0 && l.short.toLowerCase().indexOf(q) < 0) continue
    out.push(l)
  }
  return out
}

function fold(text) {
  var s = String(text || "")
  try { s = s.normalize("NFD").replace(/[̀-ͯ]/g, "") } catch (e) {}
  return s.toLowerCase()
}

var teamAliases = { "barca": "barcelona", "barça": "barcelona", "psg": "paris", "wac": "wydad", "rca": "raja",
  "asfar": "far", "far rabat": "far", "man utd": "manchester united", "man city": "manchester city",
  "spurs": "tottenham", "inter": "internazionale", "atleti": "atletico", "maroc": "morocco", "al-ahly": "ahly" }

function matchesTeamQuery(team, query) {
  var q = fold(query).trim()
  if (!q) return true
  var hay = fold(team.name + " " + team.short)
  if (hay.indexOf(q) >= 0) return true
  var alias = teamAliases[q]
  return Boolean(alias && hay.indexOf(alias) >= 0)
}

function popularMatching(query, national) {
  var out = []
  for (var i = 0; i < popularTeams.length; i++) {
    var t = popularTeams[i]
    if (national !== undefined && national !== null && t.national !== national) continue
    if (matchesTeamQuery(t, query)) out.push(t)
  }
  return out
}

function groupMatchesByLeague(matches, selectedLeagues) {
  if (!matches || !matches.length) return []
  var groups = {}, order = []
  var selected = selectedLeagues || []
  for (var m = 0; m < matches.length; m++) {
    var match = matches[m], id = match.leagueId || "other"
    if (!groups[id]) {
      groups[id] = { leagueId: id, leagueName: findLeague(id) ? leagueName(id) : (match.league || leagueName(id)),
                     leagueLogo: leagueLogo(id) || match.leagueLogo || "", round: match.round || "", matches: [], live: 0 }
      order.push(id)
    }
    if (!groups[id].round && match.round) groups[id].round = match.round
    if (match.state === "in") groups[id].live++
    groups[id].matches.push(match)
  }
  order.sort(function(a, b) {
    var la = groups[a].live > 0 ? 0 : 1, lb = groups[b].live > 0 ? 0 : 1
    if (la !== lb) return la - lb
    var ia = selected.indexOf(a), ib = selected.indexOf(b)
    return (ia < 0 ? 999 : ia) - (ib < 0 ? 999 : ib)
  })
  var result = []
  for (var k = 0; k < order.length; k++) result.push(groups[order[k]])
  return result
}

function groupByDay(matches) {
  var out = [], current = null
  for (var i = 0; i < (matches || []).length; i++) {
    var d = new Date(matches[i].date)
    var key = isNaN(d.getTime()) ? "?" : d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate()
    if (!current || current.key !== key) {
      current = { key: key, label: isNaN(d.getTime()) ? "Date to be confirmed" : formatDayLabel(d), matches: [] }
      out.push(current)
    }
    current.matches.push(matches[i])
  }
  return out
}

function sameLocalDay(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

function pad(n) { return (n < 10 ? "0" : "") + n }

function formatMatchTime(value) {
  var date = new Date(value)
  if (!value || isNaN(date.getTime())) return "—"
  return pad(date.getHours()) + ":" + pad(date.getMinutes())
}

var shortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var shortDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function startOfToday() {
  var now = new Date()
  return new Date(now.getFullYear(), now.getMonth(), now.getDate())
}

function relativeDay(date) {
  var now = new Date()
  var today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  var day = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  return Math.round((day - today) / 86400000)
}

function shortWhen(value) {
  var date = new Date(value)
  if (!value || isNaN(date.getTime())) return ""
  var diff = relativeDay(date)
  var time = formatMatchTime(value)
  if (diff === 0) return "Today " + time
  if (diff === 1) return "Tomorrow " + time
  if (diff === -1) return "Yesterday"
  if (diff > 1 && diff < 7) return shortDays[date.getDay()] + " " + time
  return date.getDate() + " " + shortMonths[date.getMonth()] + (diff >= 0 ? " " + time : "")
}

function formatDayLabel(date) {
  var diff = relativeDay(date)
  var label = date.getDate() + " " + shortMonths[date.getMonth()]
  if (diff === 0) return "Today · " + label
  if (diff === 1) return "Tomorrow · " + label
  if (diff === -1) return "Yesterday · " + label
  return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][date.getDay()] + " · " + label
}

function formatMonthLabel(date) {
  var months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
  return months[date.getMonth()] + " " + date.getFullYear()
}

function formatDateParam(date) {
  return "" + date.getFullYear() + pad(date.getMonth() + 1) + pad(date.getDate())
}

function countdown(value) {
  var ms = new Date(value).getTime() - Date.now()
  if (isNaN(ms) || ms <= 0) return ""
  var mins = Math.floor(ms / 60000)
  if (mins < 60) return "in " + mins + " min"
  var hours = Math.floor(mins / 60)
  if (hours < 24) return "in " + hours + "h " + pad(mins % 60) + "m"
  var days = Math.floor(hours / 24)
  return "in " + days + (days === 1 ? " day" : " days")
}

function liveLabel(match) {
  if (!match) return ""
  if (match.detail === "HT") return "HT"
  return match.clock || match.detail || "LIVE"
}

// Bar text: a live favourite first, otherwise the soonest upcoming one.
function pickBarMatch(teamMatches, teams) {
  var best = null
  for (var i = 0; i < teams.length; i++) {
    var m = teamMatches[teams[i].id]
    if (!m) continue
    var rank = m.state === "in" ? 0 : (m.state === "post" ? 1 : 2)
    var t = new Date(m.date).getTime()
    if (!best || rank < best.rank || (rank === best.rank && t < best.time)) best = { rank: rank, time: t, match: m, team: teams[i] }
  }
  return best
}

function formatBarLabel(teamMatches, teams) {
  if (!teams || !teams.length) return "Football"
  var best = pickBarMatch(teamMatches || {}, teams)
  if (!best) return teams[0].short + " · No match"
  var m = best.match, name = best.team.short || best.team.name
  if (m.state === "in")
    return "● " + m.home + " " + m.homeScore + "-" + m.awayScore + " " + m.away + " " + liveLabel(m)
  if (m.state === "post")
    return m.home + " " + m.homeScore + "-" + m.awayScore + " " + m.away + " · FT"
  return name + " vs " + m.opponent + " · " + shortWhen(m.date)
}
