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
rem   ChainPush.bat debug        (PowerShell: .\ChainPush.bat debug)
rem
rem runs it in this window instead, with everything it says on screen.
cd /d "%~dp0"
if /I "%~1"=="debug" goto debug

call :find
if defined PYW (start "" %PYW% tray_win.py & exit /b)
if defined PY  (start "" %PY%  tray_win.py & exit /b)
goto nopython

:debug
call :find
if not defined PY (
  if defined PYW set "PY=%PYW%"
)
if not defined PY goto nopython
echo Starting with the messages showing. Close this window to stop it.
echo.
%PY% tray_win.py
echo.
echo It has stopped. Whatever is above this line is the reason.
pause
exit /b

rem ------------------------------------------------------------------------
rem Finding a Python that is actually there.
rem
rem "where python" is not the test, and believing it was is what made this
rem open and shut without a word. Windows ships an App Execution Alias - a
rem stub at %LOCALAPPDATA%\Microsoft\WindowsApps\python.exe that exists, that
rem "where" finds, and that does nothing but print "Python was not found" and
rem point at the Microsoft Store. So the script found Python, started it, and
rem the window that opened was the Store's apology, gone before you could read
rem it.
rem
rem The only test that means anything is to run the thing and see if it works.
rem Four candidates, in the order you would want them: windowless first, then
rem the py launcher, which is what an installer from python.org leaves behind
rem whether or not PATH was ticked.
:find
set "PYW="
set "PY="
pythonw -c "import sys" >nul 2>&1 && set "PYW=pythonw"
if not defined PYW ( pyw -3 -c "import sys" >nul 2>&1 && set "PYW=pyw -3" )
python -c "import sys" >nul 2>&1 && set "PY=python"
if not defined PY ( py -3 -c "import sys" >nul 2>&1 && set "PY=py -3" )
exit /b

:nopython
echo Python 3 is not installed.
echo.
echo Windows may well have answered when you typed "python" - that is the
echo Microsoft Store shortcut standing in for it, not Python. It exists, it
echo runs, and all it does is send you to the Store.
echo.
echo Get the real one from https://www.python.org/downloads/ and tick
echo "Add python.exe to PATH" on the first screen of the installer.
echo.
pause
exit /b
