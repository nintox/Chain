-- Functional tests for the addon, against the fake client.
--
-- Finds the addon by looking for Chain.toc, starting beside this file and
-- working outwards, so the tests run wherever the tree happens to sit: inside
-- the addon folder as the repository has it, or beside it in a working copy.
local function scriptDir()
  local src = debug.getinfo(1, "S").source:sub(2)
  return src:match("^(.*)[/\\][^/\\]*$") or "."
end
local HERE = scriptDir()
local function exists(path)
  local fh = io.open(path, "r")
  if fh then fh:close() return true end
  return false
end
local DIR
for _, cand in ipairs({ HERE .. "/../", HERE .. "/../Chain/", HERE .. "/" }) do
  if exists(cand .. "Chain.toc") then DIR = cand break end
end
assert(DIR, "cannot find Chain.toc from " .. HERE)
package.path = HERE .. "/?.lua;" .. package.path
local S = dofile(HERE .. "/wowstub.lua")
local BT = {}
local function loadFile(name)
  local chunk, err = loadfile(DIR .. name)
  assert(chunk, name .. ": " .. tostring(err))
  chunk("Chain", BT)
end

-- the .toc order
for _, f in ipairs({ "Data.lua", "Stats.lua", "Decay.lua", "Core.lua", "Trade.lua",
                     "PvP.lua", "Roster.lua", "Bar.lua", "Minimap.lua", "Window.lua",
                     "Options.lua" }) do
  loadFile(f)
end

local frame = BT.frame
S.Fire(frame, "ADDON_LOADED", "Chain")

local pass, fail = 0, 0
local function ok(cond, msg)
  if cond then pass = pass + 1
  else fail = fail + 1 print("  FAIL: " .. msg) end
end
local function eq(a, b, msg)
  ok(a == b, msg .. "  (fekk " .. tostring(a) .. ", venta " .. tostring(b) .. ")")
end
local function near(a, b, msg, tol)
  ok(a and math.abs(a - b) <= (tol or 0.5), msg .. "  (fekk " .. tostring(a)
     .. ", venta " .. tostring(b) .. ")")
end

--------------------------------------------------------------------------
print("== oppsett ==")
ok(ChainDB ~= nil, "DB laga")
eq(#BT.DUNGEONS, 22, "22 instansar")
-- kryssjekka mot klienten: level 18 viser 19 400
eq(BT.Span(18, 19), 19400, "xp 18->19")
eq(BT.Span(1, 2), 400, "xp 1->2")
eq(BT.Span(59, 60), 209800, "xp 59->60")
eq(BT.Span(20, 22), 23200 + 25200, "xp over to level")

-- klienten skal overstyre den innebygde tabellen
S.level, S.xpMax = 20, 23200
BT.LearnXP()
eq(ChainDB.xpReal[20], nil, "eitt syn er ikkje nok")
BT.LearnXP()
eq(ChainDB.xpReal[20], 23200, "lærer xp frå klienten")
eq(BT.XPFor(20), 23200, "same som tabellen, ingen endring")
-- halvvegs oppdatert tilstand midt i eit ding skal ikkje lagrast
S.level, S.xpMax = 21, 23200
BT.LearnXP()
S.xpMax = 20000                    -- ein klient med annan tabell
BT.LearnXP()
eq(ChainDB.xpReal[21], nil, "half-ferdig ding blir ikkje lagra")
BT.LearnXP()
eq(BT.XPFor(21), 20000, "klienten vinn over tabellen")
eq(BT.Span(20, 22), 23200 + 20000, "Span brukar lærte verdiar")
ChainDB.xpReal[21] = nil
BT.warnedXP = nil
S.level, S.xpMax = 20, 23200

ChainDB.route.stock = { on = true, from = 18, to = 26, gold = 50 }
ChainDB.pack = 5
eq(#BT.Plan(), 1, "ruta har eitt steg")

--------------------------------------------------------------------------
print("== ein boost-run ==")
S.level, S.xp, S.xpMax = 20, 0, 23200
S.party = { { name = "Misscall-Firemaw", lvl = 60 } }
S.zone, S.map, S.inInstance = "The Stockade", 34, true
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
ok(ChainCharDB.run ~= nil, "run starta")
eq(ChainCharDB.run.by, "Misscall", "booster identifisert utan realm")
eq(ChainCharDB.run.id, "stock", "run knytt til steget")

-- ti drap og litt xp
for i = 1, 10 do
  S.xp = S.xp + 900
  S.Fire(frame, "PLAYER_XP_UPDATE")
  S.Fire(frame, "CHAT_MSG_COMBAT_XP_GAIN")
end
eq(ChainCharDB.run.xp, 9000, "xp samla i runden")
eq(ChainCharDB.run.k, 10, "mobs talde")

S.now = S.now + 420
S.zone, S.inInstance = "Stormwind City", false
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
eq(#ChainDB.runs, 1, "runden lagra")
eq(ChainDB.runs[1].xp, 9000, "lagra xp")
eq(ChainDB.runs[1].t, 420, "lagra tid")
eq(ChainDB.runs[1].by, "Misscall", "lagra booster")

--------------------------------------------------------------------------
print("== level-opp midt i ein run ==")
S.level, S.xp, S.xpMax = 20, 0, 23200
S.zone, S.map, S.inInstance = "The Stockade", 34, true
S.now = S.now + 60
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
S.xp = 22000
S.Fire(frame, "PLAYER_XP_UPDATE")
eq(ChainCharDB.run.xp, 22000, "xp før dinget")
-- ding: resten av den gamle baren (1 200) pluss det som ligg på den nye (1 500)
S.level, S.xpMax, S.xp = 21, 25200, 1500
S.Fire(frame, "PLAYER_LEVEL_UP")
eq(ChainCharDB.run.xp, 22000 + 1200 + 1500, "xp over eit level-opp")
-- og hendinga skal ikkje telje dobbelt om begge kjem
S.Fire(frame, "PLAYER_XP_UPDATE")
eq(ChainCharDB.run.xp, 24700, "ingen dobbeltteljing")
S.now = S.now + 400
S.zone, S.inInstance = "Stormwind City", false
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
eq(#ChainDB.runs, 2, "run nr 2 lagra")

--------------------------------------------------------------------------
-- Nøyaktig hendingsrekkja klienten gjev: eit lasteskjermbilete BÅDE inn og ut
print("== ekte inn- og utsoning (lasteskjerm begge vegar) ==")
ChainDB.runs = {}
ChainCharDB.run = nil
S.level, S.xp, S.xpMax = 20, 0, 23200
S.party = { { name = "Misscall-Firemaw", lvl = 60 } }

-- inn: PLAYER_ENTERING_WORLD med begge flagg false, så zone-endringa
S.zone, S.map, S.inInstance = "The Stockade", 34, true
S.Fire(frame, "PLAYER_ENTERING_WORLD", false, false)
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
ok(ChainCharDB.run ~= nil, "run starta ved insoning")
eq(ChainCharDB.run.partial, nil, "vanleg insoning er ikkje partial")

for i = 1, 8 do
  S.xp = S.xp + 1000
  S.Fire(frame, "PLAYER_XP_UPDATE")
  S.Fire(frame, "CHAT_MSG_COMBAT_XP_GAIN")
end
S.now = S.now + 400

-- ut: lasteskjerm igjen
S.zone, S.inInstance = "Stormwind City", false
S.Fire(frame, "PLAYER_ENTERING_WORLD", false, false)
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
eq(#ChainDB.runs, 1, "runden hamna i historikken")
eq(ChainDB.runs[1].xp, 8000, "med rett xp")
eq(ChainDB.runs[1].k, 8, "og rett mobs")
eq(ChainDB.runs[1].by, "Misscall", "og boosteren")

-- innlogging midt inne i ein instans er framleis partial og blir ikkje lagra
S.zone, S.map, S.inInstance = "The Stockade", 34, true
S.Fire(frame, "PLAYER_ENTERING_WORLD", true, false)
eq(ChainCharDB.run.partial, true, "innlogging inne = partial")
S.xp = S.xp + 3000
S.Fire(frame, "PLAYER_XP_UPDATE")
S.now = S.now + 300
S.zone, S.inInstance = "Stormwind City", false
S.Fire(frame, "PLAYER_ENTERING_WORLD", false, false)
eq(#ChainDB.runs, 1, "halv run blir ikkje lagra")

-- og ein /reload utanfor skal ikkje skade noko
S.Fire(frame, "PLAYER_ENTERING_WORLD", false, true)
eq(#ChainDB.runs, 1, "reload utanfor endrar ingenting")

ChainDB.runs = {}


--------------------------------------------------------------------------
print("== per-booster prognose ==")
ChainDB.runs = {}
local function record(by, xp, secs, kills)
  table.insert(ChainDB.runs, { at = S.now, t = secs, zone = "The Stockade",
    id = "stock", by = by, xp = xp, k = kills, lvl = 20, grp = 2, grpAvg = 40 })
  S.now = S.now + secs + 60
end
for i = 1, 4 do record("Misscall", 9000, 420, 90) end
for i = 1, 4 do record("Torkel", 5000, 720, 55) end

S.level, S.xp = 20, 0
S.party = { { name = "Misscall-Firemaw", lvl = 60 } }
local _, step = BT.Stage()
local st, borrowed, who = BT.StepStats(step)
eq(who, "Misscall", "brukar Misscall sine tal")
near(st.xp, 9000, "Misscall xp/run")
local fastRuns = BT.Forecast()

S.party = { { name = "Torkel-Firemaw", lvl = 60 } }
st, borrowed, who = BT.StepStats(step)
eq(who, "Torkel", "brukar Torkel sine tal")
near(st.xp, 5000, "Torkel xp/run")
local slowRuns = BT.Forecast()
ok(slowRuns > fastRuns * 1.5, "treg booster gjev mange fleire runs")
print(string.format("   Misscall %.1f runs, Torkel %.1f runs", fastRuns, slowRuns))

-- ny booster utan nok data
S.party = { { name = "Ny-Firemaw", lvl = 60 } }
st, borrowed, who = BT.StepStats(step)
eq(who, nil, "under 3 runs gjev ikkje eigne tal")
record("Ny", 7000, 600, 70); record("Ny", 7000, 600, 70); record("Ny", 7000, 600, 70)
st, borrowed, who = BT.StepStats(step)
eq(who, "Ny", "3 runs er nok")
near(st.xp, 7000, "Ny xp/run")

--------------------------------------------------------------------------
-- Klienten kallar staden "Stormwind Stockade", tabellen vår "The Stockade".
-- Identiteten er kart-ID-en, ikkje namnet.
print("== instansen blir kjend att på id, ikkje namn ==")
eq(BT.DungeonsFor(34, "Stormwind Stockade")[1].id, "stock", "id 34 er Stockades")
eq(BT.DungeonsFor(nil, "Stormwind Stockade")[1].id, "stock", "nytt namn matchar likevel")
eq(BT.DungeonsFor(nil, "The Stockade")[1].id, "stock", "gamalt namn matchar")
eq(BT.DungeonsFor(nil, "Scarlet Monastery")[1].id, "sm", "SM")
eq(BT.DungeonsFor(429, nil)[1].id ~= nil, true, "Dire Maul har fleire steg på same id")
eq(BT.DungeonsFor(nil, "Ironforge"), nil, "ein by er ingen instans")
eq(BT.Short("Stormwind Stockade"), "Stockades", "kort namn frå tabellen")

-- ein run under det nye namnet skal hamne på rett steg
local keepRuns = ChainDB.runs
ChainDB.runs = {}
BT.Touch()
ChainCharDB.run = nil
S.level, S.xp, S.xpMax = 20, 0, 23200
S.party = { { name = "Misscall-Firemaw", lvl = 60 } }
S.zone, S.map, S.inInstance = "Stormwind Stockade", 34, true
S.Fire(frame, "PLAYER_ENTERING_WORLD", false, false)
eq(ChainCharDB.run.id, "stock", "runden knytt til steget trass nytt namn")
eq(ChainCharDB.run.map, 34, "kart-id lagra")
S.xp = S.xp + 8000
S.Fire(frame, "PLAYER_XP_UPDATE")
S.now = S.now + 300
S.zone, S.inInstance = "Stormwind City", false
S.Fire(frame, "PLAYER_ENTERING_WORLD", false, false)
eq(ChainDB.runs[1].id, "stock", "og lagra med steget")
eq(#BT.Runs({ id = "stock" }), 1, "Boosters-fana finn den")
local stx, borrowedx = BT.StepStats(select(2, BT.Stage()))
eq(borrowedx, false, "Route brukar eigne tal, ikkje eit anslag")

-- gamle runs utan id skal få det ved innlasting
table.insert(ChainDB.runs, { at = S.now, t = 300, zone = "Stormwind Stockade",
  by = "Algorismus", xp = 8565, k = 93, lvl = 26 })
BT.Touch()
eq(#BT.Runs({ id = "stock" }), 1, "gammal run manglar steg")
S.Fire(frame, "ADDON_LOADED", "Chain")
eq(#BT.Runs({ id = "stock" }), 2, "og blir reparert ved innlasting")
ChainDB.runs = keepRuns
BT.Touch()
S.map = nil

--------------------------------------------------------------------------
print("== boost eller ikkje ==")
S.party = { { name = "Kompis", lvl = 21 }, { name = "Annan", lvl = 19 } }
eq(BT.Booster(), nil, "jamn gruppe har ingen booster")
eq(BT.CurrentBoost(), false, "jamn gruppe er ikkje boost")
S.party = { { name = "Misscall-Firemaw", lvl = 60 } }
eq(BT.CurrentBoost(), true, "60 i gruppa er boost")
S.party = {}
eq(BT.CurrentBoost(), true, "aleine = planlegging som boost")

-- eigne runs hamnar i si eiga bøtte
S.party = { { name = "Kompis", lvl = 21 } }
S.zone, S.map, S.inInstance = "The Stockade", 34, true
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
eq(ChainCharDB.run.by, nil, "ingen booster i runden")
S.xp = S.xp + 2000
S.Fire(frame, "PLAYER_XP_UPDATE")
S.now = S.now + 1500
S.zone, S.inInstance = "Stormwind City", false
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
S.party = { { name = "Kompis", lvl = 21 } }
local ownStats = BT.StepStats(step)
near(ownStats.xp, 2000, "eigne runs blandar seg ikkje med boost")
S.party = { { name = "Misscall-Firemaw", lvl = 60 } }
local boostStats = BT.StepStats(step)
near(boostStats.xp, 9000, "boost-tala er urørte")

--------------------------------------------------------------------------
print("== gruppesamansetjing ==")
S.level = 20
S.party = { { name = "A", lvl = 20 }, { name = "B", lvl = 20 },
            { name = "C", lvl = 20 }, { name = "D", lvl = 20 } }
local avg, n, ratio = BT.GroupInfo()
eq(n, 5, "fem i gruppa")
near(avg, 20, "snitt 20")
ok(ratio > 0.99, "jamn gruppe er på maks (fekk " .. string.format("%.2f", ratio) .. ")")
S.party = { { name = "V", lvl = 60 }, { name = "A", lvl = 20 },
            { name = "B", lvl = 20 }, { name = "C", lvl = 20 } }
avg, n, ratio = BT.GroupInfo()
ok(ratio > 0.99, "boost med boostier på ditt level er òg på maks")
S.party = { { name = "V", lvl = 60 }, { name = "A", lvl = 45 },
            { name = "B", lvl = 45 }, { name = "C", lvl = 45 } }
avg, n, ratio = BT.GroupInfo()
ok(ratio < 0.75, "høge boostier kostar deg xp (" .. string.format("%.2f", ratio) .. ")")

--------------------------------------------------------------------------
print("== instance-lockout ==")
ChainDB.entries = {}
ChainCharDB.entrySeq = 0
for i = 1, 5 do BT.NoteEntry() end
local count, freeOne, freeAll, fromNIT, daily = BT.Lockout()
eq(count, 5, "fem instansar")
eq(daily, 5, "fem i døgnet òg")
eq(fromNIT, false, "utan NIT brukar vi vår eigen logg")
ok(freeOne and freeOne > 3500, "nedteljing til neste ledige")

-- timesgrensa er per karakter, døgngrensa er kontovid
for i = 1, 7 do
  table.insert(ChainDB.entries,
    { t = S.now - 7200 - i * 60, seq = "Alt:" .. i, char = "Alt" })
end
table.insert(ChainDB.entries, { t = S.now - 300, seq = "Alt:x", char = "Alt" })
count, freeOne, freeAll, fromNIT, daily = BT.Lockout()
eq(count, 5, "alten sine instansar tel ikkje mot timen min")
eq(daily, 13, "men dei tel mot døgnet")

-- meir enn eit døgn gammalt fell ut
table.insert(ChainDB.entries, { t = S.now - 90000, seq = "Alt:g", char = "Alt" })
daily = select(5, BT.Lockout())
eq(daily, 13, "eldre enn 24 timar tel ikkje")

-- NIT er valfri. Det einaste den har som vi ikkje kan sjå sjølve, er
-- inngangar frå før addonen blei installert - så dei blir henta over i vår
-- eigen logg ein gong, og etter det treng vi den ikkje.
_G.NIT = { data = { instances = {
  { enteredTime = S.now - 100, zone = "The Stockade", playerName = "Tester" },
  { enteredTime = S.now - 200, zone = "The Stockade", playerName = "Tester" },
  { enteredTime = S.now - 4000, zone = "SM", playerName = "Tester" },
  { enteredTime = S.now - 50000, zone = "SM", playerName = "Tester" } } } }
ChainDB.useNIT = false
local before = #ChainDB.entries
local added = BT.ImportNIT()
eq(added, 4, "alle fire blei henta over")
eq(#ChainDB.entries, before + 4, "og ligg i vår eigen logg")
eq(BT.ImportNIT(), 0, "ein ny import legg ikkje til det same igjen")
local fromNITrow = nil
for _, e in ipairs(BT.InstanceLog()) do
  if e.nit then fromNITrow = e end
end
ok(fromNITrow ~= nil, "og er merka som henta frå NIT")
-- og no tel dei som våre eigne, utan at NIT er involvert
_G.NIT = nil
count, freeOne, freeAll, fromNIT, daily = BT.Lockout()
eq(fromNIT, false, "ingenting blir lese frå NIT lenger")
ok(count >= 7, "dei importerte tel med i timen (" .. count .. ")")

-- den som heller vil lese NIT direkte kan framleis slå det på
_G.NIT = { data = { instances = {
  { enteredTime = S.now - 100 }, { enteredTime = S.now - 200 },
  { enteredTime = S.now - 4000 }, { enteredTime = S.now - 50000 } } } }
ChainDB.useNIT = true
count, freeOne, freeAll, fromNIT, daily = BT.Lockout()
eq(count, 2, "då tel NIT berre den siste timen")
eq(daily, 4, "og NIT sitt døgntal")
eq(fromNIT, true, "merka som NIT-data")
ChainDB.useNIT = false
_G.NIT = nil

-- spelet sitt eige svar slår aritmetikken vår: vi ser berre dei inngangane
-- vi køyrde for, det ser alle saman
ChainDB.entries = {}
ChainCharDB.lockedAt, ChainCharDB.lockMissing = nil, nil
for i = 1, 2 do
  table.insert(ChainDB.entries, { t = S.now - 100 * i, seq = "m" .. i,
                                     char = "Tester" })
end
eq(BT.Lockout(), 2, "vi har talt to")
ok(BT.LooksLikeLockout("You have entered too many instances recently."),
   "meldinga blir kjend att")
S.Fire(frame, "CHAT_MSG_SYSTEM", "You have entered too many instances recently.")
count, freeOne, freeAll, fromNIT, daily, fromGame = BT.Lockout()
eq(count, 5, "men spelet seier fem, og då er det fem")
eq(fromGame, true, "og det er merka som spelet sitt svar")
ok(freeOne and freeOne > 0, "med ei øvre grense for når det losnar")
-- og det går ut av seg sjølv
S.now = S.now + 3700
eq(BT.LockedByGame(), nil, "svaret frå spelet varer ikkje evig")
S.now = S.now - 3700
ChainCharDB.lockedAt, ChainCharDB.lockMissing = nil, nil

-- instansloggen, slik Instances-fana les den
ChainDB.entries = {}
ChainCharDB.entrySeq = 0
S.zone, S.map, S.inInstance = "Stormwind Stockade", 34, true
for i = 1, 3 do BT.NoteEntry() end
S.inInstance = false
local log = BT.InstanceLog()
eq(#log, 3, "tre oppføringar i loggen")
eq(log[1].counts, true, "ferske tel mot timen")
eq(BT.Short(log[1].zone), "Stockades", "instansnamnet med i loggen")
ok(log[1].left > 3500, "nedteljing per oppføring")
table.insert(ChainDB.entries, { t = S.now - 4000, seq = "gammal", char = "Tester" })
log = BT.InstanceLog()
eq(#log, 4, "gamle blir framleis lista")
eq(log[#log].counts, false, "men tel ikkje")
eq(log[#log].left, 0, "og har ingen nedteljing")
-- døgntalet er informasjon, ikkje eit tak
ChainDB.daily = 0
ChainDB.entries = {}
for i = 1, 5 do BT.NoteEntry() end

--------------------------------------------------------------------------
print("== reset-varsel ==")
ChainCharDB.resetAt = nil
ChainCharDB.lastZone = "The Stockade"
S.sounds = 0
ChainDB.soundRepeat = 3
S.timers = {}
S.Fire(frame, "CHAT_MSG_SYSTEM", "The Stockade has been reset.")
local zone, age, by, inside = BT.ResetReady()
eq(zone, "The Stockade", "system-melding oppdaga")
eq(S.sounds, 1, "fyrste lyden med ein gong")
-- og den gjentek seg til du gjer noko med det
ChainCharDB.run = nil            -- du står utanfor, varselet lever
S.RunTimers(10)
eq(S.sounds, 3, "tre lydar totalt")
-- men sluttar når varselet er ute av bildet
S.sounds = 0
S.timers = {}
S.now = S.now + 60                      -- forbi dobbel-varsel-vakta
S.Fire(frame, "CHAT_MSG_SYSTEM", "The Stockade has been reset.")
ChainCharDB.resetAt = nil        -- handtert
S.RunTimers(10)
eq(S.sounds, 1, "ingen fleire lydar når situasjonen er over")
ChainCharDB.resetAt = S.now
ChainCharDB.resetZone = "The Stockade"
ChainDB.soundRepeat = 1
S.sounds = 1
-- NIT si party-melding rett etter skal ikkje gje lyd nummer to
S.Fire(frame, "CHAT_MSG_PARTY", "Instances reset!", "Misscall-Firemaw")
eq(S.sounds, 1, "ingen dobbel lyd")
eq(select(3, BT.ResetReady()), "Misscall", "kven som resetta")

-- to ulike lydar: inne tyder "ut", ute tyder "inn", og du skal høyre skilnaden
do
  ChainDB.sound = true
  ChainDB.soundRepeat = 1
  ChainDB.soundIn, ChainDB.soundOut = "levelup", "warning"
  local function ResetNow()
    S.timers = {}
    S.soundLog = {}
    S.now = S.now + 60
    ChainCharDB.resetAt = nil
    S.Fire(frame, "CHAT_MSG_SYSTEM", "The Stockade has been reset.")
    return S.LastSound()
  end
  ChainCharDB.run = { zone = "The Stockade", start = S.now, xp = 0, k = 0 }
  local heardInside = ResetNow()
  ChainCharDB.run = nil
  local heardOutside = ResetNow()
  ok(heardInside and heardOutside and heardInside ~= heardOutside,
     "reset inne og ute gjev ulik lyd (" .. tostring(heardInside) .. " / "
     .. tostring(heardOutside) .. ")")
  eq(heardOutside, "kit:" .. SOUNDKIT.UI_LEGENDARY_LOOT_TOAST, "ute: go-in-lyden")
  eq(heardInside, "kit:" .. SOUNDKIT.RAID_WARNING, "inne: zone-out-lyden")

  -- og når du faktisk går ut medan varselet lever, snur rådet og lyden med det
  ChainCharDB.run = { zone = "The Stockade", start = S.now, xp = 1, k = 1,
                         lvl = 20 }
  ResetNow()
  S.soundLog = {}
  BT.EndRun()
  eq(S.LastSound(), "kit:" .. SOUNDKIT.UI_LEGENDARY_LOOT_TOAST,
     "sonar deg ut: no er rådet å gå inn att")

  -- "Silent" tyder stille
  ChainDB.soundIn = "none"
  ChainCharDB.run = nil
  S.soundLog = {}
  ResetNow()
  eq(#S.soundLog, 0, "Silent gjev ingen lyd")
  ChainDB.soundIn, ChainDB.soundOut = "levelup", "warning"
  ChainCharDB.run = nil
  ChainDB.soundRepeat = 1
end
-- eit reset når du står på 5/5: "go in" er feil råd
ChainDB.entries = {}
ChainCharDB.entrySeq = 0
ChainCharDB.run = nil
for i = 1, 5 do BT.NoteEntry() end
ChainCharDB.resetAt = S.now
ChainCharDB.resetZone = "The Stockade"
local full = table.concat(BT.AllLines(), "\n")
ok(full:find("you are at 5/5"), "seier at du er låst ute i staden for 'go in'")
ok(not full:find("reset by Misscall %- go in"), "ingen 'go in' på 5/5")
-- med plass att skal den seie go in
ChainDB.entries = {}
full = table.concat(BT.AllLines(), "\n")
ok(full:find("go in"), "go in når det er plass")
for i = 1, 5 do BT.NoteEntry() end

S.now = S.now + 300
eq(BT.ResetReady(), nil, "varselet går ut når du står utanfor")

-- reset som ikkje gjekk gjennom skal seie kvifor
ChainCharDB.resetAt, ChainCharDB.failAt = nil, nil
S.Fire(frame, "CHAT_MSG_SYSTEM",
  "Cannot reset The Stockade.  There are players still inside the instance.")
local fz, fw = BT.ResetFailed()
eq(fz, "The Stockade", "feilmelding fanga")
eq(fw, "someone is still inside", "og grunnen")
S.Fire(frame, "CHAT_MSG_SYSTEM",
  "Cannot reset The Stockade.  There are players offline in your party.")
eq(select(2, BT.ResetFailed()), "someone is offline", "offline-varianten")
-- og eit vellukka reset gjer feilmeldinga irrelevant
S.Fire(frame, "CHAT_MSG_SYSTEM", "The Stockade has been reset.")
eq(BT.ResetFailed(), nil, "feilen forsvinn når resetet går gjennom")

-- kunngjering til gruppa er av som standard
S.said = {}
S.party = { { name = "Kompis", lvl = 21 } }
S.Fire(frame, "CHAT_MSG_SYSTEM", "The Stockade has been reset.")
eq(#S.said, 0, "seier ingenting utan at du har slått det på")
ChainDB.announce = true
local heldEntries = ChainDB.entries
ChainDB.entries = {}                 -- ingen lockout: då er "go in" rett
S.Fire(frame, "CHAT_MSG_SYSTEM", "The Stockade has been reset.")
eq(S.said[1], "PARTY: Stockades reset - go in", "kunngjer når det er på")

-- gruppa ser ikkje lockouten din. Dei ser at du ikkje går inn, og så spør
-- nokon. Difor seier addonen det sjølv - ei linje når du står fast, og ei
-- når du ikkje gjer det lenger. Ingen nedteljing i party chat.
do
  ChainDB.announceLock = true
  ChainCharDB.toldLocked = nil
  S.said = {}
  ChainDB.entries = {}
  for i = 1, 5 do
    table.insert(ChainDB.entries,
                 { t = S.now - 600, seq = "x" .. i, char = "Tester" })
  end
  S.now = S.now + 60
  ChainCharDB.resetAt = nil
  S.Fire(frame, "CHAT_MSG_SYSTEM", "The Stockade has been reset.")
  ok((S.said[1] or ""):find("locked 5/5"),
     "på 5/5 seier han lockouten i staden for 'go in' (" ..
     tostring(S.said[1]) .. ")")
  ok((S.said[1] or ""):find("free in"), "og kor lenge det er att")

  -- og ikkje ein gong til med det same
  S.said = {}
  S.now = S.now + 10
  ChainCharDB.resetAt = nil
  S.Fire(frame, "CHAT_MSG_SYSTEM", "The Stockade has been reset.")
  eq(#S.said, 0, "ingen gjentaking i party chat")

  -- når timen har gått seier han frå, ein gong
  S.said = {}
  S.now = S.now + 3700
  BT.PollLock()
  ok((S.said[1] or ""):find("free again"),
     "og seier frå når det losnar (" .. tostring(S.said[1]) .. ")")
  S.said = {}
  BT.PollLock()
  eq(#S.said, 0, "berre den eine gongen")

  -- av-brytaren
  ChainCharDB.toldLocked = nil
  ChainDB.announceLock = false
  ChainDB.entries = {}
  for i = 1, 5 do
    table.insert(ChainDB.entries, { t = S.now, seq = "y" .. i, char = "Tester" })
  end
  S.said = {}
  BT.AnnounceLock()
  eq(#S.said, 0, "kan slåast av")
  ChainDB.announceLock = true
  ChainCharDB.toldLocked = nil
end

ChainDB.entries = heldEntries
ChainDB.announce = false
S.party = {}
ChainCharDB.failAt = nil

-- det store varselet skal hengje under baren, ikkje over: baren står ofte
-- øvst på skjermen, og då har eit varsel over han ingen stad å vere
do
  ChainDB.banner = true
  BT.bannerMuted = nil
  S.Fire(frame, "CHAT_MSG_SYSTEM", "The Stockade has been reset.")
  BT.Refresh()
  local b = _G.ChainBanner
  ok(b ~= nil, "varselramma er bygd")
  ok(b and b:IsShown(), "og synleg etter eit reset")
  local p = b and b.__points[1]
  eq(p and p.point, "TOP", "toppen av varselet er festa")
  eq(p and p.relPoint, "BOTTOM", "til botnen av tekstblokka")
  ok(p and (p.y or 0) < 0, "og ligg under, ikkje over")
  local hint = b and b.hint.__points[1]
  eq(hint and hint.point, "TOP", "hintet fylgjer med nedover")
  ChainDB.banner = false
  BT.Refresh()
  ok(not b:IsShown(), "og er borte igjen når det er slått av")
end

-- to instansar bak eitt namn: SM Cath + Arm er ein kjede, ikkje eit gjensyn
do
  print("== kjede av instansar (SM-wings) ==")
  ChainDB.entries = {}
  ChainCharDB.seenInst = {}
  ChainCharDB.instId = {}
  ChainCharDB.run = nil
  S.level = 30
  S.party = { { name = "Halvar-Stonefell", lvl = 60 } }

  local function visit(instance)
    S.zone, S.map, S.inInstance = "Scarlet Monastery", 189, true
    S.guid = "Creature-0-1-" .. instance .. "-4321-0000"
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.Fire(frame, "PLAYER_TARGET_CHANGED")
    local re = ChainCharDB.run and ChainCharDB.run.reentry
    S.now = S.now + 300
    S.zone, S.inInstance = "Stormwind City", false
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.now = S.now + 60
    return re
  end

  ok(visit("189A") == nil, "Cathedral tel")
  ok(visit("189B") == nil, "Armory tel som ein instans til")
  ok(visit("189C") == nil, "og Library med")
  eq(BT.Lockout(), 3, "tre instansar den timen")
  ok(visit("189A") == true, "men tilbake i same Cathedral tel ikkje på nytt")
  eq(BT.Lockout(), 3, "framleis tre")
  ChainDB.entries = {}
  ChainCharDB.seenInst = {}
  S.guid = nil
  S.party = {}
end

-- etter ein /reload må loggen opnast på nytt av seg sjølv
do
  ChainDB.logSignal = true
  BT.chatLogArmed = nil
  S.chatlog = true                    -- klienten seier "på" medan fila er stengd
  S.chatlogToggles = {}
  S.Fire(frame, "PLAYER_ENTERING_WORLD", false, true)
  S.RunTimers(20)
  eq(S.chatlogToggles[1], "off", "reload: loggen blir skrudd av")
  eq(S.chatlogToggles[2], "on", "og på igjen, så fila blir opna")
end

-- det einaste som treff disken med ein gong: skjermbiletet
do
  print("== augeblinkeleg varsel ==")
  ChainDB.snapSignal = true
  ChainDB.logSignal = false     -- skal virke heilt utan chat-markøren
  S.screenshots = 0
  BT.lastSnap = nil
  BT.Signal("readycheck", "nokon starta ready check")
  S.RunTimers(20)
  eq(S.screenshots, 1, "ready check gir eitt skjermbilete")
  BT.lastSnap = nil
  BT.Signal("reset", "Stockades is open")
  S.RunTimers(20)
  eq(S.screenshots, 3, "og reset gir to til")
  -- men ikkje eit skred om hendingane kjem tett
  BT.Signal("reset", "Stockades is open")
  S.RunTimers(20)
  eq(S.screenshots, 3, "og ikkje fleire innan åtte sekund")
  ChainDB.snapSignal = false
  S.screenshots = 0
  BT.lastSnap = nil
  BT.Signal("readycheck", "x")
  S.RunTimers(20)
  eq(S.screenshots, 0, "og ingen når det er slått av")
  ChainDB.logSignal = true
end

-- markør til chat-loggen, for vaktskriptet utanfor spelet
ChainDB.logSignal = false
S.said, S.channels = {}, {}
BT.Signal("reset", "Stockades is open")
eq(#S.said, 0, "ingenting blir skrive når markørane er av")
ChainDB.logSignal = true
BT.Signal("reset", "Stockades is open")
eq(S.chatlog, true, "chat-logging blir slått på")
ok(S.channels["LBTester"] ~= nil, "eigen kanal, berre for denne karakteren")
ok(S.said[1] and S.said[1]:find("LTPUSH reset Stockades is open"), "markøren skriven")
-- markøren skal pressast ut av bufferen med ein gong, ikkje ligge der i ti
-- minutt slik klienten helst vil ha det
do
  S.chatlogToggles = {}
  BT.lastFlush = nil
  BT.Signal("readycheck", "nokon starta ready check")
  S.RunTimers(20)
  local t = S.chatlogToggles
  ok(#t >= 2 and t[#t] == "on" and t[#t - 1] == "off",
     "loggen blir tømt til fil rett etter markøren")
  -- men ikkje ein gong i sekundet
  local before = #S.chatlogToggles
  BT.Signal("readycheck", "endå ein")
  S.RunTimers(20)
  eq(#S.chatlogToggles, before, "og ikkje oftare enn kvart femte sekund")
end

-- og chat-loggen skal ha blitt skrudd av og på igjen, ikkje berre "på"
ok(#S.chatlogToggles >= 2 and S.chatlogToggles[#S.chatlogToggles] == "on",
   "chat-loggen blir opna på nytt, ikkje berre beden om å vere på")
-- og kanalen må stå i eit chat-vindauge, elles skriv ikkje klienten han til fila
ok(S.channelFrames[BT.SignalChannel()] ~= nil,
   "markørkanalen er synleg i eitt vindauge, så loggen får han med seg")
eq(S.channelFrames[BT.SignalChannel()], _G.ChatFrame2,
   "og det er Combat Log-vinduet, ikkje det du les i")
-- nektar det vinduet, må han falle tilbake på eit som tek imot
do
  S.channelFrames = {}
  S.refuseFrame = _G.ChatFrame2
  BT.signalFrameIndex = nil
  BT.EnableSignal()
  eq(S.channelFrames[BT.SignalChannel()], _G.ChatFrame1,
     "fell tilbake på hovudvinduet når Combat Log nektar")
  ok(BT.SignalWhere() ~= nil, "og seier kvar han hamna")
  S.refuseFrame = nil
end

-- ready check skal varsle
S.said = {}
S.sounds = 0
S.Fire(frame, "READY_CHECK", "Algorismus-Firemaw")
eq(BT.readyCheckBy, "Algorismus", "kven som starta ready check")
ok(S.said[1] and S.said[1]:find("LTPUSH readycheck"), "markør for ready check")
-- Blizzard sin eigen popup held i rommet; vi legg ikkje noko oppå
eq(S.sounds, 0, "ingen ekstra lyd frå oss")
ChainDB.logSignal = false

--------------------------------------------------------------------------
print("== xp/h og stille perioder ==")
ChainCharDB.buckets = {}
for i = 1, 10 do
  S.now = S.now + 60
  BT.AddXP(400)
end
local rate = BT.Rate()
ok(rate and rate > 20000, "rate målt (" .. tostring(rate and math.floor(rate)) .. ")")
S.now = S.now + 40 * 60
eq(BT.Rate(), nil, "rate borte etter 40 min stille")
eq(BT.IdleMin(), 40, "40 minutt stille")

--------------------------------------------------------------------------
print("== tekstbreidde ==")
S.party = { { name = "Misscall-Firemaw", lvl = 60 }, { name = "A", lvl = 33 },
            { name = "B", lvl = 26 }, { name = "C", lvl = 24 } }
S.level, S.xp, S.xpMax = 23, 12000, 31700
S.rested = 4000
S.zone, S.map, S.inInstance = "The Stockade", 34, true
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
ChainCharDB.run.xp, ChainCharDB.run.k = 8472, 93
ChainCharDB.run.reentry = true
ChainCharDB.resetAt = S.now
ChainCharDB.resetZone = "The Stockade"
ChainCharDB.resetBy = "Misscall"
S.now = S.now + 8 * 60
local slots = BT.BuildText()
local body = table.concat(BT.AllLines(slots), "\n")
print("   [" .. (slots.barLeft or "") .. "] [" .. (slots.barRight or "") .. "]")
local worst = 0
for line in (body .. "\n"):gmatch("([^\n]*)\n") do
  local clean = (line:gsub("|c%x%x%x%x%x%x%x%x", "")); clean = (clean:gsub("|r", ""))
  if clean ~= "" then
    print(string.format("   %-62s (%d)", clean, #clean))
    if #clean > worst then worst = #clean end
    ok(#clean <= 74, "linje over 74 teikn: " .. clean)
  end
end

--------------------------------------------------------------------------
print("== leveling-modus ==")
S.party = {}
S.zone, S.inInstance = "Elwynn Forest", false
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
ChainCharDB.lastEnd = nil
S.quests = { { title = "Q1", done = true, xp = 1200, level = 20 },
             { title = "Q2", done = true, xp = 900, level = 19 } }
BT.questScan = nil
BT.ScanQuests()
eq(BT.questCount, 2, "to ferdige quests")
eq(BT.questXP, 2100, "quest-xp summert")

-- Ein quest du har vakse frå er grå i loggen og verdt ingenting å levere.
-- Å telje han med sa at det låg ein level i sekken når det gjorde det ikkje.
do
  S.level = 30
  S.greenRange = 5                       -- grått under level 25
  S.quests = { { title = "Fersk", done = true, xp = 1200, level = 28 },
               { title = "Gammal", done = true, xp = 900, level = 12 },
               { title = "Eldgammal", done = true, xp = 700, level = 8 } }
  BT.questScan = nil
  BT.ScanQuests()
  eq(BT.questCount, 1, "berre den som framleis gjev xp blir talt")
  eq(BT.questXP, 1200, "og berre den sin xp")
  eq(BT.questGrey, 2, "dei grå blir talt for seg")
  ok(BT.QuestGrey(12), "level 12 er grått på 30")
  ok(not BT.QuestGrey(28), "level 28 er det ikkje")
  ok(not BT.QuestGrey(nil), "ein quest utan level blir ikkje kasta")

  -- og utan kallet i klienten fell den tilbake på same terskel som xp-fallet
  local realRange = GetQuestGreenRange
  _G.GetQuestGreenRange = nil
  ok(BT.QuestGrey(8), "utan GetQuestGreenRange held terskelen frå decay-tabellen")
  ok(not BT.QuestGrey(29), "og han er ikkje for ivrig")
  _G.GetQuestGreenRange = realRange

  S.level = 20
  S.quests = { { title = "Q1", done = true, xp = 1200, level = 20 },
               { title = "Q2", done = true, xp = 900, level = 19 } }
  BT.questScan = nil
  BT.ScanQuests()
end
slots = BT.BuildText()
body = table.concat(BT.AllLines(slots), "\n")
print("   [" .. (slots.barLeft or "") .. "] [" .. (slots.barRight or "") .. "]")
for line in (body .. "\n"):gmatch("([^\n]*)\n") do
  local clean = (line:gsub("|c%x%x%x%x%x%x%x%x", "")); clean = (clean:gsub("|r", ""))
  if clean ~= "" then
    print(string.format("   %-62s (%d)", clean, #clean))
    ok(#clean <= 74, "linje over 74 teikn: " .. clean)
  end
end

--------------------------------------------------------------------------
print("== vindauge, opsjonar og eksport ==")
BT.ToggleWindow()
ok(_G.ChainWindow ~= nil, "historikkvindauget bygd")
BT.RenderWindow()
BT.ToggleOptions()
ok(_G.ChainOptions ~= nil, "opsjonsvindauget bygd")
BT.RenderOptions()
do  -- ingenting skal stikke ut av ramma: det er slik knappane hamna utanfor
  local o = _G.ChainOptions
  local frameW, frameH = o:GetWidth(), o:GetHeight()
  local worst, worstW, tall, tallY = nil, 0, nil, 0
  local function bounds(obj, ox, oy, holderW, label)
    for _, p in ipairs(obj.__points or {}) do
      local anchor = p.point or ""
      if anchor:find("LEFT") and not anchor:find("RIGHT") then
        local w = obj:GetWidth()
        if obj.__kind == "FontString" and not obj.__w then w = obj:GetStringWidth() end
        local right = ox + (p.x or 0) + (w or 0)
        if right > holderW and right > worstW then
          worst, worstW = label or obj.__kind, right
        end
      end
      if anchor:find("TOP") and (p.y or 0) <= 0 then
        local bottom = -(oy + (p.y or 0)) + (obj:GetHeight() or 0)
        if bottom > frameH and bottom > tallY then tall, tallY = label, bottom end
      end
    end
  end
  for _, child in ipairs(o.__children or {}) do
    bounds(child, 0, 0, frameW, child.__kind)
  end
  -- og radene i rutetabellen skal halde seg innanfor si eiga rad
  for _, row in ipairs(o.rows or {}) do
    for _, child in ipairs(row.__children or {}) do
      bounds(child, 0, 0, row:GetWidth(), "rad: " .. tostring(child.__kind))
    end
  end
  ok(worst == nil, "alt held seg innanfor ramma (" .. tostring(worst)
     .. " endar på " .. math.floor(worstW) .. " av " .. frameW .. ")")

  -- og ingenting skal liggje oppå noko anna: berre widgetar med ei kjend
  -- breidde blir samanlikna, så tekstbreidder på slump ikkje lyg
  local boxes = {}
  for _, child in ipairs(o.__children or {}) do
    local p = child.__points and child.__points[1]
    -- a label's declared width is a box it is allowed to be centred in; what
    -- can actually collide is the text in it
    local w = child.__w
    if child.__kind == "FontString" then w = child:GetStringWidth() end
    if p and w and w > 0 and (p.point or ""):find("LEFT")
       and not (p.point or ""):find("RIGHT") then
      table.insert(boxes, { x = p.x or 0, y = p.y or 0, w = w,
                            h = child.__h or 16, what = child.__kind })
    end
  end
  local clash
  for i = 1, #boxes do
    for j = i + 1, #boxes do
      local a, b = boxes[i], boxes[j]
      -- same row, not merely nearby: rows here are 20 pixels apart or more
      if math.abs(a.y - b.y) < 8 and a.x < b.x + b.w and b.x < a.x + a.w then
        clash = string.format("%s ved %d og %s ved %d", a.what, a.x, b.what, b.x)
      end
    end
  end
  ok(clash == nil, "ingenting ligg oppå noko anna (" .. tostring(clash) .. ")")
  ok(tall == nil, "og ingenting under botnen (" .. tostring(tall)
     .. " endar på " .. math.floor(tallY) .. " av " .. frameH .. ")")
end

do  -- og kva level spelet slepp deg inn på
  local spans, mins = 0, 0
  for _, row in ipairs(_G.ChainOptions.rows or {}) do
    if row.id then
      if ((row.span:GetText() or ""):find("%d+%-%d+")) then spans = spans + 1 end
      if ((row.min:GetText() or ""):find("%d+%+")) then mins = mins + 1 end
    end
  end
  ok(mins > 0, "opsjonane viser minstelevel for å kome inn")
  eq(mins, spans, "kvar instans har begge tala")
  eq(BT.MinLevel({ id = "stock" }), 15, "Stockades slepp deg inn på 15")
  eq(BT.MinLevel({ id = "sm" }), 21, "SM på 21")
  for _, d in ipairs(BT.DUNGEONS) do
    ok(d.min and d.min <= d.lo, d.label .. ": minstelevel ikkje over spennet")
  end
end

do  -- kvar instans i ruteredigeringa skal vise kva level han er for
  local spans = 0
  for _, row in ipairs(_G.ChainOptions.rows or {}) do
    if row.id and (row.span:GetText() or ""):find("%d+%-%d+") then spans = spans + 1 end
  end
  ok(spans > 0, "opsjonane viser level-spennet per instans")
end
local csv = BT.BuildCSV()
ok(csv:find("^at,date,zone"), "CSV har overskrift")
local lines = select(2, csv:gsub("\n", "\n")) + 1
eq(lines, #ChainDB.runs + 1, "ei CSV-linje per run")
SlashCmdList["CHAIN"]("stats")
SlashCmdList["CHAIN"]("help")

--------------------------------------------------------------------------
print("== gull og trade-logg ==")
local tf = BT.tradeFrame
ChainDB.trades = {}
S.level = 22
S.party = { { name = "Misscall-Firemaw", lvl = 60 } }
S.tradeTarget = "Misscall-Firemaw"
S.playerMoney, S.targetMoney = 0, 0

local function doTrade(gave, got, who)
  S.tradeTarget = who or "Misscall-Firemaw"
  S.playerMoney, S.targetMoney = gave, got
  S.Fire(tf, "TRADE_SHOW")
  S.Fire(tf, "TRADE_MONEY_CHANGED")
  S.Fire(tf, "UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)
  S.Fire(tf, "TRADE_CLOSED")
  S.now = S.now + 60
end

doTrade(50 * 10000, 0)                 -- 50g til boosteren
eq(#ChainDB.trades, 1, "trade lagra")
eq(ChainDB.trades[1].with, "Misscall", "namn utan realm")
eq(ChainDB.trades[1].gave, 500000, "kopar lagra")
eq(ChainDB.trades[1].by, "Misscall", "knytt til boosteren")
eq(ChainDB.trades[1].id, "stock", "knytt til steget")

doTrade(50 * 10000, 0)
doTrade(10 * 10000, 3 * 10000)         -- 10g ut, 3g tilbake
eq(#ChainDB.trades, 3, "tre trades")
eq(BT.Spent({}), 1070000, "netto brukt = 107g")
eq(BT.Spent({ id = "stock" }), 1070000, "per steg")
near(BT.Gold(BT.Spent({})), 107, "kopar til gull")

-- kvar handelen skjedde, slik NIT skriv det: i instansen eller i byen
do
  local before = #ChainDB.trades
  S.inInstance, S.zone, S.map = true, "Stormwind Stockade", 34
  doTrade(25 * 10000, 0)
  local t = ChainDB.trades[before + 1]
  eq(t.zone, "Stormwind Stockade", "sona blir lagra")
  eq(t.id, "stock", "og instansen du står i")

  S.inInstance, S.zone, S.map = false, "Stormwind City", nil
  doTrade(30 * 10000, 0)
  local c = ChainDB.trades[before + 2]
  eq(c.zone, "Stormwind City", "og byen når du betaler ute")
  eq(c.id, "stock", "men gullet høyrer framleis til steget")
  -- rydd opp att, så tala under er som før
  table.remove(ChainDB.trades)
  table.remove(ChainDB.trades)
  BT.TouchTrades()
end

-- ein avbroten trade skal ikkje loggast
S.playerMoney, S.targetMoney = 999 * 10000, 0
S.Fire(tf, "TRADE_SHOW")
S.Fire(tf, "TRADE_MONEY_CHANGED")
S.Fire(tf, "TRADE_CLOSED")
eq(#ChainDB.trades, 3, "avbroten trade blir ikkje lagra")

-- ein handel med nokon som ikkje er booster
S.party = {}
ChainCharDB.lastBy = nil
doTrade(0, 25 * 10000, "Bankalt-Firemaw")
eq(#ChainDB.trades, 4, "fjerde trade")
eq(ChainDB.trades[4].by, nil, "ikkje booster")
eq(BT.Spent({}), 1070000 - 250000, "pengar inn trekk frå")

-- gull per level
S.level = 26
local perLevel, spent, levels = BT.SpentPerLevel()
eq(levels, 4, "fire level sidan første betaling")
near(BT.Gold(spent), 82, "totalt brukt")
near(BT.Gold(perLevel), 20.5, "per level")

local byB = BT.SpentByBooster()
eq(byB[1].with, "Misscall", "mest til boosteren")
near(BT.Gold(byB[1].net), 107, "netto til boosteren")

local tcsv = BT.BuildTradeCSV()
ok(tcsv:find("^at,date,traded_with"), "trade-CSV har overskrift")
eq(select(2, tcsv:gsub("\n", "\n")) + 1, #ChainDB.trades + 1, "ei linje per trade")
SlashCmdList["CHAIN"]("gold")

-- og det skal synast på baren, i begge modus
S.party = { { name = "Misscall-Firemaw", lvl = 60 } }
S.level, S.xp, S.xpMax = 23, 12000, 31700
S.zone, S.map, S.inInstance = "The Stockade", 34, true
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
local bbody = table.concat(BT.AllLines(), "\n")
ok(bbody:find("paid "), "boost-modus viser kva steget har kosta")
for line in (bbody .. "\n"):gmatch("([^\n]*)\n") do
  local clean = (line:gsub("|c%x%x%x%x%x%x%x%x", "")); clean = (clean:gsub("|r", ""))
  if clean ~= "" then
    print(string.format("   %-62s (%d)", clean, #clean))
    ok(#clean <= 74, "linje over 74 teikn: " .. clean)
  end
end

S.zone, S.inInstance = "Elwynn Forest", false
S.party = {}
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
ChainCharDB.lastEnd = nil
local lbody = table.concat(BT.AllLines(), "\n")
ok(lbody:find("spent "), "leveling-modus viser totalen")
for line in (lbody .. "\n"):gmatch("([^\n]*)\n") do
  local clean = (line:gsub("|c%x%x%x%x%x%x%x%x", "")); clean = (clean:gsub("|r", ""))
  if clean ~= "" then
    print(string.format("   %-62s (%d)", clean, #clean))
    ok(#clean <= 74, "linje over 74 teikn: " .. clean)
  end
end

-- gull-fana skal teikne
BT.ToggleWindow(); BT.ToggleWindow()

--------------------------------------------------------------------------
print("== booster-pris og tommel ==")
ChainDB.boosters = {}
S.party = { { name = "Misscall-Firemaw", lvl = 60 } }
S.level, S.xp, S.xpMax = 22, 0, 27300
local _, st2 = BT.Stage()

-- utan eigen pris fell den tilbake på steg-prisen (50g per 5 runs = 10g/run)
local per, own = BT.PricePerRun(st2, "Misscall")
near(per, 10, "steg-pris per run")
eq(own, false, "ikkje boosteren sin eigen pris")

-- boosteren seier 12g per run
BT.SetPrice("Misscall", 12, 1)
per, own = BT.PricePerRun(st2, "Misscall")
near(per, 12, "boosteren sin eigen pris")
eq(own, true, "merka som hans pris")
eq(BT.Cost(st2, 10, "Misscall"), 120, "ti runs hos Misscall")
eq(BT.Cost(st2, 10, "Torkel"), 100, "Torkel fell tilbake på steg-prisen")

-- pakkepris: 5 runs for 45g
BT.SetPrice("Torkel", 45, 5)
near(BT.PricePerRun(st2, "Torkel"), 9, "pakkepris per run")
eq(BT.Cost(st2, 6, "Torkel"), 90, "seks runs blir to pakkar")

-- prisen du blir oppgjeven gjeld ein pakke, aldri ein enkelt run
local stepNow = select(2, BT.Stage())
ChainDB.pack = 5
BT.SetPrice("Misscall", 60)                 -- 60g for 5 runs
eq(ChainDB.boosters["Misscall"].pack, 5, "pakkestorleiken blir lagra med prisen")
near(BT.PricePerRun(stepNow, "Misscall"), 12, "60g / 5 runs = 12g per run")
eq(BT.Cost(stepNow, 5, "Misscall"), 60, "fem runs er ein pakke")
eq(BT.Cost(stepNow, 6, "Misscall"), 120, "seks runs er to pakkar")

-- dommen blir rekna ut, ikkje klikka: xp per gull
local v = BT.XPPerGold(stepNow, "Misscall", 9000)
near(v, 750, "9 000 xp for 12g per run = 750 xp per gull")
-- billegare booster med same xp er betre
BT.SetPrice("Billeg", 30)
near(BT.XPPerGold(stepNow, "Billeg", 9000), 1500, "halv pris = dobbel verdi")
-- fleire mobs for same pris er betre
near(BT.XPPerGold(stepNow, "Misscall", 18000), 1500, "dobbel xp = dobbel verdi")
eq(select(2, BT.Grade(1500, 1500)), "good", "beste er god")
eq(select(2, BT.Grade(1200, 1500)), "ok", "80 % er ok")
eq(select(2, BT.Grade(800, 1500)), "poor", "53 % er dårleg")
eq(BT.XPPerGold(stepNow, "Ukjend", 9000) ~= nil, true, "utan eigen pris fell den til steg-prisen")
BT.SetPrice("Billeg", 0)

-- boosteren du faktisk spelar med slår prisen du sette på instansen
do
  local route = ChainDB.route.stock
  local oldGold, oldPrice = route.gold, ChainDB.boosters["Misscall"].price
  route.gold = 75                              -- 75g per pakke i configen
  BT.SetPrice("Misscall", 50)                  -- men han tek 50
  BT.Touch()
  near(BT.PricePerRun(stepNow, "Misscall"), 10, "hans 50g/5 slår 75g/5 i configen")
  near(BT.PricePerRun(stepNow, nil), 15, "utan booster gjeld configen")
  eq(BT.Cost(stepNow, 5, "Misscall"), 50, "og kostnaden fylgjer han")
  -- ruta i vindauget skal rekne med det same
  BT.ShowTab("route")
  local w2 = _G.ChainWindow
  local goldCell, basis
  for _, r in ipairs(w2.rows or {}) do
    if r:IsShown() and (r.cells[1]:GetText() or ""):find("Stockades") then
      goldCell = r.cells[7]:GetText()
      basis = r.cells[10]:GetText()
    end
  end
  ok(goldCell and goldCell:find("50g"), "rutefana brukar hans pris (" ..
     tostring(goldCell) .. ")")
  ok(basis and basis:find("Misscall's price"), "og seier kven prisen er frå")
  route.gold, ChainDB.boosters["Misscall"].price = oldGold, oldPrice
  BT.Touch()
end

-- pakkestorleik per instans: nokon sel ti der andre sel fem
do
  local route = ChainDB.route.stock
  local oldGold, oldPack = route.gold, route.pack
  local oldPrice = ChainDB.boosters["Misscall"].price
  route.gold, route.pack = 100, 10            -- 100g for ti runs her
  BT.SetPrice("Misscall", 0)
  BT.Touch()
  eq(BT.StepPack(stepNow), 10, "instansen sin eigen pakke slår innstillinga")
  near(BT.PricePerRun(stepNow, nil), 10, "100g / 10 runs = 10g per run")
  eq(BT.Cost(stepNow, 10, nil), 100, "ti runs er ein pakke")
  eq(BT.Cost(stepNow, 11, nil), 200, "elleve runs er to")
  -- ein annan instans er framleis på den globale
  local other = BT.BY_ID and BT.BY_ID["sm"] or nil
  if other then eq(BT.StepPack(other), 5, "andre instansar rører seg ikkje") end

  -- ein pris skriven no gjeld den pakken, ikkje den globale
  BT.SetPrice("Misscall", 300)
  eq(ChainDB.boosters["Misscall"].pack, 10, "prisen blir lagra mot 10 runs")
  near(BT.PricePerRun(stepNow, "Misscall"), 30, "300g / 10 runs = 30g per run")

  -- og boosteren sin eigen avtale slår instansen sin
  BT.SetPack("Misscall", 20)
  near(BT.PricePerRun(stepNow, "Misscall"), 15, "300g / 20 runs hos han")
  eq(BT.Cost(stepNow, 20, "Misscall"), 300, "tjue runs er ein pakke hos han")
  -- og den held seg når du skriv prisen på nytt
  BT.SetPrice("Misscall", 400)
  eq(ChainDB.boosters["Misscall"].pack, 20, "pakken hans står seg")
  -- blankt felt: tilbake til det instansen går for
  BT.SetPack("Misscall", nil)
  eq(BT.PackFor(stepNow, "Misscall"), 10, "blankt felt fell til instansen")

  route.gold, route.pack = oldGold, oldPack
  ChainDB.boosters["Misscall"].price = oldPrice
  ChainDB.boosters["Misscall"].pack = 5
  BT.Touch()
end

-- og ein pris frå den gamle bugen blir reparert ved innlasting
ChainDB.boosters["Gammal"] = { price = 50, pack = 1 }
ChainDB.packFixed = nil
S.Fire(frame, "ADDON_LOADED", "Chain")
eq(ChainDB.boosters["Gammal"].pack, 5, "50g blir lest som 50g for 5 runs")
near(BT.PricePerRun(stepNow, "Gammal"), 10, "altså 10g per run")
ChainDB.boosters["Gammal"] = nil

-- og det skal synast på tooltipen, ikkje på baren. Baren hadde namnet hans,
-- xp/h, gull per level og xp per gull - alt saman ting tooltipen seier betre
-- og med plass til å forklare seg. Ei linje til å lese forbi, og ingenting meir.
S.zone, S.map, S.inInstance = "The Stockade", 34, true
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
local vbody = table.concat(BT.AllLines(), "\n")
ok(not vbody:find("xp/g"), "verdien står ikkje på baren")
ok(not vbody:find("xp/h"), "og heller ikkje boosteren sin rate")
ok(not vbody:find("grp "), "gruppa heller ikkje")
BT.BarTooltip(GameTooltip)
local vtip = S.TipText()
ok(vtip:find("xp per gold"), "men verdien står på tooltipen")
ok(vtip:find("xp per hour"), "saman med raten hans")
ok(vtip:find("group"), "og gruppa")
for line in (vbody .. "\n"):gmatch("([^\n]*)\n") do
  local clean = (line:gsub("|c%x%x%x%x%x%x%x%x", "")); clean = (clean:gsub("|r", ""))
  if clean ~= "" then
    print(string.format("   %-62s (%d)", clean, #clean))
    ok(#clean <= 74, "linje over 74 teikn: " .. clean)
  end
end
-- historikk-rader skal og kunne haldast over
do
  BT.ShowTab("runs")
  local wh = _G.ChainWindow
  local r1 = wh.rows[1]
  ok(r1.tip ~= nil, "historikk-rada har ein tooltip")
  r1.__scripts.OnEnter(r1)
  local t = S.TipText()
  ok(t:find("xp,", 1, true), "med tala i klartekst")
  r1.__scripts.OnLeave(r1)
end

-- ingen kolonne skal vere for smal for innhaldet sitt: "1h 42m ago" braut
-- linja og skeivstilte heile rada
do
  BT.ShowTab("runs")
  local w4 = _G.ChainWindow
  local tooWide
  for _, r in ipairs(w4.rows or {}) do
    if r:IsShown() then
      for ci, cell in ipairs(r.cells) do
        local txt = (cell:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        -- breidda er eit grovt anslag, så berre klare overskridingar tel
        if cell:IsShown() and txt ~= "" and cell.__w
           and #txt * 5.5 > cell.__w * 1.2 then
          tooWide = ci .. ": '" .. txt .. "' i " .. cell.__w .. " px"
        end
      end
    end
  end
  ok(tooWide == nil, "ingen celle er breiare enn kolonnen (" .. tostring(tooWide) .. ")")
end

-- annonse-fana: alle som har annonsert, uansett instans, med kvisk-knapp
print("== annonse-fana ==")
do
  ChainDB.boosters = {}
  ChainDB.readAds = true
  local rf2 = BT.rosterFrame
  S.Fire(rf2, "CHAT_MSG_CHANNEL", "WTS Stockades boost 200g / 5 runs", "Seljar-Firemaw")
  S.now = S.now + 60
  S.Fire(rf2, "CHAT_MSG_WHISPER", "SM 5 runs 300g", "Kviskar-Firemaw")
  BT.ShowTab("ads")
  local w3 = _G.ChainWindow
  local rows3, whisperRow = 0, nil
  for _, r in ipairs(w3.rows or {}) do
    if r:IsShown() and (r.cells[2]:GetText() or "") ~= "" then
      rows3 = rows3 + 1
      if (r.cells[2]:GetText() or ""):find("Kviskar") then whisperRow = r end
    end
  end
  eq(rows3, 2, "begge annonsørane er på fana")
  ok(whisperRow ~= nil, "og den som kviska er med")
  ok(whisperRow and whisperRow.whisper:IsShown(), "kvisk-knappen er synleg")
  -- nyaste øvst
  ok((w3.rows[1].cells[2]:GetText() or ""):find("Kviskar"), "nyaste annonse øvst")
  -- og han skal faktisk opne eit kvisk
  S.whispered = {}
  whisperRow.whisper.__scripts.OnClick(whisperRow.whisper)
  eq(S.whispered[1], "Kviskar", "klikk opnar kvisk til rett person")
  -- kanalen annonsen kom frå står i lista, og kva han faktisk sa
  ok((whisperRow.cells[6]:GetText() or ""):find("whisper"), "og seier kvar han kom frå")
  ok((whisperRow.cells[7]:GetText() or ""):find("SM"), "og kva han skreiv")
  -- heile teksten skal kome fram når du held over rada
  ok(whisperRow.tip ~= nil, "rada har ein tooltip")
  whisperRow.__scripts.OnEnter(whisperRow)
  local rowTip = S.TipText()
  ok(rowTip:find("Kviskar", 1, true), "tooltipen namngjev annonsøren")
  ok(rowTip:find("5 runs", 1, true) or rowTip:find("300g", 1, true),
     "og har heile annonseteksten")
  -- sortering på pris skal virke som på dei andre fanene
  local head = w3.headers[4]
  head.__scripts.OnClick(head)
  ok(true, "sortering på pris kastar ikkje")
  BT.ShowTab("runs")
  ok(not w3.rows[1].whisper:IsShown(), "kvisk-knappen berre på annonse-fana")
  ChainDB.boosters = {}
end

-- kvar einaste fane skal teikne utan å kaste
for _, tab in ipairs({ "runs", "boosters", "ads", "reported", "gold", "locks", "route" }) do
  local okDraw, err = pcall(BT.ShowTab, tab)
  ok(okDraw, "fana " .. tab .. " teiknar (" .. tostring(err) .. ")")
end

-- rutefana skal ha ei celle per kolonne, og seie kva kvar stad er for
BT.ShowTab("route")
do
  local wr = _G.ChainWindow
  local filled, spans = 0, 0
  for _, row in ipairs(wr.rows or {}) do
    if row:IsShown() then
      local last = row.cells and row.cells[10]
      if last and (last:GetText() or "") ~= "" then filled = filled + 1 end
      local sp = row.cells and row.cells[3]
      if sp and ((sp:GetText() or ""):find("%d+%-%d+")) then spans = spans + 1 end
    end
  end
  ok(filled > 0, "rutefana fyller heile rada, ikkje berre dei seks fyrste")
  ok(spans > 0, "rutefana viser kva level kvar stad er for")
end

-- og prisboksen skal faktisk vere synleg på Boosters
BT.ShowTab("boosters")
local w = _G.ChainWindow
local shown = 0
for _, row in ipairs(w.rows or {}) do
  if row.price and row.price:IsShown() then shown = shown + 1 end
end
ok(shown > 0, "prisboksen er synleg på Boosters-fana")
BT.ShowTab("runs")
for _, row in ipairs(w.rows or {}) do
  ok(not (row.price and row.price:IsShown()), "og skjult på History")
  break
end

-- di eiga liste: legg inn ein booster med notat
print("== eiga booster-liste ==")
do
  local step = BT.FocusStep()
  local name = BT.AddBooster("  kjeltring-Firemaw ", "berre morgonar", step.id)
  eq(name, "Kjeltring", "namnet blir reinska og stor forbokstav")
  eq(ChainDB.boosters["Kjeltring"].note, "berre morgonar", "notatet lagra")
  ok(ChainDB.boosters["Kjeltring"].mine, "merka som din eigen")
  ok(BT.AddBooster("") == nil, "tomt namn blir avvist")
  ok(BT.AddBooster("Tester") == nil, "og du kan ikkje leggje inn deg sjølv")

  local found
  for _, b in ipairs(BT.Roster(step.id)) do
    if b.by == "Kjeltring" then found = b end
  end
  ok(found ~= nil, "han dukkar opp i lista utan ein einaste run")
  ok(found and found.n == 0, "med null runs")

  -- og i vindauget, med notatboks og ein x for å fjerne han
  BT.ShowTab("boosters")
  local noteBox, delBox
  for _, row in ipairs(w.rows or {}) do
    if row:IsShown() and (row.cells[1]:GetText() or ""):find("Kjeltring") then
      noteBox = row.note
      delBox = row.del
    end
  end
  ok(noteBox and noteBox:IsShown(), "notatboksen er synleg")
  eq(noteBox and noteBox:GetText(), "berre morgonar", "og har notatet i seg")
  ok(delBox and delBox:IsShown(), "og ein x for å fjerne han att")
  ok(w.addName and w.addName:IsShown(), "feltet for å leggje til er framme")

  -- skriv om notatet slik ein spelar ville gjort
  noteBox:SetText("pullar ikkje siste rommet")
  noteBox.__scripts.OnEditFocusLost(noteBox)
  eq(ChainDB.boosters["Kjeltring"].note, "pullar ikkje siste rommet",
     "notatet blir oppdatert når du forlèt feltet")

  -- notat skal aldri sendast vidare
  S.sent = {}
  ChainDB.share = true
  if BT.ShareOne then BT.ShareOne("Kjeltring") end
  S.RunTimers(20)
  local leaked = false
  for _, m in ipairs(S.sent) do
    if tostring(m.msg):find("morgonar") or tostring(m.msg):find("pullar") then
      leaked = true
    end
  end
  ok(not leaked, "notatet blir aldri sendt til andre")
  ChainDB.share = false

  -- og x-en fjernar han igjen
  delBox.__scripts.OnClick(delBox)
  eq(ChainDB.boosters["Kjeltring"], nil, "borte att etter x")
  BT.ShowTab("runs")
  ok(not (w.rows[1].note and w.rows[1].note:IsShown()), "notatboksen berre på Boosters")
  ok(not (w.addName and w.addName:IsShown()), "og feltet for å leggje til også")
end

-- tooltipen skal bere detaljane, og han skal virke utan rute også
print("== tooltip ==")
local okTip, tipErr = pcall(BT.BarTooltip, BT.bar)
ok(okTip, "tooltipen teiknar (" .. tostring(tipErr) .. ")")
local tip = S.TipText()
for line in (tip .. "\n"):gmatch("([^\n]*)\n") do
  local l, r = line:match("^(.-)\t(.*)$")
  if l then print(string.format("   %-26s %s", l, r))
  elseif line ~= "" then print("   " .. line) end
end
ok(tip:find("Stockades", 1, true), "tooltipen namngjev instansen")
ok(tip:find("good for levels", 1, true), "tooltipen seier kva level staden er for")
ok(tip:find("22%-30"), "og viser spennet frå tabellen")
ok(tip:find("xp per run", 1, true), "tooltipen har xp per run")
ok(tip:find("instances", 1, true), "tooltipen har lockout")
ok(tip:find("Right%-click"), "tooltipen har hjelpelinjene")
do  -- utan rute skal han falle tilbake på det du sist køyrde
  local saved = ChainDB.route
  ChainDB.route = {}
  BT.Touch()
  local okNoRoute = pcall(BT.BarTooltip, BT.bar)
  local t2 = S.TipText()
  ok(okNoRoute, "tooltipen teiknar utan rute")
  ok(t2:find("good for levels", 1, true), "og viser framleis level-spennet")
  ok(t2:find("not on it", 1, true), "og seier at staden ikkje er på ruta")
  ChainDB.route = saved
  BT.Touch()
end

-- søkefeltet skal filtrere på tvers av fanene
BT.ToggleWindow(); BT.ToggleWindow()
ok(w.search ~= nil, "søkefelt finst")
local function search(txt)
  w.search:SetText(txt)
  local fn = w.search.__scripts.OnTextChanged
  if fn then fn(w.search) end
end
search("algorismus")
search("")
BT.RenderWindow()
BT.ToggleWindow()
BT.ToggleOptions(); BT.RenderOptions(); BT.ToggleOptions()

--------------------------------------------------------------------------
print("== annonsar i chatten ==")
ChainDB.boosters = {}
ChainDB.readAds = true
local rf = BT.rosterFrame

local function ad(text, who)
  S.Fire(rf, "CHAT_MSG_CHANNEL", text, who or "Selgar-Firemaw")
end

ad("WTS Stockades boost 40g per run, whisper me", "Selgar-Firemaw")
local b = ChainDB.boosters["Selgar"]
ok(b ~= nil, "boosteren hamna i lista")
eq(b and b.adPrice, 40, "pris frå annonsen")
eq(b and b.adZone, "stock", "instansen frå annonsen")
near(BT.QuotedPrice("Selgar", "stock"), 40, "pris per run")
eq(select(2, BT.QuotedPrice("Selgar", "stock")), "advert", "merka som annonse")

ad("Selling 5 runs Scarlet Monastery boost 200g total", "Rask-Firemaw")
eq(ChainDB.boosters["Rask"].adPack, 5, "pakkestorleik frå annonsen")
near(BT.QuotedPrice("Rask", "sm"), 40, "200g for 5 runs = 40g per run")

-- ting som ikkje er annonsar skal ikkje fange
ad("anyone got 40g to spare", "Tiggar-Firemaw")
eq(ChainDB.boosters["Tiggar"], nil, "tigging er ikkje ein annonse")
-- annonsar utan pris tel også: dei aller fleste har ingen pris i seg
ad("WTS Stockades boost, FFA loot, sum ready", "Utanpris-Firemaw")
ok(ChainDB.boosters["Utanpris"] ~= nil, "annonse utan pris blir lagra")
eq(ChainDB.boosters["Utanpris"].adPrice, 0, "med pris null")
ok((ChainDB.boosters["Utanpris"].adText or ""):find("FFA"),
   "og teksten blir teken vare på")
-- men den som leitar etter folk sel ingenting
ad("LFM Stockades boost, need 2 more", "Leitar-Firemaw")
eq(ChainDB.boosters["Leitar"], nil, "LFM er ikkje eit sal")
ad("WTB SM boost, paying well", "Kjopar-Firemaw")
eq(ChainDB.boosters["Kjopar"], nil, "WTB er ikkje eit sal")
-- og aliasa folk faktisk skriv
ad("WTS Mara boost 340-360 real mobs, 12min/run", "Mara-Firemaw")
eq(ChainDB.boosters["Mara"] and ChainDB.boosters["Mara"].adZone,
   "mara", "'Mara boost' blir kjend att")
ad("Wts SM Boost Cath & Arm, Wlc Lvl 20-42, FFA Loot", "Cath-Firemaw")
eq(ChainDB.boosters["Cath"] and ChainDB.boosters["Cath"].adZone,
   "sm", "'Cath & Arm' er SM")
ad("LF small group for questing", "Quest-Firemaw")
eq(ChainDB.boosters["Quest"], nil, "'small' skal ikkje matche SM")

-- annonsar skal lesast frå kva kanal som helst, og frå kvisk
do
  ChainDB.boosters = {}
  S.Fire(rf, "CHAT_MSG_WHISPER", "stockades 5 runs 250g mate", "Kviskrar-Firemaw")
  eq(ChainDB.boosters["Kviskrar"] and ChainDB.boosters["Kviskrar"].adPrice,
     250, "kvisk blir lest")
  eq(ChainDB.boosters["Kviskrar"].adFrom, "whisper", "og merka som kvisk")

  S.Fire(rf, "CHAT_MSG_YELL", "WTS SM boost 300g / 5 runs", "Ropar-Firemaw")
  ok(ChainDB.boosters["Ropar"] ~= nil, "yell blir lest")

  S.Fire(rf, "CHAT_MSG_PARTY", "sell stockades runs 60g each", "Gruppe-Firemaw")
  ok(ChainDB.boosters["Gruppe"] ~= nil, "party blir lest")
  eq(ChainDB.boosters["Gruppe"].adFrom, "party", "merka som party")

  -- ein namngjeven kanal, slik klienten sender han
  S.Fire(rf, "CHAT_MSG_CHANNEL", "Stockades 5 runs 200g", "Kanal-Firemaw",
         nil, "5. Boosting", nil, nil, nil, 5, "Boosting")
  eq(ChainDB.boosters["Kanal"] and ChainDB.boosters["Kanal"].adFrom,
     "channel:boosting", "kanalnamnet blir hugsa")

  -- vår eigen datakanal er aldri ein annonse
  S.Fire(rf, "CHAT_MSG_CHANNEL", "Stockades 5 runs 200g", "Falsk-Firemaw",
         nil, "5. ChainData", nil, nil, nil, 5, "ChainData")
  eq(ChainDB.boosters["Falsk"], nil, "vår eigen kanal blir ikkje lest")

  -- og du kan slå av ein kjelde
  BT.SetAdSource("whisper", false)
  S.Fire(rf, "CHAT_MSG_WHISPER", "stockades 5 runs 100g", "Stille-Firemaw")
  eq(ChainDB.boosters["Stille"], nil, "avslått kjelde blir ikkje lest")
  BT.SetAdSource("whisper", true)
  S.Fire(rf, "CHAT_MSG_WHISPER", "stockades 5 runs 100g", "Stille-Firemaw")
  ok(ChainDB.boosters["Stille"] ~= nil, "og lest igjen når du slår han på")

  -- lista over kjelder: dei faste, pluss kanalane du er i, utan våre eigne
  local list = BT.AdSourceList()
  local byKey = {}
  for _, src in ipairs(list) do byKey[src.key] = src end
  ok(byKey["say"] and byKey["whisper"] and byKey["guild"], "dei faste kjeldene er med")
  ok(byKey["channel:general"] and byKey["channel:trade"], "kanalane du er i er med")
  ok(byKey["channel:lookingforgroup"], "og LookingForGroup")
  ok(byKey["channel:general"].label:find("1%."), "med nummeret chat-vindauget brukar")
  -- General heiter "General - Stormwind City" i byen og noko anna utanfor:
  -- same kanal, same innstilling
  S.Fire(rf, "CHAT_MSG_CHANNEL", "Stockades 5 runs 200g", "Bymann-Firemaw",
         nil, "1. General - Stormwind City", nil, nil, nil, 1, "General - Stormwind City")
  eq(ChainDB.boosters["Bymann"].adFrom, "channel:general",
     "General i byen er General")
  BT.SetAdSource("channel:general", false)
  S.Fire(rf, "CHAT_MSG_CHANNEL", "Stockades 5 runs 200g", "Utabygds-Firemaw",
         nil, "1. General - Westfall", nil, nil, nil, 1, "General - Westfall")
  eq(ChainDB.boosters["Utabygds"], nil, "og General utanfor byen er same kanal")
  BT.SetAdSource("channel:general", true)
  ok(not byKey["channel:leveltrackerdata"], "men ikkje vår eigen")

  -- teljaren skal vise at noko faktisk blir lest
  local counted = 0
  for _, src in ipairs(BT.AdSourceList()) do counted = counted + (src.n or 0) end
  ok(counted > 0, "kjeldene teljer kva dei har gitt")
  ok(#BT.AdLog() > 0, "og dei siste annonsane blir hugsa")
  SlashCmdList["CHAIN"]("heard")

  -- og plukkaren skal teikne
  local okDraw, err = pcall(BT.ShowAdChannels)
  ok(okDraw, "kanal-plukkaren teiknar (" .. tostring(err) .. ")")
  local cf = _G.ChainAdChannels
  local shown = 0
  for _, r in ipairs(cf and cf.rows or {}) do
    if r:IsShown() and (r.label:GetText() or "") ~= "" then shown = shown + 1 end
  end
  ok(shown >= #list, "med ei rad per kjelde")
  BT.ShowAdChannels()
  ChainDB.boosters = {}
  ChainDB.adSources = nil
end

-- eigen pris slår annonsen
ad("WTS Stockades boost 40g per run, whisper me", "Selgar-Firemaw")
BT.SetPrice("Selgar", 30, 1)
near(BT.QuotedPrice("Selgar", "stock"), 30, "din eigen pris vinn")
eq(select(2, BT.QuotedPrice("Selgar", "stock")), "yours", "merka som din")

-- og dei dukkar opp i lista sjølv utan runs
local roster = BT.Roster("stock")
local names = {}
for _, r in ipairs(roster) do names[r.by] = r end
ok(names["Selgar"], "Selgar er i lista utan ein einaste run")
eq(names["Selgar"].n, 0, "null runs")
ChainDB.readAds = false
ad("WTS Maraudon boost 90g per run", "Seint-Firemaw")
eq(ChainDB.boosters["Seint"], nil, "kan slåast av")
ChainDB.readAds = true

--------------------------------------------------------------------------
print("== folk som leitar: LFM, LFG, WTB ==")
-- Alt LooksLikeAd kastar er nettopp det folk skriv mest av. Same lesinga,
-- same lista, same kvisk-knappen - ingenting blir matcha mot noko, teksten
-- blir teken vare på heil, og søkjeboksen er det som snevrar inn.
ChainDB.groups = {}
ChainDB.readGroups = true

local function grp(text, who, ...)
  S.now = S.now + 1                 -- chat does not arrive all in one second
  S.Fire(rf, "CHAT_MSG_CHANNEL", text, who or "Nokon-Firemaw", ...)
end

grp("LFM SM cath, need healer and 2 dps, lvl 30-38", "Leiar-Firemaw")
local g = BT.GroupLog()[1]
ok(g ~= nil, "LFM blir plukka opp")
eq(g and g.by, "Leiar", "kven som skreiv det")
eq(g and g.kind, "lfm", "merka som ei gruppe som blir fylt")
eq(g and g.id, "sm", "instansen blir kjend att")
eq(g and g.levels, "30-38", "level-spennet blir lese")
ok(g and (g.needs or ""):find("healer"), "og kva dei manglar (" ..
   tostring(g and g.needs) .. ")")
ok(g and (g.text or ""):find("cath"), "teksten blir teken vare på heil")

grp("LFG Stockades, rogue 24", "Leitar-Firemaw")
eq(BT.GroupLog()[1].kind, "lfg", "LFG er nokon som vil vere med")
eq(BT.GroupLog()[1].id, "stock", "og instansen blir kjend att")

grp("WTB SM boost, paying well", "Kjopar-Firemaw")
eq(BT.GroupLog()[1].kind, "wtb", "WTB er nokon som vil kjøpe")

-- LF2M med tal
grp("LF2M ZF, need tank", "Tal-Firemaw")
eq(BT.GroupLog()[1].kind, "lfm", "LF2M er òg ei gruppe som blir fylt")
ok((BT.GroupLog()[1].needs or ""):find("2 more"), "og talet blir lese")

-- ein quest utan instans: teksten er heile poenget
grp("LF3M for Uldaman quest chain, lvl 40+", "Questar-Firemaw")
local q = BT.GroupLog()[1]
eq(q.kind, "lfm", "quest-innlegg er berre eit innlegg til")
ok((q.text or ""):find("quest"), "og teksten står der du kan søkje i han")
eq(q.levels, "40+", "'40+' blir lese")

-- eit sal er ikkje ei gruppe, og ei gruppe er ikkje eit sal
ChainDB.boosters = {}
grp("WTS Stockades boost 40g per run", "Selgar2-Firemaw")
ok(ChainDB.boosters["Selgar2"] ~= nil, "salet hamnar hos boosterane")
local none = true
for _, e in ipairs(BT.GroupLog()) do
  if e.by == "Selgar2" then none = false end
end
ok(none, "og ikkje i gruppelista")

-- vanleg prat blir ikkje plukka opp
local before = #BT.GroupLog()
grp("anyone know where the blacksmith is", "Prat-Firemaw")
eq(#BT.GroupLog(), before, "vanleg prat blir ignorert")

-- same mann som skrik det same kvart halvminutt skal ikkje fylle lista
local n0 = #BT.GroupLog()
grp("LFM SM cath, need healer and 2 dps, lvl 30-38", "Leiar-Firemaw")
grp("LFM SM cath, need healer and 2 dps, lvl 30-38", "Leiar-Firemaw")
eq(#BT.GroupLog(), n0, "ei gjentaking lagar inga ny rad")
local rep
for _, e in ipairs(BT.GroupLog()) do
  if e.by == "Leiar" then rep = e break end
end
eq(rep and rep.n, 3, "men ho blir talt")
eq(BT.GroupLog()[1].by, "Leiar", "og flyttar seg øvst")

-- kjelder og av-brytar verkar som for annonsane
S.Fire(rf, "CHAT_MSG_YELL", "LFG RFD anyone", "Ropar2-Firemaw")
eq(BT.GroupLog()[1].from, "yell", "yell blir lese og merka")
ChainDB.readGroups = false
local n1 = #BT.GroupLog()
grp("LFM BRD, need 3", "Seint2-Firemaw")
eq(#BT.GroupLog(), n1, "kan slåast av")
ChainDB.readGroups = true

-- og lista har eit tak, så ho ikkje veks i det uendelege
for i = 1, 40 do grp("LFM Stockades run " .. i, "Spam" .. i .. "-Firemaw") end
ok(#BT.GroupLog() <= 150, "lista har eit tak (" .. #BT.GroupLog() .. ")")

-- fana teiknar dei
BT.ShowTab("groups")
do
  local w3 = _G.ChainWindow
  local drew = false
  for _, r in ipairs(w3.rows or {}) do
    if r:IsShown() and (r.cells[2]:GetText() or "") ~= "" then drew = true end
  end
  ok(drew, "Groups-fana har rader")
  local whispered = false
  for _, r in ipairs(w3.rows or {}) do
    if r:IsShown() and r.whisper and r.whisper:IsShown() then whispered = true end
  end
  ok(whispered, "og ein kvisk-knapp på kvar")
end

--------------------------------------------------------------------------
print("== knappen på minimapet ==")
-- Handrulla i staden for LibDBIcon: ingenting å sende med, ingenting å halde
-- oppdatert, og ingenting som sluttar å virke når eit anna addon oppdaterer.
ChainDB.minimap = true
BT.RefreshMinimap()
local mb = _G.ChainMinimapButton
ok(mb ~= nil, "knappen blir bygd")
ok(mb and mb:IsShown(), "og er synleg")
do
  local pts = mb:GetPoints()
  ok(#pts > 0, "han er plassert på minimapet")
  local p = pts[#pts]
  ok(p.rel == _G.Minimap, "festa til minimapet")
  -- 205 grader: nede til venstre, som er der knappar plar hamne
  local r = math.sqrt(p.x * p.x + p.y * p.y)
  ok(math.abs(r - 80) < 1, "på kanten, ikkje midt oppi kartet (r=" ..
     string.format("%.1f", r) .. ")")
end

-- dra han rundt kanten
do
  local before = ChainDB.minimapAngle
  mb.__scripts.OnDragStart(mb)
  S.cursor = { 600 + 100, 400 }            -- rett til høgre for midten
  mb.__scripts.OnUpdate(mb, 0)
  mb.__scripts.OnDragStop(mb)
  ok(ChainDB.minimapAngle ~= before, "å dra flyttar han")
  ok(math.abs(ChainDB.minimapAngle) < 1, "og vinkelen fylgjer peikaren")
  local p = mb:GetPoints()[#mb:GetPoints()]
  ok(math.abs(p.x - 80) < 1 and math.abs(p.y) < 1, "så han hamnar der du slepp")
end

-- klikka gjer tre ulike ting
do
  local w = _G.ChainWindow
  if w and w:IsShown() then BT.ToggleWindow() end
  mb.__scripts.OnClick(mb, "LeftButton")
  ok(_G.ChainWindow and _G.ChainWindow:IsShown(), "venstreklikk opnar vindauget")
  mb.__scripts.OnClick(mb, "LeftButton")
  if _G.ChainOptions and _G.ChainOptions:IsShown() then BT.ToggleOptions() end
  mb.__scripts.OnClick(mb, "RightButton")
  ok(_G.ChainOptions and _G.ChainOptions:IsShown(), "høgreklikk opnar innstillingane")
  BT.ToggleOptions()
  local shownBefore = ChainDB.shown
  mb.__scripts.OnClick(mb, "MiddleButton")
  ok(ChainDB.shown ~= shownBefore, "midtklikk skjuler baren")
  mb.__scripts.OnClick(mb, "MiddleButton")
end

-- tooltipen seier det du ville opna vindauget for
do
  mb.__scripts.OnEnter(mb)
  local tip = S.TipText()
  ok(tip:find("instances this hour"), "tooltipen seier lockouten")
  ok(tip:find("Left%-click"), "og kva knappane gjer")
end

-- og han kan skruast av
ok(BT.ToggleMinimap() == false, "kan slåast av")
ok(not mb:IsShown(), "og då er han borte")
BT.ToggleMinimap()
ok(mb:IsShown(), "og på igjen")

-- ikonfilene må finnast, og vere TGA-ar spelet kan lese
do
  -- den addon-lista viser ved sida av namnet, og som .toc-en peikar på
  local toc = io.open(DIR .. "Chain.toc", "r")
  ok(toc ~= nil, "Chain.toc finst")
  if toc then
    local body = toc:read("*a"); toc:close()
    ok(body:find("IconTexture"), "toc-en peikar på eit ikon")
    local named = body:match("IconTexture:%s*(.-)%s*\n")
    local file = named and named:match("([^\\]+)$")
    local fh = file and io.open(DIR .. file .. ".tga", "rb")
    ok(fh ~= nil, "og fila den peikar på ligg der (" .. tostring(file) .. ".tga)")
    if fh then fh:close() end
  end

  local path = DIR .. "minimap.tga"
  local fh = io.open(path, "rb")
  ok(fh ~= nil, "minimap.tga finst")
  if fh then
    local head = fh:read(18)
    fh:close()
    eq(head:byte(3), 2, "ukomprimert true-colour")
    eq(head:byte(17), 32, "32 bit, altså med alfa")
    local w = head:byte(13) + head:byte(14) * 256
    eq(w, 64, "64 pikslar brei - ein toarpotens, som klienten krev")
  end
end

--------------------------------------------------------------------------
print("== deling mellom addonar ==")
S.sent, S.channels = {}, {}
ChainDB.share = false
eq(BT.ShareAll(), 0, "sender ingenting når deling er av")
ChainDB.share = true
BT.SetPrice("Selgar", 30, 1)
BT.SetPrice("Rask", 40, 1)
S.timers = {}
local n = BT.ShareAll()
ok(n >= 2, "la fleire i kø")
eq(#S.sent, 0, "ingenting går ut i same augneblink")
eq(S.channels["ChainData"] ~= nil, true, "vi blei med i kanalen")
-- meldingane kjem etter kvart, ei om gongen
S.RunTimers()
eq(S.sent[1].ch, "CHANNEL", "går over eigen kanal, ikkje guild eller party")
ok(S.sent[1].msg:find("^v2|"), "protokollversjon først")
eq(#S.sent, n, "alle sendte til slutt")
eq(BT.ShareQueued(), 0, "køen er tom")

-- same booster to gonger i køen skal ikkje bli to meldingar
S.sent, S.timers = {}, {}
BT.ShareOne("Selgar"); BT.ShareOne("Selgar"); BT.ShareOne("Selgar")
S.RunTimers()
eq(#S.sent, 1, "same booster blir slått saman i køen")

-- tommelen skal aldri ut på nettverket
for _, m in ipairs(S.sent) do
  ok(not m.msg:find("vote"), "ingen dom i meldinga")
  eq(select(2, m.msg:gsub("|", "|")), 8, "v2 har åtte skiljeteikn")
end

-- mottak frå ein annan spelar: rein måling
local function report(from, name, id, price, pack, xp, t, mobs, n)
  S.Fire(rf, "CHAT_MSG_ADDON", "LVLTRK1",
    table.concat({ "v2", name, id, price, pack, xp, t, mobs, n }, "|"),
    "CHANNEL", from)
end
report("Venn-Firemaw", "Torkel", "stock", 45, 5, 8000, 480, 80, 10)
local sh = BT.SharedStats("Torkel", "stock")
ok(sh ~= nil, "rapport motteken")
eq(sh.people, 1, "ein rapportør")
near(sh.mobs, 80, "mobs frå rapporten")
near(BT.QuotedPrice("Torkel", "stock"), 9, "45g for 5 runs = 9g per run")
eq(select(2, BT.QuotedPrice("Torkel", "stock")), "reported", "merka som rapportert")

-- same person sender på nytt: skal erstatte, ikkje leggast til
report("Venn-Firemaw", "Torkel", "stock", 45, 5, 9000, 480, 90, 10)
sh = BT.SharedStats("Torkel", "stock")
eq(sh.people, 1, "framleis ein rapportør")
near(sh.mobs, 90, "nyaste tal gjeld")

-- to personar, vekta etter kor mange runs dei har bak seg
report("Annan-Firemaw", "Torkel", "stock", 45, 5, 3000, 480, 30, 90)
sh = BT.SharedStats("Torkel", "stock")
eq(sh.people, 2, "to rapportørar")
ok(sh.mobs < 45, "den med 90 runs veg tyngst (" .. string.format("%.0f", sh.mobs) .. ")")

-- ekko av oss sjølve, feil prefiks og søppel
report("Tester", "Torkel", "stock", 45, 5, 9000, 480, 90, 10)
eq(BT.SharedStats("Torkel", "stock").people, 2, "vårt eige ekko tel ikkje")
S.Fire(rf, "CHAT_MSG_ADDON", "LVLTRK1", "tull", "CHANNEL", "Venn-Firemaw")
S.Fire(rf, "CHAT_MSG_ADDON", "ANNAPREFIX", "v2|X|stock|1|1|1|1|1|1", "CHANNEL", "Venn-Firemaw")
eq(ChainDB.boosters["X"], nil, "feil prefiks blir ignorert")
report("Venn-Firemaw", "Y", "ikkje-ein-instans", 1, 1, 1, 1, 1, 1)
eq(ChainDB.boosters["Y"], nil, "ukjend instans blir ignorert")
-- gammal protokoll blir ignorert
S.Fire(rf, "CHAT_MSG_ADDON", "LVLTRK1", "v1|Gammal|45|5|1", "CHANNEL", "Venn-Firemaw")
eq(ChainDB.boosters["Gammal"], nil, "v1 blir ignorert")
-- delingsomfang: kven som høyrer deg
eq(BT.ShareScopeName(), "everyone with the addon", "standard er alle")
S.sent, S.timers = {}, {}
BT.CycleShareScope()
eq(ChainDB.shareWith, "guild", "neste er gildet")
BT.SetPrice("Selgar", 30)
BT.ShareOne("Selgar", "stock")
S.RunTimers()
eq(S.sent[1] and S.sent[1].ch, "GUILD", "går til gildet")
S.sent, S.timers = {}, {}
BT.CycleShareScope()
eq(ChainDB.shareWith, "friends", "så namneliste")
BT.SetShareFriends("Kompis-Firemaw, Annan , ")
eq(#ChainDB.shareFriends, 2, "to namn, tomme hoppa over")
eq(ChainDB.shareFriends[1], "Kompis", "realm stripa bort")
BT.ShareOne("Selgar", "stock")
S.RunTimers()
eq(#S.sent, 2, "ei kviskring per namn")
eq(S.sent[1].ch, "WHISPER", "som whisper")
eq(S.sent[1].target, "Kompis", "til rett person")
BT.CycleShareScope()
eq(ChainDB.shareWith, "all", "og rundt att")
ChainDB.share = false

--------------------------------------------------------------------------
print("== xp-fall og når du bør byte ==")
-- grå-grensa: mobs under denne gjev ingenting
eq(BT.GreyLevel(20), 13, "grå-grense på level 20")
eq(BT.GreyLevel(30), 22, "grå-grense på level 30")
eq(BT.GreyLevel(60), 51, "grå-grense på level 60")
eq(BT.MobXP(30, 20), 0, "ein grå mob er verdt null")
ok(BT.MobXP(22, 25) > BT.MobXP(22, 22), "høgare mob gjev meir")
ok(BT.MobXP(27, 24) < BT.MobXP(24, 24), "same mob gjev mindre når du veks")

-- ein instans blir gradvis verdlaus
local stock = BT.BY_ID["stock"]
local v22, v27, v33 = BT.RunValue(stock, 22), BT.RunValue(stock, 27), BT.RunValue(stock, 33)
ok(v22 > v27 and v27 > v33, "Stockades fell i verdi med levelen din")
eq(BT.RunValue(stock, 35), 0, "og er heilt grå til slutt")
print(string.format("   Stockades: lvl 22 = %.0f, lvl 27 = %.0f, lvl 33 = %.0f, lvl 35 = %.0f",
  v22, v27, v33, BT.RunValue(stock, 35)))

-- målte tal slår modellen
ChainDB.runs = {}
for i = 1, 3 do
  table.insert(ChainDB.runs, { at = S.now, t = 300, zone = "The Stockade",
    map = 34, id = "stock", by = "Misscall", xp = 9000, k = 90, lvl = 22 })
end
BT.Touch()
S.party = { { name = "Misscall-Firemaw", lvl = 60 } }
S.level = 22
local xp, how = BT.PredictRun(stock, 22)
eq(how, "measured", "eige tal på det levelet du har data for")
near(xp, 9000, "og det er det du målte")
local xp27 = BT.PredictRun(stock, 27)
ok(xp27 < xp, "høgare level gjev mindre, forankra i målinga di")
print(string.format("   målt 9 000 på lvl 22 -> anslag %.0f på lvl 27", xp27))

-- og rådet: SM blir billegare enn Stockades etter kvart
ChainDB.route.stock = { on = true, from = 18, to = 34, gold = 50 }
ChainDB.route.sm = { on = true, from = 28, to = 42, gold = 50 }
for i = 1, 3 do
  table.insert(ChainDB.runs, { at = S.now, t = 300, zone = "Scarlet Monastery",
    map = 189, id = "sm", by = "Misscall", xp = 9000, k = 90, lvl = 34 })
end
BT.Touch()
local lvlAt, best = BT.SwitchAt(BT.BY_ID["stock"], "Misscall")
ok(lvlAt ~= nil, "den finn eit byttepunkt")
eq(best and best.id, "sm", "og peikar på SM")
ok(lvlAt >= 28, "men ikkje før levelet du sette for SM")
print(string.format("   byt til %s på level %s", best and best.label or "?", tostring(lvlAt)))
ChainDB.runs = {}
ChainDB.route.sm = nil
BT.Touch()

--------------------------------------------------------------------------
print("== cache og yting ==")
-- ein skriving utan Touch skal likevel bli oppdaga
local before = #BT.Runs({ id = "stock" })
table.insert(ChainDB.runs, { at = S.now, t = 400, zone = "The Stockade",
  id = "stock", by = "Misscall", xp = 9999, k = 80, lvl = 22 })
eq(#BT.Runs({ id = "stock" }), before + 1, "cachen ser ein skriving utan Touch")

-- 2 000 runs og 200 fulle oppteikningar
ChainDB.runs = {}
for i = 1, 2000 do
  table.insert(ChainDB.runs, { at = S.now - i * 600, t = 400 + i % 120,
    zone = "The Stockade", id = "stock", by = (i % 3 == 0) and "Torkel" or "Misscall",
    xp = 8000 + i % 2000, k = 85, lvl = 20 + i % 10, grp = 5, grpAvg = 30 })
end
BT.Touch()
S.zone, S.map, S.inInstance = "The Stockade", 34, true
S.party = { { name = "Misscall-Firemaw", lvl = 60 } }
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
local t0 = os.clock()
for i = 1, 200 do BT.BuildText() end
local ms = (os.clock() - t0) * 1000 / 200
print(string.format("   %.2f ms per oppteikning med 2 000 runs", ms))
ok(ms < 5, string.format("oppteikninga må vere under 5 ms (var %.2f)", ms))

-- combat log skal ikkje teikne opp att
local drew = 0
local realRefresh = BT.Refresh
BT.Refresh = function() drew = drew + 1 end
ChainCharDB.run.instId = "123"
for i = 1, 500 do S.Fire(frame, "COMBAT_LOG_EVENT_UNFILTERED") end
eq(drew, 0, "combat log teiknar ikkje opp att")
BT.Refresh = realRefresh

--------------------------------------------------------------------------
print("== overskrifta på baren ==")
-- Etiketten skal seie spennet du sette, ikkje kvar du har kome. Rekninga
-- under må starte frå level ditt - du kan ikkje tene xp du alt har - men
-- overskrifta arva den klemminga og endra seg kvart einaste level.
do
  local keepRoute = ChainDB.route
  ChainDB.route = {}
  for _, d in ipairs(BT.DUNGEONS) do
    ChainDB.route[d.id] = { on = false, from = d.lo, to = d.hi, gold = 0 }
  end
  ChainDB.route.sm = { on = true, from = 28, to = 42, gold = 400, pack = 10 }
  S.level = 34
  S.xp, S.xpMax = 5000, 100000
  BT.Touch()
  local slots = BT.BuildText()
  ok((slots.topLeft or ""):find("28 > 42"),
     "overskrifta seier spennet du sette (" .. tostring(slots.topLeft) .. ")")
  ok(not (slots.topLeft or ""):find("34 > 42"),
     "og ikkje kva level du tilfeldigvis er")

  -- men det som står att skal framleis reknast frå der du faktisk er
  local done, total, remain, _, step, base = BT.StageSpan()
  eq(base, 34, "rekninga startar frå level ditt")
  eq(step.from, 28, "medan steget hugsar kva du sette")
  near(remain, BT.Span(34, 42) - 5000, "og det som står att er til 42 herifrå", 1)

  -- og den endrar seg ikkje når du levlar
  S.level = 36
  BT.Touch()
  slots = BT.BuildText()
  ok((slots.topLeft or ""):find("28 > 42"), "overskrifta står stille når du levlar")

  S.level = 20
  S.xp, S.xpMax = 0, 23200
  ChainDB.route = keepRoute
  BT.Touch()
end

--------------------------------------------------------------------------
print("== ærens-systemet ==")
-- Kjeda er tre steg, og ingen av dei gjer klienten for deg: honor -> CP i tre
-- vekslingsband, CP -> rank og posisjon, og så ein brøkdel av spranget som
-- krympar med ranken. Tala er systemet sine eigne, men rekninga er vår, så
-- den blir testa frå begge endar.
do
  -- vekslinga, og at han går rett veg tilbake
  near(BT.HonorToCP(0), 0, "null honor er null CP")
  near(BT.HonorToCP(45000), 20000, "45k honor er 20k CP", 1)
  near(BT.HonorToCP(22500), 10000, "halvvegs i fyrste bandet", 1)
  near(BT.HonorToCP(175000), 40000, "175k honor er 40k CP", 1)
  near(BT.HonorToCP(500000), 60000, "500k honor er 60k CP", 1)
  -- og at bandet faktisk blir verre: same honor kjøper mindre høgare oppe
  local first = BT.HonorToCP(45000) - BT.HonorToCP(0)
  local third = BT.HonorToCP(500000) - BT.HonorToCP(455000)
  ok(third < first, "same honor kjøper mindre CP høgare oppe (" ..
     string.format("%.0f mot %.0f", third, first) .. ")")
  for _, h in ipairs({ 0, 10000, 45000, 90000, 175000, 300000, 500000 }) do
    near(BT.CPToHonor(BT.HonorToCP(h)), h, "fram og tilbake på " .. h, 2)
  end

  -- CP til rank
  local r, p = BT.CPToRank(0)
  eq(r, 1, "null CP er rank 1")
  r, p = BT.CPToRank(2000)
  eq(r, 2, "2000 CP er rank 2")
  r, p = BT.CPToRank(3500)
  eq(r, 2, "3500 CP er framleis rank 2")
  near(p, 0.5, "og halvvegs gjennom han", 0.01)
  r = BT.CPToRank(65000)
  eq(r, 14, "taket er rank 14")
  near(BT.RankCP(2, 0.5), 3500, "og vegen tilbake stemmer", 1)

  -- sjølve spådommen: du reiser ein brøkdel av vegen, og brøken krympar
  do
    local nr, np, change = BT.PredictReset(1, 0, 45000)
    ok(change > 0, "ei veke med honor flyttar deg framover")
    ok(nr > 1, "og opp i rank (" .. nr .. ")")
    -- same honor, høg rank: mindre framgang, fordi faktoren er mindre
    local _, _, lowChange = BT.PredictReset(2, 0, 60000)
    local _, _, highChange = BT.PredictReset(13, 0, 60000)
    ok(highChange < lowChange,
       "same veke flyttar deg mindre på høg rank")
  end

  -- og bakover: null honor er eit fall
  do
    local nr, _, change = BT.PredictReset(8, 0.5, 0)
    ok(change < 0, "ei veke utan honor kostar deg CP")
    ok(nr <= 8, "og kan koste deg ranken (" .. nr .. ")")
  end

  -- talet folk faktisk vil ha: kor mykje som skal til for å ikkje falle
  do
    local hold = BT.HonorToHold(8, 0.5)
    ok(hold > 0, "det finst eit tal som held deg i ro")
    local _, _, change = BT.PredictReset(8, 0.5, hold)
    near(change, 0, "og med akkurat det står du stille", 1)
    local _, _, under = BT.PredictReset(8, 0.5, hold * 0.5)
    ok(under < 0, "under det fell du")
    local _, _, over = BT.PredictReset(8, 0.5, hold * 1.5)
    ok(over > 0, "over det stig du")
  end

  -- og kor mykje til neste rank
  do
    local need = BT.HonorForRank(5, 0, 6, 0)
    ok(need and need > 0, "det finst eit tal for neste rank")
    local nr = BT.PredictReset(5, 0, need)
    ok(nr >= 6, "og med det talet kjem du dit (" .. tostring(nr) .. ")")
    -- På rank 1 er faktoren 1,0, så du reiser heile vegen: rank 14 på ei veke
    -- er faktisk mogleg i systemet, berre ikkje i eit liv. Funksjonen svarar
    -- på "kor mykje honor", ikkje "er dette realistisk".
    local wild = BT.HonorForRank(1, 0, 14, 0)
    ok(wild and wild >= 400000, "rank 14 frå rank 1 er eit enormt, men ekte tal")
    -- høgt oppe er faktoren 0,4, og då finst det ranksprang som ikkje går
    eq(BT.HonorForRank(13, 0, 14, 0), nil,
       "rank 13 til 14 på ei veke: ikkje mogleg, og det blir sagt")
  end

  -- honor per time, same maskineri som xp per time
  do
    ChainCharDB.honorBuckets, ChainCharDB.honorSession = {}, 0
    ChainCharDB.honorSeen = nil
    S.weekHonor = 0
    BT.PollHonor()
    S.weekHonor = 300
    BT.PollHonor()
    eq(ChainCharDB.honorSession, 300, "honor blir talt frå klienten si eiga teljing")
    S.now = S.now + 600
    S.weekHonor = 600
    BT.PollHonor()
    eq(ChainCharDB.honorSession, 600, "og summert vidare")
    local rate = BT.HonorRate()
    ok(rate and rate > 0, "det blir ein rate av det (" ..
       string.format("%.0f/t", rate or 0) .. ")")
    -- eit reset tek teljinga til null, og det er ikkje eit tap
    S.weekHonor = 0
    BT.PollHonor()
    eq(ChainCharDB.honorSession, 0, "resetet nullstiller i staden for å telje ned")
  end

  -- og heile tilstanden på ein gong
  do
    S.pvpRank, S.pvpProgress = 6, 0.25
    S.weekHonor, S.weekKills = 30000, 42
    local st = BT.PvPState()
    eq(st.rank, 6, "ranken din")
    eq(st.kills, 42, "og drapa")
    ok(st.newRankName ~= nil, "det er eit namn på der du hamnar")
    ok(st.hold > 0, "og eit tal som held deg i ro")
    ok(BT.PvPChunk() ~= nil, "og ei linje å setje på skjermen")
  end
end

--------------------------------------------------------------------------
print("== namnebytet ==")
-- Level Tracker, så LevelBar, no Chain. Tre namn på lagringa, og ein tom
-- historikk er det siste nokon vil ha ut av eit namnebyte. Dette er den
-- delen av eit byte som faktisk kan koste deg noko, så han blir testa.
do
  local keepDB, keepChar = ChainDB, ChainCharDB
  local frame2 = BT.frame

  -- Den avgjerande: WoW lastar addons alfabetisk, så Chain er oppe før
  -- LevelBar, og ved vår eigen ADDON_LOADED finst ikkje dei gamle dataa enno.
  -- PLAYER_LOGIN kjem etter at alt er lasta - det er der dei blir funne.
  ChainDB = BT.ApplyDefaults({}, BT.DEFAULTS)
  ChainCharDB = BT.ApplyDefaults({}, BT.CHAR_DEFAULTS)
  _G.LevelBarDB = { runs = { { at = 1, xp = 100, zone = "The Stockade" } },
                    trades = {}, entries = {}, boosters = {} }
  S.Fire(frame2, "PLAYER_LOGIN")
  eq(#ChainDB.runs, 1, "PLAYER_LOGIN finn dei gamle dataa")
  _G.LevelBarDB = nil

  -- og ein tom gammal database skal ikkje byte ut ein som er i bruk
  ChainDB = BT.ApplyDefaults({ runs = { { at = 5, xp = 5 } } }, BT.DEFAULTS)
  _G.LevelBarDB = { runs = {}, trades = {}, entries = {}, boosters = {} }
  S.Fire(frame2, "PLAYER_LOGIN")
  eq(#ChainDB.runs, 1, "ein tom gammal database tek ikkje over")
  _G.LevelBarDB = nil

  -- kjem frå LevelBar
  ChainDB, ChainCharDB = nil, nil
  _G.LevelBarDB = { runs = { { at = 1, xp = 100, zone = "The Stockade" } },
                    trades = { { at = 1, gave = 500 } },
                    entries = { { t = 1, seq = "a" } },
                    boosters = { Gammal = { price = 40, pack = 5 } } }
  _G.LevelBarCharDB = { levelAt = 1234 }
  S.Fire(frame2, "ADDON_LOADED", "Chain")
  eq(#ChainDB.runs, 1, "runs blir med over frå LevelBar")
  eq(#ChainDB.trades, 1, "trades òg")
  eq(#ChainDB.entries, 1, "og instansloggen")
  ok(ChainDB.boosters and ChainDB.boosters.Gammal, "og boosterane")
  eq(ChainCharDB.levelAt, 1234, "karakterdataa likeeins")
  ok(ChainDB.limit ~= nil, "og standardane blir lagt oppå, ikkje i staden for")

  -- og frå det aller fyrste namnet, om nokon hoppar over eit ledd
  ChainDB, ChainCharDB = nil, nil
  _G.LevelBarDB, _G.LevelBarCharDB = nil, nil
  _G.LevelTrackerDB = { runs = { { at = 2, xp = 200 }, { at = 3, xp = 300 } } }
  S.Fire(frame2, "ADDON_LOADED", "Chain")
  eq(#ChainDB.runs, 2, "og frå Level Tracker for den som hoppa over LevelBar")

  -- ein som alt har Chain-data skal ikkje få dei overskrivne
  ChainDB = { runs = { { at = 9, xp = 900 } } }
  ChainCharDB = { levelAt = 99 }
  _G.LevelBarDB = { runs = { { at = 1, xp = 1 }, { at = 2, xp = 2 } } }
  S.Fire(frame2, "ADDON_LOADED", "Chain")
  eq(#ChainDB.runs, 1, "eigne data blir ikkje overskrivne av dei gamle")
  eq(ChainCharDB.levelAt, 99, "heller ikkje karakterdataa")

  _G.LevelBarDB, _G.LevelBarCharDB, _G.LevelTrackerDB = nil, nil, nil
  ChainDB, ChainCharDB = keepDB, keepChar
end

-- og namna addonen svarar på
ok(_G.Chain == _G.LevelBar, "dei gamle globalane peikar på det same")
ok(SLASH_CHAIN1 == "/chain", "/chain er fyrste slash-kommando")
do
  local old = false
  for i = 1, 9 do
    if _G["SLASH_CHAIN" .. i] == "/levelbar" then old = true end
  end
  ok(old, "og /levelbar verkar framleis")
end

--------------------------------------------------------------------------
print(string.format("\n%d ok, %d feil", pass, fail))
if fail > 0 then os.exit(1) end
