import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Showtime.js" as Showtime

// Background half of Showtime, mounted at shell startup:
//   - runs bin/showtime-sync every few minutes to refresh events.json;
//   - shortly before each timed event, takes over the screen with a
//     fullscreen splash: Join (Enter), snooze (S), dismiss (Escape).
// Optional ~/.config/omarchy/showtime/settings.json:
//   { "leadSeconds": 60, "graceSeconds": 180, "snoozeSeconds": 60, "syncMinutes": 5,
//     "splashFollowing": true }
// IPC: omarchy-shell vcanuel.showtime sync|join|dismiss|test
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string eventsPath: home + "/.local/state/omarchy/showtime/events.json"
  readonly property string settingsPath: home + "/.config/omarchy/showtime/settings.json"
  readonly property string syncPath: {
    var url = Qt.resolvedUrl("bin/showtime-sync").toString()
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.substring(7)) : url
  }

  property var settings: ({})
  function setting(name, fallback, min, max) {
    var v = Number(settings[name])
    return isFinite(v) ? Math.min(max, Math.max(min, v)) : fallback
  }
  // How early the splash shows, and how late a missed one (machine asleep,
  // shell restarted) still shows after the start.
  readonly property int leadMs: setting("leadSeconds", 60, 0, 3600) * 1000
  readonly property int graceMs: setting("graceSeconds", 180, 0, 3600) * 1000
  readonly property int snoozeMs: setting("snoozeSeconds", 60, 10, 3600) * 1000
  readonly property int syncIntervalMs: setting("syncMinutes", 5, 1, 120) * 60000
  // Outlook meetings answered with "Follow" rather than accepted.
  readonly property bool splashFollowing: settings.splashFollowing !== false

  property var events: []
  property double nowMs: Date.now()
  property var shownIds: ({})
  property var snoozed: ({})
  property var queue: []
  readonly property var current: queue.length > 0 ? queue[0] : null

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function sync() {
    if (!syncProc.running) syncProc.running = true
  }

  function check() {
    root.nowMs = Date.now()
    var now = root.nowMs
    var added = []
    var due = Showtime.due(root.events, now, root.leadMs, root.graceMs, !root.splashFollowing)
    for (var i = 0; i < due.length; i++) {
      if (root.shownIds[due[i].id]) continue
      root.shownIds[due[i].id] = true
      added.push(due[i])
    }
    for (var id in root.snoozed) {
      if (now >= root.snoozed[id].untilMs) {
        added.push(root.snoozed[id].event)
        delete root.snoozed[id]
      }
    }
    if (added.length > 0) root.queue = root.queue.concat(added)
  }

  function next() {
    root.queue = root.queue.slice(1)
  }

  function join() {
    var e = root.current || Showtime.joinable(root.events, Date.now())
    if (root.current) next()
    if (e && e.joinUrl) Quickshell.execDetached(["xdg-open", e.joinUrl])
  }

  function snooze() {
    var e = root.current
    if (!e) return
    root.snoozed[e.id] = { event: e, untilMs: Date.now() + root.snoozeMs }
    next()
  }

  function dismiss() {
    if (root.current) next()
  }

  // Shows the splash for the next real event, or a sample one.
  function test() {
    var now = Date.now()
    var sample = Showtime.upcoming(root.events, now)[0] || {
      title: strings.t("test.title"), location: "", joinUrl: "",
      startMs: now + root.leadMs, endMs: now + root.leadMs + 30 * 60000
    }
    root.queue = root.queue.concat([Object.assign({}, sample, { id: "test|" + now })])
  }

  function clock(ms) {
    return new Date(ms).toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), Locale.ShortFormat)
  }

  Process {
    id: syncProc
    command: ["timeout", "--kill-after=5s", "90s", root.syncPath]
    onExited: eventsFile.reload()
  }

  FileView {
    id: eventsFile
    path: root.eventsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.events = Showtime.parse(text()).events; root.check() }
    onLoadFailed: root.events = []
  }

  FileView {
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.settings = parsed && typeof parsed === "object" ? parsed : ({})
      } catch (e) {
        root.settings = ({})
      }
    }
    onLoadFailed: root.settings = ({})
  }

  Timer {
    interval: root.syncIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sync()
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.check()
  }

  ShellIpc {
    target: "vcanuel.showtime"

    function sync(): void { root.sync() }
    function join(): void { root.join() }
    function dismiss(): void { root.dismiss() }
    function test(): void { root.test() }
  }

  OverlayWindow {
    id: splash
    shown: root.current !== null
    WlrLayershell.namespace: "vcanuel-showtime"

    readonly property var e: root.current
    readonly property double untilStart: e ? e.startMs - root.nowMs : 0

    onShownChanged: if (shown) Qt.callLater(function() { keys.forceActiveFocus() })

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Commons.Color.background, 0.94)
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) root.dismiss()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (splash.e && splash.e.joinUrl) root.join(); else root.dismiss()
        } else if (event.key === Qt.Key_S) root.snooze()
        else return
        event.accepted = true
      }
    }

    ColumnLayout {
      anchors.centerIn: parent
      width: Math.min(parent.width - Style.space(80), Style.space(900))
      spacing: Style.space(18)

      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        color: splash.untilStart > 0 ? Commons.Color.accent : Commons.Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.display
        font.weight: Font.DemiBold
        text: !splash.e ? ""
          : splash.untilStart > 0 ? strings.t("splash.startsIn").arg(Math.ceil(splash.untilStart / 1000))
          : splash.untilStart > -60000 ? strings.t("splash.startsNow")
          : strings.t("splash.started").arg(Showtime.durationText(-splash.untilStart, strings))
      }

      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.display * 2.4
        font.weight: Font.Bold
        text: splash.e ? splash.e.title : ""
      }

      Text {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Commons.Color.foreground
        opacity: 0.7
        font.family: Style.font.family
        font.pixelSize: Style.font.heading * 1.3
        text: !splash.e ? ""
          : root.clock(splash.e.startMs) + " – " + root.clock(splash.e.endMs)
            + (splash.e.location ? "   ·   " + splash.e.location : "")
            + (root.queue.length > 1 ? "   ·   " + strings.tn("splash.more", root.queue.length - 1).arg(root.queue.length - 1) : "")
      }

      RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Style.space(24)
        spacing: Style.space(14)

        Button {
          visible: !!(splash.e && splash.e.joinUrl)
          text: strings.t("splash.join") + "  ⏎"
          bordered: true
          selected: true
          fontSize: Style.font.heading * 1.2
          horizontalPadding: Style.space(28)
          verticalPadding: Style.space(12)
          onClicked: root.join()
        }
        Button {
          text: strings.t("splash.snooze").arg(Showtime.durationText(root.snoozeMs, strings)) + "  S"
          bordered: true
          fontSize: Style.font.heading * 1.2
          horizontalPadding: Style.space(28)
          verticalPadding: Style.space(12)
          onClicked: root.snooze()
        }
        Button {
          text: strings.t("splash.dismiss") + "  Esc"
          bordered: true
          fontSize: Style.font.heading * 1.2
          horizontalPadding: Style.space(28)
          verticalPadding: Style.space(12)
          onClicked: root.dismiss()
        }
      }
    }
  }
}
