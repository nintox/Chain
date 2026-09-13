# Phone notifications

<p align="center">
  <img src="icons/icon.png" width="96" alt="Chain Push">
</p>

Chain Push sends a notification to your phone when the instance is reset or
somebody starts a ready check — the two moments you are usually not looking at
the screen.

**It is optional.** The addon works perfectly well without it, and nothing in
the addon depends on it being installed.

---

## Install

Three steps, and the middle one is the only one that takes any thought.

### 1. Get the app on your phone

**ntfy** — free, no account, either store. Open it, tap **+**, and make up a
topic name.

> Make it long and odd: `dan-wow-4471-kf`, not `wow`. The topic *is* the
> password. Anyone who guesses it reads your alerts.

Write that name down. That is all you need from the phone.

*Prefer Discord?* Skip ntfy. In a channel you can edit: **Edit channel** →
**Integrations** → **Webhooks** → **New webhook** → **Copy webhook URL**.
That URL is what you write down instead. Turn notifications on for that
channel on your phone, or you will not hear it.

### 2. Start the program on your computer

**Download the one file for your computer from
[Releases](../../../releases) and open it.** There is nothing to install
alongside it, nothing to tick, and no Python.

| | |
|---|---|
| **Windows** | `ChainPush.exe` — double-click it. The icon appears in the tray. |
| **macOS** | `ChainPush.zip` — unzip, open `ChainPush.app`. The icon appears in the Dock. |

Both are built by `.github/workflows/chainpush.yml` on GitHub's own runners,
because a program can only be built on the system it is for.

**The first time, the system will stop you.** Windows SmartScreen: **More
info** → **Run anyway**. macOS: right-click the app → **Open** → **Open**.
Neither is signed with a paid certificate; once is enough and it never asks
again.

Running it from the source instead - which is what the folders here are for -
is in **[`windows/`](windows/)** and **[`mac/`](mac/)**, one short page each.
**`engine/`** is the code both machines share and **`icons/`** the pictures;
neither is yours to open.

**If the system refuses to open it.** macOS: right-click the app → **Open** →
**Open**. Windows SmartScreen: **More info** → **Run anyway**. Both happen
because it is not signed with a paid certificate, and once is enough — it
never asks again.

### 3. Tell it where to send

The first run asks two questions: ntfy or Discord, and the topic or webhook
from step 1. Type it in, press **Send a test**, and your phone should buzz
within a second or two.

If it does, you are finished. Everything is remembered; you will not be asked
again.

### Turn on the fast path

One thing in the game, once. `/chain config` → tick **Instant alert
(screenshot)**.

Without it, alerts still arrive, but they can be *ten minutes* late.
[Why](#how-the-alert-actually-gets-out), if you want it.

---

## Living with it

**Where is it?** A **Dock icon on a Mac**, a **tray icon on Windows**. It is
there the whole time it is working, so there is never a question of where it
went. Click it for the status, a test, and the settings.

```
  Chain Push

  Watching - 3 sent
  Sending to ntfy topic my-secret-topic-4471
  Last: Instance reset - from Chain

  [ Close ]   [ Send a test ]   [ Settings... ]
```

**Is it working?** Click the icon; the first line says so in words. If the
watcher ever dies the app notices and restarts it, rather than sitting there
looking fine.

**Closing the window does not stop it.** Click the icon again to bring it
back. **Quit**, in the Dock menu or the tray menu, is the only thing that
stops it.

**Desktop notifications too**, with the Chain icon on them, so you can see it
working without picking the phone up.

**Start it with the computer?** macOS: System Settings → General → Login Items
→ **+** → `ChainPush.app`. Windows: press Win+R, type `shell:startup`, and
drop a shortcut to `windows/ChainPush.bat` in the folder that opens.

---

## Why it has to be a separate program

A WoW addon has **no network access of any kind** — no HTTP, no sockets. That
is true of every addon ever written, so nothing running inside the game can
reach ntfy, Discord or a phone. What the game *does* do is write files, and a
program outside the game can watch them.

```
WoW  ──writes──▶  a file  ──watched by──▶  Chain Push  ──▶  ntfy / Discord
```

It only reads files. It never touches WoW, never reads its memory, never sends
it anything, and does not automate any part of playing.

**Nothing to install** on either side. On Windows the tray icon is drawn with
what has been in Windows since 1996. On a Mac the app is built by `osacompile`,
which is part of macOS.

The Mac app is *built* rather than shipped because what comes out is an
**AppleScript applet** — a real Cocoa application. That matters: a shell script
in an app bundle cannot receive a click, which is why an earlier version had no
way back once you closed its window. A real app has a Dock icon you can click,
a Quit that works, and it costs nothing at all while it waits.

*(There was a menu bar version. It is gone: on a Mac with a full menu bar,
macOS quietly gave it a slot at the far left where nothing is visible, and the
scripting host burned half a processor drawing it. A Dock icon is always there,
always clickable, and free.)*

---

## How the alert actually gets out

The obvious route — the addon writes a line, this program reads it — turns out
to be slow, and the reason is worth knowing before you wonder why:

**WoW writes its chat log in 48 KiB blocks.** Nothing you can call from an
addon flushes it. Measured on a live session, a marker written at 18:57 reached
the disk at 19:00, and during a quiet spell at the summoning stone it can sit
there for ten minutes. Which is exactly when you need it.

**Screenshots are not buffered.** The client writes the file the moment it is
asked. So that is the signal: the addon takes **one** screenshot for a ready
check and **two** in quick succession for a reset, this program watches the
`Screenshots` folder, counts the batch, sends the push, and deletes the files
again. Two seconds, every time.

That is what **Instant alert (screenshot)** turns on. It costs a flash and a
"Screenshot captured" line in chat; that is the whole price. The chat-log
marker stays on as a slow second path, and the game's own reset messages are
still read from the log for what they are worth.

The `Screenshots` folder is created if it does not exist — WoW only makes it
the first time somebody takes one, and if you never have, it is not there.

## What gets sent

| | needs the addon's marker? |
|---|---|
| the instance has been reset | no |
| a reset failed, and why | no |
| someone started a ready check | yes |
| you levelled | yes, and it is off by default |

The first two are the game's own wording and are already in the log. A ready
check produces no chat line at all, so the addon writes one itself — into a
channel only your character is in, removed from your chat windows so you never
see it. `/chain signal` turns that on.

The same event is often announced twice — once by the game, once by somebody
else's addon. Repeats inside twenty seconds are dropped, so your phone buzzes
once.

## Chat logging has to be on

The log file only exists once WoW has been told to write it. Either type
`/chatlog` in game, or turn on **Marker in the chat log** in the addon's
settings, which does it for you. If the program cannot find the file, press
**Find**, and if that fails, **Browse** to it — it is in the `Logs` folder of
your WoW install.

---

## If the tray icon does not appear on Windows

The window opens and shuts and nothing is in the tray. That means the program
started and stopped, and `pythonw` - which is what keeps a console window from
sitting behind the game - has nowhere to print the reason.

It now tells you anyway: a message box with what went wrong, and the whole of
it in `crash.log` under `%LOCALAPPDATA%\ChainPush`. To watch it start with
everything on screen:

```
windows\ChainPush.bat debug
```

That runs it in the command window rather than behind it, so whatever it says
stays where you can read it.

---

## If you would rather not use the icon

| | |
|---|---|
| macOS, Dock | `mac/build-mac-app.command` once, then `ChainPush.app` |
| Windows, tray | `windows/ChainPush.bat`, or `pythonw windows/tray_win.py` |
| no icon, just a terminal | `python3 engine/chainpush.py --saved --serve` |
| a plain window | `python3 engine/chainpush_gui.py` |
| macOS dialogs only | `bash mac/chainpush.sh` |

**Settings...** in the Mac app opens whichever settings screen this Mac can
draw — the full window where there is a `python3` with a modern Tk, the Mac's
own dialogs where there is not. Apple's own `python3` carries Tk 8.5.9, which
on any recent macOS draws an empty white rectangle, so it is not trusted on
sight.

After changing any of the sources, `python3 mac/mac_app.py` copies them back
into the built app, so it is not left carrying yesterday's copy. Inside the
app everything sits flat in `Resources` whatever folder it came from - that is
what the applet runtime expects.

### The command line

```bash
python3 engine/chainpush.py --ntfy my-topic --test   # check it reaches you
python3 engine/chainpush.py --ntfy my-topic          # then leave it running
python3 engine/chainpush.py --discord https://discord.com/api/webhooks/...
python3 engine/chainpush.py --saved                  # use the window's settings
```

Without Python at all, the shell version takes two of the same switches:

```bash
bash mac/chainpush.sh --test     # send one notification and stop
bash mac/chainpush.sh --watch    # watch and send, printing what it does
```

| | |
|---|---|
| `--log PATH` | where `WoWChatLog.txt` is, if it is somewhere unusual |
| `--ntfy-server URL` | your own ntfy server |
| `--priority` | ntfy priority: `min`, `low`, `default`, `high`, `urgent` |
| `--quiet-for N` | seconds before the same event may repeat (default 20) |
| `--enable levelup` | turn on a rule that is off by default |
| `--test` | send one notification and stop |

Stop it with Ctrl+C.

Running your own ntfy server? Change the server field in the settings, or pass
`--ntfy-server`.

## Where the settings are kept

| | |
|---|---|
| Windows | `%APPDATA%\Chain\push.json` |
| macOS | `~/Library/Application Support/Chain/push.json` |
| Linux | `~/.config/chain/push.json` |

Plain text. Delete it to start over. Your topic or webhook is in it, so it is
worth the same care as any other password.

## Building the releases

A program can only be built on the system it is for, so
`.github/workflows/chainpush.yml` builds the Windows executable and a macOS
bundle side by side and attaches both to a release. Run it from the Actions
tab, or publish a release and it runs itself.

## What is in this folder

```
push/
  mac/        double-click ChainPush.command, or build the app once
  windows/    double-click ChainPush.bat
  engine/     the code both of them run - nothing to open
  icons/      the pictures, and the script that draws them
```

Four folders rather than eighteen files in a heap. The two at the top are the
only ones anybody opens; the two underneath are shared by both machines and
are there once rather than twice.
