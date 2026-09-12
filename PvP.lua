-- Chain: the honour system, as Classic Era actually runs it today.
--
-- This is not the 2005 system, and the difference is the whole point of the
-- file. The old one took your week's honour, turned it into a standing, and
-- dragged your rank a fraction of the way towards it - so every extra kill
-- moved the needle a little, and a bad week dragged you back down.
--
-- Since patch 1.14 it is a staircase instead:
--
--   * Each week you have up to FOUR honour milestones, set by the rank you
--     are on. Meet one and you advance; the rank you land on is fixed by
--     which milestone you met.
--   * Honour below the first milestone does nothing at all. Honour between
--     two milestones does nothing. Honour past the last one does nothing.
--     There is no partial credit anywhere in it.
--   * You need at least 15 honourable kills in the week for any of it to
--     count.
--   * You cannot go down. A quiet week drops you to the bottom of the rank
--     you are on and no further.
--
-- Which means the only question worth asking is "which milestone am I going
-- for this week", and the only wrong answer is stopping between two of them.
--
-- The numbers below are the game's, and the award arithmetic is checked
-- against the worked example the ranking addons publish: a player at rank 4
-- and 60% lands on exactly 15,000 / 19,000 / 22,500 / 26,000 contribution
-- points for the four milestones, and this file reproduces all four.

local ADDON, BT = ...
local C = BT.COL

BT.PVP = {
  MAX_RANK = 14,

  -- How much of a rank's worth of contribution points each step up awards.
  -- High rank moves slowly, which is why the top of the ladder takes months
  -- even now that the weekly grind is capped.
  factor = { 1, 1, 1, 0.8, 0.8, 0.8, 0.7, 0.7, 0.6, 0.5, 0.5, 0.4, 0.4, 0.34 },

  -- Contribution points at the bottom and top of each rank
  floor   = { 0, 2000, 5000, 10000, 15000, 20000, 25000, 30000,
              35000, 40000, 45000, 50000, 55000, 60000 },
  ceiling = { 2000, 5000, 10000, 15000, 20000, 25000, 30000, 35000,
              40000, 45000, 50000, 55000, 60000, 65000 },

  -- The honour ladder. honorFor[n] is the honour a week has to reach for the
  -- week to end with you at rank n - and these are the only honour figures in
  -- the system that mean anything. Anything between two of them is the same
  -- as the lower one.
  honorFor = { 0, 4500, 11250, 22500, 33750, 45000, 77500, 110000,
               142500, 175000, 256250, 337500, 418750, 500000 },

  -- Nothing counts without these, however much honour you pile up
  MIN_HK = 15,

  -- five years of Tuesdays: long enough that anything past it is "no"
  MAX_WEEKS = 260
}

--------------------------------------------------------------------------
-- Ranks and contribution points
--------------------------------------------------------------------------
function BT.CPToRank(cp)
  cp = math.max(0, tonumber(cp) or 0)
  local P = BT.PVP
  for i = P.MAX_RANK, 1, -1 do
    if cp >= P.floor[i] then
      local span = P.ceiling[i] - P.floor[i]
      local progress = (span > 0) and ((cp - P.floor[i]) / span) or 0
      if progress > 1 then progress = 1 end
      return i, progress
    end
  end
  return 1, 0
end

function BT.RankCP(rank, progress)
  local P = BT.PVP
  rank = math.max(1, math.min(P.MAX_RANK, math.floor(tonumber(rank) or 1)))
  progress = math.max(0, math.min(1, tonumber(progress) or 0))
  return P.floor[rank] + (P.ceiling[rank] - P.floor[rank]) * progress
end

--------------------------------------------------------------------------
-- One week, one milestone
--------------------------------------------------------------------------
-- The honour a week has to reach for it to end with you on `target`.
--
-- Climbing a single rank is the cheap one: it asks only for the honour of
-- the rank you are already on. Every jump beyond that asks for the honour of
-- the rank you are jumping to, which is why four ranks in a week costs so
-- much more than one.
function BT.MilestoneHonor(rank, target)
  local P = BT.PVP
  rank = math.max(1, math.floor(tonumber(rank) or 1))
  target = math.floor(tonumber(target) or 0)
  if target <= rank or target > P.MAX_RANK then return nil end
  if target > rank + 4 then return nil end          -- four ranks is the most
  if target == rank + 1 then return P.honorFor[rank] end
  return P.honorFor[target]
end

-- What meeting that milestone awards, in contribution points.
--
-- Each rank you climb hands over a fraction of that rank's span. The first
-- one is capped by how far through your current rank you already are - you
-- cannot be paid twice for ground you have already covered - and there is a
-- small bonus in the middle of the ladder. The two flat figures at ranks 9
-- and 11 are the game's own, put there to stop the whole thing being gamed
-- with dishonourable kills.
function BT.CPGain(rank, currentCP, target)
  local P = BT.PVP
  if rank == 0 then rank = 1 end
  target = math.floor(tonumber(target) or 0)
  if target <= rank then return 0, 0 end

  local total, bonus = 0, 0
  local buckets = target - rank
  for key = rank + 1, math.min(target, P.MAX_RANK) do
    local span = P.floor[key] - P.floor[key - 1]
    local gain = span * (P.factor[key] or P.factor[#P.factor])

    if key == rank + 1 then
      if rank == 9 then gain = 3000
      elseif rank == 11 then gain = 2500 end
      -- the cap: what is left of the rank you are standing in
      if span > 0 then
        local left = span * (1 - ((currentCP - P.floor[key - 1]) / span))
        if left < gain then gain = left end
      end
      if (rank == 6 and buckets == 4)
        or (rank == 7 and buckets >= 3)
        or (rank == 8 and (buckets == 2 or buckets == 3))
        or (rank == 9 and buckets >= 3)
        or (rank == 10 and buckets >= 2) then
        bonus = 500
      elseif rank == 8 and buckets == 4 then
        bonus = 1000
      end
    end
    total = total + gain
  end
  return total, bonus
end

-- Every milestone open to you this week, cheapest first. Up to four, fewer
-- near the top of the ladder because there is less ladder left.
function BT.Milestones(rank, progress)
  local P = BT.PVP
  rank = math.floor(tonumber(rank) or 0)
  if rank < 1 then rank = 1 end
  local cp = BT.RankCP(rank, progress)
  local out = {}
  for k = 1, 4 do
    local target = rank + k
    local honor = BT.MilestoneHonor(rank, target)
    if honor then
      local gain, bonus = BT.CPGain(rank, cp, target)
      local newCP = cp + gain + bonus
      local newRank, newProgress = BT.CPToRank(newCP)
      out[#out + 1] = {
        step = k, honor = honor, target = target,
        rank = newRank, progress = newProgress, cp = newCP
      }
    end
  end
  return out
end

-- Where this week's honour has already put you: the best milestone you have
-- actually met. Nothing until the first one, and no credit for anything past
-- the last.
function BT.MetMilestone(rank, progress, honor, kills)
  honor = tonumber(honor) or 0
  local P = BT.PVP
  local enough = (tonumber(kills) or 0) >= P.MIN_HK
  local best
  for _, m in ipairs(BT.Milestones(rank, progress)) do
    if honor >= m.honor and enough then best = m end
  end
  return best
end

-- The next one you have not met, and how much more it wants. This is the
-- number to put on screen: everything between here and there is wasted.
function BT.NextMilestone(rank, progress, honor)
  honor = tonumber(honor) or 0
  for _, m in ipairs(BT.Milestones(rank, progress)) do
    if honor < m.honor then return m, m.honor - honor end
  end
  return nil
end

--------------------------------------------------------------------------
-- Several weeks: the plan
--------------------------------------------------------------------------
-- Week by week to the rank you want, taking the biggest useful step each
-- time. Overshooting is never worth paying for, so the last week takes the
-- smallest milestone that still arrives.
function BT.PlanToRank(targetRank, fromRank, fromProgress)
  local P = BT.PVP
  targetRank = math.max(1, math.min(P.MAX_RANK, math.floor(tonumber(targetRank) or 1)))
  local rank = math.max(1, math.floor(tonumber(fromRank) or 1))
  local progress = tonumber(fromProgress) or 0

  local weeks, total = {}, 0
  if rank >= targetRank then
    return { done = true, weeks = weeks, total = 0, target = targetRank }
  end

  for _ = 1, P.MAX_WEEKS do
    local options = BT.Milestones(rank, progress)
    if #options == 0 then break end
    -- the cheapest option that reaches the target, or the biggest one there is
    local pick = options[#options]
    for _, m in ipairs(options) do
      if m.rank >= targetRank then pick = m break end
    end
    total = total + pick.honor
    weeks[#weeks + 1] = {
      week = #weeks + 1, honor = pick.honor, total = total,
      from = rank, fromProgress = progress,
      rank = pick.rank, progress = pick.progress,
      options = options, picked = pick.step
    }
    if pick.rank <= rank and pick.progress <= progress then break end  -- stuck
    rank, progress = pick.rank, pick.progress
    if rank >= targetRank then
      return { weeks = weeks, total = total, target = targetRank,
               endRank = rank, endProgress = progress }
    end
  end
  return { weeks = weeks, total = total, target = targetRank,
           endRank = rank, endProgress = progress, unreachable = true }
end

--------------------------------------------------------------------------
-- What the client will tell us
--------------------------------------------------------------------------
-- Rank as a number from 1, not the index the API uses, which is offset by
-- four because the first four are the unranked ones.
function BT.MyRank()
  if not UnitPVPRank then return nil end
  local idx = UnitPVPRank("player")
  if not idx or idx <= 4 then return 0 end
  return idx - 4
end

function BT.RankName(rank)
  if not rank or rank <= 0 then return "no rank" end
  if GetPVPRankInfo then
    local name = GetPVPRankInfo(rank + 4, UnitFactionGroup and UnitFactionGroup("player") or nil)
    if name and name ~= "" then return name end
  end
  return "rank " .. rank
end

function BT.MyProgress()
  if GetPVPRankProgress then
    local p = GetPVPRankProgress()
    if p then return math.max(0, math.min(1, p)) end
  end
  return 0
end

function BT.WeekHonor()
  if not GetPVPThisWeekStats then return 0, 0 end
  local kills, honor = GetPVPThisWeekStats()
  return tonumber(honor) or 0, tonumber(kills) or 0
end

function BT.LastWeekHonor()
  if not GetPVPLastWeekStats then return 0, 0, nil end
  local kills, honor, standing = GetPVPLastWeekStats()
  return tonumber(honor) or 0, tonumber(kills) or 0, tonumber(standing)
end

-- Honour per kill, measured rather than assumed - it depends who you are
-- killing and how many of you are sharing it, so nobody else's figure is any
-- use. nil until there is enough of your own to mean anything.
function BT.HonorPerKill()
  local honor, kills = BT.WeekHonor()
  if not kills or kills < 5 or not honor or honor <= 0 then return nil end
  return honor / kills
end

--------------------------------------------------------------------------
-- Honour per hour, the same way experience per hour is done
--------------------------------------------------------------------------
-- Minute buckets rather than a running average, so a break does not quietly
-- halve the rate and a long silence says so instead of lying.
function BT.AddHonor(gained)
  if not gained or gained <= 0 then return end
  local c = ChainCharDB
  c.honorBuckets = c.honorBuckets or {}
  local m = math.floor(time() / 60)
  c.honorBuckets[tostring(m)] = (c.honorBuckets[tostring(m)] or 0) + gained
  for key in pairs(c.honorBuckets) do
    local km = tonumber(key)
    if not km or km < m - 59 then c.honorBuckets[key] = nil end
  end
  c.honorAt = time()
  c.honorSession = (c.honorSession or 0) + gained
end

function BT.HonorRate()
  local c = ChainCharDB
  if not c.honorBuckets then return nil end
  local m = math.floor(time() / 60)
  local mins, total = {}, 0
  for key, v in pairs(c.honorBuckets) do
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
  local tail = m - mins[#mins]
  if tail > 5 then tail = 5 end
  elapsed = elapsed + tail
  if elapsed <= 0 then return nil end
  return total / elapsed * 60
end

-- The honour counter only moves on the server's terms, so rather than reading
-- the kill messages we ask the client what the week total is and take the
-- difference. No text to parse and no locale to get wrong.
function BT.PollHonor()
  local honor = BT.WeekHonor()
  local c = ChainCharDB
  local last = c.honorSeen
  c.honorSeen = honor
  if last and honor > last then BT.AddHonor(honor - last) end
  -- the weekly reset takes it back to zero; that is not a loss to record
  if last and honor < last then c.honorSession = 0 end
end

--------------------------------------------------------------------------
-- Everything on screen wants the same handful of numbers
--------------------------------------------------------------------------
function BT.PvPState()
  local rank = BT.MyRank() or 0
  local progress = BT.MyProgress()
  local honor, kills = BT.WeekHonor()
  local met = BT.MetMilestone(rank, progress, honor, kills)
  local nextOne, short = BT.NextMilestone(rank, progress, honor)
  local all = BT.Milestones(rank, progress)

  return {
    rank = rank, rankName = BT.RankName(rank), progress = progress,
    honor = honor, kills = kills,
    enoughKills = kills >= BT.PVP.MIN_HK,
    killsShort = math.max(0, BT.PVP.MIN_HK - kills),
    milestones = all,
    met = met,
    -- where the week ends if you stop right now
    newRank = met and met.rank or rank,
    newRankName = BT.RankName(met and met.rank or rank),
    newProgress = met and met.progress or progress,
    nextMilestone = nextOne,
    short = short,
    -- the most this week could possibly be worth
    best = all[#all],
    rate = BT.HonorRate(),
    session = ChainCharDB.honorSession or 0
  }
end

-- What to aim at THIS week, and how much of it is still missing.
--
-- Not always the next milestone. If you have set a target rank, the plan says
-- which one this week is supposed to be, and it is often a bigger jump than
-- the next one up - aiming at the small one and stopping there is how a
-- fourteen-week plan quietly becomes a twenty-week one.
--
-- Returns the milestone, the honour still needed for it, and the state.
function BT.WeekGoal()
  local s = BT.PvPState()
  local goal
  local target = ChainCharDB.pvpTarget
  if target and target > (s.rank or 0) then
    local plan = BT.PlanToRank(target, s.rank, s.progress)
    local w1 = plan and plan.weeks and plan.weeks[1]
    if w1 then
      for _, m in ipairs(s.milestones or {}) do
        if m.honor == w1.honor then goal = m end
      end
    end
  end
  -- already past the planned one, or no plan: whatever is next
  if goal and (s.honor or 0) >= goal.honor then goal = s.nextMilestone end
  goal = goal or s.nextMilestone
  if not goal then return nil, 0, s end
  return goal, math.max(0, goal.honor - (s.honor or 0)), s, (target ~= nil)
end

-- One line, for the bar
function BT.PvPChunk()
  local s = BT.PvPState()
  if (s.honor or 0) <= 0 and (s.rank or 0) <= 0 then return nil end
  if not s.enoughKills then
    return C.warn .. BT.N(s.honor) .. " honor  -  " .. s.killsShort
      .. " more kills before any of it counts" .. C.off
  end
  if s.nextMilestone then
    return C.dim .. BT.N(s.honor) .. " honor" .. C.off .. "  "
      .. C.warn .. BT.N(s.short) .. " more" .. C.off
      .. C.dim .. " -> " .. BT.RankName(s.nextMilestone.rank) .. C.off
  end
  return C.good .. BT.N(s.honor) .. " honor  ->  " .. s.newRankName
    .. "  (the most this week can give)" .. C.off
end
