# Changelog

## 1.1.0

The addon stopped being about levelling only, so this release is mostly the
parts that are not.

**Honour**

- On the bar tooltip, the minimap tooltip and `/chain pvp`: what rank you end
  up at after the next weekly reset, and how much more honour you need tonight
  to not go backwards. It only appears once there is honour to talk about.
- The arithmetic is the honour system's own - honour into contribution points
  at three exchange rates, contribution points into a rank, then a fraction of
  the way from where you stand to where the honour says you belong, with the
  fraction shrinking as the rank goes up. It says on the tooltip that it is a
  model rather than the server.
- Honour per hour, measured in minute buckets the same way experience per hour
  is, so a break does not quietly halve the rate.

**Who is out there**

- A kill-on-sight list, by name or by whole guild.
- Enemy players detected from nameplates, your mouse, your target and the
  combat log. The combat log reaches furthest, so somebody casting two rooms
  away is in it.
- A short list on screen of who is close: class-coloured, fading as the
  sighting gets old, with everything known about them on the tooltip rather
  than in the row.
- A marked player raises the alarm whether or not you asked for alerts, the
  banner pulses and stays twice as long, and **the nameplate is marked**,
  because a line at the top of the screen tells you somebody is here but not
  which of the four in front of you it is.
- An Enemies tab for all of it, with a one-click mark on every row.

**Trade**

- The Gold tab is now Trade, and records the goods as well as the coin: what
  you gave, what you got back, both ways. Half of what crosses the table in a
  boost is a stack of cloth or the greens off the run, and a log that only
  counts money says you paid less than you did.

**Smaller things**

- Grey quests are left out of the "ready to hand in" count. They give no
  experience, so counting them made the number wrong in the one direction
  that matters.
- The bar's heading shows the span you configured rather than the level you
  happen to be, and the fill and the percentage are of the whole step, not of
  the level inside it, with a tick drawn at each level boundary.
- The search box moved below the tab row, which had grown too long to share
  the line with it.
- The minimap button goes through LibDBIcon now. The hand-rolled one drew the
  same icon in the same place, but every button-collecting addon on the screen
  looks for LibDBIcon buttons and complains about anything else. Being right
  about the pixels is worth less than being the shape the rest of the
  ecosystem expects. The tooltip and the three clicks are still ours, and the
  tooltip gained the honour line and the count of players nearby.
- `/chain` prints `/chain` in its own help, and `/chain trade`, `/chain
  enemies`, `/chain kos NAME`, `/chain nearby`, `/chain groups` and
  `/chain minimap` are in the list.
- The push program's install instructions are rewritten as three numbered
  steps, and the shell version now carries settings over from either of the
  older names rather than one.

## 1.0.0

Renamed from Level Tracker to Chain before release. Anything recorded under
the old name is adopted the first time this version loads - runs, trades,
boosters, settings - and so are the push program's settings.

First release.

**The forecast**

- Runs, time and gold remaining to the end of a route, learned from your own
  runs rather than guessed.
- The forecast follows the booster you are actually with once he has three runs
  of his own in that step, so switching from a fast booster to a slow one moves
  the numbers instead of blending them.
- A run only counts as a boost when somebody is ten or more levels above you.
  Self-cleared runs are averaged separately.
- Average group level, graded by what the make-up costs you in experience.
- Two lines under the bar and always the same two - the run you are in, then
  the next thing that happens and the decision it leads to. The booster's
  name, his rate, gold per level, experience per gold and the group's make-up
  are on the tooltip, said better and with room to explain themselves; under
  the bar they were a second line to read past.
- Ordinary levelling mode when no dungeon run is recent: experience per hour,
  time to the next level, rested, quests ready to hand in.

**Resets and lockouts**

- Reset detection from the game's own message and from party chat, with the
  three failure reasons read as well.
- The alert knows whether its advice is possible: it will not say "go in" when
  you are at five instances in the hour.
- Two different sounds, because a reset means opposite things on the two sides
  of the portal: one for "go in", another for "zone out", chosen from a short
  list and played as you pick them. The sound follows the situation - walk out
  while the alert is live and it changes to the other one. Repeated on the
  Master channel, which plays with the game muted.
- Your lockout said out loud to the party or raid, because nobody else can
  see it: one line when a reset arrives you cannot use, one when it frees up,
  and nothing in between.
- One timeline of everything that happened to an instance: every entry with
  its own countdown and every reset, in the order they happened, all of it the
  addon's own record.
- Nova Instance Tracker is optional in the real sense. The one thing it has
  that cannot be seen from here is the entries from before this addon was
  installed, so those are copied into our own log once and it can then be
  uninstalled. Reading its live count instead is a setting, off by default.
- The game's own refusal at the portal - "you have entered too many instances
  recently" - corrects the count rather than being argued with, and says so,
  because counting zone-ins cannot know about a day the addon was off.

**Knowing when to move on**

- Experience decay modelled from the grey level and zero-difference tables,
  anchored to your own measured runs, so the bar can say when another instance
  becomes the cheaper buy and the Route tab can show what a level will cost by
  the time you leave each step.

**Boosters and gold**

- A Groups tab for the other half of the same channels: everyone looking
  rather than selling - LFM, LFG, WTB - with what they are short of, the
  levels they ask for and what they said in full, whisper button included.
  Nothing is matched against anything; the search box is what narrows it, and
  a man repeating himself is one row with a count rather than twenty rows.
- A booster list fed by chat adverts, your own runs, and other people's addons.
  Adverts are read from every channel you are in, and from whispers, say, yell,
  guild and party; the settings have a list of those sources where any of them
  can be switched off.
- The verdict is computed — experience per gold — not clicked.
- Prices are per pack, and the pack is not one number for everything: the
  settings hold a default, each instance on the route can have its own, and a
  booster can have his own on top of that - because ten Stockade runs for one
  price and five in Scholomance is an ordinary week. A price typed against a
  booster wins over the one typed against the instance while he is the one
  boosting you, everywhere a figure is worked out, and a pack typed against
  him stays put when you retype his price.
- Your own list: add a booster by hand, with a note in your own words, before
  you have ever run with him. Notes are editable on every row and are never
  shared.
- Trade log: what you actually paid, to whom, and per level.

**Sharing**

- Measurements swapped addon-to-addon over a hidden channel, your guild, or a
  list of names. Off by default. Only facts travel; nothing received is passed
  on.

**Everything else**

- A button on the minimap, with the addon's own icon on it: left-click for the
  window, right-click for the settings, middle-click for the bar, drag to move
  it round the edge, and a tooltip carrying the lockout and what is left in
  the step. Hand-rolled rather than LibDBIcon - nothing to ship, nothing to
  keep up to date, nothing that breaks when another addon updates.

- Eight-tab window with sorting, a search box and CSV export, including an
  Adverts tab: everyone who has advertised anything, from any channel, newest
  first, sortable, with a whisper button on each row.
- Every instance carries two levels and shows both - the level the game lets
  you in at, and the span the place is worth doing at - on the bar, in the
  settings, on the Route tab and under the booster list, coloured against
  where you actually are. The settings say so when the span you typed starts
  before the game will let you in.
- The bar tooltip carries the whole step: the span, the run figures, what a
  level costs now and at the end of the step, the booster in full with his
  price and verdict, group, lockout, what you have paid and what the route
  still comes to. The bar itself keeps only what you act on.
- Phone alerts that arrive in seconds: the chat log is written in 48 KiB
  blocks and nothing flushes it, so the signal is a screenshot instead - one
  for a ready check, two for a reset - which the client writes at once. The
  companion program counts them, sends the push and deletes the files.
- Optional companion program for phone notifications via ntfy or Discord:
  Chain Push, a window with the two choices in it. macOS gets a ready-made
  ChainPush.app that needs nothing installed - the full window where there is
  a Python, the Mac's own dialogs where there is not - and Windows a .bat or a
  built .exe. Settings are remembered, a green light and the Dock or taskbar
  icon say it is running, and closing the window offers to keep it going in
  the background. The command-line version is still there.
- 500 addon tests against a stubbed client, 93 for the push program against a
  stubbed Tk and a throwaway server, and 30 for the shell version of it.
