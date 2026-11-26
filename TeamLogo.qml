import QtQuick
import qs.Commons
import qs.Commons as Commons

// Crest with graceful fallbacks: dark ESPN variant -> standard variant ->
// initials badge.
Item {
  id: root
  property string source: ""
  property string name: ""
  property int size: Style.space(22)
  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  property string _src: root.source
  onSourceChanged: _src = root.source

  function initials(text) {
    var words = String(text || "?").replace(/[^A-Za-zÀ-ÿ0-9 ]/g, " ").trim().split(/\s+/)
    if (!words.length || !words[0]) return "?"
    if (words.length === 1) return words[0].slice(0, 3).toUpperCase()
    return (words[0][0] + words[1][0]).toUpperCase()
  }

  Image {
    id: img
    anchors.fill: parent
    source: /^https:\/\//.test(root._src) ? root._src : ""
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    cache: true
    mipmap: true
    smooth: true
    sourceSize.width: 96
    sourceSize.height: 96
    visible: status === Image.Ready
    onStatusChanged: {
      if (status !== Image.Error) return
      if (root._src.indexOf("/500-dark/") >= 0) root._src = root._src.replace("/500-dark/", "/500/")
      else root._src = ""
    }
  }

  Rectangle {
    anchors.fill: parent
    visible: img.status !== Image.Ready
    radius: width / 2
    color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.10)
    border.width: 1
    border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.18)
    PText {
      anchors.centerIn: parent
      text: root.initials(root.name)
      font.pixelSize: Math.max(7, root.size * 0.34)
      font.bold: true
      color: Commons.Color.muted
    }
  }
}
