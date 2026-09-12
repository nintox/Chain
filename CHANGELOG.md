# Changelog

## 1.1.0

The addon stopped being about levelling only, so this release is mostly the
parts that are not.

**Honour**

- A **Rank tab**. Put in the rank you want and it lays out the weeks: the
  honour to hit each week, what that ends the week at, and what the whole
  climb comes to.
- It is built on the system the game runs **now**, not the one from 2005, and
  they work nothing alike. Since 1.14 each week gives you up to four honour
  milestones fixed by the rank you are on. Meet one and you advance a set
  amount. Honour below the first does nothing, honour between two does
  nothing, and honour past the last does nothing - there is no partial credit
  anywhere in it. You also need 15 honourable kills, and you cannot go down.
- So the tab's job is to tell you **which number to stop on**, and it says how
  far off you are and when the rest of the week is wasted. The tooltip on each
  week lists every milestone open to you that week, so you can take a slower
  one deliberately.
- The first version of this shipped the old model - honour converted to a
  standing, the rank dragged a fraction of the way towards it - and it was
  wrong in a way that showed: every pace came out at 500,000 a week and rank
  14 read as impossible. The arithmetic here is checked against the published
  worked example, and reproduces all four of its milestones exactly.
- On the bar tooltip and the minimap tooltip: the milestone you have met, the
  next one, and what is still missing - including how many kills short you
  are, since nothing counts without fifteen.
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
- Somebody found only through the combat log used to sit in the list as a grey
  name with a question mark, because the combat log carries no class. The GUID
  is enough to ask the client, so they now arrive class-coloured with the
  class written out, and the level stays an honest question mark.
- The on-screen list reads like the other watchers now: one row per player,
  tinted by class, with the name on the left and "45 Warrior" on the right.
  A marked one goes red whatever he plays, because that is the thing you have
  to see and it beats knowing the class.
- The note box on the Enemies tab did not work, and the reason is worth
  writing down: it was positioned, filled in and shown - and then hidden again
  on the same pass, because the Boosters branch further down turned it off in
  its else. It had been saving perfectly well the whole time; you could just
  never see it. The three fields that decide where a typed note goes are now
  cleared on every row too, so what you type cannot land on whoever was on
  that row on the last tab you looked at.
- **The list and the alert can both be placed properly.** Neither could be
  before: the list is only on screen while somebody is nearby, so you would
  drag it, the last enemy would age out, and it vanished mid-move; the alert
  showed for six seconds when somebody happened to walk past. Both now have a
  "move it" mode that holds them on screen - the list filled with examples so
  you can see the width and row count you are choosing, the alert cycling
  through its three kinds so you can see how wide each gets - until you say
  you are done.
  The settings have **Unlock / show list** and **Move the alert...**, which
  are the way back when you cannot see the thing at all: they turn it on,
  unlock it, and bring it home if it was left off the edge of the screen.
- The checkboxes of the first row in each settings section were left behind
  when that section folded, and stayed on screen on top of whatever moved up
  into their place. A checkbox sits four pixels above its own label, the
  boundary between two sections was a fixed margin, and the boxes landed six
  tenths of a pixel on the wrong side of it. Sections are worked out by
  identity now rather than by a magic number, and there is a test that every
  control belongs to a section and that a box and its label belong to the
  same one.
- The alert's "done" menu closed itself before you could reach it. One menu is
  shared by the list and the alert, and the list's refresh was closing it on
  every tick whatever it happened to be open on; it only closes its own now.
- A stealthed player gets the stealth icon rather than the class ring. What
  matters about a rogue you cannot see is that you cannot see him, and a druid
  in cat form is the same news - the class is on the line underneath either
  way.
- **The settings are built like the history window now**: the same width, a
  row of real tabs at the top, one page at a time underneath - Instances,
  Runs and prices, Resets and alerts, What to read out of chat, Who is out
  there, Sharing and the bar. The instance table is a page like any other
  rather than always sitting above everything else, which is most of why the
  panel used to be the length of a screen.
  The columns are 284 pixels apart instead of 164, so a label no longer has to
  be shortened until it stops saying what it means.
  Which page a control belongs to is decided when it is made rather than
  worked out afterwards from where it ended up, and the height is the tallest
  page rather than the current one - a frame that resizes when you change tab
  is a frame whose buttons move under the cursor.
- The settings drew two pages at once: the instance table came back on top of
  whichever page you had chosen. Choosing the page happened first, and
  everything after it shows and hides rows of its own - the instance table in
  particular redraws its rows on every pass. The page is chosen last now, and
  there is a test that a full redraw does not bring the table back.
- Both windows are fully opaque and the settings sit strictly above, so
  neither one's text can be read through the other when both are open.
- **A loot log**: everything that dropped, yours and everyone else's in the
  party or raid, with who got it, what it vendors for, and which run and
  booster it fell under. Its own tab, or `/chain loot`.
  The combat log carries none of this - the chat messages do, and they arrive
  for the whole group. The sentences are turned into patterns from the
  client's own strings ("You receive loot: %s.") rather than matched against
  English written out by hand, which is the only reason it works on a client
  in any language. Coins too, with the unit names taken from the client the
  same way.
  An item the client has not cached yet says so instead of showing nothing: a
  zero in a money column is a claim.
- **What it dropped from**, for your own loot. The loot message does not say -
  nothing in it does - so this is two halves neither of which is any use
  alone: the loot window names the corpse it is showing, but only as a GUID,
  and the only place that GUID was ever given a name is the combat log when
  the thing died. Somebody else's loot has no source at all and the column
  stays blank rather than guessing, because a wrong mob is worse than no mob.
- **One row per corpse.** A mob that gave you a jerkin, three cloth and
  thirty-five copper is one event, and reading it as three lines that happen
  to sit next to each other is reading it wrong. The row lists what it gave,
  coins last, with the total for the whole corpse; more than three things and
  the rest is a tally with the full list on the tooltip.
  Grouped on the way out, not on the way in: the log still stores one entry
  per thing, so exports and totals are unaffected and two of the same item off
  one mob is still two drops.
- Coins carry the source too. They came off the same corpse as everything
  else in that loot window, and leaving it out put the money and the cloth
  from one mob on two lines that did not look related to each other. The count
  column shows a dash for coins rather than "1", which meant nothing.
- Coins are written the way the game writes them - "15s 3c", "2g 15s". They
  went through the gold formatter, which rounds to whole gold, so fifteen
  silver came out as "0g" and a column of noughts read as a broken log rather
  than as small amounts.
- **A note no longer marks anybody.** They are not the same thing: "always
  rides with two friends" is worth writing about somebody you have no
  intention of hunting, and having to mark him to say it made the mark mean
  less than it should. Notes live in their own store, and old ones written
  inside a mark are moved across on the first load.
  The catch a separate note has to answer is where you find it again, so the
  kill-on-sight list shows everyone you have *written about* as well as
  everyone you have marked, labelled "note only" and in gold rather than red.
  On the screen list a marked one gets a red "!" and somebody you have only
  written about a quieter gold "*".
- The note popup has Save, Cancel and a Save-and-mark button. Enter saved and
  Escape cancelled before, and neither was written anywhere.
- **Wins and losses are a column now**, on both enemy views, not
  just on the tooltip. Green when you are ahead, red when you are not, and a
  dash when you have never fought - a column of "0-0" is a column of noise.
- **A kill-on-sight list of its own**, under the Enemies tab - one button
  switches between "everyone seen" and "kill on sight", or `/chain marked`.
  They are not the same list: somebody you marked three weeks ago is not in
  Enemies at all once the sighting has aged out, and that is exactly the one
  you want to find again. Names and whole guilds together, with your notes
  editable in place and a clear button on every row.
- **Left-click a name in the on-screen list to target him**, and shift-click
  to target and mark in one go.
  This one needed doing properly: `TargetUnit` is a protected function and an
  addon cannot call it at all, not even out of combat - so the "Target" entry
  added to the right-click menu earlier did nothing whatsoever, and it is
  gone. The rows are secure buttons running a `/target` macro instead, which
  is the only way it can work.
  A secure button's attributes are frozen in combat, so the list holds still
  there and says so in its heading, rather than pointing a click at whoever
  used to be on that row. The banner still announces everyone who turns up,
  which is the part that matters mid-fight.
- **Marked players sort to the top of the list.** It is cut off at a row
  count, so the order decides who you never see - and somebody you marked
  dropping off the bottom because three strangers walked past is the one
  failure this list cannot afford.
- How long somebody stays on the list after you stop seeing them is yours to
  set. Too short and a rogue who stepped behind a rock is gone; too long and
  the list is a history of the zone rather than who is here.
- Giving the list a scale of its own broke the dragging, and this is why: a
  frame answers GetLeft in its own units, and a SetPoint offset is read in
  those same units - but the two are only the same number while the scale is
  1. Saving one and setting the other moved the box by the scale factor every
  time you let go. Position is kept in screen pixels now and converted on the
  way in and out, so it lands where you put it at any size. The test only
  checked what was saved, never the round trip, which is exactly how it got
  through; it checks the round trip now, at a scale other than 1.
- The alert is a proper banner rather than a line of text: the class ring, the
  kind said in words - "Kill-on-sight player detected!", "Stealthed player
  detected!" - and the name, level and class under it. Marked and stealthed
  ones pulse and stay twice as long; a passing stranger does neither. It can
  be dragged where you want it.
- **A stealthed player gets its own alert, in the middle of the screen**, and
  is marked in the list. It is the one sighting where knowing is the whole of
  the advantage: a rogue you have seen is a rogue who has lost the opening,
  and the top of the screen is where you are not looking when you are being
  opened on. Read from the aura rather than guessed from the class, because
  half the ones that matter are druids.
- **Right-click anybody** for everything you might want to do about them:
  mark, mark the whole guild, target, whisper, look them up - and the list's
  own settings under that.
- **Your score against each player**: kills you or your group made, and deaths
  they caused, counted off the combat log and shown on the tooltip. It is the
  one piece of history about another player that is genuinely yours - the
  server will tell you nothing about them, but it will tell you who stopped
  moving. A death is blamed on whoever hit you last inside fifteen seconds:
  not perfect in a five-man gank, but the same thing you would remember.
- **A note on anybody, from the right-click menu.** The reason you marked
  somebody is worth more than the mark: "ganks the SM entrance at 2am" is a
  plan, a red name is a colour. Writing one marks him, because you do not
  write a note about somebody you do not care about. Never shared.
- **A level for people you have never laid eyes on.** A spell rank cannot be
  cast below the level it is learned at, so an ability puts a floor under its
  caster. Shown as "45+", because a floor is all it is - a level 60 casting
  Rank 1 still reads as 4+ - and a level you actually saw always wins and
  clears the guess.
  The spell table is Spy's, read from its global if Spy is loaded, the same
  way Nova Instance Tracker's count is read: nothing copied, nothing shipped,
  and without Spy this simply does nothing. Three thousand rows of game data
  is a job of its own.
- Class and race come off the same table, so somebody who only ever appears
  in the combat log arrives class-coloured instead of grey.
- The list has a size of its own, bigger than the game's small font by
  default. It is read in the two seconds before a fight, not studied.
- Levels are picked up from every unit the client will give one for, not only
  the one you are pointing at: your target's target, your mouseover's target,
  and whatever the rest of the group is swinging at. Most of the people you
  are actually in a fight with now arrive with a level instead of "??".
- The sighting remembers where you were standing, so the tooltip reads
  "Scarlet Monastery (47, 19)" rather than just the zone.
- The tooltip lost the paragraph explaining why a level was missing. It was
  longer than everything else on there put together; it is one dim line now.
- **Call out a sighting to your own side**: name, level if known, class,
  guild, the zone and your coordinates, straight into party, raid, guild or
  say. From the right-click menu, or `/chain spot`. Marked players can be
  called out automatically - off by default, because it puts a line in a
  channel other people read.
- A /who lookup for the missing levels was built and then removed, because it
  could never have worked: /who only returns your own faction, and everybody
  in this list is on the other one. Whispering them is impossible for the same
  reason, so that went too. A button that looks like a feature and quietly
  does nothing is worse than no button - the level says "??" and the tooltip
  says why.
- The list can be dragged wider or taller by the corner. Width is what closes
  the gap between a short name and the class beside it, and the extra room
  goes to the name rather than into the middle. Height is stored as a number
  of rows rather than pixels, so it survives a change of font or scale.
- The on-screen list grows up or down from wherever you parked it, can be
  locked, and how many rows it shows is yours to set. Right-click the list for
  all three, and "back to the middle" if it ever ends up somewhere you cannot
  reach.
- **It can be dragged properly now.** It jumped about and would not sit still,
  for two reasons: the refresh tick re-applied the anchor a few times a second
  while you were holding it, pulling the frame out from under the cursor, and
  the box grew or shrank under your finger as people came and went. Neither
  happens during a drag any more. You can also grab it by any row rather than
  hunting for the sliver of background the rows leave uncovered, and a click
  that does not move still marks somebody.

**Trade**

- The Gold tab is now Trade, and records the goods as well as the coin: what
  you gave, what you got back, both ways. Half of what crosses the table in a
  boost is a stack of cloth or the greens off the run, and a log that only
  counts money says you paid less than you did.

**At the top of the ladder**

- **At max level the bar becomes the honour bar, by itself.** There is no
  experience left to measure, so an experience bar there is a bar that will
  never move again; the week's honour is the only thing still going up.
- It says what you are **still missing this week**, in the middle where the
  experience bar says how much is left to the next level, with a percentage on
  the left exactly where that bar puts one. Same shape, because it is the bar
  it replaces and the eye already knows where each number lives.
- And it is missing towards the right number: if you have set a target rank,
  the goal is the plan's **first week**, not the smallest step up. Aiming at
  the small one and stopping there is how a fourteen-week plan quietly becomes
  a twenty-week one.
- The fill runs from the milestone you have already banked to the one you are
  aiming at this week,
  because that gap is the only stretch where the honour you earn is worth
  anything, and where you are inside it is precisely the question. The
  heading is your rank and, if you have set a target, how many weeks away it
  is. Under it: what the week ends at if you stop now, honour per hour and
  how long the next milestone is at that rate - and, first, how many kills
  short of fifteen you are, since nothing counts without them.
- Enemy players nearby get a line there too, since that is the bar you are
  looking at out in the world rather than in an instance.
- The slim second honour bar switches itself off in that mode: it would be
  the same thing drawn twice.
- Max level is asked of the client rather than assumed to be 60 - this runs
  on Era and on the anniversary realms, and it is not the same number
  everywhere. There is a switch for anybody who wants the empty experience
  bar back.

**Frames and latency**

- **A small readout on screen**: frames and latency, in the corner of your
  eye. Off by default, `/chain fps` or the switch under *Sharing and the bar*.
- The colours are the whole feature. A number you have to compare against a
  remembered threshold is a number you read; a number that turns orange is a
  number you notice. Green, gold, amber and red, and the two scales run
  opposite ways because more frames is better and more milliseconds is not.
- The latency shown is the **worse of world and home**, because that is the
  one you feel. The tooltip splits them and says which is which - world is
  whether a spell goes off, home is chat and the auction house - and says that
  the client only recomputes latency every thirty seconds, so it sitting still
  is the game and not a frozen readout.
- It hangs under the minimap until you say otherwise, which is where the eye
  already goes for this sort of number - and it no longer jumps while you drag
  it. The once-a-second refresh was re-anchoring it mid-drag, the same thing
  that made the nearby list impossible to place; neither the anchor nor the
  size is touched while you are holding it.
- Draggable, lockable, resizable, and either number can be switched off on its
  own; the box shrinks to fit rather than leaving a black bar where the other
  one was.

**Smaller things**

- The line under the bar describing the run you are in - experience so far,
  mobs, elapsed, pace, whether it counts - has moved to the tooltip. It was
  not there before, so it was worth putting there before taking it away.
  Nothing on it is something you act on mid-run: you are already inside. The
  two flags now say what they mean in words instead of being tags: "you were
  part way in when this started, so it is left out of the averages".

- Grey quests are left out of the "ready to hand in" count. They give no
  experience, so counting them made the number wrong in the one direction
  that matters.
- The bar's heading shows the span you configured rather than the level you
  happen to be - and now so does the fill. It measured the stretch left from
  your current level, so a step set to 28 > 42 sat at two per cent while you
  were level 35, under a label saying 28 > 42. The two numbers are different
  questions and both are still asked: the fill and the percentage measure the
  step as you set it up, and the runs, hours and gold still count from where
  you actually are, because you cannot earn experience you already have.
  A tick is drawn at each level boundary.
- The search box moved below the tab row, which had grown too long to share
  the line with it.
- The minimap button goes through LibDBIcon now. The hand-rolled one drew the
  same icon in the same place, but every button-collecting addon on the screen
  looks for LibDBIcon buttons and complains about anything else. Being right
  about the pixels is worth less than being the shape the rest of the
  ecosystem expects. The tooltip and the three clicks are still ours, and the
  tooltip gained the honour line and the count of players nearby.
- `/chain` prints `/chain` in its own help, and `/chain pvp`, `/chain trade`, `/chain
  enemies`, `/chain kos NAME`, `/chain nearby`, `/chain groups` and
  `/chain minimap` are in the list.
- The push program's install instructions are rewritten as three numbered
  steps, and the shell version now carries settings over from either of the
  older names rather than one.
- A slim second bar under the main one for the week's honour, with a mark at
  each milestone. Two colours, and the difference is the point: crimson is
  honour that has already bought a step and cannot be taken away, amber is
  honour earned since, which is worth nothing until the next mark is crossed.
  A long amber tail means stop or push, never carry on at this speed. Inside
  it, the one sentence worth acting on.
- The settings panel is in named sections, and **every section folds**. Click
  a heading to put it away; which ones are folded is remembered. There is a
  zoom on the title bar too, because the panel is taller than some screens
  even folded up.
  Twenty-odd controls in one undifferentiated block is a wall you read every
  time rather than a list you learn the shape of, and things that belonged
  together were nowhere near each other.
- "share with" is a label and a short value on its own button instead of a
  sentence that ran straight through the button beside it, and the value is
  gold when sharing is on and grey when it is off.

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
