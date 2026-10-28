# A library of extensions: ideas to approve (2026-10-28)

The founder asked for a good library of extensions: for different people and different uses, useful and fun.
These are seventy ideas to choose from. Nothing here is built. Reply with the numbers you approve (see
[Approving](#approving) at the end); each approved idea then gets built, tested in its sandbox, and either
shipped with the app or put in the GitHub catalog.

This builds on [extensions-catalog.md](extensions-catalog.md) (what ships and why) and doesn't repeat it.

## What every idea here can rely on

An extension is a small Swift program on `extensions/Kit`, built and signed with the app (D39). It offers
**tools** (the AI calls them; every call goes through the Guard) and **watchers** (checks every 5 minutes or
more that say "something happened"). It runs in a sandbox that allows only what its manifest asks for:

- the internet, all or nothing;
- folders fixed in the manifest, or a folder the person names for one call;
- programs listed by path (`/usr/bin/textutil`), and `git` by name;
- `media`, the graphics hardware and decoders that image code needs;
- its own data folder, which survives updates.

What it can't do yet: keep a secret (an API key or token), draw its own window or card, play sound, move the
companion (the AI can, with `companion.play` and `companion.toss`), use the pasteboard or Apple Events, or
read Calendar, Contacts or Photos. Ideas that need one of these are marked **Later** and say what they wait for.

Every extension that is **on** sends the descriptions of the tools the model sees with every request. Each
costs roughly 60–150 tokens. Instant commands (D50) let a tool skip the model altogether, so it costs nothing
(see **Works** below). Ones that are off reach the model as one line each, and the AI suggests switching one
on when it would help.

Already done, so not here: the 13 built-ins (Git, World Clock, System Vitals, Weather, Calculator, Currency,
Playtime, Images, PDF Tools, QR Codes, Archives, Dev Toolbox, Feeds), reminders linked to notes and tasks, the
notebook, watches and live reports, one-shot readings, Apple Notes and Reminders, voice, your location, tricks,
catch-me, breathing, coins, dice and rock-paper-scissors.

**Tiers used below:**

| Tier | Meaning |
|---|---|
| **Ship on** | Bundled and on from the start. Costs tokens on every request, so only everyday helpers |
| **Ship off** | Bundled, one switch away in Settings › Extensions |
| **Catalog** | On GitHub, installed from a link in the catalog (or Install from Folder today) |
| **Later** | Needs something extensions can't do yet; it's named |

**Sizes:** S is a day or two with tests. M is up to a week. L is more, or needs a sandbox question answered first.

**Works** (instant commands, D50): an author can give a tool whole-sentence commands with typed slots
("who needs water today?", "a cup of flour in grams"). Those run at once with no AI, and the author also
decides whether the model sees the tool at all.
- **Instant:** commands only. The model never sees the tool, so it costs no tokens.
- **Both:** commands for the common sentences, and the model for every other wording, for judgement and for
  chaining.
- **AI:** the model only, for free-form input or decisions.

Each idea's "Instant or AI" line names which tools go which way. Risky actions (moving to the Trash, stopping
a process) still ask, however they're reached.

## Summary

| # | Name | For | Tier | Size | Category | Works |
|---|---|---|---|---|---|---|
| E1 | Outside | allergies, runners, parents | Ship off | S | Weather & Sky | Both |
| E2 | Sky & Space | stargazers, photographers, kids | Ship off | M | Weather & Sky | Both |
| E3 | Earthquakes | people in quake country | Ship off | S | Weather & Sky | Both |
| E4 | Holidays & Days Off | everyone, remote teams | **Ship on** | S | Time & Travel | Both |
| E5 | Trip Kit | travellers | Ship off | S | Time & Travel | Both |
| E6 | Is This Link Safe? | older people, everyone | Ship off | M | Your Mac & Safety | Both |
| E7 | Network Doctor | everyone, remote workers | Ship off | S | Your Mac & Safety | Both |
| E8 | Mac Doctor | everyone | Ship off | M | Your Mac & Safety | Both |
| E9 | Space Finder | everyone | Ship off | M | Your Mac & Safety | Both |
| E10 | Gadget Batteries | everyone with AirPods or a Magic Mouse | Ship off | S | Your Mac & Safety | Instant |
| E11 | Kitchen | cooks, bakers | Ship off | S | Home & Family | Both |
| E12 | Food Facts | health-minded, allergies | Catalog | S | Home & Family | Both |
| E13 | Pantry | households | Ship off | S | Home & Family | Both |
| E14 | Plant Pal | plant people | Ship off | S | Home & Family | Both |
| E15 | Upkeep | homeowners, car owners | Ship off | S | Home & Family | Both |
| E16 | Chores | families, flatmates | Catalog | S | Home & Family | Both |
| E17 | Lent & Borrowed | everyone | Catalog | S | Home & Family | Both |
| E18 | Birthday Book | everyone | Ship off | S | Home & Family | Both |
| E19 | Baby Log | new parents | Catalog | S | Home & Family | Both |
| E20 | Story Keeper | parents, storytellers | Catalog | S | Learning & Kids | AI |
| E21 | Little Learners | parents of young kids | Ship off | M | Learning & Kids | Both |
| E22 | Secret Codes | kids, puzzle lovers | Catalog | S | Learning & Kids | Both |
| E23 | Little Log | everyone, ADHD, older people | **Ship on** | S | Wellbeing & Focus | Both |
| E24 | Habits | everyone | Ship off | S | Wellbeing & Focus | Both |
| E25 | Mood Diary | wellbeing | Ship off | S | Wellbeing & Focus | Both |
| E26 | Now & Next | ADHD, deep work | Ship off | S | Wellbeing & Focus | Both |
| E27 | Workout Log | gym-goers, runners | Catalog | S | Wellbeing & Focus | Both |
| E28 | Curious | the curious, kids, students | Ship off | S | Learning & Kids | Both |
| E29 | Wordsmith | writers, poets, songwriters | Ship off | M | Reading & Writing | Both |
| E30 | Scholar | students, researchers | Ship off | M | Learning & Kids | Both |
| E31 | Flashcards | language learners, students | Ship off | M | Learning & Kids | Both |
| E32 | Bookshelf | readers | Catalog | S | Reading & Writing | Both |
| E33 | Read Later | readers | Catalog | M | Reading & Writing | Both |
| E34 | Student Desk | students | Ship off | S | Learning & Kids | Both |
| E35 | Pocket Ledger | everyone | Ship off | M | Money & Numbers | Both |
| E36 | Money Math | everyone | Ship off | S | Money & Numbers | Both |
| E37 | Time Tracker | freelancers | Ship off | S | Work & Business | Both |
| E38 | Invoice Maker | freelancers, small business | Ship off | M | Work & Business | Both |
| E39 | Spreadsheet Helper | small business, analysts | Ship off | M | Work & Business | AI |
| E40 | Doc Converter | everyone | Ship off | S | Files & Documents | Both |
| E41 | Writer's Desk | writers, students | Catalog | S | Reading & Writing | Both |
| E42 | Uptime & Certificates | site owners, developers | Ship off | S | Work & Business | Both |
| E43 | Color Studio | designers, developers | Ship off | M | Photos & Design | Both |
| E44 | Chords & Scales | musicians | Catalog | M | Music, TV & Sports | Both |
| E45 | Photo Sorter | everyone with a messy photo folder | Ship off | M | Photos & Design | AI |
| E46 | Video & Audio Kit | creators | Catalog | L | Photos & Design | Both |
| E47 | Name Forge | parents-to-be, pet owners, writers, gamers | Catalog | S | Reading & Writing | Both |
| E48 | Word Games | everyone | Ship off | M | Fun & Games | Both |
| E49 | Trivia Night | families, friends | Catalog | S | Fun & Games | Both |
| E50 | Daily Delight | everyone | Ship off | S | Fun & Games | Instant |
| E51 | Tabletop Companion | tabletop gamers | Catalog | M | Fun & Games | Both |
| E52 | Game Deals | gamers | Catalog | S | Fun & Games | Both |
| E53 | TV Night | TV fans | Ship off | S | Music, TV & Sports | Both |
| E54 | New Music | music lovers | Catalog | S | Music, TV & Sports | Both |
| E55 | Ports & Processes | developers | Later | M | Developer Tools | Both |
| E56 | Package Watch | developers | Ship off | S | Developer Tools | Both |
| E57 | API Poke | developers | Ship off | M | Developer Tools | Both |
| E58 | Developer Disk Cleanup | developers | Ship off | M | Developer Tools | Both |
| E59 | SQLite Explorer | developers, data people | Catalog | S | Developer Tools | Both |
| E60 | GitHub Public | developers | Catalog | S | Developer Tools | Both |
| E61 | Calendar Peek | everyone | Later | M | Time & Travel | Both |
| E62 | Music Control | everyone | Later | M | Music, TV & Sports | Both |
| E63 | Shortcuts Runner | power users | Later | M | Your Mac & Safety | Both |
| E64 | Smart Home | home automation fans | Later | L | Home & Family | Both |
| E65 | Parcels | online shoppers | Later | M | Home & Family | Both |
| E66 | Ambient Sounds | focus, sleep, calm | Later | M | Wellbeing & Focus | Instant |
| E67 | Board Games | puzzle lovers | Later | L | Fun & Games | Instant |
| E68 | Companion Care | everyone who loves the companion | Later | M | Fun & Games | Instant |
| E69 | Scores & Markets | sports fans, investors | Later | M | Music, TV & Sports | Both |
| E70 | Photo Memories | everyone | Later | M | Photos & Design | Both |

---

## Outdoors and the world

### E1 · Outside
Air quality, pollen and UV for any place, and a nudge when the air turns bad.
- **For:** people with allergies or asthma, runners, parents.
- **Ask:** "Is the air good for a run?" · "How's the pollen today?" · "When is UV lowest this afternoon?"
- **Tools:** `air_now`, `pollen`, `uv_today`. **Watchers:** `air_turns_bad` (once when the index crosses a line), `clean_air_window` (a good hour to air the room).
- **Instant or AI (Both):** Instant `air_now`, `pollen`, `uv_today` ("air quality", "pollen today", "UV index"), for your own place; AI: "is the air good for a run?" and setting the watchers.
- **Needs:** internet.
- **Source:** Open-Meteo Air Quality (CAMS). No key. Free for non-commercial use; commercial use needs a paid plan, and attribution to CAMS and Open-Meteo is required. Pollen is Europe only. Same terms question as Weather (CHECKLIST: "Open-Meteo's terms if Sidefolk is paid").
- **Size / tier:** S · Ship off.
- **Privacy:** the place goes to Open-Meteo, as with Weather.
- **Lovely because:** it tells you when to open the window.

### E2 · Sky & Space
Golden hour, what's in the night sky, the next rocket launch, and a heads-up for northern lights.
- **For:** stargazers, photographers, kids, space fans.
- **Ask:** "When's golden hour tonight?" · "Which planets can I see?" · "When's the next rocket launch?" · "Any chance of aurora?"
- **Tools:** `golden_hour`, `planets_tonight`, `meteor_showers`, `next_launches`, `aurora`. **Watchers:** `launch_soon` (an hour before a launch you follow), `aurora_likely` (Kp at your latitude's line).
- **Instant or AI (Both):** Instant `golden_hour`, `next_launches`, `aurora` ("golden hour tonight", "next rocket launch"); AI: planning ("best night this week for the Perseids").
- **Needs:** internet (only for launches and aurora).
- **Source:** golden and blue hour, planets and meteor showers computed on the Mac (JPL's approximate planet formulas are public domain; the shower calendar is a small table). Aurora from NOAA SWPC's Kp JSON (US government, public domain, no key). Launches from The Space Devs' Launch Library 2: no key, about 15 calls an hour per address (secondhand figure; check before shipping). ISS passes would need CelesTrak orbits plus an SGP4 port: a later, larger step.
- **Size / tier:** M (L with the ISS) · Ship off.
- **Privacy:** only the latitude band goes out for aurora; nothing for the sky maths.
- **Lovely because:** "Look up at 21:40: Jupiter is the bright one, low in the east."

### E3 · Earthquakes
Recent earthquakes near you or anywhere, and a note when a strong one happens nearby.
- **For:** people in Japan, Chile, California, Turkey; anyone with family there.
- **Ask:** "Was that an earthquake?" · "Any big quakes near Fukuoka this week?" · "Tell me if there's a 5+ within 300 km."
- **Tools:** `recent_quakes(place, radius, min_magnitude)`. **Watcher:** `strong_quake_near`.
- **Instant or AI (Both):** Instant `recent_quakes` near you ("was that an earthquake?", "earthquakes near me"); AI: other places, the watcher.
- **Needs:** internet.
- **Source:** USGS GeoJSON feeds. No key, public domain.
- **Size / tier:** S · Ship off.
- **Privacy / risk:** it is **not a warning system**: data arrives minutes later. The tool and watcher say so plainly. Japan's own agency is faster but its feed is Japanese-only and has its own terms.
- **Lovely because:** it answers "was that a quake?" in seconds instead of a search.

### E4 · Holidays & Days Off
Public holidays for any country, long weekends, and "is Monday a day off in Japan?"
- **For:** everyone; remote teams across countries; parents planning trips.
- **Ask:** "Is Monday a holiday?" · "When's the next long weekend?" · "Holidays in Germany in December?" · "Is my colleague in Lisbon off on Thursday?"
- **Tools:** `holidays(country, year)`, `is_day_off(date, country)`, `long_weekends(country)` (worked out from holidays and weekends). **Watcher:** `holiday_tomorrow`.
- **Instant or AI (Both):** Instant `is_day_off`, `long_weekends`, `holidays` ("is Monday a holiday?", "next long weekend", "holidays in Germany"); AI: plans across countries.
- **Needs:** internet.
- **Source:** Nager.Date (now nagerholidays.com). No key, no stated rate limit, open source. Read its terms of service before shipping. Cache a year per country in the data folder so it works offline afterwards.
- **Size / tier:** S · **Ship on** (two or three small tools; it uses your country from Your location).
- **Privacy:** only a country code goes out.
- **Lovely because:** "Good news: Monday is Sports Day in Japan. A long weekend!"

### E5 · Trip Kit
A travel card for any country: plugs and voltage, emergency numbers, which side they drive on, tipping, and a packing list.
- **For:** travellers.
- **Ask:** "What plug do I need in Japan?" · "Emergency number in Italy?" · "Make a packing list for 5 days in Lisbon." · "Help me beat jet lag to Tokyo."
- **Tools:** `travel_card(country)`, `packing_list(days, kind_of_trip)`, `jet_lag_plan(from, to, arrival)`. The AI adds the forecast from Weather and money from Currency.
- **Instant or AI (Both):** Instant `travel_card` ("plug in Japan", "emergency number in Italy"); AI: `packing_list`, `jet_lag_plan`.
- **Needs:** nothing.
- **Source:** small tables we write from public facts (plug types, voltages, emergency numbers, driving side). No copying from Wikipedia's text (CC BY-SA); the facts themselves are free.
- **Size / tier:** S · Ship off.
- **Privacy / risk:** jet lag tips are general sleep and light timing, never medical advice.
- **Lovely because:** the companion packs your bag with you.

## Safety and the Mac

### E6 · Is This Link Safe?
Looks at a link or an email sender for the signs of a scam, without opening it.
- **For:** older people, their families, everyone.
- **Ask:** "Is this link safe?" · "This email says it's from my bank: is the address real?" · "Where does this short link go?"
- **Tools:** `check_link(url)`: look-alike letters and punycode, a brand in the wrong place (`apple.com.verify-id.co`), the domain's age from RDAP, known shorteners. `expand_short_link(url)` only when the person agrees.
- **Instant or AI (Both):** Instant `check_link` with a pasted address ("is this link safe: …"); AI: judging a whole email.
- **Needs:** internet (RDAP).
- **Source:** RDAP through rdap.org and the registries' public RDAP servers. No key. The other checks run on the Mac.
- **Size / tier:** M · Ship off.
- **Privacy / risk:** it never says "safe", only what it found ("this domain is 3 days old"). It doesn't visit the link by default: following a phishing link can tell the sender it was opened. The domain name goes to its registry.
- **Lovely because:** a calm second opinion before a costly click.

### E7 · Network Doctor
"Is it me or the internet?" in one answer: Wi-Fi, DNS, the wider internet and how fast it is.
- **For:** everyone; remote workers before a call.
- **Ask:** "Why is the internet slow?" · "Is my connection good enough for a video call?" · "Is it the Wi-Fi or the website?"
- **Tools:** `diagnose` (reach the router, DNS, a few big sites, each step timed), `speed` (Apple's `networkQuality`), `dns_lookup(name)`.
- **Instant or AI (Both):** Instant `diagnose`, `speed` ("is it me or the internet?", "speed test"); AI: "good enough for a video call?".
- **Needs:** internet; `/usr/bin/networkQuality`, `/sbin/ping`, `/usr/sbin/scutil`, `/usr/bin/dig`.
- **Source:** Apple's own test servers (`networkQuality`). No third party.
- **Size / tier:** S · Ship off.
- **Privacy / risk:** the Wi-Fi network's name needs Location permission on macOS 14 and later, so it's left out. A speed test uses data; the tool says so.
- **Lovely because:** "Your Wi-Fi is fine; the website is down."

### E8 · Mac Doctor
Why the fan is loud, what keeps the Mac awake, how healthy the battery is, and whether macOS has updates.
- **For:** everyone.
- **Ask:** "Why is my Mac hot?" · "What's keeping my Mac from sleeping?" · "How's my battery's health?" · "Any macOS updates?"
- **Tools:** `busy_apps` (CPU and energy now), `sleep_blockers` (`pmset -g assertions`), `battery_health` (cycle count, condition, capacity), `updates` (`softwareupdate --list`).
- **Instant or AI (Both):** Instant `busy_apps`, `sleep_blockers`, `battery_health` ("why is my Mac hot?", "battery health"); AI: explaining what to do.
- **Needs:** `/bin/ps`, `/usr/bin/pmset`, `/usr/sbin/ioreg`, `/usr/sbin/softwareupdate`; internet only for updates.
- **Source:** the Mac itself.
- **Size / tier:** M · Ship off. It could also be System Vitals' next version instead of its own extension.
- **Privacy / risk:** read-only. It never quits apps; it names them.
- **Lovely because:** it turns "my Mac is weird" into one sentence you can act on.

### E9 · Space Finder
What's eating your disk: the biggest folders and files, old downloads, duplicates.
- **For:** everyone; the most common Mac question after "why is it slow".
- **Ask:** "What's taking up space?" · "Find big files in Downloads." · "Any duplicate photos in this folder?" · "Move the old installers to the Trash."
- **Tools:** `biggest(folder)`, `old_downloads(days)`, `duplicates(folder)` (size, then a hash), `to_trash(paths)` (high risk, asks every time).
- **Instant or AI (Both):** Instant `biggest`, `old_downloads` ("what's taking up space?"); AI: choosing what goes. `to_trash` is never a command: it always asks.
- **Needs:** a folder named per call (read); the Trash needs a new, named permission (see [capabilities](#capabilities-that-unlock-the-best-later-ideas)). Until then it reports and Finder does the deleting.
- **Source:** the Mac itself.
- **Size / tier:** M · Ship off (a candidate for Ship on once the Trash permission exists).
- **Privacy / risk:** file names reach the AI when you ask. Nothing is ever deleted outright, only moved to the Trash.
- **Lovely because:** "You have 38 GB of old disk images in Downloads. Shall I put them in the Trash?"

### E10 · Gadget Batteries
The battery of your AirPods, Magic Mouse, keyboard and trackpad, and a nudge before one dies.
- **For:** everyone with Bluetooth accessories.
- **Ask:** "How much battery do my AirPods have?" · "Is my mouse about to die?"
- **Tools:** `accessories`. **Watcher:** `accessory_low` (once under 15%).
- **Instant or AI (Instant):** Instant only, `accessories` ("AirPods battery", "mouse battery"); the model needn't see it, so it costs no tokens.
- **Needs:** `/usr/sbin/ioreg`, `/usr/sbin/system_profiler`.
- **Source:** the Mac itself. AirPods show only while connected.
- **Size / tier:** S · Ship off. It could also join System Vitals.
- **Privacy / risk:** check `system_profiler` in the sandbox first; it may need a Bluetooth service opened.
- **Lovely because:** no more mouse dying in the middle of a meeting.

## Kitchen and home

### E11 · Kitchen
Scale a recipe, cups to grams for each ingredient, oven temperatures, swaps, safe cooking temperatures.
- **For:** cooks and bakers.
- **Ask:** "Scale this recipe from 4 to 6 people." · "How many grams is a cup of flour?" · "Gas mark 4 in Celsius?" · "What can I use instead of buttermilk?"
- **Tools:** `scale_recipe(text, from, to)`, `convert_ingredient(amount, unit, ingredient, to)`, `oven(temp)`, `substitute(ingredient)`, `safe_temperature(food)`.
- **Instant or AI (Both):** Instant `convert_ingredient`, `oven`, `substitute` ("a cup of flour in grams", "gas mark 4 in Celsius"); AI: `scale_recipe` on a pasted recipe.
- **Needs:** nothing.
- **Source:** our own tables. Densities worked out from USDA FoodData Central (public domain); safe temperatures from USDA (public domain); swaps written by us. Timers stay reminders.
- **Size / tier:** S · Ship off.
- **Privacy:** nothing leaves the Mac.
- **Lovely because:** the exact grams for *flour*, not a guess for "a cup of something".

### E12 · Food Facts
What's in a product: nutrition, allergens, vegan or not, from its barcode or name.
- **For:** health-minded people, people with allergies, parents.
- **Ask:** "How much sugar is in Nutella?" · "Is 3017620422003 vegan?" · "Does this contain nuts?"
- **Tools:** `product(barcode_or_name)`, `compare(a, b)`.
- **Instant or AI (Both):** Instant `product` ("is 3017620422003 vegan?", "sugar in Nutella"); AI: `compare` and advice in context.
- **Needs:** internet.
- **Source:** Open Food Facts. No key; needs a User-Agent naming the app and a contact; rate limits per endpoint. Data under ODbL: attribution required, and a database built from it must stay open.
- **Size / tier:** S · Catalog.
- **Privacy / risk:** crowd-sourced data can be wrong; the answer says so, and never replaces the label for an allergy.
- **Lovely because:** a quick answer in the shop aisle, by voice.

### E13 · Pantry
What's in the fridge and cupboard, what goes off soon, and what to cook with it.
- **For:** households who hate waste.
- **Ask:** "I bought milk, use by Friday." · "What's going off soon?" · "What can I cook with what needs eating?"
- **Tools:** `add(item, use_by)`, `used(item)`, `expiring(days)`. **Watcher:** `goes_off_tomorrow`. The AI suggests the meal.
- **Instant or AI (Both):** Instant `add`, `used`, `expiring` ("bought milk, use by Friday", "what's going off soon?"); AI: "what can I cook?".
- **Needs:** nothing.
- **Source:** the person's own list.
- **Size / tier:** S · Ship off.
- **Privacy:** local only.
- **Lovely because:** less food in the bin, and dinner ideas from what you have.

### E14 · Plant Pal
Your plants, when you last watered each, and a gentle note when one is thirsty.
- **For:** plant people, and people who keep killing plants.
- **Ask:** "I have a monstera and two cacti." · "I watered the fern." · "Who needs water today?"
- **Tools:** `add_plant(name, kind)`, `watered(plant)`, `thirsty_today`. **Watcher:** `plants_thirsty` (once a day, in the morning).
- **Instant or AI (Both):** Instant `watered`, `thirsty_today` ("I watered the fern", "who needs water today?"); AI: setting up the plants.
- **Needs:** nothing.
- **Source:** a care table we write (water every N days by kind, a little more in summer).
- **Size / tier:** S · Ship off.
- **Privacy:** local only.
- **Lovely because:** "The fern looks thirsty." Your companion keeps your plants alive.

### E15 · Upkeep
Things that need doing every few months: filters, the smoke alarm battery, the car, descaling the kettle.
- **For:** homeowners, renters, car owners.
- **Ask:** "Change the water filter every 2 months." · "I serviced the car today at 48,000 km." · "What's due soon?"
- **Tools:** `add(thing, every)`, `done(thing, date_or_km)`, `due_soon`. **Watcher:** `upkeep_digest` (weekly).
- **Instant or AI (Both):** Instant `done`, `due_soon` ("I changed the water filter", "what's due soon?"); AI: setting things up.
- **Needs:** nothing.
- **Source:** the person's own list. Unlike a repeating reminder, it remembers when each was last done.
- **Size / tier:** S · Ship off.
- **Privacy:** local only.
- **Lovely because:** the home looks after itself, a little.

### E16 · Chores
Who does what this week, fairly rotated, with a tally.
- **For:** families, flatmates.
- **Ask:** "Whose turn is the bins?" · "Sam did the dishes." · "What are this week's chores?"
- **Tools:** `setup(people, chores, rotation)`, `whose_turn(chore)`, `done(chore, person)`, `tally`. **Watcher:** `week_plan` (Sunday evening).
- **Instant or AI (Both):** Instant `whose_turn`, `done`, `tally` ("whose turn is the bins?", "Sam did the dishes"); AI: the setup.
- **Needs:** nothing.
- **Source:** the household's own list. First names only.
- **Size / tier:** S · Catalog.
- **Privacy:** local only.
- **Lovely because:** no more arguing about the bins: the companion keeps score.

### E17 · Lent & Borrowed
Who has your drill, and what you borrowed from whom.
- **For:** everyone.
- **Ask:** "I lent my drill to Sam." · "Who has my Dune book?" · "What do I need to give back?"
- **Tools:** `lent(thing, to)`, `borrowed(thing, from)`, `who_has(thing)`, `returned(thing)`. **Watcher:** `still_out` (after a few weeks).
- **Instant or AI (Both):** Instant `lent`, `borrowed`, `who_has`, `returned` ("I lent my drill to Sam", "who has my drill?"); the AI for other wordings.
- **Needs:** nothing.
- **Source:** the person's own list.
- **Size / tier:** S · Catalog.
- **Privacy:** local only.
- **Lovely because:** your things come home.

## Family

### E18 · Birthday Book
Birthdays and anniversaries with ages, gift ideas and what you gave before, and a nudge a week ahead.
- **For:** everyone.
- **Ask:** "Mum's birthday is 3 March 1966." · "How old is Mum turning?" · "Gift ideas for Sam: she loves pottery." · "What did I give Sam last year?"
- **Tools:** `add(person, date)`, `upcoming(days)`, `note_gift(person, idea_or_given)`. **Watchers:** `birthday_soon` (a week before), `birthday_today`.
- **Instant or AI (Both):** Instant `add`, `upcoming` ("Mum's birthday is 3 March", "upcoming birthdays"); AI: gift ideas.
- **Needs:** nothing. Importing birthdays from Contacts needs a host capability (Later).
- **Source:** the person's own list.
- **Size / tier:** S · Ship off.
- **Privacy:** names and dates stay local.
- **Lovely because:** "Mum turns 60 next Friday. Last year you gave her a scarf."

### E19 · Baby Log
Feeds, naps and nappies, and "when did she last eat?" at 3 a.m., by voice.
- **For:** new parents.
- **Ask:** "Fed 120 ml." · "When was the last feed?" · "How long did he nap today?"
- **Tools:** `log(kind, amount)`, `last(kind)`, `today_summary`.
- **Instant or AI (Both):** Instant `log`, `last`, `today_summary` ("fed 120 ml", "when was the last feed?"): instant matters at 3 a.m.; the model sees `last` for other wordings.
- **Needs:** nothing.
- **Source:** the parents' own log.
- **Size / tier:** S · Catalog.
- **Privacy / risk:** local only. Never medical advice.
- **Lovely because:** one less thing to remember on no sleep.

### E20 · Story Keeper
Bedtime stories that continue night after night, with the same characters.
- **For:** parents, grandparents, storytellers.
- **Ask:** "Start a story about Pip the small dragon and a fox called Juno." · "Tonight's chapter, please." · "What happened last time?"
- **Tools:** `new_story(characters, setting)`, `next_chapter(story)` (hands the AI the cast, places and last events), `save_chapter`. The AI writes; the extension remembers.
- **Instant or AI (AI):** AI: the story is written by the model; no command fits.
- **Needs:** nothing.
- **Source:** the stories written so far.
- **Size / tier:** S · Catalog.
- **Privacy:** local only.
- **Lovely because:** a story world your child grows up with.

### E21 · Little Learners
Short maths and spelling games for young kids, with stars and a cheer from the companion.
- **For:** parents of 5–10 year olds.
- **Ask:** "Times tables practice for Lina." · "Spelling words for this week: …" · "How many stars did Lina get?"
- **Tools:** `start(child, kind, level)`, `answer(child, answer)`, `stars(child)`. Words are spoken by Sidefolk's voice when voice replies are on; the AI cheers with `companion.play`.
- **Instant or AI (Both):** Instant `start`, `stars` ("times tables for Lina", "Lina's stars"); answers go through the AI or "answer 56" (a bare number would be a catch-all).
- **Needs:** nothing.
- **Source:** our own drills (number bonds, tables, simple spelling lists the parent gives).
- **Size / tier:** M · Ship off.
- **Privacy:** first names only, local.
- **Lovely because:** practice that ends in a companion cheer.

### E22 · Secret Codes
Morse, ciphers and pig latin, and clue cards for a treasure hunt.
- **For:** kids, puzzle lovers, parents planning a birthday treasure hunt.
- **Ask:** "Turn 'look under the sofa' into Morse." · "Make 5 treasure hunt clues in a secret code." · "Decode this: KHOOR."
- **Tools:** `encode(text, code)`, `decode(text, code)`, `treasure_hunt(places, code)`.
- **Instant or AI (Both):** Instant `encode`, `decode` ("SOS in Morse", "decode KHOOR"); AI: `treasure_hunt` clues.
- **Needs:** nothing.
- **Source:** written by us.
- **Size / tier:** S · Catalog.
- **Privacy:** local only.
- **Lovely because:** a birthday treasure hunt in five minutes.

## Wellbeing and focus

### E23 · Little Log
"Did I…?" and "what did I do today?", answered from a tiny log.
- **For:** everyone; people with ADHD; older people; anyone who doubts whether they locked the door.
- **Ask:** "I took my pills." · "Did I take my pills today?" · "I locked the door." · "What did I get done today?"
- **Tools:** `log(thing)`, `did_i(thing, when)`, `done_list(day)` (also a stand-up: yesterday and today).
- **Instant or AI (Both):** Instant `log`, `did_i`, `done_list` ("I took my pills", "did I take my pills today?", "what did I do today?"); the model sees `did_i` and `done_list` for other wordings.
- **Needs:** nothing.
- **Source:** the person's own words.
- **Size / tier:** S · **Ship on** (three small tools, used every day).
- **Privacy:** local only; never shared unless asked.
- **Lovely because:** "Yes, at 8:12." Peace of mind in one sentence.

### E24 · Habits
Daily habits with streaks, a weekly view, and a kind note in the evening if one is still open.
- **For:** everyone building a habit.
- **Ask:** "Track walking, reading and water." · "I read today." · "How's my week?"
- **Tools:** `add(habit, days)`, `check_in(habit)`, `week`. **Watcher:** `evening_nudge` (only for habits still open, never more than once).
- **Instant or AI (Both):** Instant `check_in`, `week` ("I read today", "how's my week?"); AI: choosing habits.
- **Needs:** nothing.
- **Source:** the person's own log.
- **Size / tier:** S · Ship off.
- **Privacy / risk:** local only. No guilt: a missed day doesn't reset a streak to zero if they choose "rest days".
- **Lovely because:** the companion cheers a 7-day streak.

### E25 · Mood Diary
A mood and one word, a gratitude line, and the pattern over weeks.
- **For:** anyone looking after their wellbeing.
- **Ask:** "Mood 4, calm." · "Three good things today: …" · "How have I been this month?"
- **Tools:** `log(mood, word, note)`, `gratitude(text)`, `pattern(weeks)`.
- **Instant or AI (Both):** Instant `log`, `gratitude` ("mood 4, calm"); AI: `pattern` and a kind reflection.
- **Needs:** nothing.
- **Source:** the person's own diary.
- **Size / tier:** S · Ship off.
- **Privacy / risk:** the most private data in this list. Local only, and it reaches the AI only when asked. Not a health tool; the AI's own care for someone in distress still applies.
- **Lovely because:** you notice the good weeks, not only the hard ones.

### E26 · Now & Next
One thing at a time: what you're doing now, a parking spot for distractions, and a soft check-in.
- **For:** people with ADHD, anyone doing deep work.
- **Ask:** "I'm writing the report for 45 minutes." · "Park: buy cat food." · "What did I park?" · "Done, what's next?"
- **Tools:** `focus(task, minutes)`, `park(thought)`, `parked`, `done` (adds to Little Log when installed, through the AI). **Watcher:** `check_in` ("Still on the report?", every 15–30 minutes, quiet hours respected).
- **Instant or AI (Both):** Instant `focus`, `park`, `parked`, `done` ("focus on the report for 45 minutes", "park: buy cat food"); AI: breaking a task down.
- **Needs:** nothing.
- **Source:** the person's own words.
- **Size / tier:** S · Ship off.
- **Privacy:** local only.
- **Lovely because:** the companion is a gentle body double.

### E27 · Workout Log
Sets, reps, runs and personal records.
- **For:** gym-goers, runners.
- **Ask:** "Bench 3×8 at 60 kg." · "Ran 5 km in 27 minutes." · "What's my best squat?" · "Volume this week?"
- **Tools:** `log(exercise, sets, reps, weight)`, `run(distance, time)`, `records`, `week`.
- **Instant or AI (Both):** Instant `log`, `run`, `records` ("bench 3×8 at 60 kg", "ran 5 km in 27 minutes", "best squat"); AI: the weekly picture.
- **Needs:** nothing.
- **Source:** the person's own log.
- **Size / tier:** S · Catalog.
- **Privacy:** local only.
- **Lovely because:** a cheer when you beat a record.

## Learning and reading

### E28 · Curious
Today in history, a short summary of anything, and a random article to wander into.
- **For:** the curious, kids, students.
- **Ask:** "What happened on this day?" · "Tell me about the Voyager probes." · "Surprise me with something interesting."
- **Tools:** `on_this_day(date)`, `summary(topic, language)`, `random_article`.
- **Instant or AI (Both):** Instant `on_this_day`, `random_article` ("what happened on this day?", "surprise me"); AI: `summary` in context.
- **Needs:** internet.
- **Source:** Wikipedia's REST API (`/api/rest_v1/page/summary`, `/feed/onthisday`). No key; a User-Agent with contact is expected. Text under CC BY-SA 4.0: each answer links to its article.
- **Size / tier:** S · Ship off.
- **Privacy:** only the topic goes out.
- **Lovely because:** a little something to learn every day, in your own language's Wikipedia.

### E29 · Wordsmith
Rhymes, syllables, definitions and synonyms, and a haiku checker. Works offline.
- **For:** writers, poets, songwriters, crossword fans.
- **Ask:** "What rhymes with orange?" · "Is this a haiku?" · "Another word for 'happy'." · "How many syllables in 'library'?"
- **Tools:** `rhymes(word)`, `syllables(text)`, `define(word)`, `synonyms(word)`.
- **Instant or AI (Both):** Instant `rhymes`, `syllables`, `define`, `synonyms` ("rhymes with orange", "syllables in library"); AI: haiku checks and writing help.
- **Needs:** nothing.
- **Source:** the CMU Pronouncing Dictionary (BSD-style licence, about 3.5 MB, bundled) for rhymes and syllables; the Mac's own dictionaries for definitions and synonyms (Dictionary Services). **Check first** that Dictionary Services works in the sandbox. Datamuse would be easier, but it needs a key from 2027 and asks customer-facing apps to describe themselves first.
- **Size / tier:** M · Ship off.
- **Privacy:** nothing leaves the Mac.
- **Lovely because:** the companion counts your haiku's syllables.

### E30 · Scholar
Find papers, cite them in any style, and hear about new papers on your topic.
- **For:** students, researchers.
- **Ask:** "Cite 10.1038/nature14539 in APA." · "Find recent papers on sleep and memory." · "Tell me about new arXiv papers on speech synthesis." · "BibTeX for ISBN 9780262046305."
- **Tools:** `find_papers(query)`, `cite(doi_or_isbn, style)` (Crossref formats citations itself), `paper(doi)`. **Watcher:** `new_papers(query, category)`.
- **Instant or AI (Both):** Instant `cite` ("cite 10.1038/nature14539 in APA"); AI: `find_papers` and summaries.
- **Needs:** internet.
- **Source:** Crossref REST (no key; a "polite" User-Agent with an email; metadata free to reuse), arXiv API (no key; at most one request every 3 seconds; asks for a thank-you line), Open Library for ISBNs. OpenAlex now needs a key, so it waits for secrets.
- **Size / tier:** M · Ship off.
- **Privacy:** only the search words go out.
- **Lovely because:** the bibliography stops being the worst part of the essay.

### E31 · Flashcards
Spaced-repetition decks, five cards with your companion each morning, starter decks for kana and hangul.
- **For:** language learners, students.
- **Ask:** "Add ありがとう: thank you, to Japanese." · "Quiz me." · "How many cards are due?" · "Import this CSV as a deck."
- **Tools:** `add_card(deck, front, back)`, `next_card(deck)`, `answer(card, how_well)`, `decks`, `import_csv(file)`. **Watcher:** `cards_due` (once a day). Sidefolk's voice can say the word aloud when voice replies are on.
- **Instant or AI (Both):** Instant `next_card`, `answer`, `add_card` ("quiz me", "got it", "again", "add ありがとう: thank you to Japanese"); AI: making decks.
- **Needs:** a file named per call, only for imports.
- **Source:** the person's cards; starter decks (hiragana, katakana, hangul, world capitals) we write.
- **Size / tier:** M · Ship off.
- **Privacy:** local only.
- **Lovely because:** a small daily ritual that makes a new language stick.

### E32 · Bookshelf
What you're reading, what's next, your yearly goal, and books found by title or ISBN.
- **For:** readers.
- **Ask:** "I started Project Hail Mary." · "I'm on page 210." · "How many books this year?" · "What's on my want-to-read list?"
- **Tools:** `find_book(query)`, `shelve(book, want_reading_read)`, `progress(book, page)`, `year`.
- **Instant or AI (Both):** Instant `progress`, `year` ("I'm on page 210", "books this year"); AI: `find_book` and suggestions.
- **Needs:** internet (search only).
- **Source:** Open Library (no key; asks for a User-Agent and no bulk scraping; most metadata is CC0).
- **Size / tier:** S · Catalog.
- **Privacy:** only search words go out; the shelf is local.
- **Lovely because:** a cheer at your 20th book of the year.

### E33 · Read Later
Save articles as clean text, and get "a 10-minute read" from your queue.
- **For:** readers who collect tabs.
- **Ask:** "Save this for later." · "I have 10 minutes: what should I read?" · "What's in my reading queue?"
- **Tools:** `save(url)` (fetches and keeps the article's text), `queue`, `pick(minutes)`, `read(id)`, `done(id)`.
- **Instant or AI (Both):** Instant `save`, `queue` ("save this for later: …", "my reading queue"); AI: `pick` and summaries.
- **Needs:** internet.
- **Source:** the articles themselves. Extracting readable text needs a careful extractor (M).
- **Size / tier:** M · Catalog.
- **Privacy / risk:** the page's text is outside content, handled as untrusted like any web page.
- **Lovely because:** your queue becomes something you actually read.

### E34 · Student Desk
Your timetable, the next class, what you need on the final, and how many days to the exam.
- **For:** students.
- **Ask:** "What's my next class?" · "I got 72 and 85; the final is 40%. What do I need for a B?" · "Week A or week B?"
- **Tools:** `timetable(set_or_show)`, `next_class`, `grade_needed(scores, weights, target)`, `average(scores, weights)`.
- **Instant or AI (Both):** Instant `next_class`, `timetable` ("what's my next class?", "week A or B?"); AI: `grade_needed` from loose wording.
- **Needs:** nothing.
- **Source:** the student's own timetable and grades.
- **Size / tier:** S · Ship off.
- **Privacy:** local only.
- **Lovely because:** "You need 68 on the final. You've got this."

## Money and work

### E35 · Pocket Ledger
Quick spending notes, monthly budgets, and subscriptions with their renewal dates.
- **For:** everyone.
- **Ask:** "Spent 12.50 on lunch." · "How much on food this month?" · "Budget 300 for groceries." · "When does the Netflix trial end?"
- **Tools:** `spent(amount, currency, category, note)`, `month(category)`, `budget(category, amount)`, `subscriptions`, `export_csv(folder)`. **Watchers:** `over_budget`, `trial_ends_soon`.
- **Instant or AI (Both):** Instant `spent`, `month` ("spent 12.50 on lunch", "food this month"); AI: budgets and questions about patterns.
- **Needs:** a folder named per call, only for export.
- **Source:** the person's own entries. Other currencies through Currency, via the AI.
- **Size / tier:** M · Ship off.
- **Privacy / risk:** local only. It tracks; it never advises.
- **Lovely because:** knowing where the money went, without a spreadsheet.

### E36 · Money Math
Loans, mortgages, savings goals, compound interest, salary per hour, and splitting a bill with a tip.
- **For:** everyone.
- **Ask:** "Monthly payment on 200,000 over 25 years at 4%?" · "How long to save 5,000 at 300 a month?" · "Split 84.50 between 3 with a 15% tip." · "50,000 a year is how much an hour?"
- **Tools:** `loan`, `savings_goal`, `compound`, `split_bill`, `salary`.
- **Instant or AI (Both):** Instant `split_bill`, `salary` ("split 84.50 between 3 with a 15% tip"); AI: `loan`, `savings_goal` from loose wording.
- **Needs:** nothing.
- **Source:** maths. Exact, which models often aren't.
- **Size / tier:** S · Ship off. It could also be the next version of Calculator.
- **Privacy / risk:** local. Numbers, never advice.
- **Lovely because:** the right number, the first time.

### E37 · Time Tracker
Start and stop a timer per client or project, and a weekly report with amounts.
- **For:** freelancers, consultants.
- **Ask:** "Start Acme." · "Stop." · "Log 2 hours for Bloom yesterday." · "How many hours for Acme this month at 80 an hour?"
- **Tools:** `start(project)`, `stop`, `log(project, hours, date)`, `report(range, rates)`, `export_csv(folder)`. **Watcher:** `still_running` (after 3 hours).
- **Instant or AI (Both):** Instant `start`, `stop`, `log` ("start Acme", "stop"); AI: `report` with rates.
- **Needs:** a folder named per call, only for export.
- **Source:** the person's own entries.
- **Size / tier:** S · Ship off.
- **Privacy:** local only.
- **Lovely because:** "You forgot to stop Acme's timer three hours ago."

### E38 · Invoice Maker
A clean, numbered PDF invoice from a sentence, and a nudge when one is unpaid.
- **For:** freelancers, small businesses.
- **Ask:** "Invoice Acme for 12 hours at 80, VAT 20%." · "Mark invoice 2026-014 paid." · "What's unpaid?"
- **Tools:** `business(details)`, `client(details)`, `invoice(client, lines, tax_rate, currency, folder)`, `paid(number)`, `unpaid`. **Watcher:** `unpaid_after(days)`.
- **Instant or AI (Both):** Instant `unpaid`, `paid` ("what's unpaid?", "mark 2026-014 paid"); AI: composing the invoice.
- **Needs:** a folder named per call (write).
- **Source:** the person's own details. The PDF is drawn with Core Graphics.
- **Size / tier:** M · Ship off.
- **Privacy / risk:** local only. It applies the tax rate you give and never decides one.
- **Lovely because:** from Time Tracker's hours to a sent invoice in one breath.

### E39 · Spreadsheet Helper
Exact totals, averages and groupings from a CSV, filters into a new file, and CSV ↔ JSON.
- **For:** small businesses, analysts, anyone with an export.
- **Ask:** "Total of Amount in sales.csv by month." · "Which customer spent the most?" · "Only the rows from March, into a new file." · "Turn this CSV into JSON."
- **Tools:** `describe(file)`, `summarize(file, column, group_by)`, `filter(file, condition, to)`, `convert(file, to)`.
- **Instant or AI (AI):** AI: columns and questions need understanding; a command can't name them well.
- **Needs:** a file named per call (read; write for new files).
- **Source:** the person's file. `.xlsx` (zipped XML) could come in a second version.
- **Size / tier:** M · Ship off.
- **Privacy / risk:** the summary reaches the AI, not the whole file.
- **Lovely because:** models guess at sums of 500 rows; this adds them up.

### E40 · Doc Converter
Word, RTF, HTML, OpenDocument and plain text into each other, and Markdown into Word.
- **For:** everyone who gets a .docx they can't open the way they want.
- **Ask:** "Turn this .docx into plain text." · "Make my Markdown notes a Word file." · "Convert report.odt to .docx."
- **Tools:** `convert(file, to)`, `markdown_to(file, to)`.
- **Instant or AI (Both):** Instant `convert` for a dropped or named file ("convert report.odt to docx"); AI otherwise.
- **Needs:** `/usr/bin/textutil`; a file named per call.
- **Source:** the Mac's own `textutil`.
- **Size / tier:** S · Ship off.
- **Privacy:** nothing leaves the Mac.
- **Lovely because:** it just works, without an online converter that keeps your file.

### E41 · Writer's Desk
Word counts, reading time, readability, long sentences and repeated words, and a daily writing goal.
- **For:** writers, students, bloggers.
- **Ask:** "How long is chapter3.md?" · "Is this easy to read?" · "Which words do I repeat too much?" · "I wrote 800 words today."
- **Tools:** `stats(file_or_text)`, `readability(file_or_text)`, `repeats(file_or_text)`, `goal(words_per_day)`, `wrote(words)`.
- **Instant or AI (Both):** Instant `wrote`, `stats` ("I wrote 800 words", "word count of chapter3.md"); AI: readability advice.
- **Needs:** a file named per call.
- **Source:** maths on the text. Readability scores are for English; other languages get counts only.
- **Size / tier:** S · Catalog.
- **Privacy:** nothing leaves the Mac.
- **Lovely because:** your companion celebrates the 50,000th word.

### E42 · Uptime & Certificates
Is my site up, how fast is it, and when does its certificate or domain run out.
- **For:** site owners, small businesses, developers.
- **Ask:** "Is shop.example.com up?" · "Tell me if my site goes down." · "When does my certificate expire?"
- **Tools:** `check(url)`, `certificate(host)`, `domain_expiry(domain)`. **Watchers:** `site_down` (two failures in a row), `certificate_expires(days)`, `domain_expires(days)`.
- **Instant or AI (Both):** Instant `check`, `certificate` ("is shop.example.com up?", "when does example.com's certificate expire?"); AI: the watchers.
- **Needs:** internet.
- **Source:** the site itself; RDAP for domains.
- **Size / tier:** S · Ship off.
- **Privacy:** only the sites you name.
- **Lovely because:** you hear it from your companion before a customer tells you.

## Creativity

### E43 · Color Studio
Colours in every notation, contrast checks, palettes, and the palette of a photo.
- **For:** designers, developers, crafters.
- **Ask:** "#3A7BD5 in HSL and OKLCH?" · "Is white text on this blue readable?" · "A palette from this photo." · "Tints of my brand colour."
- **Tools:** `convert(color)`, `contrast(fg, bg)` (WCAG, with the nearest passing shade), `palette(color, kind)`, `from_image(file, count)`, `name(color)`.
- **Instant or AI (Both):** Instant `convert`, `contrast` ("#3A7BD5 in HSL", "contrast of white on #3A7BD5"); AI: palettes from a description.
- **Needs:** a file named per call; `media` for photos.
- **Source:** maths; colour names from the xkcd colour survey (CC0).
- **Size / tier:** M · Ship off.
- **Privacy:** nothing leaves the Mac.
- **Lovely because:** "That's 'dusty teal', and it passes AA on white."

### E44 · Chords & Scales
Chords, scales, transposing, capo positions, and fingerings as little text diagrams.
- **For:** musicians, learners.
- **Ask:** "Notes in D minor 7?" · "Transpose G C D Em up 2." · "Capo for playing in E with D shapes?" · "Ukulele fingering for F?"
- **Tools:** `chord(name)`, `scale(name)`, `transpose(progression, steps)`, `capo(key, shapes)`, `fingering(chord, instrument)`.
- **Instant or AI (Both):** Instant `chord`, `scale`, `transpose` ("notes in D minor 7", "transpose G C D up 2"); AI: music questions.
- **Needs:** nothing.
- **Source:** music theory, written by us. A metronome or tuner needs sound and the microphone (Later, and the microphone stays the app's).
- **Size / tier:** M · Catalog.
- **Privacy:** nothing leaves the Mac.
- **Lovely because:** band practice without hunting through chord sites.

### E45 · Photo Sorter
Sort a photo folder into years and months, rename by date, and find near-duplicates and blurry shots.
- **For:** everyone with a messy photo folder.
- **Ask:** "Sort my Camera Uploads into year and month folders." · "Rename these by the date they were taken." · "Find blurry photos." · "Which photos are almost the same?"
- **Tools:** `sort_by_date(folder)`, `rename_by_date(folder)`, `near_duplicates(folder)`, `blurry(folder)`.
- **Instant or AI (AI):** AI: it moves files, so choices are talked through and each move asks.
- **Needs:** a folder named per call (write); `media`.
- **Source:** the photos' own EXIF data; a perceptual hash and a sharpness measure on the Mac.
- **Size / tier:** M · Ship off.
- **Privacy / risk:** it moves and renames, never deletes. The Photos library itself needs a host capability (Later).
- **Lovely because:** ten years of photos, finally in order.

### E46 · Video & Audio Kit
Shrink a video to send it, convert formats, pull out the audio, trim, make a GIF.
- **For:** creators, anyone sending a video by email.
- **Ask:** "Make this video small enough for WhatsApp." · "Extract the audio as MP3." · "A GIF of seconds 5 to 9." · "Convert this .wav to .m4a."
- **Tools:** `compress(file, target)`, `convert(file, to)`, `extract_audio(file)`, `trim(file, from, to)`, `gif(file, from, to)`.
- **Instant or AI (Both):** Instant `compress`, `extract_audio` for a dropped file ("make this smaller for WhatsApp"); AI: the rest.
- **Needs:** a file named per call; `media`; `/usr/bin/afconvert`.
- **Source:** AVFoundation and `afconvert`.
- **Size / tier:** L · Catalog. **Check first** which video-encoder services AVFoundation needs in the sandbox.
- **Privacy:** nothing leaves the Mac.
- **Lovely because:** no more uploading home videos to a random converter site.

### E47 · Name Forge
Baby names by popularity and year, names for pets, fantasy characters and projects.
- **For:** parents-to-be, pet owners, writers, gamers.
- **Ask:** "Popular girls' names in 1990?" · "A name for my grey kitten." · "Five elvish names." · "A codename for my project."
- **Tools:** `baby_names(year, sex, starts_with)`, `pet_name(hints)`, `fantasy_name(style, count)`, `codename`.
- **Instant or AI (Both):** Instant `fantasy_name`, `codename`, `baby_names` ("five elvish names", "a codename"); AI: names from hints.
- **Needs:** nothing.
- **Source:** US Social Security baby names (public domain, bundled in part); syllable tables we write. Meanings are left out: no good free source.
- **Size / tier:** S · Catalog.
- **Privacy:** nothing leaves the Mac.
- **Lovely because:** naming the cat becomes a game.

## Fun and games

### E48 · Word Games
A daily five-letter word, hangman, anagrams and word ladders, with scores and streaks.
- **For:** everyone.
- **Ask:** "Today's word game." · "Let's play hangman." · "Anagram of 'listen'?" · "Word ladder from cold to warm."
- **Tools:** `daily(guess)` (coloured squares as text), `hangman(guess)`, `anagram(word)`, `ladder(from, to)`, `streak`. The AI cheers with `companion.play`.
- **Instant or AI (Both):** Instant moves: `daily`, `hangman`, `anagram`, `ladder` ("today's word game", "guess crane", "anagram of listen"); AI: cheering and chat.
- **Needs:** nothing.
- **Source:** the ENABLE word list (public domain) to check words; a daily answer list we curate. Not called "Wordle", which is a trademark.
- **Size / tier:** M · Ship off. It could also become Playtime 2.0.
- **Privacy:** nothing leaves the Mac.
- **Lovely because:** a two-minute break with your companion every day.

### E49 · Trivia Night
Thousands of questions in categories and levels, with a family scoreboard.
- **For:** families, friends, quiz nights.
- **Ask:** "Trivia night: me, Sam and Lina, history." · "Next question." · "What's the score?"
- **Tools:** `game(players, category, difficulty)`, `next_question`, `answer(player, answer)`, `score`.
- **Instant or AI (Both):** Instant `next_question`, `answer`, `score` ("next question", "score"); AI: hosting.
- **Needs:** internet.
- **Source:** Open Trivia DB (no key; one request every 5 seconds; questions under CC BY-SA 4.0, so credit is shown). Playtime keeps its own 52 questions offline.
- **Size / tier:** S · Catalog.
- **Privacy:** first names stay local.
- **Lovely because:** the companion is the quiz host.

### E50 · Daily Delight
A fortune cookie a day, would-you-rather, a tiny adventure and a true strange fact.
- **For:** everyone.
- **Ask:** "My fortune today?" · "Would you rather…" · "Give me a tiny adventure." · "Tell me something weird and true."
- **Tools:** `fortune`, `would_you_rather`, `tiny_adventure`, `strange_fact`. Each remembers what it gave, so nothing repeats for months.
- **Instant or AI (Instant):** Instant only: `fortune`, `would_you_rather`, `tiny_adventure`, `strange_fact` ("my fortune today", "give me a tiny adventure"); no tokens.
- **Needs:** nothing.
- **Source:** written and checked by us (facts with a source each). The model could make these up; this keeps them kind, true and fresh.
- **Size / tier:** S · Ship off.
- **Privacy:** nothing leaves the Mac.
- **Lovely because:** "Today's tiny adventure: find something blue on your walk."

### E51 · Tabletop Companion
Rules lookups, initiative order, hit points and conditions for tabletop role-playing.
- **For:** tabletop gamers, game masters.
- **Ask:** "What does the 'grappled' condition do?" · "Initiative: Thorn 17, goblins 12, Mira 9." · "The goblin takes 7 damage." · "Stats for an owlbear."
- **Tools:** `rule(term)`, `monster(name)`, `spell(name)`, `initiative(entries)`, `damage(who, amount)`, `next_turn`. Dice go to the companion with `companion.toss`.
- **Instant or AI (Both):** Instant `initiative`, `damage`, `next_turn`, `rule` ("goblin takes 7 damage", "what does grappled do?"); AI: rulings.
- **Needs:** nothing if the SRD is bundled.
- **Source:** the 5e System Reference Document 5.1 (CC BY 4.0; credit required), bundled as JSON. dnd5eapi.co serves the same, with no key.
- **Size / tier:** M · Catalog.
- **Privacy:** nothing leaves the Mac.
- **Lovely because:** the companion rolls the dice for the dragon.

### E52 · Game Deals
Is a game on sale, its lowest price ever, and a note when it drops below your price.
- **For:** PC gamers.
- **Ask:** "Is Hades on sale?" · "Lowest price ever for Stardew Valley?" · "Tell me when Celeste is under 5."
- **Tools:** `deals(game)`, `lowest(game)`. **Watcher:** `price_below(game, price)`.
- **Instant or AI (Both):** Instant `deals`, `lowest` ("is Hades on sale?"); AI: the watcher.
- **Needs:** internet.
- **Source:** CheapShark (no key). **Doubtful:** its documentation didn't state terms or limits; ask them before shipping. IsThereAnyDeal needs a key (Later).
- **Size / tier:** S · Catalog.
- **Privacy:** only game names go out.
- **Lovely because:** you buy the game you wanted, at the price you wanted.

### E53 · TV Night
When the next episode airs, what's on tonight, and a note when a new season starts.
- **For:** TV fans.
- **Ask:** "When's the next episode of Severance?" · "Is there a new season of Slow Horses?" · "What's on TV tonight?"
- **Tools:** `next_episode(show)`, `show(show)`, `tonight(country)`. **Watchers:** `new_episode(show)`, `new_season(show)`.
- **Instant or AI (Both):** Instant `next_episode`, `tonight` ("next episode of Severance", "what's on tonight?"); AI: following shows.
- **Needs:** internet.
- **Source:** TVmaze (no key apparent; at least 20 calls every 10 seconds; CC BY-SA 4.0, so credit and a link back to TVmaze). Where to stream is not covered.
- **Size / tier:** S · Ship off.
- **Privacy:** only show names go out.
- **Lovely because:** "New episode tonight at 9!"

### E54 · New Music
New albums and singles from the artists you follow.
- **For:** music lovers.
- **Ask:** "Follow Radiohead and Hiromi." · "Anything new from my artists?" · "Latest album by Björk?"
- **Tools:** `follow(artist)`, `latest(artist)`, `new_releases`. **Watcher:** `new_release`.
- **Instant or AI (Both):** Instant `new_releases`, `follow` ("anything new from my artists?", "follow Radiohead"); AI: the rest.
- **Needs:** internet.
- **Source:** MusicBrainz (no key; one request a second; a descriptive User-Agent required; core data CC0).
- **Size / tier:** S · Catalog.
- **Privacy:** only artist names go out.
- **Lovely because:** you hear about the album the day it comes out.

## For developers

### E55 · Ports & Processes
What's listening on which port, and stopping the process on port 3000.
- **For:** developers.
- **Ask:** "What's on port 3000?" · "Which dev servers are running?" · "Free port 8080."
- **Tools:** `listening`, `who_uses(port)`, `stop(pid)` (high risk, asks every time).
- **Instant or AI (Both):** Instant `listening`, `who_uses` ("what's on port 3000?"); `stop` asks every time.
- **Needs:** `/usr/sbin/lsof`, `/bin/ps`, and two **new** sandbox permissions: seeing other processes, and signalling the person's own processes.
- **Source:** the Mac itself.
- **Size / tier:** M · **Later** (those permissions).
- **Privacy / risk:** process names and paths reach the AI when asked.
- **Lovely because:** no more `lsof -i :3000 | grep LISTEN` from memory.

### E56 · Package Watch
Latest versions on npm, PyPI, crates.io and Homebrew, and which of your project's packages are behind.
- **For:** developers.
- **Ask:** "Latest version of react?" · "Is my package.json out of date?" · "Tell me when Vapor 5 is out."
- **Tools:** `latest(package, ecosystem)`, `outdated(manifest_file)` (package.json, requirements.txt, Cargo.toml, Package.resolved). **Watcher:** `new_version`.
- **Instant or AI (Both):** Instant `latest` ("latest version of react"); AI: `outdated` for a project.
- **Needs:** internet; a file named per call.
- **Source:** npm registry, PyPI JSON, crates.io (no key; at most one request a second and a User-Agent with contact), Homebrew's formulae API. All free.
- **Size / tier:** S · Ship off.
- **Privacy:** package names go to their registries.
- **Lovely because:** "Your project is 3 minor versions behind on 4 packages" without running anything.

### E57 · API Poke
Send an HTTP request to an API or a local server, and read the answer nicely.
- **For:** developers.
- **Ask:** "GET localhost:8080/health." · "POST this JSON to /api/users on my local server." · "What headers does example.com send?"
- **Tools:** `request(method, url, headers, body)`, `saved`, `save(name, request)`.
- **Instant or AI (Both):** Instant GET ("GET localhost:8080/health"); AI: writing bodies; anything but GET asks.
- **Needs:** internet (which includes the local network today).
- **Source:** whatever you call.
- **Size / tier:** M · Ship off.
- **Privacy / risk:** anything but GET is high risk and asks every time. Tokens in headers pass through the AI, so it says so; real tokens wait for secrets.
- **Lovely because:** a quick check without opening another app.

### E58 · Developer Disk Cleanup
How much Xcode, simulators and package caches are taking, and a careful clean-up.
- **For:** developers.
- **Ask:** "How much space are my dev caches using?" · "Clean DerivedData." · "Remove simulators that are no longer available."
- **Tools:** `sizes` (DerivedData, Archives, device support, simulator caches, npm/yarn/pnpm, Homebrew, CocoaPods, Gradle), `clean(kind)` (to the Trash, high risk, asks every time).
- **Instant or AI (Both):** Instant `sizes` ("how much space do my dev caches use?"); `clean` asks every time.
- **Needs:** fixed folders under `~/Library/Developer`, `~/Library/Caches` and the package caches (read, write); `/usr/bin/xcrun` for simulators; the Trash permission.
- **Source:** the Mac itself.
- **Size / tier:** M · Ship off.
- **Privacy / risk:** never touches projects or the Archives you choose to keep; Archives are listed but not cleaned without naming them.
- **Lovely because:** "You have 41 GB of DerivedData." Instant disk space.

### E59 · SQLite Explorer
Tables, schema and read-only queries on a SQLite file.
- **For:** developers, data people.
- **Ask:** "What tables are in app.sqlite?" · "How many users signed up last week?" · "Export the orders table as CSV."
- **Tools:** `schema(file)`, `query(file, sql)` (read-only), `export(file, table, folder)`.
- **Instant or AI (Both):** Instant `schema` ("tables in app.sqlite"); AI: SQL from plain words.
- **Needs:** `/usr/bin/sqlite3` (`-readonly`); a file named per call.
- **Source:** the person's file.
- **Size / tier:** S · Catalog.
- **Privacy / risk:** query results reach the AI when asked; read-only by construction.
- **Lovely because:** ask your database a question in plain words.

### E60 · GitHub Public
A public repository's latest release, open issues, and a pull request's state.
- **For:** developers.
- **Ask:** "Latest release of swift-format?" · "Open issues with 'good first issue' in vapor?" · "Is PR 1234 in apple/swift merged?"
- **Tools:** `repo(name)`, `release(repo)`, `issues(repo, label)`, `pull(repo, number)`. **Watcher:** `new_issue(repo, label)`.
- **Instant or AI (Both):** Instant `release`, `pull` ("latest release of swift-format", "is PR 1234 in apple/swift merged?"); AI: issue searches.
- **Needs:** internet.
- **Source:** GitHub's REST API without a token (60 requests an hour per address). Releases are also an Atom feed, which Feeds can watch today. Private repositories and CI wait for secrets (or GitHub's own MCP server).
- **Size / tier:** S · Catalog.
- **Privacy:** only repository names go out.
- **Lovely because:** "good first issue" hunting from the desktop.

## Later: waiting for something extensions can't do yet

### E61 · Calendar Peek
Today's meetings, the next one, free slots. **Waits for:** read-only Calendar access from the host (EventKit, a macOS permission). PRODUCT plans this as a built-in. Lovely because "you're free from 2 to 4" is the most useful sentence in a workday.

*Instant or AI (Both):* Instant "what's next?", "am I free at 3?"; AI: planning the day.

### E62 · Music Control
Play, pause, skip, "what's this song?" in Music and Spotify. **Waits for:** Apple Events from the host, with tiny fixed scripts per app (the Apple Notes pattern, D38). Lovely because "play something calm" by voice.

*Instant or AI (Both):* Instant "pause the music", "next song", "what's playing?"; the model may see `play` for "something calm".

### E63 · Shortcuts Runner
Run one of your Shortcuts by name. **Waits for:** the host running `shortcuts` (the sandbox rightly denies its service); every run asks. Lovely because it bridges to everything Shortcuts reaches.

*Instant or AI (Both):* Instant "run shortcut Morning" (still asks); AI: choosing one.

### E64 · Smart Home
Lights, plugs and scenes through Home Assistant or Hue. **Waits for:** secrets, and network permission for the local network on its own. Lovely because "lights warm, I'm reading" just happens.

*Instant or AI (Both):* Instant "lights off", "living room to 50%"; AI: scenes.

### E65 · Parcels
Where's my package, and a note when it's out for delivery. **Waits for:** secrets (carriers and aggregators all need keys) and their terms. Lovely because the companion waves when the parcel is nearby.

*Instant or AI (Both):* Instant "where's my parcel?"; AI: the rest.

### E66 · Ambient Sounds
Rain, café, waves or brown noise, with a sleepy companion. **Waits for:** a host audio player that extensions can ask for, with volume and a timer. Lovely because focus and sleep, together with your companion.

*Instant or AI (Instant):* Instant only: "play rain", "stop the sounds"; no tokens.

### E67 · Board Games
A chess puzzle a day (Lichess's puzzles are CC0, no key), sudoku and mini crosswords. **Waits for:** a small interactive board on a card. Text boards aren't fun. Lovely because a calm puzzle with the morning coffee.

*Instant or AI (Instant):* Instant moves on the board; no tokens.

### E68 · Companion Care
Feed, play and tuck in your companion; it gets sleepy at night. **Waits for:** companion hooks an extension may call (tricks, moods), designed so it never guilts the person. Lovely because it's a pet that's never sad for long.

*Instant or AI (Instant):* Instant only: "feed Mochi", "tuck Mochi in"; no tokens.

### E69 · Scores & Markets
Live scores for your teams; prices for the stocks or coins you hold. **Waits for:** secrets, and data with terms that allow it (free sources are rare or forbid apps). Prices only, never advice. Lovely because "Liverpool scored!" from the corner of your screen.

*Instant or AI (Both):* Instant "Liverpool score", "price of AAPL"; AI: the rest (never advice).

### E70 · Photo Memories
"On this day" photos from your library. **Waits for:** Photos access from the host (a macOS permission) and cards that can show a picture. Lovely because a smile from five years ago.

*Instant or AI (Both):* Instant "on this day photos"; AI: finding a moment.

---

## Updates to the built-ins (not new extensions)

Small additions that fit the extensions we already ship:

- **World Clock:** "find a meeting time for Tokyo, Paris and New York within working hours".
- **Weather:** golden hour, if Sky & Space isn't approved.
- **System Vitals:** battery health, and accessory batteries (E10), if they aren't approved as their own extensions.
- **Images:** app icon sets (`.iconset` and `.icns` with `/usr/bin/iconutil`) and favicon sizes.
- **Playtime:** more of its own trivia categories (geography, science, kids).
- **QR Codes:** a Wi-Fi card ("make a QR code for my guest Wi-Fi"), when the person types the password themselves. A password should never come from the AI.

## Top 15 to build first

Chosen for value to many people, fit with what extensions can do today, clean data terms, and some delight.

1. **E23 Little Log.** Small, daily, for everyone; the best Ship on candidate.
2. **E4 Holidays & Days Off.** Tiny, daily, uses Your location; one clean source.
3. **E9 Space Finder.** The most common Mac question; report-only works today.
4. **E7 Network Doctor.** Apple's own speed test, no third party; everyone needs it.
5. **E8 Mac Doctor.** "Why is my Mac hot?" answered properly (or as System Vitals' next version).
6. **E58 Developer Disk Cleanup.** Developers get tens of gigabytes back; a strong reason to install Sidefolk.
7. **E39 Spreadsheet Helper.** Exact numbers where models guess; small businesses love it.
8. **E31 Flashcards.** A daily ritual with the companion; strong for language learners.
9. **E11 Kitchen.** Offline, exact, used weekly by many.
10. **E14 Plant Pal.** Tiny, offline, and very cute.
11. **E48 Word Games.** Offline fun every day; the companion cheers.
12. **E35 Pocket Ledger.** Money questions are daily questions; it's local and private.
13. **E6 Is This Link Safe?** Protects the people who need it most.
14. **E56 Package Watch.** Small, free sources, a daily developer question.
15. **E2 Sky & Space** (without the ISS at first). Pure delight, mostly computed on the Mac.

Close behind: E18 Birthday Book, E53 TV Night, E28 Curious, E29 Wordsmith (after the sandbox check), E37 Time Tracker with E38 Invoice Maker.

## A small Ship on set

Eight built-ins are on today. A tool that's on costs tokens on every request **only if the model sees it**.
Instant commands (D50) change the sum: a command-only tool costs nothing, and a "Both" tool can show the model
just one or two of its tools. So:

- **E23 Little Log:** Both. The model sees `did_i` and `done_list`, about 200 tokens; logging is instant.
- **E4 Holidays & Days Off:** Both. The model sees `holidays`, about 100 tokens; the everyday questions are instant.
- **E50 Daily Delight:** instant only, no tokens.
- **E10 Gadget Batteries:** instant only, no tokens.

On isn't free even then: an extension's commands claim sentences. Core intents win, and two extensions that
match the same sentence fall back to the AI. So ship on only extensions whose commands are distinctive.
Everything else ships off or goes to the catalog. The AI sees one line for each extension that's off and
suggests switching it on, so off isn't hidden. Once tools load on demand (below), the model-visible tools of
many more could be on too.

## Capabilities that unlock the best Later ideas

In the order they unlock the most:

1. **Tools loaded on demand.** The model sees one line per extension and asks for its tools when a request
   needs them. Then a much larger set can be on without the token cost. It's the biggest unlock for the library itself.
2. **Secrets for extensions** (already planned): Parcels, Scores & Markets, Smart Home, GitHub with a token,
   Datamuse from 2027, OpenAlex, IsThereAnyDeal.
3. **Companion hooks**: a low-risk way for an extension to ask for a trick or a cheer (Word Games, Little
   Learners, Habits streaks, Companion Care), through the executor like `companion.play`.
4. **Richer cards**: a picture, a colour swatch, a small board that takes clicks (Board Games, Color Studio,
   Photo Memories, book covers, QR images).
5. **Watchers at a time of day** ("every morning at 8"), not only every N minutes: Flashcards, Plant Pal,
   Habits, Birthday Book and Upkeep want a daily moment.
6. **The person's place for extensions** that declare it (Holidays, Earthquakes, Outside), handed over by the
   host from Your location, instead of the AI passing a town each time.
7. **A named Trash permission**: move chosen files to the Trash, high risk, every time (Space Finder, Developer
   Disk Cleanup).
8. **Process permissions**: see other processes; signal the person's own (Ports & Processes).
9. **A host audio player**: Ambient Sounds, pronunciations, a metronome.
10. **Host data behind macOS permissions**, read-only and typed, like Apple Notes (D38): Calendar, Contacts
    birthdays, Photos, Music, Shortcuts.
11. **A per-host network allow-list** (already planned): "can reach api.tvmaze.com" instead of "the
    internet", which also makes the install sheet calmer for every internet extension here.

## Sources to check before building

- **Open-Meteo** (E1): free only for non-commercial use, with attribution. Same open question as Weather.
- **Launch Library 2** (E2): about 15 calls an hour without a key, from secondhand pages; confirm.
- **Nager.Date** (E4): no key and no stated limit; read its terms of service (it moved to nagerholidays.com).
- **CheapShark** (E52): no terms or limits found in its documentation. **Doubtful** until they answer.
- **Datamuse** (E29): a key from 2027; customer-facing apps are asked to describe themselves. Left out on purpose.
- **OpenAlex** (E30): now needs a key. Left out until secrets.
- **Share-alike data** (Wikipedia E28, TVmaze E53, Open Trivia DB E49, Open Food Facts E12): fine to show with
  credit; we must not mix it into our own data files under another licence.
- **Sandbox checks** before promising: Dictionary Services (E29), `system_profiler` Bluetooth (E10),
  AVFoundation's video encoders (E46), moving to the Trash (E9, E58).

## Approving

Reply with the numbers you approve, for example:

> Approve E23, E4, E9, E7, E11, E14, E48, E58. E2 and E53 too, catalog for now.

For each one you can also give a tier (Ship on, Ship off, Catalog), or leave it to us. Anything you don't name
stays an idea. Approved ideas get built one by one: a manifest with the least it needs, the program on the Kit,
tests in the sandbox, an icon, examples in Settings, then Ship off or the catalog as you chose.

Sources: [Open-Meteo Air Quality](https://open-meteo.com/en/docs/air-quality-api),
[Nager.Date](https://nagerholidays.com/Api), [Datamuse](https://www.datamuse.com/api/),
[TVmaze API](https://www.tvmaze.com/api),
[OpenAlex rate limits and authentication](https://docs.openalex.org/how-to-use-the-api/rate-limits-and-authentication),
[Launch Library 2](https://thespacedevs.com/llapi),
[Open Food Facts API](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/),
[Wikimedia APIs](https://www.mediawiki.org/wiki/Wikimedia_APIs), [CheapShark API](https://apidocs.cheapshark.com/).
