-- Chain: the bar on screen and the lines under it.
--
-- The layout rule that matters: we break the lines ourselves. Letting the
-- frame wrap means it breaks wherever it runs out of pixels, which lands in
-- the middle of a phrase. BT.Pack only ever breaks between chunks.

local ADDON, BT = ...
local K = BT.K
local C = BT.COL

-- How much fits on one line under the bar. The lines are centred under a
-- 380-pixel bar and are allowed to be a little wider than it, which is what
-- keeps the summary on one line instead of shedding its last chunk onto a
-- second one that comes and goes.
local BUDGET = 74
local bar

-- ...but how much that is depends on the face. The budget is in characters
-- because the text is built long before there is a frame to measure it in,
-- and seventy-four was measured once, in the face the addon used at the time.
-- Ship a different face and the same seventy-four characters draw straight
-- over each other - which is exactly what happened.
--
-- So the number is measured instead of remembered: a sample of the kind of
-- thing that actually goes down there, drawn in the real font, gives the width
-- of an average character, and the budget is however many of those fit. The
-- 1.17 is the old slack - the lines are centred under the bar and are allowed
-- to run a little past it, which is what keeps the summary on one line rather
-- than shedding its last chunk onto a second one that comes and goes.
local SAMPLE = "11,704 xp/run   5m/run   (5 - 43m left)   ~400g (1x10)"
local budgetFor
local function Chars(factor, fallback)
  local w = (ChainDB and ChainDB.width) or 380
  local face = (BT.Face and BT.Face().key) or "?"
  if not (budgetFor and budgetFor.face == face and budgetFor.w == w) then
    local fs = bar and bar.bottomLeft
    if not fs or not fs.GetStringWidth then return fallback end
    local keep = fs:GetText()
    fs:SetText(SAMPLE)
    local px = fs:GetStringWidth() or 0
    fs:SetText(keep or "")
    if px <= 0 then return fallback end
    budgetFor = { face = face, w = w, per = px / #SAMPLE }
  end
  return math.max(20, math.floor(w * factor / budgetFor.per))
end

local function Budget() return Chars(1.17, BUDGET) end

-- The corners get a tighter one, and this is the part that was wrong from the
-- start. The packed lines are centred under the bar and may run past both ends
-- of it - that is what the slack above is for. The two corners are pinned to
-- the two ends, so anything past the bar's own width is one drawn on top of
-- the other. They were being measured against the padded number.
local function CornerBudget() return Chars(0.98, math.floor(BUDGET / 1.17)) end
-- and the measurement is thrown away when the face changes under it
function BT.ForgetBudget() budgetFor = nil end
BT.Budget = Budget
-- the level markers drawn inside the bar, kept here rather than on the frame
local ticks = {}
-- and the milestone marks on the honour bar under it
local hticks = {}
local HONOR_H = 12

--------------------------------------------------------------------------
-- The text
--------------------------------------------------------------------------
-- The two bottom corners are one line: a fontstring pinned to the left end of
-- the bar and another pinned to the right, with nothing between them but the
-- bar's width. Text that does not fit there does not wrap - it draws straight
-- over the other corner, which is how "8,881 xp/run" ended up on top of
-- "7m left" on top of the booster's name.
--
-- So they are measured together, and whatever does not fit goes down to the
-- packed lines underneath, which do wrap.
local function Corners(one, budget)
  local left = one[1]
  local used = BT.VisLen(left)
  local right, spill = {}, {}
  for i = 2, #one do
    local b = one[i]
    local w = BT.VisLen(b)
    if #spill == 0 and used + 3 + w <= budget then
      right[#right + 1] = b
      used = used + 3 + w
    else
      spill[#spill + 1] = b
    end
  end
  return left, (#right > 0) and table.concat(right, "   ") or nil, spill
end

-- The rate, coloured against what this normally gives you.
--
-- A number on its own says nothing: 56,000 xp/h is good in Scarlet Monastery
-- and terrible in Stratholme, and neither of those is something you should
-- have to remember. So it is measured against the thing you are doing.
--
-- In a boost that is the step's own record - experience a run over minutes a
-- run, which is what this dungeon with this booster has actually been paying.
-- Falling short of it means this run is going badly: a slow booster, a wipe,
-- or twenty minutes at the stone.
--
-- On your own it is your own session, once it is long enough to mean
-- anything. That answers the only question you can act on alone - am I going
-- slower than I have been - and it does not pretend to know what a good rate
-- is for the place you happen to be standing.
--
-- No reference, no colour. A green number nobody has checked is worse than a
-- white one.
local function RateColour(rate, step)
  if not rate or rate <= 0 then return nil end
  local ref
  local st = step and BT.StepStats and BT.StepStats(step)
  if st and (st.xp or 0) > 0 and (st.t or 0) > 0 then
    ref = st.xp / st.t * 3600
  else
    local ses = ChainCharDB.session
    local mins = ses and ((time() - (ses.start or time())) / 60) or 0
    if ses and (ses.xp or 0) > 0 and mins >= 20 then
      ref = ses.xp / mins * 60
    end
  end
  if not ref or ref <= 0 then return nil end
  local r = rate / ref
  if r >= 0.95 then return C.good end
  if r >= 0.80 then return C.warn end
  return C.bad
end

-- Average group level, coloured by what the make-up costs you in experience.
local function GroupChunk()
  local avg, n, ratio = BT.GroupInfo()
  if not avg then return nil end
  local txt = string.format("grp %.1f (%d)", avg, n)
  if ratio and ratio < 0.99 then
    txt = txt .. string.format(" %+.0f%% xp", (ratio - 1) * 100)
  end
  local col = C.dim
  if ratio then
    col = (ratio >= 0.90) and C.good or (ratio >= 0.75) and C.warn or C.bad
  end
  return col .. txt .. C.off
end

-- What the reset actually means for you right now. Inside, leave. Outside with
-- a free instance, go. Outside at the limit, "go in" is bad advice - you
-- cannot, so say when you can instead.
local function ResetAlert()
  local rZone, _, rBy, inside = BT.ResetReady()
  if not rZone then
    local fZone, why = BT.ResetFailed()
    if fZone then return C.bad .. "reset failed - " .. why .. C.off end
    return nil
  end
  local by = rBy and (" by " .. rBy) or ""
  local head = BT.Short(rZone) .. " reset" .. by
  if inside then return C.alert .. head .. " - zone out" .. C.off end
  local count, freeOne = BT.Lockout()
  local limit = ChainDB.limit or K.LIMIT
  if count >= limit then
    return C.bad .. head .. " - but you are at " .. count .. "/" .. limit
      .. (freeOne and (", free in " .. BT.T(freeOne)) or "") .. C.off
  end
  return C.good .. head .. " - go in" .. C.off
end

local function LockoutChunk()
  local count, freeOne, freeAll, fromNIT, daily = BT.Lockout()
  local limit = ChainDB.limit or K.LIMIT
  local dayLimit = ChainDB.daily or K.DAILY
  if count == 0 and (daily or 0) == 0 then return nil, 0 end
  local txt = "inst " .. count .. "/" .. limit
  -- "+1 in 9m" next to 3/5 reads as a wait, and there is no wait: you have
  -- two in hand. The clock only answers a question you are asking when the
  -- door is actually shut.
  if count >= limit then
    if freeOne then txt = txt .. " +1 in " .. BT.T(freeOne) end
  else
    txt = txt .. C.dim .. " " .. (limit - count) .. " to go" .. C.off .. C.gold
  end
  if freeAll and count >= limit then
    txt = txt .. " (all " .. BT.T(freeAll) .. ")"
  end
  if fromNIT then txt = txt .. " NIT" end
  if count >= limit then txt = C.bad .. txt .. C.off
  elseif count >= limit - 1 then txt = C.warn .. txt .. C.off end

  -- Only shown if you have set a ceiling of your own; the game no longer
  -- enforces one.
  local dayTxt
  if dayLimit > 0 and daily and daily >= dayLimit * 0.6 then
    dayTxt = "day " .. daily .. "/" .. dayLimit
    if daily >= dayLimit then dayTxt = C.bad .. dayTxt .. C.off
    elseif daily >= dayLimit - 5 then dayTxt = C.warn .. dayTxt .. C.off end
  end
  return txt, count, dayTxt
end

-- Boost mode: the route, the step, the run you are in, the booster
local function BoostText()
  local c = ChainCharDB
  local lvl = UnitLevel("player") or 1
  local done, total, remain, i, step, base = BT.StageSpan()
  if not step then
    return { barLeft = "Level " .. lvl, barRight = "route complete",
             cur = done, max = total }
  end

  local boosted = BT.CurrentBoost()
  local st, borrowed, byWho = BT.StepStats(step)
  local gold = boosted and BT.GoldFor(step) or 0

  -- Fixed slots rather than one centre-justified block. The eye learns where
  -- a number lives and stops reading the line to find it.
  local S = {}
  local plan = BT.Plan()
  -- Name, and the span you set for this step. Deliberately what you typed
  -- and not where you have got to: the arithmetic below has to start from
  -- your current level, because you cannot earn experience you already have,
  -- but the label is the plan. It said "34 > 42" on a step set to 28 > 42 and
  -- changed under you every time you levelled, which is the opposite of what
  -- a heading is for. How far along you are is the bar itself.
  S.topLeft = step.label .. "  " .. (step.from or base or lvl) .. " > " .. step.to
  -- The bar measures the whole step, so this is the bar's own number. It used
  -- to say only "Lvl 34 57%", which is the level - and a bar showing 4% next
  -- to a label saying 57% reads as broken rather than as two different
  -- things. Both are worth knowing; they just have to say which is which.
  do
    local doneSoFar, totalSpan = BT.StepProgress()
    if totalSpan and totalSpan > 0 then
      S.topLeft = S.topLeft .. C.dim .. "  " .. BT.Pct(doneSoFar / totalSpan) .. C.off
    end
  end
  if i and i > 0 and #plan > 1 then
    S.topLeft = S.topLeft .. C.dim .. "  step " .. i .. "/" .. #plan .. C.off
  end
  S.barLeft = "Lvl " .. lvl
  local left, right

  -- The two the bar is for: how many runs you have left, and how long until
  -- you ding. They get the corners to themselves.
  local runsLeft, ding

  -- one: what used to share those corners, now tooltip material. two: the
  -- second line, which is the next thing that happens and the decision it
  -- leads to. three: the run you are in.
  local one, two, three = {}, {}, {}

  -- The reset notice gets a line to itself: it is the one thing you have to
  -- act on, and buried among numbers it is easy to miss.
  local alert = ResetAlert()

  -- Where you are
  local rested = GetXPExhaustion and GetXPExhaustion() or nil
  local mx = UnitXPMax("player") or 0
  local xpNow = UnitXP("player") or 0
  S.barCenter = BT.N(remain) .. " to " .. step.to
  local lvlPlain = S.barLeft
  if mx > 0 then
    S.barLeft = S.barLeft .. C.dim .. "  " .. BT.Pct(xpNow / mx) .. C.off
  end
  if not boosted and (c.run or (IsInGroup and IsInGroup())) then
    table.insert(two, C.dim .. "no booster - own runs" .. C.off)
  end
  -- the group's make-up is in the tooltip, where there is room to say what
  -- it costs you rather than just what it is

  if st and (st.xp or 0) > 0 then
    local avg, avgT = st.xp, st.t or 0
    local runs = remain / avg
    right = string.format("%.1f runs", runs)

    -- whose average this is: the booster's own once he has enough runs,
    -- otherwise every run recorded for the step
    local chunk = BT.N(avg) .. " xp/run"
      .. (borrowed and " (est)"
          or (" (" .. (byWho and (byWho .. " ") or "") .. (st.n or 0) .. ")"))
    if not borrowed and not byWho and (st.long or 0) > 0
       and (st.longN or 0) >= (ChainDB.window or K.WINDOW) + 2 then
      local trend = avg / st.long - 1
      if trend <= -0.15 then
        chunk = C.bad .. chunk .. string.format(" %+.0f%%", trend * 100) .. C.off
      elseif trend >= 0.15 then
        chunk = C.good .. chunk .. string.format(" %+.0f%%", trend * 100) .. C.off
      end
    end
    table.insert(one, chunk)
    if avgT > 0 then
      table.insert(one, BT.T(avgT) .. "/run")
      table.insert(one, "~" .. BT.T(runs * avgT) .. " left")
    end
    -- the estimate is the advertised price; "paid" is what has actually left
    -- your bags on this step. They ride in one chunk so the line never breaks
    -- between a price and the money.
    local paid = BT.Spent and BT.Spent({ id = step.id }) or 0
    local priced = BT.PricePerRun(step, byWho or BT.CurrentBooster())
    if priced > 0 then
      local cost, packs = BT.Cost(step, runs, byWho or BT.CurrentBooster())
      local g = "~" .. BT.G(cost)
      -- how many packs that is, when a pack is more than one run. The gold has
      -- always been whole packs; the bar never said so, so there was no way to
      -- tell it apart from a per-run price.
      local packSize = BT.PackFor(step, byWho or BT.CurrentBooster())
      if packs and packs > 0 and packSize > 1 then
        g = g .. C.dim .. " (" .. packs .. "x" .. packSize .. ")" .. C.off .. C.gold
      end
      if paid > 0 then g = g .. " (paid " .. BT.G(BT.Gold(paid)) .. ")" end
      table.insert(one, C.gold .. g .. C.off)
    elseif paid > 0 then
      table.insert(one, C.gold .. "paid " .. BT.G(BT.Gold(paid)) .. C.off)
    end
    -- What you have already paid for and not yet had. This is the number you
    -- were otherwise keeping on your fingers halfway through a pull, and the
    -- moment it matters is the moment it runs out - so it turns red before
    -- the booster has to ask.
    do
      local credit = BT.BoosterCredit
        and BT.BoosterCredit(byWho or BT.CurrentBooster()) or nil
      if credit then
        -- His own counter first when he has one. His addon announces where you
        -- are in his pack, and that is the number he is charging against -
        -- ours is inferred from when you paid, and the two can honestly
        -- differ. Both are on the tooltip.
        -- Counted the way the pack is sold, because that is how both of you
        -- are thinking about it: "7/10" says how far through you are and how
        -- far there is to go in the same breath, where "3 runs left" is a
        -- number you have to hold against something else to make sense of.
        --
        -- And the last one gets said out loud. It is the one that decides
        -- whether you pay again before the next pull or walk out after it.
        local function Tail(leftN)
          return (leftN > 0 and leftN <= 1.01)
            and (C.warn .. " - last run" .. C.off) or ""
        end
        if credit.hisLeft then
          local v = credit.hisLeft
          local col = (v >= 2) and C.good or ((v > 0) and C.warn or C.bad)
          runsLeft = col .. credit.hisDone .. "/" .. credit.hisOf .. C.off
            .. Tail(v)
        elseif credit.ofPack and credit.ofPack >= 1
           and (credit.donePack or 0) <= credit.ofPack then
          -- the pack he is counting: what the last payment bought, and how
          -- many of those you have had
          local total = math.floor(credit.ofPack + 0.5)
          local done = math.max(0, credit.donePack or 0)
          local leftInPack = total - done
          local col = (leftInPack >= 2) and C.good
            or ((leftInPack > 0) and C.warn or C.bad)
          runsLeft = col .. done .. "/" .. total .. C.off .. Tail(leftInPack)
        else
          local v = credit.left
          local col = (v >= 1) and C.good or ((v > -0.5) and C.warn or C.bad)
          local n = string.format((math.abs(v) < 10) and "%.1f" or "%.0f", v)
          runsLeft = col .. ((v < -0.5)
            and (n:gsub("^%-", "") .. " runs owed")
            or (n .. " runs left")) .. C.off
        end
      end
    end
    local toNext = mx - (UnitXP("player") or 0)
    if toNext > 0 then
      local nr = toNext / avg
      -- "ding in" rather than "lvl 42 in": the bar says which level you are on
      -- and the top line says which stretch you are running, so the number
      -- is the only part that is news
      ding = C.info .. "ding in " .. ((avgT > 0)
        and ("~" .. BT.T(nr * avgT))
        or (string.format("%.1f", nr) .. " runs")) .. C.off
    end
  else
    right = BT.N(remain) .. " xp"
    table.insert(one, "waiting for first completed run")
    local who = BT.CurrentBooster()
    local b = who and ChainDB.boosters[who]
    local pack = BT.PackFor(step, who)
    local quoted = (b and (b.price or 0) > 0) and b.price or BT.GoldFor(step)
    if quoted > 0 then
      table.insert(one, C.gold .. BT.G(quoted)
        .. ((pack > 1) and ("/" .. pack .. " runs") or "/run") .. C.off)
    end
  end

  -- the decision the numbers above are actually for
  local switch = BT.SwitchLine and BT.SwitchLine(step, byWho or BT.CurrentBooster())
  if switch then table.insert(two, switch) end

  local lock, _, dayLock = LockoutChunk()
  S.topRight = lock
  if dayLock then table.insert(two, dayLock) end

  -- The run you are in used to have a line of its own here - experience so
  -- far, mobs, elapsed, pace, and whether it counts. All of it is on the
  -- tooltip now, where there is room to say what it means, and none of it is
  -- something you act on mid-run: you are already in the instance.
  --
  -- The booster's name, his rate, gold per level and experience per gold went
  -- the same way earlier, for the same reason. The bar keeps what you act on.

  -- Two facts under the bar, and only two: how many runs you have left, and
  -- how long until you ding. That is what you are in there for. Everything
  -- else that used to be packed along this line - experience a run, minutes a
  -- run, what it costs, what you have paid - is on the tooltip, where there is
  -- room to say what it means and where it is not sitting on top of the two
  -- numbers you actually came for.
  -- The line directly under the bar, and nothing else on it: how many runs you
  -- have left at one end, when you ding at the other. The bar itself keeps
  -- saying where you are and how far it is; this line is the two numbers you
  -- are actually counting.
  -- and the same in a boost, between the runs you have left and the ding
  do
    local rate = BT.Rate and BT.Rate()
    if rate and rate > 0 then
      local col = RateColour(rate, step)
      S.bottomCenter = (col or "") .. BT.N(rate) .. " xp/h" .. (col and C.off or "")
    end
  end

  local spill = {}
  local facts = {}
  if runsLeft then facts[#facts + 1] = runsLeft end
  if ding then facts[#facts + 1] = ding end
  if #facts > 0 then
    -- one of them alone takes the left corner rather than being centred or
    -- padded out: a single fact is a single fact
    S.bottomLeft, S.bottomRight, spill = Corners(facts, CornerBudget())
  else
    S.bottomLeft, S.bottomRight, spill = Corners(one, CornerBudget())
  end

  -- Two lines under the bar, and always the same two: the run you are in,
  -- then what the step adds up to. Group, ding and the switch advice ride on
  -- the second one rather than claiming a line of their own - a block that
  -- grows and shrinks as figures come and go is a block that moves about
  -- while you are reading it. Everything dropped from here is in the tooltip.
  local lines = {}
  if alert then table.insert(lines, alert) end
  BT.Pack(spill, lines, Budget())
  BT.Pack(three, lines, Budget())
  BT.Pack(two, lines, Budget())
  S.barRight = right
  S.extra = table.concat(lines, "\n")
  -- The fill measures the step you configured, not the stretch left from here.
  -- The label above it says "28 > 42", and a bar sitting at two per cent under
  -- a label that says 28 > 42 while you are level 35 reads as broken.
  S.cur, S.max = BT.StepProgress()
  if not S.max or S.max <= 0 then S.cur, S.max = done, total end
  return S
end

-- At the top of the ladder: the whole bar becomes the week's honour.
--
-- The staircase drawn full size. The fill runs from the milestone you have
-- already banked to the next one, because that gap is the only stretch where
-- the honour you earn is worth anything - and where you are inside it is
-- precisely the question.
local function HonorText()
  local S = {}
  local lvl = UnitLevel("player") or 1
  if not BT.PvPState then
    S.barLeft = "Level " .. lvl
    S.cur, S.max = 1, 1
    return S
  end
  local p = BT.PvPState()

  -- what this week is actually for: the plan's milestone if you have set a
  -- target, otherwise simply the next one
  local goal, short = BT.WeekGoal()

  local from = 0
  if p.met then from = p.met.honor end
  local to = goal and goal.honor or from
  S.cur = math.max(0, (p.honor or 0) - from)
  S.max = math.max(1, to - from)
  if not goal then S.cur, S.max = 1, 1 end

  S.topLeft = p.rankName .. C.dim .. "  " .. BT.Pct(p.progress or 0) .. C.off
  local target = ChainCharDB.pvpTarget
  if target and target > (p.rank or 0) then
    local plan = BT.PlanToRank(target, p.rank, p.progress)
    if plan and #plan.weeks > 0 then
      S.topLeft = S.topLeft .. C.dim .. "  -> " .. BT.RankName(target)
        .. " in " .. #plan.weeks .. (#plan.weeks == 1 and " week" or " weeks") .. C.off
    end
  end
  S.topRight = C.dim .. (p.kills or 0) .. " kills this week" .. C.off
  if goal then
    S.topRight = C.dim .. "for " .. BT.RankName(goal.rank) .. "   "
      .. (p.kills or 0) .. " kills" .. C.off
  end

  -- Shaped like the experience bar, because that is the bar this replaces and
  -- the eye already knows where each number lives: how far along on the left,
  -- what is left in the middle, what you are aiming at on the right.
  S.barLeft = BT.N(p.honor or 0) .. C.dim .. " honor  "
    .. BT.Pct(S.cur / S.max) .. C.off
  if goal then
    -- said as what is missing, because that is the number you go and get
    S.barCenter = C.warn .. BT.N(short) .. " more this week" .. C.off
    S.barRight = BT.N(goal.honor)
  else
    S.barCenter = "this week is spent"
    S.barRight = p.newRankName
  end

  -- the two things you act on: whether the kills are there at all, and where
  -- the week ends if you stop now
  local one = {}
  if not p.enoughKills then
    table.insert(one, C.bad .. p.killsShort .. " more kills before any counts" .. C.off)
  end
  table.insert(one, (p.met and C.good or C.dim) .. "stop now: "
    .. (p.met and (p.newRankName .. " " .. BT.Pct(p.newProgress)) or "no progress")
    .. C.off)
  if p.rate and p.rate > 0 then
    local txt = BT.N(p.rate) .. " honor/h"
    if p.short and p.short > 0 then
      txt = txt .. C.dim .. "  " .. BT.T(p.short / p.rate * 3600) .. " to the next" .. C.off
    end
    table.insert(one, txt)
  end
  local spill
  S.bottomLeft, S.bottomRight, spill = Corners(one, CornerBudget())

  local lines = {}
  local alert = ResetAlert()
  if alert then table.insert(lines, alert) end
  BT.Pack(spill, lines, Budget())
  -- somebody nearby is worth a line here, since this is the bar you are
  -- looking at when you are out in the world rather than in an instance
  local near = BT.Nearby and BT.Nearby() or nil
  if near and #near > 0 then
    table.insert(lines, C.warn .. #near .. " enemy player"
      .. (#near == 1 and "" or "s") .. " nearby" .. C.off)
  end
  S.extra = table.concat(lines, "\n")
  return S
end

-- Regular levelling
local function LevelText(soloStep)
  local c = ChainCharDB
  local lvl = UnitLevel("player") or 1
  local xp, mx = UnitXP("player") or 0, UnitXPMax("player") or 0
  local remain = mx - xp
  local rate = BT.Rate()
  local idle = BT.IdleMin()
  local rested = GetXPExhaustion and GetXPExhaustion() or nil

  local S = {}
  S.barLeft = "Lvl " .. lvl .. C.dim
    .. string.format("  %.1f%%", (mx > 0) and (xp / mx * 100) or 0) .. C.off
  S.barCenter = BT.N(xp) .. " / " .. BT.N(mx)
  -- the same words the boost line uses: which level you are on is already on
  -- the other end of the bar, so the number is the only part that is news
  S.barRight = rate and ("ding in ~" .. BT.T(remain / rate * 3600))
    or (BT.N(remain) .. " xp")

  -- how long you have been at it, in the two top corners
  if c.levelAt then
    S.topLeft = C.dim .. "this level " .. BT.T(time() - c.levelAt) .. C.off
  end
  -- ...unless this stretch is a step of your own, in which case the heading
  -- is the step, the same as it would be for an instance. You are on the plan
  -- either way; this part of it just has nobody to pay.
  if soloStep then
    local plan = BT.Plan()
    local at
    for i, e in ipairs(plan) do if e == soloStep then at = i end end
    S.topLeft = soloStep.label .. "  " .. (soloStep.from or lvl)
      .. " > " .. soloStep.to
      .. (at and (C.dim .. "  step " .. at .. "/" .. #plan .. C.off) or "")
    S.cur, S.max = BT.StepProgress()
  end

  -- say why there is no rate rather than claiming to still be measuring one
  local rateTxt
  if rate then
    local col = RateColour(rate, nil)
    rateTxt = (col or "") .. BT.N(rate) .. " xp/h" .. (col and C.off or "")
  elseif idle and idle > 0 then
    rateTxt = C.dim .. "no xp for " .. BT.T(idle * 60) .. C.off
  else rateTxt = "measuring xp/h" end

  -- The rate goes between the two corners, on the line it is measured
  -- alongside: how much is left on one side, how fast it is coming in in the
  -- middle, when it runs out on the other.
  S.bottomLeft = BT.N(remain) .. " to go"
  S.bottomCenter = rateTxt
  local more = {}

  local ses = c.session
  if ses and (ses.xp or 0) > 0 and idle and idle <= 30 then
    S.topRight = C.dim .. "session " .. BT.N(ses.xp) .. " xp in "
      .. BT.T(time() - (ses.start or time())) .. C.off
  end
  if rested and rested > 0 and mx > 0 and rested / mx >= 0.01 then
    table.insert(more, C.rested .. "rested " .. BT.Pct(rested / mx) .. C.off)
  end
  local qxp, qn = BT.questXP or 0, BT.questCount or 0
  local qgrey = BT.questGrey or 0
  if qxp > 0 then
    local q = C.gold .. "quests ready "
      .. ((mx > 0) and BT.Pct(qxp / mx) or BT.N(qxp)) .. " (" .. qn .. ")"
    -- said out loud rather than silently left out, so the number in the log
    -- and the number here can be reconciled
    if qgrey > 0 then
      q = q .. C.dim .. " +" .. qgrey .. " grey" .. C.off .. C.gold
    end
    if remain - qxp <= 0 then q = q .. " = level " .. (lvl + 1)
    elseif rate then q = q .. " -> ~" .. BT.T((remain - qxp) / rate * 3600) end
    table.insert(more, q .. C.off)
  end
  if BT.Spent then
    local perLevel, spent = BT.SpentPerLevel()
    if spent and spent > 0 then
      local txt = "spent " .. BT.G(BT.Gold(spent))
      if perLevel then txt = txt .. " (" .. BT.G(BT.Gold(perLevel)) .. "/lvl)" end
      table.insert(more, C.gold .. txt .. C.off)
    end
  end
  local grp = GroupChunk()
  if grp then table.insert(more, grp) end
  local lock, lockN, dayLock = LockoutChunk()
  if lock and lockN >= (ChainDB.limit or K.LIMIT) - 1 then
    table.insert(more, lock)
  end
  if dayLock then table.insert(more, dayLock) end

  local lines = {}
  -- a reset is worth saying wherever you are, not only in boost mode
  local alert = ResetAlert()
  if alert then table.insert(lines, alert) end
  BT.Pack(more, lines, Budget())

  -- The step you are heading for, so the target stays visible while questing
  local route = BT.Route()
  if route[1] then
    local step = route[1].e
    local need = BT.Span(lvl, step.to) - xp
    if need < 0 then need = 0 end
    local plan = { step.label .. " > " .. step.to }
    local st, borrowed = BT.StepStats(step)
    if st and (st.xp or 0) > 0 then
      local runs = need / st.xp
      local bb = { string.format("boost ~%.0f runs", runs) }
      -- time is left off on purpose: while questing the question is "pay or
      -- keep going", and the line has to stay inside the frame
      local cost = BT.Cost(step, runs, BT.CurrentBooster())
      if cost > 0 then table.insert(bb, "~" .. BT.G(cost))
      elseif (st.t or 0) > 0 then table.insert(bb, "~" .. BT.T(runs * st.t)) end
      table.insert(plan, table.concat(bb, " ") .. (borrowed and " est" or ""))
    end
    if rate and rate > 0 then
      table.insert(plan, "solo ~" .. BT.T(need / rate * 3600))
    end
    table.insert(lines, C.info .. table.concat(plan, "  ") .. C.off)
  end

  S.extra = table.concat(lines, "\n")
  S.cur, S.max = xp, mx
  return S
end

-- The level the client stops handing out experience at. Asked rather than
-- assumed: this addon runs on Era and on the anniversary realms, and it is
-- not the same number everywhere.
function BT.MaxLevel()
  if GetMaxPlayerLevel then
    local m = GetMaxPlayerLevel()
    if m and m > 0 then return m end
  end
  return _G.MAX_PLAYER_LEVEL or 60
end

function BT.AtMax()
  return (UnitLevel("player") or 1) >= BT.MaxLevel()
end

function BT.Mode()
  local c = ChainCharDB
  -- At the top there is no experience left to measure, so an experience bar
  -- is a bar that will never move again. The week's honour is the only thing
  -- still going up, so that is what the bar becomes - without being asked.
  if BT.AtMax() and ChainDB.honorMode ~= false then return "honor" end
  if c.run then return "boost" end
  if c.lastEnd and (time() - c.lastEnd) < 1200 then return "boost" end
  return "level"
end

-- Every string the bar shows, for tests and for anything that wants to check
-- the layout fits
function BT.AllLines(S)
  S = S or BT.BuildText() or {}
  local out = {}
  for _, k in ipairs({ "topLeft", "topRight", "barLeft", "barCenter", "barRight",
                       "bottomLeft", "bottomCenter", "bottomRight" }) do
    if S[k] and S[k] ~= "" then table.insert(out, S[k]) end
  end
  for line in ((S.extra or "") .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then table.insert(out, line) end
  end
  return out
end

function BT.BuildText()
  local mode = BT.Mode()
  if mode == "honor" then return HonorText() end
  if #BT.Plan() == 0 then return LevelText() end
  -- A stretch you are doing yourself has no booster, no price and no runs, so
  -- the boost bar has nothing to put in any of its slots. It is a levelling
  -- bar with the step's name on it.
  local _, here = BT.Stage()
  if here and here.solo then return LevelText(here) end
  if mode == "boost" then return BoostText() end
  return LevelText()
end

--------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------
local function MakeTexture(parent, layer, sublevel, r, g, b, a)
  local t = parent:CreateTexture(nil, layer, nil, sublevel)
  if t.SetColorTexture then t:SetColorTexture(r, g, b, a)
  else t:SetTexture(r, g, b, a) end
  return t
end

-- The week's honour, drawn as the staircase it is.
--
-- Scaled to the largest milestone open to you this week, with a mark at each
-- one. Two colours, and the difference between them is the whole point:
-- crimson is honour that has already bought a step and cannot be taken away,
-- amber is honour earned since, which is worth precisely nothing until the
-- next mark is crossed. A long amber tail means stop or push - never carry on
-- at the same speed.
function BT.RefreshHonorBar(w)
  if not bar or not bar.honor then return end
  -- and it is not drawn twice: at max level the main bar IS the honour bar
  if BT.Mode and BT.Mode() == "honor" then
    bar.honor:Hide()
    BT.PlaceBarText(false)
    return
  end
  if ChainDB.honorBar == false or not BT.PvPState then
    bar.honor:Hide()
    BT.PlaceBarText(false)
    return
  end
  local p = BT.PvPState()
  local top = p.best and p.best.honor or nil
  -- nothing to draw for somebody who has never been in a fight
  if not top or top <= 0 or ((p.honor or 0) <= 0 and (p.rank or 0) <= 0) then
    bar.honor:Hide()
    BT.PlaceBarText(false)
    return
  end

  w = w or bar:GetWidth() or 0
  local honor = math.min(p.honor or 0, top)
  local banked = p.met and p.met.honor or 0

  local function seg(tex, from, to)
    from, to = math.max(0, from), math.min(top, to)
    if to <= from or w <= 0 then tex:Hide() return end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", bar.honor, "TOPLEFT", w * from / top, 0)
    tex:SetPoint("BOTTOMLEFT", bar.honor, "BOTTOMLEFT", w * from / top, 0)
    tex:SetWidth(w * (to - from) / top)
    tex:Show()
  end
  seg(bar.honor.banked, 0, banked)
  seg(bar.honor.pending, banked, honor)

  local n = 0
  for _, m in ipairs(p.milestones or {}) do
    if m.honor > 0 and m.honor <= top then
      n = n + 1
      local t = hticks[n]
      if not t then
        t = MakeTexture(bar.honor, "ARTWORK", 4, 0, 0, 0, 0.55)
        t:SetWidth(1)
        hticks[n] = t
      end
      t:ClearAllPoints()
      t:SetPoint("TOP", bar.honor, "TOPLEFT", w * m.honor / top, 0)
      t:SetPoint("BOTTOM", bar.honor, "BOTTOMLEFT", w * m.honor / top, 0)
      t:Show()
    end
  end
  for i = n + 1, #hticks do hticks[i]:Hide() end

  -- The one actionable sentence, inside the bar. Kills first when there are
  -- not enough of them, because until there are, none of the honour counts.
  local txt
  if not p.enoughKills then
    txt = C.bad .. p.killsShort .. " more kills before any honor counts" .. C.off
  elseif p.nextMilestone then
    local goal, short = BT.WeekGoal()
    goal = goal or p.nextMilestone
    short = short or p.short
    txt = BT.N(short) .. " more this week" .. C.dim .. "  -> "
      .. BT.RankName(goal.rank) .. C.off
  else
    txt = C.good .. "this week is spent - " .. p.newRankName .. C.off
  end
  bar.honor.fs:SetText(txt)
  bar.honor:Show()
  BT.PlaceBarText(true)
end

-- The two bottom corners and the spill-over line sit under the bar, so they
-- have to move out of the way when the honour bar is there and come back when
-- it is not.
function BT.PlaceBarText(honorShown)
  if not bar or not bar.bottomLeft then return end
  local drop = honorShown and (HONOR_H + 4) or 0
  bar.bottomLeft:ClearAllPoints()
  bar.bottomLeft:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, -3 - drop)
  bar.bottomRight:ClearAllPoints()
  bar.bottomRight:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -2, -3 - drop)
  if bar.bottomCenter then
    bar.bottomCenter:ClearAllPoints()
    bar.bottomCenter:SetPoint("TOP", bar, "BOTTOM", 0, -3 - drop)
  end
  bar.text:ClearAllPoints()
  bar.text:SetPoint("TOP", bar, "BOTTOM", 0, -18 - drop)
end

function BT.InitUI()
  if bar then return end
  local db = ChainDB
  bar = CreateFrame("Frame", "ChainBar", UIParent)
  BT.bar = bar
  bar:SetSize(db.width or 380, 26)
  bar:SetScale(db.scale or 1)
  bar:SetMovable(true)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetClampedToScreen(true)

  local p = db.point or { "CENTER", nil, "CENTER", 0, 200 }
  bar:SetPoint(p[1], UIParent, p[3], p[4], p[5])

  bar.bg = MakeTexture(bar, "BACKGROUND", 0, 0, 0, 0, 0.75)
  bar.bg:SetAllPoints()

  -- rested underneath, quest on top: the gold band is normally the shorter
  -- of the two, so this way you can see both
  bar.rested = MakeTexture(bar, "ARTWORK", 1, 0.25, 0.63, 1, 0.55)
  bar.rested:SetPoint("TOPLEFT")
  bar.rested:SetPoint("BOTTOMLEFT")
  bar.quest = MakeTexture(bar, "ARTWORK", 2, 1, 0.82, 0, 0.7)
  bar.quest:SetPoint("TOPLEFT")
  bar.quest:SetPoint("BOTTOMLEFT")
  bar.fill = MakeTexture(bar, "ARTWORK", 3, 0.13, 0.45, 0.16, 1)
  bar.fill:SetPoint("TOPLEFT")
  bar.fill:SetPoint("BOTTOMLEFT")

  -- A second, slimmer bar underneath for the week's honour.
  --
  -- The honour system is a staircase, so a staircase is what gets drawn: the
  -- marks are the milestones, and the flat stretch between two of them is
  -- honour that buys nothing at all. Seeing that you are standing in the
  -- middle of one of those gaps says it better than any number does.
  bar.honor = CreateFrame("Frame", nil, bar)
  bar.honor:SetHeight(HONOR_H)
  bar.honor:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
  bar.honor:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -2)
  bar.honor.bg = MakeTexture(bar.honor, "BACKGROUND", 0, 0, 0, 0, 0.75)
  bar.honor.bg:SetAllPoints()
  -- banked: honour that has already bought a milestone, and cannot be lost
  bar.honor.banked = MakeTexture(bar.honor, "ARTWORK", 1, 0.62, 0.14, 0.14, 1)
  bar.honor.banked:SetPoint("TOPLEFT")
  bar.honor.banked:SetPoint("BOTTOMLEFT")
  -- pending: earned since, and worth nothing until the next mark is crossed
  bar.honor.pending = MakeTexture(bar.honor, "ARTWORK", 2, 0.55, 0.42, 0.12, 0.85)
  bar.honor.pending:SetPoint("TOPLEFT")
  bar.honor.pending:SetPoint("BOTTOMLEFT")
  bar.honor.fs = bar.honor:CreateFontString(nil, "OVERLAY", "ChainFontHighlightSmall")
  bar.honor.fs:SetPoint("CENTER")
  bar.honor:Hide()

  -- Eight fixed slots: two above, three inside, three below. Every figure has
  -- its own place, so you look at a spot rather than reading a line.
  local function Slot(point, rel, relPoint, x, y, font, just)
    local fs = bar:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint(point, rel, relPoint, x, y)
    fs:SetJustifyH(just)
    return fs
  end

  bar.topLeft     = Slot("BOTTOMLEFT",  bar, "TOPLEFT",      2, 3,
                         "ChainFontHighlightSmall", "LEFT")
  bar.topRight    = Slot("BOTTOMRIGHT", bar, "TOPRIGHT",    -2, 3,
                         "ChainFontHighlightSmall", "RIGHT")
  bar.barLeft     = Slot("LEFT",  bar, "LEFT",   6, 0, "ChainFontNormal", "LEFT")
  bar.barCenter   = Slot("CENTER", bar, "CENTER", 0, 0, "ChainFontNormal", "CENTER")
  bar.barRight    = Slot("RIGHT", bar, "RIGHT", -6, 0, "ChainFontNormal", "RIGHT")
  bar.bottomLeft  = Slot("TOPLEFT",  bar, "BOTTOMLEFT",   2, -3,
                         "ChainFontHighlightSmall", "LEFT")
  bar.bottomRight = Slot("TOPRIGHT", bar, "BOTTOMRIGHT", -2, -3,
                         "ChainFontHighlightSmall", "RIGHT")
  -- Between the two of them rather than inside the bar: the rate belongs on
  -- the line it is measured alongside, halfway between how much is left and
  -- when it runs out.
  bar.bottomCenter = Slot("TOP", bar, "BOTTOM", 0, -3,
                          "ChainFontHighlightSmall", "CENTER")

  bar.barLeft:SetTextColor(1, 1, 1)
  bar.barCenter:SetTextColor(1, 1, 1)
  bar.barRight:SetTextColor(1, 0.82, 0)

  -- anything that did not fit a corner, under the bottom row
  bar.text = bar:CreateFontString(nil, "OVERLAY", "ChainFontHighlightSmall")
  -- centred on the bar, not on the left slot, and clear of the bottom row
  bar.text:SetPoint("TOP", bar, "BOTTOM", 0, -18)
  bar.text:SetJustifyH("CENTER")
  bar.text:SetSpacing(2)

  bar:SetScript("OnDragStart", function(self)
    if not ChainDB.locked then self:StartMoving() end
  end)
  bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local pt, _, rel, x, y = self:GetPoint()
    ChainDB.point = { pt, nil, rel, x, y }
  end)
  bar:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
      if BT.ToggleOptions then BT.ToggleOptions() end
    else
      if BT.ToggleWindow then BT.ToggleWindow() end
    end
  end)
  bar:SetScript("OnEnter", function(self) BT.BarTooltip(self) end)
  bar:SetScript("OnLeave", function() BT.HideBarTooltip() end)

  -- one timer, not one per event: the elapsed-time figures have to tick even
  -- when nothing at all is happening
  bar.elapsed = 0
  bar:SetScript("OnUpdate", function(self, e)
    self.elapsed = self.elapsed + e
    if self.elapsed < 0.25 then return end
    self.elapsed = 0
    BT.Refresh()
    if BT.PollLock then BT.PollLock() end
  end)

  if not db.shown then bar:Hide() end
  BT.Refresh()
end

--------------------------------------------------------------------------
-- The banner
--------------------------------------------------------------------------
-- Deliberately large, deliberately in the way. It is the one thing in this
-- addon you are meant to notice from across the room, and it stays until the
-- situation is over rather than fading after two seconds like a raid warning.
local banner
local function Banner(text, r, g, b)
  if not banner then
    banner = CreateFrame("Frame", "ChainBanner", UIParent)
    banner:SetSize(420, 36)
    -- Anchored to the bar, not to the screen, so wherever you drag the bar
    -- the alert follows. It hangs *under* the lines rather than over the bar:
    -- the bar is usually parked at the top of the screen, and an alert above
    -- it there has nowhere to go.
    banner:SetPoint("TOP", bar.text, "BOTTOM", 0, -10)
    banner:SetClampedToScreen(true)
    banner:SetFrameStrata("HIGH")
    banner:EnableMouse(true)
    banner.edge = MakeTexture(banner, "BACKGROUND", 0, 0.35, 0.28, 0.1, 1)
    banner.edge:SetPoint("TOPLEFT", -1, 1)
    banner.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    banner.bg = MakeTexture(banner, "BACKGROUND", 1, 0.04, 0.03, 0.02, 0.95)
    banner.bg:SetAllPoints()
    banner.fs = banner:CreateFontString(nil, "OVERLAY", "ChainFontNormalLarge")
    banner.fs:SetPoint("CENTER")
    banner.fs:SetJustifyH("CENTER")
    banner.hint = banner:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
    -- the hint follows the banner downwards, so nothing is printed into the
    -- gap between the bar and the alert
    banner.hint:SetPoint("TOP", banner, "BOTTOM", 0, -2)
    banner.hint:SetText("click to dismiss")
    -- a slow pulse, so it reads as an alarm and not as furniture
    banner.t = 0
    banner:SetScript("OnUpdate", function(self, e)
      self.t = self.t + e
      self.fs:SetAlpha(0.55 + 0.45 * math.abs(math.sin(self.t * 2)))
    end)
    banner:SetScript("OnMouseUp", function(self)
      BT.bannerMuted = ChainCharDB.resetAt
      self:Hide()
    end)
    banner:Hide()
  end
  banner.fs:SetText(text)
  banner.fs:SetTextColor(r, g, b)
  if not banner:IsShown() then banner.t = 0 banner:Show() end
end

local function HideBanner() if banner then banner:Hide() end end

function BT.Refresh()
  if not bar then return end
  -- the alert is separate from the bar and does not care whether the bar is
  -- hidden or how small you have made it
  local showedBanner = false
  if not showedBanner and ChainDB.banner
     and BT.bannerMuted ~= ChainCharDB.resetAt then
    local zone, _, _, inside = BT.ResetReady()
    if zone then
      local count = BT.Lockout()
      local limit = ChainDB.limit or K.LIMIT
      if inside then
        Banner(BT.Short(zone) .. " reset - ZONE OUT", 1, 0.7, 0.25)
      elseif count >= limit then
        Banner(BT.Short(zone) .. " reset - BUT YOU ARE AT " .. count .. "/" .. limit,
               1, 0.5, 0.4)
      else
        Banner(BT.Short(zone) .. " reset - GO IN", 0.4, 1, 0.4)
      end
      showedBanner = true
    end
  end
  if not showedBanner then HideBanner() end

  local S = BT.BuildText() or {}
  bar.topLeft:SetText(S.topLeft or "")
  bar.topRight:SetText(S.topRight or "")
  bar.barLeft:SetText(S.barLeft or "")
  bar.barCenter:SetText(S.barCenter or "")
  bar.barRight:SetText(S.barRight or "")
  bar.bottomLeft:SetText(S.bottomLeft or "")
  bar.bottomRight:SetText(S.bottomRight or "")
  bar.bottomCenter:SetText(S.bottomCenter or "")
  bar.text:SetText(S.extra or "")
  -- The centre slot is the first thing to go when the bar is narrow or the
  -- two ends are long; better to drop it than to have three strings overlap.
  local w = bar:GetWidth() or 0
  local function sw(fs) return (fs.GetStringWidth and fs:GetStringWidth()) or 0 end
  local room = w - sw(bar.barLeft) - sw(bar.barRight) - 24
  bar.barCenter:SetShown(room > sw(bar.barCenter))
  -- and the same below, where the rate sits between the two ends
  local under = w - sw(bar.bottomLeft) - sw(bar.bottomRight) - 24
  bar.bottomCenter:SetShown(under > sw(bar.bottomCenter))

  local cur, max = S.cur, S.max
  max = (max and max > 0) and max or 1
  cur = math.min(cur or 0, max)
  local function seg(tex, from, to)
    from, to = math.max(0, from), math.min(max, to)
    if to <= from then tex:Hide() return end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", bar, "TOPLEFT", w * from / max, 0)
    tex:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", w * from / max, 0)
    tex:SetWidth(w * (to - from) / max)
    tex:Show()
  end
  seg(bar.fill, 0, cur)

  -- One tick per level inside the step. Eight levels of experience is a bar
  -- that barely moves in a run, and a bar that barely moves looks broken
  -- however honest it is. The ticks give it something to cross: you can see
  -- which level you are in and how far the next one is, without the fill
  -- having to pretend the step is shorter than it is.
  -- and the ticks are measured on the same scale as the fill
  local step = select(5, BT.StageSpan())
  local _, _, base = BT.StepProgress()
  local shown = 0
  if step and base and BT.Mode() == "boost" then
    for l = base + 1, (step.to or base) - 1 do
      local at = BT.Span(base, l)
      if at and at > 0 and at < max then
        shown = shown + 1
        local t = ticks[shown]
        if not t then
          t = MakeTexture(bar, "ARTWORK", 4, 0, 0, 0, 0.45)
          t:SetWidth(1)
          ticks[shown] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOP", bar, "TOPLEFT", w * at / max, 0)
        t:SetPoint("BOTTOM", bar, "BOTTOMLEFT", w * at / max, 0)
        t:Show()
      end
    end
  end
  for i = shown + 1, #ticks do ticks[i]:Hide() end

  BT.RefreshHonorBar(w)

  -- the overlays only make sense against your own level bar
  if BT.Mode() ~= "boost" or #BT.Plan() == 0 then
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    seg(bar.rested, cur, cur + (rested or 0))
    seg(bar.quest, cur, cur + (BT.questXP or 0))
  else
    bar.rested:Hide()
    bar.quest:Hide()
  end
end

-- The tooltip carries everything that would otherwise have to sit on the bar:
-- the bar is what you glance at, this is what you look at. Anything that can
-- live here instead of out there, does.
-- The tooltip outgrew one column. On a 1080-high screen it ran from the top
-- of the screen to the bottom, which is not a tooltip, it is a page. A second
-- one alongside the first halves the height, and the split is by subject
-- rather than by line count: what you are doing on the left, who you are
-- doing it with and where you stand on the right.
local side
local function SideTip()
  if side then return side end
  side = CreateFrame("GameTooltip", "ChainSideTooltip", UIParent,
                     "GameTooltipTemplate")
  return side
end
BT.SideTooltip = SideTip

-- Which of the two the lines are going to. Everything below writes through
-- this rather than naming a tooltip, so moving the split is moving one line.
local active = nil
local function Tip() return active or GameTooltip end

local function Pair(left, right)
  if right == nil or right == "" then return end
  Tip():AddDoubleLine(left, right, 0.72, 0.72, 0.72, 1, 1, 1)
end

-- Which column a block goes in is a judgement about the block, not about how
-- much room is left: the run you are in belongs with what you are doing, even
-- though the booster's own figures were written before it.
local split = false
local function Column1() active = nil end
local function Column2Again() if split then active = side end end

-- Start the second column, anchored to the right of the first
local function Column2()
  if ChainDB.oneColumn then return end
  split = true
  local t = SideTip()
  t:SetOwner(GameTooltip, "ANCHOR_NONE")
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 2, 0)
  t:ClearLines()
  active = t
  t:AddLine(BT.NAME, 1, 0.82, 0)
end

-- Two columns of different widths, with the pair hanging off to the right of
-- the bar, read as one tooltip that had burst rather than as a layout. Same
-- width, and the pair centred under the bar, is what makes it look deliberate.
--
-- It takes two passes: a tooltip is only as wide as what is in it, so the
-- widths are not known until both have been shown once.
local GAP = 2
local function Balance(owner)
  if not side or not side:IsShown() then return end
  local w = math.max(GameTooltip.GetWidth and GameTooltip:GetWidth() or 0,
                     side.GetWidth and side:GetWidth() or 0)
  if w > 0 and GameTooltip.SetMinimumWidth then
    GameTooltip:SetMinimumWidth(w)
    side:SetMinimumWidth(w)
    GameTooltip:Show()
    side:Show()
  end
  if w <= 0 then w = 260 end
  -- and the pair sits under the middle of the bar rather than starting there
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("TOP", owner, "BOTTOM", -(w + GAP) / 2, -4)
end

function BT.HideBarTooltip()
  -- GameTooltip belongs to the whole game, so the width we forced on it has
  -- to come off again - otherwise every item tooltip in the game inherits it.
  if GameTooltip.SetMinimumWidth then GameTooltip:SetMinimumWidth(0) end
  GameTooltip:Hide()
  if side then side:Hide() end
  active = nil
end

function BT.BarTooltip(owner)
  active, split = nil, false
  if GameTooltip.SetMinimumWidth then GameTooltip:SetMinimumWidth(0) end
  if side and side.SetMinimumWidth then side:SetMinimumWidth(0) end
  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
  Tip():AddLine(BT.NAME)

  -- What is happening now, and nothing else.
  --
  -- This used to be two columns and thirty-odd lines: his price, experience
  -- per gold, what a level costs here against what it costs at the end, the
  -- group's make-up, the whole ledger with him, the rank table. All of it
  -- true, all of it already on a tab, and none of it anything you act on
  -- while standing in a doorway. A tooltip you have to read is a tooltip you
  -- stop opening.
  --
  -- So: where you are, when you ding, what you have left with him, and
  -- whether you can go back in. The comparisons live on History and Boosters,
  -- which is where you go when you are deciding rather than doing.
  local lvl = UnitLevel("player") or 1
  local _, routeStep = BT.Stage()
  local step = routeStep or (BT.FocusStep and BT.FocusStep())

  if BT.Mode() == "honor" then
    local p = BT.HonorPlan and BT.HonorPlan()
    Tip():AddLine("Honour", 1, 1, 1)
    if p then
      Pair("this week", BT.N(p.honor or 0) .. C.dim .. "  " .. (p.kills or 0)
        .. " kills" .. C.off)
      if (p.killsShort or 0) > 0 then
        Pair("before any counts", C.bad .. p.killsShort .. " more kills" .. C.off)
      end
      if p.nextAt then
        Pair("next milestone", BT.N(p.nextAt) .. C.dim .. "  "
          .. BT.N(math.max(0, p.nextAt - (p.honor or 0))) .. " to go" .. C.off)
      end
    end
    local hr = BT.HonorRate and BT.HonorRate()
    if hr and hr > 0 then Pair("honor per hour", BT.N(hr)) end
  elseif not step then
    Tip():AddLine("No route set - right-click to pick your instances",
      0.7, 0.7, 0.7)
  else
    -- where you are
    local head = step.label
    if routeStep then
      local _, _, _, i = BT.StageSpan()
      local plan = BT.Plan()
      head = head .. "  " .. (step.from or lvl) .. " > " .. step.to
      if i and i > 0 and #plan > 1 then
        head = head .. C.dim .. "   step " .. i .. "/" .. #plan .. C.off
      end
    end
    Tip():AddLine(head, 1, 1, 1)

    local remain = select(3, BT.StageSpan())
    local st = BT.StepStats and BT.StepStats(step)
    if remain and remain > 0 then
      local runs = (st and (st.xp or 0) > 0) and (remain / st.xp) or nil
      Pair("left in this step", BT.N(remain) .. " xp"
        .. (runs and (C.dim .. "   " .. string.format("%.1f", runs)
                      .. " runs" .. C.off) or ""))
    end

    -- when you ding
    local rate = BT.Rate and BT.Rate()
    local toNext = (UnitXPMax("player") or 0) - (UnitXP("player") or 0)
    if rate and rate > 0 and toNext > 0 then
      Pair("ding in", "~" .. BT.T(toNext / rate * 3600))
    end

    -- what you have left with him
    local who = BT.CurrentBooster and BT.CurrentBooster()
    local credit = who and BT.BoosterCredit and BT.BoosterCredit(who) or nil
    if credit then
      local v = (credit.hisLeft ~= nil) and credit.hisLeft or credit.left
      local col = (v >= 2) and C.good or ((v > -0.5) and C.warn or C.bad)
      local txt
      if credit.hisLeft ~= nil then
        txt = credit.hisDone .. "/" .. credit.hisOf
      elseif v < -0.5 then
        txt = string.format("%.1f", -v) .. " runs owed"
      elseif credit.ofPack and credit.ofPack >= 1
         and (credit.donePack or 0) <= credit.ofPack then
        txt = math.max(0, credit.donePack or 0) .. "/"
          .. math.floor(credit.ofPack + 0.5)
      else
        txt = string.format("%.1f", v) .. " runs left"
      end
      Pair("with " .. who, col .. txt .. C.off)
    end

    -- whether you can go back in
    local count, freeOne = BT.Lockout()
    local limit = ChainDB.limit or K.LIMIT
    local lockTxt = count .. " of " .. limit .. " this hour"
    if count >= limit then
      lockTxt = C.bad .. lockTxt .. C.off
        .. (freeOne and (C.dim .. "   free in " .. BT.T(freeOne) .. C.off) or "")
    elseif freeOne then
      lockTxt = lockTxt .. C.dim .. "   +1 in " .. BT.T(freeOne) .. C.off
    end
    Pair("instances", lockTxt)

    -- and the run you are in, while you are in it - measured against what
    -- this place usually gives you, because "31,400 xp" is only good news if
    -- you know what the usual is, and a run going badly is something you can
    -- still do something about.
    local r = ChainCharDB.run
    if r and r.zone then
      local dev, over = BT.RunDeviation and BT.RunDeviation(st)
      local elapsed = math.max(0, time() - (r.start or time()))
      local timeTxt = BT.T(elapsed)
      if over and over > 60 then
        timeTxt = C.alert .. timeTxt .. C.off
          .. C.dim .. " (+" .. BT.T(over) .. ")" .. C.off
      end
      local devTxt = ""
      if dev then
        local col = (dev >= 0.15) and C.good
          or ((dev <= -0.15) and C.bad or C.warn)
        devTxt = "   " .. col .. string.format("%+.0f%%", dev * 100) .. C.off
      end
      Pair("this run", timeTxt
        .. C.dim .. "   " .. (r.k or 0) .. " mobs   "
        .. BT.N(r.xp or 0) .. " xp" .. C.off .. devTxt)
      -- and whether it is going to count, which you can still do something
      -- about: walk out and come back in properly
      if r.partial then
        Tip():AddLine("you were part way in when this started, so it is left "
          .. "out of the averages", 0.6, 0.6, 0.6, true)
      end
    end

    -- the one thing you have to act on
    local zone, age, by, inside = BT.ResetReady and BT.ResetReady()
    if zone then
      Tip():AddLine(" ")
      Tip():AddLine(inside and "reset called - get out" or "reset done - go in",
        0.4, 1, 0.4)
    end
  end

  Tip():AddLine(" ")
  Tip():AddLine("Left-click: history, gold and boosters", 0.5, 0.8, 1)
  Tip():AddLine("Right-click: settings", 0.5, 0.8, 1)
  Tip():AddLine("Drag to move" .. (ChainDB.locked and " (locked)" or ""), 0.5, 0.8, 1)
  GameTooltip:Show()
  if active then
    active:Show()
    Balance(owner)
  elseif side then
    side:Hide()
  end
end

function BT.ToggleBar()
  if not bar then return end
  ChainDB.shown = not ChainDB.shown
  if ChainDB.shown then bar:Show() else bar:Hide() end
end
