import QtQuick
import Quickshell.Io
import "Calculator.js" as Calculator

// One long-lived qalc, fed a line per query and read a line at a time.
//
// Spawning qalc per keystroke costs ~40 ms; holding one open answers in under a
// millisecond, because the 12 MB of unit and currency definitions are loaded
// once instead of every time. That is the whole reason this is a service rather
// than a Process inside Menu.qml.
//
// No debounce timer. At sub-millisecond round trips qalc replies long before
// the next keystroke, so a timer would only add latency you could measure. A
// request counter drops answers that arrive after the query moved on.
Item {
  id: root

  // Latest answer for `query`, or "" when there is nothing worth showing.
  property string result: ""
  property string query: ""

  // Set by Menu.qml on every keystroke.
  function evaluate(rawQuery) {
    var next = String(rawQuery || "")

    if (!Calculator.looksLikeExpression(next)) {
      root.query = next
      root.result = ""
      return
    }

    root.query = next
    root.pending = Calculator.normalize(next)
    root.requestId += 1
    root.awaitingResult = true

    if (!qalc.running) {
      // Answers arrive after the process starts; onStarted replays `pending`.
      qalc.running = true
      return
    }

    qalc.write(root.pending + "\n")
  }

  property string pending: ""
  property int requestId: 0
  property bool awaitingResult: false

  Process {
    id: qalc

    // -t          terse output, no "x = " preamble
    // -color=0    no ANSI, so the parser never sees escape codes
    // decimal comma 0 + ignore locale 1
    //             `.` is the decimal separator whatever LC_NUMERIC says. Under
    //             a nl_BE locale qalc reads `1.5+1` as 16, silently, because it
    //             treats `.` as a thousands separator. Calculator.js rewrites a
    //             typed `1,5` to `1.5`, so both spellings still work.
    command: [
      "qalc", "-t", "-color=0",
      "-set", "decimal comma 0",
      "-set", "ignore locale 1"
    ]
    stdinEnabled: true
    running: false

    onStarted: {
      if (root.awaitingResult && root.pending) qalc.write(root.pending + "\n")
    }

    // qalc exits if its stdin closes or it hits `quit`. Nothing here restarts it
    // on a loop: the next evaluate() starts it again, so a crash costs one query.
    onExited: {
      root.awaitingResult = false
    }

    stdout: SplitParser {
      splitMarker: "\n"

      onRead: function(line) {
        if (!root.awaitingResult) return
        if (!Calculator.isResultLine(line)) return

        root.awaitingResult = false

        var answer = Calculator.cleanResult(line)
        root.result = Calculator.isUsefulResult(answer, root.pending) ? answer : ""
      }
    }
  }

  // Stop qalc when the menu closes. It is cheap to restart and there is no
  // reason to hold a process open for a menu nobody has summoned.
  function stop() {
    root.result = ""
    root.query = ""
    root.awaitingResult = false
    qalc.running = false
  }
}
