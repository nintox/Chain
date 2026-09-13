@echo off
rem Double-click me to commit everything and push it.
rem
rem GitHub Desktop cannot do this. commit.template is not supported there -
rem the request has been closed as not planned twice - and it will not let you
rem press Commit with an empty summary, so there is no way inside that program
rem to commit without typing something.
rem
rem So the message is written to a file beforehand, by whoever made the
rem change, and this uses it. Nothing to type and nothing to think of at the
rem moment you have stopped thinking about it.
rem
rem The message lives in .git, which is never committed, so it leaves no trace
rem in the repository and is thrown away the moment it has been used.
setlocal
cd /d "%~dp0"
set "MSG=.git\chain-commit-msg.txt"

call :findgit
if not defined GIT goto nogit

rem Anything to do?
"%GIT%" diff --quiet && "%GIT%" diff --cached --quiet && (
  "%GIT%" ls-files --others --exclude-standard --error-unmatch . >nul 2>&1 || (
    echo Nothing has changed.
    echo.
    pause
    exit /b
  )
)

"%GIT%" add -A || goto fail

if exist "%MSG%" (
  "%GIT%" commit -F "%MSG%" || goto fail
  del "%MSG%"
) else (
  rem No message waiting: say what changed rather than inventing a reason for
  rem it. A mechanical line is honest; a made-up one is worse than none.
  for /f %%n in ('"%GIT%" diff --cached --name-only ^| find /c /v ""') do set "N=%%n"
  "%GIT%" commit -m "Changes to %N% file(s)" || goto fail
)

echo.
"%GIT%" push || goto fail
echo.
"%GIT%" log --oneline -1
echo.
echo Committed and pushed.
echo.
pause
exit /b

rem ------------------------------------------------------------------------
rem GitHub Desktop ships its own git and does not always put it on PATH, so
rem "git is not installed" is usually wrong. Look where it actually is.
:findgit
set "GIT="
git --version >nul 2>&1 && set "GIT=git" && exit /b
for /d %%d in ("%LOCALAPPDATA%\GitHubDesktop\app-*") do (
  if exist "%%d\resources\app\git\cmd\git.exe" set "GIT=%%d\resources\app\git\cmd\git.exe"
)
if defined GIT exit /b
if exist "%ProgramFiles%\Git\cmd\git.exe" set "GIT=%ProgramFiles%\Git\cmd\git.exe"
exit /b

:nogit
echo Could not find git.
echo.
echo It is normally installed with GitHub Desktop, at
echo   %%LOCALAPPDATA%%\GitHubDesktop\app-VERSION\resources\app\git\cmd\git.exe
echo If you have GitHub Desktop and this still says no, it is worth getting
echo git itself from https://git-scm.com/download/win - the installer puts it
echo on PATH and everything here starts working.
echo.
pause
exit /b 1

:fail
echo.
echo That did not work. The reason is above this line.
echo Nothing has been pushed.
echo.
pause
exit /b 1
