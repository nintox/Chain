<p align="center">
  <img src="push/icon.png" width="128" alt="Chain">
</p>

<h1 align="center">Chain</h1>

<p align="center">
  <b>What a run is actually worth.</b><br>
  A World of Warcraft Classic Era addon for the runs you do over and over.
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#what-it-does">What it does</a> ·
  <a href="#the-window">The window</a> ·
  <a href="#phone-notifications">Phone notifications</a> ·
  <a href="#is-this-allowed">Is this allowed</a>
</p>

---

Boosting, levelling, chaining resets, farming honour. Chain measures what you
actually do and tells you what it is worth: how many runs are left, how long
they take, what they cost, which booster to pay, and when the next instance
becomes the cheaper buy.

Nothing is guessed. Every figure comes from your own runs.

```
SM  28 > 42   4%                          inst 4/5  +1 in 13m
┌──────────────────────────────────────────────────────────┐
│ Lvl 34  57.0%        594,813 to 42               75.1 runs│
└──────────────────────────────────────────────────────────┘
 7,919 xp/run (Snoeggboost 9)   5m/run   ~6h 46m left   ~3,200g
 lvl 35 in ~7m
```

---

## Install

**From CurseForge**, with the CurseForge app or WoWUp — search for Chain.

**By hand:** download the latest release, unzip it, and put the `Chain` folder
into

```
World of Warcraft/_classic_era_/Interface/AddOns/
```

so that `AddOns/Chain/Chain.toc` exists. Restart the game, or type `/reload`
if it was already running.

`/chain` opens the window. There is also a button on the minimap: left-click
for the window, right-click for the settings.

### Setting up

`/chain config`, or right-click the minimap button.

Tick the instances you will be going through and give each one a level span, a
price, and how many runs that price buys. That is the whole setup — everything
else is learned from the runs you do.

| column | what it is |
|---|---|
| **enter** | the level the game lets you in at |
| **levels** | the span the place is actually worth doing |
| **from / to** | your plan for this step |
| **gold** | what a pack costs |
| **runs** | how many runs that pack is |

---

## What it does

### The forecast

Runs, time and gold to the end of your route, learned from your own runs
rather than guessed.

A run only counts as a boost when somebody ten or more levels above you is
doing the killing; runs you cleared yourself are averaged separately, so the
two never contaminate each other. The forecast follows the booster you are
actually with once he has three runs of his own in that step — so swapping a
fast booster for a slow one moves the numbers instead of blending them.

Two lines under the bar, and always the same two: the run you are in, then the
next thing that happens. A block that grows and shrinks as figures come and go
is a block that moves about while you are reading it. Everything else is on
the tooltip.

When no dungeon run is recent it turns into an ordinary levelling bar:
experience per hour, time to the next level, rested, and quests ready to hand
in — with the grey ones left out, because handing those in is worth nothing.

### Is he worth it?

Type the price a booster quotes and how many runs it buys. The verdict —
experience per gold — is computed, not clicked.

A price typed against a booster beats the one typed against the instance for
as long as he is the one boosting you, everywhere a figure is worked out.
Pack sizes live in three places, most specific first: the booster, the
instance, and the setting. A ten-run deal in Stockade is not a ten-run deal
everywhere, and the same man does not sell every instance the same way.

### When to move on

Experience decay is modelled from the grey level and zero-difference tables
and anchored to your own measured runs. Chain can say what a level costs here
today, what it will cost by the time you leave, and when another instance
becomes the cheaper buy.

### Resets and lockouts

Reset detection from the game's own messages, with the three failure reasons
read as well — somebody still inside, somebody zoning, somebody offline.

**Two different sounds**, because a reset means opposite things on the two
sides of the portal: one for *go in*, another for *zone out*. Walk out while
the alert is still live and the sound changes with you. Pick them in the
settings; clicking one plays it, because an alert you have never heard is an
alert you learn to ignore.

The addon keeps its own instance log with a per-entry countdown. When the game
refuses you at the door — *you have entered too many instances recently* — the
count is corrected to what the game says rather than argued with, because
counting zone-ins cannot know about a day the addon was switched off.

It can also tell your party your lockout: `locked 5/5 - free in 12m` when a
reset lands you cannot use, and `free again` when that changes. Two lines and
no more. A countdown in party chat is the fastest way to be asked to turn an
addon off.

### Boosters, adverts and groups

Boost adverts are read from every channel you are in, and from whispers, say,
yell, guild and party. Any of those sources can be switched off.

The other half of the same channels is kept too: **LFM, LFG and WTB**, with
what they are short of, the level range they ask for, and what they said in
full. Nothing is matched against your quest log or anything else clever — the
search box is what turns it into a list of one thing. Somebody shouting the
same line every thirty seconds is one row with a count, not thirty rows.

Your own notes on any booster, written in your own words. Notes are never
shared.

### Honour

Your weekly honour turned into the only two numbers that matter: what rank you
end up at after the next reset, and how much more you need tonight to not go
backwards. On the bar tooltip, on the minimap tooltip, and from `/chain pvp` —
and only once there is honour to talk about.

The arithmetic is the honour system's own — honour into contribution points at
three exchange rates, contribution points into a rank, then a fraction of the
way from where you stand to where the honour says you belong. The fraction
shrinks as the rank goes up, which is why the top ranks took months. It is a
model of the reset and says so rather than pretending to be the server.

### Who is out there

A kill-on-sight list, by name or by whole guild, and the watching to go with
it. Nameplates, your mouse, your target and the combat log all feed it — the
combat log reaches furthest, so somebody casting two rooms away is in it.

Marked players raise the alarm whether or not you asked; everyone else only if
you did. The alert for a marked one pulses and stays twice as long, and their
**nameplate is marked**, because a line at the top of the screen tells you
somebody is here but not which of the four in front of you it is.

A small list on screen shows who is close, class-coloured, fading as the
sighting gets old. Everything known about them is on the tooltip rather than
in the row: a row you have to parse is a row you look away from.

### Gold and goods

Every trade you completed — what you paid, to whom, what you got back, and
what changed hands that was not money. Half of what goes across the table in a
boost is a stack of cloth or the greens off the run, and a log that only
counts coin says you paid less than you did.

### Sharing

Measurements can be swapped addon-to-addon over a hidden channel, your guild,
or a list of names. **Off by default.** Only facts travel — the price you were
quoted, experience per run, time, mob count. Nothing you wrote and nothing you
think. Anything received is kept visibly apart from your own figures, and
nothing received is passed on.

---

## The window

`/chain`, or the minimap button.

| tab | what is on it |
|---|---|
| **History** | every run, coloured against that instance's own average, so a slow one stands out without reading the numbers |
| **Boosters** | everyone selling the step you are on, with the verdict |
| **Adverts** | everyone who has advertised anything, from any channel, with a whisper button |
| **Groups** | everyone looking rather than selling: LFM, LFG, WTB |
| **Reported** | what other people's addons told you, kept apart from your own |
| **Trade** | every trade, gold and goods, both ways |
| **Enemies** | everyone seen out there, and the kill-on-sight list |
| **Instances** | one timeline of every entry and every reset, with countdowns |
| **Route** | the plan from where you stand, step by step |

Every tab sorts by any column, searches with one box, and exports to CSV.

`/chain` on its own prints the whole list of commands. The ones worth knowing
before you need them:

| | |
|---|---|
| `/chain config` | instances, levels and prices |
| `/chain pvp` | your rank, and the one the next reset gives you |
| `/chain kos NAME` | mark somebody kill on sight |
| `/chain nearby` | the list of players on screen, on or off |
| `/chain rs` | reset your instances |
| `/chain export` | every run as CSV — add `trade` for trades |

---

## Phone notifications

Optional, and nothing in the addon depends on it.

A WoW addon has **no network access of any kind** — no HTTP, no sockets, for
anybody, ever. So nothing inside the game can reach your phone. What the game
does do is write files, and a small program outside the game can watch them.

```
WoW  ──writes──▶  a file  ──watched by──▶  Chain Push  ──▶  ntfy / Discord
```

The obvious file is the chat log, and it turns out to be far too slow: the
client writes it in 48 KB blocks, so a line can sit unwritten in memory for
ten minutes. Screenshots are not buffered — the client puts one on disk the
moment it is asked. So the addon takes one for a ready check and two for a
reset, and the companion counts them, sends the push, and deletes the files.
They were signals, not pictures.

**Chain Push** is a Dock icon on a Mac and a system tray icon on Windows. It
sits there the whole time it is working; clicking it gives you the status, a
test, and the settings. Closing the window does not stop it. Quit does.

Full instructions, including how to build the Mac app in one double-click, are
in [`push/README.md`](push/README.md).

---

## Is this allowed

Yes, and it is worth saying why rather than asking you to take it on trust.

Chain reads what the client has already put on your screen and does
arithmetic on it. It does not automate any part of playing, does not click
anything for you, does not read the game's memory, does not talk to Blizzard's
servers, and does not do anything you could not do yourself with a notepad and
more patience.

The companion program never touches WoW at all. It watches a folder.

---

## Building and testing

Everything is plain Lua with no build step. Clone it into your AddOns folder
and it runs.

```bash
lua5.4 test/run.lua       # the addon, against a stubbed client
python3 test/pushtest.py  # the companion, against a stubbed Tk and a fake server
bash test/shelltest.sh    # the shell version of the companion
```

Over seven hundred assertions, no WoW and no network in any of them. The
client is faked in `test/wowstub.lua`; if a test needs a new API, that is
where it goes.

`Libs/` is other people's code, carried the way every WoW addon carries it:
LibStub and LibDataBroker are public domain, CallbackHandler and LibDBIcon are
from the Ace3 family. Everything else here is MIT — see [LICENSE](LICENSE).
