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
  b.fs = b:CreateFontString(nil, "OVERLAY", "ChainFontHighlightSmall")
  b.fs:SetPoint("CENTER")
  b.fs:SetText(label)
  b:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(0.3, 0.3, 0.3, 0.9)
    -- Every button says what it does before you press it. A row of one-letter
    -- buttons is a row of guesses otherwise, and one of them deletes things.
    if not self.hint then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine(self.hintTitle or self.fs:GetText() or "", 1, 0.82, 0)
    GameTooltip:AddLine(self.hint, 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(self.active and 0.25 or 0.15, self.active and 0.25 or 0.15,
                            self.active and 0.35 or 0.15, 0.9)
    GameTooltip:Hide()
  end)
  b:SetScript("OnClick", onClick)
  return b
end

-- A tooltip's lines, without the holes.
--
-- These tables are written as { a, b, c or nil, d } - "put this line in only
-- when there is one" - and ipairs stops dead at the first nil. Every line
-- after an absent one was being silently dropped: a trade with no zone lost
-- its arithmetic, a run with no coin lost the group line. Varargs keep the
-- nils long enough to skip them properly.
local function Lines(...)
  local out, n = {}, select("#", ...)
  for i = 1, n do
    local v = select(i, ...)
    if v ~= nil and v ~= "" then out[#out + 1] = v end
  end
  return out
end

-- What a button says before you press it.
local function Hint(b, text, title)
  if not b then return b end
  b.hint, b.hintTitle = text, title
  return b
end

-- Asking first.
--
-- The x sits at the end of every row and it throws things away: a run out of
-- the averages, a trade out of the reckoning, a booster off the list. One
-- stray click on a dense list and a piece of your history is gone, and there
-- is nothing to undo it with. So it asks, in the game's own dialog, and the
-- question names the thing rather than saying "are you sure" at you.
--
-- preferredIndex 3 is not decoration: without it the popup can be handed a
-- frame another addon is already using, and Blizzard's own code has carried
-- that bug for years.
if type(StaticPopupDialogs) == "table" then
  StaticPopupDialogs["CHAIN_CONFIRM"] = {
    text = "%s",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function(_, data) if data and data.fn then data.fn() end end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3
  }
end

local function Confirm(question, fn)
  if type(StaticPopup_Show) ~= "function" then fn() return end
  StaticPopup_Show("CHAIN_CONFIRM", question, nil, { fn = fn })
end



--------------------------------------------------------------------------
-- Tabs inside a tab.
--
-- Eleven across the top was a wall of words to read before you could start.
-- Three of them - who sells this step, who is selling right now, and what
-- other people's addons have said - are the same subject from three angles,
-- so they sit under one heading and you pick the angle once you are there.
local SUBTABS = {
  boosting = { { "boosters", "Boosters" }, { "ads", "Sellers" },
               { "wtb", "Buyers" }, { "sell", "My boost" },
               { "reported", "Shared" } }
}
local GROUP = { boosters = "boosting", ads = "boosting",
                wtb = "boosting", sell = "boosting", reported = "boosting" }

-- What each tab is for, on the tab itself. Eleven tabs is a lot to learn by
-- clicking them one at a time.
local TAB_HINT = {
  runs = "every run and every payment, newest first. Where you settle what "
    .. "you have had since you last paid.",
  boosters = "everyone selling the step you are on, with what each one has "
    .. "actually delivered. Your notes on them live here and are never "
    .. "shared.",
  ads = "who is selling right now, read out of chat. Older than half an hour "
    .. "and they are off the list.",
  groups = "people looking for a group: LFM and LFG, out of every channel. "
    .. "Somebody wanting to buy a boost is on Boosting, with the rest of the "
    .. "buying and selling.",
  wtb = "everyone asking to buy a boost. The other side of the Sellers tab, "
    .. "and where you find somebody to split a chain with.",
  sell = "your side of the counter: what you charge, who has paid you, and "
    .. "the count that goes into party after every run.",
  boosting = "buying and selling: who sells the step you are on, who is "
    .. "advertising right now, and what other people's addons have said.",
  reported = "what other people's addons have told you, kept apart from your "
    .. "own numbers so you always know which are which.",
  gold = "every trade, both ways, and what each one bought you in runs.",
  loot = "one row per corpse, plus what the raw coin came to per run.",
  enemies = "everyone seen out there, and everyone you have marked or "
    .. "written about.",
  pvp = "the rank you want, week by week, and which honour number to stop "
    .. "on.",
  locks = "every instance you entered and every reset - the five an hour, "
    .. "and where they went.",
  route = "the plan: which instances, which levels, and what a level costs "
    .. "in each."
}

-- Column layouts
--------------------------------------------------------------------------
-- key is what the sort uses; nil means the column is not sortable
local LAYOUTS = {
  runs = {
    title = "Runs and payments, newest first. What sits above a payment is "
      .. "what you have had since it.",
    cols = {
      { "when",     78, "at", "how long ago it finished. The run you are in "
        .. "says 'now' and counts up." },
      { "instance", 90, "zone", "where it was. A payment row says 'paid' "
        .. "here instead, with the runs it bought." },
      { "xp",       55, "xp", "experience you gained in there. Coloured "
        .. "against what this instance usually gives you." },
      { "% lvl",    46, "pct", "the same run as a share of the level you "
        .. "were on. Experience on its own means nothing across levels - "
        .. "20,000 is most of a level at 22 and nothing at 58 - and this is "
        .. "the number you can hold five of in your head." },
      { "time",     45, "t", "door to door. Less is better, so the colours "
        .. "run the other way." },
      { "mobs",     40, "k", "how many things died. A short run with the "
        .. "usual mob count was a fast booster; a short run with half of "
        .. "them was a skipped wing." },
      { "xp/h",     55, "rate", "the run's own rate: its experience over its "
        .. "own time. Nothing to do with the bar's live figure." },
      { "gold",     62, "coin", "raw gold picked up off the mobs. On a "
        .. "payment row it is what you paid instead." },
      { "booster",  70, "by", "who ran it. 'self' means you cleared it "
        .. "yourself." },
      { "lvl",      30, "lvl", "the level you were when you walked in" },
      { "grp",      40, "grpAvg", "the group's average level. A high one "
        .. "costs you experience - that is the maths behind 'grp' on the "
        .. "bar." }
    }
  },
  boosters = {
    title = "Everyone selling this step. Type his price; the verdict "
      .. "follows.",
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
      { "runs left",56, "left", "what he still owes you: what you paid, "
        .. "divided by his price, less the runs recorded since. Every one of "
        .. "those can be wrong - a trade the client never announced, a run "
        .. "that never got logged, a wipe he gave you back. Type over it and "
        .. "the reckoning starts again from your number." },
      { "reported", 80, nil },
      { "your note", 96, nil }
    }
  },
  gold = {
    title = "Every trade, both ways. Hover a heading to see what it means.",
    cols = {
      { "when",    70, "at", "how long ago the trade window closed" },
      { "traded",  84, "with", "who was on the other side of it" },
      { "paid",    54, "gave", "gold you handed over" },
      { "got back",54, "got", "gold he handed you - change, or a refund" },
      { "net",     54, "net", "what actually left your bags: paid less got "
        .. "back" },
      { "buys",    46, nil, "what that net was worth in runs, at the price "
        .. "he was charging then" },
      { "to come", 50, nil, "runs he still owed you the moment this trade "
        .. "was logged - what you bought here plus anything left over from "
        .. "the pack before, which is why it can be more than 'buys'. Hover "
        .. "a row for the working. Frozen at that second; the live figure is "
        .. "on the Boosters tab." },
      { "your items", 104, nil, "items you put in the trade window - not "
        .. "gold. Usually empty." },
      { "his items", 104, nil, "items he put in the trade window - a bag of "
        .. "greens off the run, say. Not gold." },
      { "where",   78, "zone", "where you were standing when you paid" },
      { "step",    56, "id", "which step of your route the money was for" },
      { "lvl",     30, "lvl", "the level you were at the time" },
      { "booster", 52, nil, "whether this person is one of your boosters, or "
        .. "somebody you just happened to trade with" }
    }
  },
  enemies = {
    title = "Everyone seen out there, newest first. Mark one or a whole "
      .. "guild - marked ones raise the alarm.",
    cols = {
      { "when",     70, "at" },
      { "who",      96, "name" },
      { "lvl",      38, "level" },
      { "class",    70, "class" },
      { "guild",   118, "guild" },
      { "where",    92, "zone" },
      { "seen",     40, "n" },
      { "W / L",    52, "score" },
      { "how",      68, "how" },
      { "kos",      52, nil },
      { "your note",124, nil }
    }
  },
  loot = {
    title = "One row per corpse. 'from' is only known for your own loot; raw "
      .. "coin is one figure per run, on History.",
    cols = {
      { "when",      70, "at" },
      { "item",     236, "name" },
      { "n",         28, "n" },
      { "quality",   62, "quality" },
      { "to",        80, "who" },
      { "from",     108, "from" },
      { "worth",     74, "value" },
      { "where",     78, "zone" },
      { "step",      44, "step" },
      { "booster",   60, "by" }
    }
  },
  koslist = {
    title = "Everyone you have marked or written about, whether or not they "
      .. "are anywhere near you. Your notes are never shared.",
    cols = {
      { "who",       130, "who" },
      { "kind",       64, "kind" },
      { "lvl",        40, "level" },
      { "class",      74, "class" },
      { "last seen",  94, "at" },
      { "seen",       46, "n" },
      { "W / L",      54, "score" },
      { "where",     108, "zone" },
      { "",           56, nil },        -- the unmark button
      { "your note", 200, nil }
    }
  },
  groups = {
    title = "Everyone looking for a group: LFM and LFG, from every channel. "
      .. "Somebody wanting to buy a boost is on Boosting.",
    cols = {
      { "when",     70, "at" },
      { "who",      88, "by" },
      { "what",     64, "kind" },
      { "instance", 86, "zone" },
      { "needs",    78, "needs" },
      -- What he typed is "lvl 25+ pst", which is his problem, not yours. The
      -- number you are actually looking for is the one the game enforces: the
      -- level it lets you walk in at. Green once you are there.
      { "enter at", 58, "min", "the level the game lets you into that "
        .. "instance at, green once you are there. What the poster himself "
        .. "asked for is on the row tooltip." },
      { "heard in", 88, "from" },
      { "what he said", 240, nil },
      { "",         64, nil }        -- the whisper button
    }
  },
  -- The other side of Sellers, and the reason it is here rather than with
  -- the LFM posts: a man asking to buy a boost is in the same trade you are,
  -- not looking for a fifth for Scholo. He is who you split a chain with when
  -- the booster sells in tens and you want five.
  wtb = {
    title = "Everyone asking to buy a boost. The other side of Sellers - "
      .. "and who to share a chain with.",
    cols = {
      { "when",     70, "at" },
      { "who",      88, "by" },
      { "instance", 96, "zone", "the instance he named, when he named one" },
      { "enter at", 58, "min", "the level that instance lets you in at, "
        .. "green once you are there" },
      { "heard in", 96, "from" },
      { "what he said", 330, nil },
      { "",         64, nil }        -- the whisper button
    }
  },
  -- The seller's chair. Everything else here is written for the man paying;
  -- this is the same argument from the other side, and it ends the same way -
  -- with a count both of you watched go up.
  sell = {
    title = "The boost you are running. Somebody in your group trades you "
      .. "gold and he lands here, with what it bought at your price.",
    cols = {
      { "who",      96, "name", "who paid you. Added on his own when he "
        .. "trades you gold while he is in your group." },
      { "paid",     70, "paid", "gold he has handed over, all of it, across "
        .. "however many trades. It does not move when you change your "
        .. "price." },
      { "bought",   56, "runs", "what that gold came to in runs at the price "
        .. "you were charging when he paid." },
      { "done",     46, "done", "runs he has had. One goes on for everybody "
        .. "in the group each time a run finishes." },
      { "left",     56, "left", "what he still has coming. Type over it when "
        .. "the count is wrong - a wipe you gave him back, a run he sat "
        .. "out - and what he bought moves to match." },
      { "per run",  62, "per", "what one run cost him, at the price at the "
        .. "time" },
      { "paid at",  74, "at", "when the last of his gold came in" },
      { "here",     44, nil, "whether he is in your group right now. Runs "
        .. "only count for the people who are actually in them." },
      { "",         30, nil }        -- the x
    }
  },
  reported = {
    title = "What other people's addons told you, kept apart from your "
      .. "own numbers.",
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
    title = "Who is advertising right now. Off the list after half an "
      .. "hour.",
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
    title = "Every instance you entered and every reset. Green still counts "
      .. "against the five per hour.",
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
    title = "The rank you want, week by week. Honor below a milestone or past "
      .. "one is wasted - stop on the number.",
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
    title = "The plan from here, instances and stretches you do yourself. "
      .. "'g/lvl now' and 'at the end' are what a level costs there.",
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
-- exposed so the suite can measure every title against the space it has
BT.LAYOUTS = LAYOUTS

local function Rate(value, avg, higherIsBetter)
  if not value or not avg or avg <= 0 then return C.dim end
  local d = value / avg - 1
  if not higherIsBetter then d = -d end
  if d >= 0.15 then return C.good end
  if d <= -0.15 then return C.bad end
  return C.warn
end

-- Which rows you have marked, keyed by the record itself where there is one.
-- Not saved: it is a thing you do for ten seconds to settle an argument or to
-- keep your place in a long list, and a mark surviving a logout would only
-- ever be a surprise.
local picked = {}

-- The line you are on. One at a time: it answers "where was I" while you read
-- down a long list, and a list you can leave fifteen blue lines in answers
-- nothing. Marking several runs to say them out loud is a different job and
-- it has its own button on History.
local selected = nil

-- Some lists are built out of tables we keep (a run, a trade, an enemy) and
-- some out of tables built fresh on every draw. The first kind can be marked
-- by identity; the second needs a name that survives the next redraw.
local function MarkKey(d)
  if not d then return nil end
  if d.rec then return d.rec end
  local who = d.by or d.who or d.name or d.kosName or d.whisper
  local at = d.at or d.t or d.id
  if not who and not at then return nil end
  return tostring(mode) .. "|" .. tostring(who or "") .. "|"
    .. tostring(d.zone or "") .. "|" .. tostring(at or "")
end

-- Which column of a row is a person, and who that person is. Every list that
-- has one gets the same hover and the same double-click.
local PERSON_KEY = {
  by = true, who = true, name = true, kosName = true, with = true
}

local function RowPerson(d)
  if not d then return nil end
  return d.whisper or d.kosName or d.name or d.by or d.who or d.with
end

-- The tabs where the person on the row is on the other side. You cannot
-- whisper across factions in this game - it is not disabled, it does not
-- exist - so a double-click that opens a whisper box there is a button that
-- can never work.
local NO_WHISPER = { enemies = true, koslist = true }

local function Whisper(name)
  if not name or name == "" then return false end
  if ChatFrame_SendTell then
    ChatFrame_SendTell(name, SELECTED_DOCK_FRAME or DEFAULT_CHAT_FRAME)
  elseif ChatFrame_OpenChat then
    ChatFrame_OpenChat("/w " .. name .. " ")
  else
    return false
  end
  return true
end

-- "8%" of a level, or nothing when the run gave none.
local function PctText(r)
  local p = BT.RunPct and BT.RunPct(r) or nil
  if not p then return C.dim .. "-" .. C.off end
  return string.format((p < 10) and "%.1f%%" or "%.0f%%", p)
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

  -- The run you are in belongs at the top of the list. It used to appear only
  -- once you had walked out, which is the one moment you no longer need to be
  -- told about it - and when a booster says "that is five" mid-chain, the run
  -- you are standing in is exactly the one in dispute.
  --
  -- It is not in ChainDB.runs and does not go in: it counts for nothing until
  -- it is finished, it cannot be deleted, and it cannot be marked. It is shown
  -- and nothing more.
  local live = ChainCharDB.run
  if live and live.zone then
    local t = math.max(0, time() - (live.start or time()))
    local rate = (t > 0) and ((live.xp or 0) / t * 3600) or 0
    table.insert(out, {
      live = true,
      at = live.start, zone = live.zone, xp = live.xp or 0, t = t,
      k = live.k or 0, rate = rate, by = live.by, lvl = live.lvl,
      grpAvg = live.grpAvg, coin = live.coin or 0,
      pct = BT.RunPct({ xp = live.xp or 0, lvl = live.lvl }),
      tip = Lines(
        BT.Short(live.zone, live.map) or "?",
        "the run you are in, still going",
        BT.N(live.xp or 0) .. " xp, " .. (live.k or 0) .. " mobs, " .. BT.T(t),
        live.by and ("boosted by " .. live.by) or "clearing it yourself",
        "it counts for nothing until you walk out"
      ),
      cells = {
        C.good .. "now" .. C.off,
        BT.Short(live.zone, live.map) or "?",
        BT.N(live.xp or 0),
        PctText({ xp = live.xp or 0, lvl = live.lvl }),
        BT.T(t),
        tostring(live.k or 0),
        (rate > 0) and string.format("%.0fk", rate / 1000) or "-",
        ((live.coin or 0) > 0) and (C.gold .. BT.Coin(live.coin) .. C.off)
          or (C.dim .. "-" .. C.off),
        live.by or (C.dim .. "self" .. C.off),
        tostring(live.lvl or "-"),
        live.grpAvg and string.format("%.1f", live.grpAvg) or "-"
      }
    })
  end

  for _, r in ipairs(BT.Runs({})) do
    local a = Avg(r)
    local rate = ((r.t or 0) > 0) and (r.xp / r.t * 3600) or 0
    local aRate = (a and (a.longT or 0) > 0) and (a.long / a.longT * 3600) or nil
    table.insert(out, {
      rec = r,
      at = r.at, zone = r.zone, xp = r.xp, t = r.t, k = r.k,
      rate = ((r.t or 0) > 0) and (r.xp / r.t * 3600) or 0,
      by = r.by, lvl = r.lvl, grpAvg = r.grpAvg, coin = r.coin or 0,
      pct = BT.RunPct(r),
      tip = Lines(
        BT.Short(r.zone, r.map) or "?",
        date("%A %d %B, %H:%M", r.at or time()),
        BT.N(r.xp or 0) .. " xp, " .. (r.k or 0) .. " mobs, " .. BT.T(r.t)
          .. ((rate > 0) and (", " .. BT.N(rate) .. " xp/h") or ""),
        r.by and ("boosted by " .. r.by) or "cleared it yourself",
        ((r.coin or 0) > 0) and (BT.Coin(r.coin) .. " in raw gold off the mobs")
          or nil,
        r.grpAvg and string.format("group of %d, average level %.1f",
                                   r.grp or 0, r.grpAvg) or nil
      ),
      cells = {
        BT.T(time() - (r.at or time())) .. " ago",
        BT.Short(r.zone, r.map) or "?",
        Rate(r.xp, a and a.long, true) .. BT.N(r.xp) .. C.off,
        PctText(r),
        -- less time is better
        Rate(r.t, a and a.longT, false) .. BT.T(r.t) .. C.off,
        Rate(r.k, a and a.longK, true) .. tostring(r.k or 0) .. C.off,
        (rate > 0) and (Rate(rate, aRate, true)
          .. string.format("%.0fk", rate / 1000) .. C.off) or "-",
        -- raw gold off the mobs, the way NIT carries it: one number for the
        -- instance rather than four hundred lines in the loot log
        ((r.coin or 0) > 0) and (C.gold .. BT.Coin(r.coin) .. C.off)
          or (C.dim .. "-" .. C.off),
        r.by or (C.dim .. "self" .. C.off),
        tostring(r.lvl or "-"),
        r.grpAvg and string.format("%.1f", r.grpAvg) or "-"
      }
    })
  end
  -- The payments, in among the runs. "When did I pay him, and what have I had
  -- since" is one question, and it was two tabs: the times were in the Trade
  -- tab and the runs were here, and you were left holding a clock in your
  -- head. Put them on the same list, in the same order, and the answer is the
  -- rows between the money and the top.
  local ledger = BT.CreditLedger and BT.CreditLedger() or {}
  for _, t in ipairs(ChainDB.trades or {}) do
    local net = (t.gave or 0) - (t.got or 0)
    -- A balance you typed in is not a trade, but it is the single biggest
    -- thing that can happen to the reckoning: everything before it is thrown
    -- away and the count starts again from your number. It was invisible
    -- here, so a balance nobody could explain had no row to point at and no
    -- x to take it back with. It has both now.
    if t.at and t.setTo then
      local n = t.setTo
      table.insert(out, {
        trade = t, at = t.at, setTo = n,
        tip = Lines(
          "you set " .. (t.with or "?") .. "'s balance by hand",
          date("%A %d %B, %H:%M", t.at or time()),
          "counting starts again from " .. BT.Runsish(n)
            .. " - everything below this line stopped counting",
          "take it off with the x and the payments above and below add up "
            .. "again on their own"
        ),
        cells = {
          C.dim .. BT.T(time() - (t.at or time())) .. " ago" .. C.off,
          C.warn .. "set to" .. C.off .. C.dim .. "  "
            .. BT.Runsish(n) .. C.off,
          C.dim .. "-" .. C.off, C.dim .. "-" .. C.off,
          C.dim .. "-" .. C.off, C.dim .. "-" .. C.off,
          C.dim .. "-" .. C.off, C.dim .. "-" .. C.off,
          t.with or (C.dim .. "?" .. C.off),
          tostring(t.lvl or "-"),
          C.dim .. "-" .. C.off
        }
      })
    end
    if t.at and net ~= 0 then
      local led = ledger[t]
      local runs = led and led.bought or nil
      table.insert(out, {
        trade = t, at = t.at,
        tip = Lines(
          (net > 0) and ("paid " .. (t.with or "?"))
            or ("got back from " .. (t.with or "?")),
          date("%A %d %B, %H:%M", t.at or time()),
          BT.G(BT.Gold(math.abs(net)))
            .. (runs and string.format("  -  %.1f runs", runs) or ""),
          t.manual and "typed in by hand" or "the addon watched this one",
          "everything above this line is what you have had since"
        ),
        cells = {
          C.dim .. BT.T(time() - (t.at or time())) .. " ago" .. C.off,
          C.gold .. ((net > 0) and "paid" or "got back") .. C.off
            .. (runs and (C.dim .. string.format("  %.0f runs", runs) .. C.off)
                or ""),
          C.dim .. "-" .. C.off, C.dim .. "-" .. C.off,
          C.dim .. "-" .. C.off, C.dim .. "-" .. C.off,
          C.dim .. "-" .. C.off,
          C.gold .. BT.G(BT.Gold(math.abs(net))) .. C.off,
          t.with or (C.dim .. "?" .. C.off),
          tostring(t.lvl or "-"),
          C.dim .. "-" .. C.off
        }
      })
    end
  end

  -- newest first by default, and the one you are in is newer than all of them
  table.sort(out, function(a, b)
    if a.live ~= b.live then return a.live and true or false end
    return (a.at or 0) > (b.at or 0)
  end)
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
    -- What you have already paid him for and not yet had. Blank for anyone
    -- you have never traded: a zero there would read as "you are square",
    -- which is a different thing from "no money has ever changed hands".
    local credit = BT.BoosterCredit and BT.BoosterCredit(b.by) or nil
    local leftCell = C.dim .. "-" .. C.off
    if credit then
      local v = credit.left
      local col = (v >= 1) and C.good or ((v > -0.5) and C.warn or C.bad)
      leftCell = col .. string.format((math.abs(v) < 10) and "%.1f" or "%.0f", v)
        .. C.off
    end
    local vCol, vWord = BT.Grade(b.value, best.value)
    local rCol = select(1, BT.Grade(b.rate, best.rate))
    local mCol = select(1, BT.Grade(b.mobs, best.mobs))
    table.insert(out, {
      by = b.by, rate = b.rate, perRun = b.perRun, timePerRun = b.timePerRun,
      mobs = b.mobs, n = b.n, form = b.form, info = info, value = b.value,
      mine = (info.mine and b.n == 0) and true or false,
      left = credit and credit.left or nil, credit = credit,
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
        leftCell,
        others,
        ""            -- the note box sits here
      }
    })
  end
  return out
end

local function GoldRows()
  local out = {}
  local ledger = BT.CreditLedger and BT.CreditLedger() or {}
  for _, t in ipairs(BT.Trades({})) do
    local net = (t.gave or 0) - (t.got or 0)
    -- what this money is worth in runs, and where that leaves you. The point
    -- of the second number is that you stop counting: pay for ten, run four,
    -- and the row that took your money says six.
    local led = ledger[t]
    local buys = (led and led.bought) and (C.gold
      .. string.format((led.bought < 10) and "%.1f" or "%.0f", led.bought)
      .. C.off) or (C.dim .. (t.setTo and "set" or "-") .. C.off)
    local left = C.dim .. "-" .. C.off
    if led and led.left then
      local v = led.left
      local col = (v >= 1) and C.good or ((v > -0.5) and C.warn or C.bad)
      left = col .. string.format((math.abs(v) < 10) and "%.1f" or "%.0f", v)
        .. C.off
    end
    table.insert(out, {
      at = t.at, with = t.with, gave = t.gave, got = t.got, net = net,
      id = t.id, lvl = t.lvl, zone = t.zone, rec = t,
      manual = t.manual and true or nil, setTo = t.setTo,
      bought = led and led.bought or nil, leftRuns = led and led.left or nil,
      cells = {
        BT.T(time() - (t.at or time())) .. " ago",
        t.with or "?",
        (t.gave or 0) > 0 and BT.G(BT.Gold(t.gave)) or "-",
        (t.got or 0) > 0 and BT.G(BT.Gold(t.got)) or "-",
        (net >= 0 and C.gold or C.good) .. BT.G(BT.Gold(math.abs(net)))
          .. (net < 0 and " in" or "") .. C.off,
        buys,
        left,
        BT.ItemsText(t.gaveItems) and (C.info .. BT.ItemsText(t.gaveItems) .. C.off)
          or (C.dim .. "-" .. C.off),
        BT.ItemsText(t.gotItems) and (C.info .. BT.ItemsText(t.gotItems) .. C.off)
          or (C.dim .. "-" .. C.off),
        -- a line you typed has no zone to report, and saying so is the point:
        -- you should be able to see at a glance which of these the addon
        -- watched and which you told it about
        t.manual and (C.dim .. "by hand" .. C.off)
          or t.zone or (C.dim .. "-" .. C.off),
        t.id and (BT.BY_ID[t.id] and BT.BY_ID[t.id].label or t.id) or "-",
        tostring(t.lvl or "-"),
        t.by and (C.good .. "yes" .. C.off) or (C.dim .. "-" .. C.off)
      },
      tip = Lines(
        (t.with or "?") .. "   " .. date("%A %d %B, %H:%M", t.at or time()),
        ((t.gave or 0) > 0 and ("you paid " .. BT.G(BT.Gold(t.gave))) or "")
          .. (BT.ItemsText(t.gaveItems)
              and (((t.gave or 0) > 0 and " and " or "you gave ")
                   .. BT.ItemsText(t.gaveItems)) or ""),
        ((t.got or 0) > 0 and ("he handed back " .. BT.G(BT.Gold(t.got))) or "")
          .. (BT.ItemsText(t.gotItems)
              and (((t.got or 0) > 0 and " and " or "he handed you ")
                   .. BT.ItemsText(t.gotItems)) or ""),
        t.zone or nil,
        (led and led.bought)
          and (string.format("%.1f runs at %s a run", led.bought,
                             BT.G(led.per or 0))
               .. (((t.perRun or 0) > 0) and "" or " - at today's price, "
                   .. "because this trade is older than the addon's record "
                   .. "of what he charged"))
          or nil,
        (led and led.left)
          and ((led.left >= 0)
               and string.format("left him owing you %.1f runs", led.left)
               or string.format("left you %.1f runs ahead of what you had "
                                .. "paid for", -led.left))
          or nil,
        -- The working, because "you bought 3, that leaves 5" reads as bad
        -- arithmetic until you are told about the two from the pack before.
        (led and led.left and led.bought)
          and ((math.abs(led.carried or 0) < 0.05)
               and string.format("%.1f bought, nothing carried over",
                                 led.bought)
               or ((led.carried or 0) > 0
                   and string.format("%.1f bought + %.1f he still owed you = "
                                     .. "%.1f", led.bought, led.carried,
                                     led.left)
                   or string.format("%.1f bought, less the %.1f you had "
                                    .. "already taken = %.1f", led.bought,
                                    -(led.carried or 0), led.left)))
          or nil,
        (led and (led.ran or 0) > 0)
          and string.format("%d run%s recorded between this and the payment "
                            .. "before it", led.ran,
                            (led.ran == 1) and "" or "s")
          or nil,
        t.setTo and ("you set the balance here by hand. Everything before it "
          .. "stops counting and the tally starts again at "
          .. string.format("%.1f", t.setTo)) or nil,
        (t.manual and not t.setTo)
          and "you typed this one in yourself - the x removes it" or nil
      )
    })
  end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

-- Everyone who has advertised, from every channel, newest first. This is the
-- list you actually shop from: the Boosters tab answers "who sells the step I
-- am on", and this one answers "who is selling anything at all".
-- Who is selling. An advert is a person standing in a city saying they are
-- free right now; half an hour later they are three levels into somebody
-- else's chain and the line is a list of people to be disappointed by. So the
-- tab only shows the fresh ones.
--
-- What was learned from the advert - his price, his pack size - stays on his
-- record. That is knowledge about him, and it does not go stale the way the
-- offer does.
local AD_KEEP = 1800

local function AdRows()
  local out = {}
  local now = time()
  for name, info in pairs(ChainDB.boosters) do
    if info.adZone and info.adAt and (now - info.adAt) <= AD_KEEP then
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
        tip = Lines(
          name,
          (d and d.label or info.adZone)
            .. "   " .. BT.T(time() - (info.adAt or time())) .. " ago"
            .. "   " .. from,
          info.adText or "",
          (gold > 0)
            and ("He says " .. BT.G(gold)
                 .. ((pack > 1) and (" for " .. pack .. " runs") or " a run") .. ".")
            or "No price in the advert - click whisper and ask."
        )
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

-- The LFM and LFG half. A man asking to buy a boost is in the same trade you
-- are, so he is on Boosting with the rest of the buying and selling; he is
-- not somebody you are going to fill a group with.
local function GroupRows()
  local out = {}
  local mine = BT.FocusStep()
  for _, g in ipairs(BT.GroupLog()) do
   if g.kind ~= "wtb" then
    local d = g.id and BT.BY_ID[g.id]
    local age = time() - (g.at or time())
    local col = KIND_COL[g.kind] or C.dim
    -- a post about the instance you are actually on is the one you want
    local here = mine and g.id == mine.id
    out[#out + 1] = {
      at = g.at, by = g.by, kind = g.kind, needs = g.needs or "",
      levels = g.levels or "", from = g.from, min = d and d.min or nil,
      zone = d and d.label or (g.id or ""),
      whisper = g.by, rec = g,
      cells = {
        BT.T(age) .. " ago" .. ((g.n or 1) > 1
          and (C.dim .. " x" .. g.n .. C.off) or ""),
        (here and C.good or "") .. g.by .. (here and C.off or ""),
        col .. (KIND_WORD[g.kind] or g.kind) .. C.off,
        d and ((here and C.good or "") .. d.label .. (here and C.off or ""))
          or (C.dim .. "-" .. C.off),
        g.needs and (C.info .. g.needs .. C.off) or (C.dim .. "-" .. C.off),
        (d and BT.MinChunk(d)) or (g.levels and (C.dim .. g.levels .. C.off))
          or (C.dim .. "-" .. C.off),
        C.dim .. tostring(g.from or ""):gsub("^channel:", "") .. C.off,
        C.dim .. (g.text or "") .. C.off,
        ""
      },
      tip = Lines(
        g.by,
        (d and d.label or "no instance named")
          .. "   " .. BT.T(age) .. " ago"
          .. "   " .. tostring(g.from or ""):gsub("^channel:", "")
          .. ((g.n or 1) > 1 and ("   said " .. g.n .. " times") or ""),
        g.text or "",
        (KIND_WORD[g.kind] or g.kind)
          .. (g.needs and (", " .. g.needs) or "")
          .. (g.levels and (", he asks for levels " .. g.levels) or "") .. ".",
        -- the one level that is not a matter of opinion
        d and d.min and (((UnitLevel and UnitLevel("player") or 1) >= d.min)
          and ("you can enter " .. d.label .. " - it opens at " .. d.min)
          or ("you cannot enter " .. d.label .. " yet - it opens at " .. d.min))
          or nil
      )
    }
   end
  end
  return out
end

-- Everyone asking to buy one. The same posts, read for the other reason: not
-- "can I join this" but "is somebody else buying the same chain".
local function BuyerRows()
  local out = {}
  local mine = BT.FocusStep()
  for _, g in ipairs(BT.GroupLog()) do
   if g.kind == "wtb" then
    local d = g.id and BT.BY_ID[g.id]
    local age = time() - (g.at or time())
    local here = mine and g.id == mine.id
    out[#out + 1] = {
      at = g.at, by = g.by, from = g.from, min = d and d.min or nil,
      zone = d and d.label or (g.id or ""),
      whisper = g.by, rec = g,
      cells = {
        BT.T(age) .. " ago" .. ((g.n or 1) > 1
          and (C.dim .. " x" .. g.n .. C.off) or ""),
        (here and C.good or "") .. g.by .. (here and C.off or ""),
        d and ((here and C.good or "") .. d.label .. (here and C.off or ""))
          or (C.dim .. "-" .. C.off),
        (d and BT.MinChunk(d)) or (C.dim .. "-" .. C.off),
        C.dim .. tostring(g.from or ""):gsub("^channel:", "") .. C.off,
        C.dim .. (g.text or "") .. C.off,
        ""
      },
      tip = Lines(
        g.by .. " wants to buy",
        (d and d.label or "no instance named")
          .. "   " .. BT.T(age) .. " ago"
          .. "   " .. tostring(g.from or ""):gsub("^channel:", "")
          .. ((g.n or 1) > 1 and ("   said " .. g.n .. " times") or ""),
        g.text or "",
        here and "the step you are on - he is buying what you are buying"
          or nil
      )
    }
   end
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

-- Your record against somebody, as one cell. Green when you are ahead, red
-- when you are not, and nothing at all when you have never fought - a column
-- of "0-0" is a column of noise.
local function Record(e)
  local w, l = e.wins or 0, e.losses or 0
  if w == 0 and l == 0 then return C.dim .. "-" .. C.off, 0 end
  local col = (w > l) and C.good or (l > w) and C.bad or C.dim
  return col .. w .. "-" .. l .. C.off, w - l
end

-- Your customers. One row a man, and a row you can correct: the count is the
-- thing being argued about, so the number has to be reachable.
local function SellRows()
  local out = {}
  local here = BT.GroupNames and BT.GroupNames() or {}
  for _, c in ipairs(BT.Customers and BT.Customers() or {}) do
    local left = (c.runs or 0) - (c.done or 0)
    local col = (left >= 2) and C.good or ((left > 0.05) and C.warn or C.bad)
    local inGroup = here[c.name] and true or false
    out[#out + 1] = {
      rec = c, name = c.name, who = c.name, at = c.at,
      paid = c.paid or 0, runs = c.runs or 0, done = c.done or 0,
      left = left, per = c.per or 0, sell = c.name,
      cells = {
        (inGroup and "" or C.dim) .. c.name .. (inGroup and "" or C.off),
        C.gold .. BT.G(BT.Gold(c.paid or 0)) .. C.off,
        ((c.runs or 0) > 0) and string.format("%.0f", c.runs + 0.5 - 0.5)
          or (C.dim .. "-" .. C.off),
        col .. BT.SellCount(c) .. C.off,
        "",            -- the editable box sits here
        ((c.per or 0) > 0) and (C.dim .. BT.G(BT.Gold(c.per)) .. C.off)
          or (C.dim .. "-" .. C.off),
        C.dim .. BT.T(time() - (c.at or time())) .. " ago" .. C.off,
        inGroup and (C.good .. "yes" .. C.off) or (C.bad .. "gone" .. C.off),
        ""
      },
      tip = Lines(
        c.name,
        BT.G(BT.Gold(c.paid or 0)) .. " paid"
          .. (((c.runs or 0) > 0)
              and ("   " .. BT.Runsish(c.runs) .. " bought") or ""),
        BT.SellCount(c) .. " done"
          .. (((c.runs or 0) > 0)
              and ("   " .. BT.Runsish(math.max(0, left)) .. " to go") or ""),
        inGroup and "in your group - the next run counts for him"
          or "not in your group - runs will not count for him",
        ((c.runs or 0) <= 0)
          and "no price was set when he paid, so nobody knows what it bought"
          or nil
      )
    }
  end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

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
      rec = e, kosWhy = why, note = note, score = select(2, Record(e)),
      cells = {
        col .. BT.T(age) .. " ago" .. C.off,
        col .. e.name .. C.off,
        (e.level and e.level > 0) and tostring(e.level) or (C.dim .. "?" .. C.off),
        cls and (cls .. (e.class or "") .. C.off) or (C.dim .. "-" .. C.off),
        e.guild and ((why == "guild" and C.bad or C.dim) .. e.guild .. C.off)
          or (C.dim .. "-" .. C.off),
        C.dim .. (BT.Short(e.zone) or e.zone or "-") .. C.off,
        C.dim .. tostring(e.n or 1) .. C.off,
        (Record(e)),
        C.dim .. (e.how or "-") .. C.off,
        "",           -- the KOS button sits here
        ""            -- and the note box
      },
      tip = Lines(
        e.name .. ((e.level and e.level > 0) and ("  " .. e.level) or ""),
        (e.class or "") .. (e.guild and ("   <" .. e.guild .. ">") or ""),
        "seen " .. (e.n or 1) .. " time" .. ((e.n or 1) == 1 and "" or "s")
          .. ", last " .. BT.T(age) .. " ago"
          .. (e.zone and (" in " .. e.zone) or ""),
        why and (why == "guild"
          and "marked through his guild - the whole lot raises the alarm"
          or "marked by name - always raises the alarm") or nil,
        note
      )
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

-- Everyone you have marked - which is not the same list as everyone nearby,
-- and gets long enough to be worth its own view. A name you marked three
-- weeks ago is not in the Enemies tab at all once the sighting has aged out,
-- and it is exactly the one you want to be able to find and edit.
local function KOSRows()
  local out = {}
  local now = time()
  local seen = ChainDB.enemies or {}

  -- Marked, plus anybody you have written about. A note on somebody you did
  -- not mark has to be findable, or it is a note you will never read again.
  local names, kosSet = {}, {}
  for _, k in ipairs(BT.KOSList()) do
    names[#names + 1] = k.name
    kosSet[k.name] = true
  end
  for _, n in ipairs(BT.NotedList()) do
    if not kosSet[n.name] then names[#names + 1] = n.name end
  end

  for _, who in ipairs(names) do
    local k = { name = who, note = BT.EnemyNote(who) }
    local marked = kosSet[who]
    local e = seen[k.name] or {}
    local age = e.at and (now - e.at) or nil
    out[#out + 1] = {
      who = k.name, kind = marked and "name" or "note", note = k.note,
      kosName = k.name, marked = marked,
      level = e.level, class = e.class, at = e.at or 0, n = e.n, zone = e.zone,
      score = select(2, Record(e)),
      cells = {
        (marked and C.bad or C.gold) .. k.name .. C.off,
        C.dim .. (marked and "marked" or "note only") .. C.off,
        (e.level and e.level > 0)
          and (e.level .. (e.levelGuess and "+" or "")) or (C.dim .. "??" .. C.off),
        e.class and ((CLASS_COL[e.class] or C.dim) .. BT.ClassLabel(e.class) .. C.off)
          or (C.dim .. "-" .. C.off),
        age and (C.dim .. BT.T(age) .. " ago" .. C.off)
            or (C.dim .. "not since you marked him" .. C.off),
        C.dim .. tostring(e.n or 0) .. C.off,
        (Record(e)),
        C.dim .. (BT.Short(e.zone) or e.zone or "-") .. C.off,
        "", ""
      },
      tip = Lines( k.name, marked and "marked by name" or "written about, not marked",
              k.note )
    }
  end

  local guilds, gSet = {}, {}
  for _, g in ipairs(BT.KOSGuildList()) do
    local n = g.guild or g.name
    if n then guilds[#guilds + 1] = n gSet[n] = true end
  end
  for _, g in ipairs(BT.NotedGuildList()) do
    if not gSet[g.guild] then guilds[#guilds + 1] = g.guild end
  end

  for _, gname in ipairs(guilds) do
    local g = { guild = gname, note = BT.GuildNote(gname) }
    local marked = gSet[gname]
    if gname then
      -- how many of them you have actually run into
      local count, last = 0, nil
      for _, e in pairs(seen) do
        if e.guild == gname then
          count = count + 1
          if not last or (e.at or 0) > last then last = e.at end
        end
      end
      out[#out + 1] = {
        who = gname, kind = "guild", note = g.note, kosGuild = gname,
        at = last or 0, n = count, marked = marked,
        cells = {
          (marked and C.bad or C.gold) .. "<" .. gname .. ">" .. C.off,
          C.dim .. (marked and "guild" or "guild note") .. C.off,
          C.dim .. "-" .. C.off,
          C.dim .. "-" .. C.off,
          last and (C.dim .. BT.T(now - last) .. " ago" .. C.off)
               or (C.dim .. "never met one" .. C.off),
          C.dim .. tostring(count) .. C.off,
          C.dim .. "-" .. C.off,
          C.dim .. "-" .. C.off,
          "", ""
        },
        tip = Lines( "<" .. gname .. ">",
                marked and "the whole guild is marked" or "a note, no mark",
                count > 0 and (count .. " of them seen") or nil, g.note )
      }
    end
  end

  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

-- One row per corpse.
--
-- The log stores one entry per thing, which is right - exports and totals
-- want it that way, and two of the same item off one mob is two drops. But a
-- mob that gave you a jerkin, three cloth and thirty-five copper is one
-- event, and reading it as three lines that happen to sit next to each other
-- is reading it wrong.
--
-- Grouped on the way out rather than on the way in: the same entries can be
-- counted, exported and totalled without this ever being in the way.
local GROUP_WINDOW = 6

local function LootGroups()
  local flat = BT.LootLog()          -- newest first
  local out = {}
  for _, e in ipairs(flat) do
    local g = out[#out]
    -- the same person, the same corpse, and close enough in time to be the
    -- same loot window. An unknown corpse only ever groups with itself.
    local same = g and g.who == e.who and g.from == e.from
      and math.abs((g.at or 0) - (e.at or 0)) <= GROUP_WINDOW
    if not same then
      g = { at = e.at, who = e.who, from = e.from, zone = e.zone,
            step = e.step, by = e.by, items = {}, n = 0, copper = 0,
            value = 0, unpriced = 0 }
      out[#out + 1] = g
    end
    if e.copper then
      g.copper = g.copper + e.copper
      g.value = g.value + e.copper
    else
      g.items[#g.items + 1] = e
      g.n = g.n + (e.n or 1)
      local v = BT.LootValue(e)
      if v then g.value = g.value + v else g.unpriced = g.unpriced + 1 end
    end
    if (e.at or 0) > (g.at or 0) then g.at = e.at end
  end
  return out
end

-- Everything that fell, in one cell. Coins last, because they are the one
-- part that is never the reason you looked.
local QUALITY_COL = {
  [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00",
  [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000",
}

local function GroupText(g, full)
  local bits = {}
  for _, e in ipairs(g.items) do
    local q = BT.LootQuality(e)
    local col = QUALITY_COL[q or 1] or "|cffffffff"
    local n = (e.n or 1) > 1 and ((e.n) .. "x ") or ""
    bits[#bits + 1] = col .. n .. BT.LootName(e) .. C.off
  end
  if g.copper > 0 then bits[#bits + 1] = C.gold .. BT.Coin(g.copper) .. C.off end
  if #bits == 0 then return C.dim .. "-" .. C.off end
  if full or #bits <= 3 then return table.concat(bits, C.dim .. ", " .. C.off) end
  -- three and a tally: the rest is on the tooltip, and a cell that runs into
  -- the next column is worse than a cell that says there is more
  return table.concat(bits, C.dim .. ", " .. C.off, 1, 3)
    .. C.dim .. "  +" .. (#bits - 3) .. C.off
end

local function LootRows()
  local out = {}
  local me = UnitName and UnitName("player") or nil
  -- Ask the client for anything it has not seen before drawing a single row.
  -- An uncached item is a name and nothing else - no stats, no armour, no
  -- required level - and that is most of somebody else's loot.
  if BT.WarmLoot then BT.WarmLoot(ChainDB.loot) end
  for _, g in ipairs(LootGroups()) do
    local tip = Lines( g.from or ((g.who == me) and "no source recorded"
                             or "loot lines do not say what somebody else looted from") )
    for _, e in ipairs(g.items) do
      local v = BT.LootValue(e)
      tip[#tip + 1] = "   " .. ((e.n or 1) > 1 and (e.n .. "x ") or "")
        .. BT.LootName(e) .. (v and ("   " .. BT.Coin(v)) or "   not priced yet")
    end
    if g.copper > 0 then tip[#tip + 1] = "   " .. BT.Coin(g.copper) end
    tip[#tip + 1] = " "
    tip[#tip + 1] = (g.who or "?") .. " picked it up"
      .. (g.zone and (" in " .. g.zone) or "")
    if g.by then tip[#tip + 1] = "during a run with " .. g.by end
    if g.unpriced > 0 then
      tip[#tip + 1] = g.unpriced .. " of these have no price yet - the client "
        .. "only knows once it has seen the item"
    end

    -- The best thing the corpse gave, which is the one you would have opened
    -- a tooltip for, and what to call its quality. Sorting on the number
    -- rather than the word puts epic above rare rather than alphabetically
    -- between them.
    local best, bq = BT.BestLoot(g.items)
    local qWord = BT.QualityWord(bq)
    local qCell = C.dim .. "-" .. C.off
    if qWord then
      qCell = (QUALITY_COL[bq or 1] or "|cffffffff") .. qWord .. C.off
    end

    out[#out + 1] = {
      at = g.at, name = GroupText(g), n = g.n, who = g.who, value = g.value,
      zone = g.zone, step = g.step, by = g.by, from = g.from, rec = g,
      quality = bq, link = best and best.link or nil,
      cells = {
        C.dim .. BT.T(time() - (g.at or time())) .. " ago" .. C.off,
        GroupText(g),
        (g.n > 0) and tostring(g.n) or (C.dim .. "-" .. C.off),
        qCell,
        (g.who == me) and (C.good .. (g.who or "?") .. C.off)
          or (C.dim .. (g.who or "?") .. C.off),
        g.from and (C.dim .. g.from .. C.off) or (C.dim .. "-" .. C.off),
        (g.value > 0) and (C.gold .. BT.Coin(g.value) .. C.off
          .. ((g.unpriced > 0) and (C.dim .. "+" .. C.off) or ""))
          or (C.dim .. "-" .. C.off),
        C.dim .. (BT.Short(g.zone) or g.zone or "-") .. C.off,
        C.dim .. (g.step or "-") .. C.off,
        C.dim .. (g.by or "-") .. C.off
      },
      tip = tip
    }
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
        -- where this row came from, because a count you cannot trace is a
        -- count you can only argue with
        e.nit and (C.dim .. "from NIT" .. C.off)
          or e.ghost and (C.warn .. "the game said" .. C.off)
          or e.fromRun and (C.dim .. "rebuilt" .. C.off)
          or (C.dim .. "own" .. C.off)
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

    -- A stretch you do yourself has no runs, no price and nobody to pay. The
    -- only figures it can honestly carry are the levels and the experience,
    -- and how long that takes is your own rate rather than any instance's.
    if seg.e.solo then
      local rate = BT.Rate and BT.Rate()
      table.insert(out, {
        own = seg.e.own,
        tip = Lines(
          seg.e.label,
          "levels " .. seg.from .. " to " .. seg.to,
          "a stretch you do yourself - no runs, no gold, nobody to pay",
          rate and ("at your rate of " .. BT.N(rate) .. " xp/h that is about "
                    .. BT.T(xp / rate * 3600)) or nil,
          "the x removes it from the plan"
        ),
        cells = {
          C.info .. seg.e.label .. C.off,
          "-", "-",
          seg.from .. " > " .. seg.to,
          "-",
          (rate and rate > 0) and BT.T(xp / rate * 3600) or "-",
          C.dim .. "-" .. C.off, C.dim .. "-" .. C.off, C.dim .. "-" .. C.off,
          C.dim .. "on your own" .. C.off
        }
      })
    else

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
      tip = Lines(
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
      ),
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
  if mode == "wtb" then return BuyerRows() end
  if mode == "sell" then return SellRows() end
  if mode == "enemies" then return EnemyRows() end
  if mode == "pvp" then return PvPRows() end
  if mode == "koslist" then return KOSRows() end
  if mode == "loot" then return LootRows() end
  if mode == "route" then return RouteRows() end
  if mode == "gold" then return GoldRows() end
  if mode == "locks" then return LockRows() end
  if mode == "reported" then return ReportedRows() end
  return RunRows()
end

-- One line under the table saying what the tab adds up to
local function Summary()
  -- The 'after' column is frozen: it is the balance that payment left you on,
  -- at the moment it was made, which is what a ledger is for. It does not move
  -- afterwards and it should not. The number that moves belongs here.
  if mode == "gold" then
    local seen, out = {}, {}
    for i = #ChainDB.trades, 1, -1 do
      local t = ChainDB.trades[i]
      local who = t.with and ((BT.PaysFor and BT.PaysFor(t.with)) or t.with)
      if who and not seen[who] then
        seen[who] = true
        local c = BT.BoosterCredit and BT.BoosterCredit(who)
        if c then
          local v = (c.hisLeft ~= nil) and c.hisLeft or c.left
          local col = (v >= 1) and C.good or ((v > -0.5) and C.warn or C.bad)
          out[#out + 1] = who .. " " .. col
            .. string.format((math.abs(v) < 10) and "%.1f" or "%.0f", v)
            .. C.off .. C.dim
            .. ((c.hisLeft ~= nil) and " runs (his count)" or " runs") .. C.off
        end
      end
      if #out >= 3 then break end
    end
    if #out == 0 then return "no payments on record" end
    return "they owe you:  " .. table.concat(out, C.dim .. "   -   " .. C.off)
  end
  if mode == "loot" then
    local value, byWho, items, coins, unknown = BT.LootTotals()
    if items == 0 and coins == 0 then return "nothing logged yet" end
    local txt = items .. " item" .. (items == 1 and "" or "s")
    if coins > 0 then
      txt = txt .. "  -  " .. C.gold .. BT.Coin(coins) .. C.off
        .. " raw gold off mobs"
    end
    if value > 0 then
      txt = txt .. "  -  " .. C.gold .. BT.Coin(value) .. C.off .. " all told"
    end
    if unknown > 0 then
      txt = txt .. C.dim .. "  (" .. unknown .. " not priced yet)" .. C.off
    end
    if byWho[1] then
      txt = txt .. C.dim .. "  -  most to " .. byWho[1].who .. C.off
    end
    return txt
  end
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
        return C.dim .. "reading sellers out of chat is off - turn it on in "
          .. "the settings" .. C.off
      end
      return "nobody selling in the last half hour.  Boosters advertise in "
        .. "Trade (only inside a city) and LookingForGroup - join those "
        .. "channels and stand in a city."
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
  elseif mode == "groups" or mode == "wtb" then
    local buying = (mode == "wtb")
    local all = {}
    for _, g in ipairs(BT.GroupLog()) do
      if (g.kind == "wtb") == buying then all[#all + 1] = g end
    end
    if #all == 0 then
      if not ChainDB.readGroups then
        return C.dim .. "reading group posts is off - turn it on in the settings" .. C.off
      end
      if buying then
        return "nobody asking to buy just now.  WTB posts are read from the "
          .. "same channels as the rest - join LookingForGroup and the city "
          .. "channels."
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
    return #all .. (buying and " buyer" or " post") .. (#all == 1 and "" or "s")
      .. " kept"
      .. C.dim .. "   " .. fresh .. " in the last 15 minutes" .. C.off
      .. ((here > 0 and step)
          and ("   " .. C.good .. here .. " for " .. step.label .. C.off) or "")
  elseif mode == "sell" then
    local list = BT.Customers and BT.Customers() or {}
    local step = BT.FocusStep()
    local gold, pack = BT.SellPrice(step and step.id)
    local price = (gold > 0)
      and (C.gold .. BT.G(gold) .. C.off .. C.dim .. " for " .. pack
           .. " runs" .. C.off)
      or (C.bad .. "no price set" .. C.off
          .. C.dim .. " - gold that comes in cannot be turned into runs"
          .. C.off)
    if #list == 0 then
      return "nobody has paid you yet.  " .. price
        .. C.dim .. "   trade a man in your group and he lands here" .. C.off
    end
    local here = BT.GroupNames and BT.GroupNames() or {}
    local owed, gone, took = 0, 0, 0
    for _, c in ipairs(list) do
      owed = owed + math.max(0, (c.runs or 0) - (c.done or 0))
      took = took + (c.paid or 0)
      if not here[c.name] then gone = gone + 1 end
    end
    return #list .. " paying"
      .. C.dim .. "   " .. C.off .. BT.Runsish(owed) .. C.dim .. " to deliver"
      .. C.off
      .. C.dim .. "   " .. C.off .. C.gold .. BT.G(BT.Gold(took)) .. C.off
      .. C.dim .. " taken" .. C.off
      .. ((gone > 0) and (C.dim .. "   " .. gone .. " not in your group"
                          .. C.off) or "")
      .. "   " .. price
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
    -- "6 runs" against a list with two payments in it reads as "six since the
    -- last one", and it is not: it is everything on record. The one you were
    -- actually asking about is the one since the money changed hands, so it
    -- says both and labels each.
    local all = BT.Runs({})
    local agg = BT.Aggregate(all, #all)
    if not agg then return nil end
    local txt = #all .. " runs on record" .. C.dim .. "   "
      .. BT.N(agg.totalXP) .. " xp   " .. BT.T(agg.totalT) .. " inside" .. C.off
    local who = (BT.CurrentBooster and BT.CurrentBooster())
      or ChainCharDB.lastBy
    local credit = who and BT.BoosterCredit and BT.BoosterCredit(who) or nil
    if credit then
      -- Two different numbers that look like one. The pack is what the last
      -- payment bought and it is the figure on the bar; the balance is
      -- everything you are owed, carry-over from earlier packs included. Say
      -- them apart, and say the pack the same way the bar says it - the two
      -- reading differently is what sends you looking for a bug.
      txt = txt .. "   |   "
      if credit.ofPack and credit.ofPack >= 1
         and (credit.donePack or 0) <= credit.ofPack then
        txt = txt .. C.good .. credit.donePack .. "/"
          .. math.floor(credit.ofPack + 0.5) .. C.off .. " in this pack"
          .. C.dim .. "   " .. C.off
      else
        -- no pack to speak of: say what has happened since the money instead
        local since = #BT.Runs({ by = who,
                                 since = ((BT.LastPaid and BT.LastPaid(who))
                                          or 0) + 1 })
        txt = txt .. C.good .. since .. C.off .. " since you last paid " .. who
          .. C.dim .. "   " .. C.off
      end
      local v = (credit.hisLeft ~= nil) and credit.hisLeft or credit.left
      txt = txt .. C.dim
        .. ((v and v > -0.5)
            and (string.format((math.abs(v) < 10) and "%.1f" or "%.0f", v)
                 .. " to come in all")
            or (string.format("%.1f", -(v or 0)) .. " past what you paid for"))
        .. C.off
      -- and if that figure is counted from a number you typed rather than
      -- from your payments, say so. A balance nobody can derive from the rows
      -- above it is a balance you cannot argue with.
      if credit.setAt and credit.setTo then
        txt = txt .. C.warn .. "   counted from the "
          .. math.floor(credit.setTo + 0.5) .. " you set by hand "
          .. BT.T(time() - credit.setAt) .. " ago" .. C.off
      end
    end
    return txt
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

  -- Enemies and the kill-on-sight list are two views of one tab: they answer
  -- different questions ("who is here" and "who am I watching for") and the
  -- second one gets long, but they belong together.
  local enemyish = (mode == "enemies" or mode == "koslist")
  if win.enemyView then
    win.enemyView:SetShown(enemyish)
    win.enemyView.fs:SetText(mode == "koslist"
      and (C.bad .. "kill on sight" .. C.off .. C.dim .. "  - show everyone" .. C.off)
      or ("everyone seen" .. C.dim .. "  - show marked" .. C.off))
  end

  -- and the hand-entry row belongs to the Trade tab, on that same line again
  local paying = (mode == "gold")
  for _, w in ipairs({ win.payLabel, win.payName, win.payPick, win.payGold,
                       win.payButton, win.payOr, win.payRuns,
                       win.payRunsButton, win.payNote }) do
    if w then w:SetShown(paying) end
  end
  -- Whoever is boosting you now is who both of these are about, nine times in
  -- ten. Leaving the name blank means typing a number, pressing the button
  -- and being told "no name" - so it starts out filled in with him.
  if paying and win.payName and not win.payName:HasFocus()
     and (win.payName:GetText() or "") == "" then
    local who = (BT.CurrentBooster and BT.CurrentBooster())
      or ChainCharDB.lastBy
    if who then win.payName:SetText(who) end
  end
  -- And it says what the figure is right now, beside the box you would type
  -- over. "to come" in the rows above is frozen at each payment; this is the
  -- live one, and the two being different is the whole reason to look.
  if paying and win.payNote then
    local who = win.payName and win.payName:GetText()
    local c = (who and who ~= "" and BT.BoosterCredit) and BT.BoosterCredit(who)
    local v = c and (c.hisLeft or c.left) or nil
    win.payNote:SetText(v
      and (C.dim .. "now " .. C.off
           .. string.format((math.abs(v) < 10) and "%.1f" or "%.0f", v)
           .. C.dim .. " - the tally starts again from what you type" .. C.off)
      or (C.dim .. "the tally starts again from there" .. C.off))
  end

  -- and the settle-up row belongs to the History tab
  local counting = (mode == "runs")
  for _, w in ipairs({ win.sinceButton, win.sayButton, win.sayNote,
                       win.whisperTo, win.whisperButton }) do
    if w then w:SetShown(counting) end
  end
  if counting and win.sayNote then
    local n = 0
    for _, r in ipairs(ChainDB.runs) do if picked[r] then n = n + 1 end end
    -- the name to whisper: whoever the marked runs were with, since that is
    -- the person the argument is with
    if win.whisperTo and not win.whisperTo:HasFocus() then
      local who
      for _, r in ipairs(ChainDB.runs) do
        if picked[r] and r.by then who = r.by end
      end
      who = who or (BT.CurrentBooster and BT.CurrentBooster())
        or ChainCharDB.lastBy
      if who and (win.whisperTo:GetText() or "") == "" then
        win.whisperTo:SetText(who)
      end
    end
    win.sayNote:SetText((n > 0)
      and (C.good .. n .. C.off .. C.dim .. " marked - the + on each row"
           .. C.off)
      or (C.dim .. "mark runs with the + on each row, then say them" .. C.off))
    if win.sayButton then
      win.sayButton.fs:SetText((IsInRaid and IsInRaid())
        and "say in raid" or "say in party")
    end
  end

  -- and the own-step row belongs to the Route tab
  local routing = (mode == "route")
  for _, w in ipairs({ win.ownLabel, win.ownName, win.ownPick, win.ownFrom,
                       win.ownTo, win.ownAdd, win.ownNote }) do
    if w then w:SetShown(routing) end
  end

  -- and the seller's row belongs to My boost
  local selling = (mode == "sell")
  for _, w in ipairs({ win.sellLabel, win.sellGold, win.sellPer, win.sellPack,
                       win.sellRuns, win.sellAd, win.sellPost, win.sellSay }) do
    if w then w:SetShown(selling) end
  end
  if selling then
    local step = BT.FocusStep()
    local gold, pack = BT.SellPrice(step and step.id)
    if not win.sellGold:HasFocus() then
      win.sellGold:SetText((gold > 0) and tostring(math.floor(gold)) or "")
    end
    if not win.sellPack:HasFocus() then
      win.sellPack:SetText(tostring(pack))
    end
    if not win.sellAd:HasFocus() then
      win.sellAd:SetText(BT.SellAd(step and step.id)
        or BT.SellAdDefault(step))
    end
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
      -- A column heading has room for two words, and two words cannot say
      -- what "after" or "he gave" mean. The fourth field says it properly,
      -- on the heading itself, where you are already looking when you wonder.
      h.hint = col[4]
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
      row.link = d.link
      local rx = 0
      local whoX, whoW = nil, nil
      for ci, col in ipairs(layout.cols) do
        local fs = row.cells[ci]
        if not fs then break end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", row, "LEFT", rx, 0)
        fs:SetWidth(col[2] - 4)
        fs:SetText(d.cells[ci] or "")
        fs:Show()
        if not whoX and PERSON_KEY[col[3] or ""] then whoX, whoW = rx, col[2] end
        rx = rx + col[2]
      end
      for ci = #layout.cols + 1, #row.cells do row.cells[ci]:Hide() end

      -- marked, and who the line is about
      row.markKey = MarkKey(d)
      row.mark:SetWidth(math.max(1, rx))
      row.mark:SetShown((row.markKey and selected == row.markKey) and true or false)
      row.person = RowPerson(d)
      row.canWhisper = not NO_WHISPER[mode]
      row.who.canWhisper = row.canWhisper
      if row.person and whoX then
        row.who.person = row.person
        row.who:ClearAllPoints()
        row.who:SetPoint("LEFT", row, "LEFT", whoX, 0)
        row.who:SetWidth(math.max(20, whoW - 4))
        row.who:Show()
      else
        row.who.person = nil
        row.who:Hide()
      end
      -- the x removes a run from the averages on History, and on Boosters it
      -- removes somebody you put in the list yourself. It never appears on a
      -- booster you have actually run with: that is measured history.
      row.pick.rec = nil
      if mode == "runs" and d.rec then
        row.pick.rec = d.rec
        row.pick.fs:SetText(picked[d.rec] and (C.good .. "v" .. C.off) or "+")
        row.pick.hint = "mark this run, then use 'say in party' to put the "
          .. "times in chat. Marks are not saved."
        row.pick:Show()
      else
        row.pick:Hide()
      end
      row.del.rec, row.del.name, row.del.trade, row.del.own = nil, nil, nil, nil
      row.del.customer = nil
      -- the first two cells describe the row well enough to name it in the
      -- question: "2h 39m ago   paid  10 runs"
      row.del.what = ((tostring(d.cells and d.cells[1] or "")
        :gsub("|c%x%x%x%x%x%x%x%x", "")):gsub("|r", ""))
        .. "   " .. ((tostring(d.cells and d.cells[2] or "")
        :gsub("|c%x%x%x%x%x%x%x%x", "")):gsub("|r", ""))
      if mode == "runs" and d.trade then
        row.del.trade = d.trade
        row.del.hint = "take this payment out of the reckoning. The runs "
          .. "it bought stop counting with it."
        row.del:Show()
      elseif mode == "runs" and d.rec then
        row.del.rec = d.rec
        row.del.hint = "throw this run out of the averages. It stays in "
          .. "no list and stops affecting every figure worked out from it."
        row.del:Show()
      elseif mode == "boosters" and d.mine then
        row.del.name = d.by
        row.del.hint = "remove somebody you added by hand. A booster you "
          .. "have actually run with cannot be removed - that is measured "
          .. "history."
        row.del:Show()
      elseif mode == "sell" and d.sell then
        row.del.customer = d.sell
        row.del.hint = "take him off the list. What he paid and what he has "
          .. "had both go; this is the list of who you are boosting now, "
          .. "not a history."
        row.del:Show()
      elseif mode == "route" and d.own then
        row.del.own = d.own
        row.del.hint = "take this stretch out of the plan"
        row.del:Show()
      elseif mode == "gold" and d.rec then
        -- Every trade row, not only the ones you typed. Detection is now an
        -- inference - a window that closed and never mentioned a cancel - and
        -- anything inferred has to be correctable by the person who was
        -- actually there.
        row.del.trade = d.rec
        row.del.hint = "remove this trade. Everything worked out from it "
          .. "- what it bought, what he owes you - goes with it."
        row.del:Show()
      else
        row.del:Hide()
      end

      if (mode == "ads" or mode == "groups" or mode == "wtb")
         and d.whisper then
        local wx = 0
        for ci, col in ipairs(layout.cols) do
          if ci < #layout.cols then wx = wx + col[2] end
        end
        row.whisper.name = d.whisper
        row.whisper:ClearAllPoints()
        row.whisper:SetPoint("LEFT", row, "LEFT", wx, 0)
        row.whisper:Show()
      else
        Hint(row.whisper, "open a whisper to this person - the name is filled "
      .. "in, including any accents in it")
    row.whisper:Hide()
      end

      -- One note box, three tabs that want it. The branches below each show
      -- it, and the last one used to hide it again in its else - so the note
      -- on Enemies was positioned, filled in, and then switched off on the
      -- same pass. It saved perfectly well; you could just never see it.
      local noteShown = false
      if mode == "koslist" and (d.kosName or d.kosGuild) then
        local kx, nx = 0, 0
        for ci, col in ipairs(layout.cols) do
          if ci < #layout.cols - 1 then kx = kx + col[2] end
          if ci < #layout.cols then nx = nx + col[2] end
        end
        row.kos.name, row.kos.guild = d.kosName, d.kosGuild
        row.kos.clearGuild = d.marked and d.kosGuild or nil
        row.kos.markGuild = (not d.marked) and d.kosGuild or nil
        row.kos.fs:SetText(d.marked and "clear" or "mark")
        row.kos.bg:SetColorTexture(d.marked and 0.45 or 0.15,
                                   d.marked and 0.12 or 0.15, 0.15, 0.9)
        row.kos:ClearAllPoints()
        row.kos:SetPoint("LEFT", row, "LEFT", kx, 0)
        row.kos:Show()

        -- all three every time: a stale one routes what you type into
        -- whoever happened to be on this row on the last tab you looked at
        row.note.by, row.note.kos, row.note.kosGuild = nil, d.kosName, d.kosGuild
        noteShown = true
        if not row.note:HasFocus() then row.note:SetText(d.note or "") end
        row.note:ClearAllPoints()
        row.note:SetPoint("LEFT", row, "LEFT", nx, 0)
        -- as wide as the column it sits in, whichever tab that is: a box that
        -- keeps one fixed width overhangs the moment a column changes size
        row.note:SetWidth(math.max(40, layout.cols[#layout.cols][2] - 4))
        row.note:Show()
      elseif mode == "enemies" and d.name then
        local kx, nx = 0, 0
        for ci, col in ipairs(layout.cols) do
          if ci < #layout.cols - 1 then kx = kx + col[2] end
          if ci < #layout.cols then nx = nx + col[2] end
        end
        row.kos.name, row.kos.guild = d.name, d.guild
        row.kos.clearGuild = nil
        row.kos.fs:SetText(d.kosWhy and "clear" or "KOS")
        row.kos.bg:SetColorTexture(d.kosWhy and 0.45 or 0.15,
                                   d.kosWhy and 0.12 or 0.15, 0.15, 0.9)
        row.kos:ClearAllPoints()
        row.kos:SetPoint("LEFT", row, "LEFT", kx, 0)
        row.kos:Show()

        row.note.by, row.note.kos, row.note.kosGuild = nil, d.name, nil
        noteShown = true
        if not row.note:HasFocus() then row.note:SetText(d.note or "") end
        row.note:ClearAllPoints()
        row.note:SetPoint("LEFT", row, "LEFT", nx, 0)
        -- as wide as the column it sits in, whichever tab that is: a box that
        -- keeps one fixed width overhangs the moment a column changes size
        row.note:SetWidth(math.max(40, layout.cols[#layout.cols][2] - 4))
        row.note:Show()
      else
        Hint(row.kos, "mark this player, or the whole guild on a guild row. A "
      .. "marked player sets off the alarm whether or not you have alerts "
      .. "on, and his nameplate is marked too.")
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

        -- column 12 is what he still owes you, and it is a box: the figure
        -- is inferred, and when an inference is wrong you are the one who
        -- knows
        local lx = 0
        for ci, col in ipairs(layout.cols) do
          if ci < 12 then lx = lx + col[2] end
        end
        row.left.by = d.by
        if not row.left:HasFocus() then
          local v = d.left
          row.left:SetText(v and string.format(
            (math.abs(v) < 10) and "%.1f" or "%.0f", v) or "")
        end
        row.left:ClearAllPoints()
        row.left:SetPoint("LEFT", row, "LEFT", lx, 0)
        row.left:SetWidth(math.max(36, layout.cols[12][2] - 6))
        row.left:Show()

        -- and the last column is yours to write in
        local nx = 0
        for ci, col in ipairs(layout.cols) do
          if ci < #layout.cols then nx = nx + col[2] end
        end
        row.note.by, row.note.kos, row.note.kosGuild = d.by, nil, nil
        noteShown = true
        if not row.note:HasFocus() then row.note:SetText(d.info.note or "") end
        row.note:ClearAllPoints()
        row.note:SetPoint("LEFT", row, "LEFT", nx, 0)
        -- as wide as the column it sits in, whichever tab that is: a box that
        -- keeps one fixed width overhangs the moment a column changes size
        row.note:SetWidth(math.max(40, layout.cols[#layout.cols][2] - 4))
        row.note:Show()
      elseif mode == "sell" and d.sell then
        -- Column 5 is what he still has coming, and it is a box for the same
        -- reason the buyer's is: the count is the thing being argued about,
        -- so the number has to be reachable from the side that knows.
        local lx = 0
        for ci, col in ipairs(layout.cols) do
          if ci < 5 then lx = lx + col[2] end
        end
        row.left.by, row.left.sell = nil, d.sell
        if not row.left:HasFocus() then
          local v = math.max(0, d.left or 0)
          row.left:SetText(string.format(
            (math.abs(v - math.floor(v + 0.5)) < 0.05) and "%.0f" or "%.1f", v))
        end
        row.left:ClearAllPoints()
        row.left:SetPoint("LEFT", row, "LEFT", lx, 0)
        row.left:SetWidth(math.max(36, layout.cols[5][2] - 6))
        row.left:Show()
        row.price:Hide()
        row.pack:Hide()
      else
        row.price:Hide()
        row.pack:Hide()
        row.left:Hide()
        row.left.sell = nil
      end
      if not noteShown then row.note:Hide() end
      row:Show()
    else
      row.tip, row.link = nil, nil
      row.markKey, row.person, row.who.person = nil, nil, nil
      row.canWhisper, row.who.canWhisper = nil, nil
      row.price:Hide() row.pack:Hide() row.kos:Hide() row.left:Hide()
      row.note:Hide() row.del:Hide() row.whisper:Hide() row.pick:Hide()
      row.mark:Hide() row.who:Hide()
      row:Hide()
    end
  end
end

local function SetMode(m)
  -- clicking the heading itself goes back to whichever of its tabs you were
  -- last on, because that is the one you were working in
  if SUBTABS[m] then
    m = ChainCharDB[m .. "Tab"] or SUBTABS[m][1][1]
  end
  mode = m
  if GROUP[m] then ChainCharDB[GROUP[m] .. "Tab"] = m end
  -- the label doubles as the answer to your last press; a fresh visit starts
  -- with the question rather than with last time's answer
  if m == "sell" and win and win.sellLabel then
    win.sellLabel:SetText(C.dim .. "your price" .. C.off)
  end
  -- a line you marked on another tab is not where you are now
  selected = nil
  page = 1
  sortKey, sortDesc = nil, false
  for key, b in pairs(tabs) do
    -- the kill-on-sight list lives under Enemies, so that tab stays lit, and
    -- the heading stays lit for whichever of its own tabs you are on
    b.active = (key == m) or (key == "enemies" and m == "koslist")
      or (key == GROUP[m])
    b.bg:SetColorTexture(b.active and 0.25 or 0.15, b.active and 0.25 or 0.15,
                         b.active and 0.35 or 0.15, 0.9)
  end
  if win and win.subtabs then
    local shown = GROUP[m] ~= nil
    for _, b in ipairs(win.subtabs) do
      b:SetShown(shown)
      b.active = (b.key == m)
      b.bg:SetColorTexture(b.active and 0.25 or 0.15, b.active and 0.25 or 0.15,
                           b.active and 0.35 or 0.15, 0.9)
    end
    -- the subtitle steps aside for them rather than being drawn underneath
    win.subtitle:ClearAllPoints()
    win.subtitle:SetPoint("TOPLEFT", shown and (10 + (win.subWidth or 0)) or 10,
                          -54)
    win.subtitle:SetWidth(640 - (shown and (win.subWidth or 0) or 0))
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
  if win.SetToplevel then win:SetToplevel(true) end
  win:Hide()

  -- the edge is just a slightly larger rectangle behind the background
  win.edge = Tex(win, "BACKGROUND", 0.3, 0.3, 0.35, 1)
  win.edge:SetPoint("TOPLEFT", -1, 1)
  win.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  -- solid, not nearly-solid: the settings panel is the same size and can sit
  -- on top of it, and a column of numbers reading faintly through another
  -- column of numbers is worse than either
  win.bg = Tex(win, "BACKGROUND", 0.05, 0.05, 0.06, 1)
  win.bg:SetAllPoints()
  win.bg:SetDrawLayer("BACKGROUND", 2)

  win.title = win:CreateFontString(nil, "OVERLAY", "ChainFontNormal")
  win.title:SetPoint("TOPLEFT", 10, -8)
  win.title:SetText(BT.NAME)

  local close = Hint(Button(win, "X", 22, 18, function() win:Hide() end),
    "close the window. Everything in it keeps running.", "close")
  close:SetPoint("TOPRIGHT", -6, -6)

  tabs = {}
  local tx = 10
  for _, def in ipairs({ { "runs", "History" }, { "boosting", "Boosting" },
                         { "groups", "Groups" },
                         { "gold", "Trade" }, { "loot", "Loot" },
                         { "enemies", "Enemies" },
                         { "pvp", "Rank" },
                         { "locks", "Instances" },
                         { "route", "Route" } }) do
    -- ten of them now, so they are measured rather than spaced by hand:
    -- one more tab used to push the last one off the right-hand edge
    local b = Hint(Button(win, def[2], 74, 20, function() SetMode(def[1]) end),
      TAB_HINT[def[1]] or "")
    b:SetPoint("TOPLEFT", tx, -28)
    tabs[def[1]] = b
    win.tabs = win.tabs or {}
    table.insert(win.tabs, b)
    tx = tx + 78
  end

  -- They live on the subtitle line rather than on a row of their own: a row
  -- of their own costs every other tab a line of height for something only
  -- three of them use.
  win.subtabs = {}
  do
    local sx = 10
    for _, def in ipairs(SUBTABS.boosting) do
      local b = Hint(Button(win, def[2], 62, 16, function() SetMode(def[1]) end),
        TAB_HINT[def[1]] or "")
      b:SetPoint("TOPLEFT", sx, -52)
      b.key = def[1]
      table.insert(win.subtabs, b)
      sx = sx + 65
    end
    win.subWidth = sx - 10
  end

  win.subtitle = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.subtitle:SetPoint("TOPLEFT", 10, -54)
  -- stops short of the search box, which now sits on this line: nine tabs
  -- fill the row above it, and the last of them was running underneath it
  win.subtitle:SetWidth(640)
  win.subtitle:SetJustifyH("LEFT")
  -- one line, always: wrapped to two it ran straight into the column headings
  if win.subtitle.SetWordWrap then win.subtitle:SetWordWrap(false) end
  if win.subtitle.SetMaxLines then win.subtitle:SetMaxLines(1) end

  win.searchLabel = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.searchLabel:SetPoint("TOPRIGHT", -190, -54)
  win.searchLabel:SetText("show only")

  win.search = CreateFrame("EditBox", nil, win)
  win.search:SetSize(150, 20)
  win.search:SetPoint("TOPRIGHT", -34, -50)
  win.search:SetAutoFocus(false)
  win.search:SetFontObject("ChainFontHighlightSmall")
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
  Hint(clear, "empty the search box", "clear")
  clear:SetPoint("TOPRIGHT", -8, -51)

  win.headerRow = CreateFrame("Frame", nil, win)
  win.headerRow:SetPoint("TOPLEFT", 12, -76)
  win.headerRow:SetSize(850, 16)
  win.headers = {}
  for i = 1, MAX_COLS do
    local h = CreateFrame("Button", nil, win.headerRow)
    h:SetHeight(16)
    h.fs = h:CreateFontString(nil, "OVERLAY", "ChainFontNormalSmall")
    h.fs:SetPoint("LEFT")
    h:EnableMouse(true)
    h:SetScript("OnEnter", function(self)
      if not self.hint then return end
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
      GameTooltip:AddLine(self.fs:GetText() or "", 1, 0.82, 0)
      GameTooltip:AddLine(self.hint, 0.9, 0.9, 0.9, true)
      if self.key then
        GameTooltip:AddLine("click to sort", 0.6, 0.6, 0.6)
      end
      GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    -- Clicking a line colours it. Sixteen rows of numbers all look alike
    -- while you are scrolling between them and counting, and on History the
    -- same mark is the one "say in party" reads.
    row.mark = Tex(row, "BACKGROUND", 0.25, 0.50, 0.85, 0.28)
    -- as wide as the columns actually in use: the row frame is cut to the
    -- widest tab, so a full-width band leaves a stub of colour hanging off
    -- the end of every narrower one
    row.mark:SetPoint("TOPLEFT")
    row.mark:SetPoint("BOTTOMLEFT")
    row.mark:SetWidth(1)
    row.mark:Hide()
    -- A row that can be hovered: the advert text is longer than any column,
    -- and a line you can only half read is a line you have to go and find in
    -- the chat window instead.
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      if not self.tip and not self.link then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
      -- An item gets the client's own tooltip - the stats, the level, the
      -- binding, everything a list of names cannot say. Ours goes underneath
      -- rather than instead: the rest of what the corpse gave, who took it and
      -- where, which is the part the item tooltip does not know.
      local shown = false
      if self.link and GameTooltip.SetHyperlink then
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        shown = ok
      end
      for i, line in ipairs(self.tip or {}) do
        if i == 1 and not shown then GameTooltip:AddLine(line, 1, 0.82, 0)
        else
          if i == 1 then GameTooltip:AddLine(" ") end
          GameTooltip:AddLine(line, 1, 1, 1, true)
        end
      end
      if self.link then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Shift-click to put it in chat", 0.4, 0.7, 1)
      end
      GameTooltip:Show()
    end)
    -- Not a bare Hide: the name column is a frame of its own sitting on top
    -- of this one, and moving onto it leaves the row. Whether that arrives
    -- before or after the name's own OnEnter is not ours to decide, so
    -- neither handler is allowed to hide a tooltip the other just put up.
    row:SetScript("OnLeave", function(self)
      if self.who and self.who:IsShown() and self.who:IsMouseOver() then return end
      GameTooltip:Hide()
    end)
    -- and shift-click drops the link into whatever you are typing, the way it
    -- works everywhere else in the game
    row:SetScript("OnMouseUp", function(self, button)
      if button ~= "LeftButton" then return end
      if self.link and IsModifiedClick and IsModifiedClick("CHATLINK")
         and ChatEdit_InsertLink then
        ChatEdit_InsertLink(self.link)
        return
      end
      -- The name is right there and the thing you nearly always want to do
      -- with it is talk to him. A button per row for that would be another
      -- column; a double-click is free.
      --
      -- Counted here rather than hung on OnDoubleClick: that handler is a
      -- Button's, and setting a script a frame does not have throws on the
      -- spot rather than politely doing nothing.
      local now = (GetTime and GetTime()) or 0
      if self.person and self.canWhisper and self.lastClick
         and (now - self.lastClick) <= 0.4 then
        self.lastClick = nil
        Whisper(self.person)
        return
      end
      self.lastClick = now
      if not self.markKey then return end
      selected = (selected ~= self.markKey) and self.markKey or nil
      Render()
    end)

    row.cells = {}
    for c = 1, MAX_COLS do
      local fs = row:CreateFontString(nil, "OVERLAY", "ChainFontHighlightSmall")
      fs:SetJustifyH("LEFT")
      -- one line per cell. "1h 42m ago" wrapped inside a narrow column and
      -- took the row's alignment with it; a cell that does not fit is clipped
      -- rather than allowed to grow downwards.
      if fs.SetWordWrap then fs:SetWordWrap(false) end
      if fs.SetMaxLines then fs:SetMaxLines(1) end
      fs:SetPoint("LEFT", row, "LEFT", 0, 0)
      row.cells[c] = fs
    end

    -- The name column, made hoverable on its own. The row tooltip says what
    -- the row is; this says who he is, and it says the same whether you found
    -- him in the tracker, in an LFM post or in the booster table.
    row.who = CreateFrame("Frame", nil, row)
    row.who:SetHeight(17)
    row.who:EnableMouse(true)
    row.who:SetScript("OnEnter", function(self)
      if not self.person then return end
      local card = BT.PersonCard
        and BT.PersonCard(self.person, self.canWhisper and true or false) or nil
      if not card or #card == 0 then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
      for i, line in ipairs(card) do
        if i == 1 then GameTooltip:AddLine(line, 1, 0.82, 0)
        else GameTooltip:AddLine(line, 1, 1, 1, true) end
      end
      GameTooltip:Show()
    end)
    row.who:SetScript("OnLeave", function()
      -- back onto the rest of the line: say what the line says, rather than
      -- leaving a hole until the cursor moves again
      if row:IsMouseOver() then
        local f = row:GetScript("OnEnter")
        if f then f(row) return end
      end
      GameTooltip:Hide()
    end)
    -- it sits on top of the row, so the row's own clicks have to come
    -- through it rather than stop at it
    row.who:SetScript("OnMouseUp", function(self, button)
      local f = row:GetScript("OnMouseUp")
      if f then f(row, button) end
    end)
    row.who:Hide()
    -- the boosters tab needs real controls, not just text
    row.price = CreateFrame("EditBox", nil, row)
    row.price:SetSize(52, 16)
    row.price:SetAutoFocus(false)
    row.price:SetFontObject("ChainFontHighlightSmall")
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
    row.pack:SetFontObject("ChainFontHighlightSmall")
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

    -- Runs left, typed straight into the column that shows it.
    --
    -- The figure is inferred: what you paid, divided by his price, less the
    -- runs recorded since. Every one of those can be wrong - a trade the
    -- client never announced, a run that did not get logged, a wipe he gave
    -- you back. When it is wrong you are the one who knows, and arguing with
    -- you about it would be the wrong way round. So type the number; the
    -- reckoning starts again from it and everything before stops counting.
    row.left = CreateFrame("EditBox", nil, row)
    row.left:SetSize(48, 16)
    row.left:SetAutoFocus(false)
    row.left:SetFontObject("ChainFontHighlightSmall")
    row.left:SetJustifyH("CENTER")
    row.left:SetMaxLetters(5)
    row.left.bg = Tex(row.left, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
    row.left.bg:SetAllPoints()
    row.left:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.left:SetScript("OnEscapePressed", function(self)
      self.typed = nil
      self:ClearFocus()
    end)
    row.left:SetScript("OnTextChanged", function(self, byUser)
      if byUser then self.typed = true end
    end)
    row.left:SetScript("OnEditFocusLost", function(self)
      -- only when you actually typed something: focus passing through a box
      -- must not rewrite a balance
      if self.sell and self.typed and BT.SetCustomerRuns then
        BT.SetCustomerRuns(self.sell, self:GetText())
      elseif self.by and self.typed and BT.SetRunsLeft then
        BT.SetRunsLeft(self.by, self:GetText())
      end
      self.typed = nil
      Render()
      if BT.Refresh then BT.Refresh() end
    end)
    row.left:Hide()
    row.pack:Hide()

    -- your own words about this man. Never sent anywhere: what travels
    -- between copies of the addon is measurements, not opinions.
    row.note = CreateFrame("EditBox", nil, row)
    row.note:SetSize(116, 16)
    row.note:SetAutoFocus(false)
    row.note:SetFontObject("ChainFontHighlightSmall")
    row.note:SetJustifyH("LEFT")
    row.note:SetMaxLetters(60)
    row.note.bg = Tex(row.note, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
    row.note.bg:SetAllPoints()
    row.note:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    row.note:SetScript("OnEditFocusLost", function(self)
      if self.by then BT.SetBoosterNote(self.by, self:GetText()) end
      -- the same box on the enemy tabs: a note, and nothing more. Marking is
      -- the KOS button's job.
      if self.kos then BT.SetEnemyNote(self.kos, self:GetText()) end
      if self.kosGuild then BT.SetGuildNote(self.kosGuild, self:GetText()) end
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
      -- on the kill-on-sight list this button only ever clears, and a guild
      -- row has no name to clear
      if self.clearGuild then
        BT.RemoveKOSGuild(self.clearGuild)
        Render()
        return
      end
      if self.markGuild then
        BT.AddKOSGuild(self.markGuild)
        Render()
        return
      end
      if not self.name then return end
      local why = BT.IsKOS(self.name, self.guild)
      if why == "named" then BT.RemoveKOS(self.name)
      elseif why == "guild" then BT.RemoveKOSGuild(self.guild)
      else BT.AddKOS(self.name) end
      Render()
    end)
    row.kos:Hide()

    -- Ticking a run. A booster who says "that is five" when it was four is
    -- not usually lying; he is counting in his head across three customers.
    -- The way that ends is one line in party chat with the times in it, and
    -- for that you have to be able to say which runs you mean.
    row.pick = Button(row, "+", 16, 14, function(self)
      if not self.rec then return end
      picked[self.rec] = (not picked[self.rec]) or nil
      Render()
    end)
    row.pick:SetPoint("LEFT", row, "LEFT", 810, 0)
    row.pick:Hide()

    row.del = Button(row, "x", 16, 14, function(self)
      -- what is about to go, named. "Are you sure?" is not a question you can
      -- answer without being told what you are being asked about.
      local trade, name, rec, own = self.trade, self.name, self.rec, self.own
      if self.customer then
        local who = self.customer
        Confirm("Take " .. who .. " off the list?\n\nWhat he paid and what "
          .. "he has had both go with him.", function()
            BT.RemoveCustomer(who)
            Render()
          end)
        return
      end
      if own then
        local step = ChainDB.ownSteps and ChainDB.ownSteps[own]
        Confirm("Take this out of the plan?\n\n"
          .. ((step and step.label) or "this stretch") .. "  "
          .. ((step and step.from) or "?") .. " > "
          .. ((step and step.to) or "?"), function()
            if ChainDB.ownSteps then table.remove(ChainDB.ownSteps, own) end
            BT.Touch()
            Render()
            if BT.Refresh then BT.Refresh() end
          end)
        return
      end
      if trade and trade.setTo then
        Confirm("Take back the balance you set?\n\n"
          .. BT.Runsish(trade.setTo) .. ", set "
          .. BT.T(time() - (trade.at or time())) .. " ago.\n\nEvery payment "
          .. "before it starts counting again.", function()
            BT.ForgetTrade(trade)
            Render()
            if BT.Refresh then BT.Refresh() end
          end)
        return
      end
      if trade then
        Confirm("Remove this trade?\n\n" .. (self.what or "")
          .. "\n\nWhat it bought stops counting with it.", function()
            BT.ForgetTrade(trade)
            Render()
          end)
        return
      end
      if name then
        Confirm("Remove " .. name .. " from the list?\n\nYour notes on him "
          .. "go too.", function()
            BT.ForgetBooster(name)
            Render()
          end)
        return
      end
      if not rec then return end
      Confirm("Throw this run out of the averages?\n\n" .. (self.what or "")
        .. "\n\nEvery figure worked out from it changes.", function()
          for idx, r in ipairs(ChainDB.runs) do
            if r == rec then
              table.remove(ChainDB.runs, idx)
              BT.Touch()
              break
            end
          end
          Render()
          if BT.Refresh then BT.Refresh() end
        end)
    end)
    row.del:SetPoint("LEFT", row, "LEFT", 832, 0)
    rows[i] = row
  end

  local addY = -94 - ROWS * 18 - 6

  -- Settling the count with the booster, on the History tab.
  --
  -- He says five, you counted four, and neither of you can prove it because
  -- both of you are counting in your head - him across three customers at
  -- once. The addon is not counting in its head. So it can put the times in
  -- party chat and the argument is over in one line.
  --
  -- "since the last trade" is the question actually being asked: what have I
  -- had that I have not paid for. It marks those; anything else you mark or
  -- unmark yourself.
  local function PickedRuns()
    local out = {}
    for _, r in ipairs(ChainDB.runs) do
      if picked[r] then table.insert(out, r) end
    end
    table.sort(out, function(a, b) return (a.at or 0) < (b.at or 0) end)
    return out
  end

  local function LastBooster()
    for i = #ChainDB.runs, 1, -1 do
      if ChainDB.runs[i].by then return ChainDB.runs[i].by end
    end
    return ChainCharDB.lastBy
  end

  win.sinceButton = Button(win, "mark since last trade", 150, 18, function()
    local who = LastBooster()
    if not who then return end
    local from = (BT.LastPaid and BT.LastPaid(who)) or 0
    -- his alts count as him: the money goes to a bank character often enough
    -- that the runs and the gold would otherwise be about two people
    local purse = (BT.PurseFor and BT.PurseFor(who)) or { [who] = true }
    wipe(picked)
    for _, r in ipairs(ChainDB.runs) do
      if r.by and purse[r.by] and (r.at or 0) > from then picked[r] = true end
    end
    Render()
  end)
  Hint(win.sinceButton, "mark every run you have had since you last paid "
    .. "him - his bank alts included. That is the list the argument is "
    .. "about.")
  win.sinceButton:SetPoint("TOPLEFT", 12, addY + 3)

  -- One line a run, numbered the way he counts them.
  --
  -- A single line of "12m, 47m, 1h 14m ago" is a list of times somebody has to
  -- match up against their own memory. A line each - when it started, when it
  -- ended, how long it took, how many things died, what it paid - is a
  -- receipt, and there is nothing left to disagree about.
  --
  -- Eight at most. Beyond that it is a wall of text in somebody else's chat
  -- window, and the game throttles a run of messages hard enough to get you
  -- disconnected - which is why they go out half a second apart rather than
  -- all in the same frame.
  local SAY_MAX = 8

  -- How much of a level a run gave, at the level you were when you took it.
  local function Pct(r)
    local p = BT.RunPct and BT.RunPct(r) or nil
    return p and string.format("%.0f%%", p) or nil
  end

  local function SayLines()
    local list = PickedRuns()                        -- oldest first
    local n = #list
    if n == 0 then return nil end
    local lines = {}
    for i = 1, math.min(n, SAY_MAX) do
      local r = list[i]
      local from = date("%H:%M", r.at or time())
      local to = date("%H:%M", (r.at or time()) + (r.t or 0))
      lines[#lines + 1] = i .. "/" .. n
        .. (r.by and (" with " .. r.by) or "")
        .. " - " .. from .. "-" .. to
        .. ", " .. BT.T(r.t or 0)
        .. ", " .. (r.k or 0) .. " mobs"
        .. ", " .. BT.N(r.xp or 0) .. " xp"
        -- and what that experience actually was. A number of xp means
        -- nothing without knowing what a level costs at that level, and the
        -- difference between 33,000 at 43 and 33,000 at 20 is the whole
        -- argument about whether the run was worth the gold.
        .. (Pct(r) and (", " .. Pct(r) .. " of a level") or "")
    end
    if n > SAY_MAX then
      lines[#lines + 1] = "(+" .. (n - SAY_MAX) .. " older, not listed)"
    end
    return lines, list
  end

  -- half a second apart whichever way they are going out
  local function Spread(lines, send)
    for i, text in ipairs(lines) do
      if i == 1 or type(C_Timer) ~= "table" or not C_Timer.After then
        send(text)
      else
        C_Timer.After((i - 1) * 0.5, function() send(text) end)
      end
    end
  end

  win.sayButton = Button(win, "say in party", 110, 18, function()
    local lines = SayLines()
    if not lines then return end
    Spread(lines, function(text)
      if BT.SayToGroup then BT.SayToGroup(text) end
    end)
  end)
  Hint(win.sayButton, "put the marked runs in party chat, one line each: when "
    .. "it started and ended, how long it took, the mobs and the experience. "
    .. "Eight at most, half a second apart so the game does not throttle you.")
  win.sayButton:SetPoint("TOPLEFT", 170, addY + 3)

  -- And to one person instead. A booster who has left the group is out of
  -- reach of party chat entirely, and correcting somebody in front of four
  -- other people is a different thing from correcting him.
  win.whisperTo = CreateFrame("EditBox", nil, win)
  win.whisperTo:SetSize(104, 18)
  win.whisperTo:SetAutoFocus(false)
  win.whisperTo:SetFontObject("ChainFontHighlightSmall")
  win.whisperTo:SetMaxLetters(24)
  win.whisperTo.bg = Tex(win.whisperTo, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
  win.whisperTo.bg:SetAllPoints()
  win.whisperTo:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  win.whisperTo:SetPoint("TOPLEFT", 290, addY + 3)

  win.whisperButton = Button(win, "whisper", 70, 18, function()
    local lines = SayLines()
    if not lines then return end
    local to = win.whisperTo:GetText()
    if not to or to == "" then return end
    Spread(lines, function(text)
      if BT.WhisperTo then BT.WhisperTo(to, text) end
    end)
  end)
  Hint(win.whisperButton, "send the same lines to one person instead of the "
    .. "group. The name starts out filled in with whoever the marked runs "
    .. "were with, accents and all - type over it for anyone else.")
  win.whisperButton:SetPoint("TOPLEFT", 398, addY + 3)
  win.whisperTo:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    win.whisperButton:GetScript("OnClick")(win.whisperButton)
  end)

  win.sayNote = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.sayNote:SetPoint("TOPLEFT", 474, addY)

  -- Adding somebody by hand, on the Boosters tab: a name you were given in a
  -- whisper is worth keeping before you have ever run with him, and the note
  -- is where "only sells mornings" or "does not pull the last room" goes.
  win.addLabel = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.addLabel:SetPoint("TOPLEFT", 12, addY)
  win.addLabel:SetText("add someone")

  local function AddBox(width, x, hint, maxLetters)
    local e = CreateFrame("EditBox", nil, win)
    e:SetSize(width, 18)
    e:SetPoint("TOPLEFT", x, addY + 3)
    e:SetAutoFocus(false)
    e:SetFontObject("ChainFontHighlightSmall")
    e:SetMaxLetters(maxLetters or 60)
    e.bg = Tex(e, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
    e.bg:SetAllPoints()
    e.hint = e:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
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
  win.addButton = Hint(Button(win, "Add", 60, 18, DoAdd),
    "put this person on the Boosters list before you have ever run with "
    .. "him - a name from a whisper is worth keeping.")
  win.addButton:SetPoint("TOPLEFT", 526, addY + 3)
  win.addNote2 = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.addNote2:SetPoint("TOPLEFT", 596, addY)

  -- The same line, for the Trade tab: money the addon never saw. A trade that
  -- went through during a reload, gold sent by mail, or - the common one - the
  -- arrangement you were already halfway through on the day you installed
  -- this. Two ways in, because they answer different questions: "I paid him
  -- 400g" is a payment, and "I have seven left" is the whole balance, which is
  -- the only one you can answer when you never counted the gold.
  win.payLabel = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.payLabel:SetPoint("TOPLEFT", 12, addY)
  win.payLabel:SetText("never saw it?")

  win.payName = AddBox(104, 100, "booster", 24)
  win.payGold = AddBox(54, 250, "gold", 8)

  local function Said(msg, bad)
    win.payLabel:SetText((bad and C.bad or C.good) .. msg .. C.off)
  end

  -- Pick the name instead of typing it. Half of them are Zånzå and Cartèr,
  -- and getting the accents right off a screenshot is not a task an addon
  -- should be setting anybody.
  win.payPick = Button(win, "pick", 40, 18, function(self)
    local list = BT.PayableNames and BT.PayableNames() or {}
    local items = {}
    for _, p in ipairs(list) do
      items[#items + 1] = {
        text = p.name .. C.dim .. "   " .. (p.why or "") .. C.off,
        fn = function()
          win.payName:SetText(p.name)
          win.payName.hint:Hide()
          Render()
        end }
    end
    if #items == 0 then
      items[1] = { text = C.dim .. "nobody to pick - type it" .. C.off,
                   fn = function() end }
    end
    if BT.ShowNearbyMenu then BT.ShowNearbyMenu("who did you pay?", items, self) end
  end)
  Hint(win.payPick, "pick the name out of your group, your last booster or "
    .. "whoever you traded lately - names with accents in them are not "
    .. "worth typing twice.")
  win.payPick:SetPoint("TOPLEFT", 206, addY + 3)
  local function ResetSaid()
    win.payLabel:SetText("never saw it?")
  end

  local function DoPay()
    local rec, why = BT.LogPayment(win.payName:GetText(), win.payGold:GetText())
    if not rec then Said(why or "no", true) return end
    win.payGold:SetText("")
    win.payGold:ClearFocus()
    ResetSaid()
    Render()
    -- You have just paid somebody who has never run anything for you. That is
    -- usually a bank alt, and the moment you pay it is the moment you know -
    -- so ask now rather than leaving his account looking unpaid and the alt's
    -- looking like a stranger who owes you twenty runs.
    local who, by = rec.with, BT.CurrentBooster and BT.CurrentBooster()
    if by and who ~= by and not BT.PaysFor(who)
       and #BT.Runs({ by = who, limit = 1 }) == 0 then
      if BT.ShowNearbyMenu then
        BT.ShowNearbyMenu(who .. " has never run for you", {
          { text = "It is " .. C.gold .. by .. C.off .. "'s alt"
                   .. C.dim .. "  - count it for him" .. C.off,
            fn = function() BT.SetPaysFor(who, by) Render() end },
          { text = C.dim .. "No, he is his own man" .. C.off,
            fn = function() end },
        }, win.payButton)
      end
    end
  end
  win.payName:SetScript("OnEnterPressed", DoPay)
  win.payGold:SetScript("OnEnterPressed", DoPay)
  win.payButton = Hint(Button(win, "I paid him", 78, 18, DoPay),
    "log gold the addon never saw - a trade to his bank alt, or one the "
    .. "client never announced. It counts exactly like a watched trade.")
  win.payButton:SetPoint("TOPLEFT", 310, addY + 3)

  win.payOr = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.payOr:SetPoint("TOPLEFT", 396, addY)
  win.payOr:SetText(C.dim .. "or just say what is left" .. C.off)

  win.payRuns = AddBox(46, 508, "runs", 6)

  local function DoRuns()
    local rec, why = BT.SetRunsLeft(win.payName:GetText(), win.payRuns:GetText())
    if not rec then Said(why or "no", true) return end
    win.payRuns:SetText("")
    win.payRuns:ClearFocus()
    ResetSaid()
    Render()
  end
  win.payRuns:SetScript("OnEnterPressed", DoRuns)
  win.payRunsButton = Hint(Button(win, "runs left", 68, 18, DoRuns),
    "say outright how many runs he still owes you. Everything before this "
    .. "stops counting and the tally starts again from your number.")
  win.payRunsButton:SetPoint("TOPLEFT", 560, addY + 3)

  win.payNote = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.payNote:SetPoint("TOPLEFT", 636, addY)
  win.payNote:SetText(C.dim .. "the tally starts again from there" .. C.off)

  -- A step of your own, on the Route tab.
  --
  -- Nobody buys every level. You buy to 42, quest to 45 because nothing sells
  -- that stretch at a price worth paying, then buy again - and a plan that
  -- only knows about dungeons puts you on the next instance for three levels
  -- you are actually soloing, with its runs, its gold and its summoning
  -- stone. A label and two levels is all it takes to say otherwise.
  win.ownLabel = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.ownLabel:SetPoint("TOPLEFT", 12, addY)
  win.ownLabel:SetText("a stretch of your own")

  -- the same boxes as everywhere else, which means each one says what it is
  -- for while it is empty. Three unlabelled boxes in a row is a puzzle.
  win.ownName = AddBox(150, 150, "what you will be doing", 24)
  win.ownFrom = AddBox(34, 346, "from", 2)
  win.ownTo = AddBox(34, 386, "to", 2)

  -- ...and you should not have to think of the words either. These are the
  -- stretches people actually do between bought ones.
  local OWN_KINDS = { "Questing", "Grinding", "Dungeons", "Battlegrounds",
                      "Professions", "A break" }
  win.ownPick = Button(win, "pick", 40, 18, function(self)
    local items = {}
    for _, k in ipairs(OWN_KINDS) do
      items[#items + 1] = { text = k, fn = function()
        win.ownName:SetText(k)
        win.ownName.hint:SetShown(false)
      end }
    end
    if BT.ShowNearbyMenu then
      BT.ShowNearbyMenu("what will you be doing?", items, self)
    end
  end)
  Hint(win.ownPick, "pick what the stretch is, or type your own words in the "
    .. "box - it is only a name, and it is yours")
  win.ownPick:SetPoint("TOPLEFT", 302, addY + 3)

  win.ownAdd = Button(win, "Add", 50, 18, function()
    local from = tonumber(win.ownFrom:GetText())
    local to = tonumber(win.ownTo:GetText())
    if not from or not to or to <= from then
      win.ownLabel:SetText(C.bad .. "from and to, and to has to be higher"
        .. C.off)
      return
    end
    ChainDB.ownSteps = ChainDB.ownSteps or {}
    table.insert(ChainDB.ownSteps, {
      label = (win.ownName:GetText() ~= "" and win.ownName:GetText())
        or "on your own",
      from = math.floor(from), to = math.floor(to), on = true })
    win.ownName:SetText("") win.ownFrom:SetText("") win.ownTo:SetText("")
    win.ownName:ClearFocus() win.ownFrom:ClearFocus() win.ownTo:ClearFocus()
    win.ownLabel:SetText("a stretch of your own")
    BT.Touch()
    Render()
    if BT.Refresh then BT.Refresh() end
  end)
  Hint(win.ownAdd, "put a stretch you do yourself into the plan - questing, "
    .. "a dungeon you run with friends, anything you are not paying for. It "
    .. "costs nothing and borrows no instance's numbers, and while you are on "
    .. "it the bar goes back to being a levelling bar.")
  win.ownAdd:SetPoint("TOPLEFT", 428, addY + 3)
  win.ownFrom:SetScript("OnEnterPressed", function()
    win.ownAdd:GetScript("OnClick")(win.ownAdd)
  end)
  win.ownTo:SetScript("OnEnterPressed", function()
    win.ownAdd:GetScript("OnClick")(win.ownAdd)
  end)
  win.ownNote = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.ownNote:SetPoint("TOPLEFT", 488, addY)
  win.ownNote:SetText(C.dim .. "no runs, no gold, no booster - just levels"
    .. C.off)

  -- Your side of the counter: what you charge, the line you would type in
  -- LookingForGroup, and the count out loud. Same line as everything else,
  -- because only one tab's controls are ever on screen.
  win.sellLabel = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.sellLabel:SetPoint("TOPLEFT", 12, addY)
  win.sellLabel:SetText("your price")

  win.sellGold = AddBox(46, 12, "gold", 7)
  win.sellGold:SetPoint("TOPLEFT", 12, addY + 3)
  win.sellPer = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.sellPer:SetPoint("TOPLEFT", 62, addY + 7)
  win.sellPer:SetText(C.dim .. "g for" .. C.off)
  win.sellPack = AddBox(28, 96, "5", 2)
  win.sellPack:SetPoint("TOPLEFT", 96, addY + 3)
  win.sellRuns = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.sellRuns:SetPoint("TOPLEFT", 128, addY + 7)
  win.sellRuns:SetText(C.dim .. "runs" .. C.off)

  local function SaveSellPrice()
    local step = BT.FocusStep()
    BT.SetSellPrice(step and step.id, win.sellGold:GetText(),
                    win.sellPack:GetText())
    Render()
  end
  win.sellGold:SetScript("OnEditFocusLost", SaveSellPrice)
  win.sellPack:SetScript("OnEditFocusLost", SaveSellPrice)
  win.sellGold:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  win.sellPack:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  -- The advert, kept per instance. Written by you, sent by you: one press,
  -- one line, and nothing on a timer.
  win.sellAd = AddBox(356, 168, "your advert - what you would type yourself")
  win.sellAd:SetPoint("TOPLEFT", 168, addY + 3)
  win.sellAd:SetMaxLetters(180)
  win.sellAd:SetScript("OnEditFocusLost", function(self)
    local step = BT.FocusStep()
    BT.SetSellAd(step and step.id, self:GetText())
  end)
  win.sellAd:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  win.sellPost = Button(win, "post to LookingForGroup", 168, 18, function()
    local ok, why = BT.PostAd(win.sellAd:GetText())
    win.sellLabel:SetText(ok and (C.good .. "posted" .. C.off)
      or (C.bad .. (why or "no") .. C.off))
    Render()
  end)
  Hint(win.sellPost, "put that line in the LookingForGroup channel, once. "
    .. "Nothing here posts on its own and nothing repeats: an addon that "
    .. "talks in a channel by itself is what gets everybody's addon thrown "
    .. "out of it. Press it again when you want it said again.")
  win.sellPost:SetPoint("TOPLEFT", 530, addY + 3)

  win.sellSay = Button(win, "say the count", 108, 18, function()
    if not BT.SaySellCount() then
      win.sellLabel:SetText(C.bad .. "nobody on the list is in your group"
        .. C.off)
    end
  end)
  Hint(win.sellSay, "put everybody's count into party or raid now - the same "
    .. "line that goes out on its own after each run. It is the thing that "
    .. "ends the argument before it starts.")
  win.sellSay:SetPoint("TOPLEFT", 706, addY + 3)

  -- The rank you are aiming at, on the same line and in the same place as the
  -- add-someone row, because only one of the two is ever on screen.
  win.enemyView = Button(win, "", 210, 18, function()
    SetMode(mode == "koslist" and "enemies" or "koslist")
  end)
  Hint(win.enemyView, "switch between everyone you have seen and only the "
    .. "ones you have marked")
  win.enemyView:SetPoint("TOPLEFT", 12, addY + 3)

  win.targetLabel = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.targetLabel:SetPoint("TOPLEFT", 12, addY)
  win.targetLabel:SetText("rank you want")

  win.targetBox = CreateFrame("EditBox", nil, win)
  win.targetBox:SetSize(40, 18)
  win.targetBox:SetPoint("TOPLEFT", 100, addY + 3)
  win.targetBox:SetAutoFocus(false)
  win.targetBox:SetFontObject("ChainFontHighlightSmall")
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
  win.targetDown = Hint(Button(win, "-", 20, 18, Step(-1)),
    "aim one rank lower")
  win.targetDown:SetPoint("TOPLEFT", 76, addY + 3)
  win.targetUp = Hint(Button(win, "+", 20, 18, Step(1)),
    "aim one rank higher")
  win.targetUp:SetPoint("TOPLEFT", 144, addY + 3)

  win.targetName = win:CreateFontString(nil, "OVERLAY", "ChainFontHighlightSmall")
  win.targetName:SetPoint("TOPLEFT", 174, addY)
  win.targetName:SetJustifyH("LEFT")

  win.summary = win:CreateFontString(nil, "OVERLAY", "ChainFontHighlightSmall")
  win.summary:SetPoint("BOTTOMLEFT", 12, 26)
  win.summary:SetJustifyH("LEFT")

  win.pageText = win:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  win.pageText:SetPoint("BOTTOMLEFT", 12, 10)

  local prev = Button(win, "< prev", 60, 18, function()
    if page > 1 then page = page - 1 Render() end
  end)
  Hint(prev, "the page before this one")
  prev:SetPoint("BOTTOMRIGHT", -76, 8)
  local nxt = Button(win, "next >", 60, 18, function()
    page = page + 1 Render()
  end)
  Hint(nxt, "the next page of this list")
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

-- Which tab is up. Only the tests and the list's own button ask, but a thing
-- that can be set and not read is a thing you cannot check.
function BT.WindowMode() return mode end
