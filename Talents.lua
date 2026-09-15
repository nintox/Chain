-- Chain: talent builds, saved and put back.
--
-- Resetting talents costs gold and forty clicks. The gold is the point; the
-- forty clicks are not, and the fortieth one is where you notice you put two
-- points in the wrong row at level 12 and have to start again.
--
-- So: the build you are standing in can be written down, and a written-down
-- build can be spent again in one press. Nothing here plans a build for you -
-- Blizzard's own tree does that better than a copy of it would, and it is
-- already open when you need it. This sits beside it and remembers.
--
-- It is all the client's own numbers. A talent is a tab and an index, and
-- GetTalentInfo gives its row, its column and how many points are in it, so
-- there is no table of every class's talents to keep right through a patch.

local ADDON, BT = ...
local C = BT.COL

-- Declared up here rather than beside the code that builds it: everything
-- below closes over this name, and a local declared later is a different
-- variable to anything written above it - which is a quiet nil rather than an
-- error, and the message that was meant to stay on screen simply never was.
local panel

-- The three returns we use, at the indexes the Classic client puts them:
-- name, icon, row, column, rank, maxRank.
local function Talent(tab, index)
  if type(GetTalentInfo) ~= "function" then return nil end
  local name, _, tier, column, rank, maxRank = GetTalentInfo(tab, index)
  if not name then return nil end
  return { name = name, tier = tier or 1, column = column or 1,
           rank = rank or 0, max = maxRank or 0 }
end

local function Tabs()
  if type(GetNumTalentTabs) ~= "function" then return 0 end
  return GetNumTalentTabs() or 0
end

local function Count(tab)
  if type(GetNumTalents) ~= "function" then return 0 end
  return GetNumTalents(tab) or 0
end

-- The tree's own name, defensively: the client has changed what order this
-- function returns things in, and a texture path in a heading looks like a
-- bug in us.
function BT.TreeName(tab)
  if type(GetTalentTabInfo) ~= "function" then return "tree " .. tab end
  local a, b = GetTalentTabInfo(tab)
  for _, v in ipairs({ a, b }) do
    if type(v) == "string" and v ~= "" and not v:find("\\") then return v end
  end
  return "tree " .. tab
end

--------------------------------------------------------------------------
-- What you are standing in
--------------------------------------------------------------------------
function BT.ReadSpec()
  local out, spent = {}, 0
  for tab = 1, Tabs() do
    local ranks, n = {}, 0
    for index = 1, Count(tab) do
      local t = Talent(tab, index)
      local r = t and t.rank or 0
      ranks[index] = r
      n = n + r
    end
    out[tab] = ranks
    spent = spent + n
  end
  return out, spent
end

-- "31/20/0" - the way everybody says a build out loud.
function BT.SpecLine(ranks)
  local bits = {}
  for tab = 1, math.max(Tabs(), #(ranks or {})) do
    local n = 0
    for _, r in ipairs((ranks or {})[tab] or {}) do n = n + r end
    bits[#bits + 1] = tostring(n)
  end
  if #bits == 0 then return "0" end
  return table.concat(bits, "/")
end

function BT.SpecPoints(ranks)
  local n = 0
  for _, tree in pairs(ranks or {}) do
    for _, r in ipairs(tree) do n = n + r end
  end
  return n
end

--------------------------------------------------------------------------
-- The ones you have written down
--------------------------------------------------------------------------
-- Kept per class rather than per character: the mage build you worked out on
-- one mage is the build you want on the next one, and a build is meaningless
-- to a class that cannot learn it. Applying checks the class anyway.
local function MyClass()
  local _, class = UnitClass("player")
  return class or "UNKNOWN"
end

function BT.Builds(class)
  ChainDB.builds = ChainDB.builds or {}
  class = class or MyClass()
  ChainDB.builds[class] = ChainDB.builds[class] or {}
  return ChainDB.builds[class], class
end

-- A picture of the build, taken when it is written down.
--
-- Not a screenshot: an addon cannot take one it can look at afterwards. But
-- everything a picture of a talent tree is made of is right here when you
-- save - the icon, which row, which column, how many points - so the picture
-- can be kept as the handful of numbers it is and drawn again later. It
-- survives the client renumbering its own talents, and it survives being
-- looked at on a character of another class.
function BT.SnapRanks(ranks)
  local pic = {}
  for tab = 1, Tabs() do
    local list = { name = BT.TreeName(tab), n = 0 }
    for index = 1, Count(tab) do
      local name, icon, tier, column, rank, max = GetTalentInfo(tab, index)
      local n = ranks and (((ranks[tab] or {})[index]) or 0) or (rank or 0)
      if name and n > 0 then
        list[#list + 1] = { i = index, r = n, t = tier, c = column,
                            k = icon, m = max, name = name }
        list.n = list.n + n
      end
    end
    pic[tab] = list
  end
  return pic
end

function BT.SnapSpec() return BT.SnapRanks(nil) end

function BT.SaveBuild(name)
  local ranks, spent = BT.ReadSpec()
  if spent <= 0 then return nil, "nothing spent yet" end
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then name = BT.SpecLine(ranks) end
  local list = BT.Builds()
  -- the same name twice is a build you cannot tell apart in a list, so it
  -- replaces rather than joining it
  for i, b in ipairs(list) do
    if b.name:lower() == name:lower() then
      list[i] = { name = name, ranks = ranks, at = time(), pic = BT.SnapSpec(),
                  lvl = UnitLevel("player"), points = spent }
      if BT.RenderTalents then BT.RenderTalents() end
      return list[i], nil, true
    end
  end
  local b = { name = name, ranks = ranks, at = time(), pic = BT.SnapSpec(),
              lvl = UnitLevel("player"), points = spent }
  table.insert(list, b)
  if BT.RenderTalents then BT.RenderTalents() end
  return b
end

function BT.DeleteBuild(b)
  local list = BT.Builds()
  for i, x in ipairs(list) do
    if x == b or x.name == b then
      table.remove(list, i)
      if BT.RenderTalents then BT.RenderTalents() end
      return true
    end
  end
  return false
end

function BT.FindBuild(name)
  if not name or name == "" then return nil end
  local list = BT.Builds()
  for _, b in ipairs(list) do
    if b.name:lower() == name:lower() then return b end
  end
  -- and the start of a name, so a macro does not need the whole thing
  for _, b in ipairs(list) do
    if b.name:lower():find(name:lower(), 1, true) == 1 then return b end
  end
  return nil
end

--------------------------------------------------------------------------
-- Whether a build is a build at all
--------------------------------------------------------------------------
-- Two rules, and between them they decide everything: a talent in row N needs
-- five points per row above it already in that tree, and a talent with an
-- arrow into it needs the one it points from at full rank.
--
-- Rather than check them by argument, this lays the build out the way it
-- would actually be spent: take any point that is legal right now, put it
-- down, and go again. A build that can be laid out completely is a build the
-- game will take; one that gets stuck with points left over could never have
-- been learned, however it was typed in. The same walk is what puts the
-- points in for real, so a plan that passes here cannot fail there.
local function PrereqOf(tab, index)
  if type(GetTalentPrereqs) ~= "function" then return nil end
  -- the client has answered this two different ways: a table of requirements,
  -- and three plain values. Both shapes say the same thing.
  local a, b = GetTalentPrereqs(tab, index)
  if type(a) == "table" then
    local r = a[1]
    if not r then return nil end
    return r.tier or r.row, r.column
  end
  if type(a) == "number" then return a, b end
  return nil
end

-- which index in this tree sits at that row and column
local function AtCell(tab, tier, column)
  for index = 1, Count(tab) do
    local t = Talent(tab, index)
    if t and t.tier == tier and t.column == column then return index, t end
  end
  return nil
end

function BT.Legal(ranks)
  local placed, spentIn = {}, {}
  local want, total = 0, 0
  for tab = 1, Tabs() do
    placed[tab], spentIn[tab] = {}, 0
    for index = 1, Count(tab) do
      local n = ((ranks or {})[tab] or {})[index] or 0
      local t = Talent(tab, index)
      if n > 0 then
        if not t or n > t.max then return false, 0 end
        want = want + n
      end
      placed[tab][index] = 0
    end
  end
  local moved = true
  while total < want and moved do
    moved = false
    for tab = 1, Tabs() do
      for index = 1, Count(tab) do
        local n = ((ranks or {})[tab] or {})[index] or 0
        if placed[tab][index] < n then
          local t = Talent(tab, index)
          local okTier = spentIn[tab] >= ((t.tier or 1) - 1) * 5
          local okPre = true
          local ptier, pcol = PrereqOf(tab, index)
          if ptier then
            local pi, pt = AtCell(tab, ptier, pcol)
            okPre = pi and pt and (placed[tab][pi] >= pt.max) or false
          end
          if okTier and okPre then
            placed[tab][index] = placed[tab][index] + 1
            spentIn[tab] = spentIn[tab] + 1
            total = total + 1
            moved = true
          end
        end
      end
    end
  end
  return total == want, total
end

--------------------------------------------------------------------------
-- Spending it again
--------------------------------------------------------------------------
-- The order matters and it is not the order the list is in.
--
-- A talent in row 4 needs fifteen points already in that tree, and a talent
-- with an arrow into it needs the one it points from at full rank. Both are
-- satisfied by going tree by tree, row by row, and finishing each talent
-- before moving to the next: everything a talent depends on sits above it.
local function Order(ranks)
  local out = {}
  for tab = 1, Tabs() do
    for index = 1, Count(tab) do
      local t = Talent(tab, index)
      local want = ((ranks or {})[tab] or {})[index] or 0
      if t and want > 0 then
        out[#out + 1] = { tab = tab, index = index, tier = t.tier,
                          column = t.column, want = math.min(want, t.max),
                          name = t.name }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.tab ~= b.tab then return a.tab < b.tab end
    if a.tier ~= b.tier then return a.tier < b.tier end
    return a.column < b.column
  end)
  return out
end

-- Points you have that this build does not want. Nothing can take those back
-- but the trainer and the gold, so a build cannot be "put in" on top of the
-- wrong one - it can only be added to. Saying that before you press is the
-- difference between a button that did nothing and a button that told you to
-- go and reset first.
function BT.BuildExtra(b)
  if not b then return 0 end
  local extra = 0
  for tab = 1, Tabs() do
    for index = 1, Count(tab) do
      local t = Talent(tab, index)
      local want = ((b.ranks or {})[tab] or {})[index] or 0
      if t and t.rank > want then extra = extra + (t.rank - want) end
    end
  end
  return extra
end

-- What is left to do, so the panel can say it before you press anything
function BT.BuildGap(b)
  if not b then return 0 end
  local need = 0
  for _, step in ipairs(Order(b.ranks)) do
    local t = Talent(step.tab, step.index)
    if t and t.rank < step.want then need = need + (step.want - t.rank) end
  end
  return need
end

-- The run of presses, one talent point at a time.
--
-- One at a time because the client does not answer for it immediately: learn
-- a point and GetTalentInfo still says the old rank. The change arrives as
-- CHARACTER_POINTS_CHANGED, so that event is what asks for the next point.
-- Reading it back in a loop instead gives you a loop that spends nothing and
-- never ends.
local job = nil

local function Stop(msg, bad)
  job = nil
  if msg then
    print(C.info .. BT.NAME .. ":|r " .. (bad and (C.bad .. msg .. "|r") or msg))
  end
  if BT.RenderTalents then BT.RenderTalents() end
end

function BT.ApplyStatus()
  if not job then return nil end
  return job.done, job.total, job.name
end

-- One point, and only one. Returns true while there is still work to do.
function BT.ApplyNext()
  if not job then return false end
  if type(LearnTalent) ~= "function" then Stop("this client has no talents") return false end
  local left = UnitCharacterPoints and UnitCharacterPoints("player") or 0
  for _, step in ipairs(job.steps) do
    local t = Talent(step.tab, step.index)
    if t and t.rank < step.want then
      if left <= 0 then
        Stop("put in " .. job.done .. " of " .. job.total
          .. " - that is every point you have. Come back at the next level.")
        return false
      end
      -- the same talent twice in a row without the rank moving means the
      -- client refused it, and pressing it a third time will not help
      if job.last == step and job.lastRank == t.rank then
        job.stuck = (job.stuck or 0) + 1
        if job.stuck >= 2 then
          Stop("stopped at " .. (step.name or "?")
            .. " - the game would not take the point. The build may not fit "
            .. "this class or this level.", true)
          return false
        end
      else
        job.stuck = 0
      end
      job.last, job.lastRank = step, t.rank
      LearnTalent(step.tab, step.index)
      return true
    end
  end
  Stop("build \"" .. (job.name or "?") .. "\" is in - " .. job.done
    .. " point" .. ((job.done == 1) and "" or "s") .. " spent")
  return false
end

function BT.ApplyBuild(b)
  if type(b) == "string" then b = BT.FindBuild(b) end
  if not b then return nil, "no such build" end
  local list, class = BT.Builds()
  if b.class and b.class ~= class then return nil, "that is not your class" end
  local extra = BT.BuildExtra(b)
  if extra > 0 then
    return nil, "you have " .. extra .. " point" .. ((extra == 1) and "" or "s")
      .. " in places this build does not use - reset at a trainer first, "
      .. "then press it again"
  end
  local total = BT.BuildGap(b)
  if total <= 0 then return nil, "you already have that build" end
  if panel then panel.msg, panel.msgBuild = nil, nil end
  job = { steps = Order(b.ranks), total = total, done = 0, name = b.name }
  BT.ApplyNext()
  return true
end

function BT.CancelApply()
  if job then Stop("stopped - " .. job.done .. " of " .. job.total .. " put in") end
end

-- The client has finished with the last point: count it and ask for the next.
local function PointsChanged()
  if not job then
    if BT.RenderTalents then BT.RenderTalents() end
    return
  end
  job.done = job.done + 1
  BT.ApplyNext()
end

--------------------------------------------------------------------------
-- Saying why not
--------------------------------------------------------------------------
-- A button that quietly does nothing is worse than the walk to the trainer.
-- The commonest reason a build will not go in is the one nothing on screen
-- can fix: the points are already spent somewhere else, and talents go in and
-- never out. So it says so in the game's own dialog, and the panel keeps
-- saying it after you have clicked the dialog away.
if type(StaticPopupDialogs) == "table" then
  StaticPopupDialogs["CHAIN_TALENT_INFO"] = {
    text = "%s",
    button1 = _G.OKAY or "Okay",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3
  }
end

function BT.TalentSay(msg, about, short)
  if not msg then return false end
  BT.lastTalentSay = msg
  if panel then
    panel.msg, panel.msgBuild = short or msg, about
    BT.RenderTalents()
  end
  if type(StaticPopup_Show) == "function" then
    StaticPopup_Show("CHAIN_TALENT_INFO", msg)
    return true
  end
  print(C.info .. BT.NAME .. ":|r " .. msg)
  return true
end

-- What to put in the box, in whole sentences, because this one is read once
-- and acted on rather than glanced at.
function BT.WhyNot(b)
  if not b then return "that build is gone" end
  local _, class = BT.Builds()
  if b.class and b.class ~= class then
    return b.name .. " is a " .. b.class:lower() .. " build. It cannot be put "
      .. "on this character."
  end
  local extra = BT.BuildExtra(b)
  if extra > 0 then
    return "You are standing in a different build.\n\n"
      .. extra .. " point" .. ((extra == 1) and " is" or "s are")
      .. " spent where " .. b.name .. " does not want "
      .. ((extra == 1) and "it" or "them") .. ", and talents only ever go in "
      .. "- nothing but a class trainer can take them out again.\n\n"
      .. "Unlearn your talents at a trainer, then press it again and the "
      .. "whole build goes in by itself."
  end
  if BT.BuildGap(b) <= 0 then
    return "You are already standing in " .. b.name .. "."
  end
  return nil
end

-- The same thing in a few words, for the line at the bottom of the panel. The
-- box has room for the whole story; that line has one line, and four lines of
-- it went out through the bottom of the frame.
function BT.WhyNotShort(b)
  if not b then return nil end
  local _, class = BT.Builds()
  if b.class and b.class ~= class then return "not a " .. class:lower() .. " build" end
  local extra = BT.BuildExtra(b)
  if extra > 0 then
    return extra .. " point" .. ((extra == 1) and "" or "s")
      .. " in the way - unlearn at a trainer first"
  end
  if BT.BuildGap(b) <= 0 then return "you are in " .. b.name .. " already" end
  return nil
end

--------------------------------------------------------------------------
-- The panel, on Blizzard's own talent window
--------------------------------------------------------------------------
-- Where you already are when you need it. Nothing is copied from the talent
-- tree and nothing replaces it: you spec the way you always did, and this
-- keeps what you ended up with.
function BT.TalentPanelOn()
  return ChainDB.talentPanel ~= false
end

function BT.SetTalentPanel(v)
  if v == nil then v = not BT.TalentPanelOn() end
  -- and not "v and nil or false", which is false either way: the middle of
  -- an and/or chain cannot be nil, and this is the switch that turns the
  -- whole thing on
  if v then ChainDB.talentPanel = nil else ChainDB.talentPanel = false end
  if panel then
    panel:SetShown((v and panel.owner and panel.owner:IsShown()) and true or false)
  end
  return BT.TalentPanelOn()
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
    self.bg:SetColorTexture(0.32, 0.32, 0.40, 0.95)
    if not self.hint then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine(self.hintTitle or self.fs:GetText() or "", 1, 0.82, 0)
    GameTooltip:AddLine(self.hint, 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    GameTooltip:Hide()
  end)
  b:SetScript("OnClick", onClick)
  return b
end

--------------------------------------------------------------------------
-- The picture
--------------------------------------------------------------------------
-- Three trees side by side with the icons where they sit in them, which is
-- how everybody actually recognises a build: not "31/20/0" but the shape of
-- where the points are. Drawn from what was saved with it, so it looks the
-- same on a character that cannot learn a single talent in it.
-- Two sizes, because they are two different jobs. The picture on hover is
-- something you glance at beside a list, and the planner is a thing you work
-- in for a few minutes - and Blizzard's own talent icons are 37 pixels, which
-- is the size a talent icon is supposed to be. Everything here is measured off
-- these two numbers rather than written out again anywhere.
local ICON, GAP, COLS = 24, 5, 4
local PITCH = ICON + GAP
local TREE_W = COLS * PITCH + 12

local PICON, PGAP = 34, 8
local PPITCH = PICON + PGAP
local PTREE_W = COLS * PPITCH + 16

local preview

local function MakePreview()
  if preview then return preview end
  preview = CreateFrame("Frame", "ChainBuildPreview", UIParent)
  preview:SetFrameStrata("TOOLTIP")
  preview:SetSize(3 * TREE_W + 20, 260)
  preview.edge = Tex(preview, "BACKGROUND", 0.3, 0.3, 0.35, 1)
  preview.edge:SetPoint("TOPLEFT", -1, 1)
  preview.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  preview.bg = Tex(preview, "BACKGROUND", 0.04, 0.04, 0.05, 1)
  preview.bg:SetAllPoints()
  preview.bg:SetDrawLayer("BACKGROUND", 2)
  preview.title = preview:CreateFontString(nil, "OVERLAY", "ChainFontNormal")
  preview.title:SetPoint("TOPLEFT", 10, -8)
  preview.heads, preview.slots = {}, {}
  for tab = 1, 3 do
    local h = preview:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
    h:SetPoint("TOPLEFT", 10 + (tab - 1) * TREE_W, -28)
    h:SetWidth(TREE_W - 4)
    h:SetJustifyH("LEFT")
    preview.heads[tab] = h
  end
  preview:Hide()
  BT.buildPreview = preview
  return preview
end

-- One icon, made when it is first needed and kept for the next build
local function Slot(i)
  local p = MakePreview()
  if p.slots[i] then return p.slots[i] end
  local f = CreateFrame("Frame", nil, p)
  f:SetSize(ICON, ICON)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetAllPoints()
  f.edge = Tex(f, "BACKGROUND", 0.5, 0.42, 0.15, 1)
  f.edge:SetPoint("TOPLEFT", -1, 1)
  f.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  f.rank = f:CreateFontString(nil, "OVERLAY", "ChainFontNormal")
  f.rank:SetPoint("BOTTOMRIGHT", 3, -2)
  p.slots[i] = f
  return f
end

-- The build as it was saved; failing that, as it is in the game right now,
-- which is what an older build written down before there were pictures has.
local function Picture(b)
  if b and b.pic then return b.pic end
  if not b then return nil end
  local pic = {}
  for tab = 1, Tabs() do
    local list = { name = BT.TreeName(tab), n = 0 }
    for index = 1, Count(tab) do
      local want = ((b.ranks or {})[tab] or {})[index] or 0
      if want > 0 then
        local name, icon, tier, column, _, max = GetTalentInfo(tab, index)
        list[#list + 1] = { i = index, r = want, t = tier or 1, c = column or 1,
                            k = icon, m = max, name = name }
        list.n = list.n + want
      end
    end
    pic[tab] = list
  end
  return pic
end

function BT.ShowBuildPreview(b, anchor)
  local pic = Picture(b)
  if not pic then return nil end
  local p = MakePreview()
  p.title:SetText(b.name .. C.dim .. "   " .. BT.SpecLine(b.ranks)
    .. ((b.lvl and b.lvl > 0) and ("   saved at " .. b.lvl) or "") .. C.off)
  local used, bottom = 0, 0
  for tab = 1, 3 do
    local tree = pic[tab] or {}
    p.heads[tab]:SetText((tree.name or ("tree " .. tab))
      .. C.dim .. "  " .. (tree.n or 0) .. C.off)
    for _, t in ipairs(tree) do
      used = used + 1
      local f = Slot(used)
      f:ClearAllPoints()
      local x = 10 + (tab - 1) * TREE_W + ((t.c or 1) - 1) * PITCH
      local y = -46 - ((t.t or 1) - 1) * PITCH
      f:SetPoint("TOPLEFT", x, y)
      f.tex:SetTexture(t.k or "Interface\\Icons\\INV_Misc_QuestionMark")
      -- full rank is worth seeing at a glance: it is what an arrow below it
      -- waits for
      local full = (t.m or 0) > 0 and (t.r or 0) >= t.m
      f.edge:SetColorTexture(full and 1 or 0.5, full and 0.82 or 0.42,
                             full and 0 or 0.15, 1)
      f.rank:SetText(((t.m or 1) > 1) and (C.gold .. (t.r or 0) .. C.off) or "")
      f:Show()
      if -y > bottom then bottom = -y end
    end
  end
  for i = used + 1, #p.slots do p.slots[i]:Hide() end
  p:SetHeight(bottom + ICON + 12)
  p:ClearAllPoints()
  if anchor then
    p:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 8)
  else
    p:SetPoint("CENTER")
  end
  p:Show()
  return p
end

function BT.HideBuildPreview()
  if preview then preview:Hide() end
end

--------------------------------------------------------------------------
-- Making one up
--------------------------------------------------------------------------
-- The same three trees, but you click them. It is the picture with the whole
-- tree in it rather than only the points, and a talent goes in when the rules
-- would have let it: no walking to a trainer to find out that the build you
-- typed out on a napkin cannot exist.
--
-- The rules are not written out again here. A click makes the change it would
-- make and then asks whether the result is a build that could be spent - and
-- the thing that answers is the same walk that spends it for real, so a plan
-- that is allowed here cannot be refused there.
local plan

function BT.PlanPoints(ranks)
  return BT.SpecPoints(ranks or (plan and plan.ranks))
end

-- What a character of this level has to spend. Ten to thirty-nine gives you
-- one a level; nothing before ten.
function BT.PointsAt(level)
  return math.max(0, (level or UnitLevel("player") or 1) - 9)
end

function BT.PlanSet(tab, index, want)
  if not plan then return false end
  local t = Talent(tab, index)
  if not t then return false end
  want = math.max(0, math.min(want, t.max))
  plan.ranks[tab] = plan.ranks[tab] or {}
  local was = plan.ranks[tab][index] or 0
  if was == want then return false end
  plan.ranks[tab][index] = want
  -- a point that cannot be reached, or one taken out from under something
  -- that needs it, puts the whole thing back the way it was
  local okNow = BT.Legal(plan.ranks)
  if not okNow or BT.SpecPoints(plan.ranks) > (plan.cap or 51) then
    plan.ranks[tab][index] = was
    return false
  end
  if BT.RenderPlan then BT.RenderPlan() end
  return true
end

function BT.PlanRanks() return plan and plan.ranks or nil end

function BT.PlanOpen(seed, name)
  local ranks = {}
  for tab = 1, Tabs() do
    ranks[tab] = {}
    for index = 1, Count(tab) do
      ranks[tab][index] = ((seed or {})[tab] or {})[index] or 0
    end
  end
  plan = { ranks = ranks, cap = 51, name = name or "",
           editing = (name and name ~= "") and name or nil }
  if BT.RenderPlan then BT.RenderPlan(true) end
  return plan
end

function BT.PlanClose()
  plan = nil
  if BT.planner then BT.planner:Hide() end
  if BT.RenderTalents then BT.RenderTalents() end
end

function BT.PlanSave()
  if not plan then return nil, "nothing being planned" end
  local n = BT.SpecPoints(plan.ranks)
  if n <= 0 then return nil, "no points in it" end
  local name = tostring(plan.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then name = BT.SpecLine(plan.ranks) end
  local list = BT.Builds()
  local b = { name = name, ranks = plan.ranks, at = time(),
              pic = BT.SnapRanks(plan.ranks), points = n,
              lvl = BT.PointsAt(UnitLevel("player")) >= n
                    and UnitLevel("player") or (n + 9), planned = true }
  for i, x in ipairs(list) do
    if x.name:lower() == name:lower() then list[i] = b return b end
  end
  table.insert(list, b)
  return b
end

local ROWS = 8

local function BuildPanel(owner)
  panel = CreateFrame("Frame", "ChainTalents", owner)
  panel.owner = owner
  panel:SetSize(308, 46 + ROWS * 24 + 62)
  panel:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, -12)
  panel:SetFrameStrata(owner:GetFrameStrata() or "HIGH")
  panel.edge = Tex(panel, "BACKGROUND", 0.3, 0.3, 0.35, 1)
  panel.edge:SetPoint("TOPLEFT", -1, 1)
  panel.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  panel.bg = Tex(panel, "BACKGROUND", 0.05, 0.05, 0.06, 1)
  panel.bg:SetAllPoints()
  panel.bg:SetDrawLayer("BACKGROUND", 2)

  panel.title = panel:CreateFontString(nil, "OVERLAY", "ChainFontNormalLarge")
  panel.title:SetPoint("TOPLEFT", 12, -8)
  panel.title:SetText(BT.NAME .. " builds")

  -- a fontstring cannot be hovered, so the line has a frame behind it that
  -- can. Two lines of numbers with no words on them is the thing people ask
  -- about first.
  panel.noteHit = CreateFrame("Frame", nil, panel)
  panel.noteHit:SetPoint("TOPLEFT", 10, -28)
  panel.noteHit:SetSize(284, 18)
  panel.noteHit:EnableMouse(true)
  panel.noteHit:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine("where you are", 1, 0.82, 0)
    GameTooltip:AddLine("The points you have already spent, tree by tree, and "
      .. "how many are still in your pocket. A build is put in on top of what "
      .. "is already there - talents only ever go in - so these two numbers "
      .. "decide what any of the buttons below can do.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  panel.noteHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

  panel.note = panel:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  panel.note:SetPoint("TOPLEFT", 12, -30)
  panel.note:SetWidth(284)
  panel.note:SetJustifyH("LEFT")

  panel.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(284, 22)
    row:SetPoint("TOPLEFT", 12, -50 - (i - 1) * 24)
    -- the whole row is the hover target, not just the name: you are pointing
    -- at a build, not at a word
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      if self.build then BT.ShowBuildPreview(self.build, panel) end
    end)
    row:SetScript("OnLeave", function() BT.HideBuildPreview() end)
    row.name = row:CreateFontString(nil, "OVERLAY", "ChainFontNormal")
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetWidth(110)
    row.name:SetJustifyH("LEFT")
    row.spec = row:CreateFontString(nil, "OVERLAY", "ChainFontHighlightSmall")
    row.spec:SetPoint("LEFT", 114, 0)
    row.use = Button(row, "use", 44, 20, function(self)
      if not self.build then return end
      local ok = BT.ApplyBuild(self.build)
      if not ok then
        -- the whole story in the box, the short of it on the panel
        BT.TalentSay(BT.WhyNot(self.build), self.build,
                     BT.WhyNotShort(self.build))
      end
    end)
    row.use:SetPoint("LEFT", 216, 0)
    -- A build is a first draft more often than not: the one you wrote down at
    -- 40 is the one you want with three points moved at 47. Editing it is the
    -- planner again, opened on what is already there - and saving under the
    -- same name replaces it, which is what editing means.
    row.edit = Button(row, "edit", 44, 20, function(self)
      if not self.build then return end
      BT.PlanOpen(self.build.ranks, self.build.name)
    end)
    row.edit.hint = "open this build in the planner. Save it under the same "
      .. "name and it takes the place of this one; change the name and you "
      .. "have two."
    row.edit:SetPoint("LEFT", 168, 0)

    row.del = Button(row, "x", 20, 20, function(self)
      if self.build then BT.DeleteBuild(self.build) end
    end)
    row.del:SetPoint("LEFT", 264, 0)
    panel.rows[i] = row
  end

  local y = -50 - ROWS * 24 - 6
  panel.box = CreateFrame("EditBox", nil, panel)
  panel.box:SetSize(112, 20)
  panel.box:SetPoint("TOPLEFT", 10, y)
  panel.box:SetAutoFocus(false)
  panel.box:SetFontObject("ChainFontHighlightSmall")
  panel.box:SetMaxLetters(24)
  panel.box.bg = Tex(panel.box, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
  panel.box.bg:SetAllPoints()
  panel.box.hint = panel.box:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  panel.box.hint:SetPoint("LEFT", panel.box, "LEFT", 4, 0)
  panel.box.hint:SetText("name it")
  panel.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  panel.box:SetScript("OnTextChanged", function(self)
    self.hint:SetShown((self:GetText() or "") == "")
  end)
  panel.box:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine("name it", 1, 0.82, 0)
    GameTooltip:AddLine("What to call the build you are about to write down - "
      .. "\"levelling\", \"aoe\", \"the one that works\". Leave it empty and it "
      .. "is called what it is, 31/20/0. A name you have used before replaces "
      .. "that build.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  panel.box:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local function Save()
    local b, why = BT.SaveBuild(panel.box:GetText())
    if not b then
      print(C.info .. BT.NAME .. ":|r " .. C.bad .. (why or "no") .. "|r")
      return
    end
    panel.box:SetText("")
    panel.box:ClearFocus()
    BT.RenderTalents()
  end
  panel.box:SetScript("OnEnterPressed", Save)

  panel.plan = Button(panel, "plan", 48, 20, function()
    -- Empty. It was seeded with the points you already had, on the grounds
    -- that a plan is usually the build you have with the rest filled in - but
    -- a planner that starts with somebody else's answer in it is a planner you
    -- have to undo before you can think, and the points cannot be taken out in
    -- any order anyway.
    BT.PlanOpen()
  end)
  panel.plan.hint = "build one by clicking, without having the points. The "
    .. "rules are the game's own: a point that could not be learned does not "
    .. "go in, so a plan that can be written down is a plan that can be spent."
  panel.plan.hintTitle = "plan a build"
  panel.plan:SetPoint("TOPLEFT", 134, y)

  panel.save = Button(panel, "save this", 74, 20, Save)
  panel.save.hint = "write down the build you are standing in. Name it and it "
    .. "keeps the name; leave the name empty and it is called what it is, "
    .. "31/20/0. Saving over a name you already used replaces it."
  panel.save.hintTitle = "save this build"
  panel.save:SetPoint("TOPLEFT", 186, y)

  panel.status = panel:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  panel.status:SetPoint("TOPLEFT", 12, y - 26)
  panel.status:SetWidth(284)
  panel.status:SetJustifyH("LEFT")

  panel.stop = Button(panel, "stop", 44, 16, function() BT.CancelApply() end)
  panel.stop.hint = "stop putting points in. What is already in stays in."
  panel.stop:SetPoint("TOPLEFT", 240, y - 26)
  panel.stop:Hide()

  BT.talentPanel = panel
  return panel
end

-- The planner's own window: the whole tree, clickable, with a name and a
-- save. Built once and filled again every time a point moves.
local function MakePlanner()
  if BT.planner then return BT.planner end
  local f = CreateFrame("Frame", "ChainPlanner", UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetSize(3 * PTREE_W + 28, 380)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f.edge = Tex(f, "BACKGROUND", 0.3, 0.3, 0.35, 1)
  f.edge:SetPoint("TOPLEFT", -1, 1)
  f.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  f.bg = Tex(f, "BACKGROUND", 0.04, 0.04, 0.05, 1)
  f.bg:SetAllPoints()
  f.bg:SetDrawLayer("BACKGROUND", 2)

  f.title = f:CreateFontString(nil, "OVERLAY", "ChainFontNormalLarge")
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetText(BT.NAME .. " - plan a build")
  f.count = f:CreateFontString(nil, "OVERLAY", "ChainFontNormal")
  f.count:SetPoint("TOPRIGHT", -38, -12)
  f.countHit = CreateFrame("Frame", nil, f)
  f.countHit:SetPoint("TOPRIGHT", -30, -6)
  f.countHit:SetSize(140, 18)
  f.countHit:EnableMouse(true)
  f.countHit:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine("points in this plan", 1, 0.82, 0)
    GameTooltip:AddLine("Fifty-one is what sixty gives you: one a level from "
      .. "ten. You can plan past what you have - it says which level the plan "
      .. "needs - and putting it in before then spends as far as your points "
      .. "reach.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  f.countHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local close = Button(f, "X", 24, 20, function() BT.PlanClose() end)
  close:SetPoint("TOPRIGHT", -6, -6)

  f.note = f:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  f.note:SetPoint("TOPLEFT", 12, -30)
  f.note:SetWidth(3 * PTREE_W)
  f.note:SetJustifyH("LEFT")
  f.note:SetText(C.dim .. "left-click adds a point, right-click takes one "
    .. "out. A point the game would refuse does not go in." .. C.off)

  f.heads, f.slots = {}, {}
  for tab = 1, 3 do
    local h = f:CreateFontString(nil, "OVERLAY", "ChainFontHighlightSmall")
    h:SetPoint("TOPLEFT", 12 + (tab - 1) * PTREE_W, -48)
    h:SetWidth(PTREE_W - 6)
    h:SetJustifyH("LEFT")
    f.heads[tab] = h
  end

  f.box = CreateFrame("EditBox", nil, f)
  f.box:SetSize(146, 22)
  f.box:SetAutoFocus(false)
  f.box:SetFontObject("ChainFontHighlightSmall")
  f.box:SetMaxLetters(24)
  f.box.bg = Tex(f.box, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
  f.box.bg:SetAllPoints()
  f.box.hint = f.box:CreateFontString(nil, "OVERLAY", "ChainFontDisableSmall")
  f.box.hint:SetPoint("LEFT", f.box, "LEFT", 4, 0)
  f.box.hint:SetText("name it")
  f.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  f.box:SetScript("OnTextChanged", function(self)
    self.hint:SetShown((self:GetText() or "") == "")
    if plan then plan.name = self:GetText() end
  end)
  f.box:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine("name it", 1, 0.82, 0)
    GameTooltip:AddLine("What this plan is called once it is saved. Enter "
      .. "saves it from here.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
  end)
  f.box:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local function Keep()
    local b, why = BT.PlanSave()
    if not b then
      BT.TalentSay(why or "nothing to save")
      return
    end
    BT.PlanClose()
    BT.RenderTalents()
  end
  f.box:SetScript("OnEnterPressed", Keep)
  f.save = Button(f, "save build", 92, 22, Keep)
  f.save.hint = "write this down as a build. It can be put in the day you "
    .. "have the points for it - and until then it goes in as far as your "
    .. "points reach."
  f.clear = Button(f, "clear", 60, 22, function()
    if plan then BT.PlanOpen(nil, plan.name) end
  end)
  f.clear.hintTitle = "clear"
  f.clear.hint = "take every point back out and start again"
  BT.planner = f
  return f
end

-- What the talent actually does, in the game's own words.
--
-- "Improved Ambush" is a name, not a reason to spend three points on it. The
-- client will hand over the real text two different ways depending on the
-- build you are running, and on some it will hand over neither - so this asks
-- for it, checks whether anything arrived, and tries the other way before
-- giving up. Without the check a silent failure looks exactly like a talent
-- with nothing to say about itself.
function BT.TalentWords(tip, tab, index)
  if not tip then return false end
  if tip.ClearLines then tip:ClearLines() end
  local function got()
    return (tip.NumLines and (tip:NumLines() or 0) or 0) > 0
  end
  if tip.SetTalent then
    pcall(tip.SetTalent, tip, tab, index)
    if got() then return true end
  end
  if type(GetTalentLink) == "function" and tip.SetHyperlink then
    local link = GetTalentLink(tab, index)
    if link then
      pcall(tip.SetHyperlink, tip, link)
      if got() then return true end
    end
  end
  return false
end

-- Why that one will not take a point.
--
-- The answer is always one of two things and the planner already knows both,
-- so it can say them instead of refusing in silence. Hovering a talent you
-- cannot have yet is exactly when you want to be told what is in the way.
function BT.PlanWhy(tab, index, ranks)
  ranks = ranks or BT.PlanRanks()
  local t = Talent(tab, index)
  if not (t and ranks) then return nil end
  local have = ((ranks[tab] or {})[index] or 0)
  if have >= t.max then return "full" end
  local spent = 0
  for _, r in ipairs(ranks[tab] or {}) do spent = spent + r end
  local need = ((t.tier or 1) - 1) * 5
  if spent < need then
    return "needs " .. need .. " points in " .. BT.TreeName(tab)
      .. " - you have put in " .. spent
  end
  local ptier, pcol = PrereqOf(tab, index)
  if ptier then
    local pi, pt = AtCell(tab, ptier, pcol)
    if pi and pt and ((ranks[tab] or {})[pi] or 0) < pt.max then
      return "needs " .. pt.name .. " at " .. pt.max .. "/" .. pt.max
    end
  end
  local total = BT.SpecPoints(ranks)
  if total >= 51 then return "that is all fifty-one points" end
  return nil
end

-- One clickable talent, made when first needed
local function PlanSlot(i)
  local f = MakePlanner()
  if f.slots[i] then return f.slots[i] end
  local b = CreateFrame("Button", nil, f)
  b:SetSize(PICON, PICON)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints()
  b.edge = Tex(b, "BACKGROUND", 0.25, 0.25, 0.28, 1)
  b.edge:SetPoint("TOPLEFT", -1, 1)
  b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  b.rank = b:CreateFontString(nil, "OVERLAY", "ChainFontNormal")
  b.rank:SetPoint("BOTTOMRIGHT", 3, -2)
  b:SetScript("OnClick", function(self, button)
    if not self.tab then return end
    local was = ((BT.PlanRanks() or {})[self.tab] or {})[self.index] or 0
    BT.PlanSet(self.tab, self.index, was + ((button == "RightButton") and -1 or 1))
  end)
  b:SetScript("OnEnter", function(self)
    if not self.tab then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local told = BT.TalentWords(GameTooltip, self.tab, self.index)
    local t = Talent(self.tab, self.index)
    if t then
      local have = ((BT.PlanRanks() or {})[self.tab] or {})[self.index] or 0
      -- the game has already said the name if it said anything at all
      if not told then GameTooltip:AddLine(t.name, 1, 0.82, 0) end
      GameTooltip:AddLine(have .. "/" .. t.max .. "   row " .. t.tier,
        0.8, 0.8, 0.8)
      local why = BT.PlanWhy(self.tab, self.index)
      if why == "full" then
        GameTooltip:AddLine("as far as it goes", 0.5, 0.8, 0.5)
      elseif why then
        -- what is in the way, rather than a click that does nothing
        GameTooltip:AddLine(why, 1, 0.5, 0.4, true)
      else
        GameTooltip:AddLine("left-click puts a point in", 0.5, 0.8, 1)
      end
      if have > 0 then
        GameTooltip:AddLine("right-click takes one out", 0.5, 0.8, 1)
      end
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.slots[i] = b
  return b
end

function BT.RenderPlan(place)
  local f = MakePlanner()
  local ranks = BT.PlanRanks()
  if not ranks then f:Hide() return end
  local used, bottom = 0, 0
  for tab = 1, Tabs() do
    local n = 0
    for _, r in ipairs(ranks[tab] or {}) do n = n + r end
    f.heads[tab]:SetText(BT.TreeName(tab) .. C.dim .. "  " .. n .. C.off)
    for index = 1, Count(tab) do
      local t = Talent(tab, index)
      if t then
        used = used + 1
        local b = PlanSlot(used)
        b.tab, b.index = tab, index
        local have = (ranks[tab] or {})[index] or 0
        local _, icon = GetTalentInfo(tab, index)
        b.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        -- a talent with nothing in it is there to be read, not to be looked
        -- at: grey, and the ones you have taken light up
        if b.tex.SetDesaturated then b.tex:SetDesaturated(have <= 0) end
        b.tex:SetAlpha((have > 0) and 1 or 0.45)
        local full = have >= t.max
        b.edge:SetColorTexture(
          (have <= 0) and 0.25 or (full and 1 or 0.5),
          (have <= 0) and 0.25 or (full and 0.82 or 0.42),
          (have <= 0) and 0.28 or (full and 0 or 0.15), 1)
        b.rank:SetText((have > 0) and (C.gold .. have .. C.off) or "")
        b:ClearAllPoints()
        local x = 12 + (tab - 1) * PTREE_W + ((t.column or 1) - 1) * PPITCH
        local y = -66 - ((t.tier or 1) - 1) * PPITCH
        b:SetPoint("TOPLEFT", x, y)
        b:Show()
        if -y > bottom then bottom = -y end
      end
    end
  end
  for i = used + 1, #f.slots do f.slots[i]:Hide() end

  local spent = BT.SpecPoints(ranks)
  local mine = BT.PointsAt(UnitLevel("player"))
  f.count:SetText(C.gold .. spent .. C.off .. C.dim .. " of " .. (plan.cap or 51)
    .. ((spent > mine) and (C.warn .. "   needs level " .. (spent + 9) .. C.off)
        or "") .. C.off)

  local y = -(bottom + PICON + 14)
  f.box:ClearAllPoints()
  f.box:SetPoint("TOPLEFT", 12, y)
  f.save:ClearAllPoints()
  f.save:SetPoint("TOPLEFT", 164, y)
  f.clear:ClearAllPoints()
  f.clear:SetPoint("TOPLEFT", 262, y)
  f:SetHeight(-y + 34)
  f.title:SetText(plan.editing
    and (BT.NAME .. " - editing " .. plan.editing)
    or (BT.NAME .. " - plan a build"))
  if place then
    f.box:SetText(plan.name or "")
    f:Show()
  end
end

function BT.RenderTalents()
  if not panel then return end
  local list, class = BT.Builds()
  local _, spent = BT.ReadSpec()
  local free = UnitCharacterPoints and UnitCharacterPoints("player") or 0
  panel.note:SetText(C.dim .. BT.SpecLine((BT.ReadSpec())) .. " now"
    .. ((free > 0) and ("   " .. C.warn .. free .. " to spend" .. C.off) or "")
    .. C.off)

  local done, total, name = BT.ApplyStatus()
  -- the dialog can be clicked away; the reason stays here until it is not
  -- the reason any more
  if panel.msg and panel.msgBuild and not BT.WhyNot(panel.msgBuild) then
    panel.msg, panel.msgBuild = nil, nil
  end
  panel.status:SetText(done
    and (C.warn .. done .. " of " .. total .. C.off .. C.dim .. "  putting in "
         .. (name or "") .. C.off)
    or panel.msg and (C.warn .. panel.msg .. C.off)
    or (C.dim .. ((#list == 0)
        and "spec the way you like it, then save it"
        or "'use' spends the points for you, top to bottom") .. C.off))
  panel.stop:SetShown(done and true or false)

  for i, row in ipairs(panel.rows) do
    local b = list[i]
    row.use.build, row.del.build, row.build = b, b, b
    row.edit.build = b
    if b then
      local gap, extra = BT.BuildGap(b), BT.BuildExtra(b)
      row.name:SetText((extra > 0) and (C.dim .. b.name .. C.off) or b.name)
      row.spec:SetText(C.dim .. BT.SpecLine(b.ranks) .. C.off)
      -- three states, and the middle one is the one people get stuck on: the
      -- points are already spent somewhere else and only the trainer can undo
      -- that
      row.use.fs:SetText((gap <= 0) and "on" or ((extra > 0) and "reset" or "use"))
      row.use.hint = (gap <= 0) and "you are already standing in this one"
        or (extra > 0)
        and ("you have " .. extra .. " point" .. ((extra == 1) and "" or "s")
             .. " in places this build does not use. Talents only go in, never "
             .. "out - reset at a trainer first and then press this again.")
        or ("put this build in - " .. gap .. " point"
             .. ((gap == 1) and "" or "s") .. " to spend. It goes in tree by "
             .. "tree and row by row, because that is the only order the game "
             .. "will take.")
      row.use.hintTitle = b.name
      row.del.hint = "forget this build. What you have spent stays spent."
      row:Show()
    else
      row:Hide()
    end
  end
  panel.title:SetText(BT.NAME .. " builds" .. C.dim .. "  " .. spent
    .. " in" .. C.off)

  -- The frame is as tall as what is in it. A line that wrapped to four went
  -- out through the bottom edge and carried on down the screen, which is the
  -- kind of thing you only see once you have something long to say.
  local top = 50 + ROWS * 24 + 6 + 26
  local h = panel.status.GetStringHeight and panel.status:GetStringHeight() or 0
  if not h or h < 12 then h = 12 end
  panel:SetHeight(top + h + 14)
end

-- Blizzard's talent window is loaded the first time you press N, so we cannot
-- reach it before then. This attaches to it whenever it shows up, and to the
-- one that is already there if it has.
local function Attach()
  if panel then return panel end
  local owner = _G.PlayerTalentFrame or _G.TalentFrame
  if not owner then return nil end
  BuildPanel(owner)
  owner:HookScript("OnShow", function()
    if not BT.TalentPanelOn() then panel:Hide() return end
    panel:Show()
    BT.RenderTalents()
  end)
  owner:HookScript("OnHide", function()
    panel:Hide()
    BT.HideBuildPreview()
  end)
  panel:SetShown(BT.TalentPanelOn() and owner:IsShown() and true or false)
  if panel:IsShown() then BT.RenderTalents() end
  return panel
end
BT.AttachTalents = Attach

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHARACTER_POINTS_CHANGED")
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "CHARACTER_POINTS_CHANGED" then
    PointsChanged()
  elseif event == "ADDON_LOADED" and arg1 == "Blizzard_TalentUI" then
    Attach()
  elseif event == "PLAYER_LOGIN" then
    -- it can already be loaded: another addon may have asked for it
    Attach()
  end
end)
BT.talentFrame = frame
