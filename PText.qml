import QtQuick
import qs.Commons
import qs.Commons as Commons

// Plain-text label: network data must never be rendered as rich text.
Text {
  textFormat: Text.PlainText
  color: Commons.Color.foreground
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  elide: Text.ElideRight
  verticalAlignment: Text.AlignVCenter
}
