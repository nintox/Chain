#!/bin/bash
# Tests for the no-Python version of the push program: the part of LevelPush
# that runs on a Mac with nothing installed. No dialogs are involved - those
# are the Mac's own - but everything underneath them is exercised here: the
# settings file, the line matching, the sending and the watching.

set -u
# beside the addon, or inside it
for cand in "$(dirname "$0")/../push" "$(dirname "$0")/../Chain/push"; do
  [ -d "$cand" ] && PUSH="$(cd "$cand" && pwd)" && break
done
[ -n "${PUSH:-}" ] || { echo "cannot find the push folder" >&2; exit 1; }
TMP="$(mktemp -d)"
PASS=0; FAIL=0

ok()  { if [ "$1" = "1" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL: $2"; fi }
eqs() { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1))
        echo "  FAIL: $3 (fekk '$1', venta '$2')"; fi }

# a throwaway server standing in for ntfy
python3 - "$TMP" <<'PY' &
import sys, os
from http.server import BaseHTTPRequestHandler, HTTPServer
out = os.path.join(sys.argv[1], "received")
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode()
        with open(out, "a") as fh:
            fh.write("%s\t%s\t%s\n" % (self.path, self.headers.get("Title") or "-", body))
        self.send_response(200); self.end_headers()
    def log_message(self, *a): pass
srv = HTTPServer(("127.0.0.1", 8731), H)
srv.serve_forever()
PY
SERVER_PID=$!
sleep 1

export LT_CONF="$TMP/push.json"
export LT_STATE="$TMP/count"
export LT_SOURCE_ONLY=1
# shellcheck disable=SC1090
. "$PUSH/chainpush.sh"

echo "== innstillingar =="
SERVICE="ntfy"; TOPIC="hemmeleg"; SERVER="http://127.0.0.1:8731"; WEBHOOK=""
LOG="$TMP/WoWChatLog.txt"
conf_save
ok "$([ -f "$LT_CONF" ] && echo 1)" "innstillingsfila blir skriven"
SERVICE=""; TOPIC=""; LOG=""
conf_load
eqs "$SERVICE" "ntfy" "tenesta blir lesen tilbake"
eqs "$TOPIC" "hemmeleg" "emnet blir lese tilbake"
eqs "$LOG" "$TMP/WoWChatLog.txt" "loggstien blir lesen tilbake"
# og den same fila som python-versjonen skriv
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['topic'])" "$LT_CONF" >"$TMP/py" 2>/dev/null
eqs "$(cat "$TMP/py")" "hemmeleg" "python-versjonen les same fil"

echo "== linjer =="
eqs "$(classify '9/11 20:14:03.123  Stockade has been reset.')" \
    "Instance reset|Stockade" "reset frå spelet"
eqs "$(classify '9/11 20:14:03.123  [1. LBTeldan] Nintoz: LTPUSH readycheck Nintoz')" \
    "Ready check|Nintoz" "ready check frå addonen"
eqs "$(classify '9/11 20:14:03.123  [1. LBTeldan] Nintoz: LTPUSH reset Stockades is open')" \
    "Instance reset|Stockades is open" "reset-markør"
ok "$([ -z "$(classify '9/11 20:14:03.123  Selling boosts 200g')" ] && echo 1)" \
   "vanleg chat blir ignorert"
case "$(classify 'Cannot reset Stockade.  There are players still inside the instance.')" in
  "Reset failed|"*) ok 1 "mislykka reset" ;;
  *) ok 0 "mislykka reset" ;;
esac

echo "== sending =="
send "Ready check" "Nintoz"
sleep 0.3
eqs "$(head -1 "$TMP/received" | cut -f1)" "/hemmeleg" "gjekk til rett emne"
eqs "$(head -1 "$TMP/received" | cut -f2)" "Ready check" "med tittel"
eqs "$(head -1 "$TMP/received" | cut -f3)" "Nintoz" "og innhald"

SERVICE="discord"; WEBHOOK="http://127.0.0.1:8731/hook"
send "Instance reset" "Stockades"
sleep 0.3
ok "$(grep -c '"content"' "$TMP/received" >/dev/null && echo 1)" "discord får JSON"
SERVICE="ntfy"

echo "== fylgjer loggfila =="
: > "$LOG"
: > "$TMP/received"
watch_log >"$TMP/watchlog" 2>&1 &
WATCHER=$!
sleep 1
{
  echo "9/11 20:14:03.123  Stockade has been reset."
  echo "9/11 20:14:04.123  [1. LBTeldan] Nintoz: LTPUSH readycheck Nintoz"
  echo "9/11 20:14:05.123  Stockade has been reset."
} >> "$LOG"
for _ in $(seq 1 40); do
  [ "$(wc -l < "$TMP/received")" -ge 2 ] && break
  sleep 0.25
done
sleep 0.5
stop_watching
lines=$(wc -l < "$TMP/received")
eqs "$lines" "2" "to varsel ut av tre linjer (duplikat droppa)"
ok "$(grep -q "Ready check" "$TMP/received" && echo 1)" "ready check kom fram"
eqs "$(cat "$LT_STATE")" "2" "teljaren stemmer"
ok "$(pgrep -f "tail -n 0 -F $LOG" >/dev/null && echo 0 || echo 1)" "tail blir drepen med"

echo "== gøymd, men framleis i gang =="
export LT_SHOW="$TMP/show"
SHOWFLAG="$LT_SHOW"
rm -f "$SHOWFLAG"
sleep 30 &
WATCHER=$!
( hidden_wait; echo "$?" > "$TMP/hidden1" ) &
HID=$!
sleep 0.6
touch "$SHOWFLAG"
wait "$HID" 2>/dev/null
eqs "$(cat "$TMP/hidden1")" "0" "kjem tilbake når du opnar appen igjen"
ok "$([ ! -f "$SHOWFLAG" ] && echo 1)" "og ryddar flagget"
kill "$WATCHER" 2>/dev/null

# og gir seg om det ikkje er noko att å passe på
WATCHER=999999
( hidden_wait; echo "$?" > "$TMP/hidden2" ) &
HID=$!
wait "$HID" 2>/dev/null
eqs "$(cat "$TMP/hidden2")" "1" "gir seg når vaktaren er borte"

echo "== mac-appen =="
# Appen blir bygd på Mac-en med osacompile, så det einaste som kan testast
# her er oppskrifta. Ein AppleScript-applet, fordi eit shell-script i ei
# app-mappe ikkje kan ta imot eit klikk i Docken.
BUILD="$PUSH/build-mac-app.command"
ok "$([ -x "$BUILD" ] && echo 1)" "byggeskriptet er køyrbart"
ok "$(bash -n "$BUILD" && echo 1)" "og gyldig bash"
ok "$(grep -q "osacompile" "$BUILD" && echo 1)" "det byggjer med osacompile"
ok "$(grep -q "applet.applescript" "$BUILD" && echo 1)" "frå applet.applescript"
ok "$([ -f "$PUSH/applet.applescript" ] && echo 1)" "som ligg der"
ok "$(grep -q "^on reopen" "$PUSH/applet.applescript" && echo 1)" \
   "og tek imot klikk i Docken"
ok "$(grep -q "^on quit" "$PUSH/applet.applescript" && echo 1)" "og Quit"
ok "$([ -f "$PUSH/icon.icns" ] && echo 1)" "ikonet finst å byggje med"
ok "$(bash -n "$PUSH/chainpush.sh" && echo 1)" "skriptet er gyldig bash"
ok "$(grep -q -- "--settings-only" "$PUSH/chainpush.sh" && echo 1)" \
   "og kan opne berre innstillingane"

kill "$SERVER_PID" 2>/dev/null
rm -rf "$TMP"
echo
echo "$PASS ok, $FAIL feil"
[ "$FAIL" -eq 0 ]
