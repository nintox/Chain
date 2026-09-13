# Chain Push on Windows

## Just use the program

Download **`ChainPush.exe`** from the repository's
[Releases](../../../../releases), and double-click it.

That is the whole install. Nothing else to get, nothing to tick, no Python.
The Chain icon appears in the tray next to the clock; right-click it for the
menu: status, a test notification, the log, settings, quit.

**Windows will stop you the first time.** SmartScreen says it does not
recognise the program: **More info** → **Run anyway**. That happens because
it is not signed with a paid certificate, and once is enough.

The first run asks where to send: an ntfy topic or a Discord webhook. The
[page above](../README.md#1-get-the-app-on-your-phone) says how to get one.
After that it never asks again.

### Start it with Windows

Press **Win+R**, type `shell:startup`, and drop a shortcut to `ChainPush.exe`
into the folder that opens.

---

## Running it from this folder instead

Everything below is for working on it, or for running the source without
downloading anything. You need **Python 3** for any of it.

| | |
|---|---|
| `ChainPush.bat` | Starts the tray from this folder. |
| `tray_win.py` | The tray icon itself. It is what the .bat starts. |

Double-click `ChainPush.bat`, or from a terminal:

```
ChainPush.bat debug
```

In PowerShell rather than the old command prompt, the same line needs `.\` in
front of it - PowerShell will not run anything from the folder you are
standing in without being told to:

```
.\ChainPush.bat debug
```

Either way it runs in the window rather than behind it, so whatever is on
screen when it stops is the reason.

> **Windows will answer when you type `python` whether or not it is there.**
> What answers is an App Execution Alias - a stub Windows ships that exists,
> that runs, and that does nothing but tell you to go to the Microsoft Store.
> The .bat does not take its word for it: it runs Python and checks that it
> works, so "not installed" means not installed. If you would rather not see
> the stub at all: Settings -> Apps -> Advanced app settings -> App execution
> aliases, and turn the `python.exe` ones off.
>
> The real thing is at [python.org](https://www.python.org/downloads/). Tick
> **Add python.exe to PATH** on the first screen.

## If it opens and shuts

A `crash.log` is written under `%LOCALAPPDATA%\ChainPush` whether or not you
were watching - the .exe writes it too.

## Building the .exe yourself

```
python3 -m pip install pyinstaller pillow
python3 ..\engine\build.py
```

writes `..\dist\ChainPush.exe`. The one on Releases is this, built the same
way by `.github/workflows/chainpush.yml` on a GitHub runner - which is also
how the macOS app gets built, since neither can be built on the other's
machine.
