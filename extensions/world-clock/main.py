#!/usr/bin/env python3
"""World Clock, a Sidefolk extension that ships with the app (Python 3.9, standard library only).

It speaks MCP over stdio: one JSON-RPC 2.0 message per line in, one per line out. It needs no
permission at all: the time zone rules come from macOS's own database (/usr/share/zoneinfo), which
every extension may read, so its answers handle daylight saving exactly where a guess wouldn't.
"""
import json
import os
import re
import sys
import unicodedata
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, available_timezones

PROTOCOL = "2025-06-18"
PLACE = {"type": "string", "minLength": 1, "maxLength": 80}

TOOLS = [
    {"name": "current_time", "title": "Time around the world",
     "description": "The current date and time in one or more places: cities (Tokyo, San Francisco), countries with one "
                    "time zone (Japan), IANA zones (Europe/Paris), UTC offsets (UTC+2) or \"here\".",
     "inputSchema": {"type": "object", "additionalProperties": False, "properties": {
         "places": {"type": "array", "items": PLACE, "minItems": 1, "maxItems": 12,
                    "description": "Where; \"here\" if not given."},
     }}},
    {"name": "convert_time", "title": "Convert a time between places",
     "description": "What a time in one place is in other places, like 09:30 in Paris for New York and Tokyo. The time is "
                    "\"HH:MM\", \"9am\", \"noon\", or \"YYYY-MM-DD HH:MM\" for another day (today in the first place otherwise).",
     "inputSchema": {"type": "object", "additionalProperties": False, "required": ["time", "to"], "properties": {
         "time": {"type": "string", "minLength": 1, "maxLength": 40, "description": "The time to convert."},
         "from": dict(PLACE, description="Where that time is; \"here\" if not given."),
         "to": {"type": "array", "items": PLACE, "minItems": 1, "maxItems": 12, "description": "Where to convert it to."},
     }}},
]

# Places people name that aren't the last part of an IANA zone, or that would be ambiguous.
ALIASES = {
    "san francisco": "America/Los_Angeles", "silicon valley": "America/Los_Angeles", "seattle": "America/Los_Angeles",
    "portland": "America/Los_Angeles", "san diego": "America/Los_Angeles", "las vegas": "America/Los_Angeles",
    "la": "America/Los_Angeles", "california": "America/Los_Angeles", "washington": "America/New_York",
    "washington dc": "America/New_York", "boston": "America/New_York", "miami": "America/New_York",
    "atlanta": "America/New_York", "philadelphia": "America/New_York", "nyc": "America/New_York",
    "austin": "America/Chicago", "dallas": "America/Chicago", "houston": "America/Chicago",
    "salt lake city": "America/Denver", "montreal": "America/Toronto", "ottawa": "America/Toronto",
    "rio": "America/Sao_Paulo", "rio de janeiro": "America/Sao_Paulo", "beijing": "Asia/Shanghai",
    "shenzhen": "Asia/Shanghai", "guangzhou": "Asia/Shanghai", "mumbai": "Asia/Kolkata", "delhi": "Asia/Kolkata",
    "new delhi": "Asia/Kolkata", "bangalore": "Asia/Kolkata", "bengaluru": "Asia/Kolkata", "chennai": "Asia/Kolkata",
    "hyderabad": "Asia/Kolkata", "osaka": "Asia/Tokyo", "kyoto": "Asia/Tokyo", "lahore": "Asia/Karachi",
    "tel aviv": "Asia/Jerusalem", "abu dhabi": "Asia/Dubai", "munich": "Europe/Berlin", "frankfurt": "Europe/Berlin",
    "hamburg": "Europe/Berlin", "geneva": "Europe/Zurich", "barcelona": "Europe/Madrid", "milan": "Europe/Rome",
    "manchester": "Europe/London", "edinburgh": "Europe/London", "lyon": "Europe/Paris", "marseille": "Europe/Paris",
    "cape town": "Africa/Johannesburg", "sfax": "Africa/Tunis", "sousse": "Africa/Tunis",
    "uk": "Europe/London", "united kingdom": "Europe/London", "england": "Europe/London", "ireland": "Europe/Dublin",
    "france": "Europe/Paris", "germany": "Europe/Berlin", "spain": "Europe/Madrid", "italy": "Europe/Rome",
    "netherlands": "Europe/Amsterdam", "belgium": "Europe/Brussels", "switzerland": "Europe/Zurich",
    "austria": "Europe/Vienna", "poland": "Europe/Warsaw", "sweden": "Europe/Stockholm", "norway": "Europe/Oslo",
    "denmark": "Europe/Copenhagen", "finland": "Europe/Helsinki", "greece": "Europe/Athens", "turkey": "Europe/Istanbul",
    "ukraine": "Europe/Kyiv", "portugal": "Europe/Lisbon", "japan": "Asia/Tokyo", "korea": "Asia/Seoul",
    "south korea": "Asia/Seoul", "china": "Asia/Shanghai", "india": "Asia/Kolkata", "singapore": "Asia/Singapore",
    "israel": "Asia/Jerusalem", "uae": "Asia/Dubai", "saudi arabia": "Asia/Riyadh", "egypt": "Africa/Cairo",
    "tunisia": "Africa/Tunis", "morocco": "Africa/Casablanca", "algeria": "Africa/Algiers", "nigeria": "Africa/Lagos",
    "kenya": "Africa/Nairobi", "south africa": "Africa/Johannesburg", "new zealand": "Pacific/Auckland",
    "argentina": "America/Argentina/Buenos_Aires", "colombia": "America/Bogota", "peru": "America/Lima",
    "vietnam": "Asia/Ho_Chi_Minh", "thailand": "Asia/Bangkok", "philippines": "Asia/Manila", "pakistan": "Asia/Karachi",
    "bangladesh": "Asia/Dhaka", "nepal": "Asia/Kathmandu", "iran": "Asia/Tehran", "iceland": "Atlantic/Reykjavik",
}
REGIONS = ("Africa/", "America/", "Antarctica/", "Asia/", "Atlantic/", "Australia/", "Europe/", "Indian/", "Pacific/")
HERE = {"", "here", "local", "local time", "my time", "my place", "home"}


class Problem(Exception):
    """Something the model should read and can act on: becomes an isError result."""


def fold(text):
    """Lowercase, accents and underscores gone, spaces collapsed: "São_Paulo" and "sao paulo" match."""
    plain = "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c))
    return re.sub(r"[\s_]+", " ", plain.replace("-", " ")).strip().lower()


_zones = None


def zones():
    """By folded full name and by folded city name, regional zones first."""
    global _zones
    if _zones is None:
        names = sorted(available_timezones(), key=lambda z: (not z.startswith(REGIONS), z))
        full, city = {}, {}
        for name in names:
            full.setdefault(fold(name), name)
            city.setdefault(fold(name.split("/")[-1]), name)
        _zones = (full, city)
    return _zones


def local_zone_name():
    try:
        match = re.search(r"zoneinfo/(.+)$", os.readlink("/etc/localtime"))
        return match.group(1) if match else None
    except OSError:
        return None


def resolve(place):
    """(label, tzinfo) for a place, the label worded to follow a time ("in Tokyo", "here in Paris"),
    or a Problem that says what was not understood."""
    key = fold(place)
    if key in HERE:
        name = local_zone_name()
        if name:
            return "here in %s" % name.split("/")[-1].replace("_", " "), ZoneInfo(name)
        return "here", datetime.now().astimezone().tzinfo
    if key in ("utc", "gmt", "z", "zulu"):
        return "in UTC", timezone.utc
    offset = re.fullmatch(r"(?:utc|gmt)([+\-−])(\d{1,2})(?::?(\d{2}))?", place.strip().lower().replace(" ", ""))
    if offset:
        sign = -1 if offset.group(1) in "-−" else 1
        delta = timedelta(hours=int(offset.group(2)), minutes=int(offset.group(3) or 0))
        if delta > timedelta(hours=14):
            raise Problem("%s isn't a real UTC offset." % place)
        return "at " + place.strip(), timezone(sign * delta)
    full, city = zones()
    name = full.get(key) or ALIASES.get(key) or city.get(key)
    if not name:
        raise Problem("I don't know where “%s” is. Try a big city nearby, a country with one time zone, or an IANA zone "
                      "like Europe/Paris." % place.strip())
    return "in " + place.strip(), ZoneInfo(name)


def offset_text(moment):
    minutes = int(moment.utcoffset().total_seconds() // 60)
    sign = "+" if minutes >= 0 else "−"
    hours, rest = divmod(abs(minutes), 60)
    return "UTC%s%d%s" % (sign, hours, ":%02d" % rest if rest else "")


def describe(moment, label):
    zone = moment.tzname() or ""
    # Named zones have an abbreviation (CET, JST); offsets and UTC itself only repeat the offset.
    abbreviation = "%s, " % zone if zone and not zone.startswith(("+", "-", "UTC")) else ""
    return "%s %d %s, %s %s (%s%s)" % (moment.strftime("%A"), moment.day, moment.strftime("%B"), moment.strftime("%H:%M"),
                                      label, abbreviation, offset_text(moment))


def difference(moment, reference):
    minutes = int((moment.utcoffset() - reference.utcoffset()).total_seconds() // 60)
    if minutes == 0:
        return "the same time as you"
    hours, rest = divmod(abs(minutes), 60)
    span = ("%d h %02d" % (hours, rest)) if rest else ("%d hour%s" % (hours, "" if hours == 1 else "s"))
    return "%s %s you" % (span, "ahead of" if minutes > 0 else "behind")


def parse_time(text, tz):
    key = text.strip().lower().replace(".", "")
    if key in ("noon", "midday"):
        key = "12:00"
    elif key == "midnight":
        key = "00:00"
    match = re.fullmatch(r"(?:(\d{4})-(\d{2})-(\d{2})[ t])?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?", key)
    if not match:
        raise Problem("I couldn't read “%s” as a time. Use HH:MM, 9am, noon, or YYYY-MM-DD HH:MM." % text.strip())
    year, month, day, hour, minute, half = match.groups()
    hour, minute = int(hour), int(minute or 0)
    if half:
        if not 1 <= hour <= 12:
            raise Problem("“%s” isn't a time on a 12-hour clock." % text.strip())
        hour = hour % 12 + (12 if half == "pm" else 0)
    if hour > 23 or minute > 59:
        raise Problem("“%s” isn't a time of day." % text.strip())
    today = datetime.now(tz)
    try:
        moment = datetime(int(year or today.year), int(month or today.month), int(day or today.day), hour, minute, tzinfo=tz)
    except ValueError:
        raise Problem("“%s” isn't a real date." % text.strip())
    # In the hour the clocks skip in spring, that wall time never happens there.
    if moment.astimezone(timezone.utc).astimezone(tz).replace(tzinfo=None) != moment.replace(tzinfo=None):
        raise Problem("%s doesn't happen on that day: the clocks skip that hour. Try an hour later." % text.strip())
    return moment


# --- Tools --------------------------------------------------------------------------------------

def current_time(args):
    now = datetime.now(timezone.utc)
    here = now.astimezone()
    lines, problems = [], []
    for place in args.get("places") or ["here"]:
        try:
            label, tz = resolve(place)
        except Problem as problem:
            problems.append(str(problem))
            continue
        moment = now.astimezone(tz)
        line = "It is " + describe(moment, label)
        if fold(place) not in HERE:
            line += ", " + difference(moment, here)
        lines.append(line + ".")
    if not lines:
        raise Problem(" ".join(problems))
    return "\n".join(lines + problems)


def convert_time(args):
    origin_label, origin = resolve(args.get("from") or "here")
    moment = parse_time(args.get("time", ""), origin)
    lines, problems = [], []
    for place in args.get("to") or []:
        try:
            label, tz = resolve(place)
        except Problem as problem:
            problems.append(str(problem))
            continue
        lines.append("- " + describe(moment.astimezone(tz), label))
    if not lines:
        raise Problem(" ".join(problems))
    return "\n".join(["%s is:" % describe(moment, origin_label)] + lines + problems)


CALLS = {"current_time": current_time, "convert_time": convert_time}


# --- Protocol -----------------------------------------------------------------------------------

def call_tool(name, arguments):
    if name not in CALLS:
        return {"content": [{"type": "text", "text": "Unknown tool: %s" % name}], "isError": True}
    try:
        text = CALLS[name](arguments)
    except Problem as problem:
        return {"content": [{"type": "text", "text": str(problem)}], "isError": True}
    return {"content": [{"type": "text", "text": text}]}


def answer(message):
    method, params = message.get("method"), message.get("params") or {}
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion", PROTOCOL), "capabilities": {"tools": {}},
                "serverInfo": {"name": "world-clock", "version": "1.0.0"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        return call_tool(params.get("name"), params.get("arguments") or {})
    raise NotImplementedError(method)


def main():
    for line in sys.stdin:
        try:
            message = json.loads(line)
        except ValueError:
            continue
        if not isinstance(message, dict) or "id" not in message or "method" not in message:
            continue  # notifications need no answer
        reply = {"jsonrpc": "2.0", "id": message["id"]}
        try:
            reply["result"] = answer(message)
        except NotImplementedError as e:
            reply["error"] = {"code": -32601, "message": "Method not found: %s" % e}
        except Exception as e:  # report, don't crash: one bad call shouldn't stop the extension
            reply["error"] = {"code": -32603, "message": str(e)}
        sys.stdout.write(json.dumps(reply) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
