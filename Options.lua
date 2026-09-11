-- Chain: settings, the route editor, and slash commands.

local ADDON, BT = ...
local C = BT.COL
local PER_PAGE = 11
-- Wide enough that the right-hand column's box ends inside the frame:
-- COL[3] + label 112 + box 44 + margin. Everything else is measured off it.
local WIDTH = 508
local opt, exportFrame, optPage = nil, nil, 1

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
  b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.15, 0.15, 0.15, 0.9) end)
  b:SetScript("OnClick", onClick)
  return b
end

-- A number box that only writes back a sane value
local function NumBox(parent, w, onSet)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(w, 18)
  e:SetAutoFocus(false)
  e:SetFontObject("GameFontHighlightSmall")
  e:SetJustifyH("CENTER")
  e:SetMaxLetters(6)
  e.bg = Tex(e, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
  e.bg:SetAllPoints()
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEditFocusLost", function(self)
    onSet(tonumber(self:GetText()))
    if BT.RenderOptions then BT.RenderOptions() end
    if BT.Refresh then BT.Refresh() end
  end)
  return e
end

local function Check(parent, onSet)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(20, 20)
  c:SetScript("OnClick", function(self)
    onSet(self:GetChecked() and true or false)
    if BT.RenderOptions then BT.RenderOptions() end
    if BT.Refresh then BT.Refresh() end
  end)
  return c
end

--------------------------------------------------------------------------
local function BuildOptions()
  opt = CreateFrame("Frame", "ChainOptions", UIParent)
  -- a starting size only: the height is set from the content at the end of
  -- this function, because guessing it is how the buttons ended up hanging
  -- off the bottom edge
  opt:SetSize(WIDTH, 232 + PER_PAGE * 24)
  opt:SetPoint("CENTER", 200, 0)
  opt:SetMovable(true)
  opt:EnableMouse(true)
  opt:RegisterForDrag("LeftButton")
  opt:SetScript("OnDragStart", opt.StartMoving)
  opt:SetScript("OnDragStop", opt.StopMovingOrSizing)
  opt:SetClampedToScreen(true)
  opt:SetFrameStrata("DIALOG")
  opt:Hide()

  opt.edge = Tex(opt, "BACKGROUND", 0.3, 0.3, 0.35, 1)
  opt.edge:SetPoint("TOPLEFT", -1, 1)
  opt.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  opt.bg = Tex(opt, "BACKGROUND", 0.05, 0.05, 0.06, 0.98)
  opt.bg:SetAllPoints()
  opt.bg:SetDrawLayer("BACKGROUND", 2)

  opt.title = opt:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  opt.title:SetPoint("TOPLEFT", 10, -8)
  opt.title:SetText(BT.NAME .. " settings")

  local close = Button(opt, "X", 22, 18, function() opt:Hide() end)
  close:SetPoint("TOPRIGHT", -6, -6)

  -- A panel this tall does not fit every screen even folded up, so it can be
  -- shrunk outright. Steps rather than a free number: the point is to make it
  -- fit, not to tune it.
  opt.zoom = Button(opt, "", 46, 18, function()
    local steps = { 0.8, 0.9, 1, 1.1 }
    local now = ChainDB.optScale or 1
    local at = 1
    for i, v in ipairs(steps) do if math.abs(v - now) < 0.01 then at = i end end
    ChainDB.optScale = steps[(at % #steps) + 1]
    opt:SetScale(ChainDB.optScale)
    BT.RenderOptions()
  end)
  opt.zoom:SetPoint("TOPRIGHT", -32, -6)

  opt:SetScale(ChainDB.optScale or 1)

  opt.help = opt:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  opt.help:SetPoint("TOPLEFT", 10, -26)
  opt.help:SetJustifyH("LEFT")
  -- bounded and wrapping: written out in full it ran off the right edge
  opt.help:SetWidth(WIDTH - 20)
  opt.help:SetText("Tick the instances you will be boosted through, then set a level span "
    .. "and a price.\n'enter' is the level the game lets you in at; 'levels' is what the "
    .. "place is worth doing at; 'runs' is how many runs that price buys here.")

  -- column headings for the route table
  -- 'gold' is the price of a pack and 'runs' is how many runs that pack is,
  -- because the pack is not the same everywhere: ten Stockade runs for one
  -- price and five in Scholomance is an ordinary week.
  local heads = { { "use", 34 }, { "instance", 82 }, { "enter", 34 },
                  { "levels", 46 }, { "from", 38 }, { "to", 38 },
                  { "gold", 52 }, { "runs", 36 }, { "per", 114 } }
  local hx = 12
  for _, h in ipairs(heads) do
    local fs = opt:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", hx, -60)
    fs:SetText(h[1])
    hx = hx + h[2]
  end

  opt.rows = {}
  for i = 1, PER_PAGE do
    local row = CreateFrame("Frame", nil, opt)
    row:SetSize(476, 22)
    row:SetPoint("TOPLEFT", 12, -76 - (i - 1) * 24)
    if i % 2 == 0 then
      row.stripe = Tex(row, "BACKGROUND", 1, 1, 1, 0.03)
      row.stripe:SetAllPoints()
    end
    row.check = Check(row, function(v)
      if row.id then ChainDB.route[row.id].on = v end
    end)
    row.check:SetPoint("LEFT", 0, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 34, 0)
    row.name:SetWidth(78)
    row.name:SetJustifyH("LEFT")
    -- what the game demands before it lets you through the door, and the span
    -- the instance is actually meant for. Neither is common knowledge, and
    -- guessing them is how a route ends up full of grey mobs or full of
    -- instances you cannot get into yet.
    row.min = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.min:SetPoint("LEFT", 116, 0)
    row.min:SetWidth(30)
    row.min:SetJustifyH("LEFT")
    row.span = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.span:SetPoint("LEFT", 150, 0)
    row.span:SetWidth(42)
    row.span:SetJustifyH("LEFT")
    row.from = NumBox(row, 36, function(v)
      if row.id and v then ChainDB.route[row.id].from = math.max(1, math.min(59, v)) end
    end)
    row.from:SetPoint("LEFT", 196, 0)
    row.to = NumBox(row, 36, function(v)
      if row.id and v then ChainDB.route[row.id].to = math.max(2, math.min(60, v)) end
    end)
    row.to:SetPoint("LEFT", 234, 0)
    row.gold = NumBox(row, 50, function(v)
      if row.id then ChainDB.route[row.id].gold = math.max(0, v or 0) end
    end)
    row.gold:SetPoint("LEFT", 272, 0)
    -- how many runs that price buys here. Blank means "whatever Runs per
    -- price says", so a route typed in before this existed still reads right.
    row.pack = NumBox(row, 32, function(v)
      if not row.id then return end
      v = tonumber(v)
      if not v or v <= 0 then ChainDB.route[row.id].pack = nil
      else ChainDB.route[row.id].pack = math.max(1, math.min(99, math.floor(v))) end
    end)
    row.pack:SetPoint("LEFT", 324, 0)
    row.note = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.note:SetPoint("LEFT", 360, 0)
    row.note:SetWidth(112)
    row.note:SetJustifyH("LEFT")
    opt.rows[i] = row
  end

  local y = -76 - PER_PAGE * 24 - 6
  opt.pageText = opt:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  opt.pageText:SetPoint("TOPLEFT", 12, y)
  local prev = Button(opt, "< prev", 56, 18, function()
    if optPage > 1 then optPage = optPage - 1 BT.RenderOptions() end
  end)
  prev:SetPoint("TOPRIGHT", -72, y + 2)
  local nxt = Button(opt, "next >", 56, 18, function()
    optPage = optPage + 1 BT.RenderOptions()
  end)
  nxt:SetPoint("TOPRIGHT", -12, y + 2)

  -- General settings, laid out on a grid rather than by hand. Every earlier
  -- pass moved one control and quietly landed it on top of another.
  local COL = { 12, 176, 340 }
  local row = 0
  opt.boxes = {}
  local function At(c, dy) return COL[c], y - row * 24 + (dy or 0) end
  local function NextRow() row = row + 1 end

  local function Field(c, label, width, get, set)
    local fs = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local x, ly = At(c)
    fs:SetPoint("TOPLEFT", x, ly)
    fs:SetText(label)
    local box = NumBox(opt, width or 40, set)
    box:SetPoint("TOPLEFT", x + 112, ly + 3)
    box.get = get
    table.insert(opt.boxes, box)
    return box
  end

  -- A heading and a hairline across the panel. Twenty-odd controls in one
  -- undifferentiated block is a wall you read every time instead of a list you
  -- learn the shape of - and the things that belong together were nowhere near
  -- each other.
  -- A heading and a hairline, and the heading is a button: click it and the
  -- section folds away. Twenty-odd controls in one undifferentiated block is a
  -- wall you read every time rather than a list you learn the shape of, and
  -- the panel was taller than a lot of screens.
  --
  -- Which ones are folded is remembered, so the two settings you actually
  -- change stay open and the rest stay out of the way.
  opt.sections = {}
  local function Section(title, key)
    row = row + 0.35
    local x, ly = At(1)
    local head = CreateFrame("Button", nil, opt)
    head:SetSize(WIDTH - 24, 14)
    head:SetPoint("TOPLEFT", x, ly + 2)
    head.fs = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    head.fs:SetPoint("LEFT", 0, 0)
    head.fs:SetJustifyH("LEFT")
    local line = Tex(opt, "ARTWORK", 0.35, 0.35, 0.42, 0.8)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", x, ly - 13)
    line:SetPoint("TOPRIGHT", opt, "TOPLEFT", WIDTH - 12, ly - 13)

    local sec = { key = key, title = title, head = head, line = line, y = ly }
    head:SetScript("OnClick", function()
      ChainDB.optFold = ChainDB.optFold or {}
      ChainDB.optFold[key] = not ChainDB.optFold[key]
      BT.RenderOptions()
    end)
    table.insert(opt.sections, sec)
    row = row + 0.75
  end

  local function Toggle(c, label, set)
    local chk = Check(opt, set)
    local x, ly = At(c)
    chk:SetPoint("TOPLEFT", x - 2, ly + 4)
    local fs = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x + 20, ly)
    fs:SetText(label)
    fs:SetWidth(140)
    fs:SetJustifyH("LEFT")
    chk.label = fs
    return chk
  end

  y = y - 26
  Section("Runs and prices", "runs")
  opt.pack = Field(1, "Runs per price", 40, function() return ChainDB.pack end,
    -- the fallback only: the 'runs' column above beats it per instance, and a
    -- pack typed against a booster beats them both while he is boosting you
    function(v) ChainDB.pack = math.max(1, math.floor(v or 1)) end)
  opt.window = Field(2, "Runs in average", 40, function() return ChainDB.window end,
    function(v) ChainDB.window = math.max(1, math.floor(v or 5)) end)
  opt.limit = Field(3, "Max per hour", 40, function() return ChainDB.limit end,
    function(v) ChainDB.limit = math.max(1, math.floor(v or 5)) end)
  NextRow()

  Section("Resets and alerts", "resets")
  opt.sound = Toggle(1, "Sound on reset", function(v) ChainDB.sound = v end)
  do
    local x, ly = At(1)
    opt.soundRepeat = NumBox(opt, 28, function(v)
      ChainDB.soundRepeat = math.max(1, math.min(10, math.floor(v or 1)))
    end)
    opt.soundRepeat:SetPoint("TOPLEFT", x + 124, ly + 3)
  end
  opt.announce = Toggle(2, "Tell the group on reset",
    function(v) ChainDB.announce = v end)
  opt.banner = Toggle(3, "Big alert on reset", function(v) ChainDB.banner = v end)
  NextRow()

  -- A reset means the opposite thing depending on which side of the portal
  -- you are on, so it gets two sounds. Clicking plays the one you land on:
  -- picking an alert you have never heard is how you end up ignoring it.
  do
    local function Cycle(which)
      local key = (which == "out") and (ChainDB.soundOut or "warning")
        or (ChainDB.soundIn or "levelup")
      local at = 1
      for i, s in ipairs(BT.SOUNDS) do if s.key == key then at = i end end
      local nxt = BT.SOUNDS[(at % #BT.SOUNDS) + 1]
      if which == "out" then ChainDB.soundOut = nxt.key
      else ChainDB.soundIn = nxt.key end
      if BT.Beep then BT.Beep(which) end
      BT.RenderOptions()
    end
    local x, ly = At(1)
    opt.soundIn = Button(opt, "", 156, 18, function() Cycle("in") end)
    opt.soundIn:SetPoint("TOPLEFT", x, ly - 1)
    local x2, ly2 = At(2)
    opt.soundOut = Button(opt, "", 156, 18, function() Cycle("out") end)
    opt.soundOut:SetPoint("TOPLEFT", x2, ly2 - 1)
    local x3, ly3 = At(3)
    opt.soundHint = opt:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    opt.soundHint:SetPoint("TOPLEFT", x3, ly3)
    opt.soundHint:SetWidth(156)
    opt.soundHint:SetJustifyH("LEFT")
    opt.soundHint:SetText("click to hear it")
  end
  NextRow()

  Section("What to read out of chat", "chat")
  -- Its history is taken into our own log on every login whether this is on
  -- or off. This only decides whether its live count is trusted over ours.
  opt.nit = Toggle(1, "Read NIT's count",
    function(v) ChainDB.useNIT = v end)
  opt.ads = Toggle(2, "Read boost adverts", function(v) ChainDB.readAds = v end)

  opt.signal = Toggle(3, "Marker in the chat log", function(v)
    ChainDB.logSignal = v
    if v then BT.EnableSignal() end
  end)
  NextRow()
  opt.snap = Toggle(1, "Instant alert (screenshot)", function(v)
    ChainDB.snapSignal = v
  end)
  -- The other half of what people write in those channels: LFM, LFG, WTB.
  -- Its own switch, because a busy LookingForGroup produces a great deal more
  -- of it than it does boost adverts.
  opt.groups = Toggle(3, "Read LFM and LFG posts", function(v)
    ChainDB.readGroups = v
  end)
  NextRow()
  do
    -- its own row: the explanation is longer than any column
    local x, ly = At(1)
    local fs = opt:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", x, ly + 4)
    fs:SetWidth(WIDTH - 30)
    fs:SetJustifyH("LEFT")
    fs:SetText("The chat log is written in 48 KB blocks and can lag ten minutes. "
      .. "A screenshot reaches the disk at once, so that is what the phone "
      .. "program watches for.")
  end
  NextRow()

  Section("Who is out there", "enemies")
  opt.watch = Toggle(1, "Watch for enemies", function(v)
    ChainDB.watchEnemies = v
  end)
  opt.alertAll = Toggle(2, "Alert on everyone", function(v)
    ChainDB.alertEveryone = v
  end)
  opt.enemySound = Toggle(3, "Sound on a marked one", function(v)
    ChainDB.enemySound = v
  end)
  NextRow()
  -- The one alert that is allowed to be rude, because it is the only sighting
  -- where knowing is the whole of the advantage.
  opt.stealth = Toggle(1, "Shout about stealth", function(v)
    ChainDB.stealthAlert = v
  end)
  -- Off by default: it puts a line in a chat channel other people read.
  opt.announceKOS = Toggle(2, "Call out marked ones", function(v)
    ChainDB.announceKOS = v
  end)
  -- Where the call-out goes. "auto" is the right answer almost always: the
  -- people who can do anything about it are whoever you are with.
  opt.sightChan = Button(opt, "", 140, 18, function()
    local order = { "auto", "party", "raid", "guild", "say" }
    local now = ChainDB.sightChannel or "auto"
    local at = 1
    for i, v in ipairs(order) do if v == now then at = i end end
    ChainDB.sightChannel = order[(at % #order) + 1]
    BT.RenderOptions()
  end)
  do
    local x3, ly3 = At(3)
    opt.sightChan:SetPoint("TOPLEFT", x3, ly3 - 1)
  end
  NextRow()
  opt.nearbyList = Toggle(1, "List on screen", function(v)
    ChainDB.nearbyList = v
    if BT.RefreshNearby then BT.RefreshNearby() end
  end)
  -- How many of them the list shows at once. Everyone within range is still
  -- counted in the heading; this is only how many rows you want in the way.
  opt.nearbyRows = Field(2, "Rows to show", 32,
    function() return ChainDB.nearbyRows or 8 end,
    function(v)
      if BT.SetNearbyRows then BT.SetNearbyRows(v or 8) end
    end)
  -- which way it grows from where you parked it, so a list at the bottom of
  -- the screen does not grow off it. Also on right-click, on the list itself.
  opt.nearbyGrow = Button(opt, "", 140, 18, function()
    if BT.SetNearbyGrow then
      BT.SetNearbyGrow((ChainDB.nearbyGrow == "up") and "down" or "up")
    end
    BT.RenderOptions()
  end)
  do
    local x3, ly3 = At(3)
    opt.nearbyGrow:SetPoint("TOPLEFT", x3, ly3 - 1)
  end
  NextRow()

  Section("Sharing and the bar", "share")
  opt.announceLock = Toggle(1, "Tell the group your lockout",
    function(v) ChainDB.announceLock = v end)
  opt.minimap = Toggle(3, "Button on the minimap", function(v)
    ChainDB.minimap = v
    if BT.RefreshMinimap then BT.RefreshMinimap() end
  end)
  NextRow()

  opt.share = Toggle(1, "Share what you measure", function(v)
    ChainDB.share = v
    if v then BT.StartSharing() else BT.StopSharing() end
  end)
  do
    local x, ly = At(2)
    -- "share with" is a fixed label and the button holds only the value, so
    -- the button can be sized to the longest value rather than to a sentence.
    -- It carried the whole phrase before and ran clean through the button
    -- beside it.
    opt.scopeLabel = opt:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    opt.scopeLabel:SetPoint("TOPLEFT", x, ly)
    opt.scopeLabel:SetText("share with")
    opt.scope = Button(opt, "", 90, 18, function()
      BT.CycleShareScope()
      BT.RenderOptions()
    end)
    opt.scope:SetPoint("TOPLEFT", x + 66, ly - 1)
    -- bounded, so a longer name in some future locale truncates instead of
    -- climbing over the next control
    opt.scope.fs:SetWidth(84)
    opt.scope.fs:SetJustifyH("CENTER")
    -- which chat sources adverts are read from. A booster shouts in whichever
    -- channel he likes, so the addon listens to all of them and this is where
    -- you take one away. It sits in the column that was empty, not on top of
    -- the toggle next to it.
    local x3, ly3 = At(3)
    opt.channels = Button(opt, "advert channels...", 140, 18,
      function() BT.ShowAdChannels() end)
    opt.channels:SetPoint("TOPLEFT", x3, ly3 - 1)
  end
  NextRow()

  do
    local x, ly = At(1)
    opt.friendsLabel = opt:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    opt.friendsLabel:SetPoint("TOPLEFT", x, ly)
    opt.friendsLabel:SetText("names to whisper")
    opt.friends = CreateFrame("EditBox", nil, opt)
    opt.friends:SetSize(290, 18)
    opt.friends:SetPoint("TOPLEFT", x + 148, ly + 3)
    opt.friends:SetAutoFocus(false)
    opt.friends:SetFontObject("GameFontHighlightSmall")
    opt.friends.bg = Tex(opt.friends, "BACKGROUND", 0.12, 0.12, 0.14, 0.9)
    opt.friends.bg:SetAllPoints()
    opt.friends:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    opt.friends:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    opt.friends:SetScript("OnEditFocusLost", function(self)
      BT.SetShareFriends(self:GetText())
      BT.RenderOptions()
    end)
  end
  NextRow()

  opt.showBar = Toggle(1, "Show the bar", function(v)
    if v ~= (ChainDB.shown and true or false) then BT.ToggleBar() end
  end)
  opt.lock = Toggle(2, "Lock the bar", function(v) ChainDB.locked = v end)
  do
    local x, ly = At(3)
    opt.rs = Button(opt, "Reset instances", 130, 18, function() BT.DoReset() end)
    opt.rs:SetPoint("TOPLEFT", x, ly - 1)
  end
  NextRow()

  opt.scale = Field(1, "Bar scale", 44, function() return ChainDB.scale end,
    function(v)
      v = tonumber(v) or 1
      if v < 0.5 then v = 0.5 elseif v > 3 then v = 3 end
      ChainDB.scale = v
      if BT.bar then BT.bar:SetScale(v) end
    end)
  -- The week's honour as a second, slimmer bar under the first, with a mark at
  -- each milestone. Off for anybody who never goes near a battleground.
  opt.honorBar = Toggle(3, "Honor bar too", function(v)
    ChainDB.honorBar = v
    if BT.Refresh then BT.Refresh() end
  end)
  opt.width = Field(2, "Bar width", 50, function() return ChainDB.width end,
    function(v)
      v = tonumber(v) or 380
      if v < 200 then v = 200 elseif v > 900 then v = 900 end
      ChainDB.width = v
      if BT.bar then BT.bar:SetWidth(v) end
    end)
  NextRow()

  y = y - row * 24 - 14
  local exp = Button(opt, "Export runs (CSV)", 130, 20, function() BT.ShowExport("runs") end)
  exp:SetPoint("TOPLEFT", 12, y)
  local expT = Button(opt, "Export gold (CSV)", 130, 20, function() BT.ShowExport("trades") end)
  expT:SetPoint("TOPLEFT", 152, y)
  local wipe = Button(opt, "Delete all history", 130, 20, function()
    StaticPopup_Show("CHAIN_WIPE")
  end)
  wipe:SetPoint("TOPLEFT", 292, y)

  -- The frame is as tall as what is in it. Every hand-picked height so far
  -- has been wrong the moment a row was added, and a button drawn past the
  -- bottom edge still works, which is how it went unnoticed.
  opt.fullHeight = -y + 20 + 12
  opt:SetSize(WIDTH, opt.fullHeight)

  -- Everything below the first section heading has to be able to move, so its
  -- built position is recorded once, here, and the layout pass works from
  -- that rather than from wherever it was last put.
  opt.placed = {}
  local function remember(w)
    if not w or not w.GetPoint then return end
    local pt, rel, relPt, px, py = w:GetPoint(1)
    if not pt or not py then return end
    table.insert(opt.placed, { w = w, pt = pt, rel = rel, relPt = relPt,
                              x = px, y = py })
  end
  for _, c in ipairs({ opt:GetChildren() }) do remember(c) end
  for _, r in ipairs({ opt:GetRegions() }) do remember(r) end

  -- Which section each thing sits in: by where it is, not by when it was
  -- made, so the inline blocks that build their own widgets need no special
  -- handling.
  for i, sec in ipairs(opt.sections) do
    local nextY = opt.sections[i + 1] and opt.sections[i + 1].y or -math.huge
    sec.widgets = {}
    for _, p in ipairs(opt.placed) do
      if p.w ~= sec.head and p.w ~= sec.line
         and p.y < sec.y - 14 and p.y > nextY + 2 then
        table.insert(sec.widgets, p)
      end
    end
    -- how much height folding this one away saves
    local lowest = sec.y - 14
    for _, p in ipairs(sec.widgets) do
      local bottom = p.y - (p.w.GetHeight and p.w:GetHeight() or 16)
      if bottom < lowest then lowest = bottom end
    end
    sec.contentH = (sec.y - 14) - lowest
  end
end

-- Fold the closed sections away and slide everything under them up. Positions
-- come from what was recorded at build time, never from where things are now,
-- so folding and unfolding cannot drift.
local function LayoutSections()
  if not opt or not opt.sections then return end
  local fold = ChainDB.optFold or {}
  local shift, cut = 0, 0

  local hidden = {}
  for _, sec in ipairs(opt.sections) do
    local closed = fold[sec.key] and true or false
    sec.head.fs:SetText((closed and (C.dim .. "+ ") or (C.gold .. "- "))
      .. sec.title .. C.off)
    sec.head:ClearAllPoints()
    sec.head:SetPoint("TOPLEFT", 12, sec.y + 2 + shift)
    sec.line:ClearAllPoints()
    sec.line:SetPoint("TOPLEFT", 12, sec.y - 13 + shift)
    sec.line:SetPoint("TOPRIGHT", opt, "TOPLEFT", WIDTH - 12, sec.y - 13 + shift)
    for _, p in ipairs(sec.widgets) do
      hidden[p.w] = closed
      if not closed then
        p.w:ClearAllPoints()
        p.w:SetPoint(p.pt, p.rel or opt, p.relPt or p.pt, p.x, p.y + shift)
      end
      p.w:SetShown(not closed)
    end
    if closed then
      shift = shift + sec.contentH
      cut = cut + sec.contentH
    end
  end

  -- and the buttons below the last section come up with it
  local lastY = opt.sections[#opt.sections] and opt.sections[#opt.sections].y or 0
  for _, p in ipairs(opt.placed) do
    if hidden[p.w] == nil and p.y < lastY - 14 then
      p.w:ClearAllPoints()
      p.w:SetPoint(p.pt, p.rel or opt, p.relPt or p.pt, p.x, p.y + shift)
    end
  end
  opt:SetHeight(math.max(120, (opt.fullHeight or 400) - cut))
end
BT.LayoutOptions = LayoutSections

function BT.RenderOptions()
  if not opt or not opt:IsShown() then return end
  local db = ChainDB
  LayoutSections()
  opt.zoom.fs:SetText(math.floor((db.optScale or 1) * 100 + 0.5) .. "%")
  local pages = math.ceil(#BT.DUNGEONS / PER_PAGE)
  if optPage > pages then optPage = pages end
  if optPage < 1 then optPage = 1 end
  opt.pageText:SetText("page " .. optPage .. " of " .. pages)

  for i = 1, PER_PAGE do
    local row = opt.rows[i]
    local d = BT.DUNGEONS[(optPage - 1) * PER_PAGE + i]
    if d then
      local r = db.route[d.id] or { on = false, from = d.lo, to = d.hi, gold = 0 }
      db.route[d.id] = r
      row.id = d.id
      row.name:SetText(d.label)
      row.min:SetText(BT.MinChunk(d) or "")
      row.span:SetText(BT.SpanChunk(d) or "")
      row.check:SetChecked(r.on and true or false)
      row.from:SetText(tostring(r.from or d.lo))
      row.to:SetText(tostring(r.to or d.hi))
      row.gold:SetText(tostring(r.gold or 0))
      if not row.pack:HasFocus() then
        row.pack:SetText((r.pack and r.pack > 0) and tostring(r.pack)
          or tostring(db.pack or 1))
      end
      -- what we know about this instance already - or, ahead of that, that
      -- the span you typed starts before the game will let you in
      local runs = BT.Runs({ id = d.id })
      if d.min and (r.from or 0) < d.min then
        row.note:SetText(C.bad .. "cannot enter before " .. d.min .. C.off)
      elseif #runs > 0 then
        local agg = BT.Aggregate(runs, db.window or 5)
        row.note:SetText(string.format("%d runs, %s xp each", #runs, BT.N(agg.xp)))
      else
        row.note:SetText("")
      end
      row:Show()
    else
      row.id = nil
      row:Hide()
    end
  end

  for _, box in ipairs(opt.boxes or {}) do
    if not box:HasFocus() then box:SetText(tostring(box.get() or 0)) end
  end
  if not opt.soundRepeat:HasFocus() then
    opt.soundRepeat:SetText(tostring(db.soundRepeat or 1))
  end
  opt.sound:SetChecked(db.sound and true or false)
  opt.soundIn.fs:SetText("go in: " .. BT.SoundByKey(db.soundIn or "levelup").label)
  opt.soundOut.fs:SetText("zone out: " .. BT.SoundByKey(db.soundOut or "warning").label)
  opt.banner:SetChecked(db.banner and true or false)
  opt.announce:SetChecked(db.announce and true or false)
  opt.ads:SetChecked(db.readAds and true or false)
  opt.signal:SetChecked(db.logSignal and true or false)
  opt.snap:SetChecked(db.snapSignal and true or false)
  opt.groups:SetChecked(db.readGroups and true or false)
  opt.announceLock:SetChecked(db.announceLock and true or false)
  opt.minimap:SetChecked(db.minimap ~= false)
  opt.watch:SetChecked(db.watchEnemies and true or false)
  opt.alertAll:SetChecked(db.alertEveryone and true or false)
  opt.enemySound:SetChecked(db.enemySound and true or false)
  opt.nearbyList:SetChecked(db.nearbyList ~= false)
  opt.share:SetChecked(db.share and true or false)
  opt.nit:SetChecked(db.useNIT and true or false)
  opt.lock:SetChecked(db.locked and true or false)
  opt.honorBar:SetChecked(db.honorBar ~= false)
  opt.stealth:SetChecked(db.stealthAlert ~= false)
  opt.announceKOS:SetChecked(db.announceKOS and true or false)
  opt.sightChan.fs:SetText((db.announceKOS and C.gold or C.dim)
    .. "call out in: " .. (db.sightChannel or "auto") .. C.off)
  opt.showBar:SetChecked(db.shown and true or false)
  -- short on purpose: the long version ran into the column beside it
  opt.nit.label:SetText(_G.NIT and "Read NIT's count"
    or (C.dim .. "NIT not installed" .. C.off))

  -- The chosen value in gold when sharing is actually on, and the whole row
  -- greyed when it is off: a setting you cannot see the state of is a setting
  -- you click twice to find out.
  local sharing = db.share and true or false
  opt.scope.fs:SetText((sharing and C.gold or C.dim) .. BT.ShareScopeName() .. C.off)
  opt.nearbyGrow.fs:SetText((db.nearbyList ~= false)
    and ("list grows " .. C.gold
         .. ((db.nearbyGrow == "up") and "up" or "down") .. C.off)
    or (C.dim .. "list grows "
        .. ((db.nearbyGrow == "up") and "up" or "down") .. C.off))
  opt.scopeLabel:SetText(sharing and "share with"
    or (C.dim .. "share with" .. C.off))
  local friends = table.concat(db.shareFriends or {}, ", ")
  if not opt.friends:HasFocus() then opt.friends:SetText(friends) end
  -- the names field stays where it is whatever the scope says: hiding it left
  -- an unexplained hole in the middle of the panel
  -- short enough to sit clear of the box next to it, whatever the state
  local wantsNames = (db.shareWith == "friends")
  opt.friendsLabel:SetText(wantsNames and "names to whisper"
    or (C.dim .. "names to whisper" .. C.off))
end

--------------------------------------------------------------------------
-- Where adverts are read from
--------------------------------------------------------------------------
-- Boosters advertise wherever they feel like: Trade, General, the server's
-- own boosting channel, a whisper. The addon listens to all of it, and this
-- is the list where you take one away - built from the channels you are
-- actually in, so it matches what your chat window shows.
local chanFrame
local CHAN_ROWS = 18

local function BuildAdChannels()
  chanFrame = CreateFrame("Frame", "ChainAdChannels", UIParent)
  chanFrame:SetSize(260, 96 + CHAN_ROWS * 20)
  chanFrame:SetPoint("CENTER", -220, 0)
  chanFrame:SetMovable(true)
  chanFrame:EnableMouse(true)
  chanFrame:RegisterForDrag("LeftButton")
  chanFrame:SetScript("OnDragStart", chanFrame.StartMoving)
  chanFrame:SetScript("OnDragStop", chanFrame.StopMovingOrSizing)
  chanFrame:SetClampedToScreen(true)
  chanFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  chanFrame:Hide()

  chanFrame.edge = Tex(chanFrame, "BACKGROUND", 0.3, 0.3, 0.35, 1)
  chanFrame.edge:SetPoint("TOPLEFT", -1, 1)
  chanFrame.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  chanFrame.bg = Tex(chanFrame, "BACKGROUND", 0.05, 0.05, 0.06, 0.98)
  chanFrame.bg:SetAllPoints()
  chanFrame.bg:SetDrawLayer("BACKGROUND", 2)

  chanFrame.title = chanFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  chanFrame.title:SetPoint("TOPLEFT", 10, -8)
  chanFrame.title:SetText("Read adverts from")

  local close = Button(chanFrame, "X", 22, 18, function() chanFrame:Hide() end)
  close:SetPoint("TOPRIGHT", -6, -6)

  chanFrame.help = chanFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  chanFrame.help:SetPoint("TOPLEFT", 10, -26)
  chanFrame.help:SetWidth(240)
  chanFrame.help:SetJustifyH("LEFT")
  chanFrame.help:SetText("Every channel you are in is read unless you untick it, "
    .. "General and Trade included. One you are not in cannot be read at all - "
    .. "/join it and it appears here.")

  chanFrame.rows = {}
  for i = 1, CHAN_ROWS do
    local row = CreateFrame("Frame", nil, chanFrame)
    row:SetSize(236, 20)
    row:SetPoint("TOPLEFT", 12, -56 - (i - 1) * 20)
    row.check = Check(row, function(v)
      if row.key then BT.SetAdSource(row.key, v) end
    end)
    row.check:SetPoint("LEFT", 0, 0)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 24, 0)
    row.label:SetWidth(200)
    row.label:SetJustifyH("LEFT")
    chanFrame.rows[i] = row
  end

  local y = -56 - CHAN_ROWS * 20 - 4
  local all = Button(chanFrame, "all on", 60, 18, function()
    for _, src in ipairs(BT.AdSourceList()) do BT.SetAdSource(src.key, true) end
    BT.RenderAdChannels()
  end)
  all:SetPoint("TOPLEFT", 12, y)
  local none = Button(chanFrame, "all off", 60, 18, function()
    for _, src in ipairs(BT.AdSourceList()) do BT.SetAdSource(src.key, false) end
    BT.RenderAdChannels()
  end)
  none:SetPoint("TOPLEFT", 78, y)
  chanFrame.note = chanFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  chanFrame.note:SetPoint("TOPLEFT", 146, y - 2)
end

function BT.RenderAdChannels()
  if not chanFrame or not chanFrame:IsShown() then return end
  local list = BT.AdSourceList()
  for i = 1, CHAN_ROWS do
    local row = chanFrame.rows[i]
    local src = list[i]
    if src then
      row.key = src.key
      -- what each one has actually given you, so a channel nobody advertises
      -- in is obvious at a glance
      row.label:SetText(src.label .. ((src.n or 0) > 0
        and (C.dim .. "   " .. src.n .. " heard" .. C.off) or ""))
      row.check:SetChecked(src.on)
      row:Show()
    else
      row.key = nil
      row:Hide()
    end
  end
  local off = 0
  for _, src in ipairs(list) do if not src.on then off = off + 1 end end
  chanFrame.note:SetText(off == 0 and (C.dim .. "reading all of them" .. C.off)
    or (C.warn .. off .. " turned off" .. C.off))
  if not ChainDB.readAds then
    chanFrame.note:SetText(C.bad .. "adverts are off in the settings" .. C.off)
  end
end

function BT.ShowAdChannels()
  if not chanFrame then BuildAdChannels() end
  if chanFrame:IsShown() then chanFrame:Hide() return end
  chanFrame:Show()
  BT.RenderAdChannels()
end

function BT.ToggleOptions()
  if not opt then BuildOptions() end
  if opt:IsShown() then opt:Hide() else opt:Show() BT.RenderOptions() end
end

function BT.InitOptions()
  StaticPopupDialogs["CHAIN_WIPE"] = {
    text = "Delete every recorded run, booster and trade? This cannot be undone.",
    button1 = YES, button2 = NO,
    OnAccept = function()
      ChainDB.runs = {}
      ChainDB.trades = {}
      BT.Touch()
      BT.TouchTrades()
      ChainCharDB.entries = {}
      ChainCharDB.buckets = {}
      ChainCharDB.lastBy = nil
      if BT.Refresh then BT.Refresh() end
      if BT.RenderWindow then BT.RenderWindow() end
      print(C.warn .. BT.NAME .. ":|r history deleted.")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3
  }
end

--------------------------------------------------------------------------
-- CSV export
--------------------------------------------------------------------------
function BT.BuildTradeCSV()
  local out = { "at,date,traded_with,paid_copper,got_copper,net_gold,where,step,level,was_booster,char" }
  for _, t in ipairs(ChainDB.trades) do
    table.insert(out, table.concat({
      t.at or 0,
      date("%Y-%m-%d %H:%M", t.at or 0),
      '"' .. (t.with or "") .. '"',
      t.gave or 0,
      t.got or 0,
      string.format("%.4f", BT.Gold((t.gave or 0) - (t.got or 0))),
      '"' .. (t.zone or "") .. '"',
      t.id or "",
      t.lvl or "",
      t.by and "1" or "0",
      '"' .. (t.char or "") .. '"'
    }, ","))
  end
  return table.concat(out, "\n")
end

function BT.BuildCSV()
  local out = { "at,date,zone,step,xp,seconds,mobs,booster,level,group_size,group_avg,reentry,char" }
  for _, r in ipairs(ChainDB.runs) do
    table.insert(out, table.concat({
      r.at or 0,
      date("%Y-%m-%d %H:%M", r.at or 0),
      '"' .. (r.zone or "") .. '"',
      r.id or "",
      r.xp or 0,
      r.t or 0,
      r.k or 0,
      r.by or "",
      r.lvl or "",
      r.grp or "",
      r.grpAvg and string.format("%.2f", r.grpAvg) or "",
      r.reentry and "1" or "0",
      '"' .. (r.char or "") .. '"'
    }, ","))
  end
  return table.concat(out, "\n")
end

function BT.ShowExport(what)
  if not exportFrame then
    exportFrame = CreateFrame("Frame", "ChainExport", UIParent)
    exportFrame:SetSize(560, 380)
    exportFrame:SetPoint("CENTER")
    exportFrame:SetMovable(true)
    exportFrame:EnableMouse(true)
    exportFrame:RegisterForDrag("LeftButton")
    exportFrame:SetScript("OnDragStart", exportFrame.StartMoving)
    exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)
    exportFrame:SetFrameStrata("FULLSCREEN_DIALOG")

    exportFrame.edge = Tex(exportFrame, "BACKGROUND", 0.3, 0.3, 0.35, 1)
    exportFrame.edge:SetPoint("TOPLEFT", -1, 1)
    exportFrame.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    exportFrame.bg = Tex(exportFrame, "BACKGROUND", 0.04, 0.04, 0.05, 0.99)
    exportFrame.bg:SetAllPoints()
    exportFrame.bg:SetDrawLayer("BACKGROUND", 2)

    local title = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Ctrl+C to copy, then paste into a spreadsheet")

    local close = Button(exportFrame, "X", 22, 18, function() exportFrame:Hide() end)
    close:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", "ChainExportScroll",
      exportFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -30)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetWidth(500)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function() exportFrame:Hide() end)
    scroll:SetScrollChild(edit)
    exportFrame.edit = edit
  end
  exportFrame.edit:SetText((what == "trades") and BT.BuildTradeCSV() or BT.BuildCSV())
  exportFrame.edit:HighlightText()
  exportFrame.edit:SetFocus()
  exportFrame:Show()
end

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------
local function Say(msg) print(C.info .. BT.NAME .. ":|r " .. msg) end

-- The new names first, the old ones kept: a command already in your fingers
-- should not stop working because the addon changed its name.
-- The new name first, then every one it has answered to, because muscle
-- memory outlives a rename and none of these are taken by anything else.
SLASH_CHAIN1 = "/chain"
SLASH_CHAIN2 = "/ch"
SLASH_CHAIN3 = "/levelbar"
SLASH_CHAIN4 = "/lb"
SLASH_CHAIN5 = "/level"
SLASH_CHAIN6 = "/lt"
SLASH_CHAIN7 = "/boost"
SlashCmdList["CHAIN"] = function(input)
  local cmd, rest = (input or ""):lower():match("^(%S*)%s*(.*)$")
  if cmd == "" or cmd == "window" then
    BT.ToggleWindow()
  elseif cmd == "boosters" or cmd == "gold" or cmd == "trade" or cmd == "route"
      or cmd == "history" or cmd == "instances" or cmd == "adverts"
      or cmd == "groups" or cmd == "lfg" or cmd == "lfm" then
    BT.ShowTab(cmd == "history" and "runs" or cmd == "instances" and "locks"
      or cmd == "adverts" and "ads" or cmd == "trade" and "gold"
      or (cmd == "lfg" or cmd == "lfm") and "groups" or cmd)
  elseif cmd == "config" or cmd == "options" or cmd == "opt" then
    BT.ToggleOptions()
  elseif cmd == "show" or cmd == "hide" or cmd == "toggle" then
    BT.ToggleBar()
    Say("bar " .. (ChainDB.shown and "shown" or "hidden"))
  elseif cmd == "lock" then
    ChainDB.locked = true Say("bar locked")
  elseif cmd == "unlock" then
    ChainDB.locked = false Say("bar unlocked - drag it where you want it")
  elseif cmd == "scale" then
    local v = tonumber(rest)
    if v and v >= 0.5 and v <= 3 then
      ChainDB.scale = v
      if BT.bar then BT.bar:SetScale(v) end
      Say("scale " .. v)
    else
      Say("usage: /chain scale 0.5 - 3")
    end
  elseif cmd == "signal" then
    ChainDB.logSignal = not ChainDB.logSignal
    if ChainDB.logSignal then
      BT.EnableSignal()
      Say("chat logging on, and markers will be written for the watcher script."
        .. " See the push folder in the addon for how to get them to your phone.")
    else
      Say("markers off")
    end
  elseif cmd == "testalert" then
    ChainCharDB.resetAt = time()
    ChainCharDB.resetZone = ChainCharDB.lastZone or "The Stockade"
    ChainCharDB.resetBy = nil
    BT.bannerMuted = nil
    BT.FlagReset(ChainCharDB.resetZone, nil)
    Say("that is what a reset looks and sounds like")
  elseif cmd == "rs" or cmd == "resetinstance" or cmd == "resetinstances" then
    BT.DoReset()
  elseif cmd == "debug" or cmd == "status" then
    local c = ChainCharDB
    Say("zone: " .. tostring(BT.InDungeon() or "outside")
      .. "  boosted: " .. tostring(BT.CurrentBoost())
      .. "  booster: " .. tostring(BT.CurrentBooster()))
    if c.run then
      Say(string.format("run: %s  %s xp  %d mobs  %s  %s%s",
        tostring(c.run.zone), BT.N(c.run.xp or 0), c.run.k or 0,
        BT.T(time() - (c.run.start or time())),
        c.run.partial and "PARTIAL - will not be stored" or "will be stored",
        c.run.reentry and ", same instance" or ""))
    else
      Say("run: none in progress")
    end
    Say(#ChainDB.runs .. " runs stored, " .. #ChainDB.trades
      .. " trades, " .. #ChainDB.entries .. " instance entries")
  elseif cmd == "share" then
    ChainDB.share = not ChainDB.share
    if ChainDB.share then
      BT.JoinShareChannel()
      Say("sharing on - sent " .. BT.ShareAll() .. " entries to other copies of the addon")
    else
      BT.LeaveShareChannel()
      Say("sharing off")
    end
  elseif cmd == "ads" then
    ChainDB.readAds = not ChainDB.readAds
    Say("reading boost adverts from chat is "
      .. (ChainDB.readAds and "on" or "off"))
  elseif cmd == "flush" then
    -- the blunt instrument: close the chat log so everything in the buffer
    -- hits the disk now
    BT.lastFlush = nil
    if BT.FlushChatLog then BT.FlushChatLog() end
    Say("chat log closed and reopened - anything buffered is on disk now")
  elseif cmd == "testpush" then
    -- Proof, end to end: turns the marker on, writes both kinds, and tells
    -- you where to look. If these two lines do not appear in the chat log,
    -- nothing reaches your phone and we know it before a reset does.
    ChainDB.logSignal = true
    ChainDB.snapSignal = true
    BT.EnableSignal()
    BT.Signal("readycheck", "test from /chain testpush")
    BT.lastSnap = nil                 -- the test wants both, back to back
    BT.Signal("reset", "test from /chain testpush")
    -- flush straight away rather than waiting for the timer: this command
    -- exists to be watched
    BT.lastFlush = nil
    if BT.FlushChatLog then BT.FlushChatLog() end
    local on = LoggingChat and LoggingChat() and "on" or "off"
    local where = BT.SignalWhere() or "nowhere - that is the problem"
    Say("wrote two markers. Chat logging is " .. on .. ", channel "
      .. BT.SignalChannel() .. ", shown in: " .. where
      .. ", flushed to disk. Build " .. (BT.VERSION or "?") .. "+snap."
      .. " Also took screenshots as the instant alert - that is the one that "
      .. "should reach your phone in seconds."
      .. " They should be in Logs/WoWChatLog.txt now, and LevelPush should "
      .. "have buzzed your phone twice.")
  elseif cmd == "kos" then
    if rest and rest ~= "" then
      BT.AddKOS(rest)
      Say("marked " .. rest .. " - kill on sight")
    else
      BT.ShowTab("enemies")
    end
  elseif cmd == "enemies" or cmd == "spy" then
    BT.ShowTab("enemies")
  elseif cmd == "pvp" or cmd == "honor" or cmd == "honour" or cmd == "rank" then
    if rest and rest ~= "" then
      local v = tonumber(rest)
      if v then
        ChainCharDB.pvpTarget = math.max(1, math.min(BT.PVP.MAX_RANK, math.floor(v)))
      end
    end
    BT.ShowTab("pvp")
  elseif cmd == "spot" or cmd == "callout" then
    -- the nearest one, or the one you have targeted
    local e
    local want = (rest ~= "" ) and BT.KOSKey(rest) or nil
    for _, x in ipairs(BT.Nearby(ChainDB.nearbySeconds or 60)) do
      if want then
        if x.name == want then e = x break end
      elseif not e then e = x end
    end
    if not e then Say("nobody to call out") return end
    local txt, chan = BT.AnnounceSighting(e, nil, true)
    Say(txt and ("told " .. (chan or "?"):lower() .. ": " .. txt)
             or "could not send that")
  elseif cmd == "nearby" then
    Say("the list on screen is " .. (BT.ToggleNearby() and "on" or "off"))
  elseif cmd == "minimap" then
    Say("minimap button " .. (BT.ToggleMinimap() and "shown" or "hidden"))
  elseif cmd == "importnit" then
    local added = BT.ImportNIT and BT.ImportNIT() or 0
    Say(added > 0
      and ("took " .. added .. " instance entries from NIT into our own log")
      or "nothing new in NIT's log - ours already has it all")
  elseif cmd == "heard" then
    local log = BT.AdLog()
    if #log == 0 then
      Say("no adverts read yet. Boosters advertise in Trade (inside a city) "
        .. "and LookingForGroup; join those channels and stand in a city.")
    else
      Say("the last " .. math.min(#log, 10) .. " adverts read:")
      for i = 1, math.min(#log, 10) do
        local a = log[i]
        local d = a.id and BT.BY_ID[a.id]
        print("   " .. C.dim .. BT.T(time() - (a.at or time())) .. " ago" .. C.off
          .. "  " .. (a.by or "?") .. "  " .. (d and d.label or a.id or "?")
          .. "  " .. C.gold .. BT.G(a.gold or 0)
          .. ((a.pack or 1) > 1 and ("/" .. a.pack .. " runs") or "/run") .. C.off
          .. C.dim .. "  " .. tostring(a.from or "?"):gsub("^channel:", "") .. C.off)
      end
    end
  elseif cmd == "announce" then
    ChainDB.announce = not ChainDB.announce
    Say("reset announcements to the group are "
      .. (ChainDB.announce and "on" or "off"))
  elseif cmd == "export" then
    BT.ShowExport((rest == "gold" or rest == "trade" or rest == "trades")
                  and "trades" or "runs")
  elseif cmd == "gold" or cmd == "spent" then
    local perLevel, spent, levels = BT.SpentPerLevel()
    if not spent or spent == 0 then Say("no trades recorded yet") return end
    Say("paid " .. BT.G(BT.Gold(spent)) .. " in total"
      .. (perLevel and (", " .. BT.G(BT.Gold(perLevel)) .. " per level over "
                        .. levels .. " levels") or ""))
    for _, b in ipairs(BT.SpentByBooster()) do
      Say(string.format("  %s: %s over %d trade%s%s", b.with, BT.G(BT.Gold(b.net)),
        b.n, b.n == 1 and "" or "s", b.booster and " (booster)" or ""))
    end
  elseif cmd == "reset" then
    StaticPopup_Show("CHAIN_WIPE")
  elseif cmd == "stats" then
    local _, step = BT.Stage()
    if not step then Say("no route set - /chain config") return end
    local st, borrowed, by = BT.StepStats(step)
    if not st then Say(step.label .. ": nothing recorded yet") return end
    Say(string.format("%s: %s xp/run, %s per run, %.0f mobs, over %d runs%s",
      step.label, BT.N(st.xp), BT.T(st.t), st.k, st.longN,
      by and (" (" .. by .. ")") or borrowed and " (estimate)" or ""))
    for _, b in ipairs(BT.BoosterTable(step.id)) do
      Say(string.format("  %s: %s xp/h over %d runs", b.by, BT.N(b.rate), b.n))
    end
  else
    Say("commands:")
    print("  /chain            history, boosters and route")
    print("  /chain boosters   straight to the booster list and prices")
    print("  /chain config     pick instances, levels and prices")
    print("  /chain stats      print the current step to chat")
    print("  /chain rs         reset your instances")
    print("  /chain testalert  preview the reset alert")
    print("  /chain signal     write markers for the phone-notification script")
    print("  /chain share      swap prices and thumbs with other addon users")
    print("  /chain ads        read boost adverts out of chat")
    print("  /chain adverts    everyone who has advertised, with whisper")
    print("  /chain groups     everyone looking rather than selling")
    print("  /chain heard      the last adverts the addon picked up")
    print("  /chain testpush   write test markers for the phone program")
    print("  /chain flush      force the chat log out to disk")
    print("  /chain announce   tell the group when the instance resets")
    print("  /chain trade      what you have paid, and to whom")
    print("  /chain pvp        the rank planner - add a number to set a target")
    print("  /chain enemies    everyone seen out there, and the KOS list")
    print("  /chain kos NAME   mark somebody kill on sight")
    print("  /chain nearby     the list of players on screen, on or off")
    print("  /chain spot       call out who is nearby, with where you are")
    print("  /chain minimap    show or hide the minimap button")
    print("  /chain export     every run as CSV (add 'trade' for trades)")
    print("  /chain show       show or hide the bar")
    print("  /chain lock       stop the bar being dragged")
    print("  /chain scale 1.2  resize the bar")
    print("  /chain reset      delete all recorded history")
    print("  /chain debug      what the addon thinks is going on right now")
  end
end
