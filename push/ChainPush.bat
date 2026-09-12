@echo off
rem Double-click me on Windows.
rem
rem It puts a Chain icon in the system tray, by the clock, and watches from
rem there. Right click the icon for the menu: a test notification, the log,
rem settings, quit. Nothing to install - the tray icon is drawn with what is
rem already in Windows.
rem
rem pythonw rather than python on purpose: no console window hanging around
rem behind the game.
cd /d "%~dp0"
where pythonw >nul 2>&1 && (start "" pythonw tray_win.py & exit /b)
where python  >nul 2>&1 && (start "" python  tray_win.py & exit /b)
echo Python 3 is not installed.
echo Get it from https://www.python.org/downloads/ - tick "Add python.exe to PATH".
pause
