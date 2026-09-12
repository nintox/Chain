-- Chain: everything derived from the run log.
--
-- The database stores one record per completed run and nothing else. Every
-- number on screen - the rolling average, a booster's rating, the forecast,
-- the history window - is computed from that list on demand. That is the
-- whole reason for being an addon rather than an aura: with the raw runs kept
-- we can ask new questions of old data instead of only ever seeing the five
-- numbers we happened to accumulate at the time.

local ADDON, BT = ...
local K = BT.K

--------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------
function BT.N(v)
  v = math.floor((v or 0) + 0.5)
  local neg = v < 0
  if neg then v = -v end
  local str, out = tostring(v), ""
  while #str > 3 do
    out = "," .. str:sub(-3) .. out
    str = str:sub(1, -4)
  end
  return (neg and "-" or "") .. str .. out
end

function BT.G(v)
  v = math.floor((v or 0) + 0.5)
  if v >= 10000 then return string.format("%.1fk g", v / 1000) end
  return BT.N(v) .. "g"
end

-- Coin, written the way the game writes it. BT.G rounds to whole gold, which
-- is right for a boost price and wrong for a drop: fifteen silver came out as
-- "0g", and a column of noughts says the log is broken rather than that the
-- amounts are small.
function BT.Coin(copper)
  copper = math.floor(math.max(0, tonumber(copper) or 0) + 0.5)
  local g = math.floor(copper / 10000)
  local si = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = BT.N(g) .. "g" end
  if si > 0 then out[#out + 1] = si .. "s" end
  -- copper only when it is all there is, otherwise it is three characters of
  -- nothing on every line
  if c > 0 and g == 0 then out[#out + 1] = c .. "c" end
  if #out == 0 then return "0c" end
  return table.concat(out, " ")
end

function BT.T(sec)
  sec = math.floor(sec or 0)
  if sec < 0 then sec = 0 end
  if sec < 60 then return sec .. "s" end
  local m = math.floor(sec / 60)
  if m < 60 then return m .. "m" end
  return math.floor(m / 60) .. "h " .. (m % 60) .. "m"
end

function BT.Pct(v)
  return string.format("%.1f%%", (v or 0) * 100)
end

function BT.Short(zone, map)
  if not zone and not map then return nil end
  if zone and BT.SHORT[zone] then return BT.SHORT[zone] end
  local list = BT.DungeonsFor(map, zone)
  if list and list[1] then return list[1].label end
  return zone
end

-- "Spelar-Testrealm" -> "Spelar": the realm eats a third of a line
function BT.ShortName(name)
  if type(name) ~= "string" then return nil end
  if Ambiguate then
    local short = Ambiguate(name, "short")
    if short and short ~= "" then return short end
  end
  return name:match("^[^%-]+") or name
end

-- Visible length, ignoring colour escapes
function BT.VisLen(s)
  if not s then return 0 end
  local plain = (s:gsub("|c%x%x%x%x%x%x%x%x", ""))
  plain = (plain:gsub("|r", ""))
  return #plain
end

-- Break chunks into lines that fit, only ever between chunks
function BT.Pack(bits, out, budget)
  budget = budget or 60
  local cur, len = {}, 0
  for _, b in ipairs(bits) do
    if b and b ~= "" then
      local w = BT.VisLen(b)
      if #cur > 0 and len + 3 + w > budget then
        table.insert(out, table.concat(cur, "   "))
        cur, len = {}, 0
      end
      table.insert(cur, b)
      len = len + ((#cur > 1) and 3 or 0) + w
    end
  end
  if #cur > 0 then table.insert(out, table.concat(cur, "   ")) end
  return out
end

--------------------------------------------------------------------------
-- Experience arithmetic
--------------------------------------------------------------------------
-- Experience needed to go from level a to level b
function BT.Span(a, b)
  local total = 0
  for l = a, b - 1 do total = total + BT.XPFor(l) end
  return total
end

-- The level span an instance is meant for, as written in the table rather
-- than as you happened to set your route. Not everybody knows that the
-- Stockades stop being worth anything at 30, and the number is no use kept
-- in a file nobody reads.
function BT.SpanOf(step)
  local d = step and (BT.BY_ID[step.id or step] or step)
  if not d or not d.lo or not d.hi then return nil end
  return d.lo, d.hi
end

function BT.SpanText(step)
  local lo, hi = BT.SpanOf(step)
  if not lo then return nil end
  return lo .. "-" .. hi
end

-- The level the game will let you in at, and whether you are there yet.
function BT.MinLevel(step)
  local d = step and (BT.BY_ID[step.id or step] or step)
  return d and d.min or nil
end

-- "15+" coloured: green once you can walk in, red while you cannot.
function BT.MinChunk(step, level)
  local min = BT.MinLevel(step)
  if not min then return nil end
  level = level or UnitLevel("player") or 1
  local col = (level >= min) and BT.COL.good or BT.COL.bad
  return col .. min .. "+" .. BT.COL.off
end

-- The same thing coloured against where you actually are: green while the
-- instance still suits you, red once you have outgrown it, dim before.
function BT.SpanChunk(step, level)
  local lo, hi = BT.SpanOf(step)
  if not lo then return nil end
  level = level or UnitLevel("player") or 1
  local col = BT.COL.dim
  if level >= lo and level <= hi then col = BT.COL.good
  elseif level > hi then col = BT.COL.bad end
  return col .. lo .. "-" .. hi .. BT.COL.off
end

--------------------------------------------------------------------------
-- The route
--------------------------------------------------------------------------
-- Ticked instances, in level order. A step ends at its "to" level; the step
-- effectively starts at whichever is later, its own "from" or where the
-- previous step left off.
function BT.Plan()
  local db = ChainDB
  local plan = {}
  for _, d in ipairs(BT.DUNGEONS) do
    local r = db.route[d.id]
    if r and r.on and (r.to or 0) > (r.from or 0) then
      table.insert(plan, { id = d.id, zone = d.zone, label = d.label,
                           maps = d.maps, from = r.from, to = r.to,
                           gold = r.gold or 0 })
    end
  end
  table.sort(plan, function(a, b)
    if a.from ~= b.from then return a.from < b.from end
    return a.to < b.to
  end)
  return plan
end

-- The remaining steps, each with the level span still to cover
function BT.Route()
  local lvl = UnitLevel("player") or 1
  local out, floor = {}, lvl
  for i, e in ipairs(BT.Plan()) do
    if e.to > floor then
      local from = math.max(e.from, floor)
      if from < e.to then
        table.insert(out, { e = e, i = i, from = from, to = e.to })
        floor = e.to
      end
    end
  end
  return out
end

-- The step you are on right now
function BT.Stage()
  local r = BT.Route()
  if not r[1] then return nil end
  return r[1].i, r[1].e, r[1].from
end

-- How far through the current step you are.
-- Returns done, total, remaining, index, step, base level
function BT.StageSpan()
  local i, e, base = BT.Stage()
  if not e then return 0, 0, 0, nil, nil, nil end
  local lvl = UnitLevel("player") or 1
  base = math.min(base or lvl, lvl)
  local total = BT.Span(base, e.to)
  local done = BT.Span(base, lvl) + (UnitXP("player") or 0)
  if done > total then done = total end
  return done, total, total - done, i, e, base
end

-- How far through the step **as you set it up**. 28 > 42 on the label means
-- 28 > 42 on the bar, and at level 35 that is halfway, not two per cent.
--
-- Deliberately not StageSpan. That one rebases to your current level, and it
-- has to: runs, hours and gold remaining cannot count experience you already
-- have. Both are right, they answer different questions - and the bar answers
-- this one, because the bar sits directly under the label.
function BT.StepProgress()
  local _, e = BT.Stage()
  if not e then return 0, 0 end
  local from = tonumber(e.from) or 1
  local to = tonumber(e.to) or from
  if to <= from then return 0, 0 end
  local lvl = UnitLevel("player") or 1
  local total = BT.Span(from, to)
  if not total or total <= 0 then return 0, 0 end
  local done
  if lvl >= to then
    done = total
  elseif lvl <= from then
    -- below the step: the bar is empty rather than negative
    done = (lvl == from) and (UnitXP("player") or 0) or 0
  else
    done = BT.Span(from, lvl) + (UnitXP("player") or 0)
  end
  if done > total then done = total end
  if done < 0 then done = 0 end
  return done, total, from, to
end

function BT.GoldFor(step)
  if not step then return 0 end
  local r = ChainDB.route[step.id]
  return (r and tonumber(r.gold)) or 0
end

-- How many runs one price covers here. Three answers, most specific first:
-- the pack the booster's own price was quoted for, the pack this instance is
-- normally sold in, and the setting. They are genuinely different numbers -
-- one man sells Stockade ten at a time and another five, and the same man
-- sells ten in Stockade and five in Scholomance - so a single global figure
-- silently misprices half the route.
function BT.StepPack(step)
  local r = step and ChainDB.route[step.id]
  local p = r and tonumber(r.pack) or nil
  if p and p > 0 then return math.floor(p) end
  return math.max(1, math.floor(ChainDB.pack or 1))
end

function BT.PackFor(step, name)
  local b = name and ChainDB.boosters[name]
  if b and (b.price or 0) > 0 and (b.pack or 0) > 0 then
    return math.max(1, math.floor(b.pack))
  end
  return BT.StepPack(step)
end

-- Cost of a number of runs: whole packs, because that is what you buy
function BT.Cost(step, runs, name)
  if not runs or runs <= 0 then return 0, 0 end
  local pack = BT.PackFor(step, name)
  local b = name and ChainDB.boosters[name]
  if b and (b.price or 0) > 0 then
    local packs = math.ceil(runs / pack)
    return packs * b.price, packs
  end
  local g = BT.GoldFor(step)
  if g <= 0 then return 0, 0 end
  local packs = math.ceil(runs / pack)
  return packs * g, packs
end

--------------------------------------------------------------------------
-- Querying the run log
--------------------------------------------------------------------------
-- filter: { id = step id, zone = zone name, by = booster, boosted = bool,
--           since = timestamp, limit = keep at most N newest }
-- Returns newest-last, which is how the log is stored.
-- The bar redraws four times a second and every line asks the log a question,
-- so the answers are cached until the log actually changes. BT.Touch() is what
-- invalidates them - call it after any write to ChainDB.runs.
BT.dirty = 0
local cache, cacheStamp = {}, nil
function BT.Touch()
  BT.dirty = BT.dirty + 1
  cache = {}
end

function BT.Runs(filter)
  filter = filter or {}
  -- The stamp catches a log that grew or shrank even if nobody called Touch,
  -- so a stale answer cannot outlive a write that forgot to announce itself.
  local stamp = BT.dirty .. ":" .. #ChainDB.runs
  if stamp ~= cacheStamp then
    cache, cacheStamp = {}, stamp
  end
  local sig = table.concat({
    tostring(filter.id), tostring(filter.zone), tostring(filter.by),
    tostring(filter.boosted), tostring(filter.since), tostring(filter.limit)
  }, "|")
  local hit = cache[sig]
  if hit then return hit end

  local out = {}
  local runs = ChainDB.runs
  for i = 1, #runs do
    local r = runs[i]
    local ok = true
    if filter.id and r.id ~= filter.id then ok = false end
    if ok and filter.zone and r.zone ~= filter.zone then ok = false end
    if ok and filter.by and r.by ~= filter.by then ok = false end
    if ok and filter.boosted ~= nil then
      local b = (r.by ~= nil)
      if b ~= filter.boosted then ok = false end
    end
    if ok and filter.since and (r.at or 0) < filter.since then ok = false end
    if ok then table.insert(out, r) end
  end
  if filter.limit and #out > filter.limit then
    local trimmed = {}
    for i = #out - filter.limit + 1, #out do table.insert(trimmed, out[i]) end
    out = trimmed
  end
  cache[sig] = out
  return out
end

-- Averages over a list of runs. `window` limits the average to the newest N
-- while still reporting the all-time figures, so we can show a trend.
function BT.Aggregate(list, window)
  local n = #list
  if n == 0 then return nil end
  local allXP, allT, allK = 0, 0, 0
  for _, r in ipairs(list) do
    allXP = allXP + (r.xp or 0)
    allT = allT + (r.t or 0)
    allK = allK + (r.k or 0)
  end
  window = window or n
  local first = math.max(1, n - window + 1)
  local wx, wt, wk, wn = 0, 0, 0, 0
  for i = first, n do
    wx = wx + (list[i].xp or 0)
    wt = wt + (list[i].t or 0)
    wk = wk + (list[i].k or 0)
    wn = wn + 1
  end
  local last = list[n]
  return {
    xp = wx / wn, t = wt / wn, k = wk / wn, n = wn,
    lastXP = last.xp, lastT = last.t, lastK = last.k, lastAt = last.at,
    long = allXP / n, longT = allT / n, longK = allK / n, longN = n,
    totalXP = allXP, totalT = allT
  }
end

--------------------------------------------------------------------------
-- What the current step is worth
--------------------------------------------------------------------------
-- One booster's own record in one step
function BT.BoosterStats(id, by)
  if not id or not by then return nil end
  local list = BT.Runs({ id = id, by = by })
  if #list < K.BOOSTER_MIN then return nil end
  return BT.Aggregate(list, ChainDB.window or K.WINDOW)
end

-- Averages for a step, in this order:
--   1. the booster you are actually with, once he has enough runs
--   2. the step's own runs in the mode you are in (boosted or self-cleared)
--   3. borrowed from another step in the same zone, or from where you stand
-- Returns stats, borrowed, boosterName
function BT.StepStats(step)
  if not step then return nil end
  local boosted = BT.CurrentBoost()

  if step.id and boosted then
    local who = BT.CurrentBooster()
    local bs = who and BT.BoosterStats(step.id, who)
    if bs then return bs, false, who end
  end

  local window = ChainDB.window or K.WINDOW
  local own = BT.Aggregate(BT.Runs({ id = step.id, boosted = boosted }), window)
  if own then return own, false, nil end

  -- another step in the same instance (DM West vs DM North, say)
  local siblings = BT.DungeonsFor(step.maps and step.maps[1], step.zone)
  if siblings then
    for _, d in ipairs(siblings) do
      if d.id ~= step.id then
        local same = BT.Aggregate(BT.Runs({ id = d.id, boosted = boosted }), window)
        if same then return same, true, nil end
      end
    end
  end

  -- otherwise whatever we are standing in
  local here, hereMap = BT.CurrentZone()
  local list = (here or hereMap) and BT.DungeonsFor(hereMap, here) or nil
  if list then
    for _, d in ipairs(list) do
      local st = BT.Aggregate(BT.Runs({ id = d.id, boosted = boosted }), window)
      if st then return st, true, nil end
    end
  end
  return nil
end

-- Runs and time left for the whole route, plus whether every step had real
-- measurements of its own. Uses the current booster's numbers where we have
-- them, which is what makes the total move when you switch booster.
function BT.Forecast()
  local consumed = UnitXP("player") or 0
  local runs, secs, gold, complete = 0, 0, 0, true
  local boosted = BT.CurrentBoost()
  local who = boosted and BT.CurrentBooster() or nil
  local prev
  for idx, seg in ipairs(BT.Route()) do
    local xp = BT.Span(seg.from, seg.to)
    if idx == 1 then xp = xp - consumed end
    if xp < 0 then xp = 0 end

    local st = who and BT.BoosterStats(seg.e.id, who) or nil
    st = st or BT.Aggregate(BT.Runs({ id = seg.e.id, boosted = boosted }),
                            ChainDB.window or K.WINDOW)
    if not st or (st.xp or 0) <= 0 then
      complete = false
      st = prev
    end
    if st and (st.xp or 0) > 0 then
      local r = xp / st.xp
      runs = runs + r
      if (st.t or 0) > 0 then secs = secs + r * st.t end
      gold = gold + (BT.Cost(seg.e, r, who))
      prev = st
    else
      complete = false
    end
  end
  return runs, secs, complete, gold
end

--------------------------------------------------------------------------
-- Boosters
--------------------------------------------------------------------------
-- What you actually get told per run. A price entered against a booster wins
-- over the step price, because the step price is what the instance usually
-- goes for and the booster price is what this man charges.
function BT.BoosterInfo(name)
  if not name then return nil end
  local b = ChainDB.boosters[name]
  if not b then
    b = { price = 0, pack = 0 }
    ChainDB.boosters[name] = b
  end
  return b
end

-- Boosters sell packs, not single runs: the number you are quoted covers
-- however many runs "Runs per price" says. Storing the pack with the price
-- means changing that setting later cannot silently reprice what you already
-- entered.
function BT.SetPrice(name, gold, pack)
  local b = BT.BoosterInfo(name)
  if not b then return end
  b.price = math.max(0, tonumber(gold) or 0)
  pack = tonumber(pack)
  if pack then
    -- price and pack said together: one statement, and the next one replaces it
    b.pack, b.packSet = math.max(1, math.floor(pack)), nil
  elseif not b.packSet then
    -- no pack said: whatever this instance is normally sold in
    b.pack = BT.StepPack(BT.FocusStep and BT.FocusStep() or nil)
  end
end

-- The pack on its own, for the man who does ten where everyone else does five.
-- Said this way it sticks: retyping his price later does not quietly put him
-- back on the usual number, which is the whole reason the box exists.
function BT.SetPack(name, pack)
  local b = BT.BoosterInfo(name)
  if not b then return end
  pack = tonumber(pack)
  if not pack or pack <= 0 then
    b.pack, b.packSet = 0, nil
    return
  end
  b.pack, b.packSet = math.max(1, math.floor(pack)), true
end

-- Experience per gold: the one number that answers "is he worth it". More
-- mobs pulled means more experience per run, a lower price means more runs for
-- the same gold, and both land in the same figure. Nothing to click.
function BT.XPPerGold(step, name, perRun)
  if not perRun or perRun <= 0 then return nil end
  local gold = BT.PricePerRun(step, name)
  if not gold or gold <= 0 then return nil end
  return perRun / gold
end

-- Grade a figure against the best anyone in this step manages. Returns a
-- colour and a one word verdict.
function BT.Grade(value, best)
  if not value or not best or best <= 0 then return BT.COL.dim, nil end
  local r = value / best
  if r >= 0.9 then return BT.COL.good, "good" end
  if r >= 0.7 then return BT.COL.warn, "ok" end
  return BT.COL.bad, "poor"
end

-- Gold per run for a step, preferring the booster's own price
function BT.PricePerRun(step, name)
  local pack = BT.PackFor(step, name)
  local b = name and ChainDB.boosters[name]
  if b and (b.price or 0) > 0 then
    return b.price / pack, true
  end
  local g = BT.GoldFor(step)
  if g <= 0 then return 0, false end
  return g / pack, false
end

-- Every booster who has run this step for you, best first.
-- Experience per hour is the ranking metric: it folds speed and how much of
-- the instance actually gets pulled into a single number.
local boosterCache, boosterStamp = {}, nil
function BT.BoosterTable(id)
  local stamp = BT.dirty .. ":" .. #ChainDB.runs
  if stamp ~= boosterStamp then boosterCache, boosterStamp = {}, stamp end
  if boosterCache[id or "?"] then return boosterCache[id or "?"] end

  local seen, out = {}, {}
  for _, r in ipairs(BT.Runs({ id = id, boosted = true })) do
    local b = seen[r.by]
    if not b then
      b = { by = r.by, n = 0, xp = 0, t = 0, k = 0, runs = {} }
      seen[r.by] = b
      table.insert(out, b)
    end
    b.n = b.n + 1
    b.xp = b.xp + (r.xp or 0)
    b.t = b.t + (r.t or 0)
    b.k = b.k + (r.k or 0)
    table.insert(b.runs, r)
  end
  for _, b in ipairs(out) do
    b.rate = (b.t > 0) and (b.xp / b.t * 3600) or 0
    b.perRun = b.xp / b.n
    b.timePerRun = b.t / b.n
    b.mobs = b.k / b.n
    -- recent form: his last few runs against his own record
    local recent = BT.Aggregate(b.runs, K.WINDOW)
    if recent and b.n >= K.WINDOW + 2 and recent.t > 0 and b.rate > 0 then
      b.form = (recent.xp / recent.t * 3600) / b.rate - 1
    end
    b.last = b.runs[#b.runs]
  end
  table.sort(out, function(a, b) return a.rate > b.rate end)
  boosterCache[id or "?"] = out
  return out
end

-- The booster table with the automatic verdict worked out: experience per
-- gold for each, and the best of each figure so the rest can be graded
-- against it.
function BT.RatedBoosters(step)
  if not step then return {}, {} end
  local list = BT.Roster and BT.Roster(step.id) or BT.BoosterTable(step.id)
  local best = { rate = 0, mobs = 0, value = 0 }
  for _, b in ipairs(list) do
    b.value = BT.XPPerGold(step, b.by, b.perRun)
    if (b.rate or 0) > best.rate then best.rate = b.rate end
    if (b.mobs or 0) > best.mobs then best.mobs = b.mobs end
    if (b.value or 0) > best.value then best.value = b.value end
  end
  return list, best
end

-- The booster you are with, rated against the best other one in this step.
-- Returns a table, or nil when there is nothing to say yet.
function BT.BoosterRating(id)
  local who = BT.CurrentBooster()
  if not who or not id then return nil end
  local tbl = BT.BoosterTable(id)
  local me, best
  for _, b in ipairs(tbl) do
    if b.by == who then me = b
    elseif not best or b.rate > best.rate then best = b end
  end
  if not me or me.n < 1 or me.rate <= 0 then return nil end
  me.bestOther = best
  me.vsBest = (best and best.rate > 0) and (me.rate / best.rate - 1) or nil
  return me
end

--------------------------------------------------------------------------
-- Group make-up
--------------------------------------------------------------------------
-- In Classic a party splits a mob's experience by level, so your cut is
-- (your level / sum of levels) times a small bonus for group size. Every
-- boostie above your level eats into your share, which is why a low average
-- group level means more experience for you.
-- Returns average level, members counted, your share against the best this
-- group size could realistically be.
function BT.GroupInfo()
  if not (IsInGroup and IsInGroup()) then return nil end
  local my = UnitLevel("player") or 0
  if my <= 0 then return nil end
  local sum, n, top = my, 1, my
  for i = 1, 4 do
    local u = "party" .. i
    if UnitExists(u) then
      local lvl = UnitLevel(u) or 0
      -- level 0 means the client has not learned it yet; skip rather than lie
      if lvl > 0 then
        sum, n = sum + lvl, n + 1
        if lvl > top then top = lvl end
      end
    end
  end
  if n < 2 then return nil end
  local bonus = K.GROUP_BONUS[n] or 1.4
  local share = bonus * my / sum
  -- best case: everyone else at your level, except the one high player if
  -- there is one - you cannot wish a booster smaller
  local bestSum = my * (n - 1) + ((top >= my + K.BOOST_GAP) and top or my)
  local best = bonus * my / bestSum
  return sum / n, n, (best > 0) and (share / best) or nil, top
end
