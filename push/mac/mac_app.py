#!/usr/bin/env python3
"""
Refresh the copies of the program inside ChainPush.app.

The app itself is built by build-mac-app.command, which runs osacompile on
applet.applescript - that has to happen on a Mac. This only refreshes what the
app carries, so after changing chainpush.py, chainpush_gui.py or chainpush.sh
the app is not left holding yesterday's copy.

    python3 mac_app.py

If the app has not been built yet there is nothing to refresh, and it says so
rather than pretending.
"""

import os
import shutil
import stat
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PUSH = os.path.dirname(HERE)
APP = os.path.join(HERE, "ChainPush.app")
RES = os.path.join(APP, "Contents", "Resources")
EXE = os.path.join(APP, "Contents", "MacOS", "applet")

# Inside the app everything sits flat in Resources - that is what the applet
# runtime expects - so this is a map from where each file lives in the
# repository to the one name it answers to in there.
CARRIED = [
    ("engine", "chainpush.py"),
    ("engine", "chainpush_gui.py"),
    ("mac", "chainpush.sh"),
    ("icons", "iconbytes.py"),
    ("icons", "notify.png"),
    ("icons", "icon.png"),
]


def source(where, name):
    return os.path.join(PUSH, where, name)


def main():
    if not os.path.isdir(APP):
        print("ChainPush.app has not been built yet - run "
              "build-mac-app.command on a Mac first", file=sys.stderr)
        return 1
    os.makedirs(RES, exist_ok=True)
    for where, name in CARRIED:
        src = source(where, name)
        if not os.path.exists(src):
            print("missing " + name, file=sys.stderr)
            return 1
        shutil.copy2(src, os.path.join(RES, name))
    icon = source("icons", "icon.icns")
    if os.path.exists(icon):
        # applet.icns is the name the AppleScript applet runtime looks for
        shutil.copy2(icon, os.path.join(RES, "applet.icns"))

    # the shell version has to stay executable; the applet binary is Apple's
    path = os.path.join(RES, "chainpush.sh")
    if os.path.exists(path):
        mode = os.stat(path).st_mode
        os.chmod(path, mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    print("ChainPush.app refreshed:")
    for root, _dirs, files in os.walk(APP):
        for f in sorted(files):
            full = os.path.join(root, f)
            print("  %-46s %6d bytes" % (os.path.relpath(full, HERE),
                                         os.path.getsize(full)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
