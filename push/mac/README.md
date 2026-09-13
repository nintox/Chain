# Chain Push on macOS

## Just use the app

Download **`ChainPush.zip`** from the repository's
[Releases](../../../../releases), unzip it, and open `ChainPush.app`.

That is the whole install. The icon sits in the Dock the whole time it is
working; click it for the status, a test notification and the settings.

**macOS will stop you the first time**: right-click the app → **Open** →
**Open**. That happens because it is not signed with a paid certificate, and
once is enough.

The first run asks where to send: an ntfy topic or a Discord webhook. The
[page above](../README.md#1-get-the-app-on-your-phone) says how to get one.

**Closing the window does not stop it.** Click the Dock icon to bring it back.
**Quit**, in the Dock menu, is the only thing that stops it.

### Start it with the Mac

System Settings → General → Login Items → **+** → `ChainPush.app`.

---

## Building it from this folder instead

Everything below is for working on it. macOS has `osacompile` and usually a
`python3` already, so unlike Windows there is nothing to install first.

| | |
|---|---|
| `build-mac-app.command` | Double-click once. Makes `ChainPush.app` beside it. |
| `ChainPush.command` | The plain window, if you would rather not build an app. |
| `chainpush.sh` | The same job with no Python at all, using only what every Mac has. |
| `applet.applescript` | What the app is compiled from. |
| `mac_app.py` | Refreshes the copies inside a built app after a change. |

## Build it

Double-click **`build-mac-app.command`**.

It runs `osacompile`, which is already part of macOS. Nothing is downloaded
and nothing is installed. About two seconds later **`ChainPush.app`** appears
in this folder. Drag it to Applications or the Dock if you want it handy.

You build once. After that you just open the app.

**If macOS refuses to open it**: right-click the app → **Open** → **Open**.
That happens because it is not signed with a paid certificate, and once is
enough — it never asks again.

## Use it

Open the app. The icon sits in the Dock the whole time it is working, so
there is never a question of where it went. Click it for the status, a test
notification and the settings.

The first run asks where to send: an ntfy topic or a Discord webhook. The
[page above](../README.md#1-get-the-app-on-your-phone) says how to get one.

**Closing the window does not stop it.** Click the Dock icon to bring it back.
**Quit**, in the Dock menu, is the only thing that stops it.

## Start it with the Mac

System Settings → General → Login Items → **+** → `ChainPush.app`.

## No Python on this Mac

`chainpush.sh` does the same job with bash, curl and the Mac's own dialogs.
The app uses it on its own when there is no usable `python3`, so there is
usually nothing for you to do. By hand:

```bash
bash chainpush.sh --test     # send one notification and stop
bash chainpush.sh --watch    # watch and send, printing what it does
```

## After changing the code

```bash
python3 mac_app.py
```

copies `engine/chainpush.py`, `engine/chainpush_gui.py`, `chainpush.sh` and
the pictures back into the built app, so it is not left carrying yesterday's
copy. Inside the app they all sit flat in `Resources`, whichever folder they
came from — that is what the applet runtime expects.
