import QtQuick
import Quickshell.Io

// One api.py request stream.  A request made while another is running
// replaces any queued one, so only the newest pending request runs next.
// Results are reported with the key they were requested for, letting the
// panel cache every answer and ignore ones that are no longer on screen.
//
// api.py bounds its own run time and output; this is the second line of
// defence for the shell: a child that outlives `timeoutMs` is killed, and a
// child that exits without reporting still frees the queue, so a stuck or
// failed request can never leave the fetcher permanently busy.
Item {
  id: root
  visible: false
  property string scriptPath: ""
  property string runningKey: ""
  property string queuedKey: ""
  property var queuedArgs: null
  // Must be longer than the api.py command deadline (25 s, pulse 45 s).
  property int timeoutMs: 35000
  // Cap on what is read back from the child (api.py prints at most 2 MiB).
  readonly property int maxChars: 3 * 1024 * 1024
  readonly property bool busy: proc.running || runningKey !== "" || queuedArgs !== null

  signal done(string key, string text)

  function request(key, args) {
    if (runningKey !== "") {
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
    watchdog.interval = root.timeoutMs
    watchdog.restart()
  }

  function finished(text) {
    watchdog.stop()
    recovery.stop()
    var key = runningKey
    runningKey = ""
    var out = text.length > root.maxChars ? "" : text
    if (queuedArgs !== null) {
      var nextKey = queuedKey, nextArgs = queuedArgs
      queuedKey = ""; queuedArgs = null
      start(nextKey, nextArgs)
    }
    root.done(key, out)
  }

  // The child ran past its deadline: kill it.  Its exit then reports an
  // empty answer through the normal path, which also starts any queued request.
  Timer {
    id: watchdog
    repeat: false
    onTriggered: {
      if (proc.running) proc.signal(9)
      recovery.restart()
    }
  }

  // Backstop: if the process is gone (or never started) but nothing was
  // reported, report an empty answer instead of staying busy forever.
  Timer {
    id: recovery
    interval: 1500
    repeat: false
    onTriggered: if (root.runningKey !== "") root.finished("")
  }

  Process {
    id: proc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.runningKey !== "") root.finished(String(text || "").trim())
    }
    onRunningChanged: if (!running && root.runningKey !== "") recovery.restart()
  }
}
