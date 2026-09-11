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

local pending = nil

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

function BT.TradeSnapshot()
  if not (GetPlayerTradeMoney and GetTargetTradeMoney) then return end
  local who = UnitName and UnitName("NPC") or nil
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

function BT.TradeClear() pending = nil end

-- Log the trade that just went through. Attributed to the step you are on,
-- and to a booster when the person you traded is one.
function BT.TradeComplete()
  local t = pending
  pending = nil
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

  table.insert(ChainDB.trades, {
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
    id = (inside and inside.id) or (step and step.id) or nil,
    -- only claim it was the booster when the names actually match
    by = (by and t.with == by) and by or nil,
    lvl = UnitLevel("player"),
    char = UnitName("player")
  })
  while #ChainDB.trades > BT.K.MAX_TRADES do
    table.remove(ChainDB.trades, 1)
  end
  BT.TouchTrades()
  if BT.Refresh then BT.Refresh() end
  if BT.RenderWindow then BT.RenderWindow() end
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

function BT.OnTradeEvent(_, event, ...)
  if event == "TRADE_SHOW" or event == "TRADE_MONEY_CHANGED"
     or event == "TRADE_ACCEPT_UPDATE" or event == "TRADE_PLAYER_ITEM_CHANGED"
     or event == "TRADE_TARGET_ITEM_CHANGED" then
    BT.TradeSnapshot()
  elseif event == "UI_INFO_MESSAGE" then
    -- Classic passes (messageType, message); older builds passed just the
    -- message, so check both rather than assuming one shape
    local a, b = ...
    local msg = (type(a) == "string") and a or b
    if msg and ERR_TRADE_COMPLETE and msg == ERR_TRADE_COMPLETE then
      BT.TradeComplete()
    end
  elseif event == "TRADE_CLOSED" or event == "TRADE_REQUEST_CANCEL" then
    -- TRADE_CLOSED also fires after a successful trade, but the completion
    -- message always arrives first, so by now there is nothing left to log
    BT.TradeClear()
  end
end

tradeFrame:SetScript("OnEvent", BT.OnTradeEvent)
for _, e in ipairs({ "TRADE_SHOW", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE",
                     "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
                     "TRADE_CLOSED", "TRADE_REQUEST_CANCEL", "UI_INFO_MESSAGE" }) do
  tradeFrame:RegisterEvent(e)
end
