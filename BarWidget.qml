import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Showtime.js" as Showtime

// The event in progress, or the next one, in the bar. Reads the
// events.json the service keeps fresh; left click joins, middle click
// syncs, right click opens the calendarUrl setting.
BarWidget {
  id: root

  property var events: []
  property string error: ""
  property double nowMs: Date.now()

  readonly property string eventsPath: Quickshell.env("HOME") + "/.local/state/omarchy/showtime/events.json"
  readonly property int maxTitle: setting("maxTitleLength", 28)
  readonly property double lookaheadMs: setting("lookaheadHours", 12) * 3600000
  readonly property string calendarUrl: {
    var url = String(setting("calendarUrl", ""))
    return /^https:\/\/[^\s]+$/.test(url) ? url : ""
  }

  readonly property var now: Showtime.current(events, nowMs)[0] || null
  readonly property var next: {
    var e = Showtime.upcoming(events, nowMs)[0]
    return e && e.startMs - nowMs <= lookaheadMs ? e : null
  }
  // An event about to start wins the bar over one that is ending.
  readonly property var shown: next && (!now || next.startMs - nowMs <= 10 * 60000) ? next : now
  readonly property bool soon: !!shown && shown === next && next.startMs - nowMs <= 5 * 60000

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function clock(ms) {
    return new Date(ms).toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), Locale.ShortFormat)
  }

  function label() {
    if (!shown) return "󰃭"
    var title = Showtime.shorten(shown.title, maxTitle)
    if (shown === now) return "󰤙 " + strings.t("bar.now").arg(title).arg(Showtime.durationText(now.endMs - nowMs, strings))
    var until = next.startMs - nowMs
    if (until < 60 * 60000) return "󰃰 " + strings.t("bar.in").arg(title).arg(Showtime.durationText(until, strings))
    return "󰃰 " + strings.t(Showtime.sameDay(next.startMs, nowMs) ? "bar.at" : "bar.tomorrow").arg(title).arg(clock(next.startMs))
  }

  function agenda() {
    var list = events.filter(function(e) { return e.endMs > nowMs && Showtime.sameDay(e.startMs, nowMs) })
    var lines = list.map(function(e) {
      return (e.allDay ? strings.t("tooltip.allDay") : clock(e.startMs) + " – " + clock(e.endMs))
        + "   " + Showtime.shorten(e.title, 60)
    })
    var text = lines.length ? strings.t("tooltip.today") + "\n" + lines.join("\n") : strings.t("tooltip.nothing")
    if (error) text += "\n\n⚠ " + strings.t("error." + error)
    return text + "\n\n" + strings.t("tooltip.hint")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    path: root.eventsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { var p = Showtime.parse(text()); root.events = p.events; root.error = p.error }
    onLoadFailed: { root.events = []; root.error = "not-synced" }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label()
    active: root.soon
    tooltipText: root.agenda()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) Quickshell.execDetached(["omarchy-shell", "vcanuel.showtime", "sync"])
      else if (buttonCode === Qt.RightButton) { if (root.calendarUrl) Quickshell.execDetached(["xdg-open", root.calendarUrl]) }
      else Quickshell.execDetached(["omarchy-shell", "vcanuel.showtime", "join"])
    }
  }
}
