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
for _, f in ipairs({ "Data.lua", "Stats.lua", "Decay.lua", "Core.lua", "Trade.lua", "Loot.lua",
                     "PvP.lua", "Enemy.lua", "Roster.lua", "Meter.lua", "Bar.lua", "Minimap.lua", "Window.lua",
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

-- Tooltipen på baren vaks ut av éin kolonne: på ein 1080 høg skjerm gjekk han
-- frå topp til botn, og då er det ikkje ein tooltip lenger, det er ei side.
-- Delinga går etter emne, ikkje etter linjetal: det du gjer til venstre, kven
-- du gjer det med og kvar du står til høgre.
local function TwoColumns(what)
  local tip = BT.SideTooltip and BT.SideTooltip()
  ok(tip ~= nil, "det finst ein kolonne to")
  if not tip then return end
  -- tel linjene i kvar kolonne kvar for seg
  local left, right = 0, 0
  -- med ein run i gang, som er når tooltipen er på sitt lengste
  local keepRun = ChainCharDB.run
  ChainCharDB.run = { zone = "The Stockade", map = 34, id = "stock",
                      start = S.now - 300, xp = 6000, k = 40, lvl = 23,
                      by = BT.CurrentBooster() }
  tip.__lines = 0
  local realAdd, realDouble = tip.AddLine, tip.AddDoubleLine
  local gAdd, gDouble = GameTooltip.AddLine, GameTooltip.AddDoubleLine
  local leftText, rightText = {}, {}
  tip.AddLine = function(self, t, ...) right = right + 1
    rightText[#rightText + 1] = tostring(t or "") return realAdd(self, t, ...) end
  tip.AddDoubleLine = function(self, l, ...) right = right + 1
    rightText[#rightText + 1] = tostring(l or "")
    return realDouble(self, l, ...) end
  GameTooltip.AddLine = function(self, t, ...) left = left + 1
    leftText[#leftText + 1] = tostring(t or "") return gAdd(self, t, ...) end
  GameTooltip.AddDoubleLine = function(self, l, ...) left = left + 1
    leftText[#leftText + 1] = tostring(l or "")
    return gDouble(self, l, ...) end
  BT.BarTooltip(GameTooltip)
  tip.AddLine, tip.AddDoubleLine = realAdd, realDouble
  GameTooltip.AddLine, GameTooltip.AddDoubleLine = gAdd, gDouble

  ChainCharDB.run = keepRun
  ok(right > 0, (what or "tooltipen") .. " brukar begge kolonnane")
  -- og dei skal vere omtrent like høge: ein kolonne som er dobbelt så lang
  -- som den andre les som ein tooltip som har sprukke, ikkje som eit oppsett
  -- Kva kolonne eit avsnitt hamnar i er ei vurdering av avsnittet, ikkje av
  -- kor mykje plass som er att: runen du står i høyrer saman med det du gjer,
  -- ikkje med kven du gjer det med.
  local function inColumn(list, needle)
    for _, t in ipairs(list) do if t:find(needle, 1, true) then return true end end
    return false
  end
  ok(inColumn(leftText, "this run"), "runen du står i står i fyrste kolonne")
  ok(inColumn(rightText, "xp per hour"), "og boosteren sine tal i den andre")

  local tall, short = math.max(left, right), math.min(left, right)
  ok(short * 2 >= tall, (what or "tooltipen") .. " er skeiv: "
     .. left .. " mot " .. right .. " linjer")
end

-- Dei to hjørna under baren er EI linje: ein fontstring festa i venstre enden
-- og ein i høgre, med ingenting mellom seg enn breidda på baren. Tekst som
-- ikkje får plass der brytar ikkje - den blir teikna rett oppå det andre
-- hjørnet. Linjelengd-testen sjekkar kvar linje for seg, så to hjørne som
-- kvar for seg er korte nok gjekk rett forbi han.
local function CornersFit(what)
  local sl = BT.BuildText() or {}
  local l = BT.VisLen(sl.bottomLeft or "")
  -- farta ligg mellom dei og tel med i det som skal få plass på linja
  local r = BT.VisLen(sl.bottomRight or "") + BT.VisLen(sl.bottomCenter or "")
  local cap = (BT.Budget and BT.Budget()) or 74
  ok(l + r + 3 <= cap, (what or "hjørna") .. " kolliderer: " .. (l + r + 3)
     .. " teikn av " .. cap .. " - \"" .. tostring(sl.bottomLeft) .. "\" / \""
     .. tostring(sl.bottomRight) .. "\"")
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
S.party = { { name = "Boostar-Testrealm", lvl = 60 } }
S.zone, S.map, S.inInstance = "The Stockade", 34, true
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
ok(ChainCharDB.run ~= nil, "run starta")
eq(ChainCharDB.run.by, "Boostar", "booster identifisert utan realm")
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
eq(ChainDB.runs[1].by, "Boostar", "lagra booster")

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
S.party = { { name = "Boostar-Testrealm", lvl = 60 } }

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
eq(ChainDB.runs[1].by, "Boostar", "og boosteren")

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
for i = 1, 4 do record("Boostar", 9000, 420, 90) end
for i = 1, 4 do record("Snoegg", 5000, 720, 55) end

S.level, S.xp = 20, 0
S.party = { { name = "Boostar-Testrealm", lvl = 60 } }
local _, step = BT.Stage()
local st, borrowed, who = BT.StepStats(step)
eq(who, "Boostar", "brukar Boostar sine tal")
near(st.xp, 9000, "Boostar xp/run")
local fastRuns = BT.Forecast()

S.party = { { name = "Snoegg-Testrealm", lvl = 60 } }
st, borrowed, who = BT.StepStats(step)
eq(who, "Snoegg", "brukar Snoegg sine tal")
near(st.xp, 5000, "Snoegg xp/run")
local slowRuns = BT.Forecast()
ok(slowRuns > fastRuns * 1.5, "treg booster gjev mange fleire runs")
print(string.format("   Boostar %.1f runs, Snoegg %.1f runs", fastRuns, slowRuns))

-- ny booster utan nok data
S.party = { { name = "Ny-Testrealm", lvl = 60 } }
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
S.party = { { name = "Boostar-Testrealm", lvl = 60 } }
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
  by = "Sjekkar", xp = 8565, k = 93, lvl = 26 })
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
S.party = { { name = "Boostar-Testrealm", lvl = 60 } }
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
S.party = { { name = "Boostar-Testrealm", lvl = 60 } }
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
for i = 1, 5 do S.now = S.now + 180 BT.NoteEntry() end
local count, freeOne, freeAll, fromNIT, daily = BT.Lockout()
eq(count, 5, "fem instansar")
eq(daily, 5, "fem i døgnet òg")
eq(fromNIT, false, "utan NIT brukar vi vår eigen logg")
ok(freeOne and freeOne > 2500, "nedteljing til neste ledige")

-- timesgrensa er per karakter, døgngrensa er kontovid
for i = 1, 7 do
  table.insert(ChainDB.entries,
    { t = S.now - 7200 - i * 300, seq = "Alt:" .. i, char = "Alt" })
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
  -- godt bak våre eigne, så minutt-nøkkelen i importen ikkje kolliderer
  { enteredTime = S.now - 1000, zone = "The Stockade", playerName = "Tester" },
  { enteredTime = S.now - 1200, zone = "The Stockade", playerName = "Tester" },
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
-- "+1 in 9m" ved sida av 3/5 les som ei venting, og det er inga venting: du
-- har to i handa. Klokka svarar berre på eit spørsmål du faktisk stiller når
-- døra er stengd.
do
  local before = ChainDB.entries
  ChainDB.entries = { { t = S.now - 100, seq = "u1", char = "Tester" },
                      { t = S.now - 200, seq = "u2", char = "Tester" } }
  ChainCharDB.lockedAt, ChainCharDB.lockMissing = nil, nil
  S.level, S.xp, S.xpMax = 23, 12000, 31700
  local body = table.concat(BT.AllLines(), "\n")
  ok(body:find("inst 2/5"), "baren seier kor mange du har brukt")
  ok(body:find("3 to go"), "og kor mange du har att, ikkje ei nedteljing")
  ok(not body:find("%+1 in"), "for det er ingenting å vente på")
  ChainDB.entries = before
end

ok(freeAll and freeOne <= freeAll,
   "ein blir ledig før alle blir det (" .. tostring(freeOne) .. " <= "
   .. tostring(freeAll) .. ")")

-- Og det spelet la til skal ikkje bli liggjande. Slepp spelet deg inn, var
-- du ikkje på taket likevel - same beviset den andre vegen. Utan dette stod
-- gjettinga i timen og baren klatra til 7/5, som er eit tal spelet ikkje gjev
-- deg.
do
  eq(BT.Lockout(), 5, "fem no")
  S.zone, S.map, S.inInstance = "Stormwind Stockade", 34, true
  S.now = S.now + 60
  BT.NoteEntry()
  local n = BT.Lockout()
  eq(n, 5, "og fem etter at spelet slapp deg inn - ikkje seks")
  S.now = S.now + 60
  BT.NoteEntry()
  eq(BT.Lockout(), 5, "og framleis fem")
  local one, all = select(2, BT.Lockout())
  ok(one <= all, "og klokkene står framleis rett veg")
  S.inInstance = false
end

-- Nedteljinga, sagt høgt. Ei gruppe som står ved summoning-steinen ventar på
-- det talet nokon må spørje om heile tida. Så det blir sagt på ein rytme i
-- staden for kvar gong noko dultar borti det: kvart femte minutt medan det er
-- langt fram, ein gong på eitt minutt, og ein gong når det losnar.
do
  local before = ChainDB.entries
  local oldAnnounce = ChainDB.announceLock
  ChainDB.announceLock = true
  ChainCharDB.toldLocked, ChainCharDB.toldMark = nil, nil
  ChainCharDB.lockedAt, ChainCharDB.lockMissing = nil, nil
  S.party = { { name = "Boostar-Testrealm", lvl = 60 } }

  local function said()
    local out = S.said[#S.said]
    S.said = {}
    return out
  end
  local function lockAt(secondsLeft)
    -- fem inngangar, den eldste akkurat så gammal at det er så lenge att
    ChainDB.entries = {}
    for i = 1, 5 do
      table.insert(ChainDB.entries,
        { t = S.now - (3600 - secondsLeft) + (i - 1), seq = "l" .. i,
          char = "Tester" })
    end
  end

  -- Inne i instansen seier han ingenting. Du kjem på taket ved å gå inn, så
  -- det var akkurat då linja kom - til fire som nettopp såg deg gjere det.
  S.said = {}
  lockAt(16 * 60)
  S.inInstance = true
  ChainCharDB.toldLocked = nil
  BT.AnnounceLock()
  eq(said(), nil, "seier ingenting om lockouten medan du er inne")
  S.inInstance = false
  BT.AnnounceLock()
  ok((said() or ""):find("5/5"), "men seier det når du kjem ut")

  -- Åleine er det ingen å seie det til, men talet er verdt å ha likevel: då
  -- går same linja til ditt eige chat-vindauge i staden for ingen stad.
  do
    local wasParty = S.party
    S.party = {}
    S.said, S.printed = {}, {}
    lockAt(16 * 60)
    ChainCharDB.toldLocked, ChainCharDB.toldMark = nil, nil
    BT.AnnounceLock(true)
    eq(#S.said, 0, "åleine går det ikkje til party")
    ok(S.Said("%[CHAIN%] %- 5/5"), "men det står i ditt eige vindauge")
    S.party = wasParty
    S.said, S.printed = {}, {}
  end

  -- Den eine linja som er verdt å seie innanfrå: ein plass er ledig. Det er
  -- nettopp gjengen som står inne som ventar på den.
  S.inInstance = true
  ChainDB.entries = {}
  BT.AnnounceLock()
  ok((said() or ""):find("instance unlocked"), "men at ein plass er ledig blir sagt inne òg")
  S.inInstance = false

  S.said = {}
  lockAt(16 * 60)
  ChainCharDB.toldLocked, ChainCharDB.toldMark = nil, nil
  BT.AnnounceLock(true)
  local first = said()
  ok(first and first:find("5/5"), "den seier frå at du er låst")
  ok(first and first:find("16m"), "og kor lenge det er att")
  -- og det står kven som seier det, så det ikkje ser ut som nokon som skriv
  ok(first and first:find("^PARTY: %[CHAIN%] %- "),
     "med namnet framfor (" .. tostring(first) .. ")")

  -- ingenting mellom merka
  lockAt(15 * 60 + 30)
  BT.AnnounceLock()
  eq(said(), nil, "og gjentek seg ikkje mellom merka")

  -- femminutt-merka blir sagde, nedover, med den ekte tida
  lockAt(15 * 60)
  BT.AnnounceLock()
  ok((said() or ""):find("instance free in 15m"), "femten minutt blir sagt")
  lockAt(12 * 60)
  BT.AnnounceLock()
  eq(said(), nil, "og ikkje ein gong til før neste merke")
  lockAt(10 * 60)
  BT.AnnounceLock()
  ok((said() or ""):find("instance free in 10m"), "ti minutt blir sagt")
  lockAt(5 * 60)
  BT.AnnounceLock()
  ok((said() or ""):find("instance free in 5m"), "fem minutt blir sagt")

  -- eitt minutt er det ein reiser seg på
  lockAt(50)
  BT.AnnounceLock()
  -- heile minutt, aldri sekund: "free in 50s" er ei anna eining du må rekne
  -- om før du kan samanlikne med linja før
  ok((said() or ""):find("instance free in 1m"), "og eitt minutt for seg sjølv")
  lockAt(20)
  BT.AnnounceLock()
  eq(said(), nil, "berre ein gong")

  -- og når det losnar
  ChainDB.entries = {}
  BT.AnnounceLock()
  ok((said() or ""):find("instance unlocked"), "og ein gong når det losnar")
  BT.AnnounceLock()
  eq(said(), nil, "og ikkje meir enn det")

  ChainDB.entries = before
  ChainDB.announceLock = oldAnnounce
  ChainCharDB.toldLocked, ChainCharDB.toldMark = nil, nil
  S.party = {}
  S.said = {}
end

-- Og ein rekonstruksjon som pressar talet over ei grense spelet framleis
-- handhevar, er vist feil. Både spøkelse og inngangar bygde opp att frå
-- runloggen er gjetting; ein inngang vi faktisk såg skje blir aldri kasta for
-- å få eit tal til å sjå rett ut.
do
  local before = ChainDB.entries
  ChainCharDB.lockedAt, ChainCharDB.lockMissing = nil, nil
  ChainDB.entries = {}
  for i = 1, 4 do
    table.insert(ChainDB.entries, { t = S.now - i * 300, seq = "real" .. i,
                                    char = "Tester" })
  end
  table.insert(ChainDB.entries, { t = S.now - 30, seq = "guess",
                                  char = "Tester", fromRun = true })
  eq(BT.Lockout(), 5, "fem i loggen, og ein av dei er gjetta")
  S.zone, S.map, S.inInstance = "Stormwind Stockade", 34, true
  S.now = S.now + 10
  BT.NoteEntry()
  ok(BT.Lockout() <= 5, "spelet slapp deg inn, så gjettinga ryk ut ("
     .. BT.Lockout() .. ")")
  local realsLeft, guessLeft = 0, 0
  for _, e in ipairs(ChainDB.entries) do
    if tostring(e.seq):find("^real") then realsLeft = realsLeft + 1 end
    if e.seq == "guess" then guessLeft = guessLeft + 1 end
  end
  eq(realsLeft, 4, "og det vi faktisk såg står att")
  eq(guessLeft, 0, "medan gjettinga er borte")
  S.inInstance = false
  ChainDB.entries = before
end

-- Ein /reload er ikkje ein instansinngang.
--
-- Dette er den som kosta mest: ved reload kasta vi runen og lét Sync starte
-- ein ny - og å starte ein run skriv ein inngang mot fem-i-timen. Så kvart
-- einaste /reload medan du stod inne i ein dungeon talde som å gå inn i ein ny,
-- og ein dag med reloading for å hente endringar la talet fleire over sanninga.
-- NIT skriv "UI Reload detected, loading last instance data instead of
-- creating new" av nettopp denne grunnen.
do
  local before = ChainDB.entries
  ChainDB.entries = {}
  ChainCharDB.entrySeq = 0
  ChainCharDB.lockedAt, ChainCharDB.lockMissing = nil, nil
  ChainCharDB.run = nil
  BT.reloadedAt = 0
  S.zone, S.map, S.inInstance = "Scarlet Monastery", 189, true
  S.now = S.now + 600
  S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
  eq(BT.Lockout(), 1, "å gå inn tel ein")
  ChainCharDB.run.xp = 9000

  -- og så laster han om, ståande på same staden
  S.printed = {}
  S.now = S.now + 120
  S.Fire(frame, "PLAYER_ENTERING_WORLD", false, true)
  eq(BT.Lockout(), 1, "reload tel ikkje som ein ny instans")
  ok(ChainCharDB.run ~= nil, "og runen held fram")
  eq(ChainCharDB.run.xp, 9000, "med det den alt hadde samla")

  -- og om klienten melder verda før han vedgår instansen, tek vakta det
  ChainCharDB.run = nil
  S.now = S.now + 5
  S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
  eq(BT.Lockout(), 1, "og heller ikkje når runen blei borte i lastinga")
  ok(S.Said("back from a reload"), "og den seier kvifor")

  -- Og det motsette, som er den som kosta ein inngang: du laster om i byen og
  -- går inn i instansen rett etterpå. Vakta spurde om siste sona var den same
  -- - og det er ho framleis eit halvt minutt etter at du gjekk ut - så den
  -- ekte inngangen blei kasta og talet stod eitt for lågt resten av timen.
  do
    local keep, keepRun = ChainDB.entries, ChainCharDB.run
    ChainDB.entries = {}
    ChainCharDB.run = nil
    ChainCharDB.seenInst = {}
    S.guid = nil
    BT.reloadedAt, BT.reloadRunZone = 0, nil
    -- han har vore inne, og går ut
    S.zone, S.map, S.inInstance = "Scarlet Monastery", 189, true
    S.now = S.now + 600
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    eq(BT.Lockout(), 1, "inne ein gong")
    -- han drep noko, så inngangen ikkje blir kasta som "såg aldri nokon"
    ChainCharDB.run.xp, ChainCharDB.run.k = 9000, 60
    S.zone, S.inInstance = "Tirisfal Glades", false
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")

    -- laster om ute
    S.now = S.now + 60
    S.Fire(frame, "PLAYER_ENTERING_WORLD", false, true)
    eq(BT.reloadRunZone, nil, "ingen run var i gang, så ingenting å halde på")

    -- og går inn med det same
    S.now = S.now + 5
    S.zone, S.inInstance = "Scarlet Monastery", true
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    eq(BT.Lockout(), 2, "inngangen rett etter ein reload i byen tel")

    S.zone, S.inInstance = "Tirisfal Glades", false
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    ChainCharDB.seenInst = {}
    BT.reloadedAt, BT.reloadRunZone = 0, nil
    -- legg tilbake det blokka over dreiv med
    ChainDB.entries, ChainCharDB.run = keep, keepRun
  end

  -- men eit ekte opphald etterpå er ein ekte inngang
  BT.reloadedAt = 0
  S.now = S.now + 600
  S.zone, S.inInstance = "Tirisfal Glades", false
  S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
  S.now = S.now + 60
  S.zone, S.inInstance = "Scarlet Monastery", true
  S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
  eq(BT.Lockout(), 2, "ein ny instans etterpå tel som før")

  S.zone, S.inInstance = "Tirisfal Glades", false
  S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
  ChainDB.entries = before
  ChainCharDB.seenInst = {}
end

-- Loggen hans, rad for rad, slik Instances-fana viste han då den sa 7/5.
-- Dette er ikkje eit tenkt tilfelle: det er dataa, og dei seier kva som var
-- gale. To "entered SM" eitt minutt frå kvarandre klokka 44 minutt sidan, og
-- ingenting mellom dei. Eitt oppmøte, meldt to gonger.
do
  local before, beforeR = ChainDB.entries, ChainDB.resets
  local me = UnitName("player")
  ChainCharDB.lockedAt, ChainCharDB.lockMissing = nil, nil
  local function ago(m) return S.now - math.floor(m * 60) end
  ChainDB.entries = {
    { t = ago(59),   seq = "n1", zone = "Scarlet Monastery", char = me },
    { t = ago(44.4), seq = "n2", zone = "Scarlet Monastery", char = me },
    { t = ago(44),   seq = "n3", zone = "Scarlet Monastery", char = me },
    { t = ago(35),   seq = "n4", zone = "Scarlet Monastery", char = me,
      from = "NIT" },
    { t = ago(30),   seq = "n5", zone = "Scarlet Monastery", char = me },
    { t = ago(8),    seq = "n6", zone = "Scarlet Monastery", char = me },
    { t = ago(1),    seq = "n7", zone = "Scarlet Monastery", char = me },
  }
  ChainDB.resets = {
    { at = ago(59.2), zone = "Scarlet Monastery", by = "Berreta", char = me },
    { at = ago(45),   zone = "Scarlet Monastery", by = "Berreta", char = me },
    { at = ago(30.5), zone = "Scarlet Monastery", by = "Berreta", char = me },
    { at = ago(11),   zone = "Scarlet Monastery", by = "Berreta", char = me },
  }
  eq(BT.Lockout(), 7, "loggen hans las sju, og sju finst ikkje")

  S.printed = {}
  local gone = BT.DedupeEntries()
  eq(gone, 1, "eitt oppmøte var meldt to gonger")
  eq(BT.Lockout(), 6, "og då er det seks")
  ok(S.Said("duplicate arrival"), "og den seier kva den fjerna")

  -- Og det er resetet som skil dei to tilfella, ikkje klokka. To inngangar
  -- like tett på kvarandre, men med eit reset imellom, er to instansar: det
  -- er heile mekanikken. Ein rask kjede ser nettopp slik ut.
  local rescue = {
    { t = ago(20),    seq = "r1", zone = "Scarlet Monastery", char = me },
    { t = ago(19),    seq = "r2", zone = "Scarlet Monastery", char = me },
  }
  ChainDB.entries = rescue
  ChainDB.resets = { { at = ago(19.5), zone = "Scarlet Monastery",
                       by = "Berreta", char = me } }
  eq(BT.DedupeEntries(), 0, "eit reset imellom gjer dei til to instansar")
  eq(#ChainDB.entries, 2, "og begge blir ståande")

  -- ta resetet vekk, og då er dei same oppmøtet
  ChainDB.entries = {
    { t = ago(20), seq = "r1", zone = "Scarlet Monastery", char = me },
    { t = ago(19), seq = "r2", zone = "Scarlet Monastery", char = me },
  }
  ChainDB.resets = {}
  eq(BT.DedupeEntries(), 1, "utan reset er dei eitt")

  eq(BT.DedupeEntries(), 0, "og den finn ikkje på fleire")

  ChainDB.entries, ChainDB.resets = before, beforeR
end

-- To zone-ins innan nokre sekund kan ikkje begge vere instansinngangar. Å gå
-- ut av ein instans og inn i ein fersk er to lasteskjermar og eit reset
-- imellom; spelet gjer ikkje det på ti sekund, kva enn sone-eventa seier. Så
-- ein inngang så tett på den førre er same ankomst meldt to gonger.
do
  local before = ChainDB.entries
  ChainDB.entries = {}
  ChainCharDB.entrySeq = 0
  ChainCharDB.lockedAt, ChainCharDB.lockMissing = nil, nil
  S.zone, S.map, S.inInstance = "Stormwind Stockade", 34, true
  S.now = S.now + 100
  BT.NoteEntry()
  eq(BT.Lockout(), 1, "fyrste ankomsten tel")
  S.printed = {}
  S.now = S.now + 3
  BT.NoteEntry()
  eq(BT.Lockout(), 1, "same ankomst tre sekund seinare tel ikkje igjen")
  ok(S.Said("same arrival twice"), "og den seier frå at den let vere")
  -- men eit skikkeleg opphald er ein ny instans
  S.now = S.now + 60
  BT.NoteEntry()
  eq(BT.Lockout(), 2, "eit minutt seinare er det ein ny ein")
  S.inInstance = false
  ChainDB.entries = before
end

-- Og det må skje utan at du soner inn. Å stå utanfor med eit tal som ikkje kan
-- stemme er det eine tilfellet ei zone-in aldri fiksar, for du prøver ikkje:
-- baren seier at døra er stengd.
do
  local before = ChainDB.entries
  ChainCharDB.lockedAt, ChainCharDB.lockMissing = nil, nil
  ChainDB.entries = {}
  for i = 1, 5 do
    table.insert(ChainDB.entries, { t = S.now - i * 300, seq = "ekte" .. i,
                                    char = "Tester" })
  end
  table.insert(ChainDB.entries, { t = S.now - 20, seq = "gjetta",
                                  char = "Tester", fromRun = true })
  eq(BT.Lockout(), 6, "seks i loggen, og seks finst ikkje")
  S.printed = {}
  S.now = S.now + 10
  BT.PollLock()
  eq(BT.Lockout(), 5, "tikken ryddar det utan at du rører deg")
  ok(S.Said("could not have been right"), "og seier at den gjorde det")
  local left = 0
  for _, e in ipairs(ChainDB.entries) do
    if tostring(e.seq):find("^ekte") then left = left + 1 end
  end
  eq(left, 5, "og det vi faktisk såg står att")
  ChainDB.entries = before
end

-- og det går ut av seg sjølv
S.now = S.now + 3700
eq(BT.LockedByGame(), nil, "svaret frå spelet varer ikkje evig")
S.now = S.now - 3700
ChainCharDB.lockedAt, ChainCharDB.lockMissing = nil, nil

-- Runloggen er betre bevis enn inngangsloggen: ein lagra run er prov på at du
-- var inne, ein inngang er berre eit notat vi tok på vegen inn - og feilen med
-- instans-ID-en sletta det notatet som eit falskt gjensyn. Ni runs den siste
-- timen ved sida av "2/5" er ikkje eit reknestykke som går opp.
do
  local oldEntries, oldRuns = ChainDB.entries, ChainDB.runs
  ChainDB.entries, ChainDB.runs = {}, {}
  ChainCharDB.lockedAt, ChainCharDB.lockMissing = nil, nil
  local me = "Tester"
  for i = 1, 4 do
    table.insert(ChainDB.runs, { at = S.now - i * 400, zone = "Scarlet Monastery",
                                 id = "sm", xp = 9000, k = 60, t = 300,
                                 char = me })
  end
  -- ein av dei var eit gjensyn, og det talde ikkje den gongen heller
  ChainDB.runs[2].reentry = true
  -- og éin inngang overlevde
  table.insert(ChainDB.entries, { t = ChainDB.runs[1].at, seq = "x1",
                                  zone = "Scarlet Monastery", char = me })
  eq(BT.Lockout(), 1, "loggen har berre den eine att")
  local back = BT.ReconcileEntries()
  eq(back, 2, "to blir henta tilbake frå runloggen")
  eq(BT.Lockout(), 3, "og då stemmer talet med runane")
  eq(BT.ReconcileEntries(), 0, "og ein gong til gjev ingen dublettar")

  ChainDB.entries, ChainDB.runs = oldEntries, oldRuns
end

-- instansloggen, slik Instances-fana les den
ChainDB.entries = {}
ChainCharDB.entrySeq = 0
S.zone, S.map, S.inInstance = "Stormwind Stockade", 34, true
for i = 1, 3 do S.now = S.now + 180 BT.NoteEntry() end
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
for i = 1, 5 do S.now = S.now + 180 BT.NoteEntry() end

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
S.Fire(frame, "CHAT_MSG_PARTY", "Instances reset!", "Boostar-Testrealm")
eq(S.sounds, 1, "ingen dobbel lyd")
eq(select(3, BT.ResetReady()), "Boostar", "kven som resetta")

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
for i = 1, 5 do S.now = S.now + 180 BT.NoteEntry() end
ChainCharDB.resetAt = S.now
ChainCharDB.resetZone = "The Stockade"
local full = table.concat(BT.AllLines(), "\n")
ok(full:find("you are at 5/5"), "seier at du er låst ute i staden for 'go in'")
ok(not full:find("reset by Boostar %- go in"), "ingen 'go in' på 5/5")
-- med plass att skal den seie go in
ChainDB.entries = {}
full = table.concat(BT.AllLines(), "\n")
ok(full:find("go in"), "go in når det er plass")
for i = 1, 5 do S.now = S.now + 180 BT.NoteEntry() end

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
eq(S.said[1], "PARTY: [CHAIN] - Stockades reset - go in",
   "kunngjer når det er på, med namnet framfor")

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
  ok((S.said[1] or ""):find("%[CHAIN%] %- 5/5"),
     "på 5/5 seier han lockouten i staden for 'go in' (" ..
     tostring(S.said[1]) .. ")")
  ok((S.said[1] or ""):find("instance free in"), "og kor lenge det er att")

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
  ok((S.said[1] or ""):find("instance unlocked"),
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

  -- Ein ekte GUID: Creature-0-<server>-<map>-<kopi>-<npc>-<spawn>. Kartet er
  -- 189 for Scarlet Monastery i kvar einaste kopi som har funnest - det er
  -- feltet etter som skil den eine kopien frå den andre. Testen stod før med
  -- kartfeltet som det som varierte, og det var akkurat feilen: med berre det
  -- feltet såg den andre Stockade-runen på dagen ut som eit gjensyn med den
  -- fyrste, og talde ikkje mot dei fem i timen.
  local function visit(copy, map)
    S.zone, S.map, S.inInstance = "Scarlet Monastery", 189, true
    S.guid = "Creature-0-4672-" .. (map or 189) .. "-" .. copy .. "-3975-0000A1"
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.Fire(frame, "PLAYER_TARGET_CHANGED")
    local re = ChainCharDB.run and ChainCharDB.run.reentry
    S.now = S.now + 300
    S.zone, S.inInstance = "Stormwind City", false
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.now = S.now + 60
    return re
  end

  ok(visit(7771) == nil, "Cathedral tel")
  ok(visit(7772) == nil, "Armory tel som ein instans til")
  ok(visit(7773) == nil, "og Library med")
  eq(BT.Lockout(), 3, "tre instansar den timen")
  ok(visit(7771) == true, "men tilbake i same Cathedral tel ikkje på nytt")
  eq(BT.Lockout(), 3, "framleis tre")

  -- og same kopinummeret i ein annan instans er ikkje same instansen
  ok(visit(7771, 33) == nil, "same nummer i Shadowfang er ein annan stad")
  eq(BT.Lockout(), 4, "fire")

  -- NIT seier begge halvdelane høgt:
  --   "New instance Scarlet Monastery (5 this hour)"
  --   "Same instance ID as last detected (4 this hour), merging"
  -- Talet flyttar seg to gonger på veg inn - opp når du soner, ned att når
  -- mobbane viser at det er den same du nettopp var i - og eit tal som rettar
  -- seg sjølv i stille er eit tal du endar opp med å krangle med. Det er
  -- nettopp difor NIT går an å kontrollere.
  do
    ChainDB.entries = {}
    ChainCharDB.seenInst = {}
    ChainCharDB.run = nil
    S.targetDead = false
    S.printed = {}
    S.zone, S.map, S.inInstance = "Scarlet Monastery", 189, true
    S.guid = "Creature-0-4672-189-7100-3975-0000A1"
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.Fire(frame, "PLAYER_TARGET_CHANGED")
    ok(S.Said("new instance"), "den seier frå når ein instans blir talt")
    ok(S.Said("1/5 this hour"), "og kva talet står på")

    -- ut og inn att i den same instansen: talet skal gå ned igjen, og seie det
    S.zone, S.inInstance = "Tirisfal Glades", false
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.now = S.now + 60
    S.printed = {}
    S.zone, S.inInstance = "Scarlet Monastery", true
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.Fire(frame, "PLAYER_TARGET_CHANGED")
    ok(S.Said("same instance as the last one"), "og når den slår dei saman att")
    eq(BT.Lockout(), 1, "og då står det på ein, ikkje to")

    -- og den kan skruast av
    ChainDB.sayCount = false
    S.printed = {}
    ChainCharDB.seenInst = {}
    S.zone, S.inInstance = "Tirisfal Glades", false
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.now = S.now + 60
    S.zone, S.inInstance = "Scarlet Monastery", true
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    eq(S.Said("new instance"), nil, "og den kan skruast av")
    ChainDB.sayCount = nil

    S.zone, S.inInstance = "Tirisfal Glades", false
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.guid = nil
    ChainDB.entries = {}
    ChainCharDB.seenInst = {}
  end

  -- Freistinga her er å splitte runen når mob-ID-ane sluttar å stemme: alle
  -- fire SM-vengjene heiter "Scarlet Monastery", så sonenamnet rører seg
  -- ikkje. Det blei prøvd, og baren gjekk til 6/5 - eit tal spelet ikkje gjev
  -- deg, så det den talde var ikkje ein instans. NIT gjer det ikkje heller:
  -- den brukar mob-ID-en berre til å avgjere om ein run som nettopp har
  -- STARTA eigentleg er den førre som held fram, aldri til å avslutte ein som
  -- er i gang.
  do
    ChainDB.entries = {}
    ChainCharDB.seenInst = {}
    ChainCharDB.run = nil
    S.targetDead = false
    S.zone, S.map, S.inInstance = "Scarlet Monastery", 189, true
    S.guid = "Creature-0-4672-189-8001-3975-0000A1"
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.Fire(frame, "PLAYER_TARGET_CHANGED")
    eq(BT.Lockout(), 1, "instansen tel ein")
    eq(ChainCharDB.run.instId, "189:8001", "og runen veit kvar han er")

    -- mobbar med ein annan ID midt i runen skal ikkje kunne lage ein til
    for i = 1, 6 do
      BT.NoteInstance("Creature-0-4672-189-8002-3975-0000B" .. i)
    end
    eq(BT.Lockout(), 1, "og framleis berre ein, uansett kva mobbane seier")
    eq(ChainCharDB.run.instId, "189:8001", "runen held på ID-en sin")

    S.zone, S.inInstance = "Tirisfal Glades", false
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.guid = nil
    ChainDB.entries = {}
    ChainCharDB.seenInst = {}
  end

  -- Og eit lik du dreg med deg i target-ramma er den same fella i sakte film:
  -- går du ut og inn att med den døde moben frå førre instans framleis
  -- markert, blir den nye runen stempla som eit gjensyn med den gamle og
  -- inngangen kasta. Ein død target får ikkje seie noko.
  do
    ChainDB.entries = {}
    ChainCharDB.seenInst = {}
    ChainCharDB.run = nil
    S.targetDead = false
    S.zone, S.map, S.inInstance = "Scarlet Monastery", 189, true
    S.guid = "Creature-0-4672-189-9001-3975-0000A1"
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.Fire(frame, "PLAYER_TARGET_CHANGED")
    eq(BT.Lockout(), 1, "fyrste instansen tel")
    ChainCharDB.run.xp = 9000

    -- ut, og moben er død og framleis markert
    S.targetDead = true
    S.zone, S.inInstance = "Tirisfal Glades", false
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.now = S.now + 60

    -- inn i ein heilt ny instans, med liket framleis i ramma
    S.zone, S.inInstance = "Scarlet Monastery", true
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    eq(BT.Lockout(), 2, "den nye instansen tel, trass i liket i ramma")
    eq(ChainCharDB.run.reentry, nil, "og blir ikkje stempla som eit gjensyn")

    S.targetDead = false
    S.zone, S.inInstance = "Tirisfal Glades", false
    S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
    S.guid = nil
    ChainDB.entries = {}
    ChainCharDB.seenInst = {}
  end

  -- ein GUID utan noko å kjenne den att på skal ikkje gje eit falskt gjensyn
  eq(BT.InstIdFrom("Creature-0-4672-189-0-3975-0000A1"), nil, "tom kopi-id tel ikkje")
  eq(BT.InstIdFrom("Player-4672-00A1B2C3"), nil, "og ein spelar er ikkje ein instans")
  eq(BT.InstIdFrom(nil), nil, "og ingenting er ingenting")
  eq(BT.InstIdFrom("Creature-0-4672-189-7771-3975-0000A1"), "189:7771",
     "kart og kopi saman er kva vi kjenner ein instans på")
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
S.Fire(frame, "READY_CHECK", "Sjekkar-Testrealm")
eq(BT.readyCheckBy, "Sjekkar", "kven som starta ready check")
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
S.party = { { name = "Boostar-Testrealm", lvl = 60 }, { name = "A", lvl = 33 },
            { name = "B", lvl = 26 }, { name = "C", lvl = 24 } }
S.level, S.xp, S.xpMax = 23, 12000, 31700
S.rested = 4000
S.zone, S.map, S.inInstance = "The Stockade", 34, true
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
ChainCharDB.run.xp, ChainCharDB.run.k = 8472, 93
ChainCharDB.run.reentry = true
ChainCharDB.resetAt = S.now
ChainCharDB.resetZone = "The Stockade"
ChainCharDB.resetBy = "Boostar"
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
    local cap = (BT.Budget and BT.Budget()) or 74
    ok(#clean <= cap, "linje over " .. cap .. " teikn: " .. clean)
  end
end
CornersFit()

-- Budsjettet er i teikn fordi teksten blir bygd lenge før det finst ei ramme
-- å måle han i - men kor mange teikn som får plass kjem heilt an på ansiktet.
-- Fireogsytti var målt éin gong, i den skrifta addonen brukte den gongen; med
-- ei breiare skrift teikna dei same fireogsytti rett over kvarandre.
do
  local wide = BT.Budget()
  eq(wide, 74, "med den gamle breidda er budsjettet det gamle")

  S.charW = 9
  BT.ForgetBudget()
  local tight = BT.Budget()
  ok(tight < wide, "ei breiare skrift gir eit mindre budsjett (" .. tight .. ")")
  CornersFit("hjørna med brei skrift")

  S.charW = 4
  BT.ForgetBudget()
  ok(BT.Budget() > wide, "og ei smalare gir eit større")
  CornersFit("hjørna med smal skrift")

  S.charW = 6
  BT.ForgetBudget()
  eq(BT.Budget(), 74, "og tilbake der vi var")
end

--------------------------------------------------------------------------
print("== leveling-modus ==")
-- Same ordlyd som i boost: kva level du er på står alt i den andre enden av
-- baren, så talet er einaste nytt.
local function DingWording()
  local sl = BT.BuildText() or {}
  local r = ((tostring(sl.barRight or ""):gsub("|c%x%x%x%x%x%x%x%x", ""))):gsub("|r", "")
  ok(r:find("^ding in") or r:find("xp$"),
     "høgre ende seier når du dingar (" .. r .. ")")
  ok(not r:find(" to %d+$"), "og ikkje 'to 32' i ei anna form enn boost-linja")
  -- Farta står midt mellom dei to hjørna under baren, ikkje midt i baren:
  -- ho høyrer til på linja ho blir målt saman med.
  local c = ((tostring(sl.bottomCenter or ""):gsub("|c%x%x%x%x%x%x%x%x", ""))):gsub("|r", "")
  ok(c:find("xp/h") or c:find("no xp for") or c:find("measuring"),
     "og farta står midt mellom hjørna (" .. c .. ")")
end
S.party = {}
S.zone, S.inInstance = "Elwynn Forest", false
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
ChainCharDB.lastEnd = nil
S.quests = { { title = "Q1", done = true, xp = 1200, level = 20 },
             { title = "Q2", done = true, xp = 900, level = 19 } }
BT.questScan = nil
BT.ScanQuests()
DingWording()

-- Er du åleine og borte i fem minutt, sluttar farta å telje. I gruppe er eit
-- opphald eit reset, ein summon eller nokon sin hund; åleine er det du som
-- ikkje er der, og ei fart som tel vidare ved postkassa seier at du dingar om
-- fem minutt.
do
  local wasParty = S.party
  S.party = {}
  ChainCharDB.buckets = {}
  for _ = 1, 10 do
    S.now = S.now + 60
    S.xp = S.xp + 700
    S.Fire(frame, "PLAYER_XP_UPDATE")
  end
  ok((BT.Rate() or 0) > 0, "med xp inn er det ei fart")

  S.now = S.now + 6 * 60
  eq(BT.Rate(), nil, "åleine er ho borte etter fem minutt stille")

  S.party = { { name = "Kompis", lvl = 30 } }
  ok((BT.Rate() or 0) > 0, "i gruppe tel han framleis - eit opphald er noko anna")

  S.now = S.now + 6 * 60
  eq(BT.Rate(), nil, "men ikkje etter tolv")
  S.party = wasParty
end

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
CornersFit()

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

  -- Og ingenting skal liggje oppå noko anna. Sidene ligg med vilje på same
  -- staden - berre éi er framme om gongen - så samanlikninga er per side, som
  -- er nøyaktig det som kan vere på skjermen samtidig.
  local pageOf = {}
  for _, pg in ipairs(o.pages or {}) do
    for _, w in ipairs(pg.widgets) do pageOf[w] = pg.key end
  end
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
                            h = child.__h or 16, what = child.__kind,
                            page = pageOf[child] })
    end
  end
  local clash
  for i = 1, #boxes do
    for j = i + 1, #boxes do
      local a, b = boxes[i], boxes[j]
      -- same row, not merely nearby: rows here are 20 pixels apart or more
      local together = (a.page == b.page) or not a.page or not b.page
      if together and math.abs(a.y - b.y) < 8
         and a.x < b.x + b.w and b.x < a.x + a.w then
        clash = string.format("%s ved %d og %s ved %d (side %s/%s)",
          a.what, a.x, b.what, b.x, tostring(a.page), tostring(b.page))
      end
    end
  end
  ok(clash == nil, "ingenting ligg oppå noko anna (" .. tostring(clash) .. ")")
  ok(tall == nil, "og ingenting under botnen (" .. tostring(tall)
     .. " endar på " .. math.floor(tallY) .. " av " .. frameH .. ")")
end

do  -- Fanene i innstillingane: same form som det store vindauget, éi side om
    -- gongen. Panelet var 508 breitt med seks blokker stabla nedover, og
    -- kolonnane var smale nok til at ein etikett i den eine nådde inn i den
    -- neste.
  local o = _G.ChainOptions
  ok(o.pages and #o.pages >= 5, "panelet er delt i sider")
  eq(#o.tabs, #o.pages, "og det er ei fane per side")
  ok(o.pages[1].key == "route", "instansane er fyrste sida")

  -- kvar einaste kontroll høyrer til nøyaktig éi side. Det er invarianten:
  -- ein widget utan side blir aldri gøymd, og dukkar opp oppå den sida du
  -- faktisk ser på.
  local pageOf, twice = {}, 0
  for _, pg in ipairs(o.pages) do
    for _, w in ipairs(pg.widgets) do
      if pageOf[w] then twice = twice + 1 end
      pageOf[w] = pg.key
    end
  end
  eq(twice, 0, "og ingen widget høyrer til to sider")

  local orphans = {}
  for _, name in ipairs({ "watch", "alertAll", "enemySound", "stealth",
                          "announceKOS", "nearbyList", "sound", "announce",
                          "banner", "nit", "ads", "signal", "snap", "groups",
                          "loot", "announceLock", "minimap", "share",
                          "showBar", "lock", "honorBar", "honorMode" }) do
    local t = o[name]
    if t then
      if not pageOf[t] then orphans[#orphans + 1] = name .. " (boks)" end
      if t.label and not pageOf[t.label] then
        orphans[#orphans + 1] = name .. " (etikett)"
      end
      if t.label and pageOf[t] ~= pageOf[t.label] then
        orphans[#orphans + 1] = name .. " (boks og etikett på kvar si side)"
      end
    end
  end
  eq(#orphans, 0, "alt høyrer til ei side (" .. table.concat(orphans, ", ") .. ")")

  -- og å byte fane viser éi side og gøymer resten
  BT.ShowOptionsPage("enemies")
  ok(o.watch:IsShown(), "kontrollane på den valde sida er framme")
  ok(o.watch.label:IsShown(), "med etikettane sine")
  ok(not o.pack:IsShown(), "og dei på andre sider er borte")
  ok(not o.rows[1]:IsShown(), "instans-tabellen òg")

  BT.ShowOptionsPage("route")
  ok(o.rows[1]:IsShown(), "og tilbake igjen")
  ok(not o.watch:IsShown(), "medan den førre er gøymd")

  -- Og ei heil oppteikning skal ikkje dra instans-tabellen fram igjen oppå
  -- den sida du faktisk er på. Alt over sidevalet viser og gøymer rader av
  -- seg sjølv, og instans-tabellen teiknar sine på nytt kvar gong.
  BT.ShowOptionsPage("share")
  BT.RenderOptions()
  ok(not o.rows[1]:IsShown(),
     "ei oppteikning hentar ikkje instans-tabellen tilbake")
  ok(o.share:IsShown(), "medan sida du er på står")
  BT.ShowOptionsPage("route")
  BT.RenderOptions()
  ok(o.rows[1]:IsShown(), "og på Instances er tabellen der")

  -- fana som er vald skal syne det
  BT.ShowOptionsPage("enemies")
  for _, b in ipairs(o.tabs) do
    if b.key == "enemies" then ok(b.active, "den valde fana er merkt")
    else ok(not b.active, "og dei andre ikkje (" .. b.key .. ")") end
  end

  -- Begge vindauga opne samtidig: innstillingane skal liggje over, og vere
  -- ugjennomsiktige. To kolonnar med tal som les svakt gjennom kvarandre er
  -- verre enn begge kvar for seg.
  do
    local w = _G.ChainWindow
    ok(o.__strata == "FULLSCREEN_DIALOG",
       "innstillingane ligg over vindauget (" .. tostring(o.__strata) .. ")")
    ok(w.__strata == "DIALOG", "og vindauget under")
    eq(o.bg.__alpha, 1, "og bakgrunnen er heilt tett")
    eq(w.bg.__alpha, 1, "på begge to")
  end

  -- høgda skal ikkje endre seg når du byter: ei ramme som skiftar storleik
  -- under peikaren er ei ramme der knappane flyttar seg
  local h1 = o:GetHeight()
  BT.ShowOptionsPage("share")
  eq(o:GetHeight(), h1, "høgda står still når du byter fane")
  BT.ShowOptionsPage("route")
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
-- Alt addonen skriv går gjennom fem font-objekt av våre eigne. Eit font-objekt
-- er delt av alle strengane som brukar det, så eit byte slår gjennom overalt
-- med ein gong - utan reload, og utan å røre resten av spelet.
do
  local small = _G.ChainFontHighlightSmall
  ok(small ~= nil, "addonen har sine eigne font-objekt")
  local path, size = small:GetFont()
  ok(path:find("DejaVuSans"), "og skriv i skrifta som fylgjer med addonen")
  eq(size, 9, "eit hakk mindre, sidan ho er breiare enn spelet si eiga")

  BT.SetFace("game")
  path, size = _G.ChainFontHighlightSmall:GetFont()
  ok(path:find("FRIZQT"), "spelet sitt eige ansikt er eitt val unna")
  eq(size, 10, "og då er storleiken spelet sin òg")

  -- storleiken kjem frå spelet sitt objekt med same namn, så eit byte av
  -- ansikt endrar ikkje kor stor halve addonen er
  local _, big = _G.ChainFontNormalLarge:GetFont()
  eq(big, 16, "kvart objekt held sin eigen storleik")

  -- og knappen i opsjonane seier kva du har og byter til neste
  BT.ShowOptionsPage("share")
  BT.RenderOptions()
  if _G.ChainOptions and _G.ChainOptions.face then
    local btn = _G.ChainOptions.face
    eq(btn.fs:GetText(), "Game default", "knappen seier kva ansikt du har")
    btn.__scripts.OnClick(btn)
    ok((BT.Face().name or "") ~= "Game default", "og eit trykk byter til neste")
  end

  BT.SetFace("sans")
end

SlashCmdList["CHAIN"]("stats")
SlashCmdList["CHAIN"]("help")

-- Begge kunngjeringane er av til du slår dei på, og begge skal kunne slåast
-- på utan å finne fram i opsjonane.
do
  local was, wasLock = ChainDB.announce, ChainDB.announceLock
  ChainDB.announce, ChainDB.announceLock = false, false
  SlashCmdList["CHAIN"]("announce")
  eq(ChainDB.announce, true, "/chain announce slår på reset-kunngjeringa")
  SlashCmdList["CHAIN"]("lockout")
  eq(ChainDB.announceLock, true, "/chain lockout slår på nedteljinga")
  SlashCmdList["CHAIN"]("lockout")
  eq(ChainDB.announceLock, false, "og av igjen")
  ChainDB.announce, ChainDB.announceLock = was, wasLock
end

--------------------------------------------------------------------------
print("== gull og trade-logg ==")
local tf = BT.tradeFrame
ChainDB.trades = {}
S.level = 22
S.party = { { name = "Boostar-Testrealm", lvl = 60 } }
S.tradeTarget = "Boostar-Testrealm"
S.playerMoney, S.targetMoney = 0, 0

local function doTrade(gave, got, who)
  S.tradeTarget = who or "Boostar-Testrealm"
  S.playerMoney, S.targetMoney = gave, got
  S.Fire(tf, "TRADE_SHOW")
  S.Fire(tf, "TRADE_MONEY_CHANGED")
  S.Fire(tf, "UI_INFO_MESSAGE", 1, ERR_TRADE_COMPLETE)
  S.Fire(tf, "TRADE_CLOSED")
  S.now = S.now + 60
end

doTrade(50 * 10000, 0)                 -- 50g til boosteren
eq(#ChainDB.trades, 1, "trade lagra")
eq(ChainDB.trades[1].with, "Boostar", "namn utan realm")
eq(ChainDB.trades[1].gave, 500000, "kopar lagra")
eq(ChainDB.trades[1].by, "Boostar", "knytt til boosteren")
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

-- Ein avbroten trade skal ikkje loggast. Eit avbrot melder alltid frå om seg
-- sjølv - TRADE_REQUEST_CANCEL kjem etter TRADE_CLOSED når du avbryt og før
-- det når den andre gjer det - så det er fråværet av den meldinga som skil ein
-- fullført handel frå ein forlaten.
S.playerMoney, S.targetMoney = 999 * 10000, 0
S.Fire(tf, "TRADE_SHOW")
S.Fire(tf, "TRADE_MONEY_CHANGED")
S.Fire(tf, "TRADE_CLOSED")
S.Fire(tf, "TRADE_REQUEST_CANCEL")
S.RunTimers(10)
eq(#ChainDB.trades, 3, "avbroten trade blir ikkje lagra")

-- og den andre rekkjefølgja, når det er den andre parten som avbryt
S.Fire(tf, "TRADE_SHOW")
S.Fire(tf, "TRADE_MONEY_CHANGED")
S.Fire(tf, "TRADE_REQUEST_CANCEL")
S.Fire(tf, "TRADE_CLOSED")
S.RunTimers(10)
eq(#ChainDB.trades, 3, "og når avbrotet kjem først")

-- Classic Era sender ikkje alltid "Trade complete." i det heile. Då er det
-- to hakar og eit lukka vindauge som er beskjeden - utan dette blei logga
-- ståande tom etter ein handel som openbert hadde skjedd.
do
  local before = #ChainDB.trades
  S.tradeTarget = "Boostar-Testrealm"
  S.playerMoney, S.targetMoney = 40 * 10000, 0
  S.Fire(tf, "TRADE_SHOW")
  S.Fire(tf, "TRADE_MONEY_CHANGED")
  S.Fire(tf, "TRADE_ACCEPT_UPDATE", 1, 1)
  S.Fire(tf, "TRADE_CLOSED")
  eq(#ChainDB.trades, before, "ingenting blir skrive med det same")
  S.RunTimers(10)
  eq(#ChainDB.trades, before + 1, "men eit augeblink seinare er den logga")
  eq(ChainDB.trades[before + 1].gave, 400000, "med beløpet")
  ok((ChainDB.trades[before + 1].perRun or 0) > 0, "og prisen den blei kjøpt på")

  -- Og utan hakar i det heile: eit vindauge som lukkar seg og aldri nemner
  -- eit avbrot er ein handel som gjekk gjennom. Å krevje at begge hakane kom
  -- i eitt event var framleis for strengt - når den andre aksepterer blir
  -- handelen utført og vindauget rive ned, og det siste eventet kjem ikkje
  -- påliteleg fram. Handlar gjekk framleis ulogga.
  S.playerMoney, S.targetMoney = 77 * 10000, 0
  S.Fire(tf, "TRADE_SHOW")
  S.Fire(tf, "TRADE_MONEY_CHANGED")
  S.Fire(tf, "TRADE_CLOSED")
  S.RunTimers(10)
  eq(#ChainDB.trades, before + 2, "lukka utan avbrot: det er ein handel")
  eq(ChainDB.trades[before + 2].gave, 770000, "med beløpet")

  -- og avbryt du etter at begge har akseptert, rekk avbrytinga å stoppe det
  S.Fire(tf, "TRADE_SHOW")
  S.Fire(tf, "TRADE_MONEY_CHANGED")
  S.Fire(tf, "TRADE_ACCEPT_UPDATE", 1, 1)
  S.Fire(tf, "TRADE_CLOSED")
  S.Fire(tf, "TRADE_REQUEST_CANCEL")
  S.RunTimers(10)
  eq(#ChainDB.trades, before + 2, "avbrytinga rekk å stoppe det")

  table.remove(ChainDB.trades)
  table.remove(ChainDB.trades)
  BT.TouchTrades()
  S.now = S.now + 60
end

-- ein handel med nokon som ikkje er booster
S.party = {}
ChainCharDB.lastBy = nil
doTrade(0, 25 * 10000, "Bankar-Testrealm")
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
eq(byB[1].with, "Boostar", "mest til boosteren")
near(BT.Gold(byB[1].net), 107, "netto til boosteren")

local tcsv = BT.BuildTradeCSV()
ok(tcsv:find("^at,date,traded_with"), "trade-CSV har overskrift")
eq(select(2, tcsv:gsub("\n", "\n")) + 1, #ChainDB.trades + 1, "ei linje per trade")
SlashCmdList["CHAIN"]("gold")

--------------------------------------------------------------------------
print("== kva pengane kjøpte ==")
-- Du betaler 400g for ti runs og så tel du på fingrane. Det er akkurat den
-- rekninga addonet skal gjere: den veit kva ein run kostar hos han, den veit
-- kva du betalte, og den veit kor mange runs du har fått.
do
  local oldTrades, oldRuns = ChainDB.trades, ChainDB.runs
  local oldBoosters = ChainDB.boosters
  ChainDB.trades, ChainDB.runs = {}, {}
  ChainDB.boosters = { Paidar = { price = 200, pack = 5 } }   -- 40g per run
  BT.Touch() BT.TouchTrades()

  local t0 = S.now
  table.insert(ChainDB.trades, { at = t0, with = "Paidar", gave = 400 * 10000,
                                 got = 0, id = "stock", by = "Paidar",
                                 perRun = 40, lvl = 22 })
  BT.TouchTrades()

  local c = BT.BoosterCredit("Paidar")
  ok(c ~= nil, "det finst ei rekning med han")
  near(c.runsPaid, 10, "400g til 40g per run er ti runs")
  eq(c.runsDone, 0, "ingen runs gått enno")
  near(c.left, 10, "ti runs til gode")

  -- fire runs seinare
  for i = 1, 4 do
    table.insert(ChainDB.runs, { at = t0 + i * 600, by = "Paidar", id = "stock",
                                 zone = "The Stockade", xp = 9000, k = 30, t = 500 })
  end
  BT.Touch()
  c = BT.BoosterCredit("Paidar")
  eq(c.runsDone, 4, "fire runs gått")
  near(c.left, 6, "seks igjen - og det er talet du slepp å telje")

  -- går du forbi det du har betalt for, snur talet
  for i = 5, 12 do
    table.insert(ChainDB.runs, { at = t0 + i * 600, by = "Paidar", id = "stock",
                                 zone = "The Stockade", xp = 9000, k = 30, t = 500 })
  end
  BT.Touch()
  c = BT.BoosterCredit("Paidar")
  near(c.left, -2, "to runs meir enn du har betalt for")

  -- og betaler du att, står den rett igjen
  table.insert(ChainDB.trades, { at = t0 + 8000, with = "Paidar",
                                 gave = 200 * 10000, got = 0, id = "stock",
                                 by = "Paidar", perRun = 40, lvl = 23 })
  BT.TouchTrades()
  c = BT.BoosterCredit("Paidar")
  near(c.runsPaid, 15, "600g totalt er femten runs")
  near(c.left, 3, "tre til gode att")
  near(BT.Gold(c.paid), 600, "og totalen står i gull")

  -- runs du gjekk før du nokon gong betalte han skal ikkje telje: elles
  -- skuldar du tjue runs til ein booster du aldri har handla med før i dag
  table.insert(ChainDB.runs, 1, { at = t0 - 86400, by = "Paidar", id = "stock",
                                  zone = "The Stockade", xp = 9000, k = 30, t = 500 })
  BT.Touch()
  eq(BT.BoosterCredit("Paidar").runsDone, 12, "runs frå i går tel ikkje med")

  -- men ein run same kvelden, rett før du gjorde opp, gjer det
  table.insert(ChainDB.runs, 1, { at = t0 - 1800, by = "Paidar", id = "stock",
                                  zone = "The Stockade", xp = 9000, k = 30, t = 500 })
  BT.Touch()
  eq(BT.BoosterCredit("Paidar").runsDone, 13, "same økta tel med")

  -- den som aldri har fått ei krone har inga rekning i det heile
  eq(BT.BoosterCredit("Ukjend"), nil, "ingen handel, inga rekning")
  eq(BT.BoosterCredit(nil), nil, "og ingen booster heller")

  -- hovudboka gjev same svar, men frose ved kvar betaling
  local led = BT.CreditLedger()
  local first, second = ChainDB.trades[1], ChainDB.trades[2]
  ok(led[first] ~= nil, "første betalinga står i boka")
  near(led[first].bought, 10, "og kva den kjøpte")
  near(led[first].left, 9, "ein run var gått då pengane skifta hender")
  near(led[second].bought, 5, "andre betalinga kjøpte fem")
  near(led[second].left, 2, "og då stod det to att")

  -- og det skal stå på baren
  S.party = { { name = "Paidar-Testrealm", lvl = 60 } }
  ChainCharDB.lastBy = "Paidar"
  S.level, S.xp, S.xpMax = 23, 12000, 31700
  S.zone, S.map, S.inInstance = "The Stockade", 34, true
  S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
  local cbody = table.concat(BT.AllLines(), "\n")
  ok(cbody:find("runs left") or cbody:find("runs owed") or cbody:find("/%d+ runs"),
     "baren seier kor mange runs som står att")
  BT.BarTooltip(GameTooltip)
  local ctip = S.TipText()
  ok(ctip:find("your account with Paidar"), "tooltipen viser heile rekninga")
  ok(ctip:find("that buys"), "kva pengane kjøpte")
  ok(ctip:find("runs since"), "kor mange runs du har hatt")

  -- og i trade-loggen, ei rad per betaling med kva den kjøpte og kva som stod att
  BT.ToggleWindow()
  BT.ShowTab("gold")
  do
    local wg = _G.ChainWindow
    local withRuns = 0
    for _, row in ipairs(wg.rows or {}) do
      if row:IsShown() then
        local buys = row.cells and row.cells[6]
        local rest = row.cells and row.cells[7]
        local bt = buys and (buys:GetText() or "") or ""
        local rt = rest and (rest:GetText() or "") or ""
        if bt:find("%d") and rt:find("%d") then withRuns = withRuns + 1 end
      end
    end
    eq(withRuns, 2, "begge betalingane seier kva dei kjøpte og kva som stod att")
  end
  -- og på booster-rada, så du ser det der du vel kven du skal gå med
  BT.ShowTab("boosters")
  do
    local wb = _G.ChainWindow
    local found = false
    for _, row in ipairs(wb.rows or {}) do
      if row:IsShown() and row.cells and row.cells[1]
         and (row.cells[1]:GetText() or ""):find("Paidar") then
        local left = row.cells[12] and (row.cells[12]:GetText() or "") or ""
        if left:find("%d") then found = true end
      end
    end
    ok(found, "booster-rada seier kor mange runs du har til gode hos han")
  end
  BT.ToggleWindow()

  -- Ein handel addonet ikkje fekk med seg skal kunne skrivast inn. Utan det
  -- er balansen feil frå fyrste dag, og eit tal du veit er feil er eit tal du
  -- sluttar å lese.
  do
    -- du skriv det inn no, etter alt som står over
    S.now = t0 + 9000
    local before = #ChainDB.trades
    local leftBefore = BT.BoosterCredit("Paidar").left
    local rec, why = BT.LogPayment("  paidar-Testrealm ", 200)
    ok(rec ~= nil, "betaling skriven inn for hand (" .. tostring(why) .. ")")
    eq(#ChainDB.trades, before + 1, "og den står i logga")
    eq(rec.with, "Paidar", "namnet reinska")
    ok(rec.manual, "merka som skriven inn")
    near(BT.BoosterCredit("Paidar").left, leftBefore + 5,
         "200g til 40g per run er fem runs meir")

    -- og ut att om du skreiv feil
    ok(BT.ForgetTrade(rec), "og den kan fjernast")
    eq(#ChainDB.trades, before, "logga er som før")
    near(BT.BoosterCredit("Paidar").left, leftBefore, "og balansen med")

    eq(BT.LogPayment("", 100), nil, "utan namn skjer ingenting")
    eq(BT.LogPayment("Paidar", 0), nil, "og utan beløp heller")
    -- ein du aldri har sett pris på fell tilbake på instansen sin pris, slik
    -- alt anna i addonet gjer
    local fb = BT.LogPayment("Utanpris", 100)
    ok(fb ~= nil and (fb.perRun or 0) > 0, "utan eigen pris gjeld instansen sin")
    BT.ForgetTrade(fb)
  end

  -- Halve gullet i ein boost blir levert til ein bank-alt og ikkje til
  -- boosteren sjølv. Handelen er ekte og pengane er borte; dei landar berre
  -- på eit namn som aldri har køyrt noko for deg - så boosteren ser ubetalt ut
  -- og alten ser ut som ein framand som skuldar deg tjue runs.
  do
    S.now = t0 + 9500
    local leftBefore = BT.BoosterCredit("Paidar").left
    BT.LogPayment("Banken", 200)
    eq(BT.BoosterCredit("Paidar").left, leftBefore,
       "gull til ein framand tel ikkje for boosteren")

    BT.SetPaysFor("Banken", "Paidar")
    near(BT.BoosterCredit("Paidar").left, leftBefore + 5,
         "men peikar du alten mot han, tel det")
    eq(BT.PaysFor("Banken"), "Paidar", "og den hugsar kven han betaler for")

    -- og det kan gjerast om
    BT.SetPaysFor("Banken", nil)
    near(BT.BoosterCredit("Paidar").left, leftBefore, "og det kan gjerast om")
    eq(BT.SetPaysFor("Paidar", "Paidar"), nil, "ein kan ikkje vere sin eigen alt")

    -- frå slash-linja òg
    SlashCmdList["CHAIN"]("alt banken paidar")
    eq(BT.PaysFor("Banken"), "Paidar", "og frå slash-linja")
    SlashCmdList["CHAIN"]("alt banken")
    eq(BT.PaysFor("Banken"), nil, "og tilbake igjen")

    -- Namn skal ikkje måtte skrivast. Halvparten heiter Zånzå og Cartèr.
    S.party = { { name = "Berreta-Testrealm", lvl = 60 },
                { name = "Cartèr-Testrealm", lvl = 60 } }
    local names = BT.PayableNames()
    local found = {}
    for _, p in ipairs(names) do found[p.name] = p.why end
    ok(found["Berreta"], "gruppa du står i er med")
    ok(found["Cartèr"], "aksentar og alt")
    ok(found["Paidar"], "og dei du har handla med før")
    eq(found["Tester"], nil, "men ikkje deg sjølv")
    S.party = {}
  end

  -- Og den blunte varianten, den du treng den dagen du installerer dette
  -- midt i ei avtale: sju runs igjen, og ferdig med det.
  do
    local rec = BT.SetRunsLeft("Paidar", 7)
    ok(rec ~= nil, "balansen kan settast direkte")
    local c = BT.BoosterCredit("Paidar")
    near(c.left, 7, "sju runs igjen, uansett kva som stod før")
    eq(c.setTo, 7, "og den hugsar at du sa det")

    -- runs frå før tel ikkje lenger med
    near(c.runsDone, 0, "teljinga startar på nytt")

    -- ein run etterpå trekk frå
    table.insert(ChainDB.runs, { at = S.now + 10, by = "Paidar", id = "stock",
                                 zone = "The Stockade", xp = 9000, k = 30, t = 500 })
    BT.Touch()
    near(BT.BoosterCredit("Paidar").left, 6, "ein run seinare står det seks")

    -- og betaler du meir oppå, legg det seg til
    BT.LogPayment("Paidar", 120)                    -- tre runs
    near(BT.BoosterCredit("Paidar").left, 9, "tre kjøpte runs oppå dei seks")

    -- hovudboka viser same tala, og seier kva lina er
    local led = BT.CreditLedger()
    local setRow
    for _, t in ipairs(ChainDB.trades) do if t.setTo then setRow = t end end
    ok(setRow and led[setRow] and led[setRow].setTo == 7,
       "lina som sette balansen står som det i boka")

    -- slash-vegen inn, for når vindauget er lukka
    -- og frå slash-linja. Runen over ligg eit augeblink etter, så den blir
    -- trekt frå med det same - som den skal: du sa fire, og så gjekk du ein.
    SlashCmdList["CHAIN"]("left paidar 4")
    near(BT.BoosterCredit("Paidar").left, 3, "og /chain left set den òg")
    SlashCmdList["CHAIN"]("paid paidar 80")
    near(BT.BoosterCredit("Paidar").left, 5, "og /chain paid legg til")
    SlashCmdList["CHAIN"]("left paidar")
    SlashCmdList["CHAIN"]("paid")
  end

  -- og raden for å skrive det inn skal stå på Trade-fana, og berre der
  do
    BT.ToggleWindow()
    BT.ShowTab("gold")
    local wp = _G.ChainWindow
    ok(wp.payName and wp.payName:IsShown(), "namnefeltet står på Trade")
    ok(wp.payRunsButton and wp.payRunsButton:IsShown(), "og knappen for runs")
    ok(not (wp.addName and wp.addName:IsShown()),
       "og add-someone-raden ligg ikkje oppå den")
    -- x-en skal stå på lina du skreiv inn sjølv, og ikkje på dei andre
    local manual, watched = 0, 0
    for _, row in ipairs(wp.rows or {}) do
      if row:IsShown() and row.del and row.del:IsShown() then manual = manual + 1 end
      if row:IsShown() and row.del and not row.del:IsShown() then watched = watched + 1 end
    end
    ok(manual > 0, "x-en står på linene du skreiv inn")
    -- og på dei addonet såg sjølv òg: deteksjonen er ein slutning no - eit
    -- vindauge som lukka seg og aldri nemnde eit avbrot - og det som er
    -- slutta seg til må kunne rettast av den som faktisk var der
    eq(watched, 0, "og på dei addonet såg sjølv òg")
    BT.ShowTab("boosters")
    ok(not (wp.payName and wp.payName:IsShown()), "og er borte på dei andre fanene")
    BT.ToggleWindow()
  end

  ChainDB.trades, ChainDB.runs, ChainDB.boosters = oldTrades, oldRuns, oldBoosters
  ChainCharDB.lastBy = nil
  S.party = {}
  BT.Touch() BT.TouchTrades()
end

-- og det skal synast på baren, i begge modus
S.party = { { name = "Boostar-Testrealm", lvl = 60 } }
S.level, S.xp, S.xpMax = 23, 12000, 31700
S.zone, S.map, S.inInstance = "The Stockade", 34, true
S.Fire(frame, "ZONE_CHANGED_NEW_AREA")
local bbody = table.concat(BT.AllLines(), "\n")
-- Gullet høyrer ikkje heime på baren. Under baren står to ting - kor mange
-- runs du har att og kor lenge til du dinger - og kva steget har kosta står
-- på tooltipen, der det er plass til å seie kva det tyder.
ok(not bbody:find("paid "), "baren pakkar ikkje gullet inn under seg")
S.tip = {}
BT.BarTooltip(GameTooltip)
ok((S.TipText() or ""):find("paid"), "men tooltipen seier kva steget har kosta")
for line in (bbody .. "\n"):gmatch("([^\n]*)\n") do
  local clean = (line:gsub("|c%x%x%x%x%x%x%x%x", "")); clean = (clean:gsub("|r", ""))
  if clean ~= "" then
    print(string.format("   %-62s (%d)", clean, #clean))
    ok(#clean <= 74, "linje over 74 teikn: " .. clean)
  end
end
CornersFit()

-- Under baren står to ting når du er i ein boost, og berre to: kor mange runs
-- du har att, og kor lenge til du dinger. Det er det du er der for.
local function Plain(t)
  return ((tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""))):gsub("|r", "")
end
do
  -- Rett under baren, og ingenting anna på den linja: kor mange runs du har
  -- att i den eine enden, når du dingar i den andre. Baren sjølv held fram med
  -- å seie kvar du er og kor langt det er.
  local sl = BT.BuildText() or {}
  ok(Plain(sl.bottomLeft):find("^ding in"),
     "utan noko kjøpt er ding-linja åleine (" .. Plain(sl.bottomLeft) .. ")")
  eq(sl.bottomRight, nil, "og ingenting i det andre hjørnet")

  local who = BT.CurrentBooster() or "Boostar"
  BT.SetPrice(who, 100, 10)
  BT.LogPayment(who, 100)
  BT.Touch()
  local s2 = BT.BuildText() or {}
  ok(Plain(s2.bottomLeft):find("runs"),
     "med noko kjøpt er venstre kor mange runs du har att ("
     .. Plain(s2.bottomLeft) .. ")")
  ok(Plain(s2.bottomRight):find("^ding in"),
     "og høgre når du dingar (" .. Plain(s2.bottomRight) .. ")")
  ok(not Plain(s2.bottomLeft):find("xp/run")
     and not Plain(s2.bottomRight):find("xp/run"),
     "xp per run er ikkje der - det står på tooltipen")
  ok(not Plain(s2.bottomLeft):find("paid ")
     and not Plain(s2.bottomRight):find("paid "),
     "og ikkje gullet heller")
  CornersFit("hjørna under baren i boost")

  -- Farta står midt i baren, i begge modus. Det er talet du fylgjer medan du
  -- held på, det er like breitt heile tida, og midten er den eine staden
  -- ingenting anna slåst om.
  -- utan ei måling står det ingenting der, og baren seier avstanden som før
  eq(s2.bottomCenter, nil, "utan ei måling står det ingenting mellom dei")
  ok(Plain(s2.barCenter):find(" to %d+$"),
     "og baren seier avstanden som før (" .. Plain(s2.barCenter) .. ")")
  for _ = 1, 8 do
    S.now = S.now + 120
    S.xp = math.min(S.xpMax - 100, S.xp + 900)
    S.Fire(frame, "PLAYER_XP_UPDATE")
  end
  BT.Touch()
  local s4 = BT.BuildText() or {}
  ok((BT.Rate() or 0) > 0, "og no har han ei måling")
  ok(Plain(s4.bottomCenter):find("xp/h"),
     "farta står midt mellom hjørna i boost òg (" .. Plain(s4.bottomCenter) .. ")")

  -- Eit tal åleine seier ingenting: 56 000 xp/h er bra i SM og elendig i
  -- Strat. Difor blir det målt mot det steget faktisk plar gi, og fargen er
  -- svaret. Utan noko å måle mot står det kvitt - ein grøn farge ingen har
  -- sjekka er verre enn ingen farge.
  local stepNow2 = select(5, BT.StageSpan())
  local st2 = stepNow2 and BT.StepStats(stepNow2)
  if st2 and (st2.xp or 0) > 0 and (st2.t or 0) > 0 then
    local ref = st2.xp / st2.t * 3600
    ok((s4.bottomCenter or ""):find("|cff%x%x%x%x%x%x"),
       "farta har ein farge når det finst noko å måle mot")
    local got = BT.Rate() or 0
    local want = (got / ref >= 0.95) and BT.COL.good
      or ((got / ref >= 0.80) and BT.COL.warn or BT.COL.bad)
    ok((s4.bottomCenter or ""):find(want:gsub("|", "%%|"), 1) ~= nil,
       "og det er rett farge for " .. string.format("%.0f%%", got / ref * 100))
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
CornersFit()

-- gull-fana skal teikne
BT.ToggleWindow(); BT.ToggleWindow()

--------------------------------------------------------------------------
print("== booster-pris og tommel ==")
ChainDB.boosters = {}
S.party = { { name = "Boostar-Testrealm", lvl = 60 } }
S.level, S.xp, S.xpMax = 22, 0, 27300
local _, st2 = BT.Stage()

-- utan eigen pris fell den tilbake på steg-prisen (50g per 5 runs = 10g/run)
local per, own = BT.PricePerRun(st2, "Boostar")
near(per, 10, "steg-pris per run")
eq(own, false, "ikkje boosteren sin eigen pris")

-- boosteren seier 12g per run
BT.SetPrice("Boostar", 12, 1)
per, own = BT.PricePerRun(st2, "Boostar")
near(per, 12, "boosteren sin eigen pris")
eq(own, true, "merka som hans pris")
eq(BT.Cost(st2, 10, "Boostar"), 120, "ti runs hos Boostar")
eq(BT.Cost(st2, 10, "Snoegg"), 100, "Snoegg fell tilbake på steg-prisen")

-- pakkepris: 5 runs for 45g
BT.SetPrice("Snoegg", 45, 5)
near(BT.PricePerRun(st2, "Snoegg"), 9, "pakkepris per run")
eq(BT.Cost(st2, 6, "Snoegg"), 90, "seks runs blir to pakkar")

-- prisen du blir oppgjeven gjeld ein pakke, aldri ein enkelt run
local stepNow = select(2, BT.Stage())
ChainDB.pack = 5
BT.SetPrice("Boostar", 60)                 -- 60g for 5 runs
eq(ChainDB.boosters["Boostar"].pack, 5, "pakkestorleiken blir lagra med prisen")
near(BT.PricePerRun(stepNow, "Boostar"), 12, "60g / 5 runs = 12g per run")
eq(BT.Cost(stepNow, 5, "Boostar"), 60, "fem runs er ein pakke")
eq(BT.Cost(stepNow, 6, "Boostar"), 120, "seks runs er to pakkar")

-- dommen blir rekna ut, ikkje klikka: xp per gull
local v = BT.XPPerGold(stepNow, "Boostar", 9000)
near(v, 750, "9 000 xp for 12g per run = 750 xp per gull")
-- billegare booster med same xp er betre
BT.SetPrice("Billeg", 30)
near(BT.XPPerGold(stepNow, "Billeg", 9000), 1500, "halv pris = dobbel verdi")
-- fleire mobs for same pris er betre
near(BT.XPPerGold(stepNow, "Boostar", 18000), 1500, "dobbel xp = dobbel verdi")
eq(select(2, BT.Grade(1500, 1500)), "good", "beste er god")
eq(select(2, BT.Grade(1200, 1500)), "ok", "80 % er ok")
eq(select(2, BT.Grade(800, 1500)), "poor", "53 % er dårleg")
eq(BT.XPPerGold(stepNow, "Ukjend", 9000) ~= nil, true, "utan eigen pris fell den til steg-prisen")
BT.SetPrice("Billeg", 0)

-- boosteren du faktisk spelar med slår prisen du sette på instansen
do
  local route = ChainDB.route.stock
  local oldGold, oldPrice = route.gold, ChainDB.boosters["Boostar"].price
  route.gold = 75                              -- 75g per pakke i configen
  BT.SetPrice("Boostar", 50)                  -- men han tek 50
  BT.Touch()
  near(BT.PricePerRun(stepNow, "Boostar"), 10, "hans 50g/5 slår 75g/5 i configen")
  near(BT.PricePerRun(stepNow, nil), 15, "utan booster gjeld configen")
  eq(BT.Cost(stepNow, 5, "Boostar"), 50, "og kostnaden fylgjer han")
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
  ok(basis and basis:find("Boostar's price"), "og seier kven prisen er frå")
  route.gold, ChainDB.boosters["Boostar"].price = oldGold, oldPrice
  BT.Touch()
end

-- pakkestorleik per instans: nokon sel ti der andre sel fem
do
  local route = ChainDB.route.stock
  local oldGold, oldPack = route.gold, route.pack
  local oldPrice = ChainDB.boosters["Boostar"].price
  route.gold, route.pack = 100, 10            -- 100g for ti runs her
  BT.SetPrice("Boostar", 0)
  BT.Touch()
  eq(BT.StepPack(stepNow), 10, "instansen sin eigen pakke slår innstillinga")
  near(BT.PricePerRun(stepNow, nil), 10, "100g / 10 runs = 10g per run")
  eq(BT.Cost(stepNow, 10, nil), 100, "ti runs er ein pakke")
  eq(BT.Cost(stepNow, 11, nil), 200, "elleve runs er to")
  -- ein annan instans er framleis på den globale
  local other = BT.BY_ID and BT.BY_ID["sm"] or nil
  if other then eq(BT.StepPack(other), 5, "andre instansar rører seg ikkje") end

  -- ein pris skriven no gjeld den pakken, ikkje den globale
  BT.SetPrice("Boostar", 300)
  eq(ChainDB.boosters["Boostar"].pack, 10, "prisen blir lagra mot 10 runs")
  near(BT.PricePerRun(stepNow, "Boostar"), 30, "300g / 10 runs = 30g per run")

  -- og boosteren sin eigen avtale slår instansen sin
  BT.SetPack("Boostar", 20)
  near(BT.PricePerRun(stepNow, "Boostar"), 15, "300g / 20 runs hos han")
  eq(BT.Cost(stepNow, 20, "Boostar"), 300, "tjue runs er ein pakke hos han")
  -- og den held seg når du skriv prisen på nytt
  BT.SetPrice("Boostar", 400)
  eq(ChainDB.boosters["Boostar"].pack, 20, "pakken hans står seg")
  -- blankt felt: tilbake til det instansen går for
  BT.SetPack("Boostar", nil)
  eq(BT.PackFor(stepNow, "Boostar"), 10, "blankt felt fell til instansen")

  route.gold, route.pack = oldGold, oldPack
  ChainDB.boosters["Boostar"].price = oldPrice
  ChainDB.boosters["Boostar"].pack = 5
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
ok(not vbody:find("Gammal"), "og ikkje namnet hans heller")
-- xp/h står no midt i baren, med vilje: det er talet du fylgjer medan du held
-- på. Det er di eiga fart, ikkje boosteren si vurdering.
ok(vbody:find("xp/h") or vbody:find("measuring") or vbody:find("no xp for"),
   "farta står der derimot")
ok(not vbody:find("grp "), "gruppa heller ikkje")
TwoColumns("med ein booster")
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
CornersFit()

-- baren skal seie at gullet er heile pakkar. Reknestykket har alltid runda
-- opp til pakkar, men "~3 200g" ser likt ut anten det er per run eller per
-- ti - og då må ein spørje i staden for å sjå det.
do
  local who = BT.CurrentBooster()
  local oldPack = ChainDB.pack
  ChainDB.pack = 10
  BT.SetPrice(who or "Boostar", 100, 10)
  BT.Touch()
  S.tip = {}
  BT.BarTooltip(GameTooltip)
  local body = ((S.TipText() or ""):gsub("|c%x%x%x%x%x%x%x%x", "")):gsub("|r", "")
  local packs, size = body:match("(%d+) x (%d+)")
  ok(packs ~= nil, "tooltipen seier kor mange pakkar gullet er")
  eq(size, "10", "og kor mange runs det er i ein")
  -- talet skal vere det same som utrekninga faktisk brukar
  local remain, _, curStep = select(3, BT.StageSpan()), nil, select(5, BT.StageSpan())
  local st = curStep and BT.StepStats(curStep)
  if remain and remain > 0 and st and (st.xp or 0) > 0 then
    local _, want = BT.Cost(curStep, remain / st.xp, who)
    eq(tonumber(packs), want, "og det er dei pakkane du betaler for")
  end
  -- tooltipen skal seie kor mange runs du då har kjøpt
  BT.BarTooltip(GameTooltip)
  local tip = S.TipText()
  ok(tip:find("you pay for"), "tooltipen seier kor mange runs pakkane dekker")

  -- ein pakke på éin run har ingenting å seie frå seg
  ChainDB.pack = 1
  BT.SetPrice(who or "Boostar", 12, 1)
  BT.Touch()
  local one = table.concat(BT.AllLines(), "\n")
  ok(not one:find("x1%)"), "og seier ingenting når ein pakke er ein run")

  ChainDB.pack = oldPack
  BT.SetPrice(who or "Boostar", 60, 5)
  BT.Touch()
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

-- Den runden du er inne i høyrer heime øvst i lista. Han dukka fyrst opp når
-- du hadde gått ut, som er det eine augeblikket du ikkje treng å bli fortalt
-- om han - og når boosteren seier "det er fem" midt i kjeda, er runden du står
-- i nettopp den det er usemje om.
do
  local keepRun = ChainCharDB.run
  ChainCharDB.run = { start = S.now - 240, zone = "The Stockade", map = 34,
                      id = "sm", by = "Teljar", xp = 4200, k = 31, lvl = 22 }
  BT.ShowTab("runs")
  local wl = _G.ChainWindow
  local top = wl.rows[1]
  local when = ((top.cells[1]:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""))
  when = (when:gsub("|r", ""))
  eq(when, "now", "runden du er i står øvst, og seier 'now'")
  ok((top.cells[3]:GetText() or ""):find("4,200"), "med xp så langt")
  ok(not top.del:IsShown(), "han kan ikkje slettast - han er ikkje lagra enno")
  ok(not top.pick:IsShown(), "og ikkje hakkast av - han tel ikkje for noko enno")

  -- og når du går ut, er han borte att: han er lagra som ein vanleg run då,
  -- og skal ikkje stå der to gonger
  ChainCharDB.run = nil
  BT.ShowTab("runs")
  local nowRows = 0
  for _, r in ipairs(wl.rows or {}) do
    local txt = ((r.cells[1]:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""))
    if r:IsShown() and (txt:gsub("|r", "")) == "now" then nowRows = nowRows + 1 end
  end
  eq(nowRows, 0, "ute av instansen er han borte frå lista att")
  ChainCharDB.run = keepRun
end

-- Ei kolonneoverskrift har plass til to ord, og to ord kan ikkje seie kva
-- "after" eller "he gave" tyder. Difor forklarar overskrifta seg sjølv når du
-- held peikaren over henne - der du alt ser når du lurer.
do
  BT.ShowTab("gold")
  local wh2 = _G.ChainWindow
  local found, sortable = 0, 0
  for _, h in ipairs(wh2.headers or {}) do
    if h:IsShown() and h.hint then found = found + 1 end
  end
  ok(found >= 8, "gull-fana forklarar kolonnane sine (" .. found .. ")")

  local h = wh2.headers[7]
  eq(h.fs:GetText(), "to come", "og 'after' heiter noko ein forstår")
  S.tip = {}
  h.__scripts.OnEnter(h)
  local t = S.TipText() or ""
  ok(t:find("still owed you"), "med forklaringa i tooltipen")
  ok(t:find("Frozen"), "og at han er frosen der, ikkje levande")
  h.__scripts.OnLeave(h)

  BT.ShowTab("runs")
  local hints = 0
  for _, hh in ipairs(wh2.headers or {}) do
    if hh:IsShown() and hh.hint then hints = hints + 1 end
  end
  ok(hints >= 8, "historikk-fana gjer det same (" .. hints .. ")")
end

-- Betalingane høyrer heime i same lista som runane. "Når betalte eg, og kva
-- har eg fått sidan" er eitt spørsmål, og det var to faner: tidene låg i
-- Trade-fana og runane her, og du sat att med ei klokke i hovudet.
do
  local keepT, keepR = ChainDB.trades, ChainDB.runs
  ChainDB.trades, ChainDB.runs = {}, {}
  ChainCharDB.run = nil
  table.insert(ChainDB.trades, { at = S.now - 3000, with = "Blandar",
    gave = 400 * 10000, got = 0, id = "sm", perRun = 40, lvl = 38,
    char = "Tester" })
  for i = 1, 3 do
    table.insert(ChainDB.runs, { at = S.now - 2500 + i * 300, t = 300,
      zone = "The Stockade", id = "sm", by = "Blandar", xp = 9000, k = 60,
      lvl = 38 })
  end
  BT.Touch() BT.TouchTrades()
  BT.ShowTab("runs")
  local wm = _G.ChainWindow

  local order, tradeAt = {}, nil
  for i, row in ipairs(wm.rows or {}) do
    if row:IsShown() then
      local what = ((row.cells[2]:GetText() or "")
        :gsub("|c%x%x%x%x%x%x%x%x", "")):gsub("|r", "")
      if what ~= "" then
        table.insert(order, what)
        if what:find("^paid") and not tradeAt then tradeAt = #order end
      end
    end
  end
  ok(tradeAt ~= nil, "betalinga står i lista (" .. table.concat(order, " | ") .. ")")
  eq(tradeAt, 4, "under dei tre runane som kom etter henne")

  -- og ho seier kva ho kjøpte og kven som fekk pengane
  local tr
  for _, row in ipairs(wm.rows or {}) do
    local what = ((row.cells[2]:GetText() or "")
      :gsub("|c%x%x%x%x%x%x%x%x", "")):gsub("|r", "")
    if row:IsShown() and what:find("^paid") then tr = row break end
  end
  if tr then
    ok((tr.cells[7]:GetText() or ""):find("400"), "med summen i gull-kolonnen")
    ok((tr.cells[8]:GetText() or ""):find("Blandar"), "og kven som fekk dei")
    ok(tr.del:IsShown(), "og ho kan strykast herifrå òg")
    ok(not tr.pick:IsShown(), "men ikkje hakkast av - det er runar ein tel")
  end

  ChainDB.trades, ChainDB.runs = keepT, keepR
  BT.Touch() BT.TouchTrades()
end

-- Å gjere opp teljinga med boosteren.
--
-- Han seier fem, du talde fire, og ingen av dykk kan bevise noko fordi begge
-- tel i hovudet - han på tvers av tre kundar samtidig. Addonen tel ikkje i
-- hovudet, så han kan legge tidene i party chat og saka er ute av verda.
do
  BT.ShowTab("runs")
  local wq = _G.ChainWindow
  ok(wq.sinceButton ~= nil and wq.sinceButton:IsShown(),
     "historikk-fana har ein knapp for 'sidan sist betaling'")
  ok(wq.sayButton ~= nil and wq.sayButton:IsShown(), "og ein for å seie det")

  -- ei rad har eit hakk, og hakket slår av og på
  local picky
  for _, r in ipairs(wq.rows or {}) do
    if r:IsShown() and r.pick and r.pick:IsShown() and r.pick.rec then
      picky = r break
    end
  end
  ok(picky ~= nil, "og kvar rad har eit hakk")
  if picky then
    local rec = picky.pick.rec
    picky.pick.__scripts.OnClick(picky.pick)
    ok((wq.sayNote:GetText() or ""):find("1"), "eitt hakk er sett")

    -- og det blir sagt i party, med tidene i
    S.said, S.printed = {}, {}
    wq.sayButton.__scripts.OnClick(wq.sayButton)
    local line = S.said[1] or S.printed[1] or ""
    ok(line:find("1 run"), "linja seier kor mange (" .. line .. ")")
    ok(line:find("ago"), "og kor lenge sidan")
    ok(line:find("%[CHAIN%]"), "og kven som seier det")

    -- av att
    picky.pick.__scripts.OnClick(picky.pick)
    ok(not (wq.sayNote:GetText() or ""):find("1 "), "hakket kan takast av")
    S.said, S.printed = {}, {}
    wq.sayButton.__scripts.OnClick(wq.sayButton)
    eq(#S.said + #S.printed, 0, "og utan hakk blir ingenting sagt")
    if rec then end
  end

  -- "sidan sist betaling" er spørsmålet som faktisk blir stilt: kva har eg
  -- fått som eg ikkje har betalt for
  do
    local who = "Teljar"
    ChainDB.trades = ChainDB.trades or {}
    table.insert(ChainDB.trades, { at = S.now - 3000, with = who,
      gave = 100 * 10000, got = 0, id = "sm", perRun = 20, char = "Tester" })
    ChainDB.runs = ChainDB.runs or {}
    local before = { at = S.now - 3600, t = 300, zone = "The Stockade",
                     id = "sm", by = who, xp = 9000, k = 60, lvl = 20 }
    table.insert(ChainDB.runs, before)
    local a1 = { at = S.now - 2000, t = 300, zone = "The Stockade", id = "sm",
                 by = who, xp = 9000, k = 60, lvl = 20 }
    local a2 = { at = S.now - 1000, t = 300, zone = "The Stockade", id = "sm",
                 by = who, xp = 9000, k = 60, lvl = 20 }
    table.insert(ChainDB.runs, a1)
    table.insert(ChainDB.runs, a2)
    BT.Touch() BT.TouchTrades()
    BT.ShowTab("runs")
    wq.sinceButton.__scripts.OnClick(wq.sinceButton)
    ok((wq.sayNote:GetText() or ""):find("2"),
       "berre dei to etter betalinga blir hakka av ("
       .. (wq.sayNote:GetText() or "") .. ")")
    S.said, S.printed = {}, {}
    wq.sayButton.__scripts.OnClick(wq.sayButton)
    local line = S.said[1] or S.printed[1] or ""
    ok(line:find("2 runs with " .. who), "og linja namngir han (" .. line .. ")")
  end
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
  S.Fire(rf2, "CHAT_MSG_CHANNEL", "WTS Stockades boost 200g / 5 runs", "Seljar-Testrealm")
  S.now = S.now + 60
  S.Fire(rf2, "CHAT_MSG_WHISPER", "SM 5 runs 300g", "Kviskar-Testrealm")
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
  -- Ein annonse er ein som står i ei by og seier han er ledig no. Ein halv
  -- time seinare er han tre level inn i ei anna kjede, og linja er ei liste
  -- over folk som skal skuffe deg.
  do
    S.now = S.now + 1900
    BT.ShowTab("ads")
    local left = 0
    for _, r in ipairs(w3.rows or {}) do
      if r:IsShown() and (r.cells[2]:GetText() or "") ~= "" then left = left + 1 end
    end
    eq(left, 0, "ein halvtime gamal annonse er av lista")
    -- men det han lærte om prisen hans står att: det er kunnskap om han, og
    -- den blir ikkje gammal slik tilbodet gjer
    ok((ChainDB.boosters["Kviskar"] or {}).adPrice ~= nil
       or (ChainDB.boosters["Kviskar"] or {}).price ~= nil,
       "men prisen hans er ikkje gløymd")
    S.now = S.now - 1900
    BT.ShowTab("ads")
  end

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

-- Overskrifta på fana deler linje med "show only"-boksen, og ein fontstring
-- som ikkje får plass klipper ikkje - han blir teikna rett inn i han. Det er
-- same feilen som dei to hjørna under baren, og han såg slik ut:
--   "...'left' is what is still oweshow only"
do
  local LIMIT = 120
  for tab, layout in pairs(BT.LAYOUTS or {}) do
    local t = layout.title or ""
    ok(#t <= LIMIT, "overskrifta på " .. tab .. " er " .. #t
       .. " teikn og går inn i søkeboksen: " .. t)
  end
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
  local name = BT.AddBooster("  kjeltring-Testrealm ", "berre morgonar", step.id)
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
  S.Fire(rf, "CHAT_MSG_CHANNEL", text, who or "Selgar-Testrealm")
end

ad("WTS Stockades boost 40g per run, whisper me", "Selgar-Testrealm")
local b = ChainDB.boosters["Selgar"]
ok(b ~= nil, "boosteren hamna i lista")
eq(b and b.adPrice, 40, "pris frå annonsen")
eq(b and b.adZone, "stock", "instansen frå annonsen")
near(BT.QuotedPrice("Selgar", "stock"), 40, "pris per run")
eq(select(2, BT.QuotedPrice("Selgar", "stock")), "advert", "merka som annonse")

ad("Selling 5 runs Scarlet Monastery boost 200g total", "Rask-Testrealm")
eq(ChainDB.boosters["Rask"].adPack, 5, "pakkestorleik frå annonsen")
near(BT.QuotedPrice("Rask", "sm"), 40, "200g for 5 runs = 40g per run")

-- ting som ikkje er annonsar skal ikkje fange
ad("anyone got 40g to spare", "Tiggar-Testrealm")
eq(ChainDB.boosters["Tiggar"], nil, "tigging er ikkje ein annonse")
-- annonsar utan pris tel også: dei aller fleste har ingen pris i seg
ad("WTS Stockades boost, FFA loot, sum ready", "Utanpris-Testrealm")
ok(ChainDB.boosters["Utanpris"] ~= nil, "annonse utan pris blir lagra")
eq(ChainDB.boosters["Utanpris"].adPrice, 0, "med pris null")
ok((ChainDB.boosters["Utanpris"].adText or ""):find("FFA"),
   "og teksten blir teken vare på")
-- men den som leitar etter folk sel ingenting
ad("LFM Stockades boost, need 2 more", "Leitar-Testrealm")
eq(ChainDB.boosters["Leitar"], nil, "LFM er ikkje eit sal")
ad("WTB SM boost, paying well", "Kjopar-Testrealm")
eq(ChainDB.boosters["Kjopar"], nil, "WTB er ikkje eit sal")
-- og aliasa folk faktisk skriv
ad("WTS Mara boost 340-360 real mobs, 12min/run", "Mara-Testrealm")
eq(ChainDB.boosters["Mara"] and ChainDB.boosters["Mara"].adZone,
   "mara", "'Mara boost' blir kjend att")
ad("Wts SM Boost Cath & Arm, Wlc Lvl 20-42, FFA Loot", "Cath-Testrealm")
eq(ChainDB.boosters["Cath"] and ChainDB.boosters["Cath"].adZone,
   "sm", "'Cath & Arm' er SM")
ad("LF small group for questing", "Quest-Testrealm")
eq(ChainDB.boosters["Quest"], nil, "'small' skal ikkje matche SM")

-- annonsar skal lesast frå kva kanal som helst, og frå kvisk
do
  ChainDB.boosters = {}
  S.Fire(rf, "CHAT_MSG_WHISPER", "stockades 5 runs 250g mate", "Kviskrar-Testrealm")
  eq(ChainDB.boosters["Kviskrar"] and ChainDB.boosters["Kviskrar"].adPrice,
     250, "kvisk blir lest")
  eq(ChainDB.boosters["Kviskrar"].adFrom, "whisper", "og merka som kvisk")

  S.Fire(rf, "CHAT_MSG_YELL", "WTS SM boost 300g / 5 runs", "Ropar-Testrealm")
  ok(ChainDB.boosters["Ropar"] ~= nil, "yell blir lest")

  S.Fire(rf, "CHAT_MSG_PARTY", "sell stockades runs 60g each", "Gruppe-Testrealm")
  ok(ChainDB.boosters["Gruppe"] ~= nil, "party blir lest")
  eq(ChainDB.boosters["Gruppe"].adFrom, "party", "merka som party")

  -- ein namngjeven kanal, slik klienten sender han
  S.Fire(rf, "CHAT_MSG_CHANNEL", "Stockades 5 runs 200g", "Kanal-Testrealm",
         nil, "5. Boosting", nil, nil, nil, 5, "Boosting")
  eq(ChainDB.boosters["Kanal"] and ChainDB.boosters["Kanal"].adFrom,
     "channel:boosting", "kanalnamnet blir hugsa")

  -- vår eigen datakanal er aldri ein annonse
  S.Fire(rf, "CHAT_MSG_CHANNEL", "Stockades 5 runs 200g", "Falsk-Testrealm",
         nil, "5. ChainData", nil, nil, nil, 5, "ChainData")
  eq(ChainDB.boosters["Falsk"], nil, "vår eigen kanal blir ikkje lest")

  -- og du kan slå av ein kjelde
  BT.SetAdSource("whisper", false)
  S.Fire(rf, "CHAT_MSG_WHISPER", "stockades 5 runs 100g", "Stille-Testrealm")
  eq(ChainDB.boosters["Stille"], nil, "avslått kjelde blir ikkje lest")
  BT.SetAdSource("whisper", true)
  S.Fire(rf, "CHAT_MSG_WHISPER", "stockades 5 runs 100g", "Stille-Testrealm")
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
  S.Fire(rf, "CHAT_MSG_CHANNEL", "Stockades 5 runs 200g", "Bymann-Testrealm",
         nil, "1. General - Stormwind City", nil, nil, nil, 1, "General - Stormwind City")
  eq(ChainDB.boosters["Bymann"].adFrom, "channel:general",
     "General i byen er General")
  BT.SetAdSource("channel:general", false)
  S.Fire(rf, "CHAT_MSG_CHANNEL", "Stockades 5 runs 200g", "Utabygds-Testrealm",
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
ad("WTS Stockades boost 40g per run, whisper me", "Selgar-Testrealm")
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
ad("WTS Maraudon boost 90g per run", "Seint-Testrealm")
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
  S.Fire(rf, "CHAT_MSG_CHANNEL", text, who or "Nokon-Testrealm", ...)
end

grp("LFM SM cath, need healer and 2 dps, lvl 30-38", "Leiar-Testrealm")
local g = BT.GroupLog()[1]
ok(g ~= nil, "LFM blir plukka opp")
eq(g and g.by, "Leiar", "kven som skreiv det")
eq(g and g.kind, "lfm", "merka som ei gruppe som blir fylt")
eq(g and g.id, "sm", "instansen blir kjend att")
eq(g and g.levels, "30-38", "level-spennet blir lese")
ok(g and (g.needs or ""):find("healer"), "og kva dei manglar (" ..
   tostring(g and g.needs) .. ")")
ok(g and (g.text or ""):find("cath"), "teksten blir teken vare på heil")

grp("LFG Stockades, rogue 24", "Leitar-Testrealm")
eq(BT.GroupLog()[1].kind, "lfg", "LFG er nokon som vil vere med")
eq(BT.GroupLog()[1].id, "stock", "og instansen blir kjend att")

grp("WTB SM boost, paying well", "Kjopar-Testrealm")
eq(BT.GroupLog()[1].kind, "wtb", "WTB er nokon som vil kjøpe")

-- LF2M med tal
grp("LF2M ZF, need tank", "Tal-Testrealm")
eq(BT.GroupLog()[1].kind, "lfm", "LF2M er òg ei gruppe som blir fylt")
ok((BT.GroupLog()[1].needs or ""):find("2 more"), "og talet blir lese")

-- ein quest utan instans: teksten er heile poenget
grp("LF3M for Uldaman quest chain, lvl 40+", "Questar-Testrealm")
local q = BT.GroupLog()[1]
eq(q.kind, "lfm", "quest-innlegg er berre eit innlegg til")
ok((q.text or ""):find("quest"), "og teksten står der du kan søkje i han")
eq(q.levels, "40+", "'40+' blir lese")

-- eit sal er ikkje ei gruppe, og ei gruppe er ikkje eit sal
ChainDB.boosters = {}
grp("WTS Stockades boost 40g per run", "Selgar2-Testrealm")
ok(ChainDB.boosters["Selgar2"] ~= nil, "salet hamnar hos boosterane")
local none = true
for _, e in ipairs(BT.GroupLog()) do
  if e.by == "Selgar2" then none = false end
end
ok(none, "og ikkje i gruppelista")

-- vanleg prat blir ikkje plukka opp
local before = #BT.GroupLog()
grp("anyone know where the blacksmith is", "Prat-Testrealm")
eq(#BT.GroupLog(), before, "vanleg prat blir ignorert")

-- same mann som skrik det same kvart halvminutt skal ikkje fylle lista
local n0 = #BT.GroupLog()
grp("LFM SM cath, need healer and 2 dps, lvl 30-38", "Leiar-Testrealm")
grp("LFM SM cath, need healer and 2 dps, lvl 30-38", "Leiar-Testrealm")
eq(#BT.GroupLog(), n0, "ei gjentaking lagar inga ny rad")
local rep
for _, e in ipairs(BT.GroupLog()) do
  if e.by == "Leiar" then rep = e break end
end
eq(rep and rep.n, 3, "men ho blir talt")
eq(BT.GroupLog()[1].by, "Leiar", "og flyttar seg øvst")

-- kjelder og av-brytar verkar som for annonsane
S.Fire(rf, "CHAT_MSG_YELL", "LFG RFD anyone", "Ropar2-Testrealm")
eq(BT.GroupLog()[1].from, "yell", "yell blir lese og merka")
ChainDB.readGroups = false
local n1 = #BT.GroupLog()
grp("LFM BRD, need 3", "Seint2-Testrealm")
eq(#BT.GroupLog(), n1, "kan slåast av")
ChainDB.readGroups = true

-- og lista har eit tak, så ho ikkje veks i det uendelege
for i = 1, 40 do grp("LFM Stockades run " .. i, "Spam" .. i .. "-Testrealm") end
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
-- Gjennom LibDBIcon i staden for ei ramme av vårt eige. Den handrulla verka
-- fint, men kvar einaste knappe-samlar på skjermen leitar etter LibDBIcon og
-- klagar på alt anna. Her testar vi vår side av avtalen: objektet vi leverer,
-- og kva våre eigne klikk og tooltip gjer.
ChainDB.minimap = true
BT.RefreshMinimap()
do
  local obj = S.ldbObjects["Chain"]
  ok(obj ~= nil, "datamengda blir levert til LibDataBroker")
  eq(obj and obj.type, "launcher", "som ein launcher")
  ok(obj and (obj.icon or ""):find("minimap"), "med ikonet vårt (" ..
     tostring(obj and obj.icon) .. ")")
  ok(S.iconRegistered["Chain"] ~= nil, "og registrert hos LibDBIcon")
  ok(S.iconRegistered["Chain"].db == ChainDB.minimapIcon,
     "med vår eiga tabell, så posisjonen blir hugsa")

  -- klikka er våre
  local w = _G.ChainWindow
  if w and w:IsShown() then BT.ToggleWindow() end
  obj.OnClick(nil, "LeftButton")
  ok(_G.ChainWindow and _G.ChainWindow:IsShown(), "venstreklikk opnar vindauget")
  obj.OnClick(nil, "LeftButton")
  if _G.ChainOptions and _G.ChainOptions:IsShown() then BT.ToggleOptions() end
  obj.OnClick(nil, "RightButton")
  ok(_G.ChainOptions and _G.ChainOptions:IsShown(), "høgreklikk opnar innstillingane")
  BT.ToggleOptions()
  local shown = ChainDB.shown
  obj.OnClick(nil, "MiddleButton")
  ok(ChainDB.shown ~= shown, "midtklikk skjuler baren")
  obj.OnClick(nil, "MiddleButton")

  -- og tooltipen er vår
  S.tip = {}
  obj.OnTooltipShow(GameTooltip)
  local tip = S.TipText()
  ok(tip:find("Chain"), "tooltipen har namnet")
  ok(tip:find("instances this hour"), "og lockouten")
  ok(tip:find("Left%-click"), "og kva knappane gjer")

  -- av og på
  eq(BT.ToggleMinimap(), false, "kan slåast av")
  eq(S.iconHidden["Chain"], true, "og då blir han gøymd")
  BT.ToggleMinimap()
  eq(S.iconHidden["Chain"], false, "og synleg igjen")
end

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

-- og biblioteka må faktisk liggje i mappa, elles er knappen borte hos folk
for _, lib in ipairs({ "LibStub/LibStub.lua",
                       "CallbackHandler-1.0/CallbackHandler-1.0.lua",
                       "LibDataBroker-1.1/LibDataBroker-1.1.lua",
                       "LibDBIcon-1.0/LibDBIcon-1.0.lua" }) do
  local fh = io.open(DIR .. "Libs/" .. lib, "r")
  ok(fh ~= nil, "Libs/" .. lib .. " ligg i mappa")
  if fh then fh:close() end
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
report("Venn-Testrealm", "Snoegg", "stock", 45, 5, 8000, 480, 80, 10)
local sh = BT.SharedStats("Snoegg", "stock")
ok(sh ~= nil, "rapport motteken")
eq(sh.people, 1, "ein rapportør")
near(sh.mobs, 80, "mobs frå rapporten")
near(BT.QuotedPrice("Snoegg", "stock"), 9, "45g for 5 runs = 9g per run")
eq(select(2, BT.QuotedPrice("Snoegg", "stock")), "reported", "merka som rapportert")

-- same person sender på nytt: skal erstatte, ikkje leggast til
report("Venn-Testrealm", "Snoegg", "stock", 45, 5, 9000, 480, 90, 10)
sh = BT.SharedStats("Snoegg", "stock")
eq(sh.people, 1, "framleis ein rapportør")
near(sh.mobs, 90, "nyaste tal gjeld")

-- to personar, vekta etter kor mange runs dei har bak seg
report("Annan-Testrealm", "Snoegg", "stock", 45, 5, 3000, 480, 30, 90)
sh = BT.SharedStats("Snoegg", "stock")
eq(sh.people, 2, "to rapportørar")
ok(sh.mobs < 45, "den med 90 runs veg tyngst (" .. string.format("%.0f", sh.mobs) .. ")")

-- ekko av oss sjølve, feil prefiks og søppel
report("Tester", "Snoegg", "stock", 45, 5, 9000, 480, 90, 10)
eq(BT.SharedStats("Snoegg", "stock").people, 2, "vårt eige ekko tel ikkje")
S.Fire(rf, "CHAT_MSG_ADDON", "LVLTRK1", "tull", "CHANNEL", "Venn-Testrealm")
S.Fire(rf, "CHAT_MSG_ADDON", "ANNAPREFIX", "v2|X|stock|1|1|1|1|1|1", "CHANNEL", "Venn-Testrealm")
eq(ChainDB.boosters["X"], nil, "feil prefiks blir ignorert")
report("Venn-Testrealm", "Y", "ikkje-ein-instans", 1, 1, 1, 1, 1, 1)
eq(ChainDB.boosters["Y"], nil, "ukjend instans blir ignorert")
-- gammal protokoll blir ignorert
S.Fire(rf, "CHAT_MSG_ADDON", "LVLTRK1", "v1|Gammal|45|5|1", "CHANNEL", "Venn-Testrealm")
eq(ChainDB.boosters["Gammal"], nil, "v1 blir ignorert")
-- delingsomfang: kven som høyrer deg
eq(BT.ShareScopeName(), "everyone", "standard er alle")
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
BT.SetShareFriends("Kompis-Testrealm, Annan , ")
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
    map = 34, id = "stock", by = "Boostar", xp = 9000, k = 90, lvl = 22 })
end
BT.Touch()
S.party = { { name = "Boostar-Testrealm", lvl = 60 } }
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
    map = 189, id = "sm", by = "Boostar", xp = 9000, k = 90, lvl = 34 })
end
BT.Touch()
local lvlAt, best = BT.SwitchAt(BT.BY_ID["stock"], "Boostar")
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
  id = "stock", by = "Boostar", xp = 9999, k = 80, lvl = 22 })
eq(#BT.Runs({ id = "stock" }), before + 1, "cachen ser ein skriving utan Touch")

-- 2 000 runs og 200 fulle oppteikningar
ChainDB.runs = {}
for i = 1, 2000 do
  table.insert(ChainDB.runs, { at = S.now - i * 600, t = 400 + i % 120,
    zone = "The Stockade", id = "stock", by = (i % 3 == 0) and "Snoegg" or "Boostar",
    xp = 8000 + i % 2000, k = 85, lvl = 20 + i % 10, grp = 5, grpAvg = 30 })
end
BT.Touch()
S.zone, S.map, S.inInstance = "The Stockade", 34, true
S.party = { { name = "Boostar-Testrealm", lvl = 60 } }
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
print("== vindauget si eiga plass ==")
-- Ni faner fyller rada, og søkjeboksen låg oppå den siste av dei.
do
  BT.ShowTab("runs")
  local w = _G.ChainWindow
  local function firstPoint(obj)
    local pts = obj:GetPoints()
    return pts and pts[#pts] or nil
  end
  -- faneraden ligg på -28; søket må vere tydeleg under han
  local sp = firstPoint(w.search)
  ok(sp ~= nil, "søkjeboksen er plassert")
  ok(sp and sp.y <= -44,
     "og ligg under faneraden, ikkje oppå henne (y=" ..
     tostring(sp and sp.y) .. ")")
  -- og rada med overskrifter må vere under søket igjen
  local hp = firstPoint(w.headerRow)
  ok(hp and sp and hp.y < sp.y, "kolonneoverskriftene er under søket")

  -- Rank-fana har ein målboks på same linje som legg-til-rada, og berre éi av
  -- dei skal vere framme om gongen. To sett kontrollar i same rute er den
  -- feilen som har kome att flest gonger her.
  S.pvpRank, S.pvpProgress = 5, 0
  S.weekHonor, S.weekKills = 60000, 200
  BT.ShowTab("pvp")
  ok(w.targetBox and w.targetBox:IsShown(), "målboksen er framme på Rank")
  ok(not w.addName:IsShown(), "og legg-til-boksen er det ikkje")
  BT.ShowTab("boosters")
  ok(w.addName:IsShown(), "på Boosters er det omvendt")
  ok(not w.targetBox:IsShown(), "og målboksen er borte")
  BT.ShowTab("runs")
end

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

  -- Fyllet skal måle steget du sette opp. Han stod på 1,9% på level 35 i eit
  -- steg frå 28 til 42, under ei overskrift som sa "28 > 42" - og ein bar på
  -- to prosent under den overskrifta les som øydelagt.
  do
    local doneP, totalP, fromP, toP = BT.StepProgress()
    eq(fromP, 28, "fyllet måler frå der steget byrjar")
    eq(toP, 42, "og til der det sluttar")
    near(totalP, BT.Span(28, 42), "heile spennet er nemnaren", 1)
    near(doneP, BT.Span(28, 34) + 5000, "og teljaren er kor langt du har kome", 1)
    ok(doneP / totalP > 0.3,
       "så baren står midt på, ikkje på to prosent (" ..
       string.format("%.1f%%", doneP / totalP * 100) .. ")")
    -- og prosenten i overskrifta er den same som fyllet
    ok((slots.topLeft or ""):find(BT.Pct(doneP / totalP), 1, true),
       "overskrifta seier same prosent som baren viser")
    -- baren sjølv skal ha fått dei tala
    eq(slots.max, totalP, "baren får heile spennet som maks")
    eq(slots.cur, doneP, "og det du har gjort som fyll")
  end

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

  S.level = 34
  BT.Touch()
  -- Runen du står i høyrer heime på tooltippen, ikkje under baren. Han er
  -- ikkje noko du handlar på midt i - du er alt inne i instansen - og under
  -- baren var han ei linje som kom og gjekk medan du las.
  do
    ChainCharDB.run = { start = S.now - 90, xp = 2119, k = 16,
                        partial = true, zone = "Scarlet Monastery" }
    local sl = BT.BuildText()
    local under = sl.extra or ""
    ok(not under:find("2,119"), "runen står ikkje under baren lenger")
    ok(not under:find("not in average"), "og heller ikkje merkelappane hans")

    BT.BarTooltip(BT.bar)
    local tip = S.TipText()
    ok(tip:find("this run"), "men han står på tooltippen")
    ok(tip:find("2,119"), "med xp-en")
    ok(tip:find("16 mobs"), "og mobsa")
    ok(tip:find("left out of the averages"),
       "og kvifor han ikkje tel, sagt med ord i staden for ein merkelapp")
    ChainCharDB.run = nil
  end

  S.level = 20
  S.xp, S.xpMax = 0, 23200
  ChainDB.route = keepRoute
  BT.Touch()
end

--------------------------------------------------------------------------
print("== ærens-systemet ==")
-- Dette er IKKJE 2005-systemet. Sidan 1.14 er det ei trapp: kvar veke har du
-- opp til fire honor-milepælar, og ingenting mellom dei tel. Heile fila står
-- og fell på at trappa er rett, så ho blir testa mot det publiserte dømet.
do
  local P = BT.PVP

  -- honorFor[n] er honoren som ei veke må nå for å ende på rank n, og dei
  -- skal svare nøyaktig til botnen av kvar rank
  eq(P.honorFor[1], 0, "rank 1 krev berre drapa")
  eq(P.honorFor[6], 45000, "og ladderen er spelet sin eigen")
  eq(P.honorFor[14], 500000, "toppen er 500k")
  eq(#P.honorFor, 14, "ein for kvar rank")

  -- Å klatre éin rank spør berre om honoren til ranken du alt står på. Alle
  -- større sprang spør om honoren til der du hoppar til - det er difor fire
  -- ranker på ei veke kostar så mykje meir enn éin.
  eq(BT.MilestoneHonor(4, 5), P.honorFor[4], "eitt steg opp kostar din eigen rank")
  eq(BT.MilestoneHonor(4, 6), P.honorFor[6], "to steg kostar målet sin")
  eq(BT.MilestoneHonor(4, 8), P.honorFor[8], "og fire steg likeeins")
  eq(BT.MilestoneHonor(4, 9), nil, "fem ranker på ei veke finst ikkje")
  eq(BT.MilestoneHonor(4, 4), nil, "og du kan ikkje sikte på der du er")
  eq(BT.MilestoneHonor(13, 15), nil, "eller forbi toppen")

  -- Det publiserte dømet: rank 4 og 60,0% skal gje nøyaktig desse fire.
  -- Går dette i stykker, er rekninga vår feil og ikkje testen.
  do
    local ms = BT.Milestones(4, 0.6)
    eq(#ms, 4, "fire milepælar på rank 4")
    eq(ms[1].honor, 22500, "fyrste er 22 500")
    eq(ms[2].honor, 45000, "andre er 45 000")
    eq(ms[3].honor, 77500, "tredje er 77 500")
    eq(ms[4].honor, 110000, "fjerde er 110 000")
    near(ms[1].cp, 15000, "22 500 endar på 15 000 CP", 1)
    near(ms[2].cp, 19000, "45 000 endar på 19 000 CP", 1)
    near(ms[3].cp, 22500, "77 500 endar på 22 500 CP", 1)
    near(ms[4].cp, 26000, "110 000 endar på 26 000 CP", 1)
    -- og det same sagt som rank og prosent, slik spelaren ser det
    eq(ms[1].rank, 5, "som er rank 5")
    near(ms[1].progress, 0, "på 0%", 0.001)
    eq(ms[2].rank, 5, "rank 5")
    near(ms[2].progress, 0.8, "på 80%", 0.001)
    eq(ms[3].rank, 6, "rank 6")
    near(ms[3].progress, 0.5, "på 50%", 0.001)
    eq(ms[4].rank, 7, "rank 7")
    near(ms[4].progress, 0.2, "på 20%", 0.001)
  end

  -- Taket på fyrste steget: du kan ikkje få betalt to gonger for veg du alt
  -- har gått. Same rank, lenger framme, skal gje mindre.
  do
    local low = BT.Milestones(4, 0.0)[1]
    local high = BT.Milestones(4, 0.9)[1]
    ok(low.cp - BT.RankCP(4, 0) > high.cp - BT.RankCP(4, 0.9),
       "jo lenger ut i ranken du er, jo mindre gjev fyrste steget")
    -- men begge endar på minst botnen av neste rank
    -- og taket er hardt: fyrste steget tek deg aldri forbi botnen av neste
    -- rank, uansett kvar i ranken du står. Frå 0% endar du på 80% av vegen,
    -- frå 90% endar du akkurat på botnen av rank 5 - aldri over.
    near(low.cp, BT.RankCP(4, 0.8), "frå 0% kjem du 80% av vegen", 1)
    near(high.cp, BT.RankCP(5, 0), "frå 90% kjem du akkurat til rank 5", 1)
    ok(low.cp <= BT.RankCP(5, 0) + 1 and high.cp <= BT.RankCP(5, 0) + 1,
       "og ingen av dei går forbi botnen av neste rank")
  end

  -- Toppen av stigen har færre milepælar, fordi det er mindre stige att
  eq(#BT.Milestones(11, 0), 3, "rank 11 har tre")
  eq(#BT.Milestones(12, 0), 2, "rank 12 har to")
  eq(#BT.Milestones(13, 0), 1, "og rank 13 har éin einaste veg vidare")
  eq(BT.Milestones(13, 0)[1].honor, 418750, "og han kostar 418 750")

  -- Ingenting mellom milepælane tel. Det er heile poenget.
  do
    local met = BT.MetMilestone(4, 0.6, 44999, 50)
    eq(met.honor, 22500, "44 999 er verdt akkurat det same som 22 500")
    local met2 = BT.MetMilestone(4, 0.6, 45000, 50)
    eq(met2.honor, 45000, "eitt einaste honor meir, og du er på neste")
    eq(BT.MetMilestone(4, 0.6, 22499, 50), nil, "under den fyrste er null")
    -- og over den siste er like verdilaust som mellom to
    local over = BT.MetMilestone(4, 0.6, 999999, 50)
    eq(over.honor, 110000, "over den siste får du ikkje meir enn den siste")
  end

  -- 15 drap, elles tel ingenting
  eq(BT.MetMilestone(4, 0.6, 500000, 14), nil, "14 drap er ikkje nok")
  ok(BT.MetMilestone(4, 0.6, 500000, 15) ~= nil, "15 er")

  -- neste milepæl og kor langt unna han er - talet som skal på skjermen
  do
    local m, short = BT.NextMilestone(4, 0.6, 30000)
    eq(m.honor, 45000, "neste er 45 000")
    eq(short, 15000, "og du manglar 15 000")
    eq(BT.NextMilestone(4, 0.6, 200000), nil, "over toppen finst det ingen neste")
  end

  -- Planen: veke for veke til ranken du vil ha
  do
    local plan = BT.PlanToRank(10, 4, 0)
    ok(#plan.weeks > 0, "det blir ein plan")
    ok(plan.endRank >= 10, "som kjem fram (" .. tostring(plan.endRank) .. ")")
    -- fire ranker er det meste ei veke kan gje, så seks ranker tek minst to
    ok(#plan.weeks >= 2, "seks ranker tek meir enn ei veke")
    -- veketala skal auke, og totalen skal stemme med summen
    local sum = 0
    for i, w in ipairs(plan.weeks) do
      eq(w.week, i, "veke " .. i .. " er nummerert rett")
      sum = sum + w.honor
      near(w.total, sum, "totalen fylgjer med", 1)
      ok(w.honor > 0 or w.from <= 1, "kvar veke har eit tal å stoppe på")
    end
    near(plan.total, sum, "og heile planen er summen av vekene", 1)
    -- siste veka skal ikkje betale for meir enn du bad om
    local last = plan.weeks[#plan.weeks]
    ok(last.rank >= 10, "siste veka kjem i mål")

    -- er du der alt, er det ingen plan å lage
    local none = BT.PlanToRank(3, 5, 0)
    ok(none.done, "er du over målet, er det ikkje noko å planleggje")
  end

  -- rank 14 frå ingenting: det skal gå, og det skal ta fleire veker enn folk
  -- håpar. Den gamle modellen vår sa 500 000 i veka for alltid, som var feil.
  do
    local plan = BT.PlanToRank(14, 1, 0)
    ok(not plan.unreachable, "rank 14 er naaeleg")
    ok(#plan.weeks >= 4, "men ikkje på under fire veker (" ..
       #plan.weeks .. ")")
    ok(plan.total > 1000000, "og det kostar millionar til saman")
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
    ok(rate and rate > 0, "det blir ein rate av det")
    S.weekHonor = 0
    BT.PollHonor()
    eq(ChainCharDB.honorSession, 0, "resetet nullstiller i staden for å telje ned")
  end

  -- honor per drap, målt og ikkje gjetta
  do
    S.weekHonor, S.weekKills = 10000, 100
    near(BT.HonorPerKill(), 100, "honor per drap er målt", 0.01)
    S.weekKills = 2
    eq(BT.HonorPerKill(), nil, "to drap er ikkje nok til å seie noko")
  end

  -- og heile tilstanden, slik baren og fana ser han
  do
    S.pvpRank, S.pvpProgress = 4, 0.6
    S.weekHonor, S.weekKills = 30000, 60
    local st = BT.PvPState()
    eq(st.rank, 4, "ranken din")
    ok(st.enoughKills, "nok drap")
    eq(st.met.honor, 22500, "du har nådd den fyrste")
    eq(st.newRank, 5, "så veka endar på rank 5")
    eq(st.short, 15000, "og du manglar 15 000 til neste")
    ok(BT.PvPChunk() ~= nil, "og det blir ei linje for baren")
    -- for få drap skal seiast rett ut, ikkje gøymast
    S.weekKills = 3
    local st2 = BT.PvPState()
    ok(not st2.enoughKills, "for få drap blir merka")
    eq(st2.killsShort, 12, "og det blir sagt kor mange som manglar")
    ok((BT.PvPChunk() or ""):find("kills"), "også på baren")
  end

  -- kommandoen, som er den andre vegen inn
  do
    S.pvpRank, S.pvpProgress = 6, 0.25
    S.weekHonor, S.weekKills = 30000, 42
    ok(pcall(SlashCmdList["CHAIN"], "pvp"), "/chain pvp gaar utan aa falle")
    ok(pcall(SlashCmdList["CHAIN"], "pvp 12"), "og med eit maal")
    eq(ChainCharDB.pvpTarget, 12, "som blir hugsa")
  end
end

print("== baren på level 60 ==")
-- På toppen er det ingen xp igjen å måle, så ein xp-bar er ein bar som aldri
-- meir kjem til å røre seg. Veka sin honor er det einaste som framleis går
-- opp, så det er det baren blir - utan å bli spurd.
do
  local keepLevel, keepRun = S.level, ChainCharDB.run
  ChainCharDB.run = nil
  S.level = 59
  BT.Touch()
  ok(BT.Mode() ~= "honor", "på veg opp er det framleis ein xp-bar")

  S.level = 60
  S.pvpRank, S.pvpProgress = 6, 0.25
  S.weekHonor, S.weekKills = 30000, 40
  BT.Touch()
  eq(BT.Mode(), "honor", "på 60 byter han av seg sjølv")

  local sl = BT.BuildText()
  ok((sl.barLeft or ""):find("honor"), "baren tel honor")
  ok((sl.topLeft or ""):find("%%"), "og overskrifta er ranken din")

  -- Fyllet går frå milepælen du har banka til den du siktar på denne veka,
  -- for det er den einaste strekninga der honoren du tener er verdt noko.
  local keepTarget = ChainCharDB.pvpTarget
  ChainCharDB.pvpTarget = nil
  BT.Touch()
  sl = BT.BuildText()
  local p = BT.PvPState()
  local from = p.met and p.met.honor or 0
  eq(sl.max, p.nextMilestone.honor - from, "utan mål er nemnaren spranget til neste")
  eq(sl.cur, p.honor - from, "og teljaren kor langt inn i det du er")
  ok((sl.barCenter or ""):find("more this week"),
     "midten seier kor mykje du manglar for denne veka")
  ok((sl.barLeft or ""):find("%%"), "og venstre har ein prosent, som på xp-baren")

  -- Har du sett eit mål, er det planen si veke 1 som gjeld - ikkje det
  -- minste spranget. Å sikte på det vesle og stoppe der er korleis ein plan
  -- på fjorten veker stille blir ein på tjue.
  do
    ChainCharDB.pvpTarget = 12
    BT.Touch()
    local goal, short = BT.WeekGoal()
    local plan = BT.PlanToRank(12, p.rank, p.progress)
    eq(goal.honor, plan.weeks[1].honor, "målet er planen si fyrste veke")
    eq(short, goal.honor - p.honor, "og det som manglar er rekna mot det")
    local sl2 = BT.BuildText()
    eq(sl2.max, goal.honor - from, "og baren måler heile det spranget")
    ok((sl2.topRight or ""):find("for "), "overskrifta seier kva det er for")
  end
  ChainCharDB.pvpTarget = keepTarget
  BT.Touch()
  sl = BT.BuildText()

  -- og den slanke andre-baren skal ikkje teikne det same om att
  BT.Refresh()
  ok(not BT.bar.honor:IsShown(),
     "den vesle honor-baren er borte, han ville vore det same to gonger")

  -- for få drap skal seiast, sidan ingenting tel utan dei
  S.weekKills = 3
  BT.Touch()
  ok(table.concat(BT.AllLines(BT.BuildText()), " "):find("more kills"),
     "for få drap blir sagt rett ut")

  -- og du kan slå det av om du vil ha den tomme xp-baren tilbake
  ChainDB.honorMode = false
  ok(BT.Mode() ~= "honor", "det kan skruast av")
  ChainDB.honorMode = nil

  S.level, ChainCharDB.run = keepLevel, keepRun
  S.weekKills = 40
  BT.Touch()
end


print("== loot-loggen ==")
-- Kamploggen ber ingenting om loot. Chat-meldingane gjer det, og dei kjem for
-- heile gruppa - difor er dette den einaste vegen til "kven fekk kva".
--
-- Mønstera blir bygde av klienten sine eigne setningar, ikkje av engelske ord
-- skrivne inn her. Det er heile grunnen til at det virkar på ein klient på
-- kva språk som helst.
do
  ChainDB.loot = {}
  local LINK = "|cffa335ee|Hitem:12345::::::::60:::::|h[Krol Blade]|h|r"
  local LINK2 = "|cff1eff00|Hitem:999::::::::60:::::|h[Grønt Sverd]|h|r"
  S.items[12345] = { name = "Krol Blade", quality = 4, price = 15000 }
  S.items[999] = { name = "Grønt Sverd", quality = 2, price = 500 }
  local lf = BT.lootFrame

  -- deg sjølv
  S.Fire(lf, "CHAT_MSG_LOOT", "You receive loot: " .. LINK .. ".")
  eq(#ChainDB.loot, 1, "ditt eige loot blir logga")
  eq(ChainDB.loot[1].id, 12345, "med rett item")
  eq(ChainDB.loot[1].n, 1, "og eitt av det")
  ok(ChainDB.loot[1].mine, "og merkt som ditt")

  -- og nokon andre i gruppa, som er heile poenget
  S.Fire(lf, "CHAT_MSG_LOOT", "Kompis receives loot: " .. LINK2 .. ".")
  eq(#ChainDB.loot, 2, "andre sitt loot blir òg logga")
  eq(ChainDB.loot[2].who, "Kompis", "med kven som fekk det")
  eq(ChainDB.loot[2].mine, nil, "og det er ikkje ditt")

  -- fleire av same
  S.Fire(lf, "CHAT_MSG_LOOT", "Kompis receives loot: " .. LINK2 .. "x4.")
  eq(ChainDB.loot[3].n, 4, "talet blir lese når det står der")
  -- og "x4"-varianten skal ikkje bli lesen som eit item som heiter noko x4:
  -- det er difor dei fleirtalige mønstera blir prøvde fyrst
  eq(ChainDB.loot[3].id, 999, "og itemet er framleis rett")

  -- ting som ikkje er loot skal ikkje bli det
  local before = #ChainDB.loot
  S.Fire(lf, "CHAT_MSG_LOOT", "Kompis says something about loot")
  eq(#ChainDB.loot, before, "ei linje utan item er ikkje loot")

  -- Mynt, med klienten sine eigne einingsord. Men mynt er ikkje loot slik eit
  -- item er: det dett av nesten kvart lik, og ei linje per plukk gøymer dei
  -- femten grøne inne i fire hundre linjer med "3s 95c". NIT ber det som eitt
  -- tal per instans, og det høyrer til runen, ikkje til loggen.
  eq(BT.ParseCoins("You loot 2 Gold 15 Silver 3 Copper"),
     2 * 10000 + 15 * 100 + 3, "mynt blir rekna om til kopar")
  do
    local rowsBefore = #ChainDB.loot
    ChainCharDB.run = { zone = "The Stockade", start = S.now, xp = 0, k = 0,
                        id = "stock" }
    S.Fire(lf, "CHAT_MSG_MONEY", "You loot 2 Gold 15 Silver 3 Copper")
    eq(#ChainDB.loot, rowsBefore, "og det blir ikkje ei linje i loggen")
    eq(ChainCharDB.run.coin, 2 * 10000 + 15 * 100 + 3, "det legg seg på runen")
    S.Fire(lf, "CHAT_MSG_MONEY", "You loot 45 Silver")
    eq(ChainCharDB.run.coin, 2 * 10000 + 15 * 100 + 3 + 4500, "og summerer seg")
    eq(BT.RunCoin(), ChainCharDB.run.coin, "totalen tel runen du står i")
    ChainCharDB.run = nil
    -- utanfor ein run er det ikkje pengar instansen gav deg
    local loose = BT.RunCoin()
    S.Fire(lf, "CHAT_MSG_MONEY", "You loot 9 Gold")
    eq(BT.RunCoin(), loose, "mynt utanfor ein run tel ikkje med")
    eq(#ChainDB.loot, rowsBefore, "og lagar framleis inga linje")
  end

  -- verdi kjem frå klienten, og "ikkje lasta enno" skal seiast som ukjent og
  -- ikkje som null - ein null i ein pengekolonne er ein påstand
  eq(BT.LootValue(ChainDB.loot[1]), 15000, "verdien kjem frå klienten")
  eq(BT.LootValue({ link = "|Hitem:4242|h[Ukjent]|h", n = 1 }), nil,
     "eit item som ikkje er lasta er ukjent, ikkje gratis")
  eq(BT.LootValue(ChainDB.loot[3]), 500 * 4, "og fleire tel med talet")

  -- summane
  local value, byWho, items, coins, unknown = BT.LootTotals()
  eq(items, 6, "alle gjenstandane er talde (1 + 1 + 4)")
  eq(coins, BT.RunCoin(), "og myntane kjem frå runane, ikkje frå loggen")
  ok(value > 0, "det blir ein sum av det")
  ok(byWho[1] and byWho[1].who, "og ei liste over kven som fekk mest")

  -- Kva det datt frå. Loot-meldinga seier det ikkje - ingenting i henne gjer
  -- det - så dette er kjent for ditt eige loot og blankt for alle andre sitt.
  -- Loot-vindauget namngjev liket som ein GUID, og den einaste staden den
  -- GUID-en nokon gong fekk eit namn er kamploggen då tingen døydde.
  do
    BT.NoteCorpse("Creature-0-1-1-1-731-0001", "Defias Thug")
    S.lootSlots = { "Creature-0-1-1-1-731-0001" }
    BT.NoteLootSource()
    S.Fire(lf, "CHAT_MSG_LOOT", "You receive loot: " .. LINK .. ".")
    eq(ChainDB.loot[#ChainDB.loot].from, "Defias Thug", "kjelda blir med")

    -- og andre sitt loot skal IKKJE få ei gjetta kjelde
    S.Fire(lf, "CHAT_MSG_LOOT", "Kompis receives loot: " .. LINK2 .. ".")
    eq(ChainDB.loot[#ChainDB.loot].from, nil,
       "andre sitt loot har inga kjelde, og blir ikkje gjetta")

    -- ein GUID vi aldri såg døy har vi ikkje noko namn på
    S.lootSlots = { "Creature-0-1-1-1-999-9999" }
    S.units["target"] = nil
    BT.NoteLootSource()
    S.Fire(lf, "CHAT_MSG_LOOT", "You receive loot: " .. LINK .. ".")
    eq(ChainDB.loot[#ChainDB.loot].from, nil, "ukjend lik gjev ingen kjelde")

    -- Mynt har inga kjelde å få lenger, fordi det ikkje er ei linje. Det som
    -- betyr noko er at itemet frå same vindauget framleis får si.
    BT.NoteCorpse("Creature-0-1-1-1-731-0003", "Riverpaw Mystic")
    S.lootSlots = { "Creature-0-1-1-1-731-0003" }
    BT.NoteLootSource()
    local n0 = #ChainDB.loot
    S.Fire(lf, "CHAT_MSG_MONEY", "You loot 16 Copper")
    S.Fire(lf, "CHAT_MSG_LOOT", "You receive loot: " .. LINK2 .. "x3.")
    eq(#ChainDB.loot, n0 + 1, "berre itemet blei ei linje")
    eq(ChainDB.loot[#ChainDB.loot].from, "Riverpaw Mystic", "og det fekk kjelda si")

    -- og ei gammal kjelde skal ikkje henge att på neste lik
    BT.NoteCorpse("Creature-0-1-1-1-731-0002", "Defias Bandit")
    S.lootSlots = { "Creature-0-1-1-1-731-0002" }
    BT.NoteLootSource()
    S.now = S.now + 60
    S.Fire(lf, "CHAT_MSG_LOOT", "You receive loot: " .. LINK .. ".")
    eq(ChainDB.loot[#ChainDB.loot].from, nil,
       "ei gammal kjelde blir ikkje hengande att")
    S.lootSlots = {}
  end

  -- Og dei fire hundre linjene som alt ligg der skal ryddast, ikkje berre
  -- sluttast å lage. Dei blir folda inn i runen dei skjedde i, ved klokka.
  do
    local oldLoot, oldRuns = ChainDB.loot, ChainDB.runs
    local t0 = S.now
    ChainDB.runs = {
      { at = t0, t = 600, zone = "The Stockade", id = "stock", xp = 9000, k = 30 },
      { at = t0 + 1200, t = 600, zone = "The Stockade", id = "stock",
        xp = 9000, k = 30 },
    }
    ChainDB.loot = {
      { at = t0 - 7200, copper = 111 },                       -- før alt
      { at = t0 + 60, copper = 500 },                         -- i fyrste
      { at = t0 + 120, copper = 250 },                        -- i fyrste
      { at = t0 + 900, copper = 77 },                         -- mellom to runs
      { at = t0 + 1300, copper = 1000 },                      -- i andre
      { at = t0 + 1350, id = 12345, link = "x", n = 1 },      -- eit item
    }
    ChainDB.coinFolded, ChainDB.coinLoose = nil, nil
    local moved, loose = BT.FoldCoins()
    eq(#ChainDB.loot, 1, "berre itemet står att i loggen")
    eq(ChainDB.runs[1].coin, 750, "myntane frå fyrste runen hamna der")
    eq(ChainDB.runs[2].coin, 1000, "og frå den andre der")
    eq(moved, 1750, "det som fann ein heim")
    eq(loose, 111 + 77, "og det som ikkje gjorde det")
    eq(ChainDB.coinLoose, 188, "blir lagt til side i staden for å forsvinne")
    eq(BT.RunCoin(), 750 + 1000 + 188, "totalen er alt saman")

    -- og den gjer det berre éin gong
    eq(select(1, BT.FoldCoins()), 0, "og ikkje ein gong til")

    -- historikk-fana skal vise det per run, slik NIT gjer per instans
    BT.Touch()
    BT.ToggleWindow()
    BT.ShowTab("runs")
    do
      local wr, withGold = _G.ChainWindow, 0
      for _, row in ipairs(wr.rows or {}) do
        -- betalingane ligg no i same lista, og dei har gull i same kolonnen;
        -- det er runane vi tel her
        local what = ((row.cells[2]:GetText() or "")
          :gsub("|c%x%x%x%x%x%x%x%x", "")):gsub("|r", "")
        if row:IsShown() and not what:find("^paid") and not what:find("^got back") then
          local g = (row.cells[7]:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", "")
          g = g:gsub("|r", "")
          if g:find("%d") and g ~= "-" then withGold = withGold + 1 end
        end
      end
      eq(withGold, 2, "begge runane viser kva mobbane gav i rått gull")
    end
    BT.ToggleWindow()

    ChainDB.loot, ChainDB.runs = oldLoot, oldRuns
    ChainDB.coinFolded, ChainDB.coinLoose = nil, nil
    BT.Touch()
  end

  -- Mynt skal ikkje runde seg vekk. Femten sølv kom ut som "0g", og ein
  -- kolonne med nullar seier at loggen er øydelagd, ikkje at beløpa er små.
  do
    eq(BT.Coin(1503), "15s 3c", "småpengar blir sagt i sølv og kopar")
    eq(BT.Coin(2 * 10000 + 1500), "2g 15s", "og store i gull og sølv")
    eq(BT.Coin(0), "0c", "og null er null kopar, ikkje null gull")
    eq(BT.Coin(10000), "1g", "eit reint gullbeløp har ingen hale")
  end


  -- Ei rad per lik. Loggen lagrar éi oppføring per ting, som er rett -
  -- eksport og summar vil ha det slik - men ein mob som gav deg ei jakke og
  -- tre tøy er éi hending, og å lese det som to linjer som tilfeldigvis står
  -- ved sida av kvarandre er å lese det feil.
  do
    ChainDB.loot = {}
    BT.NoteCorpse("Creature-0-1-1-1-731-0007", "Riverpaw Taskmaster")
    S.lootSlots = { "Creature-0-1-1-1-731-0007" }
    BT.NoteLootSource()
    S.Fire(lf, "CHAT_MSG_MONEY", "You loot 35 Copper")
    S.Fire(lf, "CHAT_MSG_LOOT", "You receive loot: " .. LINK .. ".")
    S.Fire(lf, "CHAT_MSG_LOOT", "You receive loot: " .. LINK2 .. "x3.")
    eq(#ChainDB.loot, 2, "loggen har to oppføringar - myntane er ikkje ei")

    BT.ShowTab("loot")
    local wg, rows = _G.ChainWindow, {}
    for _, r in ipairs(wg.rows) do
      if r:IsShown() then rows[#rows + 1] = r end
    end
    eq(#rows, 1, "men det blir éi rad")
    local cell = (rows[1].cells[2]:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    ok(cell:find("Krol Blade"), "med gjenstanden")
    ok(cell:find("3x"), "og talet på dei det var fleire av")
    ok(not cell:find("35c"), "og myntane står ikkje der - dei ligg på runen")
    eq((rows[1].cells[3]:GetText() or ""), "4", "og n er alt som fall (1 + 3)")
    local worth = (rows[1].cells[7]:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    eq(worth, BT.Coin(15000 + 1500), "og verdien er summen av heile liket")
    -- og kvaliteten på det beste som fall, som eige felt: sortert på talet,
    -- ikkje på ordet, så epic hamnar over rare og ikkje alfabetisk mellom dei
    local q = (rows[1].cells[4]:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    eq(q, BT.QualityWord(4), "kvaliteten på det beste liket gav")

    -- Tooltipen skal vere klienten sin eigen for gjenstanden - stats, level,
    -- binding, alt ei liste med namn ikkje kan seie - og vår eiga under, ikkje
    -- i staden: resten av det liket gav, kven som tok det og kvar.
    rows[1].__scripts.OnEnter(rows[1])
    local t = S.TipText()
    ok(t:find("%[hyperlink%]"), "vi spør spelet om den ekte tooltipen")
    ok(t:find("Krol Blade"), "og det er den beste gjenstanden vi spør om")
    ok(t:find("picked it up"), "vår eiga står under, ikkje i staden")
    ok(t:find("Shift%-click"), "og den seier korleis du får den i chatten")

    -- shift-klikk legg lenka i det du skriv, slik det verkar elles i spelet
    S.chatLinks = {}
    S.shiftDown = false
    rows[1].__scripts.OnMouseUp(rows[1], "LeftButton")
    eq(#S.chatLinks, 0, "eit vanleg klikk gjer ingenting")
    S.shiftDown = true
    rows[1].__scripts.OnMouseUp(rows[1], "LeftButton")
    eq(#S.chatLinks, 1, "shift-klikk legg den i chatten")
    ok(tostring(S.chatLinks[1]):find("Krol Blade"), "og det er rett gjenstand")
    S.shiftDown = false

    -- og sortering på kvalitet er på talet, ikkje på ordet
    ok(BT.QualityWord(4) ~= nil, "kvaliteten har eit ord klienten eig")
    eq(BT.QualityWord(2), _G.ITEM_QUALITY2_DESC or "Uncommon",
       "og det er klienten sitt, ikkje vårt")

    -- eit anna lik skal ikkje slåast saman med det
    S.now = S.now + 30
    BT.NoteCorpse("Creature-0-1-1-1-731-0008", "Riverpaw Mystic")
    S.lootSlots = { "Creature-0-1-1-1-731-0008" }
    BT.NoteLootSource()
    S.Fire(lf, "CHAT_MSG_LOOT", "You receive loot: " .. LINK2 .. ".")
    BT.ShowTab("loot")
    local n = 0
    for _, r in ipairs(wg.rows) do if r:IsShown() then n = n + 1 end end
    eq(n, 2, "eit anna lik er si eiga rad")

    -- og eit anna menneske si loot heller ikkje, same kor nært i tid
    S.Fire(lf, "CHAT_MSG_LOOT", "Kompis receives loot: " .. LINK2 .. ".")
    BT.ShowTab("loot")
    n = 0
    for _, r in ipairs(wg.rows) do if r:IsShown() then n = n + 1 end end
    eq(n, 3, "og ein annan spelar si loot er si eiga")
    S.lootSlots = {}
  end

  -- fana
  ChainDB.loot = {}
  S.Fire(lf, "CHAT_MSG_LOOT", "You receive loot: " .. LINK .. ".")
  S.now = S.now + 30
  S.Fire(lf, "CHAT_MSG_LOOT", "Kompis receives loot: " .. LINK2 .. ".")
  BT.ShowTab("loot")
  local wl, seen = _G.ChainWindow, {}
  for _, r in ipairs(wl.rows) do
    if r:IsShown() then
      seen[#seen + 1] = (r.cells[2]:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
  end
  ok(table.concat(seen, " "):find("Krol Blade"), "fana viser det")
  ok(table.concat(seen, " "):find("Grønt Sverd"), "og resten òg")

  -- og han kan slåast av
  ChainDB.logLoot = false
  local n = #ChainDB.loot
  S.Fire(lf, "CHAT_MSG_LOOT", "You receive loot: " .. LINK .. ".")
  eq(#ChainDB.loot, n, "av er av")
  ChainDB.logLoot = nil

  BT.ForgetLoot()
  eq(#ChainDB.loot, 0, "og han kan tømmast")
  BT.ShowTab("runs")
end


print("== fps og ping ==")
-- To tal i augekroken. Fargen er heile poenget: eit tal du må samanlikne med
-- ein hugsa terskel er eit tal du les, eit tal som blir oransje er eit tal du
-- legg merke til.
do
  local function plain(t)
    return (t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  end
  local function colourOf(t, which)
    -- fargekoden rett før talet; eininga står i sin eigen dimma bit etterpå
    for col, num in (t or ""):gmatch("(|c%x%x%x%x%x%x%x%x)(%d+)|r") do
      local after = (t or ""):match("|r|c%x%x%x%x%x%x%x%x ?(%a+)|r",
                                    (t or ""):find(col .. num .. "|r", 1, true))
      if after == which then return col end
    end
    return ""
  end

  ChainDB.meter = false
  eq(BT.ToggleMeter(), true, "han kan slåast på")
  local m = BT.meterFrame()
  ok(m and m:IsShown(), "og då står han på skjermen")

  S.fps, S.msHome, S.msWorld = 60, 30, 30
  BT.RefreshMeter()
  local t = m.fs:GetText()
  ok(plain(t):find("60 fps"), "framerata står der")
  ok(plain(t):find("30 ms"), "og latensen")

  -- fargane skal faktisk skifte, og kvar veg
  local greenFps = colourOf(BT.MeterText(), "fps")
  S.fps = 8
  local redFps = colourOf(BT.MeterText(), "fps")
  ok(greenFps ~= "" and greenFps ~= redFps,
     "låg framerate får ein annan farge enn høg")

  S.fps = 60
  local greenMs = colourOf(BT.MeterText(), "ms")
  S.msWorld, S.msHome = 800, 800
  local redMs = colourOf(BT.MeterText(), "ms")
  ok(greenMs ~= "" and greenMs ~= redMs, "og høg latens ein annan enn låg")
  ok(greenFps ~= redMs, "dei to skalaene går kvar sin veg")

  -- world er den som avgjer om ein spell går av; home er chat. Den største av
  -- dei to er den du faktisk kjenner.
  S.msHome, S.msWorld = 40, 300
  local _, ms = BT.MeterStats()
  eq(ms, 300, "den verste av dei to er den som blir vist")

  -- kvar for seg av og på
  ChainDB.meterFPS = false
  ok(not plain(BT.MeterText()):find("fps"), "framerata kan skruast av åleine")
  ok(plain(BT.MeterText()):find("ms"), "medan latensen står att")
  ChainDB.meterFPS = nil

  -- og heile greia av
  eq(BT.ToggleMeter(), false, "han kan slåast av")
  BT.RefreshMeter()
  ok(not m:IsShown(), "og då er han borte")

  -- Han skal henge under kartet til du seier noko anna, og han skal ikkje
  -- hoppe medan du dreg: oppdateringa kvart sekund ankra han på nytt midt i
  -- draget, som er nøyaktig det same som gjorde nærleik-lista umogleg å
  -- plassere.
  ChainDB.meter, ChainDB.meterPos = true, nil
  ChainDB.meterLocked = nil
  BT.RefreshMeter()
  do
    local pt = m.__points[#m.__points]
    eq(pt.rel, _G.Minimap, "han heng under kartet som standard")
    eq(pt.point, "TOP", "med toppen sin mot botnen av det")
  end

  m.__scripts.OnDragStart(m)
  ok(BT.MeterDragging(), "han veit at han er i eit drag")
  m.__left, m.__top = 300, 700
  local before = #m.__points
  S.fps = 12
  BT.RefreshMeter()
  eq(#m.__points, before, "oppdateringa ankrar han ikkje på nytt medan du held")
  m.__scripts.OnDragStop(m)
  ok(not BT.MeterDragging(), "draget er slutt")
  eq(ChainDB.meterPos.x, 300 * m:GetScale(), "posisjonen er i skjermpikslar")

  -- og låst er låst
  ChainDB.meterLocked = true
  m.__scripts.OnDragStart(m)
  ok(not BT.MeterDragging(), "låst lar seg ikkje dra")
  ChainDB.meterLocked = nil

  ChainDB.meterPos = nil
  ChainDB.meter = false
  S.fps = 60
  BT.RefreshMeter()
end


print("== kven som er der ute ==")
-- To ting som berre gjev meining saman: ei liste over kven du vil vite om,
-- og sjølve vaktinga. Deteksjonen er ikkje smart og treng ikkje vere det -
-- klienten fortel deg om ein spelar i det eit nameplate dukkar opp, i det
-- musa strauk over ein, i det du targetar ein, og kvar gong ein castar noko
-- innanfor combat-loggen.
do
  ChainDB.watchEnemies = true
  ChainDB.enemies, ChainDB.kos, ChainDB.kosGuilds = {}, {}, {}
  ChainDB.enemyQuiet = {}
  local ef = BT.enemyFrame

  -- eit nameplate: alt verdt å vite er lesbart akkurat då og ingen annan stad
  S.units["nameplate1"] = { name = "Gankar-Testrealm", level = 60, class = "ROGUE",
                            guild = "Bad Bois", hostile = true }
  S.Fire(ef, "NAME_PLATE_UNIT_ADDED", "nameplate1")
  local seen = ChainDB.enemies["Gankar"]
  ok(seen ~= nil, "spelaren blir sett")
  eq(seen and seen.level, 60, "med level")
  eq(seen and seen.class, "ROGUE", "og klasse")
  eq(seen and seen.guild, "Bad Bois", "og guild")

  -- ein på di eiga side er ikkje interessant
  S.units["nameplate2"] = { name = "Venn-Testrealm", level = 55, hostile = false }
  S.Fire(ef, "NAME_PLATE_UNIT_ADDED", "nameplate2")
  eq(ChainDB.enemies["Venn"], nil, "vennlege blir ikkje plukka opp")

  -- combat-loggen rekk lenger enn noko nameplate, men veit mindre - og skal
  -- ikkje viske ut det nameplatet fortalde oss
  BT.NoteCombatLogUnit("Player-4-0001", "Gankar-Testrealm", 0x440)
  eq(ChainDB.enemies["Gankar"].level, 60, "combat-loggen slettar ikkje levelen")
  BT.NoteCombatLogUnit("Player-4-0002", "Fjern-Testrealm", 0x440)
  ok(ChainDB.enemies["Fjern"] ~= nil, "ein som castar langt unna blir sett")
  BT.NoteCombatLogUnit("Creature-0-1-1-1-99", "Ulv", 0x440)
  eq(ChainDB.enemies["Ulv"], nil, "mobs er ikkje spelarar")
  BT.NoteCombatLogUnit("Player-4-0003", "Snill-Testrealm", 0x400)   -- ikkje fiendtleg

  -- Ein som snik seg. Dette blei lese berre av auraene på ein unit klienten
  -- alt teikna - eit nameplate, targetet ditt - altså måtte du kunne SJÅ han
  -- før vi fortalde deg at du ikkje kunne. Spy les det av kamploggen, som
  -- kunngjer auraen i det den landar, to rom unna. Det er det varselet som er
  -- verdt noko.
  do
    local ab = BT.alertFrame and BT.alertFrame()
    if ab then ab:Hide() end
    ChainDB.stealthQuiet = {}
    S.guids["Player-4-0050"] = { class = "ROGUE", race = "Human", name = "Snik" }
    BT.NoteCombatLogUnit("Player-4-0050", "Snik-Testrealm", 0x440,
                         1784, "SPELL_AURA_APPLIED", "Stealth", true)
    ok(ChainDB.enemies["Snik"], "han blir sett")
    eq(ChainDB.enemies["Snik"].stealth, true, "og merkt som snikande")
    ab = BT.alertFrame and BT.alertFrame()
    ok(ab and ab:IsShown(), "og varselet kjem opp")
    ok(ab and (ab.head:GetText() or ""):find("Stealth"),
       "og seier kva slags varsel")

    -- id-en er svaret som ikkje kan vere feil: namnet er ulikt på kvar
    -- klient, og tabellen var fem engelske ord - altså slo den ikkje til i
    -- det heile på ein tysk klient
    ok(BT.StealthSpell(5215, nil), "Prowl blir kjent att på id åleine")
    ok(BT.StealthSpell(nil, "Stealth"), "og på namn når vi har namnet")
    ok(not BT.StealthSpell(1111, "Frostbolt"), "og ein vanleg spell gjer ikkje")

    -- og han som svingar er han du kan sjå, kva enn den siste auraen sa
    BT.NoteCombatLogUnit("Player-4-0050", "Snik-Testrealm", 0x440,
                         nil, "SWING_DAMAGE", nil, true)
    eq(ChainDB.enemies["Snik"].stealth, false, "eit slag tek han ut av snikinga")

    -- og auraen som fell av gjer det same
    BT.NoteCombatLogUnit("Player-4-0050", "Snik-Testrealm", 0x440,
                         1784, "SPELL_AURA_APPLIED", "Stealth", true)
    eq(ChainDB.enemies["Snik"].stealth, true, "han snik seg att")
    BT.NoteCombatLogUnit("Player-4-0050", "Snik-Testrealm", 0x440,
                         1784, "SPELL_AURA_REMOVED", "Stealth", true)
    eq(ChainDB.enemies["Snik"].stealth, false, "og auraen som fell av tel òg")

    -- det som blir gjort MOT nokon seier ingenting om dei: berre kjelda
    BT.NoteCombatLogUnit("Player-4-0051", "Offer-Testrealm", 0x440,
                         1784, "SPELL_AURA_APPLIED", "Stealth")
    eq(ChainDB.enemies["Offer"].stealth, nil,
       "målet for ein spell blir ikkje merkt som snikande")
    if ab then ab:Hide() end
    ChainDB.stealthQuiet = {}
    -- rydd etter oss: lista under blir målt i høgd, og to ekstra namn i ho
    -- er nok til å gjere den målinga til noko anna
    ChainDB.enemies["Snik"], ChainDB.enemies["Offer"] = nil, nil
  end

  -- Kamploggen ber ingen klasse, og difor sat alle som blei funne der som eit
  -- grått namn med spørsmålsteikn. GUID-en er nok til å spørje klienten,
  -- som veit klasse og rase for alle han har sett. Level veit han ikkje, og
  -- det skal stå som ukjent i staden for å bli gjetta.
  S.guids["Player-4-0009"] = { class = "ROGUE", race = "Orc", name = "Gankar2" }
  BT.NoteCombatLogUnit("Player-4-0009", "Gankar2-Testrealm", 0x440)
  do
    local found = ChainDB.enemies["Gankar2"]
    ok(found ~= nil, "han blei notert")
    eq(found and found.class, "ROGUE", "og klassa kom frå GUID-en")
    eq(found and found.race, "Orc", "rasa likeeins")
    eq(found and found.level, nil, "men level blir ikkje gjetta")
    eq(BT.ClassLabel("ROGUE"), "Rogue", "og klassa har eit namn for rada")
    eq(BT.ClassLabel(nil), "?", "ukjent klasse seier det")
  end

  -- Level for motstandarar kan berre kome frå å ha sett dei. /who returnerer
  -- berre di eiga side, så eit oppslag kunne aldri fylt inn ein einaste ein -
  -- og ein knapp som ser ut som ein funksjon og stille ikkje gjer noko er
  -- verre enn ingen knapp. Difor står det "??" og tooltippen seier kvifor.
  do
    ChainDB.enemies = ChainDB.enemies or {}
    BT.NoteEnemy("Ukjendlvl", { class = "MAGE", how = "combat log" })
    eq(ChainDB.enemies["Ukjendlvl"].level, nil, "ingen level frå kamploggen")
    eq(BT.LookupPlayer, nil, "og ingen /who-knapp som lovar noko anna")
  end

  -- Det du derimot kan gjere er å seie frå til di eiga side, med koordinatar.
  do
    ChainDB.sightQuiet = {}
    S.said = {}
    S.zone = "Scarlet Monastery"
    S.mapPos = { 0.47, 0.19 }
    BT.NoteEnemy("Roparen", { level = 45, class = "WARRIOR", guild = "Era Enjoyers" })
    local e = ChainDB.enemies["Roparen"]

    local txt = BT.SightingText(e)
    ok(txt:find("Roparen"), "meldinga har namnet")
    ok(txt:find("45"), "og levelen")
    ok(txt:find("Warrior"), "og klassa")
    ok(txt:find("Era Enjoyers"), "og guilden")
    ok(txt:find("47, 19"), "og kvar du står (" .. txt .. ")")

    -- kanalen fylgjer kven du faktisk er saman med
    local keepParty = S.party
    S.party = { { name = "Kompis", lvl = 60 } }
    S.inRaid = false
    eq(BT.SightChannel(), "PARTY", "i gruppe går det til party")
    S.inRaid = true
    eq(BT.SightChannel(), "RAID", "i raid til raid")
    S.inRaid, S.party = false, {}
    local keepGuild = S.inGuild
    S.inGuild = true
    eq(BT.SightChannel(), "GUILD", "aleine, men i guild, til guilden")
    S.inGuild = false
    eq(BT.SightChannel(), "SAY", "og heilt aleine til say")

    local said, chan = BT.AnnounceSighting(e, nil, true)
    ok(said ~= nil, "meldinga blir sendt")
    eq(chan, "SAY", "på den kanalen som passar")
    ok(S.said[#S.said] and S.said[#S.said]:find("Roparen"),
       "og klienten fekk henne (" .. tostring(S.said[#S.said]) .. ")")
    S.party, S.inGuild = keepParty, keepGuild

    -- same mann om att skal ikkje fylle party-chatten
    eq(BT.AnnounceSighting(e), nil, "same mann med ein gong igjen blir kutta")
  end

  -- Stealth: eige varsel, midt på skjermen. Det er den eine observasjonen der
  -- det å vite er heile fordelen - ein rogue du har sett er ein rogue som har
  -- mista opninga.
  do
    ChainDB.stealthQuiet = {}
    S.units["nameplate7"] = { name = "Snikar-Testrealm", level = 60,
                              class = "ROGUE", hostile = true }
    S.auras["nameplate7"] = { "Stealth" }
    BT.NoteUnit("nameplate7", "nameplate")
    local e = ChainDB.enemies["Snikar"]
    ok(e and e.stealth, "vi ser at han er stealtha")
    local sb = BT.alertFrame()
    ok(sb and sb:IsShown(), "og det kjem eit varsel midt på skjermen")
    ok((sb.head:GetText() or ""):find("Stealthed"), "som seier kva det er")
    -- og stealth får sitt eige ikon, ikkje klasseringen: det som betyr noko
    -- med ein rogue du ikkje ser er at du ikkje ser han
    ok((sb.icon.__tex or ""):find("Stealth"),
       "med stealth-ikonet (" .. tostring(sb.icon.__tex) .. ")")
    ok((sb.name:GetText() or ""):find("Snikar"), "og kven det er")

    -- og han skal ikkje skrike kvar gong same mannen dukkar opp
    sb:Hide()
    BT.NoteUnit("nameplate7", "nameplate")
    ok(not sb:IsShown(), "same mann om att gjev ikkje nytt varsel med ein gong")

    -- Å dra lista rundt: ho hoppa, fordi refresh-tikken re-ankra ramma midt i
    -- draget. Og radene dekkjer nesten heile flata, så det einaste du kunne ta
    -- tak i var ein tynn stripe av bakgrunn.
    do
      ChainDB.watchEnemies, ChainDB.nearbyList = true, true
      ChainDB.nearbyLocked = nil
      BT.NoteEnemy("Draaen", { level = 60, class = "MAGE" })
      BT.RefreshNearby()
      local nb = _G.ChainNearby
      local r1 = nb.rows[1]
      ok(r1.__scripts.OnDragStart ~= nil, "du kan ta tak i sjølve rada")

      r1.__scripts.OnDragStart(r1)
      ok(nb.__moving, "og då flyttar heile lista seg")
      ok(BT.NearbyDragging(), "ho veit at ho er i eit drag")

      -- brukaren dreg henne bortover, og tikken går medan han held
      nb.__left, nb.__top = 700, 500
      local beforeH = nb:GetHeight()
      local p = nb.__points[#nb.__points]
      local px, py = p.x, p.y
      BT.NoteEnemy("Enda1", { level = 20 })
      BT.NoteEnemy("Enda2", { level = 21 })
      BT.RefreshNearby()
      local q = nb.__points[#nb.__points]
      eq(q.x, px, "tikken flyttar henne ikkje medan du held henne")
      eq(q.y, py, "verken vassrett eller loddrett")
      eq(nb:GetHeight(), beforeH, "og ho veks ikkje under fingeren din")

      -- slepp, og då skal ho hugse kvar du la henne
      r1.__scripts.OnDragStop(r1)
      ok(not BT.NearbyDragging(), "draget er slutt")
      -- lagra i skjermen sine einingar, ikkje i ramma sine: ei skalert ramme
      -- les sin eigen GetLeft i sine eigne einingar, og ankeret mot UIParent
      -- er i skjermen sine. Å blande dei to er akkurat feilen som får boksen
      -- til å hoppe når du skrur opp storleiken.
      eq(ChainDB.nearbyPos.x, 700 * nb:GetScale(),
         "og posisjonen er lagra i skjermen sine einingar")

      -- Rundturen, som er det som faktisk braut: legg henne ein stad, lagre,
      -- ankre på nytt, og ho skal lande på same staden på SKJERMEN. GetLeft
      -- svarar i ramma sine einingar og ein SetPoint-offset blir lese i dei
      -- same - men dei to er berre same tal så lenge skalaen er 1. Den gamle
      -- testen såg berre på lagringa, og difor gjekk dette rett forbi han.
      do
        BT.SetNearbyScale(1.15)
        nb.__left, nb.__top = 700, 500
        r1.__scripts.OnDragStart(r1)
        r1.__scripts.OnDragStop(r1)
        local savedX, savedY = ChainDB.nearbyPos.x, ChainDB.nearbyPos.y
        near(savedX, 700 * 1.15, "lagra i skjermpikslar", 0.01)

        -- la ramma finne plassen sin frå ankeret i staden for frå testen
        nb.__left, nb.__top = nil, nil
        BT.RefreshNearby()
        local pt = nb.__points[#nb.__points]
        near(pt.x * nb:GetScale(), savedX,
             "og ho kjem tilbake til same skjermplass", 0.01)
        near(pt.y * nb:GetScale(), savedY, "både vassrett og loddrett", 0.01)

        -- og å skru opp storleiken skal ikkje flytte henne
        BT.SetNearbyScale(1.5)
        local pt2 = nb.__points[#nb.__points]
        near(pt2.x * nb:GetScale(), savedX,
             "større boks står på same staden", 0.01)

        ChainDB.nearbyScale = nil
        nb.__left, nb.__top = 700, 500
        BT.RefreshNearby()
      end

      -- og no skal tikken få lov igjen
      BT.RefreshNearby()
      ok(nb:GetHeight() ~= beforeH, "etterpå får ho vekse som normalt")

      -- låst betyr låst
      ChainDB.nearbyLocked = true
      nb.__moving = false
      r1.__scripts.OnDragStart(r1)
      ok(not nb.__moving, "låst lar seg ikkje dra")
      ChainDB.nearbyLocked = nil

        -- Å plassere lista er umogleg så lenge ho berre er på skjermen når
      -- nokon er i nærleiken: du dreg i henne, den siste blir forelda, og ho
      -- forsvinn midt i flyttinga.
      do
        ChainDB.enemies = {}
        ChainDB.nearbyLocked = true
        BT.RefreshNearby()
        local nb6 = _G.ChainNearby
        ok(not nb6:IsShown(), "tom liste er borte til vanleg")

        ok(BT.PlaceNearby(true), "men plasseringsmodus slår henne på")
        ok(nb6:IsShown(), "og då står ho der sjølv om ingen er i nærleiken")
        eq(ChainDB.nearbyLocked, nil, "og ho er låst opp, elles kan du ikkje dra")
        ok((nb6.title:GetText() or ""):find("drag me"), "og ho seier kva du skal gjere")
        -- fylt ut med døme, så du ser breidda og radtalet du faktisk vel
        local filled = 0
        for _, r in ipairs(nb6.rows) do if r:IsShown() then filled = filled + 1 end end
        eq(filled, 8, "og er fylt ut med døme")

        -- og ho blir ståande medan du held på
        BT.RefreshNearby()
        ok(nb6:IsShown(), "ho blir ståande gjennom oppdateringar")

        -- ferdig
        BT.PlaceNearby(false)
        ok(not nb6:IsShown(), "og forsvinn igjen når du er ferdig")

        -- har ho hamna utanfor skjermen, kjem ho heim att - det er vegen
        -- tilbake når du ikkje kan sjå henne for å høgreklikke
        ChainDB.nearbyPos = { x = 99999, y = 99999 }
        BT.PlaceNearby(true)
        eq(ChainDB.nearbyPos, nil, "ei liste utanfor skjermen kjem heim")
        BT.PlaceNearby(false)
        ChainDB.nearbyLocked = nil
      end

      -- Same for varselet: eit varsel du berre ser i seks sekund når nokon
      -- tilfeldigvis går forbi er eit varsel du ikkje kan plassere.
      do
        ok(BT.PlaceAlert(true), "varselet kan haldast på skjermen")
        local ab = BT.alertFrame()
        ok(ab:IsShown(), "og då står det der")
        ok((ab.head:GetText() or ""):find("right%-click"), "med beskjed om kva du gjer")
        -- menyen er delt mellom lista og varselet, og lista si oppdatering
        -- lukka han kvar tikk uansett kva han stod open på - difor rakk du
        -- aldri fram til "done"
        ChainDB.enemies, ChainDB.nearbyList = {}, false
        BT.AlertMenu()
        local mn = _G.ChainNearbyMenu
        ok(mn:IsShown(), "menyen er oppe")
        BT.RefreshNearby()
        ok(mn:IsShown(), "og lista si oppdatering lukkar han ikkje")

        -- eit klikk utanfor menyen legg han vekk, slik alle andre menyar i
        -- spelet gjer. Ein meny som blir ståande les som om han har hengt seg.
        ok(mn.closer ~= nil and mn.closer:IsShown(),
           "med menyen oppe ligg det eit klikkfelt over resten av skjermen")
        mn.closer.__scripts.OnMouseDown(mn.closer)
        ok(not mn:IsShown(), "og eit klikk der lukkar menyen")
        ok(not mn.closer:IsShown(), "og klikkfeltet er borte med han")

        -- Klikkfeltet held på at klikket landar hos oss og ikkje på ei anna
        -- ramme over heile skjermen, og det kan ein ikkje vere sikker på. So
        -- menyen gir opp av seg sjølv når peikaren har gått frå han.
        BT.AlertMenu()
        ok(mn:IsShown(), "menyen er oppe igjen")
        S.mouseOver = mn
        mn.__scripts.OnUpdate(mn, 30)
        ok(mn:IsShown(), "han står så lenge peikaren er på han")
        S.mouseOver = nil
        mn.__scripts.OnUpdate(mn, 2)
        ok(mn:IsShown(), "og eit par sekund etter at han gjekk")
        mn.__scripts.OnUpdate(mn, 4)
        ok(not mn:IsShown(), "men ikkje fem")

        -- og bed du om han att på det same, er det du som legg han vekk
        BT.AlertMenu()
        ok(mn:IsShown(), "opp att")
        BT.AlertMenu()
        ok(not mn:IsShown(), "og eit trykk til på same staden lukkar han")

        BT.AlertMenu()
        ChainDB.nearbyList = true
        mn:Hide()
        -- det skal ikkje forsvinne av seg sjølv medan du held på
        ab.__scripts.OnUpdate(ab, 30)
        ok(ab:IsShown(), "og det forsvinn ikkje under fingeren din")
        BT.PlaceAlert(false)
        ok(not ab:IsShown(), "ferdig, og det er borte")

        -- utanfor skjermen kjem det heim att
        ChainDB.alertPos = { x = 99999, y = 99999 }
        BT.PlaceAlert(true)
        eq(ChainDB.alertPos, nil, "eit varsel utanfor skjermen kjem heim")
        BT.PlaceAlert(false)
      end

      -- Ei liste som berre finst medan nokon er i nærleiken er ei liste du
      -- ikkje kan sjå på: ein tom skjerm og eit øydelagt addon ser heilt like
      -- ut, og du finn ut kva det var når ein rogue alt er oppå deg.
      do
        S.inCombat = false
        ChainDB.enemies = {}
        ChainDB.nearbyAlways = nil
        BT.RefreshNearby()
        local nb6 = _G.ChainNearby
        ok(not nb6:IsShown(), "utan nokon i nærleiken er ho borte som før")

        BT.ToggleNearbyAlways(true)
        ok(nb6:IsShown(), "men slår du det på, står ho der")
        -- Tom seier ho kva ho er, ikkje kva ho ikkje har. "nobody about" er
        -- svar på eit spørsmål ingen stilte.
        ok((nb6.title:GetText() or ""):find("Enemy tracker"),
           "tom står namnet der, ikkje '0 nearby' og ikkje 'nobody about'")
        ok(not (nb6.title:GetText() or ""):find("nobody"),
           "og ikkje eit ord om kven som ikkje er der")

        -- og ein veg inn til resten: lista er eit hjørne av Enemies-fana
        ok(nb6.open ~= nil, "det er ein knapp i toppen")
        BT.ShowTab("runs")
        nb6.open.__scripts.OnClick(nb6.open)
        eq(BT.WindowMode and BT.WindowMode(), "enemies",
           "og han tek deg til Enemies-fana")
        local headOnly = nb6:GetHeight()

        -- og ho veks når nokon dukkar opp
        BT.NoteEnemy("Nykomar", { level = 40, class = "MAGE" })
        BT.RefreshNearby()
        ok(nb6:GetHeight() > headOnly, "og veks når nokon dukkar opp")
        ok((nb6.title:GetText() or ""):find("1 nearby"), "og tel dei")

        -- Dra-merket høyrer til den tilstanden der du faktisk kan dra. Det
        -- stod på den låste, som er akkurat feil veg.
        ChainDB.nearbyLocked = nil
        BT.RefreshNearby()
        ok((nb6.title:GetText() or ""):find("drag me"),
           "ulåst seier at du kan dra henne")
        BT.ToggleNearbyLock()
        ok(not (nb6.title:GetText() or ""):find("drag me"),
           "og låst seier ingenting - du har alt bestemt deg")
        ok(not (nb6.title:GetText() or ""):find("locked"),
           "heller ikkje ordet 'locked'")
        ChainDB.nearbyLocked = nil
        BT.ToggleNearbyAlways(false)
        ChainDB.enemies = {}
        BT.RefreshNearby()
      end

      -- Varselet sjølv skal og kunne klikkast. Det er der auget ditt er i det
      -- augeblinket, og å måtte finne fram til lista i staden er akkurat den
      -- ekstra sekundet ein rogue treng.
      do
        S.inCombat = false
        ChainDB.enemies = {}
        BT.AddKOS("Zanza")
        BT.NoteEnemy("Zanza", { level = 60, class = "ROGUE" })
        local ab2 = BT.alertFrame()
        ok(ab2.target ~= nil, "varselet har ein secure knapp over seg")
        eq(ab2.target:GetAttribute("macrotext1"), "/targetexact Zanza",
           "og den peikar på den varselet ropar om")
        eq(ab2.target:ClicksFor(), "AnyDown,AnyUp",
           "meld på for både ned og opp, elles gjer knappen ingenting")
        -- og han peikar seg sjølv i det du klikkar, same kva siste
        -- oppfrisking rakk
        ab2.target:SetAttribute("macrotext1", nil)
        ab2.target.__scripts.PreClick(ab2.target)
        eq(ab2.target:GetAttribute("macrotext1"), "/targetexact Zanza",
           "og peikar seg sjølv på veg inn")
        ok((ab2.hint:GetText() or ""):find("click to target"),
           "og det står kva eit klikk gjer")

        -- I kamp er attributtet fryst. Eit sett frå før verkar framleis, så
        -- knappen er ikkje daud - han peikar berre på den han peika på. Å
        -- seie kven er det einaste ærlege: eit varsel som ropar eitt namn
        -- medan klikket targetar eit anna er verre enn eitt som innrømmer det.
        S.inCombat = true
        BT.AddKOS("Ocoka")
        BT.NoteEnemy("Ocoka", { level = 34, class = "SHAMAN" })
        eq(ab2.target:GetAttribute("macrotext1"), "/targetexact Zanza",
           "i kamp blir makroen ståande")
        ok((ab2.hint:GetText() or ""):find("targets Zanza"),
           "og varselet seier kven klikket faktisk tek")

        -- ute av kampen tek det att med det same, ikkje ved neste tikk
        S.inCombat = false
        BT.CombatEnded()
        eq(ab2.target:GetAttribute("macrotext1"), "/targetexact Ocoka",
           "etter kampen peikar det på rett person")
        BT.RemoveKOS("Zanza") BT.RemoveKOS("Ocoka")
        ab2:Hide()
      end

      -- Targeting er protected: TargetUnit kan ikkje kallast frå ein addon i
      -- det heile, heller ikkje utanfor kamp. Einaste vegen er at sjølve
      -- klikket køyrer ein /target-makro på ein secure knapp.
      do
        S.inCombat = false
        ChainDB.enemies = {}
        BT.NoteEnemy("Maal", { level = 40, class = "HUNTER" })
        BT.RefreshNearby()
        local nb5 = _G.ChainNearby
        local r = nb5.rows[1]
        eq(r:GetAttribute("type1"), "macro", "rada er ein makro-knapp")
        -- Ein secure knapp som berre er meld på for "LeftButtonUp" køyrer
        -- ikkje handlinga i det heile på denne klienten. Spy har den linja i
        -- kjeldekoda si med eit kommenteringsteikn framfor og denne under.
        eq(r:ClicksFor(), "AnyDown,AnyUp",
           "og meld på for både ned og opp, elles gjer han ingenting")
        eq(r:GetAttribute("macrotext1"), "/targetexact Maal",
           "som targetar den som står der")

        -- i kamp er attributta fryste, så lista ventar i staden for å peike
        -- klikket på feil person
        S.inCombat = true
        BT.NoteEnemy("Ny I Kamp", { level = 50 })
        BT.RefreshNearby()
        eq(r:GetAttribute("macrotext1"), "/targetexact Maal",
           "i kamp blir klikket ståande der det var")
        ok((nb5.title:GetText() or ""):find("held"),
           "og lista seier frå at ho held igjen")

        -- ute av kamp igjen tek ho att
        S.inCombat = false
        BT.RefreshNearby()
        local names = {}
        for _, row in ipairs(nb5.rows) do
          if type(row.rec) == "table" then names[row.rec.name] = row end
        end
        ok(names["Ny I Kamp"] ~= nil, "etter kampen er den nye der")
        eq(names["Ny I Kamp"]:GetAttribute("macrotext1"), "/targetexact Ny I Kamp",
           "og klikket peikar på han")

        -- Klikket peikar seg sjølv i det du klikkar, ikkje berre ved neste
        -- oppfrisking: rada under peikaren er den du vil ha.
        names["Maal"]:SetAttribute("macrotext1", nil)
        names["Maal"].armedFor = nil
        names["Maal"].__scripts.PreClick(names["Maal"])
        eq(names["Maal"]:GetAttribute("macrotext1"), "/targetexact Maal",
           "klikket peikar seg sjølv på veg inn")

        -- shift targetar OG merkar, sidan den sikre delen køyrer uansett
        ChainDB.kos = {}
        S.shiftDown = true
        names["Maal"].__scripts.PostClick(names["Maal"], "LeftButton", true)
        eq(BT.IsKOS("Maal"), nil,
           "nedtrykket gjer ingenting - klikket kjem to gonger")
        names["Maal"].__scripts.PostClick(names["Maal"], "LeftButton", false)
        S.shiftDown = false
        eq(select(1, BT.IsKOS("Maal")), "named", "shift-klikk merkar han òg")

        -- og eit vanleg venstreklikk merkar ikkje: det berre targetar
        ChainDB.kos = {}
        names["Maal"].__scripts.PostClick(names["Maal"], "LeftButton", false)
        eq(BT.IsKOS("Maal"), nil, "vanleg klikk merkar ikkje")
      end

      -- Dei merka skal stå øvst. Lista blir kutta ved eit tal rader, så
      -- rekkjefylgja avgjer kven du aldri ser - og at ein du har merka fell
      -- av botnen fordi tre framande gjekk forbi er den eine feilen denne
      -- lista ikkje har råd til.
      do
        ChainDB.enemies, ChainDB.kos, ChainDB.kosGuilds = {}, {}, {}
        BT.NoteEnemy("Gammalmerka", { level = 40 })
        BT.AddKOS("Gammalmerka")
        S.now = S.now + 5
        BT.NoteEnemy("Fersk1", { level = 20 })
        S.now = S.now + 1
        BT.NoteEnemy("Fersk2", { level = 21 })
        local list = BT.Nearby(600)
        eq(list[1].name, "Gammalmerka", "den merka står øvst")
        eq(list[2].name, "Fersk2", "og resten etter kor nyleg dei er sett")

        -- og ein merka gjennom guilden likeeins
        BT.NoteEnemy("Guildmann", { level = 30, guild = "Bad Bois" })
        BT.AddKOSGuild("Bad Bois")
        S.now = S.now + 10
        BT.NoteEnemy("Heilt Fersk", { level = 22 })
        local l2 = BT.Nearby(600)
        ok(l2[1].name == "Gammalmerka" or l2[1].name == "Guildmann",
           "begge dei merka kjem før den ferskaste")
        ok(l2[2].name == "Gammalmerka" or l2[2].name == "Guildmann",
           "og dei tek dei to øvste plassane")
        ChainDB.kos, ChainDB.kosGuilds = {}, {}
      end

      -- Kor lenge dei blir liggjande etter at du slutta å sjå dei
      do
        ChainDB.enemies = {}
        BT.SetNearbySeconds(30)
        eq(BT.NearbySeconds(), 30, "du kan setje kor lenge")
        BT.NoteEnemy("Forsvinn", { level = 10 })
        eq(#BT.Nearby(), 1, "han er der no")
        S.now = S.now + 40
        eq(#BT.Nearby(), 0, "og borte etter tretti sekund")
        BT.SetNearbySeconds(600)
        eq(#BT.Nearby(), 1, "set du lenger, er han der igjen")
        BT.SetNearbySeconds(1)
        eq(BT.NearbySeconds(), 10, "og det finst eit golv")
        BT.SetNearbySeconds(99999)
        eq(BT.NearbySeconds(), 1800, "og eit tak")
        ChainDB.nearbySeconds = nil
      end

      -- Ei evne set eit golv under nokon du aldri har sett: ein rang kan ikkje
      -- kastast under det levelet han blir lært på. Det er eit golv og ikkje
      -- meir - ein level 60 som kastar Rank 1 les framleis som "4+" - så det
      -- blir lagra som ei gjetting og vist med "+".
      do
        ChainDB.enemies = {}
        _G.Spy_AbilityList = {
          [1111] = { level = 34, class = "MAGE" },
          [2222] = { level = 45, class = "MAGE" },
          [3333] = { level = 12, class = "MAGE" },
        }
        ok(BT.HasAbilityData(), "vi ser tabellen når han er der")
        BT.NoteCombatLogUnit("Player-4-0101", "Kastar-Testrealm", 0x440, 1111)
        local e = ChainDB.enemies["Kastar"]
        eq(e.level, 34, "evna set eit golv")
        ok(e.levelGuess, "og det er merkt som ei gjetting")
        eq(e.class, "MAGE", "klassa kjem med på kjøpet")

        -- eit høgare golv vinn
        BT.NoteCombatLogUnit("Player-4-0101", "Kastar-Testrealm", 0x440, 2222)
        eq(ChainDB.enemies["Kastar"].level, 45, "eit høgare golv vinn")
        -- eit lågare gjer ikkje
        BT.NoteCombatLogUnit("Player-4-0101", "Kastar-Testrealm", 0x440, 3333)
        eq(ChainDB.enemies["Kastar"].level, 45, "og eit lågare rører det ikkje")

        -- men å sjå dei sjølv avgjer, uansett kva evna sa
        BT.NoteEnemy("Kastar-Testrealm", { level = 38 })
        eq(ChainDB.enemies["Kastar"].level, 38, "eit sett level slår gjettinga")
        eq(ChainDB.enemies["Kastar"].levelGuess, nil, "og er ikkje lenger gjetta")
        -- og då skal ei evne ikkje få heve det igjen
        BT.NoteCombatLogUnit("Player-4-0101", "Kastar-Testrealm", 0x440, 2222)
        eq(ChainDB.enemies["Kastar"].level, 38, "evna overstyrer ikkje det du såg")

        -- og "+" skal stå på rada
        BT.NoteCombatLogUnit("Player-4-0102", "Gjetta-Testrealm", 0x440, 2222)
        BT.RefreshNearby()
        local nb3, found = _G.ChainNearby, nil
        for _, r in ipairs(nb3.rows) do
          if type(r.rec) == "table" and r.rec.name == "Gjetta" then found = r end
        end
        ok(found and (found.right:GetText() or ""):find("45%+"),
           "og rada seier 45+ (" .. tostring(found and found.right:GetText()) .. ")")

        _G.Spy_AbilityList = nil
        ok(not BT.HasAbilityData(), "utan tabellen gjer det rett og slett ingenting")
        ok(BT.NoteAbilityLevel("Kvasom", 50) == nil, "og ingen level blir gjetta")
      end

      -- Storleik: dette blir lese på to sekund før ein slåstkamp, ikkje studert
      do
        ChainDB.nearbyScale = nil
        local nb4 = _G.ChainNearby
        BT.RefreshNearby()
        ok(nb4:GetScale() > 1, "lista er større enn spelet sin småskrift som standard")
        BT.SetNearbyScale(1.5)
        eq(ChainDB.nearbyScale, 1.5, "og du kan skru henne opp")
        eq(nb4:GetScale(), 1.5, "som slår ut med ein gong")
        BT.SetNearbyScale(3)
        eq(ChainDB.nearbyScale, 2, "med eit tak")
        ChainDB.nearbyScale = nil
        BT.RefreshNearby()
      end

      -- Kven som slo kven: det einaste stykket historie om ein annan spelar
      -- som er ditt eige. Serveren fortel deg ingenting om dei, men han
      -- fortel deg kven som slutta å røre seg.
      do
        ChainDB.enemies = {}
        local keepGuid = S.guid
        S.guid = "Player-1-0000"
        BT.NoteEnemy("Bolla", { level = 60, class = "ROGUE" })
        BT.NoteFight("PARTY_KILL", "Player-1-0000", "Meg", 0x511,
                     "Player-4-0077", "Bolla-Testrealm", 0x440)
        eq(ChainDB.enemies["Bolla"].wins, 1, "eit drap blir talt")

        -- og andre vegen: den som slo deg sist får æra for at du datt
        BT.NoteFight("SWING_DAMAGE", "Player-4-0077", "Bolla-Testrealm", 0x440,
                     "Player-1-0000", "Meg", 0x511)
        BT.NoteFight("UNIT_DIED", nil, nil, nil, "Player-1-0000", "Meg", 0x511)
        eq(ChainDB.enemies["Bolla"].losses, 1, "og eit tap likeeins")

        -- ein som ikkje har rørt deg på lenge skal ikkje få skulda
        BT.lastHitBy, BT.lastHitAt = "Bolla", S.now - 600
        BT.NoteFight("UNIT_DIED", nil, nil, nil, "Player-1-0000", "Meg", 0x511)
        eq(ChainDB.enemies["Bolla"].losses, 1, "gammalt slag gjev ikkje skulda")

        -- og det står på tooltippen, som er heile poenget
        BT.RefreshNearby()
        local nb2 = _G.ChainNearby
        for _, r in ipairs(nb2.rows) do
          if r.rec and r.rec.name == "Bolla" then
            r.__scripts.OnEnter(r)
          end
        end
        local tip = S.TipText()
        ok(tip:find("you 1"), "scoren står på tooltippen (" .. tip:sub(1, 60) .. ")")
        S.guid = keepGuid
      end

      -- Notat på folk, frå høgreklikk. Grunnen til at du merka nokon er verdt
      -- meir enn merket: "gankar SM-inngangen kl 2" er ein plan, eit raudt
      -- namn er ein farge.
      do
        local keepKos = ChainDB.kos
        ChainDB.kos = {}
        local e2 = ChainDB.enemies["Bolla"]
        local pop = BT.NotePopup(e2)
        ok(pop ~= nil and pop:IsShown(), "notatboksen kjem opp")
        eq(pop.title:GetText(), "Bolla", "med namnet på han det gjeld")
        pop.box:SetText("gankar SM-inngangen kl 2")
        pop.save()
        -- eit notat merkar han IKKJE. "Ryr alltid med to venner" er verdt å
        -- skrive om ein du ikkje har tenkt å jakte på, og å måtte merke han
        -- for å seie det gjorde merket mindre verdt enn det skal vere.
        eq(BT.IsKOS("Bolla"), nil, "å skrive eit notat merkar han ikkje")
        eq(BT.EnemyNote("Bolla"), "gankar SM-inngangen kl 2", "men notatet er lagra")

        -- og den eine knappen gjer begge delar når det er den slags notat
        pop.mark.__scripts.OnClick(pop.mark)
        eq(select(1, BT.IsKOS("Bolla")), "named", "knappen merkar òg")
        eq(BT.EnemyNote("Bolla"), "gankar SM-inngangen kl 2",
           "og notatet står framleis")
        ok(not pop:IsShown(), "og boksen lukkar seg")

        -- og opnar du han igjen, står det du skreiv der
        BT.NotePopup(e2)
        eq(pop.box:GetText(), "gankar SM-inngangen kl 2", "notatet kjem fram igjen")
        pop:Hide()
        ChainDB.kos = keepKos
      end

    -- Boksen skal kunne dragast breiare og høgare. Breidda er det som lukkar
      -- holet mellom eit kort namn og klassa ved sida av; høgda er berre kor
      -- mange du vil sjå, så ho blir lagra som eit tal rader og ikkje som
      -- pikslar - då overlever ho ei endring av font eller skala.
      do
        local g = nb.grip
        ok(g ~= nil, "det er eit handtak i hjørnet")
        ChainDB.nearbyWidth, ChainDB.nearbyRows = nil, nil
        local wasName = nb.rows[1].name:GetWidth()

        g.__scripts.OnDragStart(g)
        nb:SetSize(300, 22 + 12 * 14)
        g.__scripts.OnDragStop(g)
        eq(ChainDB.nearbyWidth, 300, "breidda blir hugsa")
        eq(ChainDB.nearbyRows, 12, "og høgda blir til eit tal rader")

        BT.RefreshNearby()
        eq(nb:GetWidth(), 300, "boksen er så brei som du drog henne")
        ok(nb.rows[1].name:GetWidth() > wasName,
           "og namnet får plassen, i staden for at det opnar seg eit hol")

        -- og tikken skal ikkje endre storleik medan du held handtaket
        g.__scripts.OnDragStart(g)
        nb:SetSize(260, 22 + 5 * 14)
        local wMid, hMid = nb:GetWidth(), nb:GetHeight()
        BT.RefreshNearby()
        eq(nb:GetWidth(), wMid, "tikken rører ikkje breidda medan du dreg")
        eq(nb:GetHeight(), hMid, "eller høgda")
        g.__scripts.OnDragStop(g)

        ChainDB.nearbyWidth, ChainDB.nearbyRows = nil, nil
        BT.RefreshNearby()
      end

      -- og det finst ein veg tilbake om ho hamnar utanfor skjermen
      ok(BT.ResetNearbyPos(), "ho kan sendast heim igjen")
      eq(ChainDB.nearbyPos, nil, "og då er posisjonen gløymd")
      nb.__left, nb.__top = nil, nil
    end

    -- ein som ikkje er stealtha skal ikkje utløyse det
    S.units["nameplate8"] = { name = "Openlyst-Testrealm", level = 60,
                              class = "WARRIOR", hostile = true }
    S.auras["nameplate8"] = {}
    BT.NoteUnit("nameplate8", "nameplate")
    ok(not sb:IsShown(), "og ein som står i open dag gjer det ikkje")
    eq(ChainDB.enemies["Openlyst"].stealth, nil, "han er ikkje merkt som stealtha")
  end
  eq(ChainDB.enemies["Snill"], nil, "og ikkje-fiendtlege blir ikkje talt")

  -- KOS: ved namn og ved heile guilden, som er slik det oftast går
  BT.AddKOS("Gankar", "tok meg tre gonger i ST")
  eq(select(1, BT.IsKOS("Gankar")), "named", "namnet er merka")
  eq(select(2, BT.IsKOS("Gankar")), "tok meg tre gonger i ST", "med notatet ditt")
  BT.AddKOSGuild("Bad Bois", "heile gjengen")
  eq(select(1, BT.IsKOS("Ukjend", "Bad Bois")), "guild", "guilden er merka")
  eq(BT.IsKOS("Tilfeldig", "Anna Guild"), nil, "og resten er det ikkje")
  eq(#BT.KOSList(), 1, "ein på namnelista")
  eq(#BT.KOSGuildList(), 1, "og ein guild")
  ok(BT.RemoveKOS("Gankar"), "namn kan fjernast")
  eq(BT.IsKOS("Gankar"), nil, "og då er han borte")
  BT.AddKOS("Gankar", "tok meg tre gonger i ST")

  -- varselet: dei du har merka er verdt ein alarm anten du bad om det eller
  -- ikkje, og alle andre berre om du bad om det
  do
    ChainDB.alertEveryone = false
    ChainDB.enemyQuiet = {}
    BT.EnemyAlert({ name = "Gankar", level = 60, class = "ROGUE", guild = "Bad Bois" })
    local b = BT.alertFrame()
    ok(b ~= nil and b:IsShown(), "ein merka spelar gjev varsel")
    ok((b.head:GetText() or ""):find("Kill%-on%-sight"), "og det står kvifor")
    ok((b.name:GetText() or ""):find("Gankar"), "og kven")
    -- level og klasse ligg attmed namnet, som på varselet elles
    ok((b.name:GetText() or ""):find("60"), "med level")
    ok((b.name:GetText() or ""):find("Rogue"), "og klasse")

    -- ein tilfeldig framand gjer det ikkje, med mindre du har bedt om det
    ChainDB.enemyQuiet = {}
    b:Hide()
    BT.EnemyAlert({ name = "Tilfeldig", level = 40 })
    ok(not b:IsShown(), "ein framand gjev ikkje varsel som standard")
    ChainDB.alertEveryone = true
    ChainDB.enemyQuiet = {}
    BT.EnemyAlert({ name = "Tilfeldig", level = 40 })
    ok(b:IsShown(), "men gjer det når du har slått det på")
    ChainDB.alertEveryone = false

    -- og den same personen skal ikkje lage eitt varsel i sekundet
    ChainDB.enemyQuiet = {}
    BT.EnemyAlert({ name = "Gankar", guild = "Bad Bois" })
    b:Hide()
    BT.EnemyAlert({ name = "Gankar", guild = "Bad Bois" })
    ok(not b:IsShown(), "same person varslar ikkje om att med ein gong")
  end

  -- Notatboksen på Enemies blei plassert, fylt ut - og så slått av igjen på
  -- same teikninga, fordi Boosters si else-grein gøymde han. Han lagra heilt
  -- fint; du fekk berre aldri sjå han.
  do
    ChainDB.enemies, ChainDB.kos, ChainDB.kosGuilds = {}, {}, {}
    BT.NoteEnemy("Notatmann", { level = 40, class = "MAGE" })
    BT.ShowTab("enemies")
    local w9 = _G.ChainWindow
    local r
    for _, x in ipairs(w9.rows) do
      if x:IsShown() and (x.cells[2]:GetText() or ""):find("Notatmann") then r = x end
    end
    ok(r ~= nil, "rada er der")
    ok(r and r.note:IsShown(), "og notatboksen er faktisk synleg")
    eq(r and r.note.kos, "Notatmann", "og peikar på rett person")
    r.note:SetText("test notat")
    r.note.__scripts.OnEditFocusLost(r.note)
    eq(BT.EnemyNote("Notatmann"), "test notat", "det du skriv blir lagra")
    eq(BT.IsKOS("Notatmann"), nil, "og det merkar han ikkje")

    -- og dei tre rutingfelta skal nullstillast, elles hamnar det du skriv hos
    -- den som stod på rada på førre fana
    BT.ShowTab("boosters")
    local rb
    for _, x in ipairs(w9.rows) do if x:IsShown() and x.note:IsShown() then rb = x end end
    if rb then
      eq(rb.note.kos, nil, "kos blir nullstilt på Boosters")
      eq(rb.note.kosGuild, nil, "og kosGuild òg")
    end
    BT.ShowTab("enemies")
    ChainDB.kos, ChainDB.kosGuilds = {}, {}
  end

  -- Og notatboksen frå høgreklikk skal verke like eins
  do
    ChainDB.kos = {}
    local e = ChainDB.enemies["Notatmann"]
    local pop = BT.NotePopup(e)
    ok(pop:IsShown(), "popupen kjem opp")
    pop.box:SetText("frå menyen")
    pop.save()
    eq(BT.EnemyNote("Notatmann"), "frå menyen", "og lagrar")
    eq(BT.IsKOS("Notatmann"), nil, "utan å merke han")
    ChainDB.kos = {}
  end

  -- Kor mange gonger du har vunne og tapt, i sjølve lista og ikkje berre på
  -- tooltippen
  do
    ChainDB.enemies, ChainDB.kos = {}, {}
    BT.NoteEnemy("Vinnar", { level = 60 })
    BT.NoteEnemy("Taper", { level = 60 })
    BT.NoteEnemy("Ukjend", { level = 60 })
    ChainDB.enemies["Vinnar"].wins = 3
    ChainDB.enemies["Vinnar"].losses = 1
    ChainDB.enemies["Taper"].wins = 0
    ChainDB.enemies["Taper"].losses = 4
    BT.ShowTab("enemies")
    local w10, got = _G.ChainWindow, {}
    for _, x in ipairs(w10.rows) do
      if x:IsShown() then
        local who = (x.cells[2]:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        got[who] = (x.cells[8]:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      end
    end
    eq(got["Vinnar"], "3-1", "vunne-tapt står i lista")
    eq(got["Taper"], "0-4", "begge vegar")
    eq(got["Ukjend"], "-", "og ein du aldri har slåst med får ein strek, ikkje 0-0")
    ChainDB.enemies = {}
  end

  -- Ei eiga liste for dei merka, under Enemies. Det er ikkje same lista som
  -- "kven er her": ein du merka for tre veker sidan står ikkje i Enemies i det
  -- heile når observasjonen er forelda - og det er nettopp han du vil finne
  -- att og skrive om.
  do
    ChainDB.enemies, ChainDB.kos, ChainDB.kosGuilds = {}, {}, {}
    ChainDB.notes, ChainDB.guildNotes = {}, {}
    BT.NoteEnemy("Sett", { level = 44, class = "ROGUE" })
    BT.AddKOS("Sett", "tok meg i SM")
    BT.AddKOS("AldriSett", "ein eg fekk tips om")
    BT.AddKOSGuild("Bad Bois", "heile gjengen")

    BT.ShowTab("koslist")
    local w5 = _G.ChainWindow
    local found = {}
    for _, r in ipairs(w5.rows) do
      if r:IsShown() then found[#found + 1] = r.cells[1]:GetText() or "" end
    end
    eq(#found, 3, "alle tre står der")
    local all = table.concat(found, " ")
    ok(all:find("Sett"), "den du har sett")
    ok(all:find("AldriSett"), "og den du aldri har sett")
    ok(all:find("Bad Bois"), "og guilden")

    -- ein du aldri har møtt skal seie det i staden for å lyge om level
    for _, r in ipairs(w5.rows) do
      if r:IsShown() and (r.cells[1]:GetText() or ""):find("AldriSett") then
        ok((r.cells[5]:GetText() or ""):find("not since"),
           "aldri sett blir sagt rett ut")
      end
    end

    -- fana over skal framleis lyse
    ok(w5.enemyView and w5.enemyView:IsShown(), "og det er ein veg tilbake")

    -- clear-knappen fjernar guilden
    for _, r in ipairs(w5.rows) do
      if r:IsShown() and (r.cells[2]:GetText() or ""):find("guild") then
        r.kos.__scripts.OnClick(r.kos)
      end
    end
    eq(#BT.KOSGuildList(), 0, "guilden kan fjernast herifrå")

    -- og ein du berre har skrive om, utan å merke, skal òg vere å finne her -
    -- elles er det eit notat du aldri les igjen
    BT.SetEnemyNote("BereNotat", "ryr alltid med to venner")
    BT.ShowTab("koslist")
    local withNote = {}
    for _, r in ipairs(w5.rows) do
      if r:IsShown() then withNote[#withNote + 1] = r.cells[1]:GetText() or "" end
    end
    ok(table.concat(withNote, " "):find("BereNotat"),
       "ein umerka med notat står i lista")
    for _, r in ipairs(w5.rows) do
      if r:IsShown() and (r.cells[1]:GetText() or ""):find("BereNotat") then
        ok((r.cells[2]:GetText() or ""):find("note only"),
           "og det står at han berre har eit notat")
      end
    end

    BT.ShowTab("enemies")
    ChainDB.kos, ChainDB.kosGuilds = {}, {}
    ChainDB.notes, ChainDB.guildNotes = {}, {}
  end

  -- Både KOS og stealth skal ropast ut på same måten, midt på skjermen.
  do
    ChainDB.alertPos = nil
    ChainDB.enemyQuiet, ChainDB.stealthQuiet = {}, {}
    ChainDB.kos, ChainDB.kosGuilds = {}, {}
    BT.AddKOS("Merka")

    BT.EnemyAlert({ name = "Merka", level = 55, class = "WARRIOR" })
    local b = BT.alertFrame()
    ok(b:IsShown(), "ein merka blir ropt ut")
    ok((b.head:GetText() or ""):find("Kill%-on%-sight"), "med KOS i klartekst")

    BT.StealthAlert({ name = "Snik", level = 60, class = "ROGUE" })
    ok(b:IsShown(), "og ein stealtha likeeins")
    ok((b.head:GetText() or ""):find("Stealthed"), "med stealth i klartekst")

    -- same ramma, så dei to kan ikkje tie kvarandre i hel eller stable seg
    eq(BT.alertFrame(), BT.stealthBanner(), "begge bruker same ramma")

    -- og ho står midt på skjermen til du flyttar henne
    local pt = b.__points[1]
    ok(pt and (pt.point or ""):find("CENTER"),
       "forankra i midten (" .. tostring(pt and pt.point) .. ")")
    ChainDB.kos, ChainDB.kosGuilds = {}, {}
  end

  -- nærleik: den som blei sett for lenge sidan er ikkje i nærleiken lenger
  do
    ChainDB.enemies = {}
    BT.NoteEnemy("Nylig", { level = 60 })
    ChainDB.enemies["Gammal"] = { name = "Gammal", at = S.now - 600, n = 1 }
    eq(#BT.Nearby(60), 1, "berre den ferske er i nærleiken")
    eq(#BT.SeenList(), 2, "men begge står i lista")
  end

  -- fana teiknar dei, og KOS-knappen verkar
  do
    ChainDB.enemies = {}
    BT.NoteEnemy("Gankar", { level = 60, class = "ROGUE", guild = "Bad Bois" })
    BT.ShowTab("enemies")
    local w4 = _G.ChainWindow
    local row
    for _, r in ipairs(w4.rows or {}) do
      if r:IsShown() and (r.cells[2]:GetText() or ""):find("Gankar") then row = r end
    end
    ok(row ~= nil, "Enemies-fana har rader")
    ok(row and row.kos and row.kos:IsShown(), "og ein KOS-knapp på kvar")
    if row then
      -- guilden hans er framleis merka frå testen over, og då er det den
      -- knappen ville fjerna først
      ChainDB.kos, ChainDB.kosGuilds = {}, {}
      row.kos.name, row.kos.guild = "Gankar", "Bad Bois"
      row.kos.__scripts.OnClick(row.kos)
      eq(select(1, BT.IsKOS("Gankar")), "named", "eitt klikk merkar han")
      row.kos.__scripts.OnClick(row.kos)
      eq(BT.IsKOS("Gankar"), nil, "og eitt til fjernar merket")
    end
  end

  -- trade-fana tek med gjenstandane, ikkje berre gullet
  do
    local keep = ChainDB.trades
    ChainDB.trades = { { at = S.now, with = "Berreta", gave = 4000000, got = 0,
                         gaveItems = { { name = "Runecloth", count = 20 } },
                         gotItems = { { name = "Green Hills of Stranglethorn" } },
                         zone = "Stormwind City" } }
    BT.TouchTrades()
    eq(BT.ItemsText({ { name = "Runecloth", count = 20 } }), "20x Runecloth",
       "gjenstandar blir til tekst")
    eq(BT.ItemsText(nil), nil, "og ingenting blir ingenting")
    BT.ShowTab("gold")
    local w5 = _G.ChainWindow
    local found = false
    for _, r in ipairs(w5.rows or {}) do
      if r:IsShown() then
        for _, c in ipairs(r.cells) do
          if (c:GetText() or ""):find("Runecloth") then found = true end
        end
      end
    end
    ok(found, "og står i Trade-fana")
    ChainDB.trades = keep
    BT.TouchTrades()
  end

  -- merket på sjølve nameplatet. Ei linje øvst på skjermen seier at nokon er
  -- her; den seier ikkje kven av dei fire framfor deg det er.
  do
    ChainDB.kos, ChainDB.kosGuilds = {}, {}
    S.plates["nameplate1"] = CreateFrame("Frame", nil, UIParent)
    S.units["nameplate1"] = { name = "Merka-Testrealm", level = 60,
                              class = "ROGUE", guild = "Bad Bois", hostile = true }
    BT.MarkPlate("nameplate1")
    local plate = S.plates["nameplate1"]
    local mark
    for _, ch in ipairs(plate.__children or {}) do mark = ch end
    ok(mark == nil or not mark:IsShown(), "ingen merke på ein som ikkje er merka")

    BT.AddKOS("Merka")
    BT.MarkPlate("nameplate1")
    mark = nil
    for _, ch in ipairs(plate.__children or {}) do mark = ch end
    ok(mark ~= nil and mark:IsShown(), "merket kjem på når han er KOS")
    ok((mark.fs:GetText() or ""):find("KOS"), "og det står KOS på det")

    -- og å merke nokon medan platen alt står oppe skal syne med ein gong
    BT.RemoveKOS("Merka")
    ok(not mark:IsShown(), "merket går av når du fjernar merket")
    BT.AddKOS("Merka")
    ok(mark:IsShown(), "og på igjen med ein gong, utan å vente på ny plate")

    -- guild-merket gjeld heile guilden
    BT.RemoveKOS("Merka")
    BT.AddKOSGuild("Bad Bois")
    BT.MarkPlate("nameplate1")
    ok(mark:IsShown(), "guild-merket set merke på plata òg")

    S.Fire(BT.enemyFrame, "NAME_PLATE_UNIT_REMOVED", "nameplate1")
    ok(not mark:IsShown(), "og det går av når plata forsvinn")
    S.plates, ChainDB.kos, ChainDB.kosGuilds = {}, {}, {}
  end

  -- varselet skal oppføre seg ulikt for dei merka
  do
    -- ikkje nullstill globalen: ramma er laga ein gong og halden i ein local,
    -- så ein ny blir aldri bygd og globalen blir ståande tom
    ChainDB.enemyQuiet = {}
    BT.AddKOS("Slem")
    BT.EnemyAlert({ name = "Slem", level = 60 })
    local b = BT.alertFrame()
    -- ein merka pulsar og står dobbelt så lenge; ein framand gjer ingen av
    -- delane. Ei linje som oppfører seg likt anten det er ein forbipasserande
    -- eller mannen som har drepe deg fire gonger er ei linje du lærer å
    -- ignorere.
    ok(b.pulse == true, "ein merka gjev eit høgt varsel")
    local loudHold = b.hold
    ChainDB.enemyQuiet = {}
    ChainDB.alertEveryone = true
    BT.EnemyAlert({ name = "Framand", level = 30 })
    ok(b.pulse == false, "ein framand eit stille eitt")
    ok(b.hold < loudHold, "og han står kortare (" .. b.hold ..
       " mot " .. loudHold .. ")")
    ChainDB.alertEveryone = false
    ChainDB.kos = {}
  end

  -- lista på skjermen: fana er for å lese etterpå, denne er for akkurat no
  do
    ChainDB.enemies = {}
    ChainDB.nearbyList = true
    BT.NoteEnemy("Naer", { level = 60, class = "ROGUE", guild = "Bad Bois" })
    BT.RefreshNearby()
    local nb = _G.ChainNearby
    ok(nb ~= nil, "lista blir bygd")
    ok(nb and nb:IsShown(), "og er synleg når nokon er i nærleiken")
    ok((nb.rows[1].name:GetText() or ""):find("Naer"), "med namnet i")
    -- level og klasse saman til høgre, slik spelet skriv det elles
    eq(nb.rows[1].right:GetText(), "60 Rogue", "med level og klasse til høgre")
    ok((nb.title:GetText() or ""):find("1 nearby"), "og kor mange det er")

    -- eit klikk på rada merkar han, og tooltipen seier alt vi veit
    ChainDB.kos, ChainDB.kosGuilds = {}, {}
    S.shiftDown = true
    nb.rows[1].__scripts.PostClick(nb.rows[1], "LeftButton")
    S.shiftDown = false
    eq(select(1, BT.IsKOS("Naer")), "named", "klikk på rada merkar han")
    nb.rows[1].__scripts.OnEnter(nb.rows[1])
    local tip = S.TipText()
    ok(tip:find("Naer"), "tooltipen har namnet")
    -- "Level 60 Rogue", slik spelet skriv det - ikkje "level 60  ROGUE"
    ok(tip:find("Level 60"), "levelen")
    ok(tip:find("Rogue"), "klassen")
    ok(tip:find("Bad Bois"), "guilden")
    ok(tip:find("seen"), "og kor mange gonger han er sett")
    ok(tip:find("marked by name"), "og at han er merka")

    -- den som gjekk sin veg fell ut av seg sjølv
    ChainDB.enemies["Naer"].at = S.now - 600
    BT.RefreshNearby()
    ok(not nb:IsShown(), "lista forsvinn når ingen er i nærleiken")

    -- og kan slåast av
    BT.NoteEnemy("Naer2", { level = 20 })
    BT.RefreshNearby()
    ok(nb:IsShown(), "synleg igjen")
    eq(BT.ToggleNearby(), false, "kan slåast av")
    ok(not nb:IsShown(), "og då er ho borte")
    BT.ToggleNearby()
  end

  -- og heile vaktinga kan skruast av
  ChainDB.watchEnemies = false
  ChainDB.enemies = {}
  S.Fire(ef, "NAME_PLATE_UNIT_ADDED", "nameplate1")
  eq(next(ChainDB.enemies), nil, "avslått er avslått")
  ChainDB.watchEnemies = true
  S.units = {}
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
print("== oppgradering frå ein gammal installasjon ==")
-- Alt over er skrive med dagens former. Det er ikkje det nokon faktisk har på
-- disken: dei har eit år med handlar utan pris på seg, ein loot-logg full av
-- myntlinjer, ein inngangslogg som instans-ID-feilen har tømt, og ingen av
-- dei nye flaggene. Så: bygg ein slik database, lat addonet laste, og sjå
-- etter at kvar einaste migrering landar.
do
  local keepDB, keepChar = ChainDB, ChainCharDB
  local frame2 = BT.frame
  local t0 = S.now
  S.level = 30
  S.units["player"] = S.units["player"] or {}

  ChainDB = {
    -- gamle runs: ingen coin, ingen step på nokre av dei
    runs = {
      { at = t0 - 3000, t = 300, zone = "The Stockade", id = "stock",
        xp = 9000, k = 60, by = "Gamling", char = "Tester", lvl = 28 },
      { at = t0 - 2000, t = 300, zone = "The Stockade", id = "stock",
        xp = 9000, k = 60, by = "Gamling", char = "Tester", lvl = 29 },
      -- og denne er merkt som eit gjensyn av den gamle, feile regelen: han
      -- markerte kvar einaste gjentaking av same *instans-namn*. Det er
      -- nettopp desse runane som mista inngangen sin, så flagget må ikkje
      -- takast for god fisk i reparasjonen.
      { at = t0 - 1000, t = 300, zone = "The Stockade", id = "stock",
        xp = 9000, k = 60, by = "Gamling", char = "Tester", lvl = 29,
        reentry = true },
    },
    -- gamle handlar: ingen perRun, ingen manual, ingen setTo
    trades = {
      { at = t0 - 3600, with = "Gamling", gave = 100 * 10000, got = 0,
        id = "stock", by = "Gamling", char = "Tester", lvl = 28 },
    },
    -- og ein inngangslogg som feilen har ete opp: éin står att av tre
    entries = {
      { t = t0 - 3000, seq = "Tester:1", zone = "The Stockade",
        char = "Tester" },
    },
    -- loot-loggen slik han såg ut: éi linje per myntplukk
    loot = {
      { at = t0 - 2900, copper = 500, who = "Tester", n = 1, mine = true },
      { at = t0 - 2880, copper = 250, who = "Tester", n = 1, mine = true },
      { at = t0 - 1900, copper = 1000, who = "Tester", n = 1, mine = true },
      { at = t0 - 1880, id = 12345, link = "x", n = 1, who = "Tester" },
      { at = t0 - 500, copper = 33, who = "Tester", n = 1, mine = true },
    },
    boosters = { Gamling = { price = 100, pack = 5 } },   -- 20g per run
    route = { stock = { on = true, from = 22, to = 30, gold = 50, pack = 5 } },
  }
  ChainCharDB = {
    -- og gamle instans-IDar i det gamle formatet, utan kolon
    seenInst = { ["34"] = t0 - 1000 },
    instId = { ["The Stockade"] = "34" },
    entrySeq = 1,
  }
  S.Fire(frame2, "ADDON_LOADED", "Chain")

  -- 1. ingenting er borte
  eq(#ChainDB.runs, 3, "runane står")
  eq(#ChainDB.trades, 1, "og handelen")

  -- 2. inngangane er bygde opp att frå runloggen, òg dei som den gamle
  --    regelen hadde stempla som gjensyn
  eq(#ChainDB.entries, 3, "dei tapte inngangane er henta tilbake")
  eq(BT.Lockout(), 3, "og timen tel tre, ikkje ein")
  ok(ChainDB.entriesRepaired, "og reparasjonen er gjord unna")

  -- 3. myntane er folda inn i runane og ute av loggen
  eq(#ChainDB.loot, 1, "berre gjenstanden står att i loot-loggen")
  eq(ChainDB.runs[1].coin, 750, "myntane frå fyrste runen ligg på han")
  eq(ChainDB.runs[2].coin, 1000, "og den andre sine")
  eq(ChainDB.coinLoose, 33, "det som fall utanfor er teke vare på")
  eq(BT.RunCoin(), 750 + 1000 + 33, "og totalen er alt saman")
  ok(ChainDB.coinFolded, "og det skjer berre ein gong")

  -- 4. ein gammal handel utan pris på seg blir framleis rekna om til runs, på
  --    dagens pris, og seier ifrå om det
  local c = BT.BoosterCredit("Gamling")
  ok(c ~= nil, "det finst ei rekning med han")
  near(c.runsPaid, 5, "100g til 20g per run er fem runs")
  eq(c.guessed, 1, "og den eine er prisa på dagens pris")

  -- 5. ein gammal instans-ID i det gamle formatet skal ikkje lage eit falskt
  --    gjensyn: dei nye nøklane har kolon og kan ikkje kollidere
  eq(BT.InstIdFrom("Creature-0-4672-34-991-1234-0000"), "34:991",
     "ny nøkkel har både kart og kopi")
  ok(ChainCharDB.seenInst["34:991"] == nil, "og finst ikkje i den gamle lista")

  -- 6. dei nye innstillingane har trygge utgangspunkt
  eq(ChainDB.nearbyAlways, nil, "lista står ikkje plutseleg på skjermen")
  eq(ChainDB.meter, nil, "og fps-målaren slår seg ikkje på av seg sjølv")

  -- 7. og ei ny lasting gjer ingenting om att
  local runsBefore = ChainDB.runs[1].coin
  local entriesBefore = #ChainDB.entries
  S.Fire(frame2, "ADDON_LOADED", "Chain")
  eq(ChainDB.runs[1].coin, runsBefore, "myntane blir ikkje talde to gonger")
  eq(#ChainDB.entries, entriesBefore, "og inngangane ikkje lagde to gonger")

  -- 8. og etter reparasjonen blir flagget trudd att, slik det skal - det blir
  --    rekna ut riktig no
  do
    table.insert(ChainDB.runs, { at = t0 - 200, t = 300, zone = "The Stockade",
                                 id = "stock", xp = 9000, k = 60,
                                 by = "Gamling", char = "Tester", lvl = 30,
                                 reentry = true })
    BT.Touch()
    eq(BT.ReconcileEntries(), 0, "eit ekte gjensyn får ingen inngang")
    table.remove(ChainDB.runs)
    BT.Touch()
  end

  ChainDB, ChainCharDB = keepDB, keepChar
  BT.Touch() BT.TouchTrades()
end

-- Og ein logg som kjem frå eit namnebyte kan vere i kva rekkjefølgje som
-- helst. Foldinga går framover gjennom begge listene, så ein peikar som berre
-- flyttar seg framover ville lagt halve myntbunken i "heimlaus".
do
  local keepDB, keepChar = ChainDB, ChainCharDB
  local t0 = S.now
  ChainDB = BT.ApplyDefaults({
    runs = {
      { at = t0 - 1000, t = 300, zone = "The Stockade", id = "stock",
        xp = 9000, k = 60, char = "Tester" },
      { at = t0 - 3000, t = 300, zone = "The Stockade", id = "stock",
        xp = 9000, k = 60, char = "Tester" },
    },
    loot = {
      { at = t0 - 900, copper = 100, who = "Tester" },
      { at = t0 - 2900, copper = 700, who = "Tester" },
    },
  }, BT.DEFAULTS)
  ChainCharDB = BT.ApplyDefaults({}, BT.CHAR_DEFAULTS)
  BT.FoldCoins()
  local byAt = {}
  for _, r in ipairs(ChainDB.runs) do byAt[r.at] = r.coin end
  eq(byAt[t0 - 1000], 100, "myntane finn runen sin uansett rekkjefølgje")
  eq(byAt[t0 - 3000], 700, "og den andre òg")
  eq(ChainDB.coinLoose, nil, "og ingenting blir heimlaust")
  ChainDB, ChainCharDB = keepDB, keepChar
  BT.Touch() BT.TouchTrades()
end

--------------------------------------------------------------------------
print("== betalte runs blir talde ned ==")
-- Hans tilfelle, slik skjermbiletet viste det: 400g skrive inn for hand for
-- trettan minutt sidan, ti runs kjøpt, to runs gått sidan - og baren sa
-- framleis "10 runs paid up".
do
  local keepT, keepR, keepB = ChainDB.trades, ChainDB.runs, ChainDB.boosters
  local who = "Cart\195\168r"          -- Cartèr, slik klienten skriv han
  ChainDB.trades, ChainDB.runs = {}, {}
  ChainDB.boosters = { [who] = { price = 400, pack = 10 } }   -- 40g per run
  BT.Touch() BT.TouchTrades()

  local t0 = S.now
  ChainDB.trades[1] = { at = t0 - 780, with = who, gave = 400 * 10000, got = 0,
                        id = "sm", by = who, manual = true, perRun = 40,
                        char = "Tester", lvl = 38 }
  BT.TouchTrades()
  local c = BT.BoosterCredit(who)
  ok(c ~= nil, "det finst ei rekning")
  near(c.runsPaid, 10, "400g til 40g per run er ti runs")
  near(c.left, 10, "og ingen gått enno")

  -- så to runs med han
  for i = 1, 2 do
    table.insert(ChainDB.runs, { at = t0 - 600 + i * 200, t = 240, zone = "SM",
                                 id = "sm", xp = 8881, k = 66, by = who,
                                 char = "Tester" })
  end
  BT.Touch()
  c = BT.BoosterCredit(who)
  eq(c.runsDone, 2, "to runs gått")
  near(c.left, 8, "så det står att åtte, ikkje ti")

  ChainDB.trades, ChainDB.runs, ChainDB.boosters = keepT, keepR, keepB
  BT.Touch() BT.TouchTrades()
end

-- Halve gullet går til ein bank-alt, og augeblinken handelen går gjennom er
-- augeblinken du veit kven ho er. Så den spør då, i staden for å la boosteren
-- sjå ubetalt ut og alten sjå ut som ein framand som skuldar deg tjue runs.
do
  local keepT, keepR, keepB = ChainDB.trades, ChainDB.runs, ChainDB.boosters
  ChainDB.trades, ChainDB.runs = {}, {}
  ChainDB.boosters = { Carter = { price = 400, pack = 10 } }
  ChainCharDB.lastBy = "Carter"
  S.party = {}
  BT.Touch() BT.TouchTrades()

  ok(BT.AskIfAlt("Anisora"), "ein framand medan nokon boostar deg blir spurd om")
  ok(BT.AskIfAlt("Carter") == false, "boosteren sjølv blir ikkje spurd om")

  -- og ein som faktisk har køyrt for deg er ingen bank-alt
  table.insert(ChainDB.runs, { at = S.now - 100, by = "Kjend", id = "sm",
                               xp = 9000, k = 60, char = "Tester" })
  BT.Touch()
  ok(BT.AskIfAlt("Kjend") == false, "og ein som har køyrt for deg heller ikkje")

  -- seier du nei, blir du ikkje spurd igjen
  BT.BoosterInfo("Anisora").notAnAlt = true
  ok(BT.AskIfAlt("Anisora") == false, "og eit nei blir hugsa")
  ChainDB.boosters["Anisora"].notAnAlt = nil

  -- og seier du ja, tel gullet hennar for han
  BT.SetPaysFor("Anisora", "Carter")
  ok(BT.AskIfAlt("Anisora") == false, "ein alt som alt er knytt blir ikkje spurd")
  ChainDB.trades[1] = { at = S.now - 600, with = "Anisora", gave = 400 * 10000,
                        got = 0, id = "sm", perRun = 40, char = "Tester" }
  BT.TouchTrades()
  near(BT.BoosterCredit("Carter").runsPaid, 10,
       "og gullet til alten er hans runs")

  ChainCharDB.lastBy = nil
  ChainDB.trades, ChainDB.runs, ChainDB.boosters = keepT, keepR, keepB
  BT.Touch() BT.TouchTrades()
end

-- Boosteren sin eigen teljar. Addonet hans kunngjer kvar kvar enkelt er i
-- pakken - "[BoostBuddy] Nintoz - Run 4/10" - og det er talet han fakturerer
-- mot. Han veit når pakken starta; vi gjettar ut frå når du betalte.
do
  local keepT, keepR, keepB = ChainDB.trades, ChainDB.runs, ChainDB.boosters
  local me = UnitName("player")
  ChainDB.trades, ChainDB.runs = {}, {}
  ChainDB.boosters = { Carter = { price = 400, pack = 10 } }
  ChainCharDB.packRun = nil
  ChainDB.trades[1] = { at = S.now - 600, with = "Carter", gave = 400 * 10000,
                        got = 0, id = "sm", perRun = 40, char = "Tester" }
  BT.Touch() BT.TouchTrades()
  eq(BT.PackRun("Carter"), nil, "utan ei melding er det ingen teljar")

  -- ei linje som gjeld nokon andre er ikkje vår
  eq(BT.NotePackRun("[BoostBuddy] Truehair - Run 3/10", "Carter"), nil,
     "ei linje om ein annan i raidet tel ikkje")

  -- og ei som gjeld deg blir teken
  local p = BT.NotePackRun("[BoostBuddy] " .. me .. " - Run 4/10", "Carter")
  ok(p ~= nil, "linja om deg blir lesen")
  eq(p.n, 4, "kor langt du er komen")
  eq(p.of, 10, "og kor stor pakken er")
  local n, of, by = BT.PackRun("Carter")
  eq(n, 4, "og den kan lesast att")
  eq(of, 10, "med pakkestorleiken")
  eq(by, "Carter", "og kven som sa det")

  -- ein annan booster sin teljar gjeld ikkje denne
  eq(BT.PackRun("Berreta"), nil, "og gjeld berre den som sa det")

  -- baren skal vise hans tal når han har eitt
  local c = BT.BoosterCredit("Carter")
  eq(c.hisDone, 4, "rekninga ber hans tal")
  eq(c.hisLeft, 6, "og kor mange som står att av pakken hans")

  -- og den blir gammal
  S.now = S.now + 7300
  eq(BT.PackRun("Carter"), nil, "ein gammal teljar blir ikkje trudd")
  S.now = S.now - 7300

  -- Talet han sa er sant for den runden han sa det på. Han seier det ein gong
  -- per run, og ein booster som sluttar å seie det - eller har skrudd av
  -- addonen - let oss sitte med eit tal som var rett for tjue minutt og tre
  -- runder sidan. "9/10 runs" stod på baren i to timar etter at pakken var
  -- ferdig, fordi det var det siste han sa.
  do
    local said = ChainCharDB.packRun.at
    S.now = S.now + 400
    table.insert(ChainDB.runs, { at = said + 200, t = 300, zone = "The Stockade",
      id = "sm", by = "Carter", xp = 9000, k = 60, lvl = 20 })
    BT.Touch()
    eq(BT.PackRun("Carter"), 5, "ein run vi har sett tel eitt hakk vidare")
    eq(BT.BoosterCredit("Carter").hisLeft, 5, "og rekninga fylgjer med")

    -- og går det til enden av pakken, er pakken over: då er det vår eiga
    -- rekning som gjeld, og ho veit at du har gått forbi det du betalte for
    for i = 2, 6 do
      table.insert(ChainDB.runs, { at = said + 200 + i * 300, t = 300,
        zone = "The Stockade", id = "sm", by = "Carter", xp = 9000, k = 60,
        lvl = 20 })
    end
    S.now = S.now + 2000
    BT.Touch()
    eq(BT.PackRun("Carter"), nil, "ved enden av pakken er det ikkje noko att å tru på")
    eq(BT.BoosterCredit("Carter").hisLeft, nil, "og baren viser ikkje hans tal lenger")
    ok((BT.BoosterCredit("Carter").left or 0) < 10,
       "vår eiga rekning har talt rundene")
  end

  -- ei betaling som er nyare enn meldinga er ein ny pakke: hans gamle tal er
  -- om den førre
  do
    ChainCharDB.packRun = nil
    ChainDB.runs = {}
    BT.Touch()
    local q = BT.NotePackRun(me .. " - Run 3/10", "Carter")
    ok(q ~= nil, "han seier kor han er")
    eq(BT.PackRun("Carter"), 3, "og det blir trudd")
    table.insert(ChainDB.trades, { at = q.at + 10, with = "Carter",
      gave = 400 * 10000, got = 0, id = "sm", perRun = 40, char = "Tester" })
    BT.TouchTrades()
    eq(BT.PackRun("Carter"), nil, "men ikkje etter at du har betalt for ein ny")
    S.now = S.now + 60
  end

  -- Ein run forbi det som er betalt er normalt: du tek ein på krita og gjer
  -- opp på slutten. Ein heil pakke forbi er det ikkje - då har det gått pengar
  -- vi ikkje såg, og då seier han frå i staden for å la talet drive til at
  -- baren påstår du skuldar sju runder.
  do
    ChainDB.trades, ChainDB.runs = {}, {}
    ChainCharDB.debtTold, ChainCharDB.packRun = nil, nil
    ChainDB.trades[1] = { at = S.now - 7200, with = "Carter", gave = 400 * 10000,
                          got = 0, id = "sm", perRun = 40, char = "Tester" }
    for i = 1, 9 do
      table.insert(ChainDB.runs, { at = S.now - 7000 + i * 300, t = 300,
        zone = "The Stockade", id = "sm", by = "Carter", xp = 9000, k = 60,
        lvl = 20 })
    end
    BT.Touch() BT.TouchTrades()
    S.printed = {}
    BT.CheckDebt("Carter")
    eq(#S.printed, 0, "ni av ti er ikkje noko å seie frå om")

    for i = 10, 21 do
      table.insert(ChainDB.runs, { at = S.now - 7000 + i * 300, t = 300,
        zone = "The Stockade", id = "sm", by = "Carter", xp = 9000, k = 60,
        lvl = 20 })
    end
    BT.Touch()
    S.printed = {}
    BT.CheckDebt("Carter")
    ok(S.Said("runs past what is logged"), "ein heil pakke forbi blir sagt frå om")
    ok(S.Said("/chain paid Carter"), "med kommandoen som rettar det")

    S.printed = {}
    BT.CheckDebt("Carter")
    eq(#S.printed, 0, "men berre ein gong per betaling")

    -- og gjer du opp, er han stille igjen til neste gong
    table.insert(ChainDB.trades, { at = S.now, with = "Carter",
      gave = 400 * 10000, got = 0, id = "sm", perRun = 40, char = "Tester" })
    BT.TouchTrades()
    S.printed = {}
    BT.CheckDebt("Carter")
    eq(#S.printed, 0, "etter ei ny betaling er han stille")
  end

  -- ulike former på linja
  ChainCharDB.packRun = nil
  ok(BT.NotePackRun(me .. " - run 2/5", "Carter"), "liten r i run går òg")
  eq(select(2, BT.PackRun()), 5, "og pakkestorleiken blir med")

  ChainCharDB.packRun = nil
  ChainDB.trades, ChainDB.runs, ChainDB.boosters = keepT, keepR, keepB
  BT.Touch() BT.TouchTrades()
end

-- Og den som fekk det til å stå stille: runloggen heldt klienten si eiga
-- skrivemåte medan handelsloggen heldt den vaska, og dei blir samanlikna med
-- eit rett likskapsteikn. Ein booster som heiter CartEr var to ulike folk for
-- addonet - runsa hans talde for den eine og gullet for den andre, og
-- balansen rørte seg aldri.
do
  local keepT, keepR, keepB = ChainDB.trades, ChainDB.runs, ChainDB.boosters
  eq(BT.CleanName("CartEr"), "Carter", "vaskaren endrar ei stor bokstav inni")

  ChainDB.trades, ChainDB.runs = {}, {}
  ChainDB.boosters = { Carter = { price = 400, pack = 10 } }
  local t0 = S.now
  ChainDB.trades[1] = { at = t0 - 780, with = "Carter", gave = 400 * 10000,
                        got = 0, id = "sm", perRun = 40, char = "Tester" }
  -- runane slik klienten stava han
  for i = 1, 2 do
    table.insert(ChainDB.runs, { at = t0 - 400 + i * 100, t = 240, zone = "SM",
                                 id = "sm", xp = 8881, k = 66, by = "CartEr",
                                 char = "Tester" })
  end
  BT.Touch() BT.TouchTrades()
  eq(BT.BoosterCredit("Carter").runsDone, 0,
     "med to skrivemåtar tel ingen av runsa")

  -- og opprydninga ved innlasting set det på plass
  ChainDB.namesCleaned = nil
  S.Fire(BT.frame, "ADDON_LOADED", "Chain")
  BT.Touch() BT.TouchTrades()
  eq(ChainDB.runs[1].by, "Carter", "runloggen blir vaska")
  eq(BT.BoosterCredit("Carter").runsDone, 2, "og då tel dei")
  near(BT.BoosterCredit("Carter").left, 8, "åtte att av ti")

  ChainDB.trades, ChainDB.runs, ChainDB.boosters = keepT, keepR, keepB
  BT.Touch() BT.TouchTrades()
end

--------------------------------------------------------------------------
print(string.format("\n%d ok, %d feil", pass, fail))
if fail > 0 then os.exit(1) end
