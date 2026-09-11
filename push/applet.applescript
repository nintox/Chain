-- Chain Push - the Mac app.
--
-- An AppleScript applet, which is a real Cocoa application: it has a Dock
-- icon, it sits there doing nothing at no cost while it waits, and macOS
-- hands it the events a program is supposed to get - clicked in the Dock,
-- asked to quit, asked to log out.
--
-- That last part is the whole reason for it. A shell script in an app bundle
-- cannot be clicked: there is nobody home to receive the click. The previous
-- attempt put the status item in the menu bar through the scripting host
-- instead, which drew nothing on a full menu bar and cost half a processor
-- doing it.
--
-- Two more things fall out of being a real app bundle: notifications posted
-- from in here are credited to Chain Push, with the Chain icon, rather
-- than to Script Editor; and Quit in the Dock menu works the way Quit works
-- in every other program.
--
-- The watching itself is not done here. chainpush.py runs alongside, follows
-- the chat log and the screenshot folder, and sends to your phone. This is
-- the face on it.

property watching : false

on appFolder()
	tell application "System Events"
		return POSIX path of (container of (path to me))
	end tell
end appFolder

on resources()
	return POSIX path of (path to me) & "Contents/Resources/"
end resources

on shell(cmd)
	try
		return do shell script cmd
	on error errText
		return "ERROR " & errText
	end try
end shell

-- Which python can be trusted. /usr/bin/python3 on a Mac without the
-- developer tools is a stub that pops an install dialog the moment it is
-- touched, so it is only used when the tools are actually there.
on findPython()
	repeat with p in {"/opt/homebrew/bin/python3", "/usr/local/bin/python3"}
		if my shell("test -x " & quoted form of (p as text) & " && echo yes") is "yes" then
			return p as text
		end if
	end repeat
	if my shell("/usr/bin/xcode-select -p >/dev/null 2>&1 && test -x /usr/bin/python3 && echo yes") is "yes" then
		return "/usr/bin/python3"
	end if
	return ""
end findPython

on isSetUp()
	set py to my findPython()
	if py is "" then return false
	set r to my shell(quoted form of py & " -c 'import sys; sys.path.insert(0, sys.argv[1]); import chainpush; c = chainpush.load_config(); print(1 if (c.get(\"topic\") if c.get(\"service\") == \"ntfy\" else c.get(\"webhook\")) else 0)' " & quoted form of my resources())
	return r is "1"
end isSetUp

on startWatching()
	set py to my findPython()
	if py is "" then
		-- no python at all: the shell version does the whole job on its own
		my shell("nohup /bin/bash " & quoted form of (my resources() & "chainpush.sh") & " --watch >> ~/Library/Logs/ChainPush.log 2>&1 &")
	else
		my shell("nohup " & quoted form of py & " -u " & quoted form of (my resources() & "chainpush.py") & " --saved --serve >> ~/Library/Logs/ChainPush.log 2>&1 &")
	end if
	set watching to true
end startWatching

on stopWatching()
	my shell("pkill -f 'chainpush.py --saved --serve' 2>/dev/null; pkill -f 'chainpush.sh --watch' 2>/dev/null; true")
	set watching to false
end stopWatching

on openSettings()
	set py to my findPython()
	set useWindow to false
	if py is not "" then
		set tkv to my shell(quoted form of py & " -c 'import tkinter; print(tkinter.TkVersion)' 2>/dev/null")
		-- Apple's own python3 carries Tk 8.5.9, which on any recent macOS puts
		-- up an empty white rectangle. The Mac's own dialogs instead.
		if tkv is "8.6" or tkv is "8.7" or tkv starts with "9" then set useWindow to true
	end if
	if useWindow then
		my shell(quoted form of py & " -u " & quoted form of (my resources() & "chainpush_gui.py") & " --settings-only > /dev/null 2>&1")
	else
		my shell("/bin/bash " & quoted form of (my resources() & "chainpush.sh") & " --settings-only > /dev/null 2>&1")
	end if
	my shell("printf 'reload\\n' >> " & quoted form of my statePath("command"))
end openSettings

on statePath(name)
	return (POSIX path of (path to home folder)) & "Library/Application Support/Chain/" & name
end statePath

-- What the watcher says about itself: how many it has sent, where to, and
-- whether it is still alive.
on statusLine()
	set raw to my shell("cat " & quoted form of my statePath("status.json") & " 2>/dev/null")
	if raw starts with "ERROR" or raw is "" then return "Starting up..."
	set py to my findPython()
	if py is "" then return "Running"
	return my shell(quoted form of py & " -c 'import json,sys,time
d=json.load(sys.stdin)
alive = d.get(\"alive\") and (time.time()-d[\"alive\"]) < 20
print((\"Watching\" if alive else \"NOT RUNNING\") + \" - \" + str(d.get(\"sent\",0)) + \" sent\")
print(\"Sending to \" + str(d.get(\"target\",\"nowhere yet\")))
print(\"Last: \" + (d.get(\"last\") or \"nothing yet\"))' <<< " & quoted form of raw)
end statusLine

on showStatus()
	set info to my statusLine()
	set answer to button returned of (display dialog "Chain Push" & return & return & info & return & return & "It keeps watching while this is closed. Click the Chain icon in the Dock to bring it back, and use Quit in its Dock menu to stop it." buttons {"Close", "Send a test", "Settings..."} default button "Close" with title "Chain Push" with icon note)
	if answer is "Send a test" then
		my shell("printf 'test\\n' >> " & quoted form of my statePath("command"))
		display notification "Test sent. Look at your phone." with title "Chain Push"
	else if answer is "Settings..." then
		my openSettings()
		my showStatus()
	end if
end showStatus

on run
	if not my isSetUp() then my openSettings()
	my startWatching()
	display notification "Watching. Close this and carry on playing - the icon stays in the Dock." with title "Chain Push"
end run

-- Clicked in the Dock. This is the event a shell script in an app bundle can
-- never receive, and the reason this is an applet at all.
on reopen
	my showStatus()
end reopen

-- Stay-open applets get this every so often; it costs nothing and it is where
-- a watcher that died quietly gets noticed.
on idle
	set raw to my shell("cat " & quoted form of my statePath("status.json") & " 2>/dev/null")
	if raw is not "" and raw does not start with "ERROR" then
		if raw does not contain "\"running\": true" and watching then
			-- it stopped on its own; put it back
			my startWatching()
		end if
	end if
	return 60
end idle

on quit
	my stopWatching()
	continue quit
end quit
