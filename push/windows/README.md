# Chain Push on Windows

Two files. You only ever touch the first one.

| | |
|---|---|
| `ChainPush.bat` | Double-click it. That is the whole install. |
| `tray_win.py` | The tray icon itself. It is what the .bat starts. |

## Start it

Double-click **`ChainPush.bat`**.

The Chain icon appears in the tray, next to the clock. Right-click it for the
menu: status, a test notification, the log, settings, quit.

Nothing is installed and nothing is downloaded — the tray icon is drawn with
what is already in Windows. You do need **Python 3**; if it is missing the
window says so and points at [python.org](https://www.python.org/downloads/).
Tick **Add python.exe to PATH** when you install it.

The first time it starts it asks where to send: an ntfy topic or a Discord
webhook. The [page above](../README.md#1-get-the-app-on-your-phone) says how
to get one. After that it never asks again.

## If it opens and shuts

Run it so you can read what it says:

```
ChainPush.bat debug
```

That runs it in the window rather than behind it. Whatever is on screen when
it stops is the reason.

There is also a `crash.log` under `%LOCALAPPDATA%\Chain
Push` — it is written whether or not you were watching.

## Start it with Windows

Press **Win+R**, type `shell:startup`, and drop a shortcut to
`ChainPush.bat` into the folder that opens.

## A single .exe instead

If you would rather keep one file somewhere else:

```
python3 -m pip install pyinstaller pillow
python3 ..\engine\build.py
```

which writes `..\dist\ChainPush.exe`. The release on GitHub is the same thing,
built the same way.
