#!/usr/bin/env python3
"""
Chain: phone notifications.

A WoW addon has no network access, so nothing inside the game can reach your
phone. What the game does do is write its chat to a log file. This program
watches that file and forwards the lines worth knowing about to ntfy or a
Discord webhook.

It only reads a file. It does not touch WoW, does not read its memory, does
not send it anything, and does not automate any part of playing.

    python3 chainpush.py --ntfy my-secret-topic-name

Run it on the machine you play on, while you play. Stop it with Ctrl+C.

If you would rather click than type, run chainpush_gui.py (or the ChainPush
program built from it): same engine, with a window and a settings screen.
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error

# ---------------------------------------------------------------- log file

# The usual places, newest flavour first. Give --log if yours is elsewhere.
CANDIDATES = [
    r"C:\Program Files (x86)\World of Warcraft\_classic_era_\Logs\WoWChatLog.txt",
    r"C:\Program Files\World of Warcraft\_classic_era_\Logs\WoWChatLog.txt",
    r"C:\Program Files (x86)\World of Warcraft\_anniversary_\Logs\WoWChatLog.txt",
    r"C:\Program Files\World of Warcraft\_anniversary_\Logs\WoWChatLog.txt",
    r"C:\World of Warcraft\_classic_era_\Logs\WoWChatLog.txt",
    "/Applications/World of Warcraft/_classic_era_/Logs/WoWChatLog.txt",
    "/Applications/World of Warcraft/_anniversary_/Logs/WoWChatLog.txt",
    os.path.expanduser("~/Applications/World of Warcraft/_classic_era_/Logs/WoWChatLog.txt"),
]


def find_log(given=None):
    if given:
        return given
    for path in CANDIDATES:
        if os.path.exists(path):
            return path
    return None


# ---------------------------------------------------------------- settings

APP = "Chain"


def config_path():
    """Where the settings live, per platform, outside the WoW folder."""
    if sys.platform.startswith("win"):
        base = os.environ.get("APPDATA") or os.path.expanduser("~")
        return os.path.join(base, APP, "push.json")
    if sys.platform == "darwin":
        return os.path.expanduser("~/Library/Application Support/%s/push.json" % APP)
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, APP.lower(), "push.json")


DEFAULTS = {
    "service": "ntfy",           # or "discord"
    "topic": "",                 # the ntfy topic: your secret, treat it as one
    "server": "https://ntfy.sh",
    "webhook": "",               # the Discord webhook URL
    "log": "",                   # blank means: look in the usual places
    "priority": "high",
    "quiet_for": 20.0,           # seconds before the same event may repeat
    "extra": [],                 # rule names that are off by default
    "autostart": True,           # start watching as soon as the window opens
}


def old_config_paths():
    """Every name this program has had, newest first. A rename should never
    cost somebody the topic they set up months ago."""
    out = []
    for old in ("LevelBar", "LevelTracker"):
        if sys.platform.startswith("win"):
            base = os.environ.get("APPDATA") or os.path.expanduser("~")
            out.append(os.path.join(base, old, "push.json"))
        elif sys.platform == "darwin":
            out.append(os.path.expanduser(
                "~/Library/Application Support/%s/push.json" % old))
        else:
            base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
            out.append(os.path.join(base, old.lower(), "push.json"))
    return out


def load_config():
    cfg = dict(DEFAULTS)
    # a rename should not cost you your settings
    if not os.path.exists(config_path()):
        for old in old_config_paths():
            if not os.path.exists(old):
                continue
            try:
                os.makedirs(os.path.dirname(config_path()), exist_ok=True)
                with open(old, encoding="utf-8") as src:
                    with open(config_path(), "w", encoding="utf-8") as dst:
                        dst.write(src.read())
            except OSError:
                pass
            break
    try:
        with open(config_path(), "r", encoding="utf-8") as fh:
            stored = json.load(fh)
        if isinstance(stored, dict):
            for key in DEFAULTS:
                if key in stored:
                    cfg[key] = stored[key]
    except (OSError, ValueError):
        pass
    return cfg


def save_config(cfg):
    path = config_path()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(cfg, fh, indent=2)
        return True
    except OSError:
        return False


# ----------------------------------------------------------------- runtime

# The watcher and the thing you can see - a menu bar item on a Mac, a tray
# icon on Windows - are two processes, because the only way to get a real menu
# bar item without asking anyone to install anything is to let the system's own
# scripting host draw it. They talk through three small files rather than a
# socket: nothing to bind, nothing to leak, and you can read the state with
# `cat` when something is wrong.
def runtime_dir():
    d = os.path.dirname(config_path())
    try:
        os.makedirs(d, exist_ok=True)
    except OSError:
        pass
    return d


def state_file(name):
    return os.path.join(runtime_dir(), name)


def write_status(**fields):
    """Merge fields into status.json. Written whole, renamed into place, so a
    reader never sees half a file."""
    path = state_file("status.json")
    cur = read_status()
    cur.update(fields)
    cur["stamp"] = time.time()
    tmp = path + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(cur, fh)
        os.replace(tmp, path)
    except OSError:
        pass
    return cur


def read_status():
    try:
        with open(state_file("status.json"), encoding="utf-8") as fh:
            got = json.load(fh)
        return got if isinstance(got, dict) else {}
    except (OSError, ValueError):
        return {}


def send_command(word):
    """From the menu bar or tray to the watcher: one word per line."""
    try:
        with open(state_file("command"), "a", encoding="utf-8") as fh:
            fh.write(str(word).strip() + "\n")
        return True
    except OSError:
        return False


def take_commands():
    """Read and clear. Returns a list of words, oldest first."""
    path = state_file("command")
    # the common case by a mile: no file, nothing to do, and no reason to
    # build an exception for it once a second
    if not os.path.exists(path):
        return []
    try:
        with open(path, encoding="utf-8") as fh:
            words = [w.strip() for w in fh if w.strip()]
        os.remove(path)
        return words
    except (OSError, ValueError):
        return []


def log_event(kind, text):
    """A line the agent can tail. Kept short; it is a feed, not a record."""
    path = state_file("events.log")
    try:
        with open(path, "a", encoding="utf-8") as fh:
            fh.write("%.3f\t%s\t%s\n" % (time.time(), kind, text))
        if os.path.getsize(path) > 200000:
            with open(path, encoding="utf-8") as fh:
                tail = fh.readlines()[-200:]
            with open(path, "w", encoding="utf-8") as fh:
                fh.writelines(tail)
    except OSError:
        pass


# ---------------------------------------------------------------- what to send

# Each rule is (name, regex, title, default on/off). The addon's own marker
# lines start with LTPUSH; the rest are the game's own wording, which is why
# the reset ones work whether or not you turn signalling on in the addon.
RULES = [
    ("readycheck", re.compile(r"LTPUSH readycheck (.+)"), "Ready check", True),
    ("reset",      re.compile(r"LTPUSH reset (.+)"),      "Instance reset", True),
    ("reset2",     re.compile(r"(.+) has been reset\."),  "Instance reset", True),
    ("failed",     re.compile(r"Cannot reset (.+?)\.\s+There are (.+?)\."),
                   "Reset failed", True),
    ("levelup",    re.compile(r"LTPUSH level (.+)"),      "Level up", False),
]

# Lines the game writes are prefixed with a timestamp; strip it for the message
TIMESTAMP = re.compile(r"^\d+/\d+ \d+:\d+:\d+\.\d+\s*")
# Channel lines look like: [1. LTNintoz] Nintoz: LTPUSH reset Stockades is open
SPEAKER = re.compile(r"^\[[^\]]*\]\s*[^:]+:\s*")


def clean(line):
    line = TIMESTAMP.sub("", line.strip())
    return SPEAKER.sub("", line).strip()


def active_rules(cfg):
    extra = set(cfg.get("extra") or [])
    return [r for r in RULES if r[3] or r[0] in extra]


def match(text, rules):
    """The first rule this line trips, as (title, body), or None."""
    for name, pattern, title, _ in rules:
        m = pattern.search(text)
        if not m:
            continue
        if name == "failed":
            return title, "%s: %s" % (m.group(1).strip(), m.group(2).strip())
        return title, m.group(1).strip()
    return None


# ---------------------------------------------------------------- sending

def send_ntfy(server, topic, title, body, priority="high"):
    url = "%s/%s" % ((server or "https://ntfy.sh").rstrip("/"), topic)
    req = urllib.request.Request(
        url,
        data=body.encode("utf-8"),
        headers={
            "Title": title,
            "Priority": priority,
            "Tags": "video_game",
        },
    )
    urllib.request.urlopen(req, timeout=10).read()


def send_discord(webhook, title, body):
    payload = json.dumps({"content": "**%s** - %s" % (title, body)})
    req = urllib.request.Request(
        webhook,
        data=payload.encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    urllib.request.urlopen(req, timeout=10).read()


def notify(cfg, title, body):
    """Send one notification by whichever service is configured."""
    if cfg.get("service") == "discord":
        if not cfg.get("webhook"):
            raise ValueError("no Discord webhook set")
        send_discord(cfg["webhook"], title, body)
    else:
        if not cfg.get("topic"):
            raise ValueError("no ntfy topic set")
        send_ntfy(cfg.get("server"), cfg["topic"], title, body,
                  cfg.get("priority", "high"))


def describe(cfg):
    """One line saying where notifications are going."""
    if cfg.get("service") == "discord":
        hook = cfg.get("webhook") or ""
        return "Discord webhook " + (hook[:40] + "..." if len(hook) > 43 else hook)
    return "ntfy: %s/%s" % ((cfg.get("server") or "").rstrip("/"), cfg.get("topic") or "")


# ---------------------------------------------------------------- the loop

def follow(path, from_start=False, stop=None):
    """Yield new lines, surviving the file being rotated or replaced."""
    handle = open(path, "r", encoding="utf-8", errors="replace")
    if not from_start:
        handle.seek(0, os.SEEK_END)
    inode = os.fstat(handle.fileno()).st_ino
    try:
        while not (stop and stop()):
            line = handle.readline()
            if line:
                yield line
                continue
            time.sleep(0.5)
            # WoW starts a fresh log on some sessions; pick the new one up
            try:
                if os.stat(path).st_ino != inode:
                    handle.close()
                    handle = open(path, "r", encoding="utf-8", errors="replace")
                    inode = os.fstat(handle.fileno()).st_ino
            except OSError:
                pass
    finally:
        handle.close()


# ------------------------------------------------------------ instant alert

# The chat log is written in 48 KiB blocks, so a marker can sit unwritten in
# the game's memory for ten minutes - long enough that the reset you were
# being told about is over. A screenshot is not buffered: the client puts the
# file on disk the moment the addon asks for one. So the addon takes one for a
# ready check and two for a reset, and this counts the batch, sends the push,
# and deletes the files again. They were signals, not pictures.
def shots_dir(log_path):
    """.../Logs/WoWChatLog.txt  ->  .../Screenshots"""
    if not log_path:
        return None
    return os.path.join(os.path.dirname(os.path.dirname(log_path)), "Screenshots")


def ensure_shots_dir(log_path):
    """WoW only makes the folder the first time somebody takes a picture, so
    it is normally missing. It is happy to write into one already there."""
    d = shots_dir(log_path)
    if not d:
        return None
    try:
        os.makedirs(d, exist_ok=True)
        return d if os.path.isdir(d) else None
    except OSError:
        return None


def watch_shots(log_path, on_signal, stop=None, poll=1.0, settle=2.0):
    """
    Poll the screenshot folder. Calls on_signal(count, title) per batch and
    removes the files. Runs until stop() is true; meant for its own thread.
    """
    d = ensure_shots_dir(log_path)
    if not d:
        return
    seen = set()
    try:
        seen = set(os.listdir(d))
    except OSError:
        pass
    while not (stop and stop()):
        time.sleep(poll)
        try:
            now = set(os.listdir(d))
        except OSError:
            continue
        fresh = now - seen
        if not fresh:
            seen = now
            continue
        # let the rest of the batch land before deciding what it means: two
        # pictures mean a reset, one means a ready check
        time.sleep(settle)
        try:
            now = set(os.listdir(d))
        except OSError:
            now = fresh
        fresh = now - seen
        seen = now
        n = len(fresh)
        if n <= 0:
            continue
        title = "Instance reset" if n >= 2 else "Ready check"
        try:
            on_signal(n, title)
        finally:
            for name in fresh:
                try:
                    os.remove(os.path.join(d, name))
                except OSError:
                    pass
                seen.discard(name)


def watch(cfg, on_event, stop=None, on_error=None, from_start=False,
          instant=True):
    """
    Follow the log and send what matters. `on_event(title, body)` is called
    after each notification goes out; `on_error(message)` when one does not.
    Blocks until `stop()` returns true, so the window runs it in a thread and
    the command line runs it on the spot.

    The screenshot signal runs alongside it in its own thread, because the
    chat log is far too slow to be the only way in.
    """
    path = find_log(cfg.get("log"))
    if not path:
        raise FileNotFoundError("no WoWChatLog.txt found")
    rules = active_rules(cfg)
    if instant:
        import threading

        def signalled(n, title):
            try:
                notify(cfg, title, "from Chain")
                if on_event:
                    on_event(title, "instant alert")
            except Exception as err:
                if on_error:
                    on_error(str(err))

        threading.Thread(target=watch_shots,
                         args=(path, signalled),
                         kwargs={"stop": stop or (lambda: False)},
                         daemon=True).start()
    quiet = float(cfg.get("quiet_for", 20) or 0)
    last = {}
    for raw in follow(path, from_start=from_start, stop=stop):
        hit = match(clean(raw), rules)
        if not hit:
            continue
        title, body = hit
        now = time.time()
        # the same reset is announced by the system and by other people's
        # addons; one phone buzz is enough
        if now - last.get(title + body, 0) < quiet:
            continue
        last[title + body] = now
        try:
            notify(cfg, title, body)
            if on_event:
                on_event(title, body)
        except Exception as err:            # network, bad topic, dead webhook
            if on_error:
                on_error(str(err))
    return path


# ------------------------------------------------------------------- serve

def serve(cfg=None, on_line=None):
    """
    Watch, and keep status.json and events.log up to date so a menu bar item
    or a tray icon can show what is happening without knowing anything about
    how any of it works. Returns when told to quit.
    """
    import threading

    cfg = cfg or load_config()
    stopping = threading.Event()
    counted = {"sent": 0, "failed": 0}

    def say(kind, text):
        log_event(kind, text)
        if on_line:
            on_line("%s  %s" % (time.strftime("%H:%M:%S"), text))

    path = find_log(cfg.get("log"))
    write_status(running=True, pid=os.getpid(), since=time.time(),
                 sent=0, failed=0, target=describe(cfg), log=path or "",
                 last="", error="")
    say("start", "watching %s" % (path or "nothing - no log found"))
    say("start", "sending to %s" % describe(cfg))

    def on_event(title, body):
        counted["sent"] += 1
        write_status(sent=counted["sent"], last="%s - %s" % (title, body),
                     lastAt=time.time(), error="")
        say("sent", "%s - %s" % (title, body))

    def on_error(err):
        counted["failed"] += 1
        write_status(failed=counted["failed"], error=str(err))
        say("error", "could not send: %s" % err)

    def run():
        try:
            watch(cfg, on_event=on_event, on_error=on_error,
                  stop=stopping.is_set)
        except Exception as err:
            write_status(running=False, error=str(err))
            say("error", "stopped: %s" % err)
            stopping.set()

    worker = threading.Thread(target=run, daemon=True)
    worker.start()

    # The heartbeat is the point: a status file that stops moving is how the
    # menu bar knows the watcher died rather than went quiet.
    # The status file is what the menu bar reads, so it has to say the watcher
    # is alive - but writing it every second means a read, a JSON dump and a
    # rename every second, for hours, to say nothing happened. Every five is
    # plenty: the menu bar calls it dead after fifteen.
    beat = 0
    try:
        while not stopping.is_set():
            time.sleep(1)
            if time.time() - beat >= 5:
                beat = time.time()
                write_status(alive=beat)
            for word in take_commands():
                if word == "quit":
                    say("stop", "told to quit")
                    stopping.set()
                elif word == "test":
                    try:
                        notify(cfg, "Chain", "This is a test. It works.")
                        on_event("Chain", "test")
                    except Exception as err:
                        on_error(err)
                elif word == "reload":
                    cfg = load_config()
                    write_status(target=describe(cfg))
                    say("start", "settings reloaded: %s" % describe(cfg))
                elif word == "settings":
                    # Whatever the launcher decided can show a settings screen
                    # on this machine - the window where Tk works, the Mac's
                    # own dialogs where it does not. The watcher does not need
                    # to know which; it just runs what it was handed.
                    opener = os.environ.get("CHAIN_SETTINGS_CMD")
                    if opener:
                        import subprocess
                        try:
                            subprocess.Popen(opener, shell=True)
                        except Exception as err:
                            say("error", "could not open the settings: %s" % err)
                    else:
                        say("error", "no settings screen on this machine")
    except KeyboardInterrupt:
        stopping.set()
    write_status(running=False, alive=time.time())
    say("stop", "stopped")


# ---------------------------------------------------------------- command line

def main():
    ap = argparse.ArgumentParser(description="Send Chain events to your phone")
    ap.add_argument("--log", help="path to WoWChatLog.txt")
    ap.add_argument("--ntfy", help="ntfy topic name")
    ap.add_argument("--ntfy-server", default="https://ntfy.sh",
                    help="ntfy server (default: https://ntfy.sh)")
    ap.add_argument("--discord", help="Discord webhook URL")
    ap.add_argument("--priority", default="high",
                    help="ntfy priority: min, low, default, high, urgent")
    ap.add_argument("--quiet-for", type=float, default=20,
                    help="seconds to ignore a repeat of the same event")
    ap.add_argument("--enable", default="", help="comma separated extra rules to turn on")
    ap.add_argument("--test", action="store_true", help="send one notification and exit")
    ap.add_argument("--serve", action="store_true",
                    help="watch, and keep the status file the menu bar item reads")
    ap.add_argument("--saved", action="store_true",
                    help="use the settings saved by the ChainPush window")
    args = ap.parse_args()

    if args.saved:
        cfg = load_config()
        if args.log:
            cfg["log"] = args.log
    else:
        if not args.ntfy and not args.discord:
            ap.error("give --ntfy TOPIC, --discord WEBHOOK_URL, or --saved")
        cfg = dict(DEFAULTS)
        cfg.update({
            "service": "discord" if args.discord else "ntfy",
            "topic": args.ntfy or "",
            "server": args.ntfy_server,
            "webhook": args.discord or "",
            "log": args.log or "",
            "priority": args.priority,
            "quiet_for": args.quiet_for,
            "extra": [x.strip() for x in args.enable.split(",") if x.strip()],
        })

    if args.test:
        notify(cfg, "Chain", "If you can read this on your phone, it works.")
        print("sent one test notification to %s" % describe(cfg))
        return

    if args.serve:
        serve(cfg, on_line=lambda line: print(line, flush=True))
        return

    path = find_log(cfg.get("log"))
    if not path:
        print("Could not find WoWChatLog.txt. Pass --log with the full path.\n"
              "It lives in the Logs folder of your WoW install, and only exists\n"
              "once chat logging has been on. Type /chatlog in game, or turn on\n"
              "\"Write a marker to the chat log\" in the addon's settings.",
              file=sys.stderr)
        sys.exit(1)

    print("watching %s" % path)
    print("sending to %s" % describe(cfg))
    print("rules: %s" % ", ".join(r[0] for r in active_rules(cfg)))
    watch(cfg,
          on_event=lambda t, b: print("  sent: %s - %s" % (t, b)),
          on_error=lambda e: print("  could not send: %s" % e, file=sys.stderr))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print()
