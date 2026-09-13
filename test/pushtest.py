#!/usr/bin/env python3
"""
Tests for the phone-notification program: the engine, and the window driven
through a fake Tk. No display, no network beyond a throwaway server on
localhost, no WoW.

    python3 pushtest.py
"""

import json
import os
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
# beside the addon, or inside it: the repository has one shape and a working
# copy the other, and a test that only runs in one of them is half a test
PUSH = None
for _cand in (os.path.join(HERE, "..", "push"),
              os.path.join(HERE, "..", "Chain", "push")):
    if os.path.isdir(_cand):
        PUSH = os.path.abspath(_cand)
        break
assert PUSH, "cannot find the push folder from " + HERE
# one folder per platform, and the shared parts beside them
ENGINE = os.path.join(PUSH, "engine")
ICONS = os.path.join(PUSH, "icons")
WINDOWS = os.path.join(PUSH, "windows")
MAC = os.path.join(PUSH, "mac")
for _d in (PUSH, ENGINE, ICONS, HERE):
    sys.path.insert(0, _d)

import tkstub                                                # noqa: E402
tkstub.install()

import chainpush as engine                                   # noqa: E402

PASS, FAIL = [0], []


def ok(cond, what):
    if cond:
        PASS[0] += 1
    else:
        FAIL.append(what)
        print("  FEIL: " + what)


def eq(got, want, what):
    ok(got == want, "%s (fekk %r, venta %r)" % (what, got, want))


# ---------------------------------------------------------------- a fake ntfy
RECEIVED = []


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        RECEIVED.append({
            "path": self.path,
            "body": self.rfile.read(length).decode("utf-8"),
            "title": self.headers.get("Title"),
            "type": self.headers.get("Content-Type"),
        })
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *a):
        pass


server = HTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
BASE = "http://127.0.0.1:%d" % server.server_port

print("== log-linjer ==")
eq(engine.clean("9/11 20:14:03.123  Stockade has been reset."),
   "Stockade has been reset.", "tidsstempel blir stripsa")
eq(engine.clean("9/11 20:14:03.123  [1. LBTeldan] Nintoz: LTPUSH reset Stockades"),
   "LTPUSH reset Stockades", "kanal og talar blir stripsa")

rules = engine.active_rules(engine.DEFAULTS)
eq(engine.match("Stockade has been reset.", rules),
   ("Instance reset", "Stockade"), "reset frå spelet sjølv")
eq(engine.match("LTPUSH readycheck Nintoz", rules),
   ("Ready check", "Nintoz"), "ready check frå addonen")
got = engine.match("Cannot reset Stockade.  There are players still inside the instance.",
                   rules)
eq(got[0], "Reset failed", "mislykka reset")
ok("still inside" in got[1], "og seier kvifor")
ok(engine.match("selling boosts 200g", rules) is None, "vanleg chat blir ignorert")
ok(engine.match("LTPUSH level 28", rules) is None, "level-regelen er av som standard")
eq(engine.match("LTPUSH level 28", engine.active_rules({"extra": ["levelup"]}))[0],
   "Level up", "men kan slåast på")

print("== sending ==")
cfg = dict(engine.DEFAULTS, service="ntfy", topic="hemmeleg", server=BASE)
engine.notify(cfg, "Ready check", "Nintoz")
eq(len(RECEIVED), 1, "ntfy fekk éi melding")
eq(RECEIVED[-1]["path"], "/hemmeleg", "til rett emne")
eq(RECEIVED[-1]["title"], "Ready check", "med tittel")
eq(RECEIVED[-1]["body"], "Nintoz", "og innhald")

dcfg = dict(engine.DEFAULTS, service="discord", webhook=BASE + "/hook")
engine.notify(dcfg, "Instance reset", "Stockades")
eq(RECEIVED[-1]["type"], "application/json", "discord får JSON")
ok("Stockades" in json.loads(RECEIVED[-1]["body"])["content"], "med innhaldet i")

try:
    engine.notify(dict(engine.DEFAULTS, service="ntfy", topic=""), "x", "y")
    ok(False, "tomt emne skal klage")
except ValueError:
    ok(True, "tomt emne skal klage")

print("== innstillingar ==")
home = tempfile.mkdtemp()
os.environ["HOME"] = home
os.environ["APPDATA"] = home
os.environ["XDG_CONFIG_HOME"] = os.path.join(home, ".config")
ok(engine.config_path().startswith(home), "innstillingane hamnar under heimemappa")
saved = dict(engine.DEFAULTS, service="discord", webhook="https://x/y", topic="abc")
ok(engine.save_config(saved), "lagring gjekk")
back = engine.load_config()
eq(back["service"], "discord", "tenesta blir hugsa")
eq(back["webhook"], "https://x/y", "webhooken blir hugsa")
eq(back["topic"], "abc", "og emnet, så du kan byte fram og tilbake")

print("== fylgjer lggfila ==")
logdir = tempfile.mkdtemp()
logpath = os.path.join(logdir, "WoWChatLog.txt")
open(logpath, "w").close()
RECEIVED.clear()
stop = threading.Event()
wcfg = dict(engine.DEFAULTS, service="ntfy", topic="t", server=BASE,
            log=logpath, quiet_for=5)
events = []
t = threading.Thread(target=engine.watch,
                     args=(wcfg,),
                     kwargs={"on_event": lambda a, b: events.append((a, b)),
                             "stop": stop.is_set},
                     daemon=True)
t.start()
time.sleep(0.6)
with open(logpath, "a") as fh:
    fh.write("9/11 20:14:03.123  Stockade has been reset.\n")
    fh.write("9/11 20:14:04.123  [1. LBTeldan] Nintoz: LTPUSH readycheck Nintoz\n")
    fh.write("9/11 20:14:05.123  Stockade has been reset.\n")   # duplikat
    fh.flush()
deadline = time.time() + 5
while len(events) < 2 and time.time() < deadline:
    time.sleep(0.1)
time.sleep(0.6)
stop.set()
eq(len(events), 2, "to varsel ut av tre linjer")
ok(("Ready check", "Nintoz") in events, "ready check kom fram")
ok(all(e[0] != "Reset failed" for e in events), "ingen falske feilmeldingar")

print("== vindauget ==")
import tkinter as tk                                          # the stub
import chainpush_gui as gui                                   # noqa: E402

engine.save_config(dict(engine.DEFAULTS, service="ntfy", topic="mitt-emne",
                        server=BASE, log=logpath, autostart=False))
root = tk.Tk()
app = gui.App(root)
ok(root.titleText.startswith("Chain Push"), "vindauget har namn")
eq(app.field.get(), "mitt-emne", "emnet blir henta fram att")
eq(app.logEntry.get(), logpath, "og loggstien")
ok(not app.running, "og han startar ikkje av seg sjølv når det er skrudd av")

# bytte teneste skal bytte feltet, ikkje miste det andre
app.service.set("discord")
app._service_changed()
eq(app.fieldLabel.opts.get("text"), "Webhook URL", "etiketten byter")
app.field.delete(0, "end")
app.field.insert("end", BASE + "/hook")
app.gather()
app.service.set("ntfy")
app._service_changed()
eq(app.field.get(), "mitt-emne", "emnet er i behald etter eit bytte")
eq(engine.load_config()["webhook"], BASE + "/hook", "og webhooken er lagra")

# start, ei linje i loggen, og stopp
RECEIVED.clear()
app.start()
ok(app.running, "start set han i gang")
time.sleep(0.6)                      # la tråden få opna fila fyrst
eq(app.statusText.opts.get("text"), "Running", "lampa seier Running")
eq(app.lamp.items[app.lampDot]["fill"], gui.GREEN, "og ho er grøn")
with open(logpath, "a") as fh:
    fh.write("9/11 21:00:00.000  [1. LBTeldan] Nintoz: LTPUSH reset Stockades open\n")
deadline = time.time() + 5
while not RECEIVED and time.time() < deadline:
    time.sleep(0.1)
ok(len(RECEIVED) >= 1, "varselet gjekk ut medan vindauget køyrde")
time.sleep(0.3)                      # meldinga til vindauget kjem like etter
root.pump(4)
ok(app.sent >= 1, "og teljaren i vindauget gjekk opp")
ok(any("sent:" in line for line in app.feed.lines), "det står i lista")

app.stop()
ok(not app.running, "stopp stoppar")
eq(app.lamp.items[app.lampDot]["fill"], gui.RED, "og lampa blir raud")

# manglande emne skal gi ei åtvaring, ikkje ein krasj
tkstub.ASKED.clear()
app.service.set("ntfy")
app.field.delete(0, "end")
app.cfg["topic"] = ""
app.start()
ok(any(a[0] == "showwarning" for a in tkstub.ASKED), "tomt emne gir åtvaring")
ok(not app.running, "og han startar ikkje")

# lukking medan han køyrer skal spørje, ikkje berre døy
app.field.insert("end", "mitt-emne")
app.start()
tkstub.ASKED.clear()
tkstub.ANSWERS["askyesnocancel"] = None                        # avbryt
app.on_close()
ok(not root.destroyed, "avbryt lukkar ingenting")
tkstub.ANSWERS["askyesnocancel"] = False                       # nei: stopp og avslutt
app.on_close()
ok(root.destroyed, "nei avsluttar")
app.stopping.set()

print("== augneblinks-varselet: skjermbilete ==")
# Den einaste vegen ut av spelet som er rask nok. Eitt bilete = ready check,
# to = reset, og filene skal vere borte etterpå: dei var signal, ikkje bilete.
shots = tempfile.mkdtemp()
logdir = os.path.join(shots, "Logs")
os.makedirs(logdir)
fakelog = os.path.join(logdir, "WoWChatLog.txt")
open(fakelog, "w").close()
eq(engine.shots_dir(fakelog), os.path.join(shots, "Screenshots"),
   "Screenshots ligg ved sida av Logs")
made = engine.ensure_shots_dir(fakelog)
ok(made and os.path.isdir(made), "mappa blir laga om ho manglar")

seen = []
stopShots = threading.Event()
watcher = threading.Thread(
    target=engine.watch_shots,
    args=(fakelog, lambda n, title: seen.append((n, title))),
    kwargs={"stop": stopShots.is_set, "poll": 0.05, "settle": 0.2},
    daemon=True)
watcher.start()
time.sleep(0.2)
open(os.path.join(made, "one.tga"), "w").close()
time.sleep(0.8)
eq(seen and seen[-1], (1, "Ready check"), "eitt bilete er ein ready check")
eq(os.listdir(made), [], "og biletet er rydda bort")
open(os.path.join(made, "a.tga"), "w").close()
open(os.path.join(made, "b.tga"), "w").close()
time.sleep(0.8)
eq(seen and seen[-1], (2, "Instance reset"), "to bilete er ein reset")
eq(os.listdir(made), [], "dei er rydda bort òg")
stopShots.set()

print("== status og kommandoar ==")
# Menylinja og vaktaren er to prosessar og snakkar gjennom tre små filer.
runtime = tempfile.mkdtemp()
engine.config_path = lambda: os.path.join(runtime, "push.json")
eq(engine.runtime_dir(), runtime, "køyrefilene ligg hos innstillingane")
engine.write_status(running=True, sent=3, target="ntfy")
st = engine.read_status()
eq(st.get("sent"), 3, "status blir skriven")
ok(st.get("stamp"), "og tidsstempla")
engine.write_status(sent=4)
eq(engine.read_status().get("target"), "ntfy", "ei endring slettar ikkje resten")
engine.send_command("test")
engine.send_command("quit")
eq(engine.take_commands(), ["test", "quit"], "kommandoar kjem i rett rekkjefylgje")
eq(engine.take_commands(), [], "og blir tømde")
engine.log_event("sent", "Instance reset - from Chain")
with open(engine.state_file("events.log")) as fh:
    line = fh.read().strip().split("\t")
eq(line[1], "sent", "hendinga er merka")
eq(line[2], "Instance reset - from Chain", "og teksten står der")

print("== appen på mac ==")
# Ein AppleScript-applet, ikkje eit shell-script i ei app-mappe. Eit
# shell-script kan ikkje ta imot eit klikk - det var heile grunnen til at det
# ikkje fanst nokon veg tilbake når du lukka vindauget. Og menylinja: ho hadde
# ikkje plass på maskina, og kosta 46 % CPU på å teikne ingenting.
applet = os.path.join(MAC, "applet.applescript")
ok(os.path.exists(applet), "applet.applescript finst")
asrc = open(applet, encoding="utf-8").read()
ok("on reopen" in asrc, "han tek imot klikk i Docken")
ok("on quit" in asrc, "og Quit i Dock-menyen")
ok("on idle" in asrc, "og ser etter ein vaktar som har dotti ut")
ok("LSUIElement" not in asrc, "ingen skjult app - Dock-ikonet er heile poenget")
ok("--saved --serve" in asrc, "han startar vaktaren")
ok("--settings-only" in asrc, "og kan opne innstillingane")

build = os.path.join(MAC, "build-mac-app.command")
ok(os.path.exists(build), "build-mac-app.command finst")
bsrc = open(build, encoding="utf-8").read()
ok("osacompile" in bsrc, "han byggjer med osacompile, som finst på kvar Mac")
ok("Delete :LSUIElement" in bsrc, "og syter for at Dock-ikonet er der")
ok("applet.icns" in bsrc, "med vårt eige ikon")
# eit ikon i bundelen er ikkje nok: macOS held på den gamle til han blir
# fortalt noko anna
ok("lsregister" in bsrc and "killall Dock" in bsrc,
   "og ikon-cachen blir tvinga til å sleppe")
ok("CFBundleIconFile" in bsrc, "og plisten peikar på ikonet")
# osacompile legg ved ein kompilert asset-katalog med det generiske
# applet-ikonet, og moderne macOS brukar den framfor .icns-fila
ok("Assets.car" in bsrc, "asset-katalogen blir fjerna")
ok("Delete :CFBundleIconName" in bsrc, "og nøkkelen som peikar på han")
ok("codesign" in bsrc, "og bundelen blir signert på nytt etterpå")
ok("pkill" in bsrc, "og ryddar bort det som køyrde frå før")

# menylinje-forsøket skal vere heilt borte: det åt ein halv prosessor
for gone in ("menubar.js", "menubar.png", "menubar@2x.png"):
    ok(not os.path.exists(os.path.join(MAC, gone))
       and not os.path.exists(os.path.join(ICONS, gone)),
       gone + " er fjerna")
ok(os.path.exists(os.path.join(ICONS, "notify.png")), "notify.png finst")

print("== skuffa på windows ==")
tray = os.path.join(WINDOWS, "tray_win.py")
ok(os.path.exists(tray), "tray_win.py finst")
import py_compile                                            # noqa: E402
try:
    py_compile.compile(tray, doraise=True, cfile=os.path.join(runtime, "t.pyc"))
    ok(True, "han kompilerer")
except Exception as err:
    ok(False, "han kompilerer (%s)" % err)
tsrc = open(tray, encoding="utf-8").read()
ok("Shell_NotifyIcon" in tsrc, "ekte skuffe-ikon, ikkje eit vindauge")
ok("NIIF_USER" in tsrc, "ballongen får vårt eige ikon")
ok(not any(line.strip().startswith(("import pystray", "from PIL", "import PIL"))
           for line in tsrc.splitlines()),
   "ingenting å installere fyrst")
bat = open(os.path.join(WINDOWS, "ChainPush.bat"), encoding="utf-8").read()
ok("tray_win.py" in bat, ".bat-fila startar skuffa")
ok("pythonw" in bat, "og utan eit konsollvindauge bak spelet")

# pythonw køyrer utan konsoll, og utan konsoll set Python sys.stdout og
# sys.stderr til None i staden for til noko ufarleg. Fyrste print() i motoren
# kastar då AttributeError - og det finst ingen stad å skrive det heller.
# Programmet startar, døyr på fyrste linja med utskrift, og viser ingenting:
# eit vindauge som opnar og lukkar seg.
ok("sys.stdout is None" in tsrc,
   "skuffa gir straumane ein stad å gå når det ikkje finst konsoll")
ok(tsrc.index("sys.stdout is None") < tsrc.index("import chainpush"),
   "og gjer det før motoren blir importert")
ok("MessageBoxW" in tsrc, "og det som likevel ryk hamnar på skjermen")
ok("crash.log" in tsrc, "og på disk")
ok(tsrc.count("_died(") >= 3,
   "både importen og sjølve køyringa er dekte")
ok("debug" in bat, ".bat-fila kan køyre med meldingane synlege")
# Windows svarer på "python" sjølv om han ikkje finst: App Execution Alias er
# ein stubb som "where" finn, som køyrer, og som berre seier at du skal til
# Microsoft Store. Å tru på "where" er grunnen til at programmet opna og lukka
# seg utan eit ord. Den einaste testen som betyr noko er å køyre tingen.
_live = [ln for ln in bat.splitlines()
          if not ln.strip().lower().startswith("rem")]
ok(not any(ln.strip().lower().startswith("where ") for ln in _live),
   "han trur ikkje på 'where' - stubben frå Store finst der òg")
ok('-c "import sys"' in bat, "han prøver å faktisk køyre Python")
ok("py -3" in bat, "og fell tilbake på py-launcheren")
ok("Store" in bat, "og seier frå om stubben når han ikkje finn noko")

print("== det som faktisk blir pakka ==")
# Rotnivået i repoet ER addon-mappa, som er heile grunnen til at ein klone kan
# symlinkast rett inn i AddOns. Prisen er at alt anna ligg i same mappa, og
# utan denne fila fylgjer det med ned i AddOns-mappa til kven som helst.
_meta = os.path.join(PUSH, "..", ".pkgmeta")
ok(os.path.exists(_meta), ".pkgmeta finst")
_msrc = open(_meta, encoding="utf-8").read()
ok("package-as: Chain" in _msrc, "pakken heiter Chain")
for _gone in ("push", "test", ".github"):
    ok(("\n  - %s\n" % _gone) in _msrc,
       _gone + " blir halde utanfor det som blir lasta ned")
ok("CHANGELOG.md" in _msrc, "og endringsloggen blir vist til folk")

print("== ikon ==")
ok(len(gui.ICON_PNG_BASE64) > 1000, "ikonet ligg inne i programmet")
for f in ("icon.png", "icon.ico", "icon.icns"):
    ok(os.path.exists(os.path.join(ICONS, f)), "%s finst" % f)
with open(os.path.join(ICONS, "icon.icns"), "rb") as fh:
    ok(fh.read(4) == b"icns", "icns-fila har rett hovud")
# notify.png er det som ligg på varselbanneret, og må vere ekte farge
from PIL import Image                                        # noqa: E402
banner = Image.open(os.path.join(ICONS, "notify.png")).convert("RGBA")
ok(banner.size[0] >= 64, "varselikonet er stort nok (%dpx)" % banner.size[0])

# .icns-fila må ha storleikane macOS spør etter. Manglar ein, kan macOS
# stillteiande bruke det generiske ikonet i staden.
import struct                                                # noqa: E402
raw = open(os.path.join(ICONS, "icon.icns"), "rb").read()
kinds, at = set(), 8
while at < len(raw):
    kind = raw[at:at + 4]
    size = struct.unpack(">I", raw[at + 4:at + 8])[0]
    if size < 8:
        break
    kinds.add(kind.decode("ascii", "replace"))
    at += size
for want in ("icp4", "icp5", "ic07", "ic08", "ic09", "ic11", "ic12", "ic13"):
    ok(want in kinds, "icns har %s" % want)
eq(struct.unpack(">I", raw[4:8])[0], len(raw), "og lengda i hovudet stemmer")

server.shutdown()
print()
print("%d ok, %d feil" % (PASS[0], len(FAIL)))
sys.exit(1 if FAIL else 0)
