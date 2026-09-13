-- Chain: static data and the saved-variable schema.
-- Nothing here talks to the game; it is the vocabulary the rest of the addon
-- uses. Keeping it first in the .toc means every other file can rely on it.

local ADDON, BT = ...
_G.Chain = BT
-- the names it used to answer to, so anything written against them still works
_G.LevelBar = BT
_G.LevelTracker = BT
_G.LevelTracker = BT   -- the old name, for anything that looked for it

BT.NAME = "Chain"
BT.VERSION = "1.0.0"

--------------------------------------------------------------------------
-- Experience table
--------------------------------------------------------------------------
-- xp[L] = experience needed to get from level L to level L+1.
-- Original pre-2.3 values: Classic Era never had the 2.3 reduction, so the
-- formula-derived numbers you find in most places are wrong here. These are
-- cross-checked against the live client.
BT.XP = {
  400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
  8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
  25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
  50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
  95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
  153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800
}
BT.MAX_LEVEL = 60

-- The table above is right for Classic Era and the vanilla Anniversary realms.
-- Rather than trust it blindly on a client we have not seen, every level you
-- are actually on is read from the game and remembered, and the remembered
-- value always wins. On a client with a different table the numbers correct
-- themselves as you level through it.
function BT.XPFor(level)
  local db = _G.ChainDB
  local learned = db and db.xpReal and db.xpReal[level]
  return learned or BT.XP[level] or 0
end

--------------------------------------------------------------------------
-- Instances
--------------------------------------------------------------------------
-- id    the key used in the database and in the options
-- mob   the level range of the trash inside, for working out how fast the
--       experience decays as you outlevel the place
-- maps  the instance ids the game reports. These are the real identity of a
--       dungeon: the displayed name is localised and Blizzard renames places
--       (what the table below calls "The Stockade" the current client calls
--       "Stormwind Stockade"), but the id never moves. Names are only a
--       fallback for a client we do not have an id from.
-- zone  a name the game has used for it
-- label what we print
-- lo/hi a sensible default level range, only used to pre-fill the options
-- min   the level the game itself demands before it will let you through the
--       door. Not the same thing as lo: you can be summoned into the Stockade
--       at 15 and be boosted there long before 22, and a booster selling you
--       runs you cannot enter is a wasted evening. Where the sources disagree
--       the higher figure is used, because being told you can go in when you
--       cannot is the worse mistake.
BT.DUNGEONS = {
  { id = "rfc",    zone = "Ragefire Chasm",            label = "RFC",          min = 10, lo = 13, hi = 18, mob = { 13, 17 }, maps = { 389 } },
  { id = "vc",     zone = "The Deadmines",             label = "Deadmines",    min = 10, lo = 15, hi = 21, mob = { 15, 20 }, maps = { 36 } },
  { id = "wc",     zone = "Wailing Caverns",           label = "WC",           min = 10, lo = 15, hi = 22, mob = { 15, 21 }, maps = { 43 } },
  { id = "sfk",    zone = "Shadowfang Keep",           label = "SFK",          min = 14, lo = 18, hi = 25, mob = { 18, 24 }, maps = { 33 } },
  { id = "bfd",    zone = "Blackfathom Deeps",         label = "BFD",          min = 15, lo = 20, hi = 27, mob = { 20, 26 }, maps = { 48 } },
  { id = "stock",  zone = "The Stockade",              label = "Stockades",    min = 15, lo = 22, hi = 30, mob = { 22, 27 }, maps = { 34 } },
  { id = "gnomer", zone = "Gnomeregan",                label = "Gnomeregan",   min = 19, lo = 25, hi = 33, mob = { 25, 32 }, maps = { 90 } },
  { id = "rfk",    zone = "Razorfen Kraul",            label = "RFK",          min = 19, lo = 25, hi = 33, mob = { 26, 32 }, maps = { 47 } },
  { id = "sm",     zone = "Scarlet Monastery",         label = "SM",           min = 21, lo = 28, hi = 42, mob = { 32, 40 }, maps = { 189, 1004 } },
  { id = "rfd",    zone = "Razorfen Downs",            label = "RFD",          min = 25, lo = 33, hi = 40, mob = { 33, 39 }, maps = { 129 } },
  { id = "ulda",   zone = "Uldaman",                   label = "Uldaman",      min = 30, lo = 36, hi = 45, mob = { 36, 44 }, maps = { 70 } },
  { id = "zf",     zone = "Zul'Farrak",                label = "ZF",           min = 35, lo = 42, hi = 48, mob = { 42, 47 }, maps = { 209 } },
  { id = "mara",   zone = "Maraudon",                  label = "Maraudon",     min = 35, lo = 42, hi = 50, mob = { 42, 49 }, maps = { 349 } },
  { id = "st",     zone = "The Temple of Atal'Hakkar", label = "Sunken Temple",min = 35, lo = 48, hi = 54, mob = { 48, 54 }, maps = { 109 } },
  { id = "brd",    zone = "Blackrock Depths",          label = "BRD",          min = 40, lo = 50, hi = 58, mob = { 50, 58 }, maps = { 230 } },
  { id = "dmw",    zone = "Dire Maul",                 label = "DM West",      min = 45, lo = 52, hi = 58, mob = { 55, 58 }, maps = { 429 } },
  { id = "dme",    zone = "Dire Maul",                 label = "DM East",      min = 45, lo = 50, hi = 56, mob = { 51, 56 }, maps = { 429 } },
  { id = "dmn",    zone = "Dire Maul",                 label = "DM North",     min = 45, lo = 54, hi = 60, mob = { 56, 60 }, maps = { 429 } },
  { id = "lbrs",   zone = "Blackrock Spire",           label = "LBRS",         min = 45, lo = 55, hi = 60, mob = { 55, 59 }, maps = { 229 } },
  { id = "ubrs",   zone = "Blackrock Spire",           label = "UBRS",         min = 45, lo = 57, hi = 60, mob = { 58, 60 }, maps = { 229 } },
  { id = "scholo", zone = "Scholomance",               label = "Scholomance",  min = 45, lo = 56, hi = 60, mob = { 56, 60 }, maps = { 289, 1007 } },
  { id = "strat",  zone = "Stratholme",                label = "Stratholme",   min = 45, lo = 56, hi = 60 }
}

BT.BY_ID = {}
BT.BY_ZONE = {}
BT.BY_MAP = {}
for _, d in ipairs(BT.DUNGEONS) do
  BT.BY_ID[d.id] = d
  BT.BY_ZONE[d.zone] = BT.BY_ZONE[d.zone] or {}
  table.insert(BT.BY_ZONE[d.zone], d)
  for _, m in ipairs(d.maps or {}) do
    BT.BY_MAP[m] = BT.BY_MAP[m] or {}
    table.insert(BT.BY_MAP[m], d)
  end
end

-- Names are compared loosely, because the same place is "The Stockade" in one
-- client and "Stormwind Stockade" in another. Strip the decoration and see if
-- one is contained in the other.
local function Normalise(name)
  if type(name) ~= "string" then return nil end
  local n = name:lower():gsub("[^%a%s]", ""):gsub("^the%s+", ""):gsub("%s+", " ")
  return (n:gsub("^%s*(.-)%s*$", "%1"))
end
BT.Normalise = Normalise

function BT.DungeonsForZone(zone)
  if BT.BY_ZONE[zone] then return BT.BY_ZONE[zone] end
  local want = Normalise(zone)
  if not want or want == "" then return nil end
  for z, list in pairs(BT.BY_ZONE) do
    local have = Normalise(z)
    if have == want or have:find(want, 1, true) or want:find(have, 1, true) then
      return list
    end
  end
  return nil
end

-- The dungeons this instance could be, id first and name only as a fallback
function BT.DungeonsFor(map, zone)
  if map and BT.BY_MAP[map] then return BT.BY_MAP[map] end
  return BT.DungeonsForZone(zone)
end

-- Short names for the places we print inside a sentence
BT.SHORT = {
  ["The Stockade"] = "Stockades", ["Scarlet Monastery"] = "SM",
  ["Ragefire Chasm"] = "RFC", ["Wailing Caverns"] = "WC",
  ["Blackfathom Deeps"] = "BFD", ["Shadowfang Keep"] = "SFK",
  ["The Deadmines"] = "Deadmines", ["Gnomeregan"] = "Gnomeregan",
  ["Razorfen Kraul"] = "RFK", ["Razorfen Downs"] = "RFD",
  ["Uldaman"] = "Uldaman", ["Zul'Farrak"] = "ZF", ["Maraudon"] = "Maraudon",
  ["The Temple of Atal'Hakkar"] = "Sunken Temple", ["Blackrock Depths"] = "BRD",
  ["Blackrock Spire"] = "Blackrock Spire", ["Dire Maul"] = "Dire Maul",
  ["Scholomance"] = "Scholomance", ["Stratholme"] = "Stratholme"
}

--------------------------------------------------------------------------
-- Tuning
--------------------------------------------------------------------------
-- What people actually type in chat. The table above holds proper names; an
-- advert says "Mara boost" or "SM Cath & Arm", and a booster who cannot be
-- matched to an instance is a booster you never hear about.
BT.ALIAS = {
  rfc = "rfc", ragefire = "rfc",
  vc = "vc", deadmines = "vc",
  wc = "wc", wailing = "wc",
  sfk = "sfk", shadowfang = "sfk",
  bfd = "bfd", blackfathom = "bfd",
  stocks = "stock", stockade = "stock", stockades = "stock",
  gnomer = "gnomer", gnome = "gnomer", gnomeregan = "gnomer",
  rfk = "rfk", kraul = "rfk",
  sm = "sm", monastery = "sm", cath = "sm", cathedral = "sm", armory = "sm",
  arm = "sm", library = "sm", lib = "sm", graveyard = "sm",
  rfd = "rfd", downs = "rfd",
  ulda = "ulda", uldaman = "ulda",
  zf = "zf", farrak = "zf", zulfarrak = "zf",
  mara = "mara", maraudon = "mara",
  st = "st", sunken = "st", atal = "st",
  brd = "brd", depths = "brd",
  dmw = "dmw", dme = "dme", dmn = "dmn",
  lbrs = "lbrs", ubrs = "ubrs",
  scholo = "scholo", scholomance = "scholo",
  strat = "strat", stratholme = "strat"
}

BT.K = {
  -- somebody this far above you is boosting, not grouping
  BOOST_GAP = 10,
  -- runs needed before a booster is judged on his own numbers
  BOOSTER_MIN = 3,
  -- how many recent runs the rolling average uses
  WINDOW = 5,
  -- instances allowed per hour, per character
  LIMIT = 5,
  -- There is no hard daily cap any more - five per hour is the only limit
  -- that stops you. The 24 hour count is kept because it is worth knowing how
  -- hard you have been going, but it is not a ceiling and is not shown on the
  -- bar unless you ask for one.
  DAILY = 0,
  -- the experience rate is stale after this many minutes without a gain
  IDLE_MIN = 10,
  -- ...but five when you are on your own. In a group a long gap is a reset, a
  -- summon or somebody's dog; alone it is you not being there.
  IDLE_SOLO = 5,
  -- a gap this long ends the session
  SESSION_GAP = 1800,
  -- how many runs to keep in the log before the oldest are dropped
  MAX_RUNS = 2000,
  -- likewise for trades
  MAX_TRADES = 1000,
  -- party experience multiplier by group size
  GROUP_BONUS = { [1] = 1, [2] = 1, [3] = 1.166, [4] = 1.3, [5] = 1.4 }
}

BT.COL = {
  good = "|cff66ff66", bad = "|cffff7a7a", warn = "|cffffd100",
  dim = "|cffcfcfcf", gold = "|cffffd100", rested = "|cff40a0ff",
  info = "|cff9fd3ff", alert = "|cffffb040", off = "|r"
}

--------------------------------------------------------------------------
-- The face everything is written in
--------------------------------------------------------------------------
-- Friz Quadrata is the game's own face and it is a display face: made for
-- carved signs and quest titles, not for a column of numbers at nine pixels.
-- At that size its serifs turn to mush, and this addon is almost entirely
-- small text in rows.
--
-- So everything we draw goes through five font objects of our own rather than
-- the game's. A font object is shared by every string using it, so changing
-- the face on these five changes every label in the addon at once - live, with
-- no reload - and it leaves the rest of the interface alone.
--
-- The client ships four faces and all of them are compromises here: Friz
-- Quadrata is a display face, Arial Narrow is narrow (thin strokes on a dark
-- background are the first thing to go at small sizes), Morpheus and Skurri
-- are for titles and damage numbers. So one comes with the addon. DejaVu Sans
-- is even, sturdy and made to be read small, it covers every accent a
-- character name can carry, and the Bitstream Vera licence it comes under lets
-- it be shipped like this - the licence is next to it in Fonts/.
BT.FACES = {
  { key = "sans", name = "DejaVu Sans",
    path = "Interface\\AddOns\\Chain\\Fonts\\DejaVuSans.ttf", nudge = -1,
    note = "even and solid at small sizes - comes with the addon" },
  { key = "game", name = "Game default",
    path = "Fonts\\FRIZQT__.TTF", nudge = 0,
    note = "Friz Quadrata, the same as the rest of the interface" },
  { key = "arial", name = "Arial Narrow",
    path = "Fonts\\ARIALN.TTF", nudge = 1,
    note = "narrow - fits more in a row, thinner to read" },
  { key = "skurri", name = "Skurri",
    path = "Fonts\\skurri.ttf", nudge = 0,
    note = "the damage numbers face - heavier, squarer" },
}

local FONTS = {
  ChainFontNormal        = "GameFontNormal",
  ChainFontNormalSmall   = "GameFontNormalSmall",
  ChainFontNormalLarge   = "GameFontNormalLarge",
  ChainFontHighlightSmall = "GameFontHighlightSmall",
  ChainFontDisableSmall  = "GameFontDisableSmall",
}

function BT.Face()
  local want = ChainDB and ChainDB.face
  for _, f in ipairs(BT.FACES) do if f.key == want then return f end end
  return BT.FACES[1]
end

-- Build them if they are not there yet, then point them at the chosen face.
-- The size comes from the game's own object of the same name, so a face swap
-- does not quietly resize half the addon; the nudge is per face, because a
-- narrow face at the same point size reads a shade smaller.
function BT.ApplyFont()
  if type(CreateFont) ~= "function" then return end
  local face = BT.Face()
  for mine, theirs in pairs(FONTS) do
    local obj = _G[mine]
    if not obj then
      obj = CreateFont(mine)
      local from = _G[theirs]
      if from and obj.SetFontObject then obj:SetFontObject(from) end
      obj.__from = theirs
    end
    local from = _G[obj.__from or theirs]
    local _, size, flags
    if from and from.GetFont then _, size, flags = from:GetFont() end
    if obj.SetFont then
      obj:SetFont(face.path, (size or 10) + (face.nudge or 0), flags or "")
    end
  end
  return face
end

function BT.SetFace(key)
  ChainDB.face = key
  local face = BT.ApplyFont()
  -- the bar packs its lines to a character count measured in the old face
  if BT.ForgetBudget then BT.ForgetBudget() end
  if BT.Refresh then BT.Refresh() end
  return face
end

--------------------------------------------------------------------------
-- Defaults
--------------------------------------------------------------------------
-- The route is a plain list of steps. Each dungeon can appear once; you tick
-- it and give it a level span and a price, exactly like the old options.
BT.DEFAULTS = {
  version = 1,
  ownSteps = {},       -- stretches you do the yourself: label, from, to
  groups = {},         -- LFM/LFG/WTB posts read from chat, oldest first
  readGroups = true,   -- read them at all; the channels are the same ones
  route = {},          -- [id] = { on = bool, from = n, to = n, gold = n,
                       --          pack = runs one price buys here, nil = use
                       --          the global figure below }
  pack = 5,            -- how many runs one price covers, where nothing more
                       -- specific is set
  limit = 5,           -- instances per hour, per character
  daily = 0,           -- optional daily ceiling; 0 means there is none
  window = 5,          -- runs in the rolling average
  -- The group cannot see your lockout: they see you not going in. This says
  -- it for you, once when you are stuck and once when you are not.
  announceLock = true,
  sound = true,        -- play a sound on instance reset
  soundRepeat = 3,     -- how many times; you are not always at the keyboard
  -- Two different sounds, because the reset means two opposite things: get
  -- out if you are still inside, get back in if you are not. One sound for
  -- both makes you look at the screen to find out which; two do not.
  soundIn = "levelup",     -- reset and you are outside: go in
  soundOut = "warning",    -- reset and you are still inside: zone out
  -- Off: the line on the bar says the same thing without covering anything.
  -- Left in for anyone who wants it, but the text is enough.
  banner = false,
  -- Writes a marker line into WoW's own chat log so a watcher program outside
  -- the game can turn it into a phone notification. Off by default; it is for
  -- people who set up the companion script.
  logSignal = false,
  snapSignal = false,   -- a screenshot as the instant alert for the phone
  resets = {},         -- every reset we were told about: our own record
  -- Who is out there. Watching is on, shouting about strangers is not: the
  -- ones you marked are worth an alarm whether or not you asked, and everyone
  -- else is worth an alarm only if you did.
  watchEnemies = true,
  alertEveryone = false,
  enemySound = true,
  kos = {},            -- kill on sight, by name
  kosGuilds = {},      -- and by whole guild, which is usually how it goes
  enemies = {},        -- everyone seen, account-wide
  nearbyList = true,   -- the small list on screen
  nearbySeconds = 60,  -- how long a sighting counts as "nearby"
  nearbyPos = nil,     -- where you dragged it
  minimap = true,      -- the button on the minimap
  minimapAngle = 205,  -- where round the edge you left it
  -- Off. NIT's history is imported into our own log once, and after that we
  -- see every zone-in ourselves; reading its count live only matters if you
  -- would rather trust it than us.
  useNIT = false,
  announce = false,    -- somebody else reset: tell the group. Off - his
                       -- addon has almost certainly said it already.
  announceReset = true,-- your own reset: tell the group. On - nobody else is
                       -- told at all, so this is the one that is news.
  readAds = true,      -- pick boosters and their prices out of chat adverts
  share = false,       -- swap measurements with other people's addons
  shareWith = "all",   -- "all" (everyone running it), "guild", or "friends"
  shareFriends = {},   -- names, for the friends scope
  locked = false,
  scale = 1,
  width = 380,
  shown = true,
  point = { "CENTER", nil, "CENTER", 0, 200 },
  xpReal = {},         -- experience per level as this client reports it
  entries = {},        -- instance entries for every character on the account
  -- what you have been told a booster charges.
  -- [name] = { price = gold, pack = runs that price covers }
  boosters = {},
  runs = {},           -- every completed run, newest last
  trades = {},         -- every completed trade, newest last
  entries = {},        -- instance entries, for the 5-per-hour limit
  session = nil
}

-- Deep-fill missing keys without touching what the user already has
function BT.ApplyDefaults(db, defaults)
  for k, v in pairs(defaults) do
    if db[k] == nil then
      if type(v) == "table" then
        local copy = {}
        BT.ApplyDefaults(copy, v)
        db[k] = copy
      else
        db[k] = v
      end
    elseif type(v) == "table" and type(db[k]) == "table" then
      BT.ApplyDefaults(db[k], v)
    end
  end
  return db
end

--------------------------------------------------------------------------
-- What an ability says about the man who used it
--------------------------------------------------------------------------
-- The combat log carries no level. That is the whole reason a rogue you have
-- fought fifteen times sits in the list as "??": we only ever learn a level
-- from a nameplate or from having him targeted, and a stealther who opens on
-- you and vanishes gives neither.
--
-- What the log does carry is what he cast, and an ability cannot be used
-- before it can be learned. So every one of these is a floor - "at least
-- this" - never a level, and the list only ever raises it.
--
-- Two kinds of entry, and both are chosen to be things worth being sure of:
--
--   1. Every class's 31-point talents. A talent that deep needs thirty-one
--      points, and thirty-one points needs level forty. There is no way round
--      that rule and no rank of the spell below it, so every one of these is
--      a flat 40 whatever else is true.
--   2. A short list of baseline abilities whose first rank is high enough to
--      be worth saying. Rank one is what is stored, because the log line
--      names the spell and not the rank: "Kidney Shot" is 30 whether it was
--      the level 30 rank or the level 60 one.
--
-- Matched on the name rather than the spell id on purpose. Ids are per rank
-- and there are thousands of them; a wrong id here would quietly claim
-- somebody is forty when he is twelve, and a name either matches or does not.
-- Where Spy is installed its own per-rank table is better than this and is
-- used first; this is what fills the column in for everybody else.
BT.ABILITY_LEVEL = {
  -- 31-point talents: thirty-one points is level forty, every class
  ["Adrenaline Rush"] = 40, ["Blade Flurry"] = 40, ["Preparation"] = 40,
  ["Cold Blood"] = 40,
  ["Mortal Strike"] = 40, ["Bloodthirst"] = 40, ["Shield Slam"] = 40,
  ["Death Wish"] = 40,
  ["Bestial Wrath"] = 40, ["Trueshot Aura"] = 40, ["Wyvern Sting"] = 40,
  ["Presence of Mind"] = 40, ["Combustion"] = 40, ["Ice Barrier"] = 40,
  ["Dark Pact"] = 40, ["Conflagrate"] = 40,
  ["Power Infusion"] = 40, ["Lightwell"] = 40, ["Shadowform"] = 40,
  ["Nature's Swiftness"] = 40, ["Elemental Mastery"] = 40,
  ["Stormstrike"] = 40,
  ["Innervate"] = 40,
  ["Holy Shock"] = 40, ["Repentance"] = 40, ["Blessing of Sanctuary"] = 40,

  -- baseline abilities, at the level their first rank is learned
  ["Blind"] = 34, ["Kidney Shot"] = 30, ["Vanish"] = 22, ["Cheap Shot"] = 18,
  ["Distract"] = 22, ["Rupture"] = 20, ["Kick"] = 16, ["Ambush"] = 18,
  ["Whirlwind"] = 30, ["Intimidating Shout"] = 22,
  ["Feign Death"] = 30,
  ["Ice Block"] = 30, ["Evocation"] = 32, ["Blink"] = 20,
  ["Cone of Cold"] = 26,
  ["Death Coil"] = 42, ["Soul Fire"] = 48, ["Howl of Terror"] = 40,
  ["Chain Lightning"] = 32,
  ["Hammer of Justice"] = 20,
}

-- The floor an ability puts under somebody, by name. nil when we have nothing
-- to say, which is most abilities and is the honest answer.
function BT.AbilityLevelByName(spellName)
  if type(spellName) ~= "string" then return nil end
  return BT.ABILITY_LEVEL[spellName]
end
