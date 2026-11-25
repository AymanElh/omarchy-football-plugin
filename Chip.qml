import QtQuick
import qs.Commons
import qs.Commons as Commons

// Pill button with an optional crest and trailing glyph.
Rectangle {
  id: root
  property string text: ""
  property string subText: ""
  property string logo: ""
  property bool showLogo: logo !== ""
  property bool selected: false
  property string trailing: ""
  property bool dot: false
  property color dotColor: "#ef4444"
  property real fontSize: Style.font.bodySmall
  signal clicked()

  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent

  implicitHeight: Math.max(Style.space(28), column.implicitHeight + Style.space(8))
  implicitWidth: row.implicitWidth + Style.space(20)
  width: implicitWidth
  height: implicitHeight
  radius: Math.min(height / 2, Style.cornerRadius > 0 ? height / 2 : 0)
  color: selected ? Qt.rgba(accent.r, accent.g, accent.b, 0.20)
         : (mouse.containsMouse ? Qt.rgba(fg.r, fg.g, fg.b, 0.09) : Qt.rgba(fg.r, fg.g, fg.b, 0.04))
  border.width: 1
  border.color: selected ? accent : Qt.rgba(fg.r, fg.g, fg.b, mouse.containsMouse ? 0.30 : 0.14)
  Behavior on color { ColorAnimation { duration: Style.duration(120) } }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)
    Rectangle {
      visible: root.dot
      width: Style.space(6); height: width; radius: width / 2
      color: root.dotColor
      anchors.verticalCenter: parent.verticalCenter
    }
    TeamLogo {
      visible: root.showLogo
      size: Style.space(16)
      source: root.logo
      name: root.text
      anchors.verticalCenter: parent.verticalCenter
    }
    Column {
      id: column
      anchors.verticalCenter: parent.verticalCenter
      PText {
        text: root.text
        font.pixelSize: root.fontSize
        font.bold: root.selected
        color: root.selected ? root.accent : root.fg
        elide: Text.ElideNone
        anchors.horizontalCenter: root.subText ? parent.horizontalCenter : undefined
      }
      PText {
        visible: root.subText !== ""
        text: root.subText
        font.pixelSize: Style.font.caption
        color: Commons.Color.muted
        elide: Text.ElideNone
        anchors.horizontalCenter: parent.horizontalCenter
      }
    }
    PText {
      visible: root.trailing !== ""
      text: root.trailing
      font.pixelSize: root.fontSize
      color: root.selected ? root.accent : Commons.Color.muted
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideNone
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
