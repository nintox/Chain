#!/usr/bin/env python3
"""
Build ChainPush into one double-clickable program.

    python3 -m pip install pyinstaller pillow
    python3 build.py

Windows gives you  dist/ChainPush.exe
macOS   gives you  dist/ChainPush.app
Linux   gives you  dist/ChainPush

A program can only be built on the system it is for - there is no way to make
a Windows .exe on a Mac - so either run this on both machines, or let the
GitHub workflow in .github/workflows/chainpush.yml do it for you: it builds
both and hangs them off the release.

Nothing here is needed to *use* the program from source: double-click
ChainPush.command on macOS or ChainPush.bat on Windows and you get the same
window.
"""

import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PUSH = os.path.dirname(HERE)
ICONS = os.path.join(PUSH, "icons")
NAME = "ChainPush"


def icons():
    """Draw the icons if they are not already sitting here."""
    want = ["icon.ico", "icon.icns", "icon.png", "iconbytes.py"]
    if all(os.path.exists(os.path.join(ICONS, f)) for f in want):
        return True
    try:
        import PIL                                           # noqa: F401
    except ImportError:
        print("Pillow is not installed, so the icons cannot be drawn.")
        print("  python3 -m pip install pillow")
        return False
    subprocess.check_call([sys.executable, os.path.join(ICONS, "icon.py")])
    return True


def main():
    have_icons = icons()
    try:
        import PyInstaller                                   # noqa: F401
    except ImportError:
        print("PyInstaller is not installed.")
        print("  python3 -m pip install pyinstaller")
        return 1

    icon = None
    if have_icons:
        icon = os.path.join(ICONS,
                            "icon.icns" if sys.platform == "darwin" else "icon.ico")
        if not os.path.exists(icon):
            icon = None

    cmd = [sys.executable, "-m", "PyInstaller",
           "--noconfirm", "--clean", "--onefile", "--windowed",
           "--name", NAME,
           "--distpath", os.path.join(PUSH, "dist"),
           "--workpath", os.path.join(PUSH, "build"),
           "--specpath", os.path.join(PUSH, "build")]
    if icon:
        cmd += ["--icon", icon]
    # optional: a tray icon, if the machine building has the libraries
    for mod in ("pystray", "PIL"):
        try:
            __import__(mod)
            cmd += ["--hidden-import", mod]
        except ImportError:
            pass
    cmd.append(os.path.join(HERE, "chainpush_gui.py"))

    print(" ".join(cmd))
    subprocess.check_call(cmd)

    out = os.path.join(PUSH, "dist")
    print("\nbuilt into %s:" % out)
    for entry in sorted(os.listdir(out)):
        print("  " + entry)
    shutil.rmtree(os.path.join(PUSH, "build"), ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
