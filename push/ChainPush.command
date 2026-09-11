#!/bin/bash
# Double-click me on macOS. Opens the Chain Push window.
cd "$(dirname "$0")" || exit 1
if command -v python3 >/dev/null 2>&1; then
  exec python3 chainpush_gui.py
fi
osascript -e 'display dialog "Python 3 is not installed.\n\nInstall it from python.org, then double-click this again." buttons {"OK"} default button 1 with icon caution'
