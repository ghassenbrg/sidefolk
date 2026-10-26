#!/usr/bin/env python3
"""Weather, a Sidefolk extension that ships with the app, off until switched on (Python 3.9, standard library).

It speaks MCP over stdio: one JSON-RPC 2.0 message per line in, one per line out. Sidefolk runs it in a
sandbox with the internet and nothing else: no files, no programs. It asks Open-Meteo (free, no account)
where a place is and what the weather there will be; the place's name is the only thing it sends.
"""
import json
import sys
import urllib.parse
import urllib.request

PROTOCOL = "2025-06-18"
GEOCODING = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST = "https://api.open-meteo.com/v1/forecast"

TOOLS = [
    {"name": "forecast", "title": "Weather forecast",
     "description": "The weather now and for the next days in a place: conditions, temperatures, chance of rain and wind.",
     "inputSchema": {"type": "object", "additionalProperties": False, "required": ["place"], "properties": {
         "place": {"type": "string", "minLength": 1, "maxLength": 80, "description": "A city or town, like Lyon or Austin, Texas."},
         "days": {"type": "integer", "minimum": 1, "maximum": 7, "description": "How many days, today included (3 if not given)."},
         "units": {"type": "string", "enum": ["metric", "imperial"], "description": "°C and km/h, or °F and mph (metric if not given)."},
     }}},
]

# WMO weather codes, as Open-Meteo reports them.
CONDITIONS = {
    0: "clear", 1: "mostly clear", 2: "partly cloudy", 3: "overcast", 45: "fog", 48: "freezing fog",
    51: "light drizzle", 53: "drizzle", 55: "heavy drizzle", 56: "freezing drizzle", 57: "freezing drizzle",
    61: "light rain", 63: "rain", 65: "heavy rain", 66: "freezing rain", 67: "freezing rain",
    71: "light snow", 73: "snow", 75: "heavy snow", 77: "snow grains", 80: "light showers", 81: "showers",
    82: "violent showers", 85: "snow showers", 86: "heavy snow showers", 95: "thunderstorms",
    96: "thunderstorms with hail", 99: "thunderstorms with hail",
}


class Problem(Exception):
    """Something the model should read and can act on: becomes an isError result."""


def fetch_json(url, params):
    request = urllib.request.Request(url + "?" + urllib.parse.urlencode(params), headers={"User-Agent": "Sidefolk-Weather/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.load(response)
    except OSError as error:
        raise Problem("Couldn't reach Open-Meteo (%s). Check the internet connection." % getattr(error, "reason", error))


def locate(place):
    found = fetch_json(GEOCODING, {"name": place, "count": 1, "language": "en", "format": "json"}).get("results") or []
    if not found:
        raise Problem("I couldn't find a place called “%s”. Try the nearest city, or add the country." % place)
    spot = found[0]
    label = ", ".join(part for part in (spot.get("name"), spot.get("admin1"), spot.get("country")) if part)
    return spot["latitude"], spot["longitude"], label


def condition(code):
    return CONDITIONS.get(code, "weather code %s" % code)


def forecast(args):
    days = args.get("days", 3)
    imperial = args.get("units") == "imperial"
    latitude, longitude, label = locate(args.get("place", ""))
    params = {"latitude": latitude, "longitude": longitude, "timezone": "auto", "forecast_days": days,
              "current": "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,precipitation",
              "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"}
    if imperial:
        params.update(temperature_unit="fahrenheit", wind_speed_unit="mph", precipitation_unit="inch")
    data = fetch_json(FORECAST, params)
    return describe(data, label)


def describe(data, label):
    units = data.get("current_units", {})
    degree = units.get("temperature_2m", "°C")
    now = data.get("current", {})
    lines = ["%s, now: %s, %s%s (feels like %s%s), wind %s %s." % (
        label, condition(now.get("weather_code")), round(now.get("temperature_2m", 0)), degree,
        round(now.get("apparent_temperature", 0)), degree, round(now.get("wind_speed_10m", 0)), units.get("wind_speed_10m", "km/h"))]
    daily = data.get("daily", {})
    for i, day in enumerate(daily.get("time", [])):
        name = "Today" if i == 0 else "Tomorrow" if i == 1 else day
        lines.append("%s: %s, %s to %s%s, %s%% chance of rain." % (
            name, condition(daily["weather_code"][i]), round(daily["temperature_2m_min"][i]), round(daily["temperature_2m_max"][i]),
            degree, daily["precipitation_probability_max"][i] if daily["precipitation_probability_max"][i] is not None else "?"))
    return "\n".join(lines)


# --- Watcher ------------------------------------------------------------------------------------

def check_rain_soon(config, state):
    """Fires once per wet spell: when rain becomes likely within the window, and again only after a dry spell."""
    latitude, longitude, label = locate(config["place"])
    data = fetch_json(FORECAST, {"latitude": latitude, "longitude": longitude, "timezone": "auto",
                                 "hourly": "precipitation_probability", "forecast_days": 2, "current": "weather_code"})
    return rain_check(data, label, config.get("within_hours", 3), config.get("chance_percent", 60), state or {})


def rain_check(data, label, within_hours, chance, state):
    hour = data.get("current", {}).get("time", "")[:13]  # "2026-10-26T14", local time where the place is
    hourly = data.get("hourly", {})
    ahead = [(t, p) for t, p in zip(hourly.get("time", []), hourly.get("precipitation_probability", []))
             if t[:13] >= hour and p is not None][:within_hours]
    likely = next(((t, p) for t, p in ahead if p >= chance), None)
    if likely is None:
        return {"triggered": False, "state": {"wet": False}, "summary": "No rain likely in %s in the next %d hours." % (label, within_hours)}
    when, probability = likely
    summary = "Rain is likely in %s around %s (%d%% chance)." % (label, when[11:16], probability)
    return {"triggered": not state.get("wet"), "state": {"wet": True}, "summary": summary}


# --- Protocol -----------------------------------------------------------------------------------

def call_tool(name, arguments):
    if name != "forecast":
        return {"content": [{"type": "text", "text": "Unknown tool: %s" % name}], "isError": True}
    try:
        return {"content": [{"type": "text", "text": forecast(arguments)}]}
    except Problem as problem:
        return {"content": [{"type": "text", "text": str(problem)}], "isError": True}


def answer(message):
    method, params = message.get("method"), message.get("params") or {}
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion", PROTOCOL), "capabilities": {"tools": {}},
                "serverInfo": {"name": "weather", "version": "1.0.0"}}
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        return call_tool(params.get("name"), params.get("arguments") or {})
    if method == "sidefolk/watch.check":
        if params.get("watcher") != "rain_soon":
            raise LookupError("Unknown watcher: %s" % params.get("watcher"))
        return check_rain_soon(params.get("config") or {}, params.get("state"))
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
