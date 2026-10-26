# python3 -I tests/test_sync.py — parses an Outlook-style feed without the network.
import datetime as dt
import importlib.machinery
import importlib.util
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("showtime_sync", os.path.join(HERE, "..", "bin", "showtime-sync"))
spec = importlib.util.spec_from_loader("showtime_sync", loader)
sync = importlib.util.module_from_spec(spec)
loader.exec_module(sync)

FEED = b"""BEGIN:VCALENDAR
VERSION:2.0
PRODID:Microsoft Exchange Server 2010
BEGIN:VTIMEZONE
TZID:Romance Standard Time
BEGIN:STANDARD
DTSTART:16010101T030000
TZOFFSETFROM:+0200
TZOFFSETTO:+0100
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=10
END:STANDARD
BEGIN:DAYLIGHT
DTSTART:16010101T020000
TZOFFSETFROM:+0100
TZOFFSETTO:+0200
RRULE:FREQ=YEARLY;INTERVAL=1;BYDAY=-1SU;BYMONTH=3
END:DAYLIGHT
END:VTIMEZONE
BEGIN:VEVENT
UID:daily
SUMMARY:Daily
DTSTART;TZID=Romance Standard Time:20261001T093000
DTEND;TZID=Romance Standard Time:20261001T094500
RRULE:FREQ=DAILY
X-MICROSOFT-SKYPETEAMSMEETINGURL:https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0
END:VEVENT
BEGIN:VEVENT
UID:cancelled
SUMMARY:Canceled: Retro
DTSTART;TZID=Romance Standard Time:20261026T140000
DTEND;TZID=Romance Standard Time:20261026T150000
END:VEVENT
BEGIN:VEVENT
UID:free
SUMMARY:Lunch
TRANSP:TRANSPARENT
LOCATION:https://meet.google.com/abc-defg-hij
DTSTART;TZID=Romance Standard Time:20261026T120000
DTEND;TZID=Romance Standard Time:20261026T130000
END:VEVENT
BEGIN:VEVENT
UID:holiday
SUMMARY:Holiday
DTSTART;VALUE=DATE:20261026
DTEND;VALUE=DATE:20261027
END:VEVENT
END:VCALENDAR
"""


@unittest.skipIf(sync.icalendar is None, "python-icalendar / python-recurring-ical-events not installed")
class OccurrencesTest(unittest.TestCase):
    def setUp(self):
        utc = dt.timezone.utc
        start = dt.datetime(2026, 10, 26, 0, 0, tzinfo=utc)
        self.events = {e["id"].split("|")[0]: e for e in sync.occurrences(
            FEED, start, start + dt.timedelta(hours=20), utc)}

    def test_windows_timezone_and_recurrence(self):
        # 09:30 Paris on 26 October 2026 is winter time: 08:30 UTC.
        self.assertEqual(self.events["daily"]["start"], "2026-10-26T08:30:00+00:00")
        self.assertTrue(self.events["daily"]["joinUrl"].startswith("https://teams.microsoft.com/l/meetup-join/"))

    def test_cancelled_dropped(self):
        self.assertNotIn("cancelled", self.events)

    def test_free_and_all_day(self):
        self.assertTrue(self.events["free"]["free"])
        self.assertEqual(self.events["free"]["joinUrl"], "https://meet.google.com/abc-defg-hij")
        self.assertTrue(self.events["holiday"]["allDay"])


if __name__ == "__main__":
    sys.exit(unittest.main())
