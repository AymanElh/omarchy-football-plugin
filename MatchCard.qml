import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// Compact score-app style row:  status | home  crest  score  crest  away
Rectangle {
  id: root
  property var match: ({})
  property bool showDate: false
  property bool showLeague: false
  property var favoriteIds: []
  property string perspectiveTeamId: ""
  signal activated()

  readonly property bool live: match.state === "in"
  readonly property bool finished: match.state === "post"
  readonly property bool favourite: favoriteIds.indexOf(String(match.homeId)) >= 0 || favoriteIds.indexOf(String(match.awayId)) >= 0
  readonly property string outcome: {
    if (!finished || !perspectiveTeamId) return ""
    var home = String(match.homeId) === perspectiveTeamId
    if (!home && String(match.awayId) !== perspectiveTeamId) return ""
    var hs = parseInt(match.homeScore), as = parseInt(match.awayScore)
    if (isNaN(hs) || isNaN(as)) return ""
    if (hs === as) return (match.homeWinner || match.awayWinner) ? ((home ? match.homeWinner : match.awayWinner) ? "W" : "L") : "D"
    return (home ? hs > as : as > hs) ? "W" : "L"
  }
  readonly property color fg: Commons.Color.foreground
  readonly property color liveColor: "#ef4444"

  width: parent ? parent.width : 300
  implicitHeight: content.implicitHeight + Style.space(12)
  radius: Style.cornerRadius
  color: hover.containsMouse ? Qt.rgba(fg.r, fg.g, fg.b, 0.09)
         : (favourite ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.10) : Qt.rgba(fg.r, fg.g, fg.b, 0.035))
  border.width: 1
  border.color: live ? Qt.rgba(liveColor.r, liveColor.g, liveColor.b, 0.55)
                : (favourite ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.45) : Qt.rgba(fg.r, fg.g, fg.b, 0.07))
  Behavior on color { ColorAnimation { duration: Style.duration(120) } }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(3)

    PText {
      visible: root.showLeague || !!(root.match.round && root.showDate)
      width: parent.width
      text: (root.showLeague ? (Model.findLeague(root.match.leagueId) ? Model.leagueName(root.match.leagueId) : (root.match.league || "")) : "")
            + (root.showLeague && root.match.round ? " · " : "") + (root.match.round || "")
      font.pixelSize: Style.font.caption
      color: Commons.Color.muted
    }

    Item {
      width: parent.width
      height: Math.max(statusCol.implicitHeight, Style.space(26))

      // Status / time column
      Column {
        id: statusCol
        width: Style.space(root.showDate ? 58 : 46)
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        PText {
          width: parent.width
          visible: root.showDate
          text: {
            var d = new Date(root.match.date)
            if (isNaN(d.getTime())) return ""
            var rel = Model.relativeDay(d)
            if (rel === 0) return "Today"
            if (rel === 1) return "Tomorrow"
            if (rel === -1) return "Yesterday"
            return Model.shortDays[d.getDay()] + " " + d.getDate() + " " + Model.shortMonths[d.getMonth()]
          }
          font.pixelSize: Style.font.caption
          color: Commons.Color.muted
        }
        Row {
          spacing: Style.space(4)
          Rectangle {
            visible: root.live
            width: Style.space(6); height: width; radius: width / 2
            color: root.liveColor
            anchors.verticalCenter: parent.verticalCenter
            SequentialAnimation on opacity {
              running: root.live && Style.duration(1000) > 0
              loops: Animation.Infinite
              NumberAnimation { to: 0.25; duration: 700 }
              NumberAnimation { to: 1; duration: 700 }
            }
          }
          PText {
            text: root.live ? Model.liveLabel(root.match)
                  : (root.finished ? (root.match.detail && root.match.detail !== "Scheduled" ? root.match.detail : "FT")
                  : (root.match.detail && root.match.detail !== "Scheduled" ? root.match.detail : Model.formatMatchTime(root.match.date)))
            width: statusCol.width - (root.live ? Style.space(10) : 0)
            font.pixelSize: Style.font.bodySmall
            font.bold: root.live
            color: root.live ? root.liveColor : (root.finished ? Commons.Color.muted : root.fg)
          }
        }
      }

      // Teams + score
      Item {
        anchors.left: statusCol.right
        anchors.right: outcomeBadge.visible ? outcomeBadge.left : parent.right
        anchors.rightMargin: outcomeBadge.visible ? Style.space(6) : 0
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height

        PText {
          id: homeName
          anchors.left: parent.left
          anchors.right: homeCrest.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          text: root.match.home || ""
          font.bold: root.finished && root.match.homeWinner
          color: root.favoriteIds.indexOf(String(root.match.homeId)) >= 0 ? Commons.Color.accent : root.fg
        }
        TeamLogo {
          id: homeCrest
          anchors.right: scoreBox.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          size: Style.space(20)
          source: root.match.homeLogo || ""
          name: root.match.home || ""
        }
        Rectangle {
          id: scoreBox
          anchors.centerIn: parent
          anchors.horizontalCenterOffset: 0
          width: Style.space(50)
          height: Style.space(22)
          radius: Style.cornerRadius
          color: root.live ? Qt.rgba(root.liveColor.r, root.liveColor.g, root.liveColor.b, 0.16)
                 : (root.match.state === "pre" ? "transparent" : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08))
          PText {
            anchors.centerIn: parent
            text: root.match.state === "pre" ? "vs" : ((root.match.homeScore || "0") + " - " + (root.match.awayScore || "0"))
            font.bold: root.match.state !== "pre"
            font.pixelSize: root.match.state === "pre" ? Style.font.bodySmall : Style.font.body
            color: root.live ? root.liveColor : (root.match.state === "pre" ? Commons.Color.muted : root.fg)
          }
        }
        TeamLogo {
          id: awayCrest
          anchors.left: scoreBox.right
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          size: Style.space(20)
          source: root.match.awayLogo || ""
          name: root.match.away || ""
        }
        PText {
          anchors.left: awayCrest.right
          anchors.leftMargin: Style.space(6)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.match.away || ""
          font.bold: root.finished && root.match.awayWinner
          color: root.favoriteIds.indexOf(String(root.match.awayId)) >= 0 ? Commons.Color.accent : root.fg
        }
      }

      Rectangle {
        id: outcomeBadge
        visible: root.outcome !== ""
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(20); height: width
        radius: Style.cornerRadius
        color: root.outcome === "W" ? "#16a34a" : (root.outcome === "L" ? "#dc2626" : "#6b7280")
        PText {
          anchors.centerIn: parent
          text: root.outcome
          font.pixelSize: Style.font.caption
          font.bold: true
          color: "#ffffff"
        }
      }
    }

    PText {
      visible: root.live && root.match.goals && root.match.goals.length > 0
      width: parent.width
      leftPadding: statusCol.width
      text: {
        var g = root.match.goals || [], parts = []
        for (var i = Math.max(0, g.length - 3); i < g.length; i++) parts.push("⚽ " + g[i].player + " " + g[i].clock)
        return parts.join("   ")
      }
      font.pixelSize: Style.font.caption
      color: Commons.Color.muted
    }
  }
}
