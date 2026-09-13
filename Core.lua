-- Chain: the live half. Watches the game, decides when a run starts
-- and ends, and writes one record per finished run into the log.

local ADDON, BT = ...
local K = BT.K

BT.CHAR_DEFAULTS = {
  run = nil,          -- the run in progress
  session = nil,      -- this stint's experience
  entrySeq = 0,
  instId = {},        -- last known instance id per zone (legacy)
  seenInst = {},      -- every instance id entered lately, and when
  buckets = {},       -- experience per minute, for xp/h
  lastBy = nil,       -- the booster you last ran with
  lastZone = nil,
  lastEnd = nil,
  lastGain = nil,
  levelAt = nil,      -- when this level started, for "this level 15m"
  resetAt = nil, resetZone = nil, resetBy = nil
}

local frame = CreateFrame("Frame", "ChainFrame")
BT.frame = frame

--------------------------------------------------------------------------
-- Small helpers over the live game state
--------------------------------------------------------------------------
-- Returns the zone name and, more importantly, the instance id. The id is
-- what actually identifies a dungeon; the name is localised and Blizzard
-- renames places under us.
function BT.InDungeon()
  local inside, kind = IsInInstance()
  if not inside then return nil end
  if kind ~= "party" and kind ~= "raid" then return nil end
  local zone, map
  if GetInstanceInfo then
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    if name and name ~= "" then zone = name end
    map = tonumber(instanceID)
  end
  if not zone or zone == "" then zone = GetRealZoneText() end
  if not zone or zone == "" then zone = GetZoneText() end
  if not zone or zone == "" then return nil end
  return zone, map
end

function BT.CurrentZone()
  local c = ChainCharDB
  if c.run then return c.run.zone, c.run.map end
  return c.lastZone, c.lastMap
end

-- A dungeon run is not automatically a boost. A normal group is people within
-- a few levels of each other; a boost is somebody far above you doing the
-- killing. Highest level wins, and group leadership only breaks a tie between
-- equals - the leader is often a boostie, not the booster.
function BT.Booster()
  if not (IsInGroup and IsInGroup()) then return nil end
  if not (UnitExists and UnitName) then return nil end
  local my = UnitLevel("player") or 0
  local name, level, isLead
  for i = 1, 4 do
    local u = "party" .. i
    if UnitExists(u) then
      local lvl = UnitLevel(u) or 0
      local lead = UnitIsGroupLeader and UnitIsGroupLeader(u) or false
      if lvl >= my + K.BOOST_GAP then
        if not level or lvl > level or (lvl == level and lead and not isLead) then
          level, name, isLead = lvl, UnitName(u), lead
        end
      end
    end
  end
  -- Through the same cleaner every typed name goes through. The run log used
  -- to keep the client's raw spelling while the trade log kept the cleaned
  -- one, and the two are compared with a plain equals - so a booster called
  -- CartEr was two different people to the addon, his runs counted for one
  -- and his gold for the other, and the balance never moved.
  return name and ((BT.CleanName and BT.CleanName(name)) or BT.ShortName(name))
    or nil
end

-- Who is boosting right now, for stats purposes
function BT.CurrentBooster()
  local c = ChainCharDB
  if c.run then return c.run.by end
  -- outside a run: whoever is in the group now, else the last one you ran
  -- with, so the plan you look at in town is still priced for him
  return BT.Booster() or c.lastBy
end

-- Are we boosting right now? Inside a run it is whatever the run started as;
-- in a group it is the group; on your own it is the route, which is planned
-- and priced as a boost.
-- Everybody you could plausibly be handing gold to right now: the group you
-- are standing in, whoever you last ran with, and whoever you have traded
-- lately. A name is a thing you should never have to type - half of them are
-- Zånzå and Cartèr, and getting the accents right from a screenshot is not a
-- task an addon should be setting you.
function BT.PayableNames()
  local out, seen = {}, {}
  local me = UnitName and UnitName("player") or nil
  local function add(name, why)
    if not name or name == "" then return end
    name = BT.ShortName(name) or name
    if name == me or seen[name] then return end
    seen[name] = true
    out[#out + 1] = { name = name, why = why }
  end

  -- the group first, because that is who is in front of you
  if IsInGroup and IsInGroup() and UnitExists then
    local party = (IsInRaid and IsInRaid()) and "raid" or "party"
    local size = (party == "raid") and 40 or 4
    for i = 1, size do
      local u = party .. i
      if UnitExists(u) then
        local lvl = UnitLevel(u) or 0
        add(UnitName(u), (lvl > 0) and ("in your group, " .. lvl) or "in your group")
      end
    end
  end
  local by = BT.CurrentBooster and BT.CurrentBooster()
  if by then add(by, "the booster") end
  -- then anybody you have handed something to lately
  local trades = ChainDB.trades or {}
  for i = #trades, math.max(1, #trades - 40), -1 do
    local t = trades[i]
    if t and t.with then add(t.with, "traded before") end
  end
  return out
end

function BT.CurrentBoost()
  local c = ChainCharDB
  if c.run then return c.run.by ~= nil end
  if IsInGroup and IsInGroup() then return BT.Booster() ~= nil end
  return true
end

-- Which step a run here belongs to. Several steps can share one instance
-- (the three wings of Dire Maul), so the step you are on wins if it matches.
function BT.StepFor(map, zone)
  local list = BT.DungeonsFor(map, zone)
  if not list or not list[1] then return nil end
  local _, e = BT.Stage()
  if e then
    for _, d in ipairs(list) do
      if d.id == e.id then return e.id end
    end
  end
  return list[1].id
end

--------------------------------------------------------------------------
-- Experience accounting
--------------------------------------------------------------------------
-- Remember what this client says a level costs, and say something once if it
-- disagrees with the built-in table - that means the forecast for levels you
-- have not reached yet is an estimate until you get there.
function BT.LearnXP()
  local lvl, mx = UnitLevel("player"), UnitXPMax("player")
  if not lvl or not mx or mx <= 0 or lvl >= BT.MAX_LEVEL then return end
  if ChainDB.xpReal[lvl] == mx then BT.pendingXP = nil return end
  -- At the moment you level, the client can report the new level while the
  -- bar still holds the old maximum. Waiting for the same pair twice means we
  -- never write down that half-updated state.
  local p = BT.pendingXP
  if not p or p.lvl ~= lvl or p.mx ~= mx then
    BT.pendingXP = { lvl = lvl, mx = mx }
    return
  end
  BT.pendingXP = nil
  ChainDB.xpReal[lvl] = mx
  local book = BT.XP[lvl]
  if book and book > 0 and math.abs(mx / book - 1) > 0.02 and not BT.warnedXP then
    BT.warnedXP = true
    print(BT.COL.warn .. BT.NAME .. ":|r this client's experience table is not "
      .. "the one built in (level " .. lvl .. " wants " .. BT.N(mx) .. ", not "
      .. BT.N(book) .. "). Forecasts past your current level are estimates "
      .. "until it has seen those levels.")
  end
end

function BT.Delta()
  local c = ChainCharDB
  local xp, mx = UnitXP("player") or 0, UnitXPMax("player") or 0
  local last, lastMax = c.lastXP, c.lastMax
  c.lastXP, c.lastMax = xp, mx
  if not last then return 0 end
  if mx ~= lastMax then
    -- levelled: the rest of the old bar plus whatever is on the new one
    return math.max(0, (lastMax or 0) - last) + xp
  end
  return math.max(0, xp - last)
end

function BT.AddXP(d)
  if not d or d <= 0 then return end
  local c = ChainCharDB
  local m = math.floor(time() / 60)
  c.buckets[tostring(m)] = (c.buckets[tostring(m)] or 0) + d
  for key in pairs(c.buckets) do
    local km = tonumber(key)
    if not km or km < m - 59 then c.buckets[key] = nil end
  end
  -- a long gap ends the session the same way logging out does
  if not c.session or (c.lastGain and (time() - c.lastGain) > K.SESSION_GAP) then
    c.session = { start = time(), xp = 0 }
  end
  c.session.xp = (c.session.xp or 0) + d
  c.lastGain = time()
end

-- Minutes since the last experience gain, nil if none in the last hour
function BT.IdleMin()
  local c = ChainCharDB
  local m, last = math.floor(time() / 60), nil
  for key in pairs(c.buckets) do
    local km = tonumber(key)
    if km and km >= m - 59 and km <= m and (not last or km > last) then last = km end
  end
  if not last then return nil end
  return m - last
end

-- Experience per hour over the last hour. Breaks up to five minutes do not
-- count against you, but a long silence means there is no rate to report -
-- better no number than one claiming you ding in five minutes at the mailbox.
function BT.Rate()
  local c = ChainCharDB
  local m = math.floor(time() / 60)
  local mins, total = {}, 0
  for key, v in pairs(c.buckets) do
    local km = tonumber(key)
    if km and km >= m - 59 and km <= m then
      table.insert(mins, km)
      total = total + v
    end
  end
  if total <= 0 or #mins == 0 then return nil end
  table.sort(mins)
  local elapsed = 1
  for i = 2, #mins do
    local gap = mins[i] - mins[i - 1]
    if gap > 5 then gap = 5 end
    elapsed = elapsed + gap
  end
  -- How long a silence is allowed before there is no rate to report. In a
  -- group it is ten minutes: a gap that long is a reset, a summon, or waiting
  -- on somebody. On your own it is five, because on your own a gap that long
  -- is you not being there, and a rate that keeps counting while you are at
  -- the mailbox is a rate that says you ding in five minutes.
  local cut = (IsInGroup and IsInGroup()) and K.IDLE_MIN or K.IDLE_SOLO
  local tail = m - mins[#mins]
  if tail > cut then return nil end
  if tail > 5 then tail = 5 end
  elapsed = elapsed + tail
  if elapsed < 1 then return nil end
  return total / elapsed * 60
end

--------------------------------------------------------------------------
-- Quests ready to hand in
--------------------------------------------------------------------------
-- A quest you have outlevelled is grey in the log and worth nothing to hand
-- in. Counting it told you there were four quests waiting and a level's worth
-- of experience in your bag when there were two and half that - which is the
-- sort of wrong that makes you plan around it.
--
-- The client knows where grey begins: GetQuestGreenRange is the number of
-- levels below you that still count as green, and grey starts one below that.
-- Where the call is missing, the table falls back on the same thresholds the
-- experience decay already uses.
function BT.QuestGrey(questLevel)
  if not questLevel or questLevel <= 0 then return false end
  local lvl = UnitLevel("player") or 1
  if GetQuestGreenRange then
    local range = GetQuestGreenRange()
    if range and range > 0 then return questLevel < (lvl - range) end
  end
  -- no such call on this client: the same threshold the experience decay uses
  return questLevel <= (BT.GreyLevel and BT.GreyLevel(lvl) or (lvl - 6))
end

function BT.ScanQuests()
  if not (GetNumQuestLogEntries and GetQuestLogTitle) then return end
  local now = time()
  if BT.questScan and (now - BT.questScan) < 2 then return end
  BT.questScan = now
  local total, count, grey = 0, 0, 0
  local n = GetNumQuestLogEntries()
  local selected = GetQuestLogSelection and GetQuestLogSelection() or nil
  for i = 1, n do
    local title, qLevel, _, isHeader, _, isComplete = GetQuestLogTitle(i)
    if title and not isHeader and isComplete == 1 then
      if BT.QuestGrey(qLevel) then
        -- counted separately: it is still a quest you can hand in, it is
        -- just not experience, and the difference is the whole point
        grey = grey + 1
      else
        count = count + 1
        if SelectQuestLogEntry and GetQuestLogRewardXP then
          SelectQuestLogEntry(i)
          total = total + (GetQuestLogRewardXP() or 0)
        end
      end
    end
  end
  if selected and SelectQuestLogEntry then SelectQuestLogEntry(selected) end
  BT.questXP, BT.questCount, BT.questGrey = total, count, grey
end

--------------------------------------------------------------------------
-- Instance identity and the five-per-hour limit
--------------------------------------------------------------------------
-- Creature-0-<server>-<instanceID>-<zoneUID>-<npc>-<spawn>
--
-- Which of fields four and five is the map and which is this particular copy
-- of it is documented one way round and used the other way round by every
-- addon that actually counts instances - Nova reads field five, and real
-- GUIDs back it: a Shadowfang mob comes back
-- Creature-0-4672-33-573-3849-..., and 33 is Shadowfang Keep's map id in
-- every copy of it that has ever existed, so field four cannot be the copy.
--
-- We take both. The pair is unique per copy whichever way round the two are,
-- which is the only way to be right without betting on the documentation. We
-- had field four alone, which meant the second Stockade of the day looked
-- like walking back into the first: it was marked a re-entry, dropped from
-- the log, and never counted against the five an hour.
--
-- Scarlet Monastery is the case that makes this matter. A boost there is
-- several instances in a row behind one zone name, and until one is reset
-- walking back into it is not a new one. Same pair, same instance.
function BT.InstIdFrom(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, map, uid = strsplit("-", guid)
  if kind ~= "Creature" and kind ~= "Vehicle" and kind ~= "GameObject" then
    return nil
  end
  if not map or map == "" or map == "0" then return nil end
  if not uid or uid == "" or uid == "0" then return nil end
  return map .. ":" .. uid, map, uid
end

-- Write an instance id onto the run in progress and do the counting that goes
-- with it. Split out so the two callers below - a run that has just started,
-- and a run that turns out to have walked into a different instance - share
-- one set of bookkeeping.
local function Record(r, id)
  local c = ChainCharDB
  r.instId = id

  -- Every instance we have been in lately, not just the last one per zone.
  -- Scarlet Monastery is four separate instances behind one name, and a
  -- Cathedral + Armory chain has two of them alive at the same time: with one
  -- slot per zone, walking back into the Cathedral looked like a new instance
  -- and the hourly count ran ahead of the truth.
  c.seenInst = c.seenInst or {}
  local now = time()
  for key, when in pairs(c.seenInst) do
    if now - when > 86400 then c.seenInst[key] = nil end
  end
  local before = c.seenInst[id]
  c.seenInst[id] = now
  c.instId[r.zone] = id                      -- kept for the older readers
  if before then
    -- walked back into an instance we already counted: it is not a new one
    r.reentry = true
    BT.DropEntry(r.entrySeq)
    r.entrySeq = nil
    -- Say so. The count moves twice on the way in - up when you zone, back
    -- down when the mobs prove it is the one you were just in - and a number
    -- that corrects itself in silence is a number you end up arguing with.
    -- Nova says both halves out loud and that is exactly why it is possible
    -- to check.
    BT.SayCount("same instance as the last one", true, id)
  else
    -- Confirmed the other way: the mobs say this is an instance we have not
    -- been in. The zone-in already counted it; this is the line that says so
    -- with the id on it, which is the difference between a number you can
    -- trace and a number you can only argue with.
    BT.SayCount("confirmed a different instance", false, id)
  end
end

-- One line in chat when the count moves, and only when it moves. At most a
-- handful an hour, which is the whole point: you can read back what it
-- thought and when, instead of watching a number and guessing.
function BT.SayCount(why, merged, id)
  if ChainDB.sayCount == false then return end
  local count = BT.Lockout()
  local limit = ChainDB.limit or K.LIMIT
  local C = BT.COL
  -- The instance id goes on the line. It is the one thing that says whether
  -- a count was a genuinely different instance or the same one seen twice,
  -- and without it a wrong number can only be argued about rather than
  -- traced.
  print((merged and C.dim or C.info) .. BT.NAME .. ":|r " .. why
    .. C.dim .. "  -  " .. count .. "/" .. limit .. " this hour"
    .. (id and ("  [" .. id .. "]") or "") .. C.off)
end

-- Scarlet Monastery is the reason this needs saying.
--
-- A run starts when the zone name changes, and in Scarlet Monastery it does
-- not: all four wings report "Scarlet Monastery". The obvious move is to
-- watch the mob ids and split the run when one stops matching - and that is
-- exactly what must not be done. It was tried, and the bar went to 6/5: a
-- number the game will not give you, so whatever it counted was not an
-- instance. Nova does not do it either; it uses the mob id only to decide
-- whether a run that has just STARTED is really the previous one carrying on,
-- never to end one that is in progress.
--
-- So the id is written once, when the run begins, and after that the run
-- keeps it. The thing that actually was wrong - a new instance being filed as
-- a return to the old one - is handled where it happens: in StartRun, which
-- refuses to read an id off a corpse.
function BT.NoteInstance(guid)
  local c = ChainCharDB
  local r = c.run
  if not r or r.instId then return end
  local id = BT.InstIdFrom(guid)
  if not id then return end
  Record(r, id)
end

-- The game enforces five an hour. If our arithmetic says six, our arithmetic
-- is wrong - there is no sixth to have - so something in the log is not an
-- instance we actually entered.
--
-- Guesses go first, and only guesses. A ghost is something the game told us
-- about and we never saw; a reconciled entry is one we rebuilt from the run
-- log because the instance-identity bug had deleted it, and that rebuild
-- deliberately ignored a re-entry flag it could not trust - so some of what
-- it put back was a genuine re-entry that should never have counted. This is
-- where that is paid for. Entries we actually watched happen are left alone,
-- and the count is reported at the limit rather than above it.
--
-- Oldest guess first, so what survives is the most recent one.
function BT.TrimOverCount()
  local limit = ChainDB.limit or K.LIMIT
  local over = BT.Lockout() - limit
  if over <= 0 then return 0 end
  local hour = time() - 3600
  local gone = 0
  for _, kind in ipairs({ "ghost", "fromRun" }) do
    for i = 1, #ChainDB.entries do
      if over <= 0 then break end
      local e = ChainDB.entries[i]
      if e and e[kind] and not e.dropped and (e.t or 0) > hour then
        e.dropped, e[kind] = true, nil
        over, gone = over - 1, gone + 1
      end
    end
  end
  for i = #ChainDB.entries, 1, -1 do
    if ChainDB.entries[i].dropped then table.remove(ChainDB.entries, i) end
  end
  if gone > 0 and BT.SayCount then
    BT.SayCount("dropped " .. gone .. " I could not have been right about",
                true)
  end
  return gone
end

-- The hourly cap is per character but the daily one is per account, so the
-- log lives account-wide and every entry remembers who walked in.
-- Two zone-ins within a few seconds cannot both be instance entries. Leaving
-- an instance and getting back into a fresh one is two loading screens and a
-- reset in between; the game will not do that in ten seconds, whatever the
-- zone events say. So a second entry that close to the last one is the same
-- arrival reported twice - a loading screen that announced the world again, a
-- wing transition - and it is thrown away rather than counted.
--
-- This is a statement about the game rather than a guess about the cause: it
-- cannot discard a real entry, because a real one cannot be there.
local DOUBLE = 10

-- A loading screen is not a doorway. The client announces the world again
-- after a reload, and it can do so before it admits to being in an instance -
-- so the run can be ended and restarted a moment later, which is a new entry
-- for something that never happened.
-- Fifteen seconds, and only for a run that was actually in progress when the
-- reload hit. The first version asked whether the last zone matched, which is
-- still true half a minute after you have walked out of the place - so a
-- reload in town followed by walking into the instance had its entry thrown
-- away, and the count sat one short for the rest of the hour.
--
-- What this is for is narrow: the client announcing the world before it will
-- admit to being in an instance, so the run goes missing across the loading
-- screen and Sync starts another. Anything wider than that eats real entries.
local RELOAD_GRACE = 15

function BT.NoteEntry()
  local c = ChainCharDB
  local me = UnitName("player")
  local zone = BT.InDungeon()

  if (time() - (BT.reloadedAt or 0)) < RELOAD_GRACE
     and zone and BT.reloadRunZone == zone then
    if BT.SayCount then
      BT.SayCount("back from a reload - the same instance, not a new one",
                  true, zone)
    end
    return nil
  end

  local last = ChainDB.entries[#ChainDB.entries]
  if last and last.char == me and (time() - (last.t or 0)) < DOUBLE then
    if BT.SayCount then
      BT.SayCount("the same arrival twice - not counting it again", true, zone)
    end
    return last.seq
  end

  c.entrySeq = (c.entrySeq or 0) + 1
  local seq = me .. ":" .. c.entrySeq
  table.insert(ChainDB.entries, { t = time(), seq = seq,
                                         zone = zone,
                                         char = me })
  -- a day of the account-wide cap, with room to spare
  while #ChainDB.entries > 200 do table.remove(ChainDB.entries, 1) end

  -- The game just let us in, so we were not at the limit - whatever we
  -- thought. Refusal adds the instances it has seen and we have not; getting
  -- through the door is the same evidence pointing the other way, and without
  -- it those guesses sit in the count for a full hour and the bar climbs to
  -- 7/5, which is a number the game will not give you.
  BT.TrimOverCount()
  if BT.SayCount then
    BT.SayCount("new instance" .. (zone and (" - " .. zone) or ""))
  end
  -- the entry that takes you to the limit is the one the group needs to hear
  -- about, and the moment you zone in is when they are still deciding
  if BT.AnnounceLock then BT.AnnounceLock() end
  return seq
end

-- Called from the bar's own timer, a few times a minute. The lockout expires
-- on a clock nobody is watching, so somebody has to look.
local lastLockCheck = 0
function BT.PollLock()
  local now = time()
  if now - lastLockCheck < 5 then return end
  lastLockCheck = now
  -- Standing outside at a count that cannot be true is the one case zoning in
  -- will never fix, because you will not try: the bar says the door is shut.
  -- So the trimming cannot wait for a zone-in to happen.
  BT.DedupeEntries()
  BT.TrimOverCount()
  BT.AnnounceLock()
end

-- Two entries for the same instance with no reset between them.
--
-- This one came out of the log rather than out of my head. The Instances tab
-- showed two "entered SM" a minute apart at the same moment, nothing between
-- them, and the hour read 7/5 - a number the game does not hand out. One
-- arrival, reported twice.
--
-- The reset log is what makes this safe to act on. A second entry into the
-- same instance is only a second instance if somebody reset it in between -
-- that is the whole mechanic - so two entries with no reset recorded between
-- them cannot both be real, however far apart the clock says they are. The
-- time window is only a guard against acting on a gap so wide that a missed
-- reset is the likelier explanation.
local DUP_WINDOW = 120

local function ResetBetween(from, to, zone)
  for _, r in ipairs(ChainDB.resets or {}) do
    local at = r.at or 0
    if at > from and at <= to then
      if not zone or not r.zone or r.zone == zone
         or (BT.Short and BT.Short(r.zone) == BT.Short(zone)) then
        return true
      end
    end
  end
  return false
end

function BT.DedupeEntries()
  local list = ChainDB.entries
  if not list or #list < 2 then return 0 end
  -- the walk below reads the log forwards in time, so make sure it is: a log
  -- merged from an older addon or from NIT can arrive in any order, and a
  -- backwards pair would compare as a negative gap and collapse everything
  table.sort(list, function(a, b) return (a.t or 0) < (b.t or 0) end)
  local gone = 0
  for i = #list, 2, -1 do
    local e, prev = list[i], list[i - 1]
    if e and prev and e.char == prev.char
       and (e.zone or "?") == (prev.zone or "?")
       and (e.t or 0) - (prev.t or 0) >= 0
       and (e.t or 0) - (prev.t or 0) <= DUP_WINDOW
       and not ResetBetween(prev.t or 0, e.t or 0, e.zone) then
      table.remove(list, i)
      gone = gone + 1
    end
  end
  if gone > 0 and BT.SayCount then
    BT.SayCount("dropped " .. gone .. " duplicate arrival"
      .. ((gone == 1) and "" or "s") .. " - no reset between them", true)
  end
  return gone
end

-- Nova puts a small red X on its "new instance" line, because a zone-in is
-- the only evidence it has at that moment and a zone-in can be wrong: a wing
-- transition, a loading screen that reports the world twice. This is the same
-- escape hatch. It takes back the newest entry of this hour, which is the one
-- that has just appeared wrongly, and says what it removed.
function BT.NotANewInstance()
  local hour = time() - 3600
  local me = UnitName and UnitName("player") or nil
  for i = #ChainDB.entries, 1, -1 do
    local e = ChainDB.entries[i]
    if e and (e.t or 0) > hour and (e.char == nil or e.char == me) then
      table.remove(ChainDB.entries, i)
      local r = ChainCharDB.run
      if r and r.entrySeq == e.seq then
        r.entrySeq, r.reentry = nil, true
      end
      if BT.SayCount then
        BT.SayCount("taken back - not a new instance", true, e.zone)
      end
      if BT.Refresh then BT.Refresh() end
      if BT.RenderWindow then BT.RenderWindow() end
      return e
    end
  end
  return nil
end

function BT.DropEntry(seq)
  if not seq then return end
  local list = ChainDB.entries
  for i = #list, 1, -1 do
    if list[i].seq == seq then table.remove(list, i) return end
  end
end

--------------------------------------------------------------------------
-- Nova Instance Tracker: borrowed from, never depended on
--------------------------------------------------------------------------
-- The one thing NIT has that we cannot is the entries from before this addon
-- was installed. So we take them, once, into our own log - rather than
-- reading its data every time and being useless the day it is uninstalled.
--
-- Everything after that is ours: we see every zone-in ourselves. Running the
-- import again is safe, because an entry already in the log is recognised by
-- when it happened and who it happened to.
-- Every reset we were told about, newest first
function BT.ResetLog(sinceHours)
  local out = {}
  local cut = sinceHours and (time() - sinceHours * 3600) or nil
  for i = #(ChainDB.resets or {}), 1, -1 do
    local r = ChainDB.resets[i]
    if not cut or (r.at or 0) >= cut then table.insert(out, r) end
  end
  return out
end

function BT.ImportNIT()
  local NIT = _G.NIT
  if not NIT or not NIT.data or not NIT.data.instances then return 0 end
  local have = {}
  for _, e in ipairs(ChainDB.entries) do
    -- to the minute: two clocks agreeing to the second is not something to
    -- rely on, and nobody enters two instances in the same minute twice
    have[(e.char or "?") .. ":" .. math.floor((e.t or 0) / 60)] = true
  end
  local added = 0
  for _, inst in ipairs(NIT.data.instances) do
    local t = tonumber(inst.enteredTime)
    local who = inst.playerName or UnitName("player")
    if t and t > 0 then
      local key = (who or "?") .. ":" .. math.floor(t / 60)
      if not have[key] then
        have[key] = true
        added = added + 1
        table.insert(ChainDB.entries, {
          t = t, seq = "nit:" .. t .. ":" .. tostring(who),
          zone = inst.zone or inst.instanceName, char = who, from = "NIT"
        })
      end
    end
  end
  if added > 0 then
    table.sort(ChainDB.entries, function(a, b) return (a.t or 0) < (b.t or 0) end)
    while #ChainDB.entries > 400 do table.remove(ChainDB.entries, 1) end
    -- NIT's clock and ours are not the same clock, so its rows can land beside
    -- our own for the same arrival. The same rule sorts it out.
    if BT.DedupeEntries then BT.DedupeEntries() end
  end
  return added
end

-- Every instance entry we know of, newest first, each with how long until it
-- stops counting against the five per hour. Our own log: NIT's history was
-- copied into it once, and everything since we saw ourselves.
function BT.InstanceLog()
  local out = {}
  for _, e in ipairs(ChainDB.entries) do
    table.insert(out, { t = e.t, zone = e.zone, char = e.char, nit = e.from == "NIT" })
  end
  table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
  local now = time()
  for _, e in ipairs(out) do
    local age = now - (e.t or now)
    e.age = age
    e.left = (age < 3600) and (3600 - age) or 0
    e.counts = age < 3600
  end
  return out
end

-- The run log is better evidence than the entry log, and for a while it was
-- the only honest one. A recorded run is proof you were inside; an entry is
-- only a note we made on the way in, and the instance-identity bug quietly
-- deleted most of them as false re-entries. So: every run with no entry
-- anywhere near it gets one. It costs a pass over two lists that are already
-- in time order, and it is what makes a log that says 2/5 next to nine runs
-- in the last hour add up again.
--
-- Runs already known to be re-entries are left alone - they did not count at
-- the time and they do not count now.
function BT.ReconcileEntries(window, trustReentry)
  if trustReentry == nil then trustReentry = true end
  window = window or 86400
  local cut = time() - window
  local entries, runs = ChainDB.entries or {}, ChainDB.runs or {}
  local added = 0
  local c = ChainCharDB
  for _, r in ipairs(runs) do
    local at = r.at or 0
    if at >= cut and r.id and not (trustReentry and r.reentry) then
      local found = false
      for _, e in ipairs(entries) do
        -- The entry is written as the run starts, so they share a moment.
        -- A missing name on either side matches anything: records from the
        -- older addons carry no character, and a nil that only ever equals
        -- another nil would put a second entry beside every one of them.
        local sameWho = (e.char == nil) or (r.char == nil) or (e.char == r.char)
        if sameWho and math.abs((e.t or 0) - at) <= 120 then
          found = true
          break
        end
      end
      if not found then
        c.entrySeq = (c.entrySeq or 0) + 1
        table.insert(entries, {
          t = at, seq = (r.char or "?") .. ":r" .. c.entrySeq,
          zone = r.zone, char = r.char, fromRun = true
        })
        added = added + 1
      end
    end
  end
  if added > 0 then
    table.sort(entries, function(a, b) return (a.t or 0) < (b.t or 0) end)
    while #entries > 200 do table.remove(entries, 1) end
    ChainDB.entries = entries
  end
  return added
end

-- Reading NIT's count live, for anyone who would rather trust it than us.
-- Off by default: our own log is complete once its history has been imported,
-- and an addon that stops working when another one is uninstalled is not
-- something to build on.
function BT.NITLockout()
  if not ChainDB.useNIT then return nil end
  local NIT = _G.NIT
  if not NIT or not NIT.data or not NIT.data.instances then return nil end
  local hour, day = time() - 3600, time() - 86400
  local count, oldest, newest, daily = 0, nil, nil, 0
  for _, inst in ipairs(NIT.data.instances) do
    local t = tonumber(inst.enteredTime)
    if t and t > day then daily = daily + 1 end
    if t and t > hour then
      count = count + 1
      if not oldest or t < oldest then oldest = t end
      if not newest or t > newest then newest = t end
    end
  end
  return count, oldest, newest, daily
end

-- Returns: hourly count for this character, seconds until one frees up,
-- seconds until all free, whether it came from NIT, and the account-wide
-- count for the last 24 hours.
function BT.Lockout()
  local nitCount, nitOldest, nitNewest, nitDaily = BT.NITLockout()
  local count, oldest, newest, daily
  local ghosts = 0
  if nitCount then
    count, oldest, newest, daily = nitCount, nitOldest, nitNewest, nitDaily
  else
    local hour, day = time() - 3600, time() - 86400
    local me = UnitName("player")
    count, daily = 0, 0
    for _, e in ipairs(ChainDB.entries) do
      local t = e.t or 0
      -- the daily cap counts every character on the account
      if t > day then daily = daily + 1 end
      -- the hourly one only counts this character
      if t > hour and (e.char == nil or e.char == me) then
        count = count + 1
        if e.ghost then ghosts = ghosts + 1 end
        if not oldest or t < oldest then oldest = t end
        if not newest or t > newest then newest = t end
      end
    end
  end
  -- The game's own refusal beats our arithmetic, and it is already in the
  -- count: being told "too many instances" writes the instances we never saw
  -- into the log as entries of their own (see BT.NoteLockedOut). They are
  -- entries like any other, so counting, expiry and the two clocks below all
  -- work on them without a special case.
  --
  -- It used to be a number added on top instead, and that was wrong twice
  -- over. The correction was a snapshot: once our own counting caught up, it
  -- was still being added, which is how the bar reached 7/5 - a number the
  -- game will not let you have. And it moved `oldest` forward to the moment
  -- of the refusal, which could put it after `newest`, which is how "one free
  -- in 58m" ended up below a line saying they were all free in 47m.
  local fromGame = ghosts > 0
  if count == 0 then return 0, nil, nil, nitCount ~= nil, daily, false end
  local freeOne = oldest and math.max(0, 3600 - (time() - oldest)) or nil
  local freeAll = newest and math.max(0, 3600 - (time() - newest)) or nil
  return count, freeOne, freeAll, nitCount ~= nil, daily, fromGame
end

--------------------------------------------------------------------------
-- Reset detection
--------------------------------------------------------------------------
-- Built from the client's own strings so it works on any locale
local function Pattern(str)
  if type(str) ~= "string" then return nil end
  local p = str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  return "^" .. p:gsub("%%%%s", "(.+)") .. "$"
end

local resetPattern = Pattern(INSTANCE_RESET_SUCCESS)
-- A reset that did not happen is worth knowing about too. Standing at the
-- portal wondering why nothing is happening is the single most common way to
-- lose a few minutes in a boost chain, and the game already tells you why.
local failPatterns = {
  { Pattern(INSTANCE_RESET_FAILED), "someone is still inside" },
  { Pattern(INSTANCE_RESET_FAILED_ZONING), "someone is zoning in" },
  { Pattern(INSTANCE_RESET_FAILED_OFFLINE), "someone is offline" }
}

-- A reset means one of two opposite things depending on which side of the
-- portal you are standing on, and the whole point of a sound is that you do
-- not have to look. So there are two of them, and they are deliberately not
-- alike: the "get out" one is the urgent one.
BT.SOUNDS = {
  { key = "warning",  label = "Raid warning",
    kit = "RAID_WARNING",      file = "Sound\\Interface\\RaidWarning.ogg" },
  { key = "ready",    label = "Ready check",
    kit = "READY_CHECK",       file = "Sound\\Interface\\ReadyCheck.ogg" },
  { key = "levelup",  label = "Level up",
    kit = "UI_LEGENDARY_LOOT_TOAST",
    file = "Sound\\Interface\\LevelUp.ogg" },
  { key = "alarm",    label = "Alarm clock",
    kit = "ALARM_CLOCK_WARNING_3",
    file = "Sound\\Interface\\AlarmClockWarning3.ogg" },
  { key = "bell",     label = "Auction bell",
    kit = "AUCTION_WINDOW_OPEN",
    file = "Sound\\Interface\\AuctionWindowOpen.ogg" },
  { key = "murloc",   label = "Murloc",
    kit = nil,                 file = "Sound\\Creature\\Murloc\\mMurlocAggroOld.ogg" },
  { key = "none",     label = "Silent",  kit = nil, file = nil }
}

function BT.SoundByKey(key)
  for _, s in ipairs(BT.SOUNDS) do
    if s.key == key then return s end
  end
  return BT.SOUNDS[1]
end

-- which = "in" (go back in) or "out" (you are inside, leave)
local function Beep(which)
  local key = (which == "out") and (ChainDB.soundOut or "warning")
    or (ChainDB.soundIn or "levelup")
  local s = BT.SoundByKey(key)
  if not s or s.key == "none" then return end
  -- Master channel on purpose: it plays even with the game muted, which is
  -- the state you are most likely in when you have walked away.
  if s.kit and PlaySound and SOUNDKIT and SOUNDKIT[s.kit] then
    PlaySound(SOUNDKIT[s.kit], "Master")
  elseif s.file and PlaySoundFile then
    PlaySoundFile(s.file, "Master")
  elseif PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
  end
end
BT.Beep = Beep

-- Which of the two the situation calls for, asked fresh every time: walk out
-- of the portal between two repeats and the sound changes with you.
local function ResetSide()
  return (ChainCharDB and ChainCharDB.run) and "out" or "in"
end

-- An addon cannot reach your phone - there is no network in the Lua sandbox,
-- for anyone, ever. So the alert has to win in the room instead: repeated, on
-- the Master channel, and printed across the middle of the screen until you
-- actually do something about it.
function BT.FlagReset(zone, by)
  local c = ChainCharDB
  local prev = c.resetAt
  c.resetAt, c.resetZone, c.resetBy = time(), zone, BT.ShortName(by)
  -- the system message and NIT's party message often both arrive
  if prev and (time() - prev) <= 15 then return end
  -- A reset is worth keeping, not just reacting to: how many the group got
  -- through in an evening, who was doing the resetting, and how long the
  -- chain ran. It is our own record, and needs nobody else's addon.
  local db = ChainDB
  db.resets = db.resets or {}
  table.insert(db.resets, { at = time(), zone = zone,
                            by = BT.ShortName(by), char = UnitName("player") })
  while #db.resets > 300 do table.remove(db.resets, 1) end
  BT.Signal("reset", (BT.Short(zone) or zone or "instance") .. " is open")
  if not ChainDB.sound then return end
  Beep(ResetSide())
  local left = math.max(0, math.floor(ChainDB.soundRepeat or 1) - 1)
  if left > 0 and C_Timer and C_Timer.After then
    local n, at = left, c.resetAt
    local function again()
      -- stop the moment the situation is dealt with
      if n <= 0 or ChainCharDB.resetAt ~= at then return end
      if not BT.ResetReady() then return end
      n = n - 1
      Beep(ResetSide())
      C_Timer.After(2, again)
    end
    C_Timer.After(2, again)
  end
end

--------------------------------------------------------------------------
-- What the game itself says about your lockout
--------------------------------------------------------------------------
-- Counting zone-ins is an estimate: it misses anything entered on a day the
-- addon was off, on another computer, or before it was installed. The game
-- knows the real answer and says so at the portal - "you have entered too
-- many instances recently". That sentence is worth more than our arithmetic,
-- so when it arrives the count is corrected to it rather than argued with.
local LOCK_STRINGS = {
  _G.ERR_TRANSFER_ABORT_TOO_MANY_INSTANCES,
  _G.INSTANCE_LIMIT,
  "You have entered too many instances recently."
}

function BT.LooksLikeLockout(msg)
  if type(msg) ~= "string" then return false end
  local low = msg:lower()
  for _, s in ipairs(LOCK_STRINGS) do
    if type(s) == "string" and s ~= "" and low:find(s:lower(), 1, true) then
      return true
    end
  end
  -- the wording moves between clients and locales; the shape does not
  return low:find("too many instances", 1, true) ~= nil
end

-- The game refused us. Whatever we had counted, the truth is "at the limit".
-- The game refused us, so it has seen instances we have not - a day the addon
-- was off, another computer, a zone-in that never became a run. Rather than
-- carry that as a number bolted onto the count, we write the missing ones
-- into the log as entries. They are entries: they count, they expire, and the
-- two clocks work on them without knowing they are any different.
--
-- Their timestamp is the moment of the refusal, which is the pessimistic
-- answer. An instance the game is counting was entered some time before it
-- told us, so an hour from now is the latest it can still be counting - and
-- being told to wait slightly too long is the right way round to be wrong.
function BT.NoteLockedOut()
  local c = ChainCharDB
  c.lockedAt = time()
  local count = BT.Lockout()
  local limit = ChainDB.limit or K.LIMIT
  if count < limit then
    local need = limit - count
    local me = UnitName("player")
    local zone = BT.InDungeon()
    for _ = 1, need do
      c.entrySeq = (c.entrySeq or 0) + 1
      table.insert(ChainDB.entries, {
        t = time(), seq = me .. ":" .. c.entrySeq, zone = zone,
        char = me, ghost = true
      })
    end
    while #ChainDB.entries > 200 do table.remove(ChainDB.entries, 1) end
    -- Say so out loud rather than quietly showing 3/5 at a door that will
    -- not open.
    print(BT.COL.warn .. BT.NAME .. ":|r the game says you are at the limit, "
      .. "and I had counted " .. count .. "/" .. limit .. ". Adding the "
      .. need .. " it has seen and I have not.")
  end
  if BT.AnnounceLock then BT.AnnounceLock(true) end
  if BT.Refresh then BT.Refresh() end
end

-- When the game last refused us, for anyone who wants to say so in words
function BT.LockedByGame()
  local c = ChainCharDB
  if not c.lockedAt then return nil end
  if (time() - c.lockedAt) > 3600 then
    c.lockedAt, c.lockMissing = nil, nil
    return nil
  end
  return c.lockedAt, c.lockMissing
end

function BT.NoteResetSystem(msg)
  if type(msg) ~= "string" then return end
  if BT.LooksLikeLockout(msg) then BT.NoteLockedOut() return end
  if resetPattern then
    local zone = msg:match(resetPattern)
    if zone then
      BT.FlagReset(zone, nil)
      BT.Announce(zone)
      return
    end
  end
  for _, f in ipairs(failPatterns) do
    if f[1] then
      local zone = msg:match(f[1])
      if zone then
        local c = ChainCharDB
        c.failAt, c.failZone, c.failWhy = time(), zone, f[2]
        return
      end
    end
  end
end

-- A failed reset you were told about in the last two minutes
function BT.ResetFailed()
  local c = ChainCharDB
  if not c.failAt or (time() - c.failAt) > 120 then return nil end
  -- a reset that then succeeded makes the failure stale
  if c.resetAt and c.resetAt >= c.failAt then return nil end
  return c.failZone, c.failWhy
end

-- Tell the group, so the boosties are not all waiting on somebody to say it.
-- Off by default: it is your chat, not ours.
-- Everything the addon says to the group says who is saying it. Four people
-- are running three addons between them and all of them are shouting numbers
-- into the same window; a line with no name on it reads as somebody typing,
-- and somebody typing gets asked follow-up questions. Nova does the same, and
-- for the same reason.
--
-- Upper case and a dash, so the tag reads as a label rather than as the first
-- word of the sentence: "[CHAIN] - 5/5 - 15m to go".
BT.SAY = "[" .. string.upper(BT.NAME) .. "] - "

local function Tell(text)
  -- Solo there is nobody to tell, but the number is still worth having - so
  -- it goes to your own chat frame rather than nowhere. Same line, so what
  -- you see alone is what the group sees when you are not.
  if not (IsInGroup and IsInGroup()) then
    print(BT.COL.info .. BT.SAY .. BT.COL.off .. text)
    return true
  end
  if type(SendChatMessage) ~= "function" then return false end
  SendChatMessage(BT.SAY .. text,
                  (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
  return true
end

-- Anything else that wants to say something to the group goes through here,
-- so it carries the same tag and falls back to your own chat frame the same
-- way when there is nobody to tell.
function BT.SayToGroup(text)
  return Tell(text)
end

-- ...and the same thing said to one person instead. A booster who has left the
-- group, or one you would rather not correct in front of four other people.
function BT.WhisperTo(name, text)
  if not name or name == "" then return false end
  if type(SendChatMessage) ~= "function" then return false end
  SendChatMessage(BT.SAY .. text, "WHISPER", nil, name)
  return true
end

-- The group cannot see your lockout. They see you standing at the portal not
-- going in, and somebody asks, and you type it out - every single time. So
-- the addon says it instead: how many you are at, and how long until that
-- changes. Nobody has to ask and nobody has to guess.
--
-- Two lines, and only two: the one that says you are stuck, and the one that
-- says you are not any more. Anything in between is a countdown in party chat,
-- which is the fastest way to be asked to turn an addon off.
local LOCK_QUIET = 120

-- Whole minutes, always, and never a zero. Seconds in a line about an hour's
-- lockout are false precision - nobody stands at the stone counting them - and
-- "free in 50s" reads as a different unit you have to convert before you can
-- compare it with the line before.
local function Mins(sec)
  return math.max(1, math.ceil((sec or 0) / 60)) .. "m"
end

local function LockText()
  local count, freeOne = BT.Lockout()
  local limit = ChainDB.limit or K.LIMIT
  if count < limit then return nil, count, limit end
  return count .. "/" .. limit
    .. (freeOne and (" - instance free in " .. Mins(freeOne)) or " - locked"),
    count, limit
end

-- The countdown, said out loud.
--
-- A group standing at the summoning stone is a group waiting on the number
-- somebody has to keep asking for. So it is announced on a schedule rather
-- than whenever something happens to poke it: every five minutes while the
-- wait is long, once at one minute, and once when a slot actually opens.
--
-- The five-minute marks are counted from the end rather than from the start -
-- "15 minutes" then "10 minutes" then "5 minutes" is a countdown; "12
-- minutes" then "7 minutes" is somebody reading a clock aloud.
-- The mark we are counting down to. Speaking is decided by the mark; what
-- gets spoken is the real time left, because a poll that catches the mark a
-- little late should still tell the truth rather than read out the label.
local function FirstMark(left)
  if not left or left <= 60 then return nil end
  if left <= 300 then return 60 end
  return math.floor(left / 300) * 300
end

local function NextMark(mark)
  if not mark then return nil end
  if mark > 300 then return mark - 300 end
  if mark > 60 then return 60 end
  return nil
end

function BT.AnnounceLock(force)
  if not ChainDB.announceLock then return end
  local c = ChainCharDB
  local text, count, limit = LockText()
  if not text then
    -- The one line worth saying from inside: a slot is open, and the group
    -- standing in the instance is exactly who is waiting to hear it. Said in
    -- words rather than shouted - a bare FREE in capitals next to a count
    -- reads like a stuck key.
    if c.toldLocked then
      c.toldLocked, c.toldMark = nil, nil
      Tell(count .. "/" .. limit .. " - instance unlocked")
    end
    return
  end

  -- The countdown is for people standing outside. Said from inside it is a
  -- clock read aloud to four people who are fighting - and going in is what
  -- puts you on the cap, so that was precisely when the first line fired.
  if not force and BT.InDungeon and BT.InDungeon() then return end

  local now = time()
  local _, freeOne = BT.Lockout()

  -- The first time, and then on the marks. Each mark is said once: the poll
  -- runs every few seconds and a countdown that repeats itself is worse than
  -- one that says nothing.
  if freeOne and c.toldLocked and not force then
    local mark = c.toldMark
    if not mark or freeOne > mark then return end
    c.toldMark = NextMark(mark)
    -- The same words every time. "free in 15m" after "free in 47m" is one
    -- sentence counting down; "15m to go" is a second way of saying the same
    -- thing, and the group has to read it twice to see they match.
    if Tell(count .. "/" .. limit .. " - instance free in " .. Mins(freeOne)) then
      c.toldLocked = now
    end
    return
  end

  if not force and c.toldLocked and (now - c.toldLocked) < LOCK_QUIET then return end
  if Tell(text) then
    c.toldLocked = now
    c.toldMark = FirstMark(freeOne)
  end
end

function BT.Announce(zone)
  if not ChainDB.announce then return end
  -- "go in" is the wrong thing to shout when you cannot. At the limit the
  -- group wants the other sentence: how long the wait is.
  local locked = LockText()
  if locked then
    -- not forced: a reset every twenty seconds is normal in a boost chain,
    -- and the group needs telling once, not once per attempt
    if ChainDB.announceLock then BT.AnnounceLock() end
    return
  end
  Tell((BT.Short(zone) or zone) .. " reset - go in")
end

-- Reset the instances you are locked to. Only the group leader can, and only
-- from outside, so the game will say no if either is untrue - which is what
-- the failure lines above are for.
function BT.DoReset()
  if BT.InDungeon() then
    print(BT.COL.warn .. BT.NAME .. ":|r you have to be outside the instance to reset it.")
    return
  end
  if type(ResetInstances) ~= "function" then
    print(BT.COL.warn .. BT.NAME .. ":|r this client does not let an addon reset instances.")
    return
  end
  ResetInstances()
end

-- Is this person the one who can actually reset?
--
-- Only the group leader can, so only the group leader saying it means
-- anything. Everybody else typing the word is somebody asking for one,
-- complaining about one, or repeating what the leader just said.
function BT.IsLeader(name)
  if not name then return false end
  if type(UnitIsGroupLeader) ~= "function" then return true end
  local short = BT.ShortName and BT.ShortName(name) or name
  local me = UnitName and UnitName("player")
  if me and (BT.ShortName and BT.ShortName(me) or me) == short then
    return UnitIsGroupLeader("player") and true or false
  end
  local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
  for i = 1, 40 do
    local u = prefix .. i
    if UnitExists and UnitExists(u) then
      local n = UnitName and UnitName(u)
      if n and (BT.ShortName and BT.ShortName(n) or n) == short then
        return UnitIsGroupLeader(u) and true or false
      end
    end
  end
  return false
end

-- Somebody in the group saying the instance has been reset.
--
-- It used to believe anyone who typed the word, and one person typing "reset"
-- in raid chat set the alarm off for everybody. Only the leader can reset, so
-- only the leader saying it counts - and a question is somebody asking for
-- one, not announcing it.
--
-- The game's own "The Stockade has been reset" is unaffected: that one is the
-- client telling you, and it needs no vouching for.
function BT.NoteResetChat(msg, sender)
  if type(msg) ~= "string" then return end
  local low = msg:lower()
  if not low:find("%f[%a]reset") then return end
  if low:find("?", 1, true) then return end
  if sender and not BT.IsLeader(sender) then return end
  BT.FlagReset(ChainCharDB.lastZone, sender)
end

-- The booster's own counter.
--
-- Boosters run an addon that announces where everybody is in their pack:
-- "[BoostBuddy] Nintoz - Run 4/10". That is the number he is charging
-- against, and it is better than anything we can work out from the outside -
-- he knows when the pack started and we are guessing from when you paid.
--
-- So when a line names you, take it. Ours stays as the fallback for the
-- boosters who announce nothing, and both are on the tooltip, because the two
-- can legitimately differ: his counts his pack, ours counts your runs with
-- him since the money changed hands.
function BT.NotePackRun(msg, sender)
  if type(msg) ~= "string" then return nil end
  local who, n, of = msg:match("(%S+)%s*%-%s*[Rr]un%s*(%d+)%s*/%s*(%d+)")
  if not who then return nil end
  n, of = tonumber(n), tonumber(of)
  if not n or not of or of <= 0 then return nil end
  local me = UnitName and UnitName("player") or nil
  if not me or BT.ShortName(who) ~= BT.ShortName(me) then return nil end

  local by = sender and ((BT.CleanName and BT.CleanName(sender))
                         or BT.ShortName(sender)) or nil
  ChainCharDB.packRun = { by = by, n = n, of = of, at = time() }
  if BT.Refresh then BT.Refresh() end
  if BT.RenderWindow then BT.RenderWindow() end
  return ChainCharDB.packRun
end

-- His count, if he said it lately and it was about this booster.
--
-- The number he said is only true for the run he said it on. He announces
-- once a run, and a booster who stops announcing - or whose addon is off, or
-- who has moved on to somebody else's pack - leaves us holding a number that
-- was right twenty minutes and three runs ago. "9/10 runs" sat on the bar for
-- two hours after the pack was finished, because that was the last thing he
-- ever said.
--
-- So it is carried forward with what we can see: every run we have done with
-- him since he said it is one more off the pack. If that takes the count to
-- the end of the pack, the pack is over and there is nothing left of his to
-- believe - our own arithmetic takes it from there, and that one knows you
-- have gone seven runs past what you paid for.
--
-- A payment newer than the announcement ends it too: that is a new pack, and
-- his old number is about the last one.
function BT.PackRun(who)
  local p = ChainCharDB.packRun
  if not p or not p.of then return nil end
  if (time() - (p.at or 0)) > 7200 then return nil end
  if who and p.by and p.by ~= who then return nil end

  local by = who or p.by
  if by and BT.LastPaid then
    local paidAt = BT.LastPaid(by)
    if paidAt and paidAt > (p.at or 0) then return nil end
  end

  local n = p.n or 0
  if by and BT.Runs then
    n = n + #BT.Runs({ by = by, since = (p.at or 0) + 1 })
  end
  if n >= p.of then return nil end
  return n, p.of, p.by
end

-- A reset you have been told about, still fresh and not yet used.
-- Returns zone, age, who, inside
function BT.ResetReady()
  local c = ChainCharDB
  if not c.resetAt then return nil end
  local age = time() - c.resetAt
  local inside = c.run ~= nil
  -- Inside there is no timeout: you might be away from the keyboard when the
  -- leader resets, and the situation lasts until you actually leave. Outside
  -- it expires, because you are meant to walk straight back in.
  if not inside and age > 120 then return nil end
  return c.resetZone, age, c.resetBy, inside
end

--------------------------------------------------------------------------
-- Signalling out of the game
--------------------------------------------------------------------------
-- An addon has no network access, so it cannot notify your phone. What it can
-- do is leave a line in the chat log the game itself writes, and let a small
-- program outside WoW watch that file. The line goes to a channel only this
-- character is in, so nobody else ever sees it.
--
-- It has to be shown in *some* chat window, though: the client only writes to
-- the chat log what a chat frame displayed, so a channel removed from every
-- window is a channel that leaves no trace in the file. It is parked in the
-- Combat Log window instead, which nobody reads, and taken out of the rest.
local SIGNAL_PREFIX = "LTPUSH"

function BT.SignalChannel()
  local me = UnitName("player") or "x"
  return "LB" .. me:gsub("%W", "")
end

-- Which window the marker is parked in: the Combat Log if there is one, the
-- last window otherwise. Never the first - that is the one you read.
function BT.SignalFrame()
  local combat = _G.ChatFrame2
  if combat then return combat, 2 end
  local n = NUM_CHAT_WINDOWS or 2
  return _G["ChatFrame" .. n], n
end

-- The chat log stops at every /reload and every relog, and - this is the part
-- that cost an evening - the client goes on reporting it as ON afterwards
-- while the file sits closed. Asking for it again does nothing in that state;
-- switching it off and on again reopens the file. Once per session is enough.
function BT.EnsureChatLog()
  if not LoggingChat then return end
  if BT.chatLogArmed then return end
  BT.chatLogArmed = true
  if LoggingChat() then LoggingChat(false) end
  LoggingChat(true)
end

function BT.EnableSignal()
  if not ChainDB.logSignal then return end
  -- the log itself has to be running, or there is nothing to watch
  BT.EnsureChatLog()
  local name = BT.SignalChannel()
  local joined = GetChannelName and GetChannelName(name) > 0
  if not joined and JoinTemporaryChannel then JoinTemporaryChannel(name) end

  -- Shown in exactly one window, or the client logs nothing at all. The
  -- Combat Log is the polite place for it, but it is a special frame in some
  -- builds and can refuse, so the result is checked and the general window
  -- taken as the fallback: a line you can see beats a push you never get.
  local keep, keepIndex = BT.SignalFrame()
  if keep and ChatFrame_AddChannel then ChatFrame_AddChannel(keep, name) end
  if not BT.FrameHasSignal(keep) then
    keep, keepIndex = _G.ChatFrame1, 1
    if keep and ChatFrame_AddChannel then ChatFrame_AddChannel(keep, name) end
  end
  BT.signalFrameIndex = keepIndex
  if ChatFrame_RemoveChannel then
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
      local f = _G["ChatFrame" .. i]
      if f and i ~= keepIndex then ChatFrame_RemoveChannel(f, name) end
    end
  end
end

-- Is our channel actually in this window's list? Without it, nothing is
-- displayed, and what is not displayed is not written to the log.
function BT.FrameHasSignal(frame)
  if not frame then return false end
  local name = BT.SignalChannel()
  if ChatFrame_ContainsChannel then
    return ChatFrame_ContainsChannel(frame, name) and true or false
  end
  -- older clients: read the window's own list
  local list = frame.channelList
  if type(list) ~= "table" then return true end   -- cannot tell; assume it took
  for _, c in ipairs(list) do
    if type(c) == "string" and c:lower() == name:lower() then return true end
  end
  return false
end

-- Where the marker ended up, for /chain testpush and the settings line
function BT.SignalWhere()
  if not ChainDB.logSignal then return nil end
  local i = BT.signalFrameIndex
  if not i then return nil end
  local f = _G["ChatFrame" .. i]
  local label = (f and f.name) or ("window " .. i)
  return label, i
end

-- The client does not write the chat log line by line: it buffers, and the
-- buffer can sit there for ten minutes. Measured on a live session - a marker
-- written at 18:57 reached the file at 19:00, which is no use at all when the
-- whole point is "he has reset it, get back in".
--
-- Closing the log flushes it, so the marker is pushed out by switching
-- logging off and straight back on a second after writing it. Rate-limited,
-- because every toggle is a moment where an arriving line could fall between
-- two file handles.
-- Measured on the live client: the file grows in exact 49,152-byte steps, so
-- the chat log is block-buffered and a marker can sit in memory for ten
-- minutes. Turning logging off and straight back on in the same frame did not
-- shift it - the client evidently defers the close - so the two halves are
-- put a few frames apart, which gives it a chance to actually close the file
-- and flush what is in the buffer.
local FLUSH_GAP = 5
function BT.FlushChatLog()
  if not LoggingChat then return end
  local now = time()
  if BT.lastFlush and now - BT.lastFlush < FLUSH_GAP then return end
  BT.lastFlush = now
  LoggingChat(false)
  local function back() LoggingChat(true) BT.chatLogArmed = true end
  if C_Timer and C_Timer.After then C_Timer.After(0.4, back) else back() end
end

-- The chat log is buffered in 48 KiB blocks and nothing flushes it, so a
-- marker written now can reach the disk ten minutes later. A screenshot does
-- not wait: the client writes the file the moment it is asked. So the alert
-- that has to be instant is a file appearing in the Screenshots folder - one
-- for a ready check, two in quick succession for a reset - and the watcher
-- outside counts them, sends the push, and deletes them again.
--
-- It costs a flash and a "Screenshot captured" line. That is the whole price,
-- and it is the only way to be told in seconds rather than minutes.
function BT.Snap(n)
  if not ChainDB.snapSignal then return end
  if not Screenshot then return end
  local now = time()
  if BT.lastSnap and now - BT.lastSnap < 8 then return end
  BT.lastSnap = now
  Screenshot()
  if (n or 1) > 1 and C_Timer and C_Timer.After then
    for i = 2, n do C_Timer.After((i - 1) * 0.8, function() Screenshot() end) end
  end
end

-- kind is a bare word the watcher matches on; text is for a human to read
function BT.Signal(kind, text)
  -- the screenshot alert stands on its own: it works with the chat marker
  -- switched off, and it is the one that arrives in seconds
  BT.Snap(kind == "reset" and 2 or 1)
  if not ChainDB.logSignal then return end
  BT.EnableSignal()
  local id = GetChannelName and GetChannelName(BT.SignalChannel()) or 0
  if id <= 0 or not SendChatMessage then return end
  SendChatMessage(SIGNAL_PREFIX .. " " .. kind .. " " .. (text or ""),
                  "CHANNEL", nil, id)

  -- out of the buffer and into the file, where the watcher can see it
  if C_Timer and C_Timer.After then C_Timer.After(1, BT.FlushChatLog)
  else BT.FlushChatLog() end
end

--------------------------------------------------------------------------
-- Run lifecycle
--------------------------------------------------------------------------
-- `partial` marks a run we only saw the tail of - you logged in or reloaded
-- while already inside. It is measured and shown but never stored, because
-- half a run would drag every average down.
function BT.StartRun(zone, partial, map, knownId)
  local c = ChainCharDB
  local by = BT.Booster()
  local avg, n = BT.GroupInfo()
  c.run = {
    zone = zone, map = map, id = BT.StepFor(map, zone), by = by,
    xp = 0, k = 0, start = time(), entrySeq = BT.NoteEntry(),
    lvl = UnitLevel("player"), grp = n, grpAvg = avg,
    partial = partial or nil
  }
  c.resetAt = nil
  -- The caller already knows which instance this is when the run was split
  -- off another one: use that rather than asking the target, which at that
  -- moment is still a mob from the wing we have just walked out of and would
  -- file the new run as a return to the old instance.
  if knownId then
    Record(c.run, knownId)
    return
  end
  -- and a corpse dragged along in the target frame is the same trap in slow
  -- motion, so a dead target gets no say
  local guid = UnitGUID and UnitGUID("target") or nil
  if not guid then return end
  if UnitIsDead and UnitIsDead("target") then return end
  BT.NoteInstance(guid)
end

function BT.EndRun()
  local c = ChainCharDB
  local r = c.run
  c.run = nil
  if not r then return end
  c.lastEnd = time()
  if c.resetAt then
    -- you were told to get out, and you did: the advice has just flipped to
    -- "go back in", so say so with the other sound rather than in silence
    c.resetAt = time()
    if ChainDB.sound then Beep("in") end
  end
  if r.entrySeq and not r.instId and (r.k or 0) == 0 and (r.xp or 0) == 0 then
    -- never saw a single unit, so no evidence we were really in there
    BT.DropEntry(r.entrySeq)
  end
  -- A run that is not kept still had money in it. It goes to the loose pile
  -- rather than nowhere, so the total across the log stays true even though
  -- this particular run is not in it.
  if (r.xp or 0) <= 0 or r.partial then
    if (r.coin or 0) > 0 then
      ChainDB.coinLoose = (ChainDB.coinLoose or 0) + r.coin
    end
  end
  if (r.xp or 0) <= 0 then return end
  if r.partial then return end

  local rec = {
    at = r.start, t = math.max(0, time() - (r.start or time())),
    zone = r.zone, map = r.map, id = r.id, by = r.by,
    xp = r.xp, k = r.k or 0, coin = (r.coin or 0) > 0 and r.coin or nil,
    lvl = r.lvl, grp = r.grp, grpAvg = r.grpAvg,
    reentry = r.reentry or nil,
    char = UnitName("player")
  }
  table.insert(ChainDB.runs, rec)
  while #ChainDB.runs > K.MAX_RUNS do table.remove(ChainDB.runs, 1) end
  BT.Touch()
  if r.by then c.lastBy = r.by end
  BT.lastRecord = rec
  if r.by and BT.CheckDebt then BT.CheckDebt(r.by) end
end

-- A run past what is logged as paid for is normal - you take one on credit and
-- settle at the end of the pack. A whole pack past it is not: it means money
-- changed hands and we did not see it. Trades to a bank alt do that, and so
-- does a trade the client never announced, which is half the reason the
-- payment log has a way to type one in at all.
--
-- So it says so, once, rather than letting the number drift until the bar
-- claims you owe seven runs. Once per payment: settle up, or tell it what you
-- paid, and it goes quiet again.
function BT.CheckDebt(who)
  if not who or not BT.BoosterCredit then return end
  local c = BT.BoosterCredit(who)
  if not c then return end
  local owed = -(c.left or 0)
  local pack = (BT.PackFor and BT.PackFor(nil, who)) or 1
  if pack < 1 then pack = 1 end
  if owed < math.max(2, pack) then return end

  local key = who .. ":" .. tostring(BT.LastPaid and BT.LastPaid(who) or 0)
  if ChainCharDB.debtTold == key then return end
  ChainCharDB.debtTold = key

  local b = ChainDB.boosters[who]
  local price = b and b.price or nil
  print(BT.COL.warn .. BT.NAME .. ":|r " .. string.format("%.0f", owed)
    .. " runs past what is logged as paid to " .. who
    .. ". If you paid and it was not picked up - a trade to his alt, or one the"
    .. " client never announced - log it with " .. BT.COL.info .. "/chain paid "
    .. who .. (price and (" " .. price) or " <gold>") .. "|r.")
end

-- Check the zone and start or stop a run
function BT.Sync(partial)
  local c = ChainCharDB
  BT.LearnXP()
  c.lastXP, c.lastMax = UnitXP("player"), UnitXPMax("player")
  local zone, map = BT.InDungeon()
  if zone then
    local r = c.run
    if not r or r.zone ~= zone then
      BT.EndRun()
      BT.StartRun(zone, partial, map)
    elseif not r.by then
      -- the booster may have invited us after we zoned in
      local by = BT.Booster()
      if by then r.by = by end
    end
    c.lastZone, c.lastMap = zone, map
  else
    BT.EndRun()
  end
end

-- How far the run in progress deviates from the usual. Returns pace, overtime
function BT.RunDeviation(st)
  local r = ChainCharDB.run
  if not r or not st then return nil end
  local el = time() - (r.start or time())
  if el < 30 then return nil end
  local over = el - (st.t or 0)
  local dev
  if (st.t or 0) > 0 and (st.xp or 0) > 0 then
    local usual = st.xp / st.t
    if usual > 0 then dev = ((r.xp or 0) / el) / usual - 1 end
  end
  return dev, over, el
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------
-- Level Tracker, then LevelBar, now Chain. Returns the name it took the data
-- from, or nil if there was nothing to take.
--
-- Called twice on purpose. The saved variables of an old name only exist as
-- globals once that addon's own file has been read, and WoW loads addons
-- alphabetically: Chain comes before LevelBar, so at our own ADDON_LOADED the
-- old data is not there yet. PLAYER_LOGIN fires after every addon is up,
-- which is the first moment the question can honestly be answered.
function BT.AdoptOldNames()
  local from
  local mine = ChainDB
  local empty = (not mine) or ((#(mine.runs or {}) == 0)
    and (#(mine.trades or {}) == 0) and (#(mine.entries or {}) == 0)
    and not next(mine.boosters or {}))
  if empty then
    local old, name
    if _G.LevelBarDB then old, name = _G.LevelBarDB, "LevelBar"
    elseif _G.LevelTrackerDB then old, name = _G.LevelTrackerDB, "Level Tracker" end
    -- only if the old one actually holds something; an empty old database is
    -- not worth trading a working new one for
    if old and ((#(old.runs or {}) > 0) or (#(old.trades or {}) > 0)
                or (#(old.entries or {}) > 0) or next(old.boosters or {})) then
      ChainDB, from = old, name
    elseif old and not mine then
      ChainDB = old
    end
  end
  if not ChainCharDB or not next(ChainCharDB) then
    ChainCharDB = _G.LevelBarCharDB or _G.LevelTrackerCharDB or ChainCharDB
  end
  return from
end

function BT.SayAdopted(from)
  if not from then return end
  print(BT.COL.info .. BT.NAME .. ":|r carried over "
    .. #(ChainDB.runs or {}) .. " runs, "
    .. #(ChainDB.trades or {}) .. " trades and "
    .. #(ChainDB.entries or {}) .. " instance entries from " .. from .. ".")
end

local EVENTS = {
  "PLAYER_LOGIN",
  "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
  "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
  "COMBAT_LOG_EVENT_UNFILTERED", "CHAT_MSG_COMBAT_XP_GAIN",
  "CHAT_MSG_SYSTEM", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
  "GROUP_ROSTER_UPDATE", "QUEST_LOG_UPDATE", "READY_CHECK",
  -- the honour system: the counter only moves on the server's terms, so we
  -- ask what the week total is on every event that could have changed it
  "CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_PVP_KILLS_CHANGED",
  "PLAYER_PVP_RANK_CHANGED", "UPDATE_FACTION"
}

function BT.OnEvent(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON then return end

    -- Level Tracker, then LevelBar, now Chain. A new name means new saved
    -- variables, and an empty history is not what anyone wants from a rename,
    -- so the most recent set we can find is adopted once and then left alone.
    -- The .toc still declares every old name, which is the only reason they
    -- are here to be read at all.
    BT.adopted = BT.AdoptOldNames()

    ChainDB = BT.ApplyDefaults(ChainDB or {}, BT.DEFAULTS)
    ChainCharDB = BT.ApplyDefaults(ChainCharDB or {}, BT.CHAR_DEFAULTS)
    -- before anything is drawn: every label in the addon is written in one of
    -- five font objects of ours, and this is where they are pointed at a face
    if BT.ApplyFont then BT.ApplyFont() end
    if BT.adopted then
      BT.SayAdopted(BT.adopted)
      BT.adopted = nil
    end
    -- The price box used to store whatever you typed as a per-run price, and
    -- nobody sells single runs. Anything sitting at pack = 1 came from that
    -- bug, so put it back on the pack size it was quoted for.
    if not ChainDB.packFixed then
      ChainDB.packFixed = true
      local pack = ChainDB.pack or 1
      local n = 0
      if pack > 1 then
        for _, b in pairs(ChainDB.boosters) do
          if (b.price or 0) > 0 and (b.pack or 1) == 1 then
            b.pack = pack
            n = n + 1
          end
        end
      end
      if n > 0 then
        print(BT.COL.info .. BT.NAME .. ":|r " .. n .. " booster price"
          .. (n == 1 and "" or "s") .. " now read as the price for " .. pack
          .. " runs, not one.")
      end
    end

    -- The instance-identity bug threw most entries away as false re-entries,
    -- so the log can say 2/5 with nine runs behind it in the same hour. The
    -- runs are the evidence; put the missing entries back from them.
    --
    -- Once, ignoring the re-entry flag the runs are carrying. That flag was
    -- written by the rule that was wrong: it marked every repeat of the same
    -- *dungeon* as a return to the same instance, so on old records it holds
    -- no information at all - and the runs it marked are precisely the ones
    -- whose entries went missing. Counting them is closer to the truth than
    -- believing it, because the ordinary shape of a boost chain is reset and
    -- go back in, which is a new instance every time.
    if BT.ReconcileEntries and not ChainDB.entriesRepaired then
      ChainDB.entriesRepaired = true
      local back = BT.ReconcileEntries(86400, false)
      if back > 0 then
        print(BT.COL.info .. BT.NAME .. ":|r put " .. back .. " instance entr"
          .. ((back == 1) and "y" or "ies") .. " back from the run log - they "
          .. "had been dropped as re-entries by mistake.")
      end
    elseif BT.ReconcileEntries then
      -- and every load after that as a safety net, believing the flag, which
      -- is worked out properly now
      BT.ReconcileEntries()
    end

    -- One spelling, everywhere. Runs kept the client's raw name and trades
    -- kept the cleaned one, so anything the cleaner changes - a capital
    -- anywhere but the first letter - made one booster into two.
    if not ChainDB.namesCleaned and BT.CleanName then
      ChainDB.namesCleaned = true
      local fixed = 0
      local function fix(v)
        if type(v) ~= "string" or v == "" then return v, false end
        local c = BT.CleanName(v)
        if c and c ~= v then fixed = fixed + 1 return c, true end
        return v, false
      end
      for _, r in ipairs(ChainDB.runs or {}) do r.by = (fix(r.by)) end
      for _, t in ipairs(ChainDB.trades or {}) do
        t.with = (fix(t.with))
        t.by = (fix(t.by))
      end
      ChainCharDB.lastBy = (fix(ChainCharDB.lastBy))
      -- and the booster table is keyed by name, so it has to be re-keyed
      local moved = {}
      for name, info in pairs(ChainDB.boosters or {}) do
        local c = BT.CleanName(name)
        if c and c ~= name then moved[name] = c end
      end
      for from, to in pairs(moved) do
        local a, b = ChainDB.boosters[from], ChainDB.boosters[to]
        if not b then ChainDB.boosters[to] = a
        else
          -- two halves of one man: keep whichever actually has a price
          if (a.price or 0) > 0 and (b.price or 0) <= 0 then b.price = a.price end
          if (a.pack or 0) > 0 and (b.pack or 0) <= 0 then b.pack = a.pack end
          if a.note and not b.note then b.note = a.note end
        end
        ChainDB.boosters[from] = nil
        fixed = fixed + 1
      end
      if fixed > 0 then
        BT.Touch() BT.TouchTrades()
        print(BT.COL.info .. BT.NAME .. ":|r tidied " .. fixed .. " name"
          .. ((fixed == 1) and "" or "s") .. " so runs and gold land on the "
          .. "same person.")
      end
    end

    -- Coin used to get a row of its own in the loot log, which is how a night
    -- of Scarlet Monastery turned into four hundred lines of "3s 95c" with
    -- the greens somewhere inside them. It belongs to the run now.
    if BT.FoldCoins and not ChainDB.coinFolded then
      local moved, loose = BT.FoldCoins()
      if (moved or 0) + (loose or 0) > 0 then
        print(BT.COL.info .. BT.NAME .. ":|r " .. BT.Coin(moved + loose)
          .. " of loose coin moved out of the loot log and onto the runs it "
          .. "came from.")
      end
    end

    -- Runs recorded before the instance-id work have no step on them, because
    -- the name they were filed under did not match the table. Give them one
    -- now rather than leaving that history stranded.
    local fixed = 0
    for _, r in ipairs(ChainDB.runs) do
      if not r.id then
        local list = BT.DungeonsFor(r.map, r.zone)
        if list and list[1] then r.id = list[1].id fixed = fixed + 1 end
      end
    end
    if fixed > 0 then
      BT.Touch()
      print(BT.COL.info .. BT.NAME .. ":|r matched " .. fixed
        .. " older run" .. (fixed == 1 and "" or "s") .. " to the right instance.")
    end
    -- entries used to live per character; the daily cap needs them pooled
    if ChainCharDB.entries then
      for _, e in ipairs(ChainCharDB.entries) do
        e.char = e.char or UnitName("player")
        e.seq = tostring(e.seq)
        table.insert(ChainDB.entries, e)
      end
      ChainCharDB.entries = nil
      table.sort(ChainDB.entries, function(a, b) return (a.t or 0) < (b.t or 0) end)
    end
    -- first run: pre-fill the route so the options are not an empty page
    if not ChainDB.seeded then
      ChainDB.seeded = true
      for _, d in ipairs(BT.DUNGEONS) do
        ChainDB.route[d.id] = ChainDB.route[d.id]
          or { on = false, from = d.lo, to = d.hi, gold = 0 }
      end
    end
    -- "Use Nova Instance Tracker" meant "read its log instead of ours", and
    -- it was on by default. It now means "trust its live count over ours",
    -- which is a different question and a much smaller one - so the old
    -- answer is not carried over as if it were an answer to the new one.
    if not ChainDB.nitReframed then
      ChainDB.nitReframed = true
      if ChainDB.useNIT then
        ChainDB.useNIT = false
        print(BT.COL.info .. BT.NAME .. ":|r the instance log is its own now - "
          .. "NIT's history has been copied into it and the count no longer "
          .. "comes from NIT. Settings has a switch if you want it back.")
      end
    end
    -- Take NIT's history into our own log, once per session. It is the only
    -- thing it has that we cannot see for ourselves, and once it is ours the
    -- addon keeps working the day NIT is uninstalled.
    if BT.ImportNIT then
      local added = BT.ImportNIT()
      if added > 0 then
        print(BT.COL.info .. BT.NAME .. ":|r took " .. added .. " instance entr"
          .. (added == 1 and "y" or "ies") .. " from Nova Instance Tracker "
          .. "into its own log. They are ours now - NIT is not needed for it.")
      end
    end
    -- first run on a character: the level has to have started sometime
    ChainCharDB.levelAt = ChainCharDB.levelAt or time()
    for _, e in ipairs(EVENTS) do frame:RegisterEvent(e) end
    if BT.InitUI then BT.InitUI() end
    if BT.InitOptions then BT.InitOptions() end
    -- the minimap exists by the time the addon loads, so the button can go
    -- straight on rather than waiting for the first frame
    if BT.RefreshMinimap then BT.RefreshMinimap() end
    if BT.RefreshMeter then BT.RefreshMeter() end
    return
  end

  if event == "PLAYER_LOGIN" then
    -- every addon is loaded by now, so the old saved variables are finally
    -- readable. This is the attempt that actually finds them.
    if BT.PollHonor then BT.PollHonor() end
    -- Both the banner and the list carry secure buttons, and a secure button
    -- built during a fight cannot have its attributes set for the rest of
    -- that fight. Building them now, at login, means the first one you ever
    -- need is already there and already armable.
    if BT.LearnStealthNames then BT.LearnStealthNames() end
    if BT.BuildBanner then BT.BuildBanner() end
    if BT.BuildNearby then BT.BuildNearby() end
    local from = BT.AdoptOldNames()
    if from then
      ChainDB = BT.ApplyDefaults(ChainDB or {}, BT.DEFAULTS)
      ChainCharDB = BT.ApplyDefaults(ChainCharDB or {}, BT.CHAR_DEFAULTS)
      BT.Touch()
      BT.SayAdopted(from)
      print(BT.COL.info .. BT.NAME .. ":|r you can turn the old addon off now - "
        .. "the history is Chain's.")
      if BT.Refresh then BT.Refresh() end
    end
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    -- This fires on every loading screen, not only at login: walking into the
    -- instance and walking back out both raise it. Throwing the run away here
    -- discarded it on the way out, one step before it would have been stored,
    -- so nothing ever reached the history.
    local isLogin, isReload = ...
    if isLogin or isReload then
      -- A reload is not an instance entry.
      --
      -- This threw the run away and let Sync start another one - and starting
      -- a run writes an entry against the five-an-hour cap. So every /reload
      -- while standing inside a dungeon counted as walking into a new one,
      -- and a day of reloading to pick up changes put the count several ahead
      -- of the truth. Nova prints "UI Reload detected, loading last instance
      -- data instead of creating new" for exactly this reason.
      --
      -- If we come back to the same place we were already in, the run we had
      -- is still the run we are in. Only somewhere else ends it.
      local zone = BT.InDungeon()
      local r = ChainCharDB.run
      -- Where we were mid-run when the lights went out. Not where we last
      -- were: you can be standing in a city half a minute after leaving the
      -- instance, and that is not the same claim at all.
      BT.reloadRunZone = r and r.zone or nil
      if not (r and zone and r.zone == zone) then
        -- only here have we really missed the start of whatever is going on
        ChainCharDB.run = nil
      end
      -- and the client can report the world before it admits to the instance,
      -- so the guard in NoteEntry covers the case where the check above ran a
      -- moment too early
      BT.reloadedAt = time()
      BT.Sync(true)
      -- a reload closes the chat log and drops the marker channel; both have
      -- to be put back or the phone goes quiet without saying so
      BT.chatLogArmed = nil
      if ChainDB.logSignal then
        if C_Timer and C_Timer.After then C_Timer.After(8, BT.EnableSignal)
        else BT.EnableSignal() end
      end
    else
      BT.Sync()
    end
    BT.ScanQuests()
  elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_XP_UPDATE" then
    if event == "PLAYER_LEVEL_UP" then ChainCharDB.levelAt = time() end
    -- both fire on a level; Delta() reads the bar so the second one is a
    -- no-op rather than a double count
    BT.LearnXP()
    local d = BT.Delta()
    if d > 0 then
      BT.AddXP(d)
      local r = ChainCharDB.run
      if r then
        r.xp = (r.xp or 0) + d
        if not r.instId and UnitGUID then BT.NoteInstance(UnitGUID("target")) end
      end
    end
    BT.ScanQuests()
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    -- This fires many times a second in a pull. We only want one thing from
    -- it - the instance id out of a nearby unit's GUID - and once we have it
    -- there is nothing left to do, so return before any redraw.
    local r = ChainCharDB.run
    local watching = ChainDB.watchEnemies and BT.NoteCombatLogUnit
    if (not r or r.instId) and not watching then return end
    if CombatLogGetCurrentEventInfo then
      local _, sub, _, src, srcName, srcFlags, _, dst, dstName, dstFlags,
            _, spellId, spellName = CombatLogGetCurrentEventInfo()
      if r and not r.instId then
        BT.NoteInstance(src)
        if not r.instId then BT.NoteInstance(dst) end
      end
      -- the combat log reaches further than any nameplate: somebody casting
      -- two rooms away is in it
      if watching then
        -- the spell goes with the caster only: what somebody was hit by says
        -- nothing about them
        -- the spell goes with the caster only, and so does what it says
        -- about whether they can be seen
        BT.NoteCombatLogUnit(src, srcName, srcFlags, spellId, sub, spellName,
                             true)
        BT.NoteCombatLogUnit(dst, dstName, dstFlags)
        -- who beat whom, which is the one piece of history about a player
        -- that is genuinely yours rather than the server's
        if BT.NoteFight then
          BT.NoteFight(sub, src, srcName, srcFlags, dst, dstName, dstFlags)
        end
      end
      -- The name of whatever just died, kept against its GUID. The loot
      -- window will name the corpse it is showing, but only as a GUID - and
      -- the only place that GUID was ever given a name is here.
      if sub == "UNIT_DIED" and BT.NoteCorpse and dst and dstName then
        BT.NoteCorpse(dst, dstName)
      end
    end
    return
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    local r = ChainCharDB.run
    if r then r.k = (r.k or 0) + 1 end
  elseif event == "CHAT_MSG_SYSTEM" then
    BT.NoteResetSystem(...)
  elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER"
      or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
    local msg, sender = ...
    BT.NoteResetChat(msg, sender)
    BT.NotePackRun(msg, sender)
  elseif event == "READY_CHECK" then
    -- Blizzard's own popup and sound already handle this in the room. The only
    -- thing missing is that it never reaches your phone, so all we add is the
    -- marker line for the watcher script.
    local who = ...
    BT.readyCheckAt = time()
    BT.readyCheckBy = who and BT.ShortName(who) or nil
    BT.Signal("readycheck", (BT.readyCheckBy or "someone") .. " started a ready check")
  elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN"
      or event == "PLAYER_PVP_KILLS_CHANGED"
      or event == "PLAYER_PVP_RANK_CHANGED" or event == "UPDATE_FACTION" then
    if BT.PollHonor then BT.PollHonor() end
  elseif event == "QUEST_LOG_UPDATE" then
    BT.ScanQuests()
  else
    BT.Sync()
    BT.ScanQuests()
  end
  if BT.Refresh then BT.Refresh() end
  if BT.RenderWindow then BT.RenderWindow() end
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", BT.OnEvent)
