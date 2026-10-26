// node tests/showtime.test.js — runs Showtime.js outside the shell.
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const vm = require("vm")

// QML's String.prototype.arg: fill the lowest %n placeholder.
const qmlArg = `String.prototype.arg = function(v) {
  var n = (this.match(/%(\\d)/g) || []).map(function(s) { return +s[1] }).sort()[0]
  return this.replace("%" + n, String(v))
};`
const src = qmlArg + fs.readFileSync(path.join(__dirname, "..", "Showtime.js"), "utf8").replace(".pragma library", "")
const S = {}
vm.runInNewContext(src, S)

const strings = { t: k => ({ "duration.minutes": "%1 min", "duration.hours": "%1 h", "duration.hoursMinutes": "%1 h %2" })[k] }
const iso = ms => new Date(ms).toISOString()
const now = Date.parse("2026-10-26T10:00:00Z")
const ev = (id, startMin, endMin, extra) => Object.assign(
  { id, title: id, start: iso(now + startMin * 60000), end: iso(now + endMin * 60000) }, extra || {})

const parsed = S.parse(JSON.stringify({ error: "partial", events: [
  ev("running", -20, 10),
  ev("next", 5, 35, { joinUrl: "https://teams.microsoft.com/l/meetup-join/x" }),
  ev("later", 120, 150, { joinUrl: "javascript:alert(1)" }),
  ev("free", 1, 30, { free: true }),
  ev("allday", -600, 840, { allDay: true }),
  { id: "broken", start: "nope", end: "nope" },
] }))
const events = parsed.events
// Arrays built inside the vm context are not deepStrictEqual to ours.
const ids = list => Array.from(list, e => e.id)

assert.strictEqual(parsed.error, "partial")
assert.strictEqual(S.parse('{"error":"<img src=x>"}').error, "", "unknown error codes are dropped")
assert.strictEqual(S.parse("not json").events.length, 0)
assert.strictEqual(events.length, 5, "events with unparsable dates are dropped")
assert.strictEqual(events.find(e => e.id === "later").joinUrl, "", "only https join links are kept")

assert.strictEqual(S.current(events, now)[0].id, "running")
assert.deepStrictEqual(ids(S.upcoming(events, now)), ["free", "next", "later"])
assert.strictEqual(S.joinable(events, now).id, "next", "an event starting soon beats the running one")
assert.strictEqual(S.joinable(events, now - 60 * 60000).id, "next", "only events with a link are joinable")

const lead = 60000, grace = 180000
assert.deepStrictEqual(ids(S.due(events, now + 4 * 60000, lead, grace)), ["next"], "free events never splash")
assert.deepStrictEqual(ids(S.due(events, now, lead, grace)), [], "nothing due yet")
assert.deepStrictEqual(ids(S.due(events, now + 7 * 60000, lead, grace)), ["next"], "still due within grace")
assert.deepStrictEqual(ids(S.due(events, now + 9 * 60000, lead, grace)), [], "gone after grace")

assert.strictEqual(S.durationText(30000, strings), "1 min")
assert.strictEqual(S.durationText(60 * 60000, strings), "1 h")
assert.strictEqual(S.durationText(65 * 60000, strings), "1 h 05")
assert.strictEqual(S.shorten("Quarterly business review", 10), "Quarterly…")

console.log("ok")
