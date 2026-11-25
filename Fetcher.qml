import QtQuick
import Quickshell.Io

// One api.py request stream.  A request made while another is running
// replaces any queued one, so only the newest pending request runs next.
// Results are reported with the key they were requested for, letting the
// panel cache every answer and ignore ones that are no longer on screen.
Item {
  id: root
  visible: false
  property string scriptPath: ""
  property string runningKey: ""
  property string queuedKey: ""
  property var queuedArgs: null
  readonly property bool busy: proc.running || queuedArgs !== null

  signal done(string key, string text)

  function request(key, args) {
    if (proc.running) {
      if (key === runningKey) { queuedKey = ""; queuedArgs = null; return }
      queuedKey = key
      queuedArgs = args
      return
    }
    start(key, args)
  }

  function start(key, args) {
    runningKey = key
    proc.command = ["python3", root.scriptPath].concat(args)
    proc.running = true
  }

  function finished(text) {
    var key = runningKey
    runningKey = ""
    if (queuedArgs !== null) {
      var nextKey = queuedKey, nextArgs = queuedArgs
      queuedKey = ""; queuedArgs = null
      start(nextKey, nextArgs)
    }
    root.done(key, text)
  }

  Process {
    id: proc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finished(String(text || "").trim())
    }
  }
}
