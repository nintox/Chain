# Chain

A levelling tracker for World of Warcraft Classic Era, written for the person
*buying* the boost rather than the one selling it.

It answers one question continuously — **how many more runs, how long, and what
will it cost** — and it answers it from your own runs rather than from a guess.
When you are not being boosted it turns into an ordinary levelling bar.

```
Stockades 22-30  27 > 28  step 1/2    inst 5/5 +1 in 57m (all 1h 0m)
[Lvl 27  55.5%           17,310 to 28                     2.0 runs]
8,566 xp/run (Algorismus 5)              5m/run  ~10m left  ~60g
    grp 34.4 (5) -2% xp   ding ~10m
    4,200 xp  45 mobs (avg 93)  3m  -17% pace
    Algorismus  102k xp/h  ~54g/lvl  714 xp/g
```

`22-30` is what the place is worth doing at, not what you set in your route —
it turns red once you have outgrown it. Everything else the addon knows is one
hover away, on the tooltip.

---

## Install

Download the repository (green **Code** button → *Download ZIP*, or clone it)
and put the `Chain` folder into:

```
World of Warcraft/_classic_era_/Interface/AddOns/
```

so that you end up with `.../AddOns/Chain/Chain.toc`. Restart the
game — WoW only scans the AddOns folder at startup, so `/reload` will not find
a newly added addon.

Optional: [phone notifications](#phone-notifications).

If the game says the addon is out of date, tick **Load out of date AddOns** on
the character-select screen, or run `/dump select(4, GetBuildInfo())` in game
and put that number after `## Interface:` in `Chain.toc`.

## Setting up

`/chain config` — tick the instances you will be boosted through, give each a
level span, a price and how many runs that price buys. Boosters sell packs,
usually of five, so **gold** is what a pack costs and **runs** is how big the
pack is. **Runs per price** at the bottom is the default for anywhere you
leave the runs column alone.

That is the whole setup. Everything else is learned from the runs you do.

---

## What it does

### The bar

Seven fixed slots — two above, three inside, two below — so every figure has
its own corner and you look at a place rather than reading a line for it.

- **xp/run (Algorismus 5)** — the average the forecast rests on, and whose it
  is. A name means the booster you are with has enough runs of his own to be
  judged on them; a bare number is every run recorded for the step; `(est)`
  means it is borrowed from another instance because this one has no data yet.
- **grp 34.4 (5) -2% xp** — average group level and what the make-up costs you.
  Classic splits a mob's experience by level, so every boostie above your own
  level takes a bite out of your share. Green is as good as that group size can
  get, red is not.
- **inst 4/5 +1 in 28m** — instances entered this hour and when the next frees
  up. Re-entering the same instance does not count; a reset does. Five per hour
  is the only limit the game enforces.
- **pace / over** — how the run you are in compares to the usual one.
- **the booster line** — his experience per hour, what a level costs at his
  pace, and `xp/gold`, which is the verdict (see below).
- **move to SM at 28 (34% cheaper)** — when to leave (see below).

Levelling on your own uses the same frame:

```
this level 30m                          session 21,411 xp in 26m
[Lvl 27  55.5%         21,590 / 38,900                ~12m to 28]
17,310 to go                                         84,000 xp/h
    quests ready 5.4% (2) -> ~10m
    Stockades > 28  boost ~2 runs ~50g  solo ~12m
```

Experience per hour disappears rather than going stale when the experience
stops coming in.

### The tooltip

The bar is what you glance at; the tooltip is what you look at. Hovering it
gives you the same step in full — the level span the instance is meant for and
whether you have outgrown it, experience, time and mobs per run, what a level
costs here now and what it will cost by the time you leave, the booster's own
figures with his price and his verdict, how he compares with the best you have
recorded, your group, your instance count, what you have paid here and in
total, and what the rest of the route comes to.

Anything that can live there instead of on the bar does, which is why the bar
is four short lines and not eight.

### Which instance for which level

Two numbers, and they are not the same thing:

- **enter** — the level the game demands before it will let you through the
  door. The Stockades will not have you before 15 however cheap the booster
  is.
- **levels** — the span the place is actually worth doing at, `22-30` for the
  Stockades. Above it the mobs go grey and the runs stop paying.

Both are carried for every instance and shown wherever you might need them,
coloured against where you are: green when you can go in, or when the place
still suits you, red when you cannot, or when you have outgrown it.

- the span sits next to the instance name on the bar, and the entry level is
  on the tooltip
- the settings have both, beside the boxes where you type your own levels, and
  will tell you when the span you typed starts before the game lets you in
- the Route tab has **enter** and **good for** next to **your span**
- the Boosters tab says both under the list

You do not have to know the levels by heart to set up a route.

### Resets

When a reset is announced you get a line on the bar and a sound repeated a few
times on the Master channel — which plays even with the game muted, the state
you are most likely in when you have walked away.

**Two sounds, not one.** A reset means the opposite thing depending on which
side of the portal you are standing on, and the whole point of a sound is that
you do not have to look: one for **go in**, another for **zone out**, picked
from a short list in the settings. Clicking one plays it, because an alert you
have never heard is an alert you end up ignoring. The sound follows the
situation rather than the moment — walk out while the alert is still live and
it changes to the other one, so you are never being told to leave a place you
have already left. A large on-screen message is
available in the settings, off by default; it hangs under the bar's lines
rather than above them, because the bar usually ends up at the top of the
screen where there is nothing above it.

**It is all our own data.** Entries, resets, trades, runs — the addon sees
them itself and keeps them itself. Nova Instance Tracker is optional in the
real sense: the one thing it has that we cannot see for ourselves is the
entries from before this addon was installed, so those are copied into our own
log once, at login, and after that it can be uninstalled without anything
breaking. (`/chain importnit` does it by hand. Reading NIT's live count
instead of ours is a setting, off by default.)

**And the game gets the last word.** Counting zone-ins is an estimate: it
cannot know about instances you entered on a day the addon was off, or on
another computer. The game does know, and says so at the portal — *you have
entered too many instances recently*. When that arrives the count is corrected
to the limit rather than argued with, and it says in chat that it was behind.

**Telling the group.** Your lockout is invisible to everybody else: they see
you standing at the portal not going in, and somebody asks, every time. So the
addon says it instead — `locked 5/5 - free in 12m` when a reset lands and you
cannot use it, and `free again - 4/5` the moment that changes. Two lines and
no more: a countdown in party chat is the fastest way to be asked to turn an
addon off. **Tell the group your lockout** in the settings.

The line knows whether its advice is any good. Inside, it says to zone out.
Outside with an instance free, it says go in. Outside at five in the hour it
says so and when one frees up, because "go in" is not advice you can act on.

When a reset is *refused* you get the reason instead — someone still inside,
someone zoning, someone offline — which is usually what you are standing at the
portal wondering about.

`/chain rs` resets your instances. `/chain testalert` previews the alert.

### Not a boost

A run only counts as a boost when somebody in the group is at least ten levels
above you. Below that it is a normal dungeon: no booster is named, no gold is
charged, and the runs are averaged separately, because clearing a place
yourself and being dragged through it are not the same number.

### The window

`/level` opens it, and so does the **button on the minimap** — left-click for
the window, right-click for the settings, middle-click to show or hide the
bar, and drag it anywhere round the edge. Hovering it gives you the two things
you would have opened the window for: how many instances you are at this hour,
and what is left in the step you are on. `/chain minimap` hides it, or the
settings do.

| tab | what is on it |
|---|---|
| **History** | every run, with booster, group, level and rate. Experience, time, mobs and rate are coloured against that instance's own average, so a slow run stands out without reading the numbers. Click a column to sort, click the **x** to throw a run out of the averages. |
| **Boosters** | everyone selling the instance in focus, plus anyone you added yourself. |
| **Adverts** | everyone who has advertised anything, newest first, what they said, and a **whisper** button on every row. |
| **Groups** | the other half of the same channels: everyone *looking* rather than selling — LFM, LFG, WTB — with what they are short of, the levels they ask for, what they said in full, and the same **whisper** button. |
| **Reported** | everything other people's addons told you, kept apart from your own figures. |
| **Gold** | every trade you completed, and what a level has actually cost. |
| **Instances** | one timeline of everything that happened to an instance — every entry with its own countdown, and every reset, in the order they happened. |
| **Route** | the plan from where you stand, step by step. |

Every tab has a **show only** box that searches what the rows actually say, so
typing an instance narrows the list to it and typing a name narrows it to that
booster.

### Groups

Boost adverts are read by looking for a sale; everything that is not one gets
thrown away, and what gets thrown away is most of what people actually write.
The Groups tab keeps that half: `LFM SM cath need healer`, `LFG RFD`,
`LF3M Uldaman quest chain 40+`.

Nothing is matched against your quest log or anything else clever. The post is
kept whole — who said it, where you heard it, how many they are short and of
what, the level range if they gave one — and the **show only** box is what
turns it into a list of one thing. Type `uldaman`, or `healer`, or a name.

Somebody shouting the same line every thirty seconds does not fill the list:
the repeat moves his row back to the top and counts, so `2m ago x7` is one
row, not seven. A post about the instance you are standing in is green.

It has its own switch in the settings — **Read LFM and LFG posts** — because a
busy LookingForGroup produces a great deal more of this than it does boost
adverts. `/chain groups` opens the tab.

### The verdict

The one thing you type on the Boosters tab is the **price** he quotes. The
column is headed with the pack this instance is sold in — `price/5 runs` — and
the number is the whole pack. It is remembered against his name along with the
pack it covered.

Next to it is **pack**, for the man who does it differently. Deals are not the
same everywhere or from everybody: ten Stockade runs for 300g from one booster
and five for 200g from the next is an ordinary evening. So there are three
places a pack size can live, most specific first — the booster, the instance,
and the setting — and the most specific one that is filled in wins. Type a
pack against a booster and it stays his: retyping his price later does not
quietly put him back on the usual number.

**A price typed against a booster beats the price typed against the instance**,
for as long as he is the one boosting you. Set the Stockades to 75g in the
settings and run with somebody charging 50g, and every figure — the estimate on
the bar, the gold per level, the route total, when to move on — is worked out
at his 50. The instance price is what the place usually goes for, and it is
used when you are alone, or with somebody you have not priced yet.

Everything else follows:

```
xp/gold  =  xp per run  ÷  gold per run
```

Pulling more mobs raises it, charging less raises it. Each booster is graded
against the best you have recorded for that instance: **good** within 10% of
the best, **ok** down to 70%, **poor** below. There is nothing to click and
nothing to keep up to date.

### Your own list

Boosters arrive in the list on their own — from their adverts, from your runs,
from other people's addons — but a name you were given in a whisper arrives
nowhere. The Boosters tab has an **add someone** row at the bottom for that:
type a name and, if you like, a note in your own words, and he is in the list
before you have ever run with him. He is filed under the instance in focus, so
adding him while you are looking at the Stockades does not clutter Scarlet
Monastery.

The **your note** column is editable on every row, not only the ones you added:
*only sells mornings*, *does not pull the last room*, *friend of Nintoz*. The
note is yours. It is never shared, never sent, and never travels between copies
of the addon — what travels is measurements, and an opinion about a stranger is
not a measurement.

The **x** on a row removes somebody you added by hand. It does not appear next
to a booster you have actually run with: those runs are recorded history, and
throwing one out is done on the History tab, one run at a time.

### When to move on

Experience from a mob falls as you outlevel it and stops entirely when the mob
turns grey. An instance that is excellent at 22 is worth nothing at 35, so the
real question during a chain is not "how many more runs" but "how many more
runs *here* before somewhere else is cheaper".

The bar answers it: **move to SM at 28 (34% cheaper)**, shown once the switch
is within four levels. The Route tab has the same thing as numbers — what a
level costs in each step today, and what it will cost by the time you leave it,
with the increase coloured.

Two sources, in this order:

1. **What you measured.** Runs are stored with the level you were, so once an
   instance has runs at several levels the fall is simply observed.
2. **The game's own arithmetic**, anchored to your measurement — the grey
   level and the zero-difference table. The shape of the curve comes from the
   formula, the size of it from your data, so an error in the model cannot make
   the absolute figures wrong, only the slope, and only until you have levelled
   through enough of it to be measuring instead.

It will not suggest somewhere before the level you set for it in your route.

### Gold

The price in the settings is what the booster advertises. What you actually
paid is read from the trade window: when a trade completes, who it was with and
how much money moved each way is logged, tagged with the step and marked as a
booster payment when the name matches the one in your group.

That gives you two numbers side by side — `~100g (paid 82g)` — the estimate for
the runs still to come and what this step has cost so far. Money coming back is
subtracted. Cancelled trades are not logged. Payments by mail are invisible to
an addon and will not appear.

Both directions are kept, with the zone you were standing in when it happened,
the way Nova Instance Tracker words it: *gave 75g to Solari in Stormwind
Stockade*, *received 1,000g from Dirtyeob in Stormwind City*. Paying at the
summoning stone is as common as paying inside, so the gold still counts towards
the step you are working on — the zone is there to tell you which trade was
which when you read the list back.

### Where the booster list comes from

**Chat adverts.** Boosters advertise their own price several times an hour, in
whichever channel they feel like, and as often as not in a whisper to you. The
addon listens to all of it — every numbered channel you are in (Trade, General,
LookingForGroup, your realm's boosting channel, anything you joined yourself),
plus say, yell, guild, party and whispers — pulls the instance and the price out
of anything that reads like a sale, and files it under that player's name.
`200g for 5 runs` and `40g per run` both work.

**A price is not required.** Most adverts do not carry one — *WTS SM Boost,
Cath & Arm, Wlc Lvl 20-42, FFA Loot, sum ready* is the usual shape — so the
advertiser is listed anyway, with **ask** in the price column and the whisper
button next to it. Type his price into the Boosters tab once he tells you, and
the verdict follows from there.

It has to name an instance and read like a sale: `WTS`, `selling`, `boost`,
`carry` or a number of runs. Somebody looking for a group is not selling one,
so `LFM Stockades boost, need 2 more` and `WTB SM boost` are skipped, and word
boundaries are used so "small group" is not Scarlet Monastery. The names people
actually type are understood — `Mara`, `Cath & Arm`, `Scholo`, `ZF`, `stocks` —
not only the proper ones.

**settings → channels…** lists every source, built from the channels you are
actually in, with a count of how many adverts each has produced, and each one
can be switched off. A channel you join tomorrow is read tomorrow: only the
ones you untick stay off. The addon's own data channels are never read as
adverts. `/chain ads` turns the whole thing off, and `/chain heard` prints the
last adverts it picked up and which channel each came from.

There is no separate "boosting" channel on most realms: boosters advertise in
**Trade** and **LookingForGroup**, which is exactly what the bulletin-board
addons read too. Two things decide whether you see any:

- **Trade only works inside a city.** Standing at the Stockades entrance you
  are in Stormwind, so Trade reaches you; standing in Westfall it does not, and
  neither the addon nor your chat window will see a word of it.
- **You have to be in the channel.** `/join LookingForGroup` and `/join
  General` if you left them, or whatever your realm's boosting channel is
  called — it is read the moment you join it.

**Other people's addons.** With sharing on, measurements are swapped with other
people running Chain. You choose who hears you:

- **everyone with the addon** — a hidden channel of its own
- **my guild**
- **only these names** — whispered to a list you type

Only facts travel: the price you were quoted, and what you clocked. There is no
opinion to send, because the verdict is computed from those numbers and
everyone derives it from the same evidence. Nothing you received is ever passed
on, so a mistake cannot bounce around gathering weight. Messages leave one at a
time, seconds apart. Sharing is off by default: `/chain share`.

Each reporter counts once per booster per instance, and a newer report replaces
their older one. Measurements are pooled weighted by how many runs each rests
on, so one person with thirty runs counts for more than one with three.

### Nova Instance Tracker

Not required. With it, the lockout counts come from its data, which means they
are right from the first minute instead of only counting what this addon has
seen. Without it, the addon keeps its own log and reaches the same numbers once
it has watched you for an hour. Reset announcements from other people's NIT are
picked up from party chat either way.

---

## Phone notifications

Optional, and a separate program — see [`push/README.md`](push/README.md).

A WoW addon has **no network access of any kind**: no HTTP, no sockets. That is
true of every addon, not just this one, so nothing running inside the game can
reach ntfy, Discord or a phone. What the game *does* do is write its chat to a
log file, and a small program outside WoW can watch that file.

```
WoW  ──writes──▶  Logs/WoWChatLog.txt  ──watched by──▶  Chain Push  ──▶  ntfy / Discord
```

It only reads a file. It never touches WoW, never reads its memory, never sends
it anything, and does not automate any part of playing.

**Chain Push** is that program. On a Mac, `push/ChainPush.app` is ready to
double-click — drag it to your Applications folder if you like. It needs
nothing installed: with Python it opens the full window, and without it runs on
the Mac's own dialogs instead, with a small window that says it is running and
a Stop button. On Windows, double-click `push/ChainPush.bat` or build
`ChainPush.exe` with `push/build.py`.

Pick ntfy or Discord, paste your topic or webhook, press Start. The icon sits
in the Dock or on the taskbar while it runs. There is a command-line version
too, `push/chainpush.py`, with the same engine.

| | needs the addon's marker? |
|---|---|
| the instance has been reset | no |
| a reset failed, and why | no |
| someone started a ready check | yes |

The chat log is written in 48 KiB blocks, so a line can sit in the game's
memory for ten minutes before it reaches the disk. For alerts that have to
arrive now, the addon takes a screenshot instead — one for a ready check, two
for a reset — because those are written at once, and the companion program
watches for them and deletes them again. **Instant alert (screenshot)** in the
settings turns it on.

The first two are the game's own wording, already in the log. A ready check
produces no chat line at all, so the addon writes one — into a channel only
your character is in, removed from your chat windows so you never see it.
`/chain signal` turns that on.

---

## Commands

```
/chain               history, boosters, gold, instances and route
/chain boosters      straight to the booster list and prices
/chain adverts       everyone who has advertised, with whisper
/chain config        instances, levels and prices
/chain stats         print the current step to chat
/chain gold          what you have paid, and to whom
/chain export        every run as CSV (add `gold` for trades)
/chain rs            reset your instances
/chain testalert     preview the reset alert
/chain signal        write markers for the phone-notification script
/chain share         swap measurements with other addon users
/chain ads           read boost adverts out of chat
/chain heard         the last adverts the addon picked up
/chain announce      tell the group when the instance resets
/chain show          show or hide the bar
/chain lock          stop the bar being dragged
/chain scale 1.2     resize the bar
/chain debug         what the addon thinks is going on right now
/chain reset         delete all recorded history
```

`/lb` is the short form. The old names — `/level`, `/lt`, `/boost` — all still
work, so nothing you have in your fingers stops working.

---

## How it stores things

Every completed run and every trade is stored individually in
`WTF/Account/<account>/SavedVariables/Chain.lua`, account-wide, so
booster records and spending carry across your characters. Averages, ratings
and forecasts are all computed from those lists on demand, which means a
settings change re-reads your whole history rather than starting over.

The instance a run belongs to is recorded by its **instance id**, not its name.
Names are localised and Blizzard renames places — what this addon's table calls
"The Stockade" the current client calls "Stormwind Stockade" — and a run filed
under a name nothing matched would never reach its step. Names are matched
loosely as a fallback.

The experience table is the original pre-2.3 one, and the addon also reads what
your client says each level costs and prefers that, so it corrects itself on a
client with a different table.

Instance entries are account-wide (the daily figure counts every character).
The run in progress and your experience-rate buckets are per character.

---

## Is this allowed?

Blizzard's UI Add-On Development Policy asks that add-ons be free, carry no
advertisements and solicit no donations, keep their code visible and
unobfuscated, stay within the T rating, and not negatively impact realms or
other players. This add-on is free, unobfuscated, uses only the documented API,
and paces its own network traffic for that last point.

Nothing subjective is broadcast. What travels between copies is what a booster
charges and what he measurably did — the same thing you would tell a friend who
asked.

The companion program reads a log file the game itself writes. It does not
interact with the client in any way.

---

## The rename

This was called **Level Tracker** until it was called Chain. If you are
upgrading: your history, gold and boosters are carried over the first time the
new version loads, because the `.toc` still declares the old saved variables
and the addon adopts them once. Chain Push keeps the settings the old
LevelPush had, for the same reason. Nothing to do by hand.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
