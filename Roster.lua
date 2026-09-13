-- Chain: where the booster list comes from.
--
-- Two sources, both optional, neither required for the addon to work:
--
--  1. The adverts boosters put in chat. They tell you their price themselves,
--     several times an hour. Reading that costs nothing and fills the list
--     with people you have never run with.
--  2. What other people running this addon measured. Only facts travel: the
--     price they were quoted, and what they clocked - experience per run,
--     time, mob count. There is no opinion to send: the verdict is worked out
--     from those numbers, so everyone computes it from the same evidence.
--
-- Anything you measured or typed yourself always wins over both.

local ADDON, BT = ...
local C = BT.COL

local PREFIX = "LVLTRK1"
-- Addon messages never appear in anyone's chat - they are invisible to
-- players and only other copies of this addon ever see them. They do have to
-- travel over some channel though, and rather than borrow your guild or your
-- party we join a hidden channel of our own. Everyone running the addon is in
-- it, nobody else is, and it is removed from your chat windows on sight.
local CHANNEL = "ChainData"

--------------------------------------------------------------------------
-- Reading adverts
--------------------------------------------------------------------------
-- Lowercased word-boundary search, so "sm" does not match "small"
local function HasWord(hay, needle)
  if needle == "" then return false end
  return hay:find("%f[%w]" .. needle:lower():gsub("(%W)", "%%%1") .. "%f[%W]") ~= nil
end

-- Where a name sits in the text, or nil. Position rather than yes-or-no,
-- because which name comes first is the whole answer below.
local function WordAt(hay, needle)
  if needle == "" then return nil end
  return hay:find("%f[%w]" .. needle:lower():gsub("(%W)", "%%%1") .. "%f[%W]")
end

-- Which instance an advert is about, if any.
--
-- The earliest name in the text wins, not the first one our own table happens
-- to list. Boosters sell by running other people down, and the instance they
-- name while doing it is not the one they are selling:
--
--   WTS Nonstop Dire Maul West+North Boost, Better than Strat/ZG/BRD and
--   incompetent mafia boosters
--
-- That went into the list as Blackrock Depths, for no better reason than that
-- BRD sits above Dire Maul in BT.DUNGEONS. An advert leads with what it is
-- selling and everything after that is context, so reading order is the
-- answer. It is a rule and not a certainty - somebody who opens with what he
-- is better than will still fool it - but it is right about how people write.
local function FirstNamed(low)
  local best, bestAt, bestLen
  -- Earliest wins; on a tie the longer name wins, because the longer name is
  -- the more specific one. "Dire Maul East" and "Dire Maul" start at the same
  -- letter and only one of them says which wing.
  local function see(needle, id)
    if not needle or needle == "" then return end
    local at = WordAt(low, needle)
    if not at then return end
    local len = #needle
    if bestAt and (at > bestAt or (at == bestAt and len <= bestLen)) then return end
    best, bestAt, bestLen = id, at, len
  end
  for _, d in ipairs(BT.DUNGEONS) do
    see(d.label, d.id)
    see(d.zone, d.id)
    local short = BT.SHORT[d.zone]
    if short then see(short, d.id) end
  end
  -- and the words people actually type: "Mara boost", "SM Cath & Arm"
  for word, id in pairs(BT.ALIAS or {}) do see(word, id) end
  return best
end

function BT.AdZone(msg)
  return FirstNamed(" " .. msg:lower() .. " ")
end

-- What was said, without the decorations: colour codes, item links and the
-- little icons people pad an advert with. Short enough to sit in a column,
-- long enough to tell one offer from another.
function BT.AdText(msg)
  if type(msg) ~= "string" then return nil end
  local t = msg:gsub("|T.-|t", ""):gsub("|A.-|a", "")
  t = t:gsub("|H.-|h(.-)|h", "%1")
  t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  t = t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  -- kept whole: the row shows as much as fits and the tooltip shows the rest
  if #t > 255 then t = t:sub(1, 252) .. "..." end
  return t
end

-- Gold, and how many runs it covers. "200g for 5 runs" and "40g per run" are
-- the two shapes people actually write.
function BT.AdPrice(msg)
  local low = msg:lower()
  local gold
  local k = low:match("(%d+%.?%d*)%s*k%s*g%f[%W]") or low:match("(%d+%.?%d*)%s*kg%f[%W]")
  if k then
    gold = tonumber(k) * 1000
  else
    local g = low:match("(%d+)%s*g%f[%W]") or low:match("(%d+)%s*gold%f[%W]")
    gold = tonumber(g)
  end
  if not gold or gold <= 0 or gold > 100000 then return nil end
  local runs = tonumber(low:match("(%d+)%s*runs?%f[%W]"))
  if runs and (runs < 1 or runs > 50) then runs = nil end
  return gold, runs
end

-- Selling something is not selling a boost. Trade chat is mostly people
-- selling things - dust, a formula, an [Edgemaster's Handguards], a summon, a
-- port, a raid loot run - and "WTS" is the only thing any of them have in
-- common with the man selling Stockade runs. WTS on its own used to be enough
-- to get on the list, and the list filled up with the other trade.
local function SaysBoost(low)
  return low:find("boost", 1, true) or low:find("carry", 1, true)
    or low:find("powerlevel", 1, true) or low:find("power level", 1, true)
    or low:find("power lvl", 1, true) or low:find("%f[%a]pl%f[%A]") ~= nil
end

-- A raid loot run says "runs" and a price exactly like a boost does, so the
-- only thing that separates them is the name of the place. These are not
-- levelling, whatever they cost, and this addon counts levels.
local RAID_SALE = { "loot run", "lootrun", "gdkp", "naxx", "aq20", "aq40",
                    "%f[%a]aq%f[%A]", "%f[%a]bwl%f[%A]", "onyxia",
                    "%f[%a]ony%f[%A]", "molten core", "%f[%a]mc%f[%A]",
                    "%f[%a]zg%f[%A]", "%f[%a]aq40%f[%A]" }
local function RaidSale(low)
  for _, w in ipairs(RAID_SALE) do
    if low:find(w) then return true end
  end
  return false
end

-- Does this read like somebody selling boosts? Two questions, and both have to
-- answer yes: is it a sale rather than a request, and is what is being sold a
-- boost rather than anything else a person sells in the same channel.
function BT.LooksLikeAd(msg)
  local low = msg:lower()
  local sells = low:find("wts", 1, true) or low:find("selling", 1, true)
    or low:find("sell ", 1, true)
  if not sells then
    -- "LFM Stockades boost, need 2 more" and "WTB SM boost" are people
    -- wanting one, not selling one. Without a plain WTS they are skipped.
    if low:find("%f[%a]lf[mg]?%f[%A]") or low:find("looking for", 1, true)
       or low:find("%f[%a]wtb%f[%A]") or low:find("%f[%a]need%f[%A]") then
      return false
    end
  end
  local id = BT.AdZone(msg)
  -- "Stockades 5 runs 200g" - a named instance and a number of runs is a boost
  -- whatever words are around it. Runs on their own are not: a loot run is
  -- runs too.
  local runs = low:find("%f[%w]runs?%f[%W]") ~= nil
  if not SaysBoost(low) and not (id and runs) then return false end
  -- and a raid is a raid even when it says boost, unless it also names an
  -- instance we level in - "SM boost" in a line that mentions MC is still SM.
  if not id and RaidSale(low) then return false end
  -- An item in the line and no instance in it is a man selling the item. The
  -- link survives as [Its Name] once the colour codes are off, and that is
  -- what the row would have shown you.
  if not id and low:find("%[.-%]") then return false end
  return true
end

--------------------------------------------------------------------------
-- Reading the other half of the channel: people looking, not selling
--------------------------------------------------------------------------
-- LooksLikeAd throws away everything that is not a sale, and what it throws
-- away is most of what is written: "LFM SM cath need healer", "LFG RFD",
-- "LF2M Uldaman quest". Those are worth keeping too - the same reading, the
-- same list, the same whisper button. Nothing is matched against your quest
-- log or anything else clever: what was said is kept whole and the search box
-- on the tab is what narrows it.
local GROUP_KINDS = {
  -- order matters: the first that matches wins, and "lfm" is more specific
  -- than the "lf" inside it
  { kind = "wtb", label = "wants to buy",
    test = function(low)
      return low:find("%f[%a]wtb%f[%A]") or low:find("want to buy", 1, true)
        or low:find("%f[%a]buying%f[%A]")
    end },
  { kind = "lfm", label = "forming",
    test = function(low)
      return low:find("%f[%a]lf%d*m%f[%A]") or low:find("looking for more", 1, true)
        or low:find("%f[%a]need%s+%d*%s*[dht]ps?%f[%A]")
        or low:find("%f[%a]need%s+%a*%s*heal", 1)
        or low:find("%f[%a]need%s+%a*%s*tank", 1)
    end },
  { kind = "lfg", label = "looking",
    test = function(low)
      return low:find("%f[%a]lfg%f[%A]") or low:find("%f[%a]lf%s*group%f[%A]")
        or low:find("looking for group", 1, true)
        or low:find("%f[%a]lf%s*grp%f[%A]")
    end }
}

-- What sort of post this is, or nil if it is neither
function BT.GroupKind(msg)
  if type(msg) ~= "string" then return nil end
  local low = " " .. msg:lower() .. " "
  for _, g in ipairs(GROUP_KINDS) do
    if g.test(low) then return g.kind, g.label end
  end
  return nil
end

-- How many they are short, and what of. "LF2M healer dps" -> 2, "healer dps"
function BT.GroupNeeds(msg)
  local low = msg:lower()
  local n = tonumber(low:match("%f[%a]lf(%d+)m%f[%A]"))
    or tonumber(low:match("%f[%a]need%s+(%d+)"))
  local roles = {}
  if low:find("heal", 1, true) then table.insert(roles, "healer") end
  if low:find("%f[%a]tank") then table.insert(roles, "tank") end
  if low:find("%f[%a]dps%f[%A]") or low:find("%f[%a]dd%f[%A]") then
    table.insert(roles, "dps")
  end
  local txt = (n and (n .. " more") or nil)
  if #roles > 0 then
    txt = (txt and (txt .. ": ") or "") .. table.concat(roles, ", ")
  end
  return txt, n
end

-- The levels a post asks for: "20-25", "lvl 24+", "24 plus"
function BT.GroupLevels(msg)
  local low = msg:lower()
  local a, b = low:match("%f[%d](%d%d?)%s*[-–]%s*(%d%d?)%f[%D]")
  if a and tonumber(a) >= 2 and tonumber(b) <= 60 and tonumber(b) > tonumber(a) then
    return a .. "-" .. b
  end
  local plus = low:match("%f[%a]l?v?l?%s*(%d%d?)%s*%+")
  if plus and tonumber(plus) >= 2 and tonumber(plus) <= 60 then return plus .. "+" end
  return nil
end

-- The kept list. Chat channels repeat themselves every thirty seconds, so the
-- same person saying the same thing again moves his row up and counts once
-- more rather than filling the list with the same line twenty times over.
local GROUP_MAX = 150
local GROUP_SAME = 900        -- seconds before a repeat counts as a new post

function BT.NoteGroup(msg, sender, source)
  if not ChainDB.readGroups then return end
  if type(msg) ~= "string" or type(sender) ~= "string" then return end
  if not BT.AdSourceOn(source) then return end
  local kind = BT.GroupKind(msg)
  if not kind then return end
  local name = BT.ShortName(sender)
  if not name or name == BT.ShortName(UnitName("player")) then return end

  local text = BT.AdText(msg)
  local now = time()
  local db = ChainDB
  db.groups = db.groups or {}
  for _, g in ipairs(db.groups) do
    if g.by == name and g.text == text then
      if (now - (g.at or 0)) < GROUP_SAME then
        db.groupSeq = (db.groupSeq or 0) + 1
        g.at, g.n, g.seq = now, (g.n or 1) + 1, db.groupSeq
        if BT.RenderWindow then BT.RenderWindow() end
        return
      end
      break
    end
  end

  local needs = BT.GroupNeeds(msg)
  db.groupSeq = (db.groupSeq or 0) + 1
  table.insert(db.groups, {
    by = name, at = now, seq = db.groupSeq, kind = kind, from = source or "say",
    id = BT.AdZone(msg), needs = needs, levels = BT.GroupLevels(msg),
    text = text, n = 1
  })
  -- oldest out. A post nobody answered an hour ago is not a post any more.
  while #db.groups > GROUP_MAX do table.remove(db.groups, 1) end
  if BT.RenderWindow then BT.RenderWindow() end
end

-- Newest first, and optionally only the ones naming one instance. Sorted by
-- the time rather than walked backwards: a repeat moves an old row to the top
-- by changing its timestamp, and walking the table would leave it where it
-- was first stored.
function BT.GroupLog(id)
  local out = {}
  for _, g in ipairs(ChainDB.groups or {}) do
    if not id or g.id == id then table.insert(out, g) end
  end
  -- seq breaks the ties: several posts can land in the same second, and a
  -- list that reshuffles itself between two draws is unreadable
  table.sort(out, function(a, b)
    if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
    return (a.seq or 0) > (b.seq or 0)
  end)
  return out
end

function BT.ForgetGroups()
  ChainDB.groups = {}
  if BT.RenderWindow then BT.RenderWindow() end
end

-- Which chat sources adverts are read from. Anything not in the table is on:
-- a channel you join tomorrow is read tomorrow without you going looking for
-- a setting, and only the ones you actually turned off stay off.
function BT.AdSourceOn(key)
  if not key then return true end
  local set = ChainDB.adSources
  if not set or set[key] == nil then return true end
  return set[key] and true or false
end

function BT.SetAdSource(key, on)
  if not key then return end
  ChainDB.adSources = ChainDB.adSources or {}
  ChainDB.adSources[key] = on and true or false
  BT.TouchRoster()
end

-- The fixed sources, in the order they are shown. Channels are added to this
-- list at run time from the ones you are actually in.
BT.AD_SOURCES = {
  { key = "say",     label = "Say" },
  { key = "yell",    label = "Yell" },
  { key = "guild",   label = "Guild" },
  { key = "whisper", label = "Whispers" },
  { key = "party",   label = "Party and raid" },
}

-- General and the other city channels carry the zone in their name - "General
-- - Stormwind City" in town, "General - Westfall" outside - and the game
-- hands us whichever one you are standing in. Keyed on the bare name they are
-- one channel, which is how you think of them and how the channel list in
-- your chat window numbers them.
function BT.ChannelKey(name)
  if type(name) ~= "string" then return nil end
  local base = name:match("^([^%-]+)%s*%-") or name
  base = base:gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if base == "" then return nil end
  return "channel:" .. base, base
end

-- Every source you could read adverts from right now: the fixed ones, then
-- every channel you are in, ours excluded. Channels you are not in cannot be
-- read at all - the game never sends them - so they are not listed.
function BT.AdSourceList()
  local out, seen = {}, {}
  for _, src in ipairs(BT.AD_SOURCES) do
    table.insert(out, { key = src.key, label = src.label, on = BT.AdSourceOn(src.key),
                        n = BT.AdCount(src.key) })
  end
  if GetChannelList then
    local list = { GetChannelList() }
    for i = 1, #list, 3 do
      local number, name = list[i], list[i + 1]
      if type(name) == "string" and not BT.OwnChannel(name) then
        local key, base = BT.ChannelKey(name)
        if key and not seen[key] then
          seen[key] = true
          -- the number the chat window shows it under, and the bare name
          table.insert(out, {
            key = key,
            label = (number and (number .. ". ") or "")
              .. (base and (base:sub(1, 1):upper() .. base:sub(2)) or name),
            on = BT.AdSourceOn(key), n = BT.AdCount(key) })
        end
      end
    end
  end
  return out
end

-- Our own two channels carry addon data, never adverts
function BT.OwnChannel(name)
  if type(name) ~= "string" then return false end
  local low = name:lower()
  if low == CHANNEL:lower() then return true end
  local me = BT.ShortName(UnitName("player") or "") or ""
  return low == ("lb" .. me:lower()) or low == ("lt" .. me:lower())
end

function BT.NoteAd(msg, sender, source)
  if not ChainDB.readAds then return end
  if type(msg) ~= "string" or type(sender) ~= "string" then return end
  if not BT.AdSourceOn(source) then return end
  if not BT.LooksLikeAd(msg) then return end
  -- An advert we cannot put a name to is still a man selling boosts.
  --
  -- It used to be thrown away outright, and the ones that go are exactly the
  -- ones worth having: a spelling nobody but him uses, a wing we have no word
  -- for, an offer with no instance in it at all. He goes on the list with a
  -- dash where the instance would be - the text of what he said is right
  -- there in the row, and the whisper button works the same.
  local id = BT.AdZone(msg)
  -- The price is optional. Most adverts do not carry one at all - "WTS SM
  -- boost, Cath & Arm, 20-42, FFA loot, sum ready" is the usual shape - and a
  -- booster you never see is worse than one whose price you have to ask for.
  local gold, runs = BT.AdPrice(msg)

  local name = BT.ShortName(sender)
  if name == BT.ShortName(UnitName("player")) then return end
  local b = BT.BoosterInfo(name)
  b.adPrice, b.adPack, b.adAt = gold or 0, runs or 1, time()
  -- nil rather than a guess: "we do not know" is a thing the row can say
  b.adZone = id
  b.adAny = true
  b.adFrom = source
  b.adText = BT.AdText(msg)
  BT.CountAd(source, name, id, gold or 0, runs or 1)
  BT.TouchRoster()
  -- the window is usually open while you are shopping
  if BT.RenderWindow then BT.RenderWindow() end
end

-- Sweeping up after the filter that used to be too wide. Everybody who typed
-- WTS anything went on the list, and what they were selling was dust and
-- enchant formulas. The adverts themselves fall off the tab after half an
-- hour, but the name stayed on the books for ever.
--
-- Only the ones that are nothing but an old advert go: no runs with him, no
-- price, no note of yours, nothing anybody told you about him, and no
-- instance named in what he said. Anything you know is knowledge, and
-- knowledge is not swept up.
-- Is what he said still an advert for a boost? Asked of a record rather than
-- of a message, so a reading that has been tightened applies to what is
-- already in the book and not only to what arrives next. The list was full of
-- dust and enchant formulas the moment the rule changed, and they would have
-- sat there until they aged out - half an hour of looking at exactly what you
-- had just asked not to see.
function BT.StillAnAd(info)
  if type(info) ~= "table" then return false end
  if info.adZone then return true end          -- it named an instance
  local text = info.adText
  if type(text) ~= "string" or text == "" then
    -- nothing kept to judge: an older record, and the name is all we have
    return info.adAny and true or false
  end
  return BT.LooksLikeAd(text) and true or false
end

function BT.ForgetStaleAds(age)
  if type(ChainDB.boosters) ~= "table" then return 0 end
  age = age or (7 * 24 * 3600)
  local known = {}
  for _, r in ipairs(ChainDB.runs or {}) do if r.by then known[r.by] = true end end
  for _, t in ipairs(ChainDB.trades or {}) do
    if t.with then known[t.with] = true end
    if t.by then known[t.by] = true end
  end
  local gone = 0
  for name, info in pairs(ChainDB.boosters) do
    if type(info) == "table" and not known[name] and not info.mine
       and not info.shared and not info.note and not info.adZone
       and not info.zones and (info.price or 0) <= 0
       and (info.adPrice or 0) <= 0
       and (info.adAt or 0) > 0
       -- old, or not an advert for a boost by today's reading. The second one
       -- has no age on it: what he said is on the record, and it either reads
       -- as a boost or it never did.
       and ((time() - info.adAt) > age or not BT.StillAnAd(info)) then
      ChainDB.boosters[name] = nil
      gone = gone + 1
    end
  end
  if gone > 0 then BT.TouchRoster() end
  return gone
end

-- How much each source has actually produced, and the last few adverts in
-- full. Without this, "I do not see any boosters" and "nothing is being read"
-- look exactly the same from the outside.
function BT.CountAd(source, name, id, gold, pack)
  local db = ChainDB
  db.adCounts = db.adCounts or {}
  local key = source or "say"
  db.adCounts[key] = (db.adCounts[key] or 0) + 1
  db.adLog = db.adLog or {}
  table.insert(db.adLog, { by = name, id = id, gold = gold, pack = pack,
                           at = time(), from = key })
  while #db.adLog > 20 do table.remove(db.adLog, 1) end
end

function BT.AdCount(source)
  local c = ChainDB.adCounts
  return (c and source and c[source]) or 0
end

-- Everything heard lately, newest first
function BT.AdLog()
  local out = {}
  for i = #(ChainDB.adLog or {}), 1, -1 do
    table.insert(out, ChainDB.adLog[i])
  end
  return out
end

--------------------------------------------------------------------------
-- The roster
--------------------------------------------------------------------------
BT.rosterDirty = 0
function BT.TouchRoster() BT.rosterDirty = BT.rosterDirty + 1 end

-- Everyone we know of for a step: people you have run with, people who
-- advertised it, and people your friends told you about.
--------------------------------------------------------------------------
-- Your own list
--------------------------------------------------------------------------
-- Everything above arrives on its own. This is the part you write yourself:
-- a name you were given, with a note in your own words. Notes are never sent
-- anywhere - what travels between copies of the addon is measurements, and an
-- opinion about a stranger is not a measurement.
local function Clean(name)
  if type(name) ~= "string" then return nil end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return nil end
  name = BT.ShortName(name) or name
  -- the game capitalises names whatever you type, so the list should too,
  -- otherwise "algo" and "Algo" become two people
  return name:sub(1, 1):upper() .. name:sub(2):lower()
end

-- Anything that takes a name typed by a person needs the same treatment, so
-- "algo", "Algo" and "Algo-Firemaw" are one man and not three.
BT.CleanName = Clean

-- Add somebody by hand. `id` ties him to one instance; without it he shows up
-- under every instance, which is what you want for "sells everything".
-- Returns the stored name, or nil and why not.
function BT.AddBooster(name, note, id)
  name = Clean(name)
  if not name then return nil, "no name" end
  if name == BT.ShortName(UnitName("player") or "") then return nil, "that is you" end
  local info = BT.BoosterInfo(name)
  info.mine = true
  info.addedAt = info.addedAt or time()
  if note and note ~= "" then info.note = note end
  if id then
    info.zones = info.zones or {}
    info.zones[id] = true
  end
  BT.Touch()
  return name
end

function BT.SetBoosterNote(name, note)
  name = Clean(name)
  if not name then return nil end
  local info = BT.BoosterInfo(name)
  info.note = (note and note ~= "") and note or nil
  BT.Touch()
  return name
end

-- Drop somebody you added yourself. Runs you have done with him are history
-- and stay; this only removes the entry you typed.
function BT.ForgetBooster(name)
  local info = name and ChainDB.boosters[name]
  if not info then return false end
  info.mine, info.note, info.zones, info.addedAt = nil, nil, nil, nil
  if (info.price or 0) <= 0 and not info.shared and not info.adZone then
    ChainDB.boosters[name] = nil
  end
  BT.Touch()
  return true
end

function BT.Roster(id)
  local out, seen = {}, {}
  for _, b in ipairs(BT.BoosterTable(id)) do
    b.known = true
    seen[b.by] = b
    table.insert(out, b)
  end
  for name, info in pairs(ChainDB.boosters) do
    if not seen[name] then
      local mine = info.mine and (not info.zones or info.zones[id])
      local relevant = mine
        or ((info.price or 0) > 0)
        or (info.adZone == id and (info.adPrice or 0) > 0)
        or (info.shared and info.shared[id] ~= nil)
      if relevant then
        table.insert(out, {
          by = name, n = 0, rate = 0, perRun = 0, timePerRun = 0, mobs = 0,
          known = false, mine = info.mine and true or false
        })
      end
    end
  end
  -- measured first, then the rest by name, so the people you have actually
  -- run with are never pushed down the page by hearsay
  table.sort(out, function(a, b)
    if (a.n > 0) ~= (b.n > 0) then return a.n > 0 end
    if a.n > 0 then return a.rate > b.rate end
    return a.by < b.by
  end)
  return out
end

-- The price to show for a booster: yours, else his advert, else what a friend
-- told you. Returns gold per run and where it came from.
function BT.QuotedPrice(name, id)
  local b = name and ChainDB.boosters[name]
  if not b then return nil end
  if (b.price or 0) > 0 then
    -- his own pack if he has one, else whatever this instance is sold in
    local pack = ((b.pack or 0) > 0) and b.pack
      or BT.StepPack(id and BT.BY_ID and BT.BY_ID[id] or nil)
    return b.price / math.max(1, pack), "yours"
  end
  if (b.adPrice or 0) > 0 and (not id or b.adZone == id) then
    return b.adPrice / (((b.adPack or 0) > 0) and b.adPack or 1), "advert"
  end
  local s = id and BT.SharedStats(name, id)
  if s and s.price then return s.price, "reported" end
  return nil
end

--------------------------------------------------------------------------
-- Sharing
--------------------------------------------------------------------------
-- One booster and one instance per message, because 255 bytes does not go far
-- and a dropped message should cost one entry, not the whole batch.
-- Format: v2|name|instance|price|pack|xp per run|seconds per run|mobs|runs
local function Encode(name, id, b, st)
  return table.concat({ "v2", name, id,
    math.floor((b and b.price) or 0), math.floor((b and b.pack) or 0),
    math.floor((st and st.perRun) or 0), math.floor((st and st.timePerRun) or 0),
    math.floor((st and st.mobs) or 0), math.floor((st and st.n) or 0) }, "|")
end

function BT.ChannelIndex()
  if not GetChannelName then return nil end
  local id = GetChannelName(CHANNEL)
  if id and id > 0 then return id end
  return nil
end

function BT.JoinShareChannel()
  if not ChainDB.share then return end
  if BT.ChannelIndex() then return end
  if JoinTemporaryChannel then JoinTemporaryChannel(CHANNEL) end
  -- take it straight back out of the chat windows; it is not for reading
  local id = BT.ChannelIndex()
  if id and ChatFrame_RemoveChannel then
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
      local frame = _G["ChatFrame" .. i]
      if frame then ChatFrame_RemoveChannel(frame, CHANNEL) end
    end
  end
end

function BT.LeaveShareChannel()
  if BT.ChannelIndex() and LeaveChannelByName then LeaveChannelByName(CHANNEL) end
end

-- Who hears you. "all" is everyone running the addon, through a hidden
-- channel of its own; "guild" keeps it in the guild; "friends" whispers the
-- names you listed and nobody else. Receiving is unchanged - you hear whatever
-- reaches you - but this decides how far your own numbers travel.
local SCOPES = { "all", "guild", "friends" }
-- Short on purpose: this goes on a button 150 pixels wide, next to another
-- button, and "everyone with the addon" ran straight through both of them.
local SCOPE_NAMES = {
  all = "everyone",
  guild = "my guild",
  friends = "these names",
}

function BT.ShareScopeName()
  return SCOPE_NAMES[ChainDB.shareWith or "all"] or "everyone with the addon"
end

function BT.CycleShareScope()
  local cur = ChainDB.shareWith or "all"
  for i, s in ipairs(SCOPES) do
    if s == cur then
      ChainDB.shareWith = SCOPES[(i % #SCOPES) + 1]
      break
    end
  end
  if ChainDB.shareWith == "all" then BT.JoinShareChannel()
  else BT.LeaveShareChannel() end
end

function BT.SetShareFriends(text)
  local list = {}
  for name in tostring(text or ""):gmatch("[^,]+") do
    name = name:match("^%s*(.-)%s*$")
    if name ~= "" then table.insert(list, BT.ShortName(name)) end
  end
  ChainDB.shareFriends = list
end

function BT.StartSharing()
  if (ChainDB.shareWith or "all") == "all" then BT.JoinShareChannel() end
  BT.ShareAll()
end

function BT.StopSharing() BT.LeaveShareChannel() end

local function Post(msg, channel, target)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(PREFIX, msg, channel, target)
  elseif SendAddonMessage then
    SendAddonMessage(PREFIX, msg, channel, target)
  end
end

local function Send(msg)
  local scope = ChainDB.shareWith or "all"
  if scope == "guild" then
    if IsInGuild and not IsInGuild() then return false end
    Post(msg, "GUILD")
    return true
  elseif scope == "friends" then
    local list = ChainDB.shareFriends or {}
    if #list == 0 then return false end
    for _, name in ipairs(list) do Post(msg, "WHISPER", name) end
    return true
  end
  local id = BT.ChannelIndex()
  if not id then return false end
  Post(msg, "CHANNEL", id)
  return true
end

-- Everyone running the addon is in the channel, and that includes boosters.
-- A shared verdict is therefore public: treat it as something you would be
-- willing to say out loud, not a private note. Your own typed price and thumb
-- stay local until you turn sharing on.
--
-- Messages leave one at a time, seconds apart. Firing forty at once would be
-- dropped by the server's own throttle anyway, and a hundred people doing it
-- on login is exactly the sort of thing the add-on policy means by not
-- impacting the realm. Nothing here is urgent.
local queue, sending = {}, false
local GAP = 3

local function Pump()
  if #queue == 0 then sending = false return end
  if not ChainDB.share then queue, sending = {}, false return end
  local msg = table.remove(queue, 1)
  Send(msg)
  if C_Timer and C_Timer.After then
    C_Timer.After(GAP, Pump)
  else
    sending = false
  end
end

local function Queue(msg)
  -- never let the queue grow without bound; the newest view wins
  local key = msg:match("^v2|([^|]+|[^|]*)|")
  for i, m in ipairs(queue) do
    if key and m:match("^v2|([^|]+|[^|]*)|") == key then
      queue[i] = msg
      return
    end
  end
  if #queue >= 60 then return end
  table.insert(queue, msg)
  if not sending then
    sending = true
    -- wait before the first one too, so clicking a thumb twice while making
    -- up your mind sends one message rather than three
    if C_Timer and C_Timer.After then
      C_Timer.After(GAP, Pump)
    else
      Pump()
    end
  end
end

-- Everything you know first-hand: a price you were quoted, or runs you
-- actually did. Nothing derived from what somebody else told you, so hearsay
-- cannot bounce around the channel gathering weight.
function BT.ShareAll()
  if not ChainDB.share then return 0 end
  if (ChainDB.shareWith or "all") == "all" then BT.JoinShareChannel() end
  local n = 0
  local seen = {}
  for _, d in ipairs(BT.DUNGEONS) do
    for _, s in ipairs(BT.BoosterTable(d.id)) do
      Queue(Encode(s.by, d.id, ChainDB.boosters[s.by], s))
      seen[s.by .. "/" .. d.id] = true
      n = n + 1
    end
  end
  -- prices you typed for boosters you have not run with yet
  for name, b in pairs(ChainDB.boosters) do
    local id = b.adZone
    if (b.price or 0) > 0 and id and not seen[name .. "/" .. id] then
      Queue(Encode(name, id, b, nil))
      n = n + 1
    end
  end
  ChainDB.lastShare = time()
  return n
end

-- how many are still waiting to go out, for the settings panel
function BT.ShareQueued() return #queue end

-- Called when you change a price or a thumb. Batched, because the game
-- throttles addon messages and a rating is not urgent.
function BT.ShareOne(name, id)
  if not ChainDB.share or not name then return end
  local b = ChainDB.boosters[name]
  if not b then return end
  if not id then
    local _, step = BT.Stage()
    id = step and step.id or b.adZone
  end
  if not id then return end
  if (ChainDB.shareWith or "all") == "all" then BT.JoinShareChannel() end
  local st
  for _, s in ipairs(BT.BoosterTable(id)) do
    if s.by == name then st = s break end
  end
  Queue(Encode(name, id, b, st))
end

function BT.OnShare(msg, sender)
  if not ChainDB.share then return end
  if type(msg) ~= "string" then return end
  local v, name, id, price, pack, xp, t, mobs, n =
    msg:match("^(v%d)|([^|]+)|([^|]*)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)$")
  if v ~= "v2" or not name or name == "" then return end
  local from = BT.ShortName(sender)
  if from == BT.ShortName(UnitName("player")) then return end
  if not BT.BY_ID[id] then return end

  local b = BT.BoosterInfo(name)
  b.shared = b.shared or {}
  b.shared[id] = b.shared[id] or {}
  -- one record per reporter, replaced when they send a newer one
  b.shared[id][from] = {
    price = tonumber(price) or 0, pack = tonumber(pack) or 0,
    xp = tonumber(xp) or 0, t = tonumber(t) or 0,
    mobs = tonumber(mobs) or 0, n = tonumber(n) or 0, at = time()
  }
  BT.TouchRoster()
  if BT.RenderWindow then BT.RenderWindow() end
end

-- Everything other people reported about a booster in one instance, pooled.
-- Measurements are weighted by how many runs each report is based on, so one
-- person with thirty runs counts for more than one person with three.
function BT.SharedStats(name, id)
  local b = name and ChainDB.boosters[name]
  local per = b and b.shared and b.shared[id]
  if not per then return nil end
  local xp, t, mobs, runs, price, prices, people = 0, 0, 0, 0, 0, 0, 0
  for _, r in pairs(per) do
    people = people + 1
    local w = math.max(1, r.n or 0)
    xp = xp + (r.xp or 0) * w
    t = t + (r.t or 0) * w
    mobs = mobs + (r.mobs or 0) * w
    runs = runs + w
    if (r.price or 0) > 0 then
      price = price + r.price / (((r.pack or 0) > 0) and r.pack or 1)
      prices = prices + 1
    end
  end
  if people == 0 then return nil end
  return {
    people = people, runs = runs,
    perRun = (runs > 0) and (xp / runs) or 0,
    timePerRun = (runs > 0) and (t / runs) or 0,
    mobs = (runs > 0) and (mobs / runs) or 0,
    price = (prices > 0) and (price / prices) or nil
  }
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------
local f = CreateFrame("Frame", "ChainRosterFrame")
BT.rosterFrame = f

function BT.OnRosterEvent(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    local prefix, msg, _, sender = ...
    if prefix == PREFIX then BT.OnShare(msg, sender) end
    return
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- channels are not available the instant you log in
    if C_Timer and C_Timer.After then
      C_Timer.After(8, BT.JoinShareChannel)
    else
      BT.JoinShareChannel()
    end
    return
  end
  local msg, sender = ...
  local source = "say"
  if event == "CHAT_MSG_CHANNEL" then
    -- ... msg, sender, language, channelString, target, flags, zoneID,
    -- channelNumber, channelName
    local _, _, _, cstring, _, _, _, number, cname = ...
    local chan = cname or cstring
    if BT.OwnChannel(chan) then return end
    source = BT.ChannelKey(chan) or ("channel:" .. tostring(number or "?"))
  elseif event == "CHAT_MSG_YELL" then source = "yell"
  elseif event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then source = "guild"
  elseif event == "CHAT_MSG_WHISPER" then source = "whisper"
  elseif event ~= "CHAT_MSG_SAY" then source = "party"
  end
  BT.NoteAd(msg, sender, source)
  -- the same line, read the other way: a sale is not a group and a group is
  -- not a sale, so one of the two keeps it and the other throws it away
  BT.NoteGroup(msg, sender, source)
end

f:SetScript("OnEvent", BT.OnRosterEvent)
-- Every channel the game will tell us about. A booster's price reaches you in
-- whichever one he is shouting in, and as often as not in a whisper.
for _, e in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL",
                     "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER",
                     "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
                     "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
                     "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
                     "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD" }) do
  f:RegisterEvent(e)
end
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
elseif RegisterAddonMessagePrefix then
  RegisterAddonMessagePrefix(PREFIX)
end
