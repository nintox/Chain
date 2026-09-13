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
- **The alert itself can be clicked to target.** That is where your eye
  already is in that second, and having to find the list instead is exactly
  the second a rogue needs. Targeting is protected - `TargetUnit` cannot be
  called from an addon at all - so the only way is a secure button running a
  `/targetexact` macro, which is what the banner now carries.
  - In combat the macro cannot be changed. One set before the fight still
    works, so the button is not dead; it is pointed at whoever it was pointed
    at. The line underneath says which: **click to target**, or **in combat -
    click targets Zånzå**. A banner shouting one name while the click takes
    another is worse than one that admits it.
  - The instant a fight ends, the banner and the list re-arm - from the
    event, not from the next tick.
- A secure button makes its parent protected too, and a protected frame
  cannot be hidden in combat: the call is simply refused. Both the banner and
  the list carry secure buttons, so both now ask first and come back to the
  hide when the fight is over. Both are also built at login rather than on
  first use, because a secure button created during a fight cannot have its
  attributes set for the rest of that fight.
- **The list can be kept on screen with nobody about** - a new setting, and on
  its right-click menu. A list that only exists while somebody is nearby is a
  list you cannot glance at: an empty screen and a broken addon look exactly
  alike, and you find out which it was when a rogue is already on you. With
  nobody around it is the header alone, two words high, and it says **nobody
  about** rather than a bare "0 nearby" that reads like something failed.
- The header said **locked** when it was locked. The word only ever meant "you
  can drag this", so it was on the wrong state entirely: it now says **drag
  me** when unlocked and nothing at all when locked, which is a box you have
  deliberately pinned down and does not need to keep mentioning it.
- **Somebody going into stealth is read off the combat log**, the way Spy does
  it. It used to be read only from the auras on a unit the client was already
  drawing - a nameplate, your target - which means you had to be able to see
  them before the addon would tell you that you could not. The combat log
  announces the aura the moment it lands, two rooms away, and that is the
  warning worth having. Swinging at somebody, or the aura falling off, takes
  them back out of it: a rogue who opens on you is a rogue you can see.
- And it is matched by **spell id first**. The old table was five English
  words, so on a German or French client it matched nothing at all and the
  whole feature was quietly off. The names are now learned from the ids at
  login by asking the client what it calls them - so a German client matches
  "Schleichen" without anybody shipping a list of translations. Stealth,
  Prowl, Vanish, Shadowmeld and both invisibilities, every rank.
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
- **Raw coin is not in the loot log at all any more.** It comes off nearly
  every corpse and it is split before you ever see it, so a row per pickup
  buries the things you opened the tab for: a night in Scarlet Monastery came
  to four hundred and forty-five rows, and fifteen of them were greens. Nova
  carries it as one figure per instance - Raw Gold From Mobs - and that is the
  right shape. It belongs to the run.
  - **History** has a **gold** column now, one figure per run, and the run
    tooltip says it in words. The loot tab's total still counts it.
  - Coin picked up outside a run is not money the instance gave you - it is a
    quest reward or a vendor - and it is left out of both numbers.
  - The rows already in your log are folded into the runs they happened in by
    their timestamps, once, on the way in; anything that lands in no run is
    kept as a lump so the total stays true. It says how much it moved.
- **Uncached items now load, so the tooltip is the real one.** An item the
  client has never seen is a name and nothing else - `GetItemInfo` answers nil
  and the tooltip draws a box with no stats, no armour, no required level -
  and that is most of somebody else's loot, because it never passed through
  your bags. Asking is the whole fix: the addon now asks for every item as it
  is logged and again before the tab draws, and redraws when the answers
  arrive. Names, prices and qualities fill in with it.
- **The item's own tooltip on hover**, straight from the client - stats,
  level, binding, everything a list of names cannot say. Ours goes underneath
  rather than instead: the rest of what that corpse gave, who took it and
  where, which is the part the item tooltip does not know. Shift-click puts
  the link in whatever you are typing, the way it works everywhere else.
- **A quality column**, and it sorts. On the number rather than the word, so
  epic lands above rare instead of alphabetically between them - and because
  the search box reads whatever the rows say, typing **rare** now narrows the
  log to rares without the box needing to know anything about quality. The
  word is the client's own (`ITEM_QUALITY3_DESC`), so it is "Selten" on a
  German client without a translation table.
- The quality shown for a row is the best thing that corpse gave, which is the
  one you would have opened a tooltip for.
- **One line in chat when the instance count moves**, the way Nova does it:
  up when you zone in, back down when the mobs prove it is the one you were
  just in. A number that corrects itself in silence is a number you end up
  arguing with - saying both halves out loud is exactly what makes it possible
  to check. At most a handful an hour, and it can be turned off.
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
- **Trades are logged on Classic Era again - second attempt, and this time
  from the right end.** Requiring both accept ticks in one event was still too
  strict: when the second person accepts, the trade executes and the window is
  torn down, and that last event does not reliably arrive. Trades were still
  going unlogged.
  A cancel, on the other hand, always announces itself - it fires after the
  close when you abort and before it when the other side does - so a trade
  window that closes and never mentions a cancel is a trade that completed.
  That is the rule now, with a moment's wait to cover both orderings. The
  ticks are kept as a second opinion rather than the deciding one.
  Because that is an inference rather than a certainty, **every trade row can
  be deleted now**, not only the ones you typed. Anything inferred has to be
  correctable by the person who was actually there.
- **Runs stopped counting against what you had paid, and the reason was two
  spellings of one man.** The run log kept the client's own spelling of a
  booster's name; the trade log kept the cleaned one every typed name goes
  through. They are compared with a plain equals - so a booster called CartEr
  was two different people to the addon. His runs counted for one and his gold
  for the other, and the balance sat at "10 runs paid up" while you ran.
  One spelling everywhere now, and the log you already have is tidied on the
  way in - runs, trades, the last booster, and the booster table itself, which
  is keyed by name and so has to be re-keyed. Two halves of one man are merged
  rather than one silently winning.
  `/chain left NAME` also says how many runs are logged under that exact name,
  and names any other spelling it found. A balance that will not move is
  almost always this, and there is no way to see it from the number alone.
- **The booster's own counter is read out of chat.** Boosters run an addon
  that announces where everybody is in the pack - `[BoostBuddy] Nintoz - Run
  4/10` - and that is the number he is charging against. He knows when the
  pack started; we are inferring it from when you paid, so the two can
  honestly differ. His goes on the bar when he has one, ours stays as the
  fallback for boosters who announce nothing, and both are on the tooltip.
  Only lines naming you count, and only from the booster you are running with.
- **A trade to a stranger asks whose purse it was**, the moment it goes
  through rather than later. Paying somebody who has never run for you while
  somebody else is boosting you is a bank alt nine times in ten, and that is
  the moment you know which. Asked once per name; say no and it stays no.
- **Gold handed to a bank alt counts for the booster.** Half the money in a
  boost goes to somebody who has never run anything for you - a bank alt, a
  guild mate holding the purse - so his account looked unpaid and the alt's
  looked like a stranger who owed you twenty runs. Point the alt at him once
  (`/chain alt Banken Berreta`, or answer the question the addon asks the
  first time you pay a stranger while he is boosting you) and everything
  handed to that name counts against his runs, priced at **his** rate.
  Payments already made to that alt are repriced when you link it, since they
  had been valued at the instance's fallback price for want of anything
  better. A price you typed against the alt yourself is left alone.
- **Names can be picked instead of typed.** Half of them are Zånzå and Cartèr,
  and getting the accents right off a screenshot is not a task an addon should
  be setting you. The **pick** button on the Trade tab lists your group, the
  booster, and everybody you have traded lately.
- **Trades are logged on Classic Era again.** The addon was listening for the
  client to say "Trade complete.", which Classic Era does not reliably send,
  so a trade that plainly happened left the log empty. It now takes both
  players ticking accept and the window closing as the completion, which is
  what Classic actually gives you, and keeps the message as a second signal
  for the realms that do send it. A cancel still gets its chance to call it
  off first.
- **What the money bought, and what is left of it.** You hand over 400g for
  ten runs and then you count on your fingers. The addon knows what a run
  costs with him and how many you have had, so it does the subtraction: the
  Trade tab shows what each payment buys and the balance after it, the
  Boosters tab carries **runs left** next to the verdict, and the bar says
  *6.0 runs paid up* - in red once you have gone past what you paid for.
- The price is recorded **on the trade**, so editing a price later reprices
  what you buy next rather than rewriting what you already bought.
- The count starts at your first payment to that booster, with two hours of
  slack in front of it, so somebody you ran with before you installed this
  does not appear owing you twenty runs, and a sitting paid for at the end
  still counts.
- **A trade the addon never saw can be typed in**, on the Trade tab or from
  chat. Gold sent by mail, a trade that went through during a reload, and
  above all the arrangement you were already halfway through on the day you
  installed this - without a way in, the balance is wrong from the first day
  and stays wrong, and a number you know is wrong is a number you stop
  reading.
  - `I paid him` takes a name and an amount and prices it the way a watched
    trade would have been: `/chain paid Boostar 400`.
  - `runs left` takes the answer directly - `/chain left Boostar 7` - and is
    the one to use when you never counted the gold. It is a line drawn under
    everything above it: the tally starts again from that number.
  - Lines you typed say **by hand** in the where column and carry an x to
    remove them. Trades the addon watched have no x: that is measured
    history, and an x on it would be an invitation to make the log say
    something other than what happened.

**The five an hour**

- **The wait is announced to the group on a countdown.** A group standing at
  the summoning stone is a group waiting on the number somebody has to keep
  asking for, so it is said on a rhythm rather than whenever something happens
  to poke it: once when you hit the cap, every five minutes while the wait is
  long, once at **one minute**, and once when a slot actually opens. Each mark
  is said once - the check runs every few seconds, and a countdown that
  repeats itself is worse than one that says nothing. Every line is worded the
  same way - `free in 47m`, `free in 15m`, `free in 5m` - because a countdown
  that changes its phrasing halfway makes you read it twice to see that the
  two halves are the same sentence. Whole minutes, always, rounded up and never
  zero: seconds in a line about an hour's lockout are false precision, and
  "free in 50s" is a different unit you have to convert before you can compare
  it with the line before it.
  What gets said is the real time left rather than the name of the mark, so a
  check that catches the mark a little late still tells the truth. Still
  behind **Tell the group your lockout**, and still your chat, not ours.

- **Everything it says to the group now says who is saying it** -
  `[CHAIN] - 5/5 - 15m to go`. Four people in a party are running three addons
  between them and all of them are putting numbers into the same window; a
  line with nothing in front of it reads as somebody typing, and somebody
  typing gets asked follow-up questions. It costs seven characters and it
  means the group knows where the number came from - and who to go and get it
  from. The reset call and the stealth spot carry the same tag.

- **In a boost the line under the bar carries two things and only two:**

      9/10 runs                                        ding in ~41m

  How many runs you have left, and when you ding. That is what you are in
  there for. The bar itself goes on saying where you are and how far it is;
  this line is the two numbers you are actually counting. `his count` and
  `lvl 42 in` are gone from the wording - the bar says which level you are on
  and the top line says which stretch you are running, so the number is the
  only part that is news. Levelling says it the same way: the right-hand end
  reads `ding in ~41m` rather than `~41m to 32`.

- **The run you are in is at the top of the History tab, while you are in it.**
  It used to appear only once you had walked out, which is the one moment you
  no longer need telling about it - and when a booster says "that is five"
  mid-chain, the run you are standing in is exactly the one in dispute. It says
  **now** in the when column and counts up. It is not saved, cannot be deleted
  and cannot be marked: it counts for nothing until you finish it.

- **The History summary says what its count covers.** "6 runs" under a list
  with two payments in it reads as six since the last one, and it is not - it
  is everything on record. It says both now: **6 runs on record** and **3 since
  you last paid Magecome**, with what that leaves him owing you.

- **The bar tooltip says what is happening now, and stops.** It had grown to
  two columns and thirty-odd lines: his price, experience per gold, what a
  level costs here against what it costs at the end, the group's make-up, the
  whole ledger with him, the rank table. All of it true, all of it already on
  a tab, and none of it anything you act on while standing in a doorway. A
  tooltip you have to *read* is a tooltip you stop opening.

      Chain
      Maraudon  42 > 50                     step 2/2
      left in this step                    19.2 runs
      ding in                                  ~21m

      runs with Magecome                        1/5
      instances this hour            4/5   +1 in 44m
      this run          24m   288 mobs   31,400 xp  +12%

  Where you are, when you ding, what you have left with him, whether you can
  go back in, and the run you are in - **measured against what the place
  usually gives you**, because `31,400 xp` is only good news if you know what
  the usual is. Green a sixth above, red a sixth below, and the elapsed time
  turns amber with the overrun beside it when the run is running long. Both
  are things you can still do something about while you are in there. A reset waiting for you gets a line of
  its own, and a run that will not count says so - that one you can still do
  something about. The comparisons live on History, Boosters and Route, which
  is where you go when you are deciding rather than doing. The second column
  is gone; there is a test that fails if the tooltip ever grows past sixteen
  lines or reaches for one.
  One fact a line, one unit a fact: a tooltip is read down its right edge, and
  a right edge made of `635,624 xp  19.2 runs` against `~21m` against `1/5` is
  not an edge. The experience figure went - runs is the unit you buy and the
  unit he counts, and the experience is on the bar two inches above. The wordy
  half of a label stays on the left, where labels live. And nothing is compared
  until there is something to compare: a booster's first minute is walking to
  the first pull, and `-100%` on an empty run is a red number that means
  nothing.

- **A step can be one you do yourself.** Nobody buys every level: you buy to
  42, quest to 45 because nothing sells that stretch at a price worth paying,
  then buy again. A plan that only knows about dungeons puts you on the next
  instance for three levels you are actually soloing - with its runs, its gold
  and its summoning stone - and every figure on the bar is then about a place
  you are not going to.
  On the Route tab: pick what it is - **Questing**, **Grinding**, **Dungeons**,
  **Battlegrounds**, **Professions**, **A break** - or type
  your own words, give it a from and a to, and it is in the plan, sorted in
  among the instances by level. The boxes say what they are for while they are
  empty, the way the rest of them do; three unlabelled boxes in a row is a
  puzzle. It costs nothing, borrows no instance's
  numbers, and while you are on it the bar goes back to being a levelling bar
  with the step's name on it: **Questing  42 > 45   step 2/3**. The row says
  how long the stretch takes at your own rate and nothing else, because
  nothing else about it is true. The x takes it back out, after asking.

- **Boosters, Sellers and Reported are one tab now: Boosting.** Eleven
  headings across the top was a wall of words to read before you could start,
  and those three are the same subject from three angles - who sells the step
  you are on, who is advertising right now, and what other people's addons have
  said. They are sub-tabs inside it, **Reported** renamed **Shared** because
  that is what it is. The heading stays lit while you are in any of them and
  opens on whichever you were last in. The slash commands are unchanged.

- **The x asks first.** It sits at the end of every row and it throws things
  away - a run out of the averages, a trade out of the reckoning, somebody off
  the Boosters list - and there is nothing to undo it with. It now puts the
  question up in the game's own dialog, and the question names the thing:
  *Remove this trade? 2h 39m ago  paid 10 runs. What it bought stops counting
  with it.* "Are you sure?" is not a question you can answer without being
  told what you are being asked about.

- **A trade row shows its working.** `you bought 3, that leaves 5` reads as
  bad arithmetic until you are told about the two that were left over from the
  pack before, so it says: **3.0 bought + 2.0 he still owed you = 5.0**, and
  underneath, how many runs were recorded between this payment and the one
  before it. That second figure is the one worth checking - the sum is only as
  right as the run log, and a run that never got logged is exactly how this
  goes wrong.

- **Tooltips were losing every line after an absent one.** The tables are
  written as `{ a, b, c or nil, d }` - put this line in only when there is one
  - and `ipairs` stops dead at the first `nil`. A trade with no zone recorded
  lost its arithmetic and its balance; a run with no coin lost the group line.
  Eleven of them, all silently truncated, for as long as they have existed.

- **`4h`, not `4h 0m`.** A zero that only ever means "nothing here" is one more
  thing to read past, and it turned up in every line that quoted a round number
  of hours.

- **Only the leader can call a reset, so only the leader is believed.** One
  person typing "reset" in raid chat set the alarm off for the whole group.
  Only the group leader can actually reset an instance - everybody else typing
  the word is asking for one, complaining about one, or repeating what the
  leader just said - so the sender is checked against the group now, and a
  question mark rules the line out either way. The game's own *The Stockade has
  been reset* is unaffected: that one is the client telling you, and it needs
  nobody to vouch for it.

- **The runs are counted the way the pack is sold: `7/10`.** That is how both
  of you are thinking about it - it says how far through you are and how much
  is left in the same breath, where `3 runs left` is a number you have to hold
  against something else to make sense of. The total is **what the last
  payment bought**, not the balance: pay for five with two still owed from
  before and the balance is seven, but nobody counts in sevens. He says "run 1
  of 5" because five is what you just bought, and the two from before are a
  separate conversation - which is what `to come` and the Trade tab are for.
  **And the last one is said out loud**: `9/10 - last run`. It is the one that
  decides whether you pay again before the next pull or walk out after it. His
  own announced count gets the same treatment.

- **The Trade tab starts out pointed at whoever is boosting you**, rather than
  at nobody. An empty name field meant typing a number, pressing the button and
  being told "no name"; it is filled in with the current booster now. Beside
  the box it says what the figure is **right now** - `now 3.0` - because the
  `to come` figures in the rows above are each frozen at their own payment, and
  the two being different is the whole reason you are looking.

- **"runs left" is a box you can type in.** The figure is inferred - what you
  paid, divided by his price, less the runs recorded since - and every one of
  those can be wrong: a trade the client never announced, a run that never got
  logged, a wipe he gave you back. When it is wrong you are the one who knows,
  and arguing with you about it would be the wrong way round. Type the number
  on the Boosters tab and the reckoning starts again from it. A box that only
  loses focus changes nothing; it has to be typed in.

- **Everything you can click says what it does.** Every button, every tab and
  every column heading carries a line explaining it, on hover. A row of
  one-letter buttons is a row of guesses otherwise, and one of them deletes
  things. There is a test that nothing clickable is left without one.

- **The credit lines are written in English now.** "4.0 runs still owed you
  after this one" is not a sentence anybody says. A trade row now reads
  **left him owing you 4.0 runs**, or **left you 2.5 runs ahead of what you
  had paid for** when it went the other way; the bar tooltip says **he owes
  you** and **you owe him** rather than "still owed you"; the Trade tab's
  summary says **they owe you: Magecome 4.0 runs**; and a trade the addon
  watched says **he handed back 1g 20s** rather than "he gave".

- **Every column heading explains itself.** A heading has room for two words,
  and two words cannot say what **after** or **he gave** mean - hover one and
  it says, where you are already looking when you wonder. Two of them were
  beyond saving and are renamed: **after** is now **to come** (how many runs
  you still had coming the moment that payment was logged, frozen at that
  second), and **you gave** / **he gave** are **your items** / **his items**,
  since they were never about gold at all - they are what was in the trade
  window besides the money.

- **The payments sit in the History list, among the runs.** "When did I pay
  him, and what have I had since" is one question, and it was two tabs: the
  times were in the Trade tab, the runs were here, and you were left holding a
  clock in your head. On one list, in one order, the answer is the rows between
  the money and the top. A payment row says **paid** with the runs it bought,
  the sum in the gold column and his name in the booster column, and the x
  strikes it from there the same as from the Trade tab.

- **And the count can be settled in one line of party chat.** He says five, you
  counted four, and neither of you can prove it, because both of you are
  counting in your head - him across three customers at once. The addon is not
  counting in its head. Every History row has a **+** to mark it,
  **mark since last trade** marks the ones the argument is actually about (his
  alts included, since the gold often goes to a bank character), and **say in
  party** puts it in chat:

      [CHAIN] - 1/5 with Magecome - 19:52-20:15, 23m, 300 mobs, 33,000 xp, 31% of a level
      [CHAIN] - 2/5 with Magecome - 20:37-21:00, 23m, 300 mobs, 33,000 xp, 31% of a level
      [CHAIN] - 3/5 with Magecome - 20:59-21:22, 23m, 300 mobs, 33,000 xp, 31% of a level

  One line a run, numbered the way he counts them. A single line of times is a
  list somebody has to match against their own memory; a line each - when it
  started, when it ended, how long it took, how many things died, what it paid
  - is a receipt, and there is nothing left to disagree about. The experience
  is given as a share of a level too: a number of xp means nothing without
  knowing what a level costs at that level, and 33,000 at 43 against 33,000 at
  20 is the whole argument about whether the run was worth the gold. Eight at most,
  then "(+4 older, not listed)", and they go out half a second apart, because
  the game throttles a run of messages hard enough to disconnect you. The marks
  are not saved: it is something you do for ten seconds to settle an argument,
  and a mark surviving a logout would only ever be a surprise.
  **Or to one person**: a name box and a **whisper** button send the same
  lines to him alone. A booster who has left the group is out of reach of
  party chat entirely, and correcting somebody in front of four other people
  is a different thing from correcting him. The box starts out filled in with
  whoever the marked runs were with, accents and all.

- **The Windows tray program opened and shut without a word.** `pythonw.exe`
  runs with no console - which is the point, since nobody wants a black window
  behind the game - and with no console Python sets `sys.stdout` and
  `sys.stderr` to `None` rather than to somewhere harmless. The first `print()`
  anywhere in the watcher then raises `AttributeError: 'NoneType' object has no
  attribute 'write'`, and there is nowhere for *that* to appear either. So the
  streams are given somewhere to go before anything else runs, and anything
  that still goes wrong gets a message box and a `crash.log` under
  `%LOCALAPPDATA%\ChainPush`. `ChainPush.bat debug` runs it in the command
  window with everything on screen. A background program is allowed to be
  quiet; it is not allowed to vanish.

- **The Adverts tab is the Sellers tab, and it only lists people who are
  actually selling.** "Adverts" named the mechanism; what you want off that tab
  is a person to whisper. And an advert is somebody standing in a city saying
  they are free *now* - half an hour later they are three levels into somebody
  else's chain, and a list of them is a list of people to be disappointed by.
  So anything older than thirty minutes drops off. What was learned from the
  advert - his price, his pack size - stays on his record: that is knowledge
  about him, and it does not go stale the way the offer does. `/chain sellers`
  opens it; `/chain adverts` still works.

- **A whole pack past what is logged as paid says so, once.** One run past is
  normal - you take one on credit and settle at the end of the pack. Ten past
  is not: it means money changed hands and the addon never saw it, which is
  what a trade to a bank alt looks like, and what a trade the client never
  announced looks like. Rather than letting the number drift until the bar
  claims you owe seven runs, it says which booster and what to type:
  `/chain paid Cartèr 400`. Once per payment - settle up, or tell it what you
  paid, and it goes quiet. The bar tooltip says the same thing under the
  balance.

- **The booster's own run counter is carried forward instead of frozen where
  he left it.** He announces once a run, and a booster who stops announcing -
  his addon off, his attention elsewhere, the pack finished - leaves us holding
  a number that was right twenty minutes and three runs ago. `9/10 runs` sat on
  the bar for two hours after the pack was over, because that was the last
  thing he ever said. Every run we have seen with him since he said it now
  counts one off the pack, and when that reaches the end of the pack there is
  nothing of his left to believe: our own arithmetic takes over, and that one
  knows you have gone seven runs past what you paid for. A payment newer than
  the announcement ends it too - that is a new pack, and his old number was
  about the last one.

- **The rate stands between the two corners under the bar, in both modes.**

      Lvl 31  47.9%      35,800 / 74,800        ding in ~41m
      39,000 to go         56,348 xp/h

  It belongs on the line it is measured alongside: how much is left on one
  side, how fast it is coming in in the middle, when it runs out on the other.
  In a boost that reads `9/10 runs  ·  56,348 xp/h  ·  ding in ~36m`. That
  makes three slots below the bar rather than two, and the middle one is
  dropped rather than allowed to overlap when the two ends leave it no room -
  the same rule the middle of the bar has always had. Without a measurement
  yet it says so: `measuring xp/h`, or `no xp for 12m` if you have been
  standing still.

- **And it is coloured against what the thing you are doing normally gives
  you.** A rate on its own says nothing: 56,000 xp/h is good in Scarlet
  Monastery and terrible in Stratholme, and neither of those is something you
  should have to hold in your head. In a boost it is measured against the
  step's own record - experience a run over minutes a run, which is what this
  dungeon with this booster has actually been paying - so falling short of it
  means this run is going badly: a slow booster, a wipe, or twenty minutes at
  the stone. On your own it is measured against your own session, once that is
  twenty minutes old, which answers the only question you can act on alone: am
  I going slower than I have been. Green at or near it, yellow a fifth below,
  red past that. With nothing to measure against there is no colour - a green
  number nobody has checked is worse than a white one.

- **On your own, five quiet minutes stops the clock.** The rate allowed ten
  before it gave up, which is right in a group, where a gap that long is a
  reset, a summon or waiting on somebody. Alone it is you not being there, and
  a rate still counting while you are at the mailbox is a rate that says you
  ding in five minutes.
  Experience a run, minutes a run, what it costs, what you have paid and how
  many packs that is have all moved to the tooltip, where there is room to say
  what they mean and where they are not sitting on top of the two numbers you
  actually came for.

- **And the corners are measured against the bar rather than the padded line
  budget** - which is what was wrong from the start. The packed lines are
  centred under the bar and may run past both ends of it, and that slack was
  being handed to the two corners as well; but they are pinned to the two ends,
  so anything past the bar's own width is one drawn on top of the other.

- **The bar works out how much fits on a line instead of remembering it.** The
  summary under the bar is packed to a budget in characters, because the text
  is built long before there is a frame to measure it in - and seventy-four was
  measured once, in the face the addon used at the time. Ship a different face
  and the same seventy-four characters draw straight over each other, which is
  exactly what happened: `11,704 xp/run` on top of `5m/run` on top of
  `(5 - 43m left)`. The number is now measured rather than remembered - a
  sample of the kind of thing that goes down there, drawn in the real font,
  gives the width of an average character - so it follows whichever face you
  pick, and the bar re-packs itself the moment you change it.

- **The whole addon is written in a face that was chosen for this.** Friz
  Quadrata is the game's own, and it is a display face - made for carved signs
  and quest titles, not for a column of numbers at nine pixels, where its
  serifs turn to mush. This addon is almost entirely small text in rows, so it
  now comes with one: **DejaVu Sans**, which is even, sturdy and made to be
  read small, and covers every accent a character name can carry. The client's
  own four are all compromises here - Friz Quadrata is a display face, Arial
  Narrow is narrow, and thin strokes on a dark background are the first thing
  to go at nine pixels; Morpheus and Skurri are for titles and damage numbers -
  so all four are offered and none of them is the default. The licence DejaVu
  comes under lets it be shipped like this, and sits next to it in `Fonts/`.
  Change it in **Bar & sharing** or with `/chain font`.
  Behind it are five font objects of ours. A font object is shared by every
  string using it, so a swap changes every label in the addon at once, on the
  spot with no reload, and leaves the rest of the interface alone. Each one
  keeps the size of the game object it was built from, so changing the face
  does not quietly resize half the addon.

- **The settings tabs say what is in them.** *What to read out of chat*, *Who
  is out there* and *Sharing and the bar* were sentences where a label was
  wanted. They are **Chat**, **Enemies** and **Bar & sharing**.

- **The list's resize handle is not drawn when the list is locked.** A handle
  you cannot pull is a smudge in the corner of a box you have deliberately
  pinned down - and with nobody about the box is one line tall, which put that
  smudge right next to the new button.

- **Empty, the list says what it is rather than what it has not got.** It used
  to read **nobody about**, which is an answer to a question nobody asked and
  makes the box sound like it is announcing that it has nothing to do. It now
  says **Enemy tracker**, and the count takes the line back the moment there is
  one.
- **And there is a way in to the rest of it**: a small **E** in the header opens
  the Enemies tab. The list is a corner of that tab - everything you want after
  seeing a name is there - and until now the only way in was a slash command you
  had to remember.

- **A click anywhere else closes the menu.** Every other menu in the game puts
  itself away when you click past it, so one that does not reads as stuck: you
  click, nothing happens, and you go looking for the way out. A full-screen
  frame one strata below the menu catches it - the menu sits on top, so its own
  items still get their clicks - and it exists only while the menu is open. All
  six menus share the one frame, so this is the meter, the nearby list, the
  alert, the player menu and both of the gold ones at once.
  That frame depends on the click landing on us rather than on somebody else's
  full-screen frame, and there is no way to be sure of that - so there are two
  more ways out that do not depend on anything. **The menu gives up five
  seconds after the pointer leaves it**, because a menu you have walked away
  from is one you are done with; and **asking for it again on the same thing
  puts it away**, since that is somebody closing it rather than opening it
  twice.

- **The list and the alert could not actually be clicked**, and the reason was
  one line in each of them. A secure button registered for `LeftButtonUp` and
  `RightButtonUp` - the obvious registration, and the one every example uses -
  does not run its action at all on this client. Spy carries that exact line in
  its source with a comment character in front of it and `AnyDown, AnyUp`
  underneath, which is how we found out. Both buttons are registered for down
  and up now, so half the clicks arrive as the press: the targeting itself is
  happy to run twice, and everything that is not targeting - the shift-mark,
  the right-click menu - ignores the press.
- **A row also points itself at the moment you click it**, rather than trusting
  the last refresh to have done it. The list reorders as people are seen, and a
  row that moved half a second ago should not cost you the target.
- **Rows target with `/targetexact` rather than `/target`.** The banner always
  did. `/target` matches on a prefix, so a click on "Ara" takes whoever is
  nearest whose name begins that way, which in a list of enemies is the wrong
  man often enough to matter.

- **The countdown is not said from inside the instance.** Going in is what
  puts you on the cap, so that was exactly when it fired - in at 4/5, then
  `5/5 - free in 11m` fifteen seconds later, to four people who had just
  watched you walk through the door. It waits until you are back outside,
  which is the moment somebody would have asked anyway, and picks up from
  wherever the clock has got to.
  The one line that is still said from inside is the one the group is actually
  waiting on: **`[CHAIN] - 4/5 - instance unlocked`**, and the countdown says
  the same word: `5/5 - instance free in 15m`.
  Solo, there is nobody to tell - so the same line goes to your own chat frame
  instead of nowhere, and what you see alone is what the group sees when you
  are not.

- **The instance counter was reading the wrong half of the creature id, and
  undercounting badly.** A creature comes back as
  `Creature-0-4672-33-573-3849-...`; we took field four as the instance, but
  33 is Shadowfang Keep's map - the same number in every copy of it that has
  ever existed. So the second Stockade of the day looked like walking back
  into the first: marked a re-entry, dropped from the log, never counted. A
  full Scarlet Monastery chain of three read as **one**.
- It now takes fields four and five together. Which of the two is the map and
  which is this copy of it is documented one way round and used the other way
  round by every addon that actually counts instances, so the pair is the only
  answer that is right either way.
- Scarlet Monastery is the case that makes this matter: a boost there is
  several instances in a row behind one zone name, and until one is reset
  walking back into it is not a new one. Same pair, same instance - and now
  three wings count three.
- **The entries that bug threw away are put back from the run log**, once, on
  the way in. A recorded run is proof you were inside; an entry is only a note
  made on the way in, and a log reading 2/5 with nine runs behind it in the
  same hour is not arithmetic. Runs already known to be re-entries are left
  alone - they did not count then and they do not count now.
- **Being refused now writes entries, not a correction.** "You have entered
  too many instances recently" means the game has seen instances we have not,
  and those are written into the log as entries of their own, stamped at the
  refusal. They then count, expire and drive both clocks like any other entry.
  - As a number added on top it was wrong twice over. It was a snapshot, so
    once our own counting caught up it was still being added - which is how
    the bar reached **7/5**, a number the game will not give you.
  - And it moved the "oldest" entry forward to the moment of the refusal,
    which could put it after the newest, which is how **"one free in 58m"**
    ended up above a line saying they were all free in 47m.
- **A run in progress is never split by mob ids.** A run starts when the zone
  name changes, and in Scarlet Monastery it does not - all four wings report
  "Scarlet Monastery" - so the obvious move is to watch the mob ids and start
  a new run when one stops matching. That was tried, and the bar went to
  **6/5**: a number the game will not give you, so whatever it counted was not
  an instance. Nova does not do it either - it uses the mob id only to decide
  whether a run that has just *started* is the previous one carrying on, never
  to end one that is in progress. The id is written once, at the start, and
  the run keeps it.
- **A corpse in your target frame no longer files a fresh instance as a
  return to the old one** - which was the real reason the count ran short, and
  is fixed where it happens rather than by counting harder somewhere else. The run read its instance id off whatever you had
  targeted when it started, and walking out and back in with the dead mob
  still selected meant the new run was stamped a re-entry and its entry
  thrown away. A dead target gets no say, and a run split off another one is
  told which instance it is in rather than asked.
- **"+1 in 9m" next to 3/5 was a wait that did not exist.** Under the cap the
  bar and the minimap now say how many you have left - **3 to go** - and the
  clock only appears when the door is actually shut.
- **A `/reload` was counting as an instance entry, and that was the whole
  story.** On a reload the addon threw away the run in progress and let the
  next zone check start another - and starting a run writes an entry against
  the five-an-hour cap. So every reload while standing inside a dungeon
  counted as walking into a new one. A day of reloading to pick up changes put
  the count several ahead of the truth, which is every off-by-one in this
  list. Nova prints "UI Reload detected, loading last instance data instead of
  creating new" for exactly this reason.
  Come back to the same place and the run you had is the run you are in; only
  somewhere else ends it. The client can also announce the world before it
  admits to being in an instance, so a second guard covers the case where the
  run went missing during the loading screen.
  That second guard was too wide on its first outing and ate a real entry: it
  asked whether the last zone matched, which is still true half a minute after
  you have walked out of the place - so a reload in town followed by walking
  straight in had its entry thrown away, and the count sat one short for the
  rest of the hour. It now asks whether a run was actually in progress in that
  instance when the lights went out, which is the only case it was ever for,
  and the window is fifteen seconds rather than thirty.
- **The same arrival is not counted twice - and the reset log is what settles
  it.** This one came out of the log rather than out of my head: the Instances
  tab showed two "entered SM" a minute apart, nothing between them, and the
  hour reading 7/5. One arrival, reported twice.
  A second entry into the same instance is only a second instance if somebody
  reset it in between - that is the whole mechanic - so two entries with no
  reset recorded between them cannot both be real. Two that *do* have a reset
  between them are kept however close together they are, because a fast chain
  looks exactly like that. The clock is only a guard against acting on a gap
  so wide that a missed reset is the likelier explanation.
  It runs on the tick and after a NIT import, so a log that is already wrong
  is cleaned up rather than only prevented from getting worse.
- **A count that cannot be true is trimmed on the clock**, not only when you
  next zone in - which is the one moment that will never arrive, because the
  bar is telling you the door is shut. Guesses go first, and it says what it
  dropped.
- **And the same escape hatch Nova has.** `/chain notnew` takes back the last
  instance it counted, for when a zone-in was not one. A zone-in is the only
  evidence there is at that moment, and it can be wrong.
- Every line that moves the count now carries the **instance id**, and the
  Instances tab says where each row came from - own, rebuilt, the game said,
  from NIT. A wrong number you can trace is a bug; a wrong number you cannot
  is an argument.
- **Getting through the door removes them again.** If the game lets you in you
  were not at the limit, whatever we thought: a refusal is evidence in one
  direction and an entry is the same evidence in the other, and only using
  half of it is what let a guess sit in the count for a full hour.
  Guesses only, and in order: first what the game told us about and we never
  saw, then what we rebuilt from the run log. An entry we actually watched
  happen is never thrown away to make a number look right.

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

**The other side of the counter**

- **A My boost tab**, under Boosting. Everything else in Chain is written for
  the man paying; this is the same argument from the other chair, and it ends
  the same way - with a count both of you watched go up.
- Somebody in your group trades you gold and he lands on the list on his own,
  with what that gold came to in runs **at the price you were charging when he
  paid**. Change your price afterwards and what he bought does not move.
- Your price is per instance, because Maraudon and the Stockades are not the
  same job. An instance you have not priced starts from the last figure you
  typed rather than from zero.
- Each time a run finishes, everybody on the list **who is still in your
  group** has had one, and one line goes into party or raid: `Ola 2/5   Kari
  4/5`. One line and not one each - four names after every run is twenty lines
  an hour in somebody else's chat window. When a man's pack runs out the line
  says so.
- The count is editable, the same way the buyer's is. Type what he has left
  and what he bought moves to match; a wipe you gave him back is not something
  the addon can see.
- **Your advert, kept per instance**, with a button that posts it to
  LookingForGroup. One press, one line. Nothing here posts on its own, nothing
  repeats, and the button will not be pressed twice inside half a minute - an
  addon that talks in a channel by itself is what gets everybody's addon
  thrown out of it.

**Numbers you can follow**

- **"1.0 owed" said the opposite of what it meant.** It is a run you have had
  and not paid for; it was read as one you have coming, which is the flattering
  direction and the wrong one. The word has only ever had two directions in it,
  so it is gone: `1.0 unpaid` on the bar's tooltip, `1 run unpaid` under the
  bar. What you have coming still says `to come`.
- The bar tooltip also names a hand-set balance when one is in force. A figure
  that cannot be checked against anything else on screen has to say where it
  came from; it costs a line only in the rare case where it is true.

- **A balance you set by hand now has a row.** Typing over "runs left" throws
  away every payment before it and starts the count again from your number -
  the single biggest thing that can happen to the reckoning - and it was
  invisible. The result was a figure nobody could derive from the rows above
  it and nobody could take back. It sits in History now as `set to 1 run`,
  with an x that puts every earlier payment back into the sum.
- **History's footer said "since you last paid" about a number that was not
  that.** It was runs since the reckoning started, which is the same thing
  only when you have never set a balance by hand. The footer now says the two
  figures apart: `5/5 in this pack` - the same count, worked the same way, as
  the one under the bar - and `2.0 to come in all`, which is the balance with
  every earlier pack's leftovers in it. When the balance is counted from a
  number you typed, it says so in amber.

**Smaller things**

- **The phone-notification folder is four folders now, not eighteen files in a
  heap.** `mac/` and `windows/` hold the two or three files that machine
  actually uses and one short page each; `engine/` is the code both of them
  run and `icons/` the pictures, sitting beside them rather than copied into
  both. The page at the top no longer explains two platforms at once - it
  points at the folder for your computer, and that folder says what to
  double-click.
- **The tracker's tooltip was a page of history over a man standing behind
  you.** Last seen, seen how often, first met, where, what spotted him - all
  of that is on the Enemies tab in sortable columns, which is where you read
  it afterwards. The tooltip answers the two questions you have while he is
  there: who he is, and whether you have beaten him before. The faction line
  went too; the race above it already says which side he is on.
- **A forecast for an instance you have never been in.** `Maraudon > 52
  boost ~87 runs ~12h 15m est` on a character that had never set foot in
  Maraudon: the figure was borrowed from somewhere else and dressed in the
  word "est", and it read as knowledge. Dire Maul is the clearest case - three
  instances behind one name, so a run through North gave West a whole number
  to boast with. The forecast waits for the first run through that door now.
  Until then the line says where you are heading and stops, which is all
  anybody can honestly say.
- **"measuring xp/h" was a claim, not a measurement.** It said work was going
  on when the truth was that nothing had happened yet. Two minutes after
  logging in there is no rate because there is no experience, and the honest
  way to say that is to leave the space empty. "no xp for 12m" stays - that
  one *is* a measurement, and it is the one you want.
- **An advert was filed under the instance it was rubbishing.** "WTS Dire
  Maul West+North, better than Strat/ZG/BRD and incompetent mafia boosters"
  went into the list as Blackrock Depths - for no better reason than that BRD
  sits above Dire Maul in our own table. The earliest name in the text wins
  now: an advert leads with what it is selling, and everything after that is
  context. On a tie the longer name wins, so "Dire Maul East" beats the bare
  "Dire Maul" that starts at the same letter.
- **Dire Maul needed the wing spelled out and Stratholme needed spelling
  wrong.** Three instances behind one name, written every way people write it
  - `DM West`, `dm w`, `Dire Maul North` - and `Stratholm` without the e,
  which in a trade channel is as common as the real thing.
- **An advert we cannot name is still a man selling boosts**, and it was being
  thrown away outright. The ones that went are exactly the ones worth having:
  a spelling nobody else uses, a wing we have no word for, an offer with no
  instance in it at all. He goes on the list with a dash where the instance
  would be - what he actually wrote is in the row, and the whisper button
  works the same.
- **"0.0 runs left" is not a thing worth writing in the corner of the
  screen.** Square with him - everything settled, nothing bought yet, or a
  balance you have just typed to zero - is a state you sit in for hours, and
  it was a number asking to be read and then found to say nothing. The corner
  goes back to being empty, and so does the tooltip line. What still shows in
  that case is the one line that explains it: that the figure is counted from
  a number you set by hand, so you know which row to take back out.
- **The level column filled in with question marks and stayed that way.** A
  level is only ever learned from a nameplate or from having somebody
  targeted, and a rogue who opens on you out of stealth and vanishes gives
  neither - so a man you had fought fifteen times sat there as `??` for ever.
  Chain now reads what he *cast*: an ability cannot be used before it can be
  learned, so every spell puts a floor under him. Two sorts of entry, both
  worth being sure of - every class's 31-point talents, which need thirty-one
  points and therefore level forty, and a short list of baseline abilities
  whose first rank is high enough to say something. Matched on the name rather
  than the spell id, because ids are per rank and a wrong one would quietly
  claim a level twelve is forty. The figure shows as `40+` and is a floor that
  only ever rises; actually seeing him still settles it outright. Where Spy is
  installed its own per-rank table is better and is used first - this is what
  fills the column in for everybody else.
- **The card offered to whisper an enemy.** You cannot whisper across
  factions in this game - it is not disabled, it does not exist - so that was
  a button that could never work. The hint and the double-click are gone on
  the enemy tabs, and gone for anybody the tracker has seen at all, since the
  tracker only ever records the other side.
- **The names in the tracker had a dark bar down either side and were cut
  short.** The row was twelve pixels narrower than the box it sits in, so the
  class stripe stopped short of both edges; and the right-hand column reserved
  room for "45 Warlock" whether or not it was showing "?? Rogue". The stripe
  reaches the edges now, and the name takes every pixel the right-hand side is
  not actually using - measured, rather than assumed.
- **Your own reset is announced to the group, and it is on.** Nobody else is
  told an instance has been reset: the client says it to whoever pressed the
  button and to no one else, so four people stand at the stone waiting for
  somebody to type it. When you are the leader Chain types it, with the half
  that is actually news - anyone still inside can zone out and back in rather
  than being locked out. Somebody else's reset stays off by default, because
  his addon has almost certainly said it already. `/chain myreset`.

- **The frames and latency readout sits on the enemy tracker.** Two boxes of
  numbers you skim, stacked into one thing to look at rather than two corners
  to hunt in - and with no box of its own up there, since two dark panels with
  a seam between them read as two things. It rides the tracker's header, so it
  is above the list when the list grows down and below it when it grows up.
  Drag it and it comes off: pulling it away is the gesture, and being made to
  find a menu item first, to do the thing you are plainly already doing, is a
  step that exists only because it was easier to write. The right-click menu
  puts it back.

- **The run you are standing in is counted.** The pack line under the bar read
  `1/5` while you were halfway through the second run, because it counted what
  was finished. Nobody counts that way: the booster says "second run" when he
  is in it. It counts the live run now, so it is `0/5` the moment you pay,
  `1/5` from the first pull, and `5/5` while you are in the last one - which
  still says *last run* in amber rather than going red as though the pack were
  spent.
- **Any line can be marked, and double-clicked.** Sixteen rows of numbers look
  alike while you are counting your way down them, so a click colours the line
  you are on. On History it is the same mark that *say in party* reads, so
  ticking a run and arguing about it are one gesture. A double-click anywhere
  on a line opens a whisper to whoever it is about - the poster, the booster,
  the man you traded.
- **Hovering a name says who he is**, and says the same thing in every list.
  The tracker knows his level, class and guild; the run log knows how many
  runs he has done for you and at what rate; the ledger knows what he still
  owes you. A name in a column was none of that.
- **Groups: the level column is the one the game enforces.** It said what the
  poster asked for, which is his opinion. It now says the level the instance
  lets you in at, green once you are there, so a post you cannot use is
  obvious at a glance. What he asked for is still on the row's tooltip.
- **The bar's tooltip is two columns now.** It had grown to a page: on a tall
  screen it ran from the top of the display to the bottom, which is not a
  tooltip any more. A second one sits alongside the first and the split is by
  subject rather than by line count - the step, what a run costs and your
  account with him on the left; who he is, how he compares, where you stand on
  the hour and the honour week on the right. **Bar tooltip in one column** in
  the settings puts it back for a narrow screen, where the height was the
  lesser problem.
  The two are the same width and the pair sits under the middle of the bar.
  That takes two passes - a tooltip is only as wide as what is in it, so
  neither width is known until both have been drawn once - and the width
  forced on GameTooltip is taken off again when it hides, because that frame
  belongs to the whole game and every item tooltip would have inherited it.
  Which column a block goes in is a judgement about the block: the run you are
  in sits with what you are doing, not with who you are doing it with, which
  also evens the two halves out.
- **The Trade tab's balance column was frozen, and reading like it was not.**
  It is the balance that payment left you on, at the moment it was made -
  which is what a ledger column is for, and why it does not move afterwards.
  But it was labelled **left** under a title saying "what is still owed you",
  so it read as a live figure that had got stuck. It is called **after** now,
  and the number that does move has a place of its own: the line under the
  table carries the live balance for whoever you have paid lately, his own
  count where he announces one.
- **Tab titles were running under the search box.** Same failure as the bar
  corners: a fontstring that does not fit does not clip, it draws into its
  neighbour - which is how the Trade tab read "…what is still oweshow only".
  The long ones are shortened, and the suite now measures every title against
  the space it actually has.
- **The two lines under the bar stopped colliding.** They are not one
  fontstring: one is pinned to the left end of the bar and one to the right,
  with nothing between them but the bar's width - so text that does not fit
  there does not wrap, it draws straight over the other corner. That is how
  "8,881 xp/run" ended up printed on top of "7m left" on top of the booster's
  name. The pair is measured together now and whatever does not fit drops to
  the packed lines underneath, which do wrap.
  The line-length test had been checking each line on its own, so two corners
  that were each short enough went straight past it. It measures the pair now.

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
