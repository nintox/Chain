#!/usr/bin/env python3
"""
Chain Push - the Windows system tray icon.

A background program on Windows belongs in the tray, by the clock, not in a
window you have to keep out of the way and not on the taskbar where closing it
kills it. This puts it there with nothing installed: Shell_NotifyIcon through
ctypes, which is part of Windows itself.

    pythonw tray_win.py

It runs the watcher in a thread, shows the Chain icon in the tray, and puts
up a balloon - with the same icon on it - whenever something is sent. Right
click for the menu: status, a test notification, the log, settings, quit.

There is no third party anything here on purpose. pystray and Pillow would do
the same job in twenty lines, but they have to be installed first, and a
program that needs a pip command before it will start is a program most people
never run.
"""

import ctypes
import ctypes.wintypes as wt
import os
import queue
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import chainpush as engine                                  # noqa: E402

APP_TITLE = "Chain Push"

# ------------------------------------------------------------- the Win32 bits

user32 = ctypes.windll.user32
shell32 = ctypes.windll.shell32
kernel32 = ctypes.windll.kernel32

WM_DESTROY = 0x0002
WM_COMMAND = 0x0111
WM_APP = 0x8000
WM_TRAYICON = WM_APP + 1
WM_LBUTTONUP = 0x0202
WM_RBUTTONUP = 0x0205

NIM_ADD, NIM_MODIFY, NIM_DELETE = 0, 1, 2
NIF_MESSAGE, NIF_ICON, NIF_TIP, NIF_INFO = 0x01, 0x02, 0x04, 0x10
NIIF_USER = 0x04                     # "use my own icon on the balloon"
NIIF_LARGE_ICON = 0x20

IMAGE_ICON = 1
LR_LOADFROMFILE, LR_DEFAULTSIZE = 0x0010, 0x0040
IDI_APPLICATION = 32512

MF_STRING, MF_SEPARATOR, MF_GRAYED = 0x0000, 0x0800, 0x0001
TPM_RIGHTBUTTON = 0x0002

ID_STATUS, ID_TARGET, ID_TEST, ID_LOG, ID_SETTINGS, ID_QUIT = 1, 2, 3, 4, 5, 6

WNDPROC = ctypes.WINFUNCTYPE(ctypes.c_long, wt.HWND, ctypes.c_uint,
                             wt.WPARAM, wt.LPARAM)


class WNDCLASS(ctypes.Structure):
    _fields_ = [("style", ctypes.c_uint), ("lpfnWndProc", WNDPROC),
                ("cbClsExtra", ctypes.c_int), ("cbWndExtra", ctypes.c_int),
                ("hInstance", wt.HINSTANCE), ("hIcon", wt.HICON),
                ("hCursor", wt.HANDLE), ("hbrBackground", wt.HBRUSH),
                ("lpszMenuName", wt.LPCWSTR), ("lpszClassName", wt.LPCWSTR)]


class NOTIFYICONDATA(ctypes.Structure):
    _fields_ = [("cbSize", wt.DWORD), ("hWnd", wt.HWND), ("uID", ctypes.c_uint),
                ("uFlags", ctypes.c_uint), ("uCallbackMessage", ctypes.c_uint),
                ("hIcon", wt.HICON), ("szTip", ctypes.c_wchar * 128),
                ("dwState", wt.DWORD), ("dwStateMask", wt.DWORD),
                ("szInfo", ctypes.c_wchar * 256), ("uVersion", ctypes.c_uint),
                ("szInfoTitle", ctypes.c_wchar * 64), ("dwInfoFlags", wt.DWORD),
                ("guidItem", ctypes.c_byte * 16), ("hBalloonIcon", wt.HICON)]


class Tray:
    def __init__(self):
        self.cfg = engine.load_config()
        self.q = queue.Queue()
        self.stopping = threading.Event()
        self.sent = 0
        self.error = ""
        self.hwnd = None
        self.icon = self._load_icon()
        self._window()
        self._add()

    # ------------------------------------------------------------- plumbing
    def _load_icon(self):
        path = os.path.join(HERE, "icon.ico")
        h = 0
        if os.path.exists(path):
            h = user32.LoadImageW(None, path, IMAGE_ICON, 0, 0,
                                  LR_LOADFROMFILE | LR_DEFAULTSIZE)
        return h or user32.LoadIconW(None, ctypes.c_wchar_p(IDI_APPLICATION))

    def _window(self):
        # A window nobody ever sees: the tray needs somewhere to send its
        # clicks, and that somewhere has to be a window.
        self.proc = WNDPROC(self._on_message)
        cls = WNDCLASS()
        cls.lpfnWndProc = self.proc
        cls.lpszClassName = "ChainPushTray"
        cls.hInstance = kernel32.GetModuleHandleW(None)
        user32.RegisterClassW(ctypes.byref(cls))
        self.hwnd = user32.CreateWindowExW(0, cls.lpszClassName, APP_TITLE,
                                           0, 0, 0, 0, 0, None, None,
                                           cls.hInstance, None)

    def _data(self, flags):
        nid = NOTIFYICONDATA()
        nid.cbSize = ctypes.sizeof(NOTIFYICONDATA)
        nid.hWnd = self.hwnd
        nid.uID = 1
        nid.uFlags = flags
        nid.uCallbackMessage = WM_TRAYICON
        nid.hIcon = self.icon
        return nid

    def _add(self):
        nid = self._data(NIF_MESSAGE | NIF_ICON | NIF_TIP)
        nid.szTip = APP_TITLE
        shell32.Shell_NotifyIconW(NIM_ADD, ctypes.byref(nid))

    def _tip(self, text):
        nid = self._data(NIF_ICON | NIF_TIP)
        nid.szTip = text[:127]
        shell32.Shell_NotifyIconW(NIM_MODIFY, ctypes.byref(nid))

    def balloon(self, title, body):
        """The same event on the machine you are sitting at, with the Chain
        icon on it rather than a generic exclamation mark."""
        nid = self._data(NIF_INFO | NIF_ICON)
        nid.szInfoTitle = str(title)[:63]
        nid.szInfo = str(body)[:255]
        nid.dwInfoFlags = NIIF_USER | NIIF_LARGE_ICON
        nid.hBalloonIcon = self.icon
        shell32.Shell_NotifyIconW(NIM_MODIFY, ctypes.byref(nid))

    def remove(self):
        nid = self._data(0)
        shell32.Shell_NotifyIconW(NIM_DELETE, ctypes.byref(nid))

    # --------------------------------------------------------------- the menu
    def _menu(self):
        menu = user32.CreatePopupMenu()
        state = "Watching - %d sent" % self.sent
        if self.error:
            state = "Running - last send failed"
        if self.stopping.is_set():
            state = "Stopped"
        user32.AppendMenuW(menu, MF_STRING | MF_GRAYED, ID_STATUS, state)
        user32.AppendMenuW(menu, MF_STRING | MF_GRAYED, ID_TARGET,
                           "Sending to " + engine.describe(self.cfg))
        user32.AppendMenuW(menu, MF_SEPARATOR, 0, None)
        user32.AppendMenuW(menu, MF_STRING, ID_TEST, "Send a test notification")
        user32.AppendMenuW(menu, MF_STRING, ID_LOG, "Open the log")
        user32.AppendMenuW(menu, MF_STRING, ID_SETTINGS, "Settings...")
        user32.AppendMenuW(menu, MF_SEPARATOR, 0, None)
        user32.AppendMenuW(menu, MF_STRING, ID_QUIT, "Quit Chain Push")

        pt = wt.POINT()
        user32.GetCursorPos(ctypes.byref(pt))
        # the documented dance: without this the menu will not go away again
        user32.SetForegroundWindow(self.hwnd)
        user32.TrackPopupMenu(menu, TPM_RIGHTBUTTON, pt.x, pt.y, 0,
                              self.hwnd, None)
        user32.PostMessageW(self.hwnd, 0, 0, 0)
        user32.DestroyMenu(menu)

    def _chose(self, which):
        if which == ID_QUIT:
            self.stopping.set()
            user32.DestroyWindow(self.hwnd)
        elif which == ID_TEST:
            threading.Thread(target=self._test, daemon=True).start()
        elif which == ID_LOG:
            self._open(engine.state_file("events.log"))
        elif which == ID_SETTINGS:
            self._settings()

    def _test(self):
        try:
            engine.notify(self.cfg, "Chain", "This is a test. It works.")
            self.q.put(("event", "Chain - test"))
        except Exception as err:
            self.q.put(("error", str(err)))

    def _open(self, path):
        try:
            os.startfile(path)                              # noqa: B606
        except Exception:
            pass

    def _settings(self):
        gui = os.path.join(HERE, "chainpush_gui.py")
        exe = sys.executable
        # pythonw, so the settings window does not drag a console along
        if exe.lower().endswith("python.exe"):
            other = exe[:-len("python.exe")] + "pythonw.exe"
            if os.path.exists(other):
                exe = other
        try:
            subprocess.Popen([exe, gui, "--settings-only"])
        except Exception as err:
            self.q.put(("error", str(err)))

    # ------------------------------------------------------------- messages
    def _on_message(self, hwnd, msg, wparam, lparam):
        if msg == WM_TRAYICON:
            if lparam in (WM_RBUTTONUP, WM_LBUTTONUP):
                self._menu()
            return 0
        if msg == WM_COMMAND:
            self._chose(wparam & 0xFFFF)
            return 0
        if msg == WM_DESTROY:
            self.remove()
            user32.PostQuitMessage(0)
            return 0
        return user32.DefWindowProcW(hwnd, msg, wparam, lparam)

    # ----------------------------------------------------------------- run
    def start_watching(self):
        def run():
            try:
                engine.watch(self.cfg,
                             on_event=lambda t, b: self.q.put(("event", "%s - %s" % (t, b))),
                             on_error=lambda e: self.q.put(("error", str(e))),
                             stop=self.stopping.is_set)
            except Exception as err:
                self.q.put(("fatal", str(err)))
        threading.Thread(target=run, daemon=True).start()

    def drain(self):
        changed = False
        try:
            while True:
                kind, text = self.q.get_nowait()
                changed = True
                if kind == "event":
                    self.sent += 1
                    self.error = ""
                    engine.log_event("sent", text)
                    title, _, body = text.partition(" - ")
                    self.balloon(title or APP_TITLE, body or text)
                else:
                    self.error = text
                    engine.log_event("error", text)
                    if kind == "fatal":
                        self.balloon(APP_TITLE, "Stopped: " + text)
        except queue.Empty:
            pass
        if changed:
            self._tip("%s - %d sent%s"
                      % (APP_TITLE, self.sent, "  (last send failed)" if self.error else ""))

    def loop(self):
        msg = wt.MSG()
        while True:
            while user32.PeekMessageW(ctypes.byref(msg), None, 0, 0, 1):
                if msg.message == 0x0012:                   # WM_QUIT
                    return
                user32.TranslateMessage(ctypes.byref(msg))
                user32.DispatchMessageW(ctypes.byref(msg))
            self.drain()
            time.sleep(0.15)


def main():
    if not sys.platform.startswith("win"):
        print("This is the Windows tray version.", file=sys.stderr)
        return 2
    tray = Tray()
    tray.start_watching()
    tray.balloon(APP_TITLE, "Watching. Nothing else to do - close this and "
                            "carry on playing.")
    try:
        tray.loop()
    finally:
        tray.stopping.set()
        tray.remove()
    return 0


if __name__ == "__main__":
    sys.exit(main())
