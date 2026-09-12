-- Chain: what came out of the runs.
--
-- Everything looted, by you or by anybody in the party or raid. The combat
-- log carries none of this; the loot messages in chat do, and they arrive for
-- every member of the group whether or not you were the one who pressed the
-- button.
--
-- The messages are read by pattern rather than by looking for English words.
-- The client already owns the sentences - LOOT_ITEM_SELF is "You receive
-- loot: %s." and LOOT_ITEM is "%s receives loot: %s." - so the patterns are
-- built from those at load. That is the whole reason this works on a client
-- in any language, and it costs nothing but doing it the right way round.
--
-- One thing this deliberately does not do: decide what is worth keeping. The
-- window sorts and filters; the log records.

local ADDON, BT = ...
local C = BT.COL

local MAX_LOOT = 4000

--------------------------------------------------------------------------
-- Turning the client's own sentences into patterns
--------------------------------------------------------------------------
local function ToPattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  -- escape everything Lua patterns treat as special, then put the two
  -- placeholders back as captures
  local p = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  p = p:gsub("%%%%s", "(.+)")
  p = p:gsub("%%%%d", "(%%d+)")
  return "^" .. p .. "$"
end

-- Order matters: the "multiple" sentences have to be tried first, because the
-- singular one ends in "%s." and would happily swallow the "x3" as part of
-- the item link.
local FORMS
local function BuildForms()
  if FORMS then return FORMS end
  FORMS = {}
  local function add(fmt, selfOnly, hasCount)
    local p = ToPattern(fmt)
    if p then
      FORMS[#FORMS + 1] = { pat = p, selfOnly = selfOnly, count = hasCount }
    end
  end
  -- somebody else, with a count
  add(_G.LOOT_ITEM_MULTIPLE, false, true)
  add(_G.LOOT_ITEM_PUSHED_MULTIPLE, false, true)
  -- you, with a count
  add(_G.LOOT_ITEM_SELF_MULTIPLE, true, true)
  add(_G.LOOT_ITEM_PUSHED_SELF_MULTIPLE, true, true)
  add(_G.LOOT_ITEM_CREATED_SELF_MULTIPLE, true, true)
  -- somebody else, one of them
  add(_G.LOOT_ITEM, false, false)
  add(_G.LOOT_ITEM_PUSHED, false, false)
  -- you, one of them
  add(_G.LOOT_ITEM_SELF, true, false)
  add(_G.LOOT_ITEM_PUSHED_SELF, true, false)
  add(_G.LOOT_ITEM_CREATED_SELF, true, false)
  return FORMS
end
BT.LootForms = BuildForms

-- Pull who, what and how many out of one loot line. nil when it is not one.
function BT.ParseLoot(msg)
  if type(msg) ~= "string" then return nil end
  for _, f in ipairs(BuildForms()) do
    local a, b, c = msg:match(f.pat)
    if a then
      local who, link, count
      if f.selfOnly then
        link, count = a, f.count and tonumber(b) or 1
        who = (UnitName and UnitName("player")) or "you"
      else
        who, link, count = a, b, f.count and tonumber(c) or 1
      end
      -- it is only loot if there is an item in it
      if link and link:find("|Hitem:", 1, true) then
        return BT.ShortName(who), link, math.max(1, count or 1), f.selfOnly
      end
    end
  end
  return nil
end

-- Coins. The client owns these words too - GOLD_AMOUNT is "%d Gold" - so the
-- unit names are taken from it rather than written out here.
local function CoinWord(fmt)
  if type(fmt) ~= "string" then return nil end
  local w = fmt:gsub("%%d", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return (w ~= "") and w or nil
end

function BT.ParseCoins(msg)
  if type(msg) ~= "string" then return nil end
  local g = CoinWord(_G.GOLD_AMOUNT) or "Gold"
  local s = CoinWord(_G.SILVER_AMOUNT) or "Silver"
  local c = CoinWord(_G.COPPER_AMOUNT) or "Copper"
  local function grab(word)
    if not word then return 0 end
    local n = msg:match("(%d+)%s*" .. word:gsub("(%W)", "%%%1"))
    return tonumber(n) or 0
  end
  local total = grab(g) * 10000 + grab(s) * 100 + grab(c)
  if total <= 0 then return nil end
  return total
end

--------------------------------------------------------------------------
-- What it dropped from
--------------------------------------------------------------------------
-- The loot message does not say. Nothing in it does - which is why this is
-- known for your own loot and blank for everybody else's, and why it says
-- blank rather than guessing.
--
-- For your own: when the loot window opens the client will name the corpse
-- through GetLootSourceInfo, as a GUID. The name for that GUID comes from the
-- combat log, which said it when the thing died. Two halves, neither of which
-- is any use alone.
local CORPSE_MAX = 60
local corpses, corpseOrder = {}, {}

function BT.NoteCorpse(guid, name)
  if not guid or not name or name == "" then return end
  if corpses[guid] then return end
  corpses[guid] = name
  table.insert(corpseOrder, guid)
  while #corpseOrder > CORPSE_MAX do
    local old = table.remove(corpseOrder, 1)
    corpses[old] = nil
  end
end

function BT.CorpseName(guid) return guid and corpses[guid] or nil end

-- Set when a loot window opens, and only trusted for a few seconds after: the
-- loot lines arrive immediately, and anything later is a different corpse.
local FRESH = 5
function BT.NoteLootSource()
  local name
  if GetNumLootItems and GetLootSourceInfo then
    for slot = 1, (GetNumLootItems() or 0) do
      local guid = GetLootSourceInfo(slot)
      if guid then
        name = BT.CorpseName(guid)
        if name then break end
      end
    end
  end
  -- the corpse you are standing on is usually the one you are pointing at
  if not name and UnitName and UnitExists and UnitExists("target")
     and (not UnitIsPlayer or not UnitIsPlayer("target")) then
    name = UnitName("target")
  end
  BT.lootFrom, BT.lootFromAt = name, time()
  return name
end

local function SourceNow()
  if not BT.lootFrom then return nil end
  if (time() - (BT.lootFromAt or 0)) > FRESH then return nil end
  return BT.lootFrom
end

--------------------------------------------------------------------------
-- The log
--------------------------------------------------------------------------
-- The item id, which is the one part of a link that is stable. Links carry
-- the player's own level and spec in them on some clients, so two links for
-- the same item are not always the same string.
function BT.ItemID(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|Hitem:(%d+)"))
end

function BT.NoteLoot(who, link, count, mine)
  if ChainDB.logLoot == false then return nil end
  if not link then return nil end
  ChainDB.loot = ChainDB.loot or {}

  local r = ChainCharDB.run
  local e = {
    at = time(), who = who, link = link, id = BT.ItemID(link),
    n = math.max(1, count or 1), mine = mine or nil,
    zone = (GetRealZoneText and GetRealZoneText()) or nil,
    -- only ever for your own: nothing in somebody else's loot line says where
    -- it came from, and a guess in that column would be worse than a blank
    from = mine and SourceNow() or nil,
    -- which run it fell in, so a run's worth can be added up later
    step = r and r.id or nil,
    by = r and r.by or nil,
  }
  table.insert(ChainDB.loot, e)

  -- trimmed from the front, oldest first
  while #ChainDB.loot > MAX_LOOT do table.remove(ChainDB.loot, 1) end
  if BT.RenderWindow then BT.RenderWindow() end
  return e
end

function BT.NoteCoins(copper, who, mine)
  if ChainDB.logLoot == false then return nil end
  if not copper or copper <= 0 then return nil end
  ChainDB.loot = ChainDB.loot or {}
  local r = ChainCharDB.run
  local e = {
    at = time(), who = who, copper = copper, n = 1, mine = mine or nil,
    zone = (GetRealZoneText and GetRealZoneText()) or nil,
    -- the coins came off the same corpse as everything else in that window,
    -- and leaving this out put the money and the cloth from one mob on two
    -- lines that did not look related
    from = mine and SourceNow() or nil,
    step = r and r.id or nil, by = r and r.by or nil,
  }
  table.insert(ChainDB.loot, e)
  while #ChainDB.loot > MAX_LOOT do table.remove(ChainDB.loot, 1) end
  if BT.RenderWindow then BT.RenderWindow() end
  return e
end

-- Newest first
function BT.LootLog()
  local out = {}
  for _, e in ipairs(ChainDB.loot or {}) do table.insert(out, e) end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

function BT.ForgetLoot()
  ChainDB.loot = {}
  if BT.RenderWindow then BT.RenderWindow() end
end

-- What an entry is worth, from the client's own item data. nil while the item
-- is still uncached - said as unknown rather than guessed at zero, because a
-- zero in a money column is a claim.
function BT.LootValue(e)
  if not e then return nil end
  if e.copper then return e.copper end
  if not GetItemInfo or not e.link then return nil end
  local _, _, _, _, _, _, _, _, _, _, price = GetItemInfo(e.link)
  if not price then return nil end
  return price * (e.n or 1)
end

function BT.LootQuality(e)
  if not e or e.copper then return nil end
  if not GetItemInfo or not e.link then return nil end
  local _, _, quality = GetItemInfo(e.link)
  return quality
end

function BT.LootName(e)
  if not e then return "?" end
  if e.copper then return BT.Coin(e.copper) end
  if e.link then
    local n = e.link:match("%[(.-)%]")
    if n then return n end
    if GetItemInfo then
      local name = GetItemInfo(e.link)
      if name then return name end
    end
  end
  return "?"
end

-- Totals, and who got what. Coins and items add up together: a run's worth is
-- both.
function BT.LootTotals(since)
  local cut = since and (time() - since) or nil
  local value, known, unknown, items, coins = 0, 0, 0, 0, 0
  local byWho = {}
  for _, e in ipairs(ChainDB.loot or {}) do
    if not cut or (e.at or 0) >= cut then
      local v = BT.LootValue(e)
      if e.copper then coins = coins + e.copper else items = items + (e.n or 1) end
      if v then
        value = value + v
        known = known + 1
        local w = e.who or "?"
        byWho[w] = (byWho[w] or 0) + v
      elseif not e.copper then
        unknown = unknown + 1
      end
    end
  end
  local list = {}
  for w, v in pairs(byWho) do list[#list + 1] = { who = w, value = v } end
  table.sort(list, function(a, b) return a.value > b.value end)
  return value, list, items, coins, unknown
end

--------------------------------------------------------------------------
-- Watching
--------------------------------------------------------------------------
local f = CreateFrame("Frame", "ChainLootFrame")
BT.lootFrame = f
f:SetScript("OnEvent", function(_, event, msg)
  if not ChainDB or ChainDB.logLoot == false then return end
  if event == "LOOT_OPENED" or event == "LOOT_READY" then
    BT.NoteLootSource()
  elseif event == "CHAT_MSG_LOOT" then
    local who, link, count, mine = BT.ParseLoot(msg)
    if who then BT.NoteLoot(who, link, count, mine) end
  elseif event == "CHAT_MSG_MONEY" then
    local copper = BT.ParseCoins(msg)
    if copper then
      -- the money line never names anybody when it is yours
      local who = (UnitName and UnitName("player")) or "you"
      local other = msg:match("^(%S+)%s")
      local mine = true
      if other and _G.LOOT_MONEY and not msg:find("^" .. (_G.YOU_LOOT_MONEY or "You")) then
        -- somebody else's share, when the client says so
      end
      BT.NoteCoins(copper, who, mine)
    end
  end
end)
f:RegisterEvent("CHAT_MSG_LOOT")
f:RegisterEvent("CHAT_MSG_MONEY")
f:RegisterEvent("LOOT_OPENED")
f:RegisterEvent("LOOT_READY")
