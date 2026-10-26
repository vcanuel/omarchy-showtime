# Showtime

Never miss a meeting again. Showtime puts your next calendar event in the
Omarchy bar and, a minute before it starts, takes over the whole screen with
a splash you cannot ignore — on top of fullscreen windows too — with a
**Join** button that opens the Teams, Zoom, Meet, Webex, Whereby, Jitsi or
Slack link found in the event.

- **In the bar:** the event in progress (`Standup · 12 min left`) or the next
  one (`Design review · in 8 min`, or its time when it is further away),
  turning to the urgent color five minutes before. Hover for the rest of
  today's agenda.
- **The splash:** title, time, place and a live countdown.
  <kbd>Enter</kbd> joins, <kbd>S</kbd> brings it back in a minute,
  <kbd>Esc</kbd> dismisses. If your laptop was asleep when it was due, it
  still shows up to three minutes after the start.
- **Any calendar** that publishes an ICS feed: Outlook / Microsoft 365,
  Google Calendar, iCloud, Fastmail, Proton, Nextcloud… several at once.
  Recurring events, time zones (including Outlook's Windows zone names) and
  cancelled occurrences are handled.
- All-day events and events marked **free** never interrupt you.
- Follows your Omarchy theme and language (English and French so far).

## Install

```bash
sudo pacman -S --needed python-icalendar python-recurring-ical-events
omarchy plugin add https://github.com/vcanuel/omarchy-showtime.git --enable
```

## Add your calendars

Put one ICS URL per line in `~/.config/omarchy/showtime/calendars`
(`https://` or `webcal://`, `#` comments allowed), then sync with a middle
click on the widget or `omarchy-shell vcanuel.showtime sync`:

```bash
mkdir -p ~/.config/omarchy/showtime
$EDITOR ~/.config/omarchy/showtime/calendars
chmod 600 ~/.config/omarchy/showtime/calendars
```

A published calendar URL lets anyone who has it read your calendar: keep that
file private.

Where to find the URL:

- **Outlook / Microsoft 365:** Outlook on the web → Settings → Calendar →
  Shared calendars → *Publish a calendar*. Choose **Can view all details**
  (otherwise every title reads *Busy*), then copy the **ICS** link. Your
  organization may have publishing turned off.
- **Google Calendar:** Settings → your calendar → *Integrate calendar* →
  **Secret address in iCal format**.
- **iCloud:** Calendar app → share the calendar as a **Public Calendar** and
  copy the `webcal://` link.

Calendars are fetched every five minutes. Published feeds can themselves lag
behind the calendar by a few minutes (Outlook up to about half an hour), so a
meeting added at the last minute may not show up in time.

## Settings

The widget's settings live in its entry in `~/.config/omarchy/shell.json`:

| Key | Default | |
|---|---|---|
| `maxTitleLength` | `28` | Longest title shown in the bar |
| `lookaheadHours` | `12` | Show the next event when it starts within this many hours |
| `calendarUrl` | `""` | Page opened by a right click, e.g. `https://outlook.office.com/calendar/view/day` |

The splash reads an optional `~/.config/omarchy/showtime/settings.json`:

```json
{ "leadSeconds": 60, "graceSeconds": 180, "snoozeSeconds": 60, "syncMinutes": 5 }
```

## Commands

```bash
omarchy-shell vcanuel.showtime test     # show the splash now
omarchy-shell vcanuel.showtime sync     # fetch the calendars
omarchy-shell vcanuel.showtime join     # join the current or next meeting
omarchy-shell vcanuel.showtime dismiss  # close the splash
```

`join` makes a handy keybinding, e.g. in `~/.config/hypr/bindings.lua`.

## How it works

`bin/showtime-sync` downloads each feed (HTTPS only, 20 MB cap, 30 s
timeout), expands the next 48 hours of events and writes them to
`~/.local/state/omarchy/showtime/events.json`. When a feed cannot be reached,
the last good copy stays in place. The shell service runs it on a timer and
watches the file; the bar widget only reads it. Event text is always rendered
as plain text, and only `https://` meeting links are ever opened.

## Tests

```bash
node tests/showtime.test.js
python3 -I tests/test_sync.py
```

## Remove

```bash
omarchy plugin remove vcanuel.showtime
rm -rf ~/.config/omarchy/showtime ~/.local/state/omarchy/showtime
```

## License

MIT
