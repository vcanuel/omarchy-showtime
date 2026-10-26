.pragma library

// Shared between the bar widget and the splash service: both read the
// events.json written by bin/showtime-sync. Pure functions only, so the
// tests can run them under node.

var ERROR_CODES = ["no-calendars", "missing-deps", "fetch-failed", "partial"]

function parse(text) {
  var parsed
  try { parsed = JSON.parse(text) } catch (err) { return { events: [], error: "" } }
  var list = parsed && Array.isArray(parsed.events) ? parsed.events.slice(0, 500) : []
  return {
    events: list.map(function(e) {
      return {
        id: String(e.id || "").slice(0, 400),
        title: String(e.title || "").slice(0, 200),
        startMs: Date.parse(e.start),
        endMs: Date.parse(e.end),
        allDay: !!e.allDay,
        free: !!e.free,
        location: String(e.location || "").slice(0, 200),
        joinUrl: /^https:\/\/[^\s]+$/.test(String(e.joinUrl || "")) ? String(e.joinUrl).slice(0, 2000) : ""
      }
    }).filter(function(e) { return e.id && !isNaN(e.startMs) && !isNaN(e.endMs) }),
    error: parsed && ERROR_CODES.indexOf(parsed.error) >= 0 ? parsed.error : ""
  }
}

function timed(events) {
  return events.filter(function(e) { return !e.allDay })
}

// Events in progress, most recently started first.
function current(events, nowMs) {
  return timed(events).filter(function(e) { return e.startMs <= nowMs && nowMs < e.endMs })
    .sort(function(a, b) { return b.startMs - a.startMs })
}

function upcoming(events, nowMs) {
  return timed(events).filter(function(e) { return e.startMs > nowMs })
    .sort(function(a, b) { return a.startMs - b.startMs })
}

// The event a click should join, among those with a link: one starting
// within ten minutes beats the one already running, which is usually ending.
function joinable(events, nowMs) {
  var linked = events.filter(function(e) { return e.joinUrl })
  var next = upcoming(linked, nowMs)[0]
  if (next && next.startMs - nowMs <= 10 * 60000) return next
  return current(linked, nowMs)[0] || next || null
}

// Events whose splash is due: starting within leadMs, or started less than
// graceMs ago (the machine was asleep, the shell restarted). Free events
// (TRANSP:TRANSPARENT) never interrupt.
function due(events, nowMs, leadMs, graceMs) {
  return timed(events).filter(function(e) {
    return !e.free && e.startMs - nowMs <= leadMs && nowMs < e.startMs + graceMs
  })
}

function sameDay(a, b) {
  var x = new Date(a), y = new Date(b)
  return x.getFullYear() === y.getFullYear() && x.getMonth() === y.getMonth() && x.getDate() === y.getDate()
}

function shorten(s, max) {
  return s.length > max ? s.slice(0, max - 1).trim() + "…" : s
}

// "12 min", "1 h", "1 h 05" through the plugin's Translations object.
// Rounded up, so "1 min" shows until the very start.
function durationText(ms, strings) {
  var mins = Math.max(0, Math.ceil(ms / 60000))
  if (mins < 60) return strings.t("duration.minutes").arg(mins)
  var h = Math.floor(mins / 60), m = mins % 60
  return m ? strings.t("duration.hoursMinutes").arg(h).arg((m < 10 ? "0" : "") + m)
    : strings.t("duration.hours").arg(h)
}
