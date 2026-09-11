-- Chain: the honour system.
--
-- What a week of honour is actually worth. The game shows you a number of
-- honour points and a rank bar and leaves you to work out the rest, and the
-- rest is the only part anybody cares about: what rank am I on Tuesday, and
-- how much more do I need tonight to not go backwards.
--
-- The arithmetic is the honour system's own, and it is a chain of three
-- steps, none of which the client does for you:
--
--   honour  ->  contribution points, at one of three exchange rates
--   CP      ->  a rank and a position inside it
--   that    ->  a fraction of the way from where you are to where the CP says
--               you should be, and the fraction shrinks as the rank goes up
--
-- The numbers below are that system's constants. They are not a guess and
-- they are not ours - they are how the weekly reset has worked since 2005 -
-- but the prediction they feed is still a model, and it says so on the
-- tooltip rather than pretending to be the server.

local ADDON, BT = ...
local C = BT.COL

BT.PVP = {
  MAX_RANK = 14,

  -- How much of the gap between where you are and where your honour says you
  -- belong you actually travel in one reset. High rank moves slowly, which is
  -- the whole reason rank 14 took people months.
  factor = { 1, 1, 1, 0.8, 0.8, 0.8, 0.7, 0.7, 0.6, 0.5, 0.5, 0.4, 0.4, 0.34 },

  -- Contribution points that mark the bottom and top of each rank
  floor   = { 0, 2000, 5000, 10000, 15000, 20000, 25000, 30000,
              35000, 40000, 45000, 50000, 55000, 60000 },
  ceiling = { 2000, 5000, 10000, 15000, 20000, 25000, 30000, 35000,
              40000, 45000, 50000, 55000, 60000, 65000 },

  -- Honour buys contribution points at three rates, and each one is worse
  -- than the last. This is why the top ranks cost so much more than the
  -- brackets alone suggest.
  --   up to 45,000 honour   20,000 CP
  --   up to 175,000 honour  another 20,000 CP
  --   up to 500,000 honour  another 20,000 CP
  bands = {
    { honor = 45000,  cp = 20000, fromHonor = 0,      fromCP = 0 },
    { honor = 175000, cp = 40000, fromHonor = 45000,  fromCP = 20000 },
    { honor = 500000, cp = 60000, fromHonor = 175000, fromCP = 40000 },
  }
}

--------------------------------------------------------------------------
-- The arithmetic
--------------------------------------------------------------------------
-- Honour earned this week into contribution points
function BT.HonorToCP(honor)
  honor = math.max(0, tonumber(honor) or 0)
  local P = BT.PVP
  for _, b in ipairs(P.bands) do
    if honor <= b.honor then
      local span = b.honor - b.fromHonor
      local gain = b.cp - b.fromCP
      if span <= 0 then return b.fromCP end
      return b.fromCP + (honor - b.fromHonor) / span * gain
    end
  end
  -- past the last band the rate does not improve; 60,000 CP is the ceiling
  local last = P.bands[#P.bands]
  return last.cp
end

-- And back again: the honour a number of contribution points costs
function BT.CPToHonor(cp)
  cp = math.max(0, tonumber(cp) or 0)
  local P = BT.PVP
  for _, b in ipairs(P.bands) do
    if cp <= b.cp then
      local span = b.cp - b.fromCP
      local cost = b.honor - b.fromHonor
      if span <= 0 then return b.fromHonor end
      return b.fromHonor + (cp - b.fromCP) / span * cost
    end
  end
  return P.bands[#P.bands].honor
end

-- Contribution points into a rank and how far through it you are
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

-- Where a rank and a progress sit, in contribution points
function BT.RankCP(rank, progress)
  local P = BT.PVP
  rank = math.max(1, math.min(P.MAX_RANK, math.floor(tonumber(rank) or 1)))
  progress = math.max(0, math.min(1, tonumber(progress) or 0))
  return P.floor[rank] + (P.ceiling[rank] - P.floor[rank]) * progress
end

-- The whole question, in one call: given where you stand and what you have
-- earned this week, where do you stand after the reset?
--
-- Returns the new rank, the new progress, and the change in contribution
-- points - negative when you are going backwards, which is the number most
-- people actually want to see.
function BT.PredictReset(rank, progress, weekHonor)
  local P = BT.PVP
  rank = math.max(1, math.min(P.MAX_RANK, math.floor(tonumber(rank) or 1)))
  local nowCP = BT.RankCP(rank, progress)
  local earnedCP = BT.HonorToCP(weekHonor)
  -- you travel a fraction of the way towards what the week earned you, and
  -- the fraction is set by the rank you are on now
  local f = P.factor[rank] or P.factor[#P.factor]
  local newCP = nowCP + (earnedCP - nowCP) * f
  if newCP < 0 then newCP = 0 end
  local newRank, newProgress = BT.CPToRank(newCP)
  return newRank, newProgress, newCP - nowCP, newCP
end

-- How much honour this week to end up exactly where you are now. Below this
-- you fall; above it you climb. It is the one number worth putting on screen.
function BT.HonorToHold(rank, progress)
  local nowCP = BT.RankCP(rank, progress)
  return BT.CPToHonor(nowCP)
end

-- And how much to reach a given rank at the next reset. Solved rather than
-- searched: the factor is linear, so the CP needed comes straight back out.
function BT.HonorForRank(rank, progress, targetRank, targetProgress)
  local P = BT.PVP
  targetRank = math.max(1, math.min(P.MAX_RANK, math.floor(tonumber(targetRank) or 1)))
  local nowCP = BT.RankCP(rank, progress)
  local wantCP = BT.RankCP(targetRank, targetProgress or 0)
  local f = P.factor[rank] or P.factor[#P.factor]
  if f <= 0 then return nil end
  local needCP = nowCP + (wantCP - nowCP) / f
  if needCP <= nowCP then return 0 end
  if needCP > P.ceiling[P.MAX_RANK] then return nil end   -- not in one week
  return BT.CPToHonor(needCP)
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

-- Honour and kills, this week and last
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
  local newRank, newProgress, change = BT.PredictReset(rank, progress, honor)
  local hold = BT.HonorToHold(rank, progress)
  return {
    rank = rank, rankName = BT.RankName(rank), progress = progress,
    honor = honor, kills = kills,
    newRank = newRank, newRankName = BT.RankName(newRank),
    newProgress = newProgress, change = change,
    hold = hold, short = math.max(0, hold - honor),
    rate = BT.HonorRate(),
    session = ChainCharDB.honorSession or 0,
    nextRank = (rank < BT.PVP.MAX_RANK)
      and BT.HonorForRank(rank, progress, rank + 1, 0) or nil
  }
end

-- One line, for the bar
function BT.PvPChunk()
  local s = BT.PvPState()
  if (s.honor or 0) <= 0 and (s.rank or 0) <= 0 then return nil end
  local arrow, col
  if s.newRank > s.rank then arrow, col = "up to", C.good
  elseif s.newRank < s.rank then arrow, col = "down to", C.bad
  else arrow, col = "holds at", C.dim end
  return col .. BT.N(s.honor) .. " honor  " .. arrow .. " " .. s.newRankName .. C.off
end
