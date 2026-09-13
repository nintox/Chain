@echo off
rem Double-click me on Windows.
rem
rem It puts a Chain icon in the system tray, by the clock, and watches from
rem there. Right click the icon for the menu: a test notification, the log,
rem settings, quit. Nothing to install - the tray icon is drawn with what is
rem already in Windows.
rem
rem pythonw rather than python on purpose: no console window hanging around
rem behind the game. The cost of that is that pythonw has nowhere to print to,
rem so if something goes wrong you get a message box and a crash.log rather
rem than a window that shuts before you can read it.
rem
rem   ChainPush.bat debug
rem
rem runs it in this window instead, with everything it says on screen.
cd /d "%~dp0"
if /I "%~1"=="debug" goto debug

where pythonw >nul 2>&1 && (start "" pythonw tray_win.py & exit /b)
where python  >nul 2>&1 && (start "" python  tray_win.py & exit /b)
echo Python 3 is not installed.
echo Get it from https://www.python.org/downloads/ - tick "Add python.exe to PATH".
pause
exit /b

:debug
where python >nul 2>&1 || (
  echo Python 3 is not installed.
  echo Get it from https://www.python.org/downloads/ - tick "Add python.exe to PATH".
  pause
  exit /b
)
echo Starting with the messages showing. Close this window to stop it.
echo.
python tray_win.py
echo.
echo It has stopped. Whatever is above this line is the reason.
pause
