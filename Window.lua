-- Chain: the detail window.
--
-- This is the part an aura cannot do. Every run is kept, so the history is
-- browsable, a bad run can be thrown out, and boosters can be put side by
-- side instead of being summarised into one line on screen.

local ADDON, BT = ...
local C = BT.COL
local ROWS = 16
-- Widened once and forgot to widen the rows to match, which threw during the
-- draw and took the whole tab with it. Derived from the layouts now, so a new
-- column cannot outrun the widgets again.
local MAX_COLS = 16
local win, tabs, rows, page, mode, sortKey, sortDesc
local filter = ""

-- Colour codes must not be searchable, or typing "ff" would match everything
local function Plain(s)
  if type(s) ~= "string" then return "" end
  local p = (s:gsub("|c%x%x%x%x%x%x%x%x", ""))
  return (p:gsub("|r", ""))
end

local function Tex(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer)
  if t.SetColorTexture then t:SetColorTexture(r, g, b, a) else t:SetTexture(r, g, b, a) end
  return t
end

local function Button(parent, label, w, h, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  b.bg = Tex(b, "BACKGROUND", 0.15, 0.15, 0.15, 0.9)
  b.bg:SetAllPoints()
  b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.fs:SetPoint("CENTER")
  b.fs:SetText(label)
  b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.3, 0.3, 0.3, 0.9) end)
  b:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(self.active and 0.25 or 0.15, self.active and 0.25 or 0.15,
                            self.active and 0.35 or 0.15, 0.9)
  end)
  b:SetScript("OnClick", onClick)
  return b
end

--------------------------------------------------------------------------
-- Column layouts
--------------------------------------------------------------------------
-- key is what the sort uses; nil means the column is not sortable
local LAYOUTS = {
  runs = {
    title = "Every run, newest first. Click the x to throw one out of the averages.",
    cols = {
      { "when",     78, "at" },
      { "instance", 90, "zone" },
      { "xp",       55, "xp" },
      { "time",     45, "t" },
      { "mobs",     40, "k" },
      { "xp/h",     55, "rate" },
      { "booster",  70, "by" },
      { "lvl",      30, "lvl" },
      { "grp",      40, "grpAvg" }
    }
  },
  boosters = {
    title = "Everyone selling this step. Type his price and how many runs it "
      .. "buys; the verdict follows. The note is yours and is never shared.",
    cols = {
      { "booster",  84, "by" },
      { "xp/h",     54, "rate" },
      { "xp/run",   56, "perRun" },
      { "time/run", 58, "timePerRun" },
      { "mobs",     42, "mobs" },
      { "runs",     38, "n" },
      { "price/%d run", 76, nil },   -- edit box; %d is the pack size
      { "pack",     36, nil },       -- edit box: his pack, if it is not the usual
      { "gold/lvl", 62, nil },
      { "xp/gold",  62, "value" },
      { "verdict",  50, "value" },
      { "reported", 86, nil },
      { "your note", 120, nil }
    }
  },
  gold = {
    title = "Every trade you completed - gold and goods, both ways. Net is "
      .. "what left your bags after anything traded back.",
    cols = {
      { "when",    74, "at" },
      { "traded",  84, "with" },
      { "paid",    58, "gave" },
      { "got back",58, "got" },
      { "net",     58, "net" },
      { "you gave",128, nil },
      { "he gave", 128, nil },
      { "where",   92, "zone" },
      { "step",    64, "id" },
      { "lvl",     30, "lvl" },
      { "booster", 52, nil }
    }
  },
  enemies = {
    title = "Everyone seen out there, newest first. Click KOS to mark one, "
      .. "or mark a whole guild - marked ones always raise the alarm.",
    cols = {
      { "when",     70, "at" },
      { "who",      96, "name" },
      { "lvl",      38, "level" },
      { "class",    70, "class" },
      { "guild",   118, "guild" },
      { "where",    98, "zone" },
      { "seen",     44, "n" },
      { "how",      74, "how" },
      { "kos",      56, nil },
      { "your note",130, nil }
    }
  },
  groups = {
    title = "Everyone looking rather than selling: LFM, LFG and WTB, from "
      .. "every channel. Type in show only to narrow it to what you want.",
    cols = {
      { "when",     70, "at" },
      { "who",      88, "by" },
      { "what",     64, "kind" },
      { "instance", 86, "zone" },
      { "needs",    78, "needs" },
      { "levels",   52, "levels" },
      { "heard in", 88, "from" },
      { "what he said", 240, nil },
      { "",         64, nil }        -- the whisper button
    }
  },
  reported = {
    title = "What other people's addons told you, kept apart from your own "
      .. "numbers so you always know which are which.",
    cols = {
      { "booster",  90, "by" },
      { "instance", 96, "zone" },
      { "xp/h",     56, "rate" },
      { "xp/run",   60, "perRun" },
      { "time/run", 60, "timePerRun" },
      { "mobs",     46, "mobs" },
      { "price/run",64, "price" },
      { "runs",     46, "runs" },
      { "from",     56, "people" },
      { "heard",    78, "at" }
    }
  },
  ads = {
    title = "Every boost advert read from chat, newest first, whatever "
      .. "instance. Click whisper to ask about the price.",
    cols = {
      { "when",     70, "at" },
      { "booster",  88, "by" },
      { "instance", 86, "zone" },
      { "price",    58, "gold" },
      { "per run",  58, "perRun" },
      { "heard in", 96, "from" },
      { "what he said", 322, nil },
      { "",         64, nil }        -- the whisper button
    }
  },
  locks = {
    title = "Everything that happened to an instance: every one you entered, "
      .. "and every reset. Green still counts against the five per hour.",
    cols = {
      { "when",     86, "t" },
      { "what",     74, "kind" },
      { "instance", 130, "zone" },
      { "character",96, "char" },
      { "counts",   62, nil },
      { "free in",  84, "left" },
      { "source",   70, nil }
    }
  },
  pvp = {
    title = "The rank you want, week by week. Honor below a milestone is "
      .. "worth nothing and honor past one is wasted - so stop on the number.",
    cols = {
      { "week",          56, "week" },
      { "honor to hit", 100, "honor" },
      { "a day",         80, "perDay" },
      { "kills",         66, "kills" },
      { "ends you at",  150, nil },
      { "honor so far", 100, "total" },
      { "",             268, nil }
    }
  },
  route = {
    title = "The plan from here. 'g/lvl now' and 'at the end' are what a "
      .. "level costs there today, and by the time you leave it.",
    cols = {
      { "step",       86, nil },
      { "enter",      40, nil },
      { "good for",   54, nil },
      { "your span",  58, nil },
      { "runs",       48, nil },
      { "time",       58, nil },
      { "gold",       58, nil },
      { "g/lvl now",  66, nil },
      { "at the end", 72, nil },
      { "based on",  150, nil }
    }
  }
}

--------------------------------------------------------------------------
-- Row data per tab
--------------------------------------------------------------------------
-- Green when a run beat the usual, red when it fell short. The comparison is
-- against that instance's own average in the same mode, so a self-cleared run
-- is never measured against a boost.
local function Rate(value, avg, higherIsBetter)
  if not value or not avg or avg <= 0 then return C.dim end
  local d = value / avg - 1
  if not higherIsBetter then d = -d end
  if d >= 0.15 then return C.good end
  if d <= -0.15 then return C.bad end
  return C.warn
end

local function RunRows()
  local out = {}
  -- one average per instance, worked out once rather than per row
  local avgFor = {}
  local function Avg(r)
    local key = (r.id or r.zone or "?") .. (r.by and "/b" or "/s")
    if avgFor[key] == nil then
      avgFor[key] = BT.Aggregate(
        BT.Runs({ id = r.id, zone = (not r.id) and r.zone or nil,
                  boosted = r.by ~= nil })) or false
    end
    return avgFor[key] or nil
  end

  for _, r in ipairs(BT.Runs({})) do
    local a = Avg(r)
    local rate = ((r.t or 0) > 0) and (r.xp / r.t * 3600) or 0
    local aRate = (a and (a.longT or 0) > 0) and (a.long / a.longT * 3600) or nil
    table.insert(out, {
      rec = r,
      at = r.at, zone = r.zone, xp = r.xp, t = r.t, k = r.k,
      rate = ((r.t or 0) > 0) and (r.xp / r.t * 3600) or 0,
      by = r.by, lvl = r.lvl, grpAvg = r.grpAvg,
      tip = {
        BT.Short(r.zone, r.map) or "?",
        date("%A %d %B, %H:%M", r.at or time()),
        BT.N(r.xp or 0) .. " xp, " .. (r.k or 0) .. " mobs, " .. BT.T(r.t)
          .. ((rate > 0) and (", " .. BT.N(rate) .. " xp/h") or ""),
        r.by and ("boosted by " .. r.by) or "cleared it yourself",
        r.grpAvg and string.format("group of %d, average level %.1f",
                                   r.grp or 0, r.grpAvg) or nil
      },
      cells = {
        BT.T(time() - (r.at or time())) .. " ago",
        BT.Short(r.zone, r.map) or "?",
        Rate(r.xp, a and a.long, true) .. BT.N(r.xp) .. C.off,
        -- less time is better
        Rate(r.t, a and a.longT, false) .. BT.T(r.t) .. C.off,
        Rate(r.k, a and a.longK, true) .. tostring(r.k or 0) .. C.off,
        (rate > 0) and (Rate(rate, aRate, true)
          .. string.format("%.0fk", rate / 1000) .. C.off) or "-",
        r.by or (C.dim .. "self" .. C.off),
        tostring(r.lvl or "-"),
        r.grpAvg and string.format("%.1f", r.grpAvg) or "-"
      }
    })
  end
  -- newest first by default
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

-- Which instance the Boosters and Route tabs talk about. The route is the
-- obvious answer, but you can perfectly well have runs recorded with no route
-- set at all, and an empty tab is no way to say so. Fall back to where you are
-- standing, then to whatever you ran most recently.
function BT.FocusStep()
  local _, step = BT.Stage()
  if step then return step end
  local here, hereMap = BT.CurrentZone()
  local list = (here or hereMap) and BT.DungeonsFor(hereMap, here) or nil
  if list and list[1] then return list[1] end
  local runs = ChainDB.runs
  for i = #runs, 1, -1 do
    local d = runs[i].id and BT.BY_ID[runs[i].id]
    if d then return d end
  end
  return nil
end

local function BoosterRows()
  local step = BT.FocusStep()
  if not step then return {} end
  local mx = UnitXPMax("player") or 0
  local out = {}
  local list, best = BT.RatedBoosters(step)
  for _, b in ipairs(list) do
    local quoted, source = BT.QuotedPrice(b.by, step.id)
    local perRunGold = quoted or BT.PricePerRun(step, b.by)
    local gPerLevel = "-"
    if perRunGold > 0 and b.perRun > 0 and mx > 0 then
      gPerLevel = BT.G(perRunGold * (mx / b.perRun))
    end
    local form = "-"
    if b.form then
      local col = (b.form <= -0.15) and C.bad or (b.form >= 0.15) and C.good or C.dim
      form = col .. string.format("%+.0f%%", b.form * 100) .. C.off
    end
    -- what other people measured, kept visibly apart from your own numbers
    local sh = BT.SharedStats(b.by, step.id)
    local others = "-"
    if sh then
      local rate = (sh.timePerRun > 0) and (sh.perRun / sh.timePerRun * 3600) or 0
      others = C.dim .. ((rate > 0) and string.format("%.0fk ", rate / 1000) or "")
        .. string.format("%.0f mobs", sh.mobs) .. C.off
    end
    local info = BT.BoosterInfo(b.by)
    local vCol, vWord = BT.Grade(b.value, best.value)
    local rCol = select(1, BT.Grade(b.rate, best.rate))
    local mCol = select(1, BT.Grade(b.mobs, best.mobs))
    table.insert(out, {
      by = b.by, rate = b.rate, perRun = b.perRun, timePerRun = b.timePerRun,
      mobs = b.mobs, n = b.n, form = b.form, info = info, value = b.value,
      mine = (info.mine and b.n == 0) and true or false,
      cells = {
        ((b.n == 0) and C.dim or "") .. b.by .. ((b.n == 0) and C.off or ""),
        (b.n > 0) and (rCol .. string.format("%.0fk", b.rate / 1000) .. C.off) or "-",
        (b.n > 0) and BT.N(b.perRun) or "-",
        (b.n > 0) and BT.T(b.timePerRun) or "-",
        (b.n > 0) and (mCol .. string.format("%.0f", b.mobs) .. C.off) or "-",
        (b.n > 0) and tostring(b.n) or (C.dim .. "0" .. C.off),
        "",           -- the price box sits here
        "",           -- and his pack size next to it
        (gPerLevel ~= "-") and (C.gold .. gPerLevel .. C.off)
          or (quoted and (C.dim .. BT.G(quoted) .. "/run " .. source .. C.off) or "-"),
        b.value and (vCol .. BT.N(b.value) .. C.off) or "-",
        vWord and (vCol .. vWord .. C.off) or (C.dim .. "no price" .. C.off),
        others,
        ""            -- the note box sits here
      }
    })
  end
  return out
end

local function GoldRows()
  local out = {}
  for _, t in ipairs(BT.Trades({})) do
    local net = (t.gave or 0) - (t.got or 0)
    table.insert(out, {
      at = t.at, with = t.with, gave = t.gave, got = t.got, net = net,
      id = t.id, lvl = t.lvl, zone = t.zone,
      cells = {
        BT.T(time() - (t.at or time())) .. " ago",
        t.with or "?",
        (t.gave or 0) > 0 and BT.G(BT.Gold(t.gave)) or "-",
        (t.got or 0) > 0 and BT.G(BT.Gold(t.got)) or "-",
        (net >= 0 and C.gold or C.good) .. BT.G(BT.Gold(math.abs(net)))
          .. (net < 0 and " in" or "") .. C.off,
        BT.ItemsText(t.gaveItems) and (C.info .. BT.ItemsText(t.gaveItems) .. C.off)
          or (C.dim .. "-" .. C.off),
        BT.ItemsText(t.gotItems) and (C.info .. BT.ItemsText(t.gotItems) .. C.off)
          or (C.dim .. "-" .. C.off),
        t.zone or (C.dim .. "-" .. C.off),
        t.id and (BT.BY_ID[t.id] and BT.BY_ID[t.id].label or t.id) or "-",
        tostring(t.lvl or "-"),
        t.by and (C.good .. "yes" .. C.off) or (C.dim .. "-" .. C.off)
      },
      tip = {
        (t.with or "?") .. "   " .. date("%A %d %B, %H:%M", t.at or time()),
        ((t.gave or 0) > 0 and ("you paid " .. BT.G(BT.Gold(t.gave))) or "")
          .. (BT.ItemsText(t.gaveItems)
              and (((t.gave or 0) > 0 and " and " or "you gave ")
                   .. BT.ItemsText(t.gaveItems)) or ""),
        ((t.got or 0) > 0 and ("he gave " .. BT.G(BT.Gold(t.got))) or "")
          .. (BT.ItemsText(t.gotItems)
              and (((t.got or 0) > 0 and " and " or "he gave ")
                   .. BT.ItemsText(t.gotItems)) or ""),
        t.zone or nil
      }
    })
  end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

-- Everyone who has advertised, from every channel, newest first. This is the
-- list you actually shop from: the Boosters tab answers "who sells the step I
-- am on", and this one answers "who is selling anything at all".
local function AdRows()
  local out = {}
  for name, info in pairs(ChainDB.boosters) do
    if info.adZone and info.adAt then
      local d = BT.BY_ID[info.adZone]
      local pack = ((info.adPack or 1) > 0) and info.adPack or 1
      local gold = info.adPrice or 0
      local perRun = (gold > 0) and (gold / pack) or 0
      local from = tostring(info.adFrom or "chat"):gsub("^channel:", "")
      table.insert(out, {
        by = name, at = info.adAt or 0, zone = d and d.label or info.adZone,
        gold = gold, perRun = perRun, pack = pack, from = from,
        whisper = name,
        cells = {
          BT.T(time() - (info.adAt or time())) .. " ago",
          name,
          d and d.label or info.adZone,
          -- most adverts name no price at all; that is what whisper is for
          (gold > 0) and (C.gold .. BT.G(gold)
            .. ((pack > 1) and (C.dim .. "/" .. pack) or "") .. C.off)
            or (C.dim .. "ask" .. C.off),
          (perRun > 0) and (C.gold .. BT.G(perRun) .. C.off) or "-",
          C.dim .. from .. C.off,
          C.dim .. (info.adText or "") .. C.off,
          ""
        },
        tip = {
          name,
          (d and d.label or info.adZone)
            .. "   " .. BT.T(time() - (info.adAt or time())) .. " ago"
            .. "   " .. from,
          info.adText or "",
          (gold > 0)
            and ("He says " .. BT.G(gold)
                 .. ((pack > 1) and (" for " .. pack .. " runs") or " a run") .. ".")
            or "No price in the advert - click whisper and ask."
        }
      })
    end
  end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

-- The other half of the channel: people looking for a group rather than
-- selling one. Nothing is matched against anything - what was said is kept
-- whole, and the search box is what turns it into a list of one thing.
local KIND_WORD = { lfm = "forming", lfg = "looking", wtb = "wants to buy" }
local KIND_COL = { lfm = C.good, lfg = C.info, wtb = C.gold }

local function GroupRows()
  local out = {}
  local mine = BT.FocusStep()
  for _, g in ipairs(BT.GroupLog()) do
    local d = g.id and BT.BY_ID[g.id]
    local age = time() - (g.at or time())
    local col = KIND_COL[g.kind] or C.dim
    -- a post about the instance you are actually on is the one you want
    local here = mine and g.id == mine.id
    out[#out + 1] = {
      at = g.at, by = g.by, kind = g.kind, needs = g.needs or "",
      levels = g.levels or "", from = g.from,
      zone = d and d.label or (g.id or ""),
      whisper = g.by,
      cells = {
        BT.T(age) .. " ago" .. ((g.n or 1) > 1
          and (C.dim .. " x" .. g.n .. C.off) or ""),
        (here and C.good or "") .. g.by .. (here and C.off or ""),
        col .. (KIND_WORD[g.kind] or g.kind) .. C.off,
        d and ((here and C.good or "") .. d.label .. (here and C.off or ""))
          or (C.dim .. "-" .. C.off),
        g.needs and (C.info .. g.needs .. C.off) or (C.dim .. "-" .. C.off),
        g.levels or (C.dim .. "-" .. C.off),
        C.dim .. tostring(g.from or ""):gsub("^channel:", "") .. C.off,
        C.dim .. (g.text or "") .. C.off,
        ""
      },
      tip = {
        g.by,
        (d and d.label or "no instance named")
          .. "   " .. BT.T(age) .. " ago"
          .. "   " .. tostring(g.from or ""):gsub("^channel:", "")
          .. ((g.n or 1) > 1 and ("   said " .. g.n .. " times") or ""),
        g.text or "",
        (KIND_WORD[g.kind] or g.kind)
          .. (g.needs and (", " .. g.needs) or "")
          .. (g.levels and (", levels " .. g.levels) or "") .. "."
      }
    }
  end
  return out
end

-- One timeline rather than two lists. An evening of boosting is entries and
-- resets alternating, and reading it as one thing is how you see that the
-- chain stalled for eleven minutes waiting for a lockout.
-- Everyone seen out there. The KOS column is a button rather than a tick,
-- because marking somebody is a decision you make once and want to see the
-- result of immediately.
local CLASS_COL = {
  WARRIOR = "|cffc79c6e", PALADIN = "|cfff58cba", HUNTER = "|cffabd473",
  ROGUE = "|cfffff569", PRIEST = "|cffffffff", SHAMAN = "|cff0070de",
  MAGE = "|cff69ccf0", WARLOCK = "|cff9482c9", DRUID = "|cffff7d0a"
}

local function EnemyRows()
  local out = {}
  local now = time()
  for _, e in ipairs(BT.SeenList()) do
    local why, note = BT.IsKOS(e.name, e.guild)
    local age = now - (e.at or now)
    local near = age <= 60
    local col = why and C.bad or near and C.warn or C.dim
    local cls = e.class and (CLASS_COL[e.class] or C.dim) or nil
    out[#out + 1] = {
      at = e.at, name = e.name, level = e.level, class = e.class,
      guild = e.guild, zone = e.zone, n = e.n, how = e.how,
      rec = e, kosWhy = why, note = note,
      cells = {
        col .. BT.T(age) .. " ago" .. C.off,
        col .. e.name .. C.off,
        (e.level and e.level > 0) and tostring(e.level) or (C.dim .. "?" .. C.off),
        cls and (cls .. (e.class or "") .. C.off) or (C.dim .. "-" .. C.off),
        e.guild and ((why == "guild" and C.bad or C.dim) .. e.guild .. C.off)
          or (C.dim .. "-" .. C.off),
        C.dim .. (BT.Short(e.zone) or e.zone or "-") .. C.off,
        C.dim .. tostring(e.n or 1) .. C.off,
        C.dim .. (e.how or "-") .. C.off,
        "",           -- the KOS button sits here
        ""            -- and the note box
      },
      tip = {
        e.name .. ((e.level and e.level > 0) and ("  " .. e.level) or ""),
        (e.class or "") .. (e.guild and ("   <" .. e.guild .. ">") or ""),
        "seen " .. (e.n or 1) .. " time" .. ((e.n or 1) == 1 and "" or "s")
          .. ", last " .. BT.T(age) .. " ago"
          .. (e.zone and (" in " .. e.zone) or ""),
        why and (why == "guild"
          and "marked through his guild - the whole lot raises the alarm"
          or "marked by name - always raises the alarm") or nil,
        note
      }
    }
  end
  return out
end

-- The rank planner.
--
-- Since 1.14 this is a staircase, not a slope: each week has up to four
-- honour milestones and nothing in between them counts for anything. So the
-- useful table is not "how much a week" - it is which number to stop on, this
-- week and every week after, until you are where you wanted to be.
local function PvPRows()
  local s = BT.PvPState()
  local target = ChainCharDB.pvpTarget
  if not target or target <= (s.rank or 0) then
    target = math.min(BT.PVP.MAX_RANK, math.max(1, (s.rank or 0) + 1))
  end
  ChainCharDB.pvpTarget = target

  local plan = BT.PlanToRank(target, s.rank, s.progress)
  local perKill = BT.HonorPerKill()
  local out = {}

  local function Kills(honor)
    if not honor or honor <= 0 then return C.dim .. "15" .. C.off end
    if not perKill or perKill <= 0 then return C.dim .. "?" .. C.off end
    return BT.N(math.max(BT.PVP.MIN_HK, honor / perKill))
  end

  for i, w in ipairs(plan.weeks) do
    local first = (i == 1)
    -- how far off you are this week, and only this week: the weeks after it
    -- have not started, so there is nothing to be short of
    local note = ""
    if first then
      if not s.enoughKills then
        note = C.bad .. s.killsShort .. " more kills before any of it counts" .. C.off
      elseif (s.honor or 0) >= w.honor then
        note = C.good .. "done - stop, the rest of the week is wasted" .. C.off
      else
        note = C.warn .. BT.N(w.honor - (s.honor or 0)) .. " more to go" .. C.off
          .. C.dim .. "  (you have " .. BT.N(s.honor or 0) .. ")" .. C.off
      end
    elseif w.picked and w.picked > 1 then
      note = C.dim .. "a " .. w.picked .. "-rank week" .. C.off
    end

    table.insert(out, {
      week = w.week, honor = w.honor, total = w.total,
      perDay = w.honor / 7, kills = perKill and w.honor / perKill or nil,
      cells = {
        (first and C.gold or "") .. "week " .. w.week .. (first and C.off or ""),
        (first and C.gold or "") .. BT.N(w.honor) .. (first and C.off or ""),
        BT.N(w.honor / 7),
        Kills(w.honor),
        BT.RankName(w.rank) .. C.dim .. "  " .. BT.Pct(w.progress) .. C.off,
        C.dim .. BT.N(w.total) .. C.off,
        note
      },
      tip = (function()
        local t = { "Week " .. w.week .. ": " .. BT.N(w.honor) .. " honor",
          "Ends the week at " .. BT.RankName(w.rank) .. ", "
            .. BT.Pct(w.progress) .. " through.",
          " ",
          "Every milestone open to you that week:" }
        for _, m in ipairs(w.options) do
          t[#t + 1] = "   " .. BT.N(m.honor) .. "  ->  " .. BT.RankName(m.rank)
            .. "  " .. BT.Pct(m.progress)
            .. (m.step == w.picked and "   <- this one" or "")
        end
        t[#t + 1] = " "
        t[#t + 1] = "Anything between two of those is worth the same as the "
          .. "lower one, and anything past the last is worth nothing at all."
        return t
      end)()
    })
  end

  if #out == 0 then
    table.insert(out, { week = 0, cells = {
      "", "", "", "",
      C.good .. BT.RankName(s.rank) .. C.off, "",
      "you are already at " .. BT.RankName(target)
    } })
  end
  return out
end

local function LockRows()
  local out = {}
  for _, e in ipairs(BT.InstanceLog()) do
    local col = e.counts and C.good or C.dim
    table.insert(out, {
      t = e.t, zone = e.zone, char = e.char, left = e.left, kind = "entered",
      cells = {
        col .. BT.T(e.age) .. " ago" .. C.off,
        col .. "entered" .. C.off,
        col .. (BT.Short(e.zone) or "?") .. C.off,
        C.dim .. (e.char or "-") .. C.off,
        e.counts and (C.warn .. "yes" .. C.off) or (C.dim .. "no" .. C.off),
        e.counts and (col .. BT.T(e.left) .. C.off) or "-",
        e.nit and (C.dim .. "from NIT" .. C.off) or (C.dim .. "own" .. C.off)
      }
    })
  end
  for _, r in ipairs(BT.ResetLog()) do
    local age = time() - (r.at or time())
    table.insert(out, {
      t = r.at, zone = r.zone, char = r.char, kind = "reset",
      cells = {
        C.dim .. BT.T(age) .. " ago" .. C.off,
        C.info .. "reset" .. C.off,
        C.info .. (BT.Short(r.zone) or r.zone or "?") .. C.off,
        C.dim .. (r.char or "-") .. C.off,
        C.dim .. "-" .. C.off,
        r.by and (C.dim .. "by " .. r.by .. C.off) or (C.dim .. "-" .. C.off),
        C.dim .. "own" .. C.off
      }
    })
  end
  table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
  return out
end

-- Everything other people have reported, for every instance, in one place
local function ReportedRows()
  local out = {}
  for name, info in pairs(ChainDB.boosters) do
    for id in pairs(info.shared or {}) do
      local sh = BT.SharedStats(name, id)
      local d = BT.BY_ID[id]
      if sh and d then
        local newest = 0
        for _, r in pairs(info.shared[id]) do
          if (r.at or 0) > newest then newest = r.at end
        end
        local rate = (sh.timePerRun > 0) and (sh.perRun / sh.timePerRun * 3600) or 0
        table.insert(out, {
          by = name, zone = d.label, rate = rate, perRun = sh.perRun,
          timePerRun = sh.timePerRun, mobs = sh.mobs, price = sh.price,
          runs = sh.runs, people = sh.people, at = newest,
          cells = {
            name, d.label,
            (rate > 0) and string.format("%.0fk", rate / 1000) or "-",
            (sh.perRun > 0) and BT.N(sh.perRun) or "-",
            (sh.timePerRun > 0) and BT.T(sh.timePerRun) or "-",
            (sh.mobs > 0) and string.format("%.0f", sh.mobs) or "-",
            sh.price and (C.gold .. BT.G(sh.price) .. C.off) or "-",
            tostring(math.floor(sh.runs)),
            C.dim .. sh.people .. (sh.people == 1 and " person" or " people") .. C.off,
            C.dim .. BT.T(time() - newest) .. " ago" .. C.off
          }
        })
      end
    end
  end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

local function RouteRows()
  local out = {}
  local consumed = UnitXP("player") or 0
  local boosted = BT.CurrentBoost()
  local who = boosted and BT.CurrentBooster() or nil
  for idx, seg in ipairs(BT.Route()) do
    local xp = BT.Span(seg.from, seg.to)
    if idx == 1 then xp = xp - consumed end
    if xp < 0 then xp = 0 end
    local st, borrowed, by = BT.StepStats(seg.e)
    -- StepStats answers for the step you are on; for later steps ask directly
    if idx > 1 then
      st = (who and BT.BoosterStats(seg.e.id, who))
        or BT.Aggregate(BT.Runs({ id = seg.e.id, boosted = boosted }),
                        ChainDB.window or BT.K.WINDOW)
      by = (who and BT.BoosterStats(seg.e.id, who)) and who or nil
      borrowed = false
    end
    local runs, tsec, cost, source
    if st and (st.xp or 0) > 0 then
      runs = xp / st.xp
      tsec = (st.t or 0) > 0 and runs * st.t or nil
      -- the booster you are with is the one who will be charging you, so his
      -- price beats the one typed against the instance
      cost = BT.Cost(seg.e, runs, who)
      local _, ownPrice = BT.PricePerRun(seg.e, who)
      source = by and (by .. ", " .. st.n .. " runs")
        or borrowed and "estimate from another step"
        or (st.longN .. " own runs")
      if ownPrice and who then
        source = source .. C.dim .. ", " .. who .. "'s price" .. C.off
      end
    else
      source = C.dim .. "no data yet" .. C.off
    end
    -- what a level costs there now and by the time you leave: the whole point
    -- of the decay model, and the pair of numbers that says when to move on
    local nowCost = BT.CostPerLevel and BT.CostPerLevel(seg.e, seg.from, who)
    local endCost = BT.CostPerLevel
      and BT.CostPerLevel(seg.e, math.max(seg.from, seg.to - 1), who)
    local endTxt = "-"
    if endCost and endCost > 0 then
      local col = C.dim
      if nowCost and nowCost > 0 then
        local up = endCost / nowCost - 1
        col = (up >= 0.5) and C.bad or (up >= 0.2) and C.warn or C.dim
      end
      endTxt = col .. BT.G(endCost) .. C.off
    end
    -- the span the instance is meant for, so the plan can be read without
    -- knowing every dungeon's levels by heart
    local lo, hi = BT.SpanOf(seg.e)
    table.insert(out, {
      tip = {
        seg.e.label,
        "levels " .. seg.from .. " to " .. seg.to
          .. (lo and ("   the place is worth doing at " .. lo .. "-" .. hi) or ""),
        "based on " .. (source and source:gsub("|c%x%x%x%x%x%x%x%x", "")
          :gsub("|r", "") or "nothing yet"),
        (nowCost and nowCost > 0)
          and ("a level here costs about " .. BT.G(nowCost) .. " now"
               .. ((endCost and endCost > nowCost)
                   and (", and " .. BT.G(endCost) .. " by " .. seg.to) or ""))
          or nil
      },
      cells = {
        seg.e.label,
        BT.MinChunk(seg.e, seg.from) or "-",
        lo and (C.dim .. lo .. "-" .. hi .. C.off) or "-",
        seg.from .. " > " .. seg.to,
        runs and string.format("%.1f", runs) or "-",
        tsec and BT.T(tsec) or "-",
        (cost and cost > 0) and (C.gold .. BT.G(cost) .. C.off) or "-",
        (nowCost and nowCost > 0) and (C.gold .. BT.G(nowCost) .. C.off) or "-",
        endTxt,
        source
      }
    })
  end
  return out
end

--------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------
local function Data()
  if mode == "boosters" then return BoosterRows() end
  if mode == "ads" then return AdRows() end
  if mode == "groups" then return GroupRows() end
  if mode == "enemies" then return EnemyRows() end
  if mode == "pvp" then return PvPRows() end
  if mode == "route" then return RouteRows() end
  if mode == "gold" then return GoldRows() end
  if mode == "locks" then return LockRows() end
  if mode == "reported" then return ReportedRows() end
  return RunRows()
end

-- One line under the table saying what the tab adds up to
local function Summary()
  if mode == "pvp" then
    local s2 = BT.PvPState()
    local target = ChainCharDB.pvpTarget or ((s2.rank or 0) + 1)
    local plan = BT.PlanToRank(target, s2.rank, s2.progress)
    local txt = "you are " .. C.gold .. s2.rankName .. C.off
      .. C.dim .. "  " .. BT.Pct(s2.progress or 0) .. " through" .. C.off
      .. "  ->  " .. C.gold .. BT.RankName(target) .. C.off
    if plan.done or #plan.weeks == 0 then
      return txt .. "  -  " .. C.good .. "already there" .. C.off
    end
    txt = txt .. "  -  " .. C.gold .. #plan.weeks .. " week"
      .. (#plan.weeks == 1 and "" or "s") .. C.off
      .. ", " .. C.gold .. BT.N(plan.total) .. C.off .. " honor in all"
    if plan.unreachable then
      txt = txt .. "  -  " .. C.bad .. "and it stalls before it gets there" .. C.off
    end
    if not s2.enoughKills then
      txt = txt .. C.dim .. "  -  every week needs " .. BT.PVP.MIN_HK
        .. " honorable kills too" .. C.off
    end
    return txt
  end
  if mode == "gold" then
    local perLevel, spent, levels = BT.SpentPerLevel()
    if not spent or spent == 0 then return "nothing paid yet" end
    local txt = "paid " .. BT.G(BT.Gold(spent)) .. " in total"
    if perLevel and levels then
      txt = txt .. "  -  " .. BT.G(BT.Gold(perLevel)) .. " per level over "
        .. levels .. " level" .. (levels == 1 and "" or "s")
    end
    local byB = BT.SpentByBooster()
    if byB[1] then
      txt = txt .. "  -  most to " .. byB[1].with .. " (" .. BT.G(BT.Gold(byB[1].net)) .. ")"
    end
    return txt
  elseif mode == "locks" then
    local count, freeOne, _, fromNIT, daily = BT.Lockout()
    local limit = ChainDB.limit or BT.K.LIMIT
    local col = (count >= limit) and C.bad or (count >= limit - 1) and C.warn or C.good
    local txt = col .. "last hour: " .. count .. "/" .. limit .. C.off
      .. "   last 24 hours: " .. (daily or 0)
    if count >= limit and freeOne then
      txt = txt .. "   " .. C.bad .. "locked out - next instance in "
        .. BT.T(freeOne) .. C.off
    elseif freeOne then
      txt = txt .. "   one frees up in " .. BT.T(freeOne)
    end
    if fromNIT then txt = txt .. C.dim .. "   (from Nova Instance Tracker)" .. C.off end
    return txt
  elseif mode == "reported" then
    if not ChainDB.share then
      return C.dim .. "sharing is off - nothing is sent and nothing is received."
        .. " Turn it on in the settings." .. C.off
    end
    local n = #ReportedRows()
    if n == 0 then
      return "nothing received yet.  Sharing with: " .. BT.ShareScopeName()
    end
    return n .. " report" .. (n == 1 and "" or "s") .. " received.  Sharing with: "
      .. BT.ShareScopeName()
  elseif mode == "boosters" then
    local step = BT.FocusStep()
    if not step then
      return "nothing recorded yet - do a run, or right-click the bar to set a route"
    end
    local _, onRoute = BT.Stage()
    local n = #BT.BoosterTable(step.id)
    -- the levels the place is worth doing, and the level it lets you in at,
    -- said out loud rather than assumed
    local span = BT.SpanChunk(step)
    local min = BT.MinChunk(step)
    local where = step.label
      .. (span and ("  " .. C.dim .. "levels " .. C.off .. span) or "")
      .. (min and ("  " .. C.dim .. "enter at " .. C.off .. min) or "")
      .. (onRoute and "" or (C.dim .. "  (not on your route)" .. C.off))
    if n == 0 then return "no boosted runs recorded for " .. where .. " yet" end
    local mine = 0
    for _, b in ipairs(BT.Roster(step.id)) do
      if b.mine then mine = mine + 1 end
    end
    if n == 0 and mine == 0 then
      return "no boosted runs recorded for " .. where
        .. " yet - add somebody by hand below"
    end
    return n .. " booster" .. (n == 1 and "" or "s") .. " for " .. where
      .. (mine > 0 and ("  " .. C.dim .. "+ " .. mine .. " you added" .. C.off) or "")
      .. ".  Type the price he quotes for a pack of "
      .. BT.StepPack(step) .. "; if he sells them "
      .. "in a different number, put that in the pack column."
  elseif mode == "ads" then
    local n = #AdRows()
    if n == 0 then
      if not ChainDB.readAds then
        return C.dim .. "reading adverts is off - turn it on in the settings" .. C.off
      end
      return "nothing heard yet.  Boosters advertise in Trade (only inside a "
        .. "city) and LookingForGroup - join those channels and stand in a city."
    end
    -- which channels are actually producing, best first
    local list, best = {}, nil
    for _, src in ipairs(BT.AdSourceList()) do
      if (src.n or 0) > 0 then table.insert(list, src) end
    end
    table.sort(list, function(a, b) return (a.n or 0) > (b.n or 0) end)
    best = list[1]
    return n .. " advertiser" .. (n == 1 and "" or "s") .. " heard"
      .. (best and (C.dim .. "   most from " .. best.label .. C.off) or "")
      .. C.dim .. "   settings - channels... to choose where from" .. C.off
  elseif mode == "groups" then
    local all = BT.GroupLog()
    if #all == 0 then
      if not ChainDB.readGroups then
        return C.dim .. "reading group posts is off - turn it on in the settings" .. C.off
      end
      return "nothing heard yet.  People post these in LookingForGroup and in "
        .. "the city channels - join those and stand in a city."
    end
    -- how many of them are about the place you are actually in
    local step = BT.FocusStep()
    local here, fresh = 0, 0
    for _, g in ipairs(all) do
      if step and g.id == step.id then here = here + 1 end
      if (time() - (g.at or 0)) < 900 then fresh = fresh + 1 end
    end
    return #all .. " post" .. (#all == 1 and "" or "s") .. " kept"
      .. C.dim .. "   " .. fresh .. " in the last 15 minutes" .. C.off
      .. ((here > 0 and step)
          and ("   " .. C.good .. here .. " for " .. step.label .. C.off) or "")
  elseif mode == "enemies" then
    local all = BT.SeenList()
    if #all == 0 then
      if not ChainDB.watchEnemies then
        return C.dim .. "the watch is off - turn it on in the settings" .. C.off
      end
      return "nobody seen yet.  Nameplates, your mouse, your target and the "
        .. "combat log all feed this; go somewhere contested."
    end
    local near, marked = #BT.Nearby(60), 0
    for _, e in ipairs(all) do
      if BT.IsKOS(e.name, e.guild) then marked = marked + 1 end
    end
    return #all .. " seen"
      .. (near > 0 and ("   " .. C.warn .. near .. " in the last minute" .. C.off) or "")
      .. (marked > 0 and ("   " .. C.bad .. marked .. " marked" .. C.off) or "")
      .. C.dim .. "   " .. #BT.KOSGuildList() .. " guild"
      .. (#BT.KOSGuildList() == 1 and "" or "s") .. " marked" .. C.off
  elseif mode == "runs" then
    local agg = BT.Aggregate(BT.Runs({}), #BT.Runs({}))
    if not agg then return nil end
    return #BT.Runs({}) .. " runs, " .. BT.N(agg.totalXP) .. " xp, "
      .. BT.T(agg.totalT) .. " inside instances"
  end
  return nil
end

local function Render()
  if not win or not win:IsShown() then return end
  local layout = LAYOUTS[mode]
  local data = Data()

  if sortKey then
    table.sort(data, function(a, b)
      local x, y = a[sortKey], b[sortKey]
      if x == nil and y == nil then return false end
      if x == nil then return false end
      if y == nil then return true end
      if type(x) == "string" or type(y) == "string" then
        x, y = tostring(x), tostring(y)
      end
      if sortDesc then return x > y end
      return x < y
    end)
  end

  -- One box, every tab: it searches whatever the rows actually say, so
  -- "stockade" narrows the history and "algorismus" narrows it to one booster
  -- without either tab needing to know about the box.
  if filter ~= "" then
    local want = filter:lower()
    local kept = {}
    for _, d in ipairs(data) do
      local hay = ""
      for _, c in ipairs(d.cells) do hay = hay .. " " .. Plain(c) end
      if hay:lower():find(want, 1, true) then table.insert(kept, d) end
    end
    data = kept
  end

  -- the add-someone row belongs to the Boosters tab and nowhere else
  local adding = (mode == "boosters")
  for _, w in ipairs({ win.addLabel, win.addName, win.addNote, win.addButton,
                       win.addNote2 }) do
    if w then w:SetShown(adding) end
  end
  if adding and win.addNote2 then
    local step = BT.FocusStep()
    win.addNote2:SetText(step and (C.dim .. "listed under " .. step.label .. C.off)
      or (C.dim .. "listed everywhere" .. C.off))
  end

  -- and the rank box belongs to the Rank tab, on the same line
  local planning = (mode == "pvp")
  for _, w in ipairs({ win.targetLabel, win.targetBox, win.targetUp,
                       win.targetDown, win.targetName }) do
    if w then w:SetShown(planning) end
  end
  if planning and win.targetBox then
    local t = ChainCharDB.pvpTarget or 1
    if not win.targetBox:HasFocus() then win.targetBox:SetText(tostring(t)) end
    win.targetName:SetText(C.gold .. BT.RankName(t) .. C.off)
  end

  local pages = math.max(1, math.ceil(#data / ROWS))
  if page > pages then page = pages end
  win.subtitle:SetText(layout.title)
  win.summary:SetText(Summary() or "")
  win.pageText:SetText(#data == 0 and ((filter ~= "")
      and ("nothing matches \"" .. filter .. "\"") or "nothing recorded yet")
    or string.format("%d-%d of %d", (page - 1) * ROWS + 1,
                     math.min(page * ROWS, #data), #data))

  -- headers
  for i = 1, #win.headers do
    local h = win.headers[i]
    local col = layout.cols[i]
    if col then
      local label = col[1]
      -- a header that names the pack size has to follow the setting
      if label:find("%%d") then
        local pack = BT.StepPack(BT.FocusStep())
        label = label:format(pack)
        if pack ~= 1 then label = label .. "s" end
      end
      if sortKey and col[3] == sortKey then label = label .. (sortDesc and " v" or " ^") end
      h.fs:SetText(label)
      h:SetWidth(col[2])
      h:Show()
      h.key = col[3]
    else
      h:Hide()
    end
  end
  -- lay the headers out left to right
  local x = 0
  for i, col in ipairs(layout.cols) do
    local h = win.headers[i]
    if not h then break end
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", win.headerRow, "TOPLEFT", x, 0)
    x = x + col[2]
  end

  for i = 1, ROWS do
    local row = rows[i]
    local d = data[(page - 1) * ROWS + i]
    if d then
      row.tip = d.tip
      local rx = 0
      for ci, col in ipairs(layout.cols) do
        local fs = row.cells[ci]
        if not fs then break end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", row, "LEFT", rx, 0)
        fs:SetWidth(col[2] - 4)
        fs:SetText(d.cells[ci] or "")
        fs:Show()
        rx = rx + col[2]
      end
      for ci = #layout.cols + 1, #row.cells do row.cells[ci]:Hide() end
      -- the x removes a run from the averages on History, and on Boosters it
      -- removes somebody you put in the list yourself. It never appears on a
      -- booster you have actually run with: that is measured history.
      row.del.rec, row.del.name = nil, nil
      if mode == "runs" and d.rec then
        row.del.rec = d.rec
        row.del:Show()
      elseif mode == "boosters" and d.mine then
        row.del.name = d.by
        row.del:Show()
      else
        row.del:Hide()
      end

      if (mode == "ads" or mode == "groups") and d.whisper then
        local wx = 0
        for ci, col in ipairs(layout.cols) do
          if ci < #layout.cols then wx = wx + col[2] end
        end
        row.whisper.name = d.whisper
        row.whisper:ClearAllPoints()
        row.whisper:SetPoint("LEFT", row, "LEFT", wx, 0)
        row.whisper:Show()
      else
        row.whisper:Hide()
      end

      if mode == "enemies" and d.name then
        local kx, nx = 0, 0
        for ci, col in ipairs(layout.cols) do
          if ci < #layout.cols - 1 then kx = kx + col[2] end
          if ci < #layout.cols then nx = nx + col[2] end
        end
        row.kos.name, row.kos.guild = d.name, d.guild
        row.kos.fs:SetText(d.kosWhy and "clear" or "KOS")
        row.kos.bg:SetColorTexture(d.kosWhy and 0.45 or 0.15,
                                   d.kosWhy and 0.12 or 0.15, 0.15, 0.9)
        row.kos:ClearAllPoints()
        row.kos:SetPoint("LEFT", row, "LEFT", kx, 0)
        row.kos:Show()

        row.note.by = nil
        row.note.kos = d.name
        if not row.note:HasFocus() then row.note:SetText(d.note or "") end
        row.note:ClearAllPoints()
        row.note:SetPoint("LEFT", row, "LEFT", nx, 0)
        row.note:Show()
      else
        row.kos:Hide()
      end

      if mode == "boosters" and d.by then
        -- column 7 is the price box
        local px = 0
        for ci, col in ipairs(layout.cols) do
          if ci < 7 then px = px + col[2] end
        end
        row.price.by = d.by
        if not row.price:HasFocus() then
          row.price:SetText(((d.info.price or 0) > 0) and tostring(d.info.price) or "")
        end
        row.price:ClearAllPoints()
        row.price:SetPoint("LEFT", row, "LEFT", px, 0)
        row.price:Show()

        -- column 8 is his pack, shown filled in with whatever applies so the
        -- price above is never ambiguous about what it buys
        row.pack.by = d.by
        if not row.pack:HasFocus() then
          row.pack:SetText(tostring(BT.PackFor(BT.FocusStep(), d.by)))
        end
        row.pack:ClearAllPoints()
        row.pack:SetPoint("LEFT", row, "LEFT", px + layout.cols[7][2], 0)
        row.pack:Show()

        -- and the last column is yours to write in
        local nx = 0
        for ci, col in ipairs(layout.cols) do
          if ci < #layout.cols then nx = nx + col[2] end
        end
        row.note.by = d.by
        if not row.note:HasFocus() then row.note:SetText(d.info.note or "") end
        row.note:ClearAllPoints()
        row.note:SetPoint("LEFT", row, "LEFT", nx, 0)
        row.note:Show()
      else
        row.price:Hide()
        row.pack:Hide()
        row.note:Hide()
      end
      row:Show()
    else
      row.tip = nil
      row.price:Hide() row.pack:Hide() row.kos:Hide()
      row.note:Hide() row.del:Hide() row.whisper:Hide()
      row:Hide()
    end
  end
end

local function SetMode(m)
  mode = m
  page = 1
  sortKey, sortDesc = nil, false
  for key, b in pairs(tabs) do
    b.active = (key == m)
    b.bg:SetColorTexture(b.active and 0.25 or 0.15, b.active and 0.25 or 0.15,
                         b.active and 0.35 or 0.15, 0.9)
  end
  Render()
end

local function Build()
  win = CreateFrame("Frame", "ChainWindow", UIParent)
  -- the extra 6 is the line the search box moved down onto
  win:SetSize(880, 26 + 28 + 20 + ROWS * 18 + 74 + 6)
  win:SetPoint("CENTER")
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetClampedToScreen(true)
  win:SetFrameStrata("DIALOG")
  win:Hide()

  -- the edge is just a slightly larger rectangle behind the background
  win.edge = Tex(win, "BACKGROUND", 0.3, 0.3, 0.35, 1)
  win.edge:SetPoint("TOPLEFT", -1, 1)
  win.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  win.bg = Tex(win, "BACKGROUND", 0.05, 0.05, 0.06, 0.98)
  win.bg:SetAllPoints()
  win.bg:SetDrawLayer("BACKGROUND", 2)

  win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  win.title:SetPoint("TOPLEFT", 10, -8)
  win.title:SetText(BT.NAME)

  local close = Button(win, "X", 22, 18, function() win:Hide() end)
  close:SetPoint("TOPRIGHT", -6, -6)

  tabs = {}
  local tx = 10
  for _, def in ipairs({ { "runs", "History" }, { "boosters", "Boosters" },
                         { "ads", "Adverts" }, { "groups", "Groups" },
                         { "reported", "Reported" },
                         { "gold", "Trade" }, { "enemies", "Enemies" },
                         { "pvp", "Rank" },
                         { "locks", "Instances" },
                         { "route", "Route" } }) do
    -- ten of them now, so they are measured rather than spaced by hand:
    -- one more tab used to push the last one off the right-hand edge
    local b = Button(win, def[2], 74, 20, function() SetMode(def[1]) end)
    b:SetPoint("TOPLEFT", tx, -28)
    tabs[def[1]] = b
    tx = tx + 78
  end

  win.subtitle = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.subtitle:SetPoint("TOPLEFT", 10, -54)
  -- stops short of the search box, which now sits on this line: nine tabs
  -- fill the row above it, and the last of them was running underneath it
  win.subtitle:SetWidth(640)
  win.subtitle:SetJustifyH("LEFT")
  -- one line, always: wrapped to two it ran straight into the column headings
  if win.subtitle.SetWordWrap then win.subtitle:SetWordWrap(false) end
  if win.subtitle.SetMaxLines then win.subtitle:SetMaxLines(1) end

  win.searchLabel = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.searchLabel:SetPoint("TOPRIGHT", -190, -54)
  win.searchLabel:SetText("show only")

  win.search = CreateFrame("EditBox", nil, win)
  win.search:SetSize(150, 20)
  win.search:SetPoint("TOPRIGHT", -34, -50)
  win.search:SetAutoFocus(false)
  win.search:SetFontObject("GameFontHighlightSmall")
  win.search.bg = Tex(win.search, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
  win.search.bg:SetAllPoints()
  win.search:SetScript("OnTextChanged", function(self)
    filter = self:GetText() or ""
    page = 1
    Render()
  end)
  win.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  win.search:SetScript("OnEscapePressed", function(self)
    self:SetText("") self:ClearFocus()
  end)

  local clear = Button(win, "x", 22, 18, function()
    win.search:SetText("")
  end)
  clear:SetPoint("TOPRIGHT", -8, -51)

  win.headerRow = CreateFrame("Frame", nil, win)
  win.headerRow:SetPoint("TOPLEFT", 12, -76)
  win.headerRow:SetSize(850, 16)
  win.headers = {}
  for i = 1, MAX_COLS do
    local h = CreateFrame("Button", nil, win.headerRow)
    h:SetHeight(16)
    h.fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h.fs:SetPoint("LEFT")
    h:SetScript("OnClick", function(self)
      if not self.key then return end
      if sortKey == self.key then sortDesc = not sortDesc
      else sortKey, sortDesc = self.key, true end
      Render()
    end)
    win.headers[i] = h
  end

  rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, win)
    row:SetSize(850, 17)
    row:SetPoint("TOPLEFT", 12, -94 - (i - 1) * 18)
    if i % 2 == 0 then
      row.stripe = Tex(row, "BACKGROUND", 1, 1, 1, 0.03)
      row.stripe:SetAllPoints()
    end
    -- A row that can be hovered: the advert text is longer than any column,
    -- and a line you can only half read is a line you have to go and find in
    -- the chat window instead.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      if not self.tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
      for i, line in ipairs(self.tip) do
        if i == 1 then GameTooltip:AddLine(line, 1, 0.82, 0)
        else GameTooltip:AddLine(line, 1, 1, 1, true) end
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.cells = {}
    for c = 1, MAX_COLS do
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetJustifyH("LEFT")
      -- one line per cell. "1h 42m ago" wrapped inside a narrow column and
      -- took the row's alignment with it; a cell that does not fit is clipped
      -- rather than allowed to grow downwards.
      if fs.SetWordWrap then fs:SetWordWrap(false) end
      if fs.SetMaxLines then fs:SetMaxLines(1) end
      fs:SetPoint("LEFT", row, "LEFT", 0, 0)
      row.cells[c] = fs
    end
    -- the boosters tab needs real controls, not just text
    row.price = CreateFrame("EditBox", nil, row)
    row.price:SetSize(52, 16)
    row.price:SetAutoFocus(false)
    row.price:SetFontObject("GameFontHighlightSmall")
    row.price:SetJustifyH("CENTER")
    row.price:SetMaxLetters(6)
    row.price.bg = Tex(row.price, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
    row.price.bg:SetAllPoints()
    row.price:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.price:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    row.price:SetScript("OnEditFocusLost", function(self)
      if self.by then
        -- no pack argument: whatever this instance is normally sold in, and
        -- the box next door is where you say otherwise
        BT.SetPrice(self.by, tonumber(self:GetText()) or 0)
        if BT.ShareOne then BT.ShareOne(self.by) end
      end
      Render()
      if BT.Refresh then BT.Refresh() end
    end)
    row.price:Hide()

    -- The man who does ten where the instance normally goes five. Blank means
    -- he sells it the way everyone else does, so an old price is never
    -- silently repriced by a setting somewhere else.
    row.pack = CreateFrame("EditBox", nil, row)
    row.pack:SetSize(32, 16)
    row.pack:SetAutoFocus(false)
    row.pack:SetFontObject("GameFontHighlightSmall")
    row.pack:SetJustifyH("CENTER")
    row.pack:SetMaxLetters(2)
    row.pack.bg = Tex(row.pack, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
    row.pack.bg:SetAllPoints()
    row.pack:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.pack:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    row.pack:SetScript("OnEditFocusLost", function(self)
      if self.by then
        BT.SetPack(self.by, tonumber(self:GetText()))
        if BT.ShareOne then BT.ShareOne(self.by) end
      end
      Render()
      if BT.Refresh then BT.Refresh() end
    end)
    row.pack:Hide()

    -- your own words about this man. Never sent anywhere: what travels
    -- between copies of the addon is measurements, not opinions.
    row.note = CreateFrame("EditBox", nil, row)
    row.note:SetSize(116, 16)
    row.note:SetAutoFocus(false)
    row.note:SetFontObject("GameFontHighlightSmall")
    row.note:SetJustifyH("LEFT")
    row.note:SetMaxLetters(60)
    row.note.bg = Tex(row.note, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
    row.note.bg:SetAllPoints()
    row.note:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    row.note:SetScript("OnEditFocusLost", function(self)
      if self.by then BT.SetBoosterNote(self.by, self:GetText()) end
      -- the same box, on the Enemies tab: a note against a name you marked
      if self.kos then BT.AddKOS(self.kos, self:GetText()) end
      Render()
    end)
    row.note:Hide()

    -- one click to ask him. A booster's advert is an invitation to whisper,
    -- and copying a name out of a list by hand is the sort of thing an addon
    -- exists to spare you.
    row.whisper = Button(row, "whisper", 62, 15, function(self)
      local name = self.name
      if not name then return end
      if ChatFrame_SendTell then
        ChatFrame_SendTell(name, SELECTED_DOCK_FRAME or DEFAULT_CHAT_FRAME)
      elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat("/w " .. name .. " ")
      end
    end)
    row.whisper:Hide()

    -- Marking somebody is one click, and the button says what it will do
    -- rather than what the state is: "KOS" to mark, "clear" to unmark.
    row.kos = Button(row, "KOS", 50, 15, function(self)
      if not self.name then return end
      local why = BT.IsKOS(self.name, self.guild)
      if why == "named" then BT.RemoveKOS(self.name)
      elseif why == "guild" then BT.RemoveKOSGuild(self.guild)
      else BT.AddKOS(self.name) end
      Render()
    end)
    row.kos:Hide()

    row.del = Button(row, "x", 16, 14, function(self)
      if self.name then
        BT.ForgetBooster(self.name)
        Render()
        return
      end
      if not self.rec then return end
      for idx, r in ipairs(ChainDB.runs) do
        if r == self.rec then
          table.remove(ChainDB.runs, idx)
          BT.Touch()
          break
        end
      end
      Render()
      if BT.Refresh then BT.Refresh() end
    end)
    row.del:SetPoint("LEFT", row, "LEFT", 832, 0)
    rows[i] = row
  end

  -- Adding somebody by hand, on the Boosters tab: a name you were given in a
  -- whisper is worth keeping before you have ever run with him, and the note
  -- is where "only sells mornings" or "does not pull the last room" goes.
  local addY = -94 - ROWS * 18 - 6
  win.addLabel = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.addLabel:SetPoint("TOPLEFT", 12, addY)
  win.addLabel:SetText("add someone")

  local function AddBox(width, x, hint, maxLetters)
    local e = CreateFrame("EditBox", nil, win)
    e:SetSize(width, 18)
    e:SetPoint("TOPLEFT", x, addY + 3)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetMaxLetters(maxLetters or 60)
    e.bg = Tex(e, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
    e.bg:SetAllPoints()
    e.hint = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    e.hint:SetPoint("LEFT", e, "LEFT", 4, 0)
    e.hint:SetText(hint)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnTextChanged", function(self)
      self.hint:SetShown((self:GetText() or "") == "")
    end)
    return e
  end

  win.addName = AddBox(120, 92, "name", 24)
  win.addNote = AddBox(300, 218, "note - your own words, never shared")

  local function DoAdd()
    local step = BT.FocusStep()
    local name, why = BT.AddBooster(win.addName:GetText(),
                                    win.addNote:GetText(), step and step.id)
    if not name then
      win.addLabel:SetText(C.bad .. (why or "no name") .. C.off)
      return
    end
    win.addName:SetText("")
    win.addNote:SetText("")
    win.addName:ClearFocus()
    win.addNote:ClearFocus()
    win.addLabel:SetText("add someone")
    Render()
  end
  win.addName:SetScript("OnEnterPressed", DoAdd)
  win.addNote:SetScript("OnEnterPressed", DoAdd)
  win.addButton = Button(win, "Add", 60, 18, DoAdd)
  win.addButton:SetPoint("TOPLEFT", 526, addY + 3)
  win.addNote2 = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.addNote2:SetPoint("TOPLEFT", 596, addY)

  -- The rank you are aiming at, on the same line and in the same place as the
  -- add-someone row, because only one of the two is ever on screen.
  win.targetLabel = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.targetLabel:SetPoint("TOPLEFT", 12, addY)
  win.targetLabel:SetText("rank you want")

  win.targetBox = CreateFrame("EditBox", nil, win)
  win.targetBox:SetSize(40, 18)
  win.targetBox:SetPoint("TOPLEFT", 100, addY + 3)
  win.targetBox:SetAutoFocus(false)
  win.targetBox:SetFontObject("GameFontHighlightSmall")
  win.targetBox:SetJustifyH("CENTER")
  win.targetBox:SetMaxLetters(2)
  win.targetBox:SetNumeric(true)
  win.targetBox.bg = Tex(win.targetBox, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
  win.targetBox.bg:SetAllPoints()

  local function SetTarget()
    local v = tonumber(win.targetBox:GetText())
    if v then
      ChainCharDB.pvpTarget = math.max(1, math.min(BT.PVP.MAX_RANK, math.floor(v)))
    end
    win.targetBox:ClearFocus()
    Render()
  end
  win.targetBox:SetScript("OnEnterPressed", SetTarget)
  win.targetBox:SetScript("OnEditFocusLost", SetTarget)
  win.targetBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  local function Step(by)
    return function()
      local now = ChainCharDB.pvpTarget or ((BT.MyRank() or 0) + 1)
      ChainCharDB.pvpTarget = math.max(1, math.min(BT.PVP.MAX_RANK, now + by))
      Render()
    end
  end
  win.targetDown = Button(win, "-", 20, 18, Step(-1))
  win.targetDown:SetPoint("TOPLEFT", 76, addY + 3)
  win.targetUp = Button(win, "+", 20, 18, Step(1))
  win.targetUp:SetPoint("TOPLEFT", 144, addY + 3)

  win.targetName = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  win.targetName:SetPoint("TOPLEFT", 174, addY)
  win.targetName:SetJustifyH("LEFT")

  win.summary = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  win.summary:SetPoint("BOTTOMLEFT", 12, 26)
  win.summary:SetJustifyH("LEFT")

  win.pageText = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  win.pageText:SetPoint("BOTTOMLEFT", 12, 10)

  local prev = Button(win, "< prev", 60, 18, function()
    if page > 1 then page = page - 1 Render() end
  end)
  prev:SetPoint("BOTTOMRIGHT", -76, 8)
  local nxt = Button(win, "next >", 60, 18, function()
    page = page + 1 Render()
  end)
  nxt:SetPoint("BOTTOMRIGHT", -12, 8)

  win.rows = rows
  page, mode = 1, "runs"
  SetMode("runs")
end

-- Open the window straight on one tab, for the slash commands and so a test
-- can drive it without reaching into the buttons
function BT.ShowTab(m)
  if not win then Build() end
  win:Show()
  SetMode(m or "runs")
end

function BT.ToggleWindow()
  if not win then Build() end
  if win:IsShown() then win:Hide() else win:Show() Render() end
end

function BT.RenderWindow() Render() end
