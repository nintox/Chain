<p align="center">
  <img src="push/icons/icon.png" width="160" alt="Chain">
</p>

<h1 align="center">Chain</h1>

<p align="center"><b>Is this run worth it?</b><br>
An addon for World of Warcraft Classic Era.</p>

---

You are being boosted through Stockade for the tenth time tonight. Is this
booster faster than the last one? How many more runs until 42? Is he charging
too much? Should you have moved to Scarlet Monastery two levels ago?

Chain answers all of that by watching what actually happens and doing the sums.
Nothing is guessed — every number comes from your own runs.

```
SM  28 > 42   4%                          inst 4/5  +1 in 13m
┌──────────────────────────────────────────────────────────┐
│ Lvl 34  57.0%        594,813 to 42               75.1 runs│
└──────────────────────────────────────────────────────────┘
 7,919 xp/run (Snoeggboost 9)   5m/run   ~6h 46m left   ~3,200g
 lvl 35 in ~7m
```

A bar on your screen, two lines under it, and everything else on the tooltip
when you hover over it.

---

## Install

1. Get it from CurseForge with the CurseForge app or WoWUp — search for
   **Chain**. Or download it here and drop the `Chain` folder into
   `World of Warcraft/_classic_era_/Interface/AddOns/`.
2. Start the game. Type **`/chain`**, or click the Chain button next to your
   minimap.
3. Right-click that button, tick the dungeons you plan to run, and put in the
   price a booster charges. That's the setup.

Everything else it works out by itself as you play.

---

## What it tells you

**How much longer.** Runs left, hours left, gold left — to the level you're
aiming at, not just the next one.

**Whether the booster is any good.** It measures each one separately. When you
swap a fast booster for a slow one the numbers change, instead of quietly
averaging the two together.

**Whether the price is fair.** Type what he's asking. Chain works out what you
get for your gold and says whether it's better or worse than the others.

**When to move somewhere else.** Mobs give less experience as you out-level
them. Chain knows when the next dungeon becomes the better deal, and tells you
before you waste a night.

**When the instance resets.** Two different sounds, because *go in* and *get
out* mean opposite things. It also keeps count of your five-per-hour limit and
can tell the group how long until you're free.

**Who's selling and who's looking.** Everyone advertising a boost in chat, and
everyone looking for a group, collected in one list you can search. Whisper
them with one click. You can add your own private notes on anyone.

**What rank you'll be.** Put in the rank you want and Chain lays out the weeks
to get there — the honour to hit each week and where that leaves you.

This part matters more than it sounds: the honour system is a staircase, not a
slope. Each week there are a few exact honour numbers that count, and
*everything in between them is worth nothing*. Stopping 500 honour short of one
is the same as not playing. Chain's whole job here is telling you which number
you're aiming at and how far off you are.

**Who's nearby.** A list of enemy players around you. Mark the ones you don't
want to meet again and Chain shouts when they show up — and puts a mark on
their nameplate so you know which one it is.

**What you've spent.** Every trade: gold, and the items that went with it.

---

## The window

`/chain`, or click the minimap button. Ten tabs — History, Boosters, Adverts,
Groups, Reported, Trade, Enemies, Rank, Instances, Route. Every one of them
sorts, searches and saves to a spreadsheet file.

Handy commands:

| | |
|---|---|
| `/chain` | the window |
| `/chain config` | the setup |
| `/chain pvp 12` | plan for rank 12 |
| `/chain kos Name` | mark somebody |
| `/chain rs` | reset your instances |

Type `/chain` on its own to see the rest.

---

## Alerts on your phone

Optional, and a separate program rather than part of the addon — a WoW addon
has **no network access of any kind**, so anything that reaches your phone has
to run outside the game. It buzzes you when the instance resets or somebody
starts a ready check: the two moments you are usually looking away.

### Download it

| | |
|---|---|
| **Windows** | [`ChainPush.exe`](../../releases) — double-click it. The icon appears in the tray, by the clock. |
| **macOS** | [`ChainPush.zip`](../../releases) — unzip, open `ChainPush.app`. The icon appears in the Dock. |

One file. Nothing to install alongside it, nothing to tick, no Python. Both
are on the [Releases](../../releases) page, built by GitHub's own runners —
a program can only be built on the system it is for.

The first time, the system will stop you: Windows SmartScreen **More info** →
**Run anyway**, macOS right-click → **Open** → **Open**. Neither is signed
with a paid certificate; once is enough. Then it asks where to send — an
[ntfy](https://ntfy.sh) topic or a Discord webhook — and never asks again.

**[What it is, how it works, and how to run it from source →](push/README.md)**

---

## Is this allowed?

Yes. Chain reads what's already on your screen and does arithmetic on it. It
doesn't play the game for you, doesn't click anything, doesn't touch Blizzard's
servers, and does nothing you couldn't do yourself with a notepad and a lot
more patience.

Anything you share with other Chain users is measurements only — prices,
times, experience. Your own notes stay yours, and sharing is off unless you
turn it on.

---

## For anyone who wants to poke at it

Plain Lua, no build step. Clone it into your AddOns folder and it runs.

```bash
lua5.4 test/run.lua       # the addon
python3 test/pushtest.py  # the phone helper
bash test/shelltest.sh
```

Around 800 checks, none of which need WoW or a network.

`Libs/` is other people's code, carried the way every WoW addon carries it.
Everything else is MIT — see [LICENSE](LICENSE).
