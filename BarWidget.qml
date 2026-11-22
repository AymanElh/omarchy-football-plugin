import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "ayman.football-matches"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property string label: panelLoader.item ? panelLoader.item.label : "Football"
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.openFromHotkey() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  visible: label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    labelVisible: false
    implicitWidth: vertical ? barSize : content.implicitWidth + scaledHorizontalMargin * 2
    implicitHeight: vertical ? content.implicitHeight + scaledVerticalPadding * 2 : barSize
    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(6)
      scale: button.pressScale
      Image {
        source: Qt.resolvedUrl("assets/football-icon.png")
        width: Style.space(22)
        height: width
        sourceSize.width: 64
        sourceSize.height: 64
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }
      PText {
        visible: !button.vertical
        text: root.label
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton && panelLoader.item) panelLoader.item.refreshAll()
      else root.togglePanel()
    }
  }
}
