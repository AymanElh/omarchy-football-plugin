import QtQuick
import qs.Commons
import qs.Commons as Commons

// Both starting XIs drawn on one vertical pitch, like score apps:
// away team in the top half attacking down, home team in the bottom half
// attacking up.  Rows come from the backend (goalkeeper -> attack), each
// ordered from the player's left to right.
Item {
  id: root
  property var homeRows: []
  property var awayRows: []
  property string homeName: ""
  property string awayName: ""
  property string homeFormation: ""
  property string awayFormation: ""
  property color homeColor: "#38bdf8"
  property color awayColor: "#f97316"

  readonly property real pad: Style.space(10)
  readonly property color line: Qt.rgba(1, 1, 1, 0.42)
  implicitHeight: Math.round(width * 1.42)

  // ---- turf ----
  Rectangle {
    id: turf
    anchors.fill: parent
    radius: Style.cornerRadius
    color: "#1d6b3a"
    clip: true
    Column {
      anchors.fill: parent
      Repeater {
        model: 12
        delegate: Rectangle {
          required property int index
          width: turf.width
          height: turf.height / 12
          color: index % 2 === 0 ? Qt.rgba(1, 1, 1, 0.035) : "transparent"
        }
      }
    }
  }

  // ---- markings ----
  Item {
    id: field
    anchors.fill: parent
    anchors.margins: root.pad
    readonly property real boxW: width * 0.58
    readonly property real boxH: height * 0.14
    readonly property real smallW: width * 0.28
    readonly property real smallH: height * 0.055

    Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1.5; border.color: root.line }
    Rectangle { width: parent.width; height: 1.5; y: parent.height / 2; color: root.line }
    Rectangle {
      width: parent.width * 0.26; height: width; radius: width / 2
      anchors.centerIn: parent
      color: "transparent"; border.width: 1.5; border.color: root.line
    }
    Rectangle { width: 5; height: 5; radius: 2.5; anchors.centerIn: parent; color: root.line }
    // top boxes
    Rectangle { width: field.boxW; height: field.boxH; anchors.horizontalCenter: parent.horizontalCenter; y: 0
      color: "transparent"; border.width: 1.5; border.color: root.line }
    Rectangle { width: field.smallW; height: field.smallH; anchors.horizontalCenter: parent.horizontalCenter; y: 0
      color: "transparent"; border.width: 1.5; border.color: root.line }
    // bottom boxes
    Rectangle { width: field.boxW; height: field.boxH; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - height
      color: "transparent"; border.width: 1.5; border.color: root.line }
    Rectangle { width: field.smallW; height: field.smallH; anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - height
      color: "transparent"; border.width: 1.5; border.color: root.line }
  }

  // ---- team labels ----
  PText {
    x: root.pad + Style.space(6); y: root.pad + Style.space(4)
    text: root.awayName + (root.awayFormation ? "  " + root.awayFormation : "")
    font.pixelSize: Style.font.caption; font.bold: true
    color: Qt.rgba(1, 1, 1, 0.85)
  }
  PText {
    x: root.pad + Style.space(6); y: root.height - root.pad - height - Style.space(4)
    text: root.homeName + (root.homeFormation ? "  " + root.homeFormation : "")
    font.pixelSize: Style.font.caption; font.bold: true
    color: Qt.rgba(1, 1, 1, 0.85)
  }

  // ---- players ----
  Repeater {
    model: root.layoutPlayers(root.awayRows, false, root.width, root.height)
    delegate: playerMarker
  }
  Repeater {
    model: root.layoutPlayers(root.homeRows, true, root.width, root.height)
    delegate: playerMarker
  }

  function layoutPlayers(rows, home, w, h) {
    var out = []
    if (!rows || !rows.length || w <= 0 || h <= 0) return out
    var top = pad + Style.space(18), bottom = h - pad - Style.space(18)
    var half = (bottom - top) / 2
    var n = rows.length
    for (var r = 0; r < n; r++) {
      var row = rows[r] || []
      // goalkeeper near own goal line, last line a little short of halfway
      var t = n > 1 ? r / (n - 1) : 0
      var depth = 0.06 + t * 0.80
      var y = home ? bottom - depth * half : top + depth * half
      for (var i = 0; i < row.length; i++) {
        var frac = (i + 0.5) / row.length
        // away team faces down the screen, so its left is the screen's right
        var x = pad + (home ? frac : 1 - frac) * (w - 2 * pad)
        out.push({ player: row[i], x: x, y: y, home: home })
      }
    }
    return out
  }

  Component {
    id: playerMarker
    Item {
      required property var modelData
      readonly property var p: modelData.player || ({})
      readonly property color kit: modelData.home ? root.homeColor : root.awayColor
      width: Math.min(Style.space(76), root.width / 5.2)
      height: shirt.height + nameTag.height + 2
      x: modelData.x - width / 2
      y: modelData.y - shirt.height / 2

      Rectangle {
        id: shirt
        width: Style.space(26); height: width; radius: width / 2
        anchors.horizontalCenter: parent.horizontalCenter
        color: parent.kit
        border.width: 2
        border.color: Qt.rgba(1, 1, 1, 0.9)
        PText {
          anchors.centerIn: parent
          text: p.number || ""
          font.pixelSize: Style.font.caption
          font.bold: true
          color: "#0b1220"
        }
        // goal badge
        Rectangle {
          visible: (p.goals || 0) > 0
          width: Style.space(15); height: width; radius: width / 2
          x: parent.width - width * 0.55; y: -height * 0.35
          color: "#ffffff"
          PText {
            anchors.centerIn: parent
            text: (p.goals || 0) > 1 ? String(p.goals) : "⚽"
            font.pixelSize: Style.font.caption * 0.8
            font.bold: true
            color: "#0b1220"
          }
        }
        // card badge
        Rectangle {
          visible: (p.red || 0) > 0 || (p.yellow || 0) > 0
          width: Style.space(8); height: Style.space(11); radius: 1.5
          x: -width * 0.4; y: -height * 0.3
          color: (p.red || 0) > 0 ? "#ef4444" : "#facc15"
          border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.35)
        }
        // substituted off
        Rectangle {
          visible: p.subbedOff === true
          width: Style.space(13); height: width; radius: width / 2
          x: -width * 0.45; y: parent.height - height * 0.65
          color: "#dc2626"
          PText { anchors.centerIn: parent; text: "↓"; font.pixelSize: Style.font.caption * 0.85; font.bold: true; color: "#ffffff" }
        }
      }
      Rectangle {
        id: nameTag
        anchors.top: shirt.bottom
        anchors.topMargin: 2
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, nameText.implicitWidth + Style.space(8))
        height: nameText.implicitHeight + 2
        radius: Style.cornerRadius
        color: Qt.rgba(0, 0, 0, 0.45)
        PText {
          id: nameText
          anchors.centerIn: parent
          width: parent.width - Style.space(4)
          horizontalAlignment: Text.AlignHCenter
          text: p.short || p.name || ""
          font.pixelSize: Style.font.caption
          color: "#ffffff"
        }
      }
    }
  }
}
