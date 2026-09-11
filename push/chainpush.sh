#!/bin/bash
# Chain Push, with nothing installed.
#
# Same job as chainpush.py: watch WoW's chat log and forward the lines worth
# knowing about to ntfy or a Discord webhook. This version uses only what
# every Mac already has - bash, curl, tail and the system's own dialogs - so
# it runs on a machine with no Python at all.
#
#   open ChainPush.app          the dialogs, the status window, the lot
#   bash chainpush.sh --watch   no dialogs: watch and send, print what it does
#   bash chainpush.sh --test    send one notification and stop
#
# It only reads a file. It does not touch WoW, does not read its memory, does
# not send it anything, and does not automate any part of playing.

set -u

APP="Chain Push"
SUPPORT="$HOME/Library/Application Support/Chain"
CONF="${LT_CONF:-$SUPPORT/push.json}"
STATE="${LT_STATE:-$SUPPORT/push.count}"
# opening the app a second time should not start a second watcher: it should
# bring the first one's window back. These two files are how they talk.
PIDFILE="${LT_PID:-$SUPPORT/push.pid}"
SHOWFLAG="${LT_SHOW:-$SUPPORT/push.show}"
QUIET_FOR=20

mkdir -p "$(dirname "$CONF")" 2>/dev/null
# Every name this has had, newest first. A rename should never ask somebody to
# type a topic they set up months ago all over again.
for OLD in LevelBar LevelTracker; do
  OLDCONF="$HOME/Library/Application Support/$OLD/push.json"
  if [ ! -f "$CONF" ] && [ -f "$OLDCONF" ]; then
    cp "$OLDCONF" "$CONF" 2>/dev/null \
      && echo "$(date '+%H:%M:%S')  carried your settings over"
  fi
done

SERVICE=""; TOPIC=""; SERVER="https://ntfy.sh"; WEBHOOK=""; LOG=""

#--------------------------------------------------------------------------
# settings, in the same file the Python version uses
#--------------------------------------------------------------------------
conf_get() {   # conf_get key  ->  value, from our own pretty-printed json
  [ -f "$CONF" ] || return 0
  sed -n "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\},\{0,1\}[[:space:]]*$/\1/p" \
    "$CONF" | head -1
}

conf_load() {
  SERVICE="$(conf_get service)"; [ -n "$SERVICE" ] || SERVICE="ntfy"
  TOPIC="$(conf_get topic)"
  SERVER="$(conf_get server)"; [ -n "$SERVER" ] || SERVER="https://ntfy.sh"
  WEBHOOK="$(conf_get webhook)"
  LOG="$(conf_get log)"
}

conf_save() {
  cat > "$CONF" <<EOF
{
  "service": "$SERVICE",
  "topic": "$TOPIC",
  "server": "$SERVER",
  "webhook": "$WEBHOOK",
  "log": "$LOG",
  "priority": "high",
  "quiet_for": $QUIET_FOR,
  "autostart": true
}
EOF
}

#--------------------------------------------------------------------------
# the Mac's own dialogs, each one harmless when there is no Mac behind it
#--------------------------------------------------------------------------
osa() { /usr/bin/osascript "$@" 2>/dev/null; }

say_error() {
  osa -e "display dialog \"$1\" buttons {\"OK\"} default button 1 with title \"$APP\" with icon caution" >/dev/null
}

ask_text() {   # ask_text prompt default
  osa -e "display dialog \"$1\" default answer \"$2\" buttons {\"Cancel\",\"OK\"} default button \"OK\" with title \"$APP\"" \
      -e 'text returned of result'
}

#--------------------------------------------------------------------------
# where the log is
#--------------------------------------------------------------------------
find_log() {
  local p
  for p in \
    "/Applications/World of Warcraft/_classic_era_/Logs/WoWChatLog.txt" \
    "/Applications/World of Warcraft/_anniversary_/Logs/WoWChatLog.txt" \
    "$HOME/Applications/World of Warcraft/_classic_era_/Logs/WoWChatLog.txt" \
    "/Applications/World of Warcraft/_retail_/Logs/WoWChatLog.txt"
  do
    [ -f "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

choose_log() {
  local picked
  picked="$(osa -e "choose file with prompt \"Find WoWChatLog.txt - it is in the Logs folder of your WoW install\"" \
                -e 'POSIX path of result')"
  printf '%s' "$picked"
}

#--------------------------------------------------------------------------
# sending
#--------------------------------------------------------------------------
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

send() {   # send title body
  local title="$1" body="$2"
  if [ "$SERVICE" = "discord" ]; then
    [ -n "$WEBHOOK" ] || return 1
    curl -sS -m 10 -X POST -H 'Content-Type: application/json' \
      -d "{\"content\": \"**$(json_escape "$title")** - $(json_escape "$body")\"}" \
      "$WEBHOOK" >/dev/null
  else
    [ -n "$TOPIC" ] || return 1
    curl -sS -m 10 -H "Title: $title" -H "Priority: high" -H "Tags: video_game" \
      -d "$body" "${SERVER%/}/$TOPIC" >/dev/null
  fi
}

notify_mac() {
  osa -e "display notification \"$(json_escape "$2")\" with title \"$(json_escape "$1")\"" >/dev/null
}

#--------------------------------------------------------------------------
# reading the log
#--------------------------------------------------------------------------
# One line in, one "title|body" out, or nothing. Kept as its own function so
# the tests can feed it lines without a WoW anywhere near.
classify() {
  local line
  line="$(printf '%s' "$1" \
    | sed -E 's/^[0-9]+\/[0-9]+ [0-9]+:[0-9]+:[0-9]+\.[0-9]+[[:space:]]*//' \
    | sed -E 's/^\[[^]]*\][[:space:]]*[^:]+:[[:space:]]*//')"
  case "$line" in
    *"LTPUSH readycheck "*) printf 'Ready check|%s' "${line#*LTPUSH readycheck }" ;;
    *"LTPUSH reset "*)      printf 'Instance reset|%s' "${line#*LTPUSH reset }" ;;
    "Cannot reset "*)       printf 'Reset failed|%s' "$(printf '%s' "${line#Cannot reset }" | tr -s ' ')" ;;
    *" has been reset."*)   printf 'Instance reset|%s' "${line%% has been reset.*}" ;;
  esac
}

# The same reset is announced by the game and by every other addon in the
# party, and they do not arrive in a row - a ready check can land between two
# copies of it. So we remember the last handful of events with their times
# rather than only the previous one. Plain strings, no associative arrays:
# macOS still ships bash 3.2, where those do not exist.
RECENT=""
seen_lately() {   # seen_lately key now  ->  0 when it is a repeat
  local key="$1" now="$2" kept="" hit=1 entry k t
  local OLD_IFS="$IFS"
  IFS='
'
  for entry in $RECENT; do
    k="${entry%@*}"; t="${entry##*@}"
    if [ $((now - t)) -lt $QUIET_FOR ]; then
      [ "$k" = "$key" ] && hit=0
      kept="$kept$entry
"
    fi
  done
  IFS="$OLD_IFS"
  if [ $hit -eq 0 ]; then RECENT="$kept"; return 0; fi
  RECENT="$kept$key@$now
"
  return 1
}

# What it is actually watching and where it is actually sending, printed once
# so the log answers the question instead of inviting a guess. The topic is
# masked: the log sits in a folder you might share.
describe_setup() {
  local who
  if [ "$SERVICE" = "discord" ]; then
    who="discord webhook (${#WEBHOOK} chars)"
  else
    who="ntfy ${SERVER%/}/$(printf '%s' "$TOPIC" | cut -c1-3)... (${#TOPIC} chars)"
  fi
  echo "$(date '+%H:%M:%S')  watching: ${LOG:-NOTHING}"
  echo "$(date '+%H:%M:%S')  sending to: $who"
  [ -f "$LOG" ] || echo "$(date '+%H:%M:%S')  WARNING: that file does not exist"
  if [ "$SERVICE" = "ntfy" ] && [ -z "$TOPIC" ]; then
    echo "$(date '+%H:%M:%S')  WARNING: no ntfy topic set - nothing can be sent"
  fi
  if [ "$SERVICE" = "discord" ] && [ -z "$WEBHOOK" ]; then
    echo "$(date '+%H:%M:%S')  WARNING: no webhook set - nothing can be sent"
  fi
}

#--------------------------------------------------------------------------
# The instant alert: screenshots
#--------------------------------------------------------------------------
# The chat log is written in 48 KiB blocks, so a marker can sit in the game's
# memory for ten minutes. A screenshot is not buffered: the client writes the
# file the moment the addon asks for it. So the addon takes one for a ready
# check and two for a reset, and this watches the folder they land in, counts
# the batch, sends the push and deletes them again.
shots_dir() {
  # .../Logs/WoWChatLog.txt  ->  .../Screenshots
  local base
  base="$(dirname "$(dirname "$LOG")")"
  printf '%s/Screenshots' "$base"
}

watch_shots() {
  local dir since batch n title
  dir="$(shots_dir)"
  # WoW only creates this folder the first time somebody takes a screenshot,
  # so it is normal for it to be missing. Make it and watch it: the game is
  # perfectly happy to write into a folder that is already there.
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir" 2>/dev/null
    if [ -d "$dir" ]; then
      echo "$(date '+%H:%M:%S')  created $dir"
    else
      echo "$(date '+%H:%M:%S')  cannot make $dir - instant alerts off"
      return 0
    fi
  fi
  echo "$(date '+%H:%M:%S')  watching for instant alerts in $dir"
  since="$(mktemp -t chainpushsince)"
  while true; do
    sleep 1
    batch="$(find "$dir" -type f -newer "$since" 2>/dev/null | head -20)"
    [ -n "$batch" ] || continue
    # let the rest of the batch land before deciding what it means
    sleep 2
    batch="$(find "$dir" -type f -newer "$since" 2>/dev/null | head -20)"
    n="$(printf '%s\n' "$batch" | grep -c .)"
    touch "$since"
    if [ "$n" -ge 2 ]; then title="Instance reset"; else title="Ready check"; fi
    echo "$(date '+%H:%M:%S')  instant alert: $n screenshot(s) -> $title"
    if send "$title" "from Chain"; then
      count=$(( $(cat "$STATE" 2>/dev/null || echo 0) + 1 ))
      echo "$count" > "$STATE" 2>/dev/null
      echo "$(date '+%H:%M:%S')  sent: $title"
      notify_mac "$title" "Chain"
    else
      echo "$(date '+%H:%M:%S')  COULD NOT SEND: $title" >&2
    fi
    # tidy up after ourselves: these were signals, not pictures
    printf '%s\n' "$batch" | while IFS= read -r f; do
      [ -n "$f" ] && rm -f "$f" 2>/dev/null
    done
  done
}

# A line a minute saying what the file looks like from *this* machine: how big
# it is and how fresh its last line is. Reading it from anywhere else can lag,
# and a question like "is the client buffering, or is my view stale?" should
# be answered by the program sitting next to the file.
heartbeat() {
  while true; do
    sleep 60
    local size last
    size="$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')"
    last="$(tail -1 "$LOG" 2>/dev/null | cut -c1-14)"
    echo "$(date '+%H:%M:%S')  heartbeat: $size bytes, last line: $last"
  done
}

watch_log() {
  local raw hit title body now count
  describe_setup
  heartbeat &
  HEARTBEAT=$!
  watch_shots &
  SHOTWATCH=$!
  echo 0 > "$STATE" 2>/dev/null
  /usr/bin/tail -n 0 -F "$LOG" 2>/dev/null | while IFS= read -r raw; do
    case "$raw" in
      *LTPUSH*) echo "$(date '+%H:%M:%S')  saw a marker line in the log" ;;
    esac
    hit="$(classify "$raw")"
    [ -n "$hit" ] || continue
    title="${hit%%|*}"; body="${hit#*|}"
    now="$(date +%s)"
    if seen_lately "$title $body" "$now"; then
      echo "$(date '+%H:%M:%S')  repeat within ${QUIET_FOR}s, skipped: $title - $body"
      continue
    fi
    if send "$title" "$body"; then
      count=$(( $(cat "$STATE" 2>/dev/null || echo 0) + 1 ))
      echo "$count" > "$STATE" 2>/dev/null
      echo "$(date '+%H:%M:%S')  sent: $title - $body"
      notify_mac "$title" "$body"
    else
      echo "$(date '+%H:%M:%S')  COULD NOT SEND: $title - $body" >&2
    fi
  done
}

stop_watching() {
  [ -n "${SHOTWATCH:-}" ] && kill "$SHOTWATCH" 2>/dev/null
  [ -n "${HEARTBEAT:-}" ] && kill "$HEARTBEAT" 2>/dev/null
  [ -n "${WATCHER:-}" ] && kill "$WATCHER" 2>/dev/null
  # tail lives in its own process under the subshell and outlives the kill
  pkill -f "tail -n 0 -F $LOG" 2>/dev/null
  return 0
}

#--------------------------------------------------------------------------
# first run
#--------------------------------------------------------------------------
setup() {
  local choice topic hook
  choice="$(osa -e "choose from list {\"ntfy app\", \"Discord\"} with prompt \"Where should the notifications go?\" with title \"$APP\"")"
  case "$choice" in
    *Discord*) SERVICE="discord" ;;
    *)         SERVICE="ntfy" ;;
  esac

  if [ "$SERVICE" = "discord" ]; then
    hook="$(ask_text "Paste the Discord webhook URL.\n\nChannel you can edit - Edit channel - Integrations - Webhooks - Copy URL." "$WEBHOOK")"
    [ -n "$hook" ] || return 1
    WEBHOOK="$hook"
  else
    topic="$(ask_text "Your ntfy topic - the name you subscribed to in the ntfy app.\n\nMake it long and odd: anyone who knows it can read your alerts." "$TOPIC")"
    [ -n "$topic" ] || return 1
    TOPIC="$topic"
  fi

  if [ -z "$LOG" ] || [ ! -f "$LOG" ]; then
    LOG="$(find_log)" || LOG="$(choose_log)"
  fi
  conf_save
  return 0
}

#--------------------------------------------------------------------------
# the status window: the thing that says "yes, it is running"
#--------------------------------------------------------------------------
# Out of the way, still working. macOS has no tray for a shell app, but the
# app's own icon in the Dock is the same promise, and a notification says so
# in as many words. Opening ChainPush again brings this window back.
# Hidden has to be a place you can get back from without knowing a trick. A
# script app cannot put an icon in the menu bar and cannot hear the Dock, so
# the window comes back by itself: the moment something is sent, and at the
# latest after half an hour. Opening ChainPush again brings it back too, on
# the Macs where that starts a second copy.
HIDE_FOR=1800
hidden_wait() {
  local deadline seen now count
  deadline=$(( $(date +%s) + HIDE_FOR ))
  seen="$(cat "$STATE" 2>/dev/null || echo 0)"
  osa -e "display notification \"Still watching. This window comes back when something is sent - or open ChainPush again. Quit from the Dock icon to stop.\" with title \"$APP\"" >/dev/null
  while true; do
    if [ -f "$SHOWFLAG" ]; then rm -f "$SHOWFLAG"; return 0; fi
    # nothing left to watch over
    kill -0 "${WATCHER:-0}" 2>/dev/null || return 1
    count="$(cat "$STATE" 2>/dev/null || echo 0)"
    [ "$count" != "$seen" ] && return 0
    now="$(date +%s)"
    [ "$now" -ge "$deadline" ] && return 0
    sleep 2
  done
}

more_menu() {
  local pick
  pick="$(osa -e "choose from list {\"Send a test notification\", \"Change settings\", \"Back\"} with prompt \"ChainPush\" default items {\"Back\"}")"
  case "$pick" in
    *test*)
      send "Chain" "If you can read this on your phone, it works." \
        && osa -e "display notification \"Test sent.\" with title \"$APP\"" >/dev/null \
        || say_error "That did not go through. Check the topic or the webhook under settings."
      ;;
    *settings*|*Change*)
      stop_watching
      setup && { watch_log & WATCHER=$!; }
      ;;
  esac
}

status_loop() {
  local sent button where
  while true; do
    sent="$(cat "$STATE" 2>/dev/null || echo 0)"
    if [ "$SERVICE" = "discord" ]; then where="Discord"; else where="ntfy / $TOPIC"; fi
    button="$(osa -e "display dialog \"Chain Push is running.\n\nWatching: $(basename "$LOG")\nSending to: $where\nSent so far: $sent\n\nHide keeps it running: the window returns when something is sent, or in half an hour.\nResets come from the game itself; ready checks need 'Marker in the chat log' ticked in the addon settings.\" buttons {\"Hide\", \"More...\", \"Stop\"} default button \"Hide\" with title \"$APP\" with icon note" \
                  -e 'button returned of result')"
    case "$button" in
      "Hide")
        hidden_wait || { stop_watching; return 0; }
        ;;
      "More...")
        more_menu
        ;;
      "Stop")
        stop_watching
        return 0
        ;;
      *)   # the dialog was closed rather than answered: keep working, hidden
        hidden_wait || { stop_watching; return 0; }
        ;;
    esac
  done
}

#--------------------------------------------------------------------------
main() {
  conf_load
  case "${1:-}" in
    --test)
      [ -n "$SERVICE" ] || { echo "no settings yet - open ChainPush.app once" >&2; exit 1; }
      send "Chain" "If you can read this on your phone, it works." \
        && echo "sent one test notification" || { echo "could not send" >&2; exit 1; }
      exit 0
      ;;
    --watch)
      [ -n "$LOG" ] || LOG="$(find_log)" || { echo "no WoWChatLog.txt found" >&2; exit 1; }
      echo "watching $LOG"
      watch_log
      exit 0
      ;;
    --settings-only)
      # Opened from the menu bar item: ask the questions, write the file, and
      # get out again. The watching is somebody else's job here.
      setup || exit 0
      conf_save
      # and let whoever is watching know there is something new to read
      printf 'reload\n' >> "$(dirname "$CONF")/command" 2>/dev/null
      exit 0
      ;;
  esac

  if [ -z "$SERVICE" ] || { [ "$SERVICE" = "ntfy" ] && [ -z "$TOPIC" ]; } \
     || { [ "$SERVICE" = "discord" ] && [ -z "$WEBHOOK" ]; }; then
    setup || exit 0
    conf_load
  fi

  if [ -z "$LOG" ] || [ ! -f "$LOG" ]; then
    LOG="$(find_log)" || LOG="$(choose_log)"
    if [ -z "$LOG" ] || [ ! -f "$LOG" ]; then
      say_error "No WoWChatLog.txt found.\n\nIt appears once chat logging has been on: type /chatlog in game, or turn on \"Marker in the chat log\" in the addon's settings, then open this again."
      exit 1
    fi
    conf_save
  fi

  # already watching in another window? bring that one back instead
  if [ -f "$PIDFILE" ]; then
    local other
    other="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$other" ] && kill -0 "$other" 2>/dev/null; then
      : > "$SHOWFLAG"
      osa -e "display notification \"Already running - bringing its window back.\" with title \"$APP\"" >/dev/null
      exit 0
    fi
  fi
  # and no leftovers from a copy that died without tidying up: two watchers
  # means two notifications for one reset. Everything but ourselves.
  local pid
  for pid in $(pgrep -f "chainpush.sh" 2>/dev/null); do
    if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
      kill "$pid" 2>/dev/null
    fi
  done
  echo $$ > "$PIDFILE"
  trap 'stop_watching; rm -f "$PIDFILE" "$SHOWFLAG"' EXIT INT TERM

  watch_log & WATCHER=$!
  status_loop
  rm -f "$PIDFILE" "$SHOWFLAG"
  exit 0
}

# sourced by the tests, run by the app
if [ "${LT_SOURCE_ONLY:-0}" != "1" ]; then
  main "$@"
fi
