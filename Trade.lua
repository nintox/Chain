-- Chain: what the levelling actually cost.
--
-- The price you type into the options is what the booster advertises. This is
-- what left your bags. They are rarely the same number - tips, a run thrown in
-- free, a pack you paid for and only half used - so both are worth keeping.
--
-- Money and items are read out of the trade window while it is open, because
-- once the trade completes the window is already torn down. The completion
-- message is what tells us it went through; a cancelled trade leaves nothing
-- behind.
--
-- Items matter as much as the gold. Half of what changes hands in a boost is
-- not coin - a stack of runecloth, the greens off the run, a bag thrown in -
-- and a log that only counts money says you paid less than you did.

local ADDON, BT = ...
local C = BT.COL

local pending = nil
-- Both sides ticked the box. In Classic this, and not a message, is what says
-- the trade went through: ERR_TRADE_COMPLETE does not reliably arrive there,
-- which is why the log stayed empty after a trade that plainly happened.
local accepted = false
-- and whether anybody called it off. A cancel always announces itself, so its
-- absence is what tells a completed trade from an abandoned one.
local cancelled = false

local function Copper(v) return math.floor(tonumber(v) or 0) end

-- Snapshot the trade as it currently stands. Called on every change, so
-- whatever was on the table at the moment it completed is what gets logged.
-- The six tradeable slots. The seventh is the "will not be traded" one, which
-- is exactly what it says and has no business in a record of what changed
-- hands.
local TRADE_SLOTS = 6

local function Items(get)
  if not get then return nil end
  local out
  for i = 1, TRADE_SLOTS do
    local name, _, count = get(i)
    if name then
      out = out or {}
      table.insert(out, { name = name, count = (count and count > 1) and count or nil })
    end
  end
  return out
end

-- Who is on the other side. "NPC" is the trade partner's unit token, but it
-- is empty often enough - a trade opened from the chat menu rather than from
-- the target - that the window's own label is worth asking as well.
local function Partner()
  local who = UnitName and UnitName("NPC") or nil
  if who and who ~= "" then return who end
  local fs = _G.TradeFrameRecipientNameText
  who = fs and fs.GetText and fs:GetText() or nil
  if who and who ~= "" then return who end
  who = UnitName and UnitName("target") or nil
  if who and who ~= "" then return who end
  return nil
end

function BT.TradeSnapshot()
  if not (GetPlayerTradeMoney and GetTargetTradeMoney) then return end
  local who = Partner()
  pending = {
    with = who and BT.ShortName(who) or nil,
    gave = Copper(GetPlayerTradeMoney()),
    got = Copper(GetTargetTradeMoney()),
    gaveItems = Items(GetTradePlayerItemInfo),
    gotItems = Items(GetTradeTargetItemInfo)
  }
end

-- "2x Runecloth, Green Hills of Stranglethorn", for a column and a tooltip
function BT.ItemsText(list)
  if not list or #list == 0 then return nil end
  local bits = {}
  for _, it in ipairs(list) do
    table.insert(bits, (it.count and (it.count .. "x ") or "") .. it.name)
  end
  return table.concat(bits, ", ")
end

function BT.TradeClear() pending, accepted, cancelled = nil, false, false end

-- Log the trade that just went through. Attributed to the step you are on,
-- and to a booster when the person you traded is one.
function BT.TradeComplete()
  local t = pending
  pending, accepted, cancelled = nil, false, false
  if not t then return end
  -- a trade with nothing in it either way is not a trade
  local anyItems = (t.gaveItems and #t.gaveItems > 0)
    or (t.gotItems and #t.gotItems > 0)
  if t.gave <= 0 and t.got <= 0 and not anyItems then return end

  local _, step = BT.Stage()
  local by = BT.CurrentBooster()

  -- Where it happened, the way Nova Instance Tracker words it: you pay the
  -- booster at the summoning stone as often as inside, and "in Stormwind
  -- City" is what tells the two apart when you read the log back.
  local inZone, inMap = BT.InDungeon()
  local zone = inZone
    or (GetRealZoneText and GetRealZoneText())
    or (GetZoneText and GetZoneText()) or nil
  local list = inZone and BT.DungeonsFor(inMap, inZone) or nil
  local inside = list and list[1] or nil
  local id = (inside and inside.id) or (step and step.id) or nil

  -- What a run cost him at this moment, so the ledger below can say what the
  -- money bought. Worked out now and kept, because prices change and a ledger
  -- that re-prices its own history every time you edit a number in the
  -- options is not a ledger.
  local perRun = BT.PricePerRun and BT.PricePerRun({ id = id }, t.with) or 0

  local rec = {
    at = time(),
    with = t.with,
    gave = t.gave,
    got = t.got,
    gaveItems = t.gaveItems,
    gotItems = t.gotItems,
    zone = zone,
    -- the instance you were standing in wins over the step you are working
    -- on: money handed over in a city belongs to the step, money handed over
    -- inside belongs to the place you were in
    id = id,
    -- only claim it was the booster when the names actually match
    by = (by and t.with == by) and by or nil,
    perRun = (perRun > 0) and perRun or nil,
    lvl = UnitLevel("player"),
    char = UnitName("player")
  }
  table.insert(ChainDB.trades, rec)
  while #ChainDB.trades > BT.K.MAX_TRADES do
    table.remove(ChainDB.trades, 1)
  end
  BT.TouchTrades()
  if BT.Refresh then BT.Refresh() end
  if BT.RenderWindow then BT.RenderWindow() end
  -- Money coming the other way, from somebody in your group, is somebody
  -- buying runs off you. Same trade window, opposite chair.
  if (t.got or 0) > (t.gave or 0) and t.with and BT.CustomerPaid then
    local here = BT.GroupNames and BT.GroupNames() or {}
    if here[BT.ShortName(t.with)] then
      BT.CustomerPaid(t.with, (t.got or 0) - (t.gave or 0), id)
    end
  end
  -- and if that was a stranger while somebody is boosting you, ask whose
  -- purse it was
  if not rec.by and BT.AskIfAlt then BT.AskIfAlt(rec.with) end
end

--------------------------------------------------------------------------
-- Reading the log back
--------------------------------------------------------------------------
BT.tradeDirty = 0
local cache, stamp = {}, nil
function BT.TouchTrades()
  BT.tradeDirty = BT.tradeDirty + 1
  cache = {}
end

-- filter: { id = step id, by = booster, since = timestamp }
function BT.Trades(filter)
  filter = filter or {}
  local st = BT.tradeDirty .. ":" .. #ChainDB.trades
  if st ~= stamp then cache, stamp = {}, st end
  local sig = tostring(filter.id) .. "|" .. tostring(filter.by) .. "|"
    .. tostring(filter.since)
  if cache[sig] then return cache[sig] end

  local out = {}
  for _, t in ipairs(ChainDB.trades) do
    local keep = true
    if filter.id and t.id ~= filter.id then keep = false end
    if keep and filter.by and t.by ~= filter.by then keep = false end
    if keep and filter.since and (t.at or 0) < filter.since then keep = false end
    if keep then table.insert(out, t) end
  end
  cache[sig] = out
  return out
end

-- Net copper out of your pocket, and the number of trades behind it
function BT.Spent(filter)
  local out, n = 0, 0
  for _, t in ipairs(BT.Trades(filter)) do
    out = out + (t.gave or 0) - (t.got or 0)
    n = n + 1
  end
  return out, n
end

-- Copper to gold, for printing
function BT.Gold(copper) return (copper or 0) / 10000 end

-- What you have actually paid per level. Counts only levels gained since the
-- first trade, so an alt that was already 30 before you started paying does
-- not make the figure look better than it was.
function BT.SpentPerLevel()
  local trades = BT.Trades({})
  if #trades == 0 then return nil end
  local firstLvl, spent = nil, 0
  for _, t in ipairs(trades) do
    if t.lvl and (not firstLvl or t.lvl < firstLvl) then firstLvl = t.lvl end
    spent = spent + (t.gave or 0) - (t.got or 0)
  end
  local now = UnitLevel("player") or 0
  local levels = now - (firstLvl or now)
  if levels < 1 or spent <= 0 then return nil, spent end
  return spent / levels, spent, levels
end

--------------------------------------------------------------------------
-- What the money bought, and what is left of it
--------------------------------------------------------------------------
-- You hand over 400g for ten runs and then you count. That is the part the
-- addon should be doing: it knows what a run costs him, it knows what you
-- paid, and it knows how many runs you have had. Runs left is the subtraction
-- nobody should be doing in their head halfway through a pull.
--
-- The count starts at your first payment to him rather than at the beginning
-- of time, so a booster you ran with before you ever installed this does not
-- show up owing you twenty runs. The two hours of slack in front of it are
-- for the other habit: paying at the end of a sitting, where the runs land
-- before the gold does.
local CREDIT_GRACE = 2 * 3600

local function PerRun(t)
  if (t.perRun or 0) > 0 then return t.perRun end
  -- an older record, from before the price was kept on it: the best we can do
  -- is today's price, and the tooltip says so
  if not BT.PricePerRun then return nil end
  local p = BT.PricePerRun({ id = t.id }, t.with)
  return (p and p > 0) and p or nil
end

-- Half the gold in a boost is handed to somebody who is not the booster: a
-- bank alt, a guild mate holding the purse, a second account. The trade is
-- real and the money is gone, but it lands against a name that has never run
-- anything for you - so the booster's account looks unpaid and the alt's
-- looks like a stranger who owes you twenty runs.
--
-- So an alt can be pointed at a booster, and everything paid to it counts for
-- him. One field, and it is the alt that carries it: you find out about the
-- alt at the moment you pay it.
function BT.PaysFor(name)
  local info = name and ChainDB.boosters[name]
  local to = info and info.payFor
  if not to or to == name then return nil end
  return to
end

function BT.SetPaysFor(alt, booster)
  alt = BT.CleanName and BT.CleanName(alt) or alt
  if not alt then return nil, "no name" end
  if booster then
    booster = BT.CleanName and BT.CleanName(booster) or booster
    if booster == alt then return nil, "that is the same person" end
  end
  local info = BT.BoosterInfo(alt)
  info.payFor = booster

  -- What you already handed the alt was priced at whatever a run costs with
  -- the alt - which is nothing, because he has never run anything, so it fell
  -- back to the instance price. Now that we know who he is collecting for,
  -- those payments are worth what a run costs with the booster. Only the ones
  -- that were priced by fallback are touched: a price you typed against that
  -- name yourself is yours and stays.
  local own = (ChainDB.boosters[alt] or {}).price or 0
  if own <= 0 then
    for _, t in ipairs(ChainDB.trades) do
      if t.with == alt then
        local p = BT.PricePerRun and BT.PricePerRun({ id = t.id }, booster) or 0
        t.perRun = (p > 0) and p or nil
      end
    end
  end
  BT.TouchTrades()
  if BT.RenderWindow then BT.RenderWindow() end
  return booster
end

-- You have just handed gold to somebody who has never run anything for you,
-- while somebody else is boosting you. That is a bank alt nine times out of
-- ten, and the moment the trade goes through is the moment you know - so ask
-- now rather than leaving his account looking unpaid and hers looking like a
-- stranger who owes you twenty runs.
--
-- Asked once per name. Say no and it is not asked again.
function BT.AskIfAlt(who, anchor)
  if not who then return false end
  local by = BT.CurrentBooster and BT.CurrentBooster()
  if not by or by == who then return false end
  if BT.PaysFor(who) then return false end
  local info = ChainDB.boosters[who]
  if info and info.notAnAlt then return false end
  -- somebody who has run for you is not a bank alt
  if #BT.Runs({ by = who, limit = 1 }) > 0 then return false end
  if not BT.ShowNearbyMenu then return false end

  BT.ShowNearbyMenu(who .. " has never run for you", {
    { text = "It is " .. C.gold .. by .. C.off .. "'s alt"
             .. C.dim .. "  - count it for him" .. C.off,
      fn = function()
        BT.SetPaysFor(who, by)
        print(C.info .. BT.NAME .. ":|r " .. who .. " now pays for " .. by
          .. " - what you hand her counts against his runs.")
      end },
    { text = C.dim .. "No, she is her own" .. C.off,
      fn = function() BT.BoosterInfo(who).notAnAlt = true end },
  }, anchor or (BT.barFrame and BT.barFrame()) or UIParent)
  return true
end

-- Every name whose payments count for this booster: himself, and any alt
-- pointed at him.
function BT.PurseFor(who)
  local names = { [who] = true }
  for name, info in pairs(ChainDB.boosters or {}) do
    if info.payFor == who then names[name] = true end
  end
  return names
end

-- Every trade with one person - or with any alt paying on his behalf - oldest
-- first
local function TradesWith(who)
  local out = {}
  if not who then return out end
  local purse = BT.PurseFor(who)
  for _, t in ipairs(ChainDB.trades) do
    if t.with and purse[t.with] then table.insert(out, t) end
  end
  return out
end

-- When money last went to him, his alts included. A payment newer than the
-- booster's own pack announcement means that announcement was about the last
-- pack, not this one.
function BT.LastPaid(who)
  local last
  for _, t in ipairs(TradesWith(who)) do
    local net = (t.gave or 0) - (t.got or 0)
    if net > 0 and (not last or (t.at or 0) > last) then last = t.at or 0 end
  end
  return last
end

-- Where the count starts for one person: the last time you told it outright
-- what the balance was, or failing that the first money that changed hands.
local function Base(list)
  for i = #list, 1, -1 do
    if list[i].setTo then return i, list[i].at or 0, list[i].setTo end
  end
  return 0, (list[1] and list[1].at or 0) - CREDIT_GRACE, 0
end

function BT.CreditStart(who)
  local list = TradesWith(who)
  if #list == 0 then return nil end
  return select(2, Base(list))
end

-- nil when you have never paid this person: there is no balance to report,
-- and a zero would read as one.
function BT.BoosterCredit(who)
  if not who then return nil end
  local list = TradesWith(who)
  if #list == 0 then return nil end

  -- Anything before a balance you typed in is history: you have said what the
  -- number is, and arguing with you about it would be the wrong way round.
  local baseIdx, baseAt, base = Base(list)
  local paid, runsPaid, guessed, n = 0, base, 0, 0
  for i = baseIdx + 1, #list do
    local t = list[i]
    local net = (t.gave or 0) - (t.got or 0)
    paid = paid + net
    n = n + 1
    local per = PerRun(t)
    if per and per > 0 and net ~= 0 then
      runsPaid = runsPaid + BT.Gold(net) / per
      if not ((t.perRun or 0) > 0) then guessed = guessed + 1 end
    end
  end

  -- a balance you set is true as of that second, so the run you had just
  -- finished is already in it
  local since = (baseIdx > 0) and (baseAt + 1) or baseAt
  local done = #BT.Runs({ by = who, since = since })

  -- His own counter, if his addon announced it. He knows when the pack
  -- started and we are inferring it from when you paid, so where the two
  -- differ his is the one to believe - but only about his pack. The gold is
  -- still ours to count.
  -- Not "BT.PackRun and BT.PackRun(who)": an and/or expression keeps only the
  -- first return value, so the pack size came back nil and the whole thing
  -- quietly did nothing. The same trap caught BT.LockedByGame.
  local hisN, hisOf
  if BT.PackRun then hisN, hisOf = BT.PackRun(who) end

  -- The pack you are working through: what the last payment bought, and how
  -- many of those you have had.
  --
  -- Deliberately the pack and not the balance. Pay for five with two still
  -- owed from before and the balance is seven - but nobody counts in sevens.
  -- He says "run 1 of 5" because five is what you just bought, and the two
  -- from before are a separate conversation, which is what "to come" and the
  -- Trade tab are for.
  local ofPack, donePack, packAt, livePack
  do
    local led = BT.CreditLedger and BT.CreditLedger() or nil
    for i = #list, 1, -1 do
      local t = list[i]
      if t.setTo or ((t.gave or 0) - (t.got or 0)) > 0 then
        local e = led and led[t]
        ofPack = (e and (e.bought or e.setTo)) or nil
        packAt = t.at or 0
        break
      end
    end
    if ofPack and packAt then
      donePack = #BT.Runs({ by = who, since = packAt + 1 })
      -- The one you are standing in counts. Nobody halfway through the second
      -- run calls it one: the number is which run this is, not how many are
      -- finished. Before the first one starts it is still 0 of 5, which is
      -- what you want to see the moment you have paid.
      local live = ChainCharDB and ChainCharDB.run
      if live and live.by == who and (live.start or 0) > packAt
         and donePack < ofPack then
        donePack, livePack = donePack + 1, true
      end
    end
  end

  return {
    who = who, paid = paid, trades = n, since = since,
    hisDone = hisN, hisOf = hisOf,
    ofPack = ofPack, donePack = donePack, livePack = livePack,
    hisLeft = (hisN and hisOf) and (hisOf - hisN) or nil,
    setAt = (baseIdx > 0) and baseAt or nil,
    setTo = (baseIdx > 0) and base or nil,
    runsPaid = runsPaid, runsDone = done, left = runsPaid - done,
    guessed = guessed
  }
end

-- The same subtraction, but frozen at each payment, so the trade log can show
-- a running balance rather than one number at the bottom.
local ledger, ledgerStamp = nil, nil
function BT.CreditLedger()
  local stamp = BT.tradeDirty .. ":" .. #ChainDB.trades .. ":" .. (BT.dirty or 0)
  if ledger and stamp == ledgerStamp then return ledger end

  local out, seen = {}, {}
  for _, t in ipairs(ChainDB.trades) do
    if t.with and not seen[t.with] then seen[t.with] = TradesWith(t.with) end
  end
  for who, list in pairs(seen) do
    local runs = BT.Runs({ by = who,
                           since = (list[1].at or 0) - CREDIT_GRACE })
    local paidRuns, at, was = 0, 1, 1
    for _, t in ipairs(list) do
      -- runs already finished by the time this line of the book was written
      was = at
      while at <= #runs and (runs[at].at or 0) <= (t.at or 0) do at = at + 1 end
      -- and what was still outstanding the moment before this money moved.
      -- Without it a row saying "you bought 3, that leaves 5" looks like bad
      -- arithmetic rather than two left over from the pack before.
      local carried = paidRuns - (at - 1)
      local ran = at - was
      if t.setTo then
        -- a line that says what the balance is rather than adding to it:
        -- everything above it stops counting, here and below
        paidRuns = t.setTo + (at - 1)
        out[t] = { setTo = t.setTo, left = t.setTo, carried = carried,
                   ran = ran }
      else
        local net = (t.gave or 0) - (t.got or 0)
        local per = PerRun(t)
        local bought = (per and per > 0 and net ~= 0)
          and (BT.Gold(net) / per) or nil
        if bought then paidRuns = paidRuns + bought end
        out[t] = { bought = bought, per = per, left = paidRuns - (at - 1),
                   carried = carried, ran = ran }
      end
    end
  end
  ledger, ledgerStamp = out, stamp
  return out
end

--------------------------------------------------------------------------
-- Trades the addon never saw
--------------------------------------------------------------------------
-- Gold handed over before you installed this, or sent by mail, or a trade
-- that went through while the addon was reloading. Without a way to type it
-- in, the balance is wrong from the first day and stays wrong - and a number
-- you know is wrong is a number you stop reading.

-- Kept in time order, because the running balance is read top to bottom and
-- a back-dated line appended to the end would be read after the runs it came
-- before.
local function Insert(rec)
  local at = rec.at or 0
  local i = #ChainDB.trades
  while i > 0 and (ChainDB.trades[i].at or 0) > at do i = i - 1 end
  table.insert(ChainDB.trades, i + 1, rec)
  while #ChainDB.trades > BT.K.MAX_TRADES do table.remove(ChainDB.trades, 1) end
  BT.TouchTrades()
  if BT.Refresh then BT.Refresh() end
  return rec
end

local function Stamp(who, when)
  local _, step = BT.Stage()
  local id = step and step.id or nil
  return {
    at = when or time(), with = who, gave = 0, got = 0,
    id = id, manual = true,
    by = ChainDB.boosters[who] and who or nil,
    lvl = UnitLevel("player"), char = UnitName("player")
  }
end

-- "I paid him 400g." Priced at what a run costs with him right now, the same
-- way a trade the addon watched would have been.
function BT.LogPayment(who, gold, when)
  who = BT.CleanName and BT.CleanName(who) or who
  if not who or who == "" then return nil, "no name" end
  gold = tonumber(gold)
  if not gold or gold == 0 then return nil, "no amount" end
  local rec = Stamp(who, when)
  if gold > 0 then rec.gave = math.floor(gold * 10000)
  else rec.got = math.floor(-gold * 10000) end
  -- priced by whoever the money is really for: paying a bank alt is paying
  -- the booster, and it buys his runs at his price
  local per = BT.PricePerRun
    and BT.PricePerRun({ id = rec.id }, BT.PaysFor(who) or who) or 0
  if per > 0 then rec.perRun = per end
  if per <= 0 then
    -- gold with no price to measure it against buys an unknown number of
    -- runs, which is worse than useless in a balance
    return nil, "no price set for " .. who
  end
  return Insert(rec)
end

-- "I have seven runs left with him." The blunt instrument, and the one you
-- want on the day you install this in the middle of an arrangement: it does
-- not care what came before, it just says what the number is from here.
function BT.SetRunsLeft(who, runs, when)
  who = BT.CleanName and BT.CleanName(who) or who
  if not who or who == "" then return nil, "no name" end
  runs = tonumber(runs)
  if not runs then return nil, "no number" end
  local rec = Stamp(who, when)
  rec.setTo = runs
  return Insert(rec)
end

-- and a way back out of a typo
function BT.ForgetTrade(rec)
  if not rec then return false end
  for i, t in ipairs(ChainDB.trades) do
    if t == rec then
      table.remove(ChainDB.trades, i)
      BT.TouchTrades()
      if BT.Refresh then BT.Refresh() end
      return true
    end
  end
  return false
end

-- Per booster, for the gold tab
function BT.SpentByBooster()
  local seen, out = {}, {}
  for _, t in ipairs(BT.Trades({})) do
    local key = t.with or "?"
    local b = seen[key]
    if not b then
      b = { with = key, net = 0, n = 0, booster = t.by ~= nil }
      seen[key] = b
      table.insert(out, b)
    end
    b.net = b.net + (t.gave or 0) - (t.got or 0)
    b.n = b.n + 1
    if t.by then b.booster = true end
  end
  table.sort(out, function(a, b) return a.net > b.net end)
  return out
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------
local tradeFrame = CreateFrame("Frame", "ChainTradeFrame")
BT.tradeFrame = tradeFrame

-- A trade that both sides accepted goes through the instant the second tick
-- lands, so a close after that is a completion. The one ordering that could
-- fool us is the player hitting cancel, which fires TRADE_CLOSED and only
-- then TRADE_REQUEST_CANCEL - so the log is written a beat later, and the
-- cancel gets its chance to call it off first.
-- What actually says a trade went through.
--
-- Requiring a TRADE_ACCEPT_UPDATE carrying both ticks was still too strict:
-- when the second person accepts, the trade executes and the window is torn
-- down, and that last event does not reliably arrive. Trades were still going
-- unlogged.
--
-- The reliable shape is the other way round. A cancel ALWAYS announces itself
-- - TRADE_REQUEST_CANCEL fires after TRADE_CLOSED when you abort and before
-- it when the other side does - so a trade window that closes and never
-- mentions a cancel is a trade that completed. Waiting a moment covers both
-- orderings, and an empty table is thrown out by TradeComplete anyway.
local function Settle()
  if not pending then return end
  local function finish()
    if pending and not cancelled then BT.TradeComplete() else BT.TradeClear() end
  end
  if C_Timer and C_Timer.After then C_Timer.After(0.3, finish) else finish() end
end

function BT.OnTradeEvent(_, event, ...)
  if event == "TRADE_SHOW" then
    cancelled, accepted = false, false
    BT.TradeSnapshot()
  elseif event == "TRADE_MONEY_CHANGED"
     or event == "TRADE_PLAYER_ITEM_CHANGED"
     or event == "TRADE_TARGET_ITEM_CHANGED" then
    BT.TradeSnapshot()
  elseif event == "TRADE_ACCEPT_UPDATE" then
    -- Snapshot first: this is the last look we get at the table before it is
    -- torn down, and it is the one that counts. The ticks are kept as a
    -- second opinion rather than as the deciding one.
    BT.TradeSnapshot()
    local mine, theirs = ...
    if (tonumber(mine) or 0) == 1 and (tonumber(theirs) or 0) == 1 then
      accepted = true
    end
  elseif event == "UI_INFO_MESSAGE" then
    -- Retail and the anniversary realms say so outright. Classic Era often
    -- does not, which is what the close-without-cancel path is for; both are
    -- kept, and whichever comes first clears the pending trade so it can
    -- never be logged twice.
    local a, b = ...
    local msg = (type(a) == "string") and a or b
    if msg and ERR_TRADE_COMPLETE and msg == ERR_TRADE_COMPLETE then
      accepted = true
      BT.TradeComplete()
    end
  elseif event == "TRADE_CLOSED" then
    Settle()
  elseif event == "TRADE_REQUEST_CANCEL" then
    -- It can arrive either side of the close, so it is a flag rather than an
    -- immediate throw-away: the settle above reads it a moment later.
    cancelled = true
  end
end

tradeFrame:SetScript("OnEvent", BT.OnTradeEvent)
for _, e in ipairs({ "TRADE_SHOW", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE",
                     "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
                     "TRADE_CLOSED", "TRADE_REQUEST_CANCEL", "UI_INFO_MESSAGE" }) do
  tradeFrame:RegisterEvent(e)
end
