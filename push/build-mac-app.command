#!/bin/bash
# Build ChainPush.app. Double-click this file once; after that you use the
# app it makes and never come back here.
#
# It uses osacompile, which is part of macOS - every Mac has had it for
# twenty years. Nothing is downloaded and nothing is installed. What comes out
# is an AppleScript applet: a real Cocoa application, with a Dock icon that
# can be clicked, a Quit that works, and no cost at all while it waits.
#
# The previous app was a shell script in an app bundle. A shell script cannot
# receive a click, which is why there was no way back once you closed the
# window. This fixes that at the root rather than working around it.

set -u
cd "$(dirname "$0")" || exit 1
HERE="$(pwd)"
APP="$HERE/ChainPush.app"

echo "Building ChainPush.app in:"
echo "  $HERE"
echo

if [ ! -f "$HERE/applet.applescript" ]; then
  echo "applet.applescript is missing - this script has to sit next to it."
  echo "Press return to close."
  read -r _
  exit 1
fi

# Anything running from the old app has to go, or the new one fights it
pkill -f "chainpush.py --saved --serve" 2>/dev/null
pkill -f "menubar.js" 2>/dev/null
pkill -f "chainpush.sh" 2>/dev/null
sleep 1

rm -rf "$APP"

# Stay open, so it is still there after the run handler finishes and can take
# a click in the Dock. Not every macOS spells the flag the same way, so if -s
# is refused we build without it and say so rather than producing something
# that quits the moment it starts.
STAYOPEN=yes
if ! /usr/bin/osacompile -s -o "$APP" "$HERE/applet.applescript" 2>/dev/null; then
  STAYOPEN=no
  if ! /usr/bin/osacompile -o "$APP" "$HERE/applet.applescript"; then
    echo "osacompile would not build it. The error is above."
    echo "Press return to close."
    read -r _
    exit 1
  fi
fi
echo "compiled  (stay open: $STAYOPEN)"

RES="$APP/Contents/Resources"
mkdir -p "$RES"
for f in chainpush.py chainpush_gui.py chainpush.sh iconbytes.py notify.png icon.png; do
  [ -f "$HERE/$f" ] && cp -f "$HERE/$f" "$RES/$f"
done
chmod +x "$RES/chainpush.sh" 2>/dev/null

# Its own icon rather than the generic AppleScript one.
#
# Replacing applet.icns is not enough, and this is why: osacompile also ships
# a compiled asset catalogue, Assets.car, holding the generic applet icon, and
# names it in the plist as CFBundleIconName. Modern macOS prefers that over
# CFBundleIconFile and never looks at the .icns at all. So the catalogue and
# the key that points at it both have to go.
if [ -f "$HERE/icon.icns" ]; then
  for existing in "$RES"/*.icns; do
    [ -e "$existing" ] && cp -f "$HERE/icon.icns" "$existing"
  done
  cp -f "$HERE/icon.icns" "$RES/applet.icns"
  rm -f "$RES/Assets.car"
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$APP/Contents/Info.plist" 2>/dev/null
  echo "icon      set (asset catalogue removed)"
fi

PLIST="$APP/Contents/Info.plist"
set_plist() {
  /usr/libexec/PlistBuddy -c "Set :$1 $2" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PLIST" 2>/dev/null
}
set_plist CFBundleName "Chain Push"
set_plist CFBundleDisplayName "Chain Push"
set_plist CFBundleIdentifier "no.chain.push"
set_plist CFBundleShortVersionString "1.1.0"
set_plist CFBundleIconFile "applet"
# A Dock icon, deliberately: it is how you know it is running and how you get
# the window back. LSUIElement would hide it, which is the bug we came from.
/usr/libexec/PlistBuddy -c "Delete :LSUIElement" "$PLIST" 2>/dev/null
echo "plist     named and identified"

# macOS caches what it thinks a bundle looks like, and it is stubborn about
# it: a new icon inside an existing bundle can go unnoticed until the next
# time you log in. The bundle has to look changed, LaunchServices has to be
# told, and the Dock has to be made to let go of the copy it is holding.
#
# A custom-icon flag left over from before also wins over the bundle's own
# icon, so anything like that goes first.
rm -f "$APP/Icon"$'\r' 2>/dev/null
/usr/bin/xattr -d com.apple.FinderInfo "$APP" 2>/dev/null

# Everything above changed files inside a signed bundle, so the signature no
# longer matches what is there. Sign it again, ad hoc, where the tools exist;
# where they do not, drop the signature rather than leave a broken one, which
# macOS refuses to launch outright.
if /usr/bin/codesign --force --sign - "$APP" 2>/dev/null; then
  echo "signed    again (ad hoc)"
else
  rm -rf "$APP/Contents/_CodeSignature"
  echo "signed    no - signature removed instead"
fi
touch "$APP" "$PLIST" "$RES/applet.icns" 2>/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" >/dev/null 2>&1
# the Dock redraws in a second and loses nothing: your windows and spaces are
# untouched, it is only the row of icons that comes back
killall Dock 2>/dev/null
echo "icon      cache cleared"

echo
echo "Done:  $APP"
echo
echo "Open it. The icon appears in the Dock and stays there."
echo "  click the Dock icon   status, a test, settings"
echo "  Dock menu - Quit      stops it"
if [ "$STAYOPEN" = "no" ]; then
  echo
  echo "NOTE: this macOS would not take the stay-open flag, so the app may"
  echo "quit straight after starting the watcher. The watching still happens."
fi
echo
echo "Press return to close this window."
read -r _
