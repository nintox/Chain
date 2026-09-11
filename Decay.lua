-- Level Tracker: when to move on.
--
-- Experience from a mob falls as you outlevel it and hits zero when it turns
-- grey. An instance that is excellent at 22 is worthless at 30, so the real
-- question during a boost chain is not "how many more runs" but "how many more
-- runs *here* before somewhere else is cheaper".
--
-- Two sources answer it, in this order:
--
--  1. What you measured. Runs are stored with the level you were, so once an
--     instance has runs at two or more levels the drop is simply observed.
--  2. The game's own arithmetic, anchored to your measurement. The shape of
--     the curve comes from the formula, the size of it from your data, so an
--     error in the model cannot make the absolute numbers wrong - only the
--     slope, and only until you have levelled through enough of it.

local ADDON, BT = ...

--------------------------------------------------------------------------
-- The game's arithmetic
--------------------------------------------------------------------------
-- The level below which a mob is grey and worth nothing.
function BT.GreyLevel(p)
  if p <= 5 then return 0 end
  if p <= 39 then return p - 5 - math.floor(p / 10) end
  if p <= 59 then return p - 1 - math.floor(p / 5) end
  return p - 9
end

-- "Zero difference": how far below you a mob can be before it gives nothing.
local ZD = {
  [1] = 5, [8] = 6, [10] = 7, [12] = 8, [16] = 9, [20] = 11,
  [30] = 12, [40] = 13, [45] = 14, [50] = 15, [55] = 16, [60] = 17
}
function BT.ZeroDiff(p)
  -- a step function: take the entry with the highest start at or below p
  local pick, at = 5, 0
  for from, v in pairs(ZD) do
    if from <= p and from >= at then pick, at = v, from end
  end
  return pick
end

-- Experience one mob of level m is worth to a player of level p, in the
-- game's own units. Only the ratio between levels is used, so the constant
-- does not have to be exactly right.
function BT.MobXP(p, m)
  if m <= BT.GreyLevel(p) then return 0 end
  local base = 45 + 5 * p
  if m >= p then return base * (1 + 0.05 * math.min(m - p, 4)) end
  local frac = 1 - (p - m) / BT.ZeroDiff(p)
  if frac <= 0 then return 0 end
  return base * frac
end

-- What a whole run of this instance is worth at level p, relative to nothing
-- in particular - it is only ever used as a ratio against another level.
function BT.RunValue(step, p)
  local d = step and BT.BY_ID[step.id]
  local range = d and d.mob
  if not range then return nil end
  local total, n = 0, 0
  for m = range[1], range[2] do
    total = total + BT.MobXP(p, m)
    n = n + 1
  end
  if n == 0 then return nil end
  return total / n
end

--------------------------------------------------------------------------
-- What you measured
--------------------------------------------------------------------------
-- Average experience per run at each level you have run this instance at.
-- Cached: the bar redraws four times a second and this walks the whole log.
local perCache, perStamp = {}, nil
function BT.PerLevel(id, boosted)
  local stamp = BT.dirty .. ":" .. #ChainDB.runs
  if stamp ~= perStamp then perCache, perStamp = {}, stamp end
  local key = tostring(id) .. "/" .. tostring(boosted)
  if perCache[key] then return perCache[key] end
  local sums = {}
  for _, r in ipairs(BT.Runs({ id = id, boosted = boosted })) do
    local l = r.lvl
    if l then
      sums[l] = sums[l] or { xp = 0, n = 0 }
      sums[l].xp = sums[l].xp + (r.xp or 0)
      sums[l].n = sums[l].n + 1
    end
  end
  local out = {}
  for l, s in pairs(sums) do out[l] = s.xp / s.n end
  perCache[key] = out
  return out
end

-- Predicted experience per run at `level`, anchored to what you have measured.
-- Returns the figure and where it came from: "measured", "model" or nil.
function BT.PredictRun(step, level)
  if not step then return nil end
  local boosted = BT.CurrentBoost()
  local per = BT.PerLevel(step.id, boosted)
  if per[level] then return per[level], "measured" end

  -- anchor on the nearest level you have actually run
  local anchor, best
  for l in pairs(per) do
    local d = math.abs(l - level)
    if not best or d < best then anchor, best = l, d end
  end
  if not anchor then return nil end

  local here, there = BT.RunValue(step, anchor), BT.RunValue(step, level)
  if not here or not there or here <= 0 then return per[anchor], "model" end
  return per[anchor] * (there / here), "model"
end

--------------------------------------------------------------------------
-- The advice
--------------------------------------------------------------------------
-- Gold per level at `level` in this instance, using the price you have for it
-- and the experience it will be giving by then.
function BT.CostPerLevel(step, level, booster)
  local xp = BT.PredictRun(step, level)
  if not xp or xp <= 0 then return nil end
  local gold = BT.PricePerRun(step, booster)
  local need = BT.XPFor(level)
  if not need or need <= 0 then return nil end
  local runs = need / xp
  if gold <= 0 then return nil, runs end
  return gold * runs, runs
end

-- Every instance we could sensibly move to, cheapest first at this level.
-- Candidates are the ones on your route plus any you have runs for.
local function Candidates()
  local seen, out = {}, {}
  for _, e in ipairs(BT.Plan()) do
    if not seen[e.id] then
      seen[e.id] = true
      -- the route says when you meant to start there; do not suggest a place
      -- before the level you set for it
      table.insert(out, { id = e.id, label = e.label, to = e.to, opens = e.from })
    end
  end
  for _, r in ipairs(BT.Runs({})) do
    local d = r.id and BT.BY_ID[r.id]
    if d and not seen[d.id] then
      seen[d.id] = true
      table.insert(out, { id = d.id, label = d.label, to = d.hi, opens = d.lo })
    end
  end
  return out
end

-- Where you should be at a given level, and what it would cost there.
-- Returns the step, its cost per level, and the cost in the one you are in.
function BT.BestAt(level, current, booster)
  local bestStep, bestCost
  for _, e in ipairs(Candidates()) do
    local cost, runs
    if (e.opens or 1) <= level then cost, runs = BT.CostPerLevel(e, level, booster) end
    -- with no price anywhere, fall back to fewest runs
    local score = cost or (runs and runs * 1000) or nil
    if score and (not bestCost or score < bestCost) then
      bestStep, bestCost = e, score
    end
  end
  local mine = current and select(1, BT.CostPerLevel(current, level, booster)) or nil
  return bestStep, bestCost, mine
end

-- The level at which somewhere else becomes the better buy, looking ahead.
-- Returns level, the instance, and how much better it is there (0..1).
function BT.SwitchAt(step, booster)
  if not step then return nil end
  local now = UnitLevel("player") or 1
  local stop = math.min(step.to or 60, BT.MAX_LEVEL)
  for level = now, stop - 1 do
    local best, bestCost, mine = BT.BestAt(level, step, booster)
    if best and mine and best.id ~= step.id and bestCost < mine * 0.9 then
      return level, best, 1 - (bestCost / mine)
    end
    -- nothing left to gain here at all
    local xp = BT.PredictRun(step, level)
    if not xp or xp <= 0 then
      return level, best, 1
    end
  end
  return nil
end

-- One short line for the bar, or nil when there is nothing to say.
-- The answer only moves when you level, when the log grows or when a price
-- changes, so it is worked out at most once a second rather than on every
-- redraw - the search over levels and instances is not cheap.
local lineCache, lineKey = nil, nil
function BT.SwitchLine(step, booster)
  if not step then return nil end
  local key = table.concat({ BT.dirty, #ChainDB.runs, UnitLevel("player") or 0,
    step.id, tostring(booster), math.floor(time()) }, "|")
  if key == lineKey then return lineCache end
  lineKey = key
  lineCache = BT.ComputeSwitchLine(step, booster)
  return lineCache
end

function BT.ComputeSwitchLine(step, booster)
  local level, best, gain = BT.SwitchAt(step, booster)
  if not level or not best then return nil end
  local now = UnitLevel("player") or 1
  if level > now + 4 then return nil end        -- too far off to act on
  local how = gain and gain >= 0.01
    and string.format(" (%.0f%% cheaper)", gain * 100) or ""
  if level <= now then
    return BT.COL.warn .. "move to " .. best.label .. " now" .. how .. BT.COL.off
  end
  return BT.COL.info .. "move to " .. best.label .. " at " .. level .. how .. BT.COL.off
end
