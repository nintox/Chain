#!/usr/bin/env python3
"""
Chain Push - the window.

Pick ntfy or Discord, paste the one thing that identifies you, press Start.
The settings are remembered, so the next time you open it there is nothing to
do but watch the light stay green.

Everything it actually does lives in chainpush.py; this is the face on it.

Built with ttk and the system's own colours on purpose. An earlier version
painted every widget dark by hand, which looks right on Windows and comes out
as white-on-white on a Mac, where Aqua ignores most background and foreground
colours. Native widgets are readable on both, and there is nothing to get
wrong.
"""

import base64
import os
import queue
import subprocess
import sys
import threading
import time
import webbrowser

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

HERE = os.path.dirname(os.path.abspath(__file__))
# Inside the built app everything is flat in Resources, so HERE is enough
# there; in the repository the pictures live in ../icons. Both, and whichever
# one is real wins.
for _d in (HERE, os.path.join(os.path.dirname(HERE), "icons")):
    if _d not in sys.path:
        sys.path.insert(0, _d)

import chainpush as engine                                  # noqa: E402

try:
    from iconbytes import ICON_PNG_BASE64
except ImportError:                                         # icon.py not run yet
    ICON_PNG_BASE64 = ""

APP_TITLE = "Chain Push"

GREEN = "#2f9e44"
RED = "#c92a2a"
AMBER = "#e8a33d"
GREY = "#868e96"
LINK = "#1971c2"


class App:
    def __init__(self, root, settings_only=False):
        self.root = root
        # Settings-only: opened from the menu bar item or the tray, where the
        # watching is already somebody else's job. The window is then a form
        # and nothing more - no Start button, no feed, and Save closes it.
        self.settingsOnly = settings_only
        self.cfg = engine.load_config()
        self.q = queue.Queue()
        self.thread = None
        self.stopping = threading.Event()
        self.running = False
        self.sent = 0
        self.tray = None

        root.title(APP_TITLE)
        self._icon()
        self._build()
        self._fill()
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.root.after(150, self._drain)

        if self.settingsOnly:
            self._settings_shape()
        elif self.cfg.get("autostart") and self._identity():
            self.start()

    # -------------------------------------------------------------- widgets
    def _icon(self):
        if not ICON_PNG_BASE64:
            return
        try:
            self.iconimg = tk.PhotoImage(data=base64.b64decode(ICON_PNG_BASE64))
            self.root.iconphoto(True, self.iconimg)
        except Exception:
            pass

    def _build(self):
        pad = 12
        outer = ttk.Frame(self.root, padding=pad)
        outer.grid(row=0, column=0, sticky="nsew")
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)
        outer.columnconfigure(0, weight=1)
        row = 0

        head = ttk.Label(outer, text=APP_TITLE, font=("TkDefaultFont", 15, "bold"))
        head.grid(row=row, column=0, sticky="w")
        row += 1
        ttk.Label(outer, foreground=GREY, justify="left",
                  text="Notifications on your phone when the instance resets or "
                       "somebody starts a ready check."
                  ).grid(row=row, column=0, sticky="w", pady=(2, 10))
        row += 1

        # --- where to send
        where = ttk.LabelFrame(outer, text="Where the notifications go", padding=10)
        where.grid(row=row, column=0, sticky="ew")
        where.columnconfigure(1, weight=1)
        row += 1

        self.service = tk.StringVar(value=self.cfg.get("service", "ntfy"))
        picks = ttk.Frame(where)
        picks.grid(row=0, column=0, columnspan=2, sticky="ew")
        ttk.Radiobutton(picks, text="ntfy app", value="ntfy", variable=self.service,
                        command=self._service_changed).grid(row=0, column=0)
        ttk.Radiobutton(picks, text="Discord", value="discord", variable=self.service,
                        command=self._service_changed).grid(row=0, column=1, padx=(16, 0))
        self.helpLink = ttk.Label(picks, text="how do I get one?", foreground=LINK,
                                  cursor="hand2")
        self.helpLink.grid(row=0, column=2, padx=(24, 0))
        self.helpLink.bind("<Button-1>", lambda _e: self._help())

        self.fieldLabel = ttk.Label(where, text="Topic")
        self.fieldLabel.grid(row=1, column=0, sticky="w", pady=(10, 0))
        self.field = ttk.Entry(where, width=44)
        self.field.grid(row=1, column=1, sticky="ew", padx=(10, 0), pady=(10, 0))
        self.fieldHint = ttk.Label(where, foreground=GREY, wraplength=430,
                                   justify="left", text="")
        self.fieldHint.grid(row=2, column=1, sticky="w", padx=(10, 0), pady=(2, 0))

        # --- the log file
        logbox = ttk.LabelFrame(outer, text="WoW chat log", padding=10)
        logbox.grid(row=row, column=0, sticky="ew", pady=(10, 0))
        logbox.columnconfigure(0, weight=1)
        row += 1

        self.logEntry = ttk.Entry(logbox)
        self.logEntry.grid(row=0, column=0, sticky="ew")
        ttk.Button(logbox, text="Find", width=7, command=self.find_log
                   ).grid(row=0, column=1, padx=(8, 0))
        ttk.Button(logbox, text="Browse", width=9, command=self.browse
                   ).grid(row=0, column=2, padx=(6, 0))
        ttk.Label(logbox, foreground=GREY, wraplength=430, justify="left",
                  text="Chat logging has to be on in game: type /chatlog, or let "
                       "the addon do it."
                  ).grid(row=1, column=0, columnspan=3, sticky="w", pady=(6, 0))

        # --- buttons
        btns = ttk.Frame(outer)
        btns.grid(row=row, column=0, sticky="ew", pady=(12, 0))
        btns.columnconfigure(2, weight=1)
        row += 1
        self.startBtn = ttk.Button(btns, text="Start", width=12, command=self.toggle)
        self.startBtn.grid(row=0, column=0)
        ttk.Button(btns, text="Send a test", command=self.test
                   ).grid(row=0, column=1, padx=(8, 0))
        self.autostart = tk.BooleanVar(value=bool(self.cfg.get("autostart", True)))
        ttk.Checkbutton(btns, text="start watching when I open this",
                        variable=self.autostart, command=self.save
                        ).grid(row=0, column=2, sticky="e")

        # --- status: the part that says "yes, it is running"
        status = ttk.Frame(outer)
        status.grid(row=row, column=0, sticky="ew", pady=(14, 0))
        status.columnconfigure(2, weight=1)
        row += 1
        # the lamp is the one thing drawn by hand, so it has to borrow the
        # theme's own background or it shows up as a white tile on a grey panel
        try:
            panel = ttk.Style().lookup("TFrame", "background") or None
        except Exception:
            panel = None
        self.lamp = tk.Canvas(status, width=14, height=14, highlightthickness=0,
                              borderwidth=0,
                              **({"background": panel} if panel else {}))
        self.lampDot = self.lamp.create_oval(2, 2, 13, 13, fill=RED, outline="")
        self.lamp.grid(row=0, column=0)
        self.statusText = ttk.Label(status, text="Stopped",
                                    font=("TkDefaultFont", 12, "bold"))
        self.statusText.grid(row=0, column=1, padx=(8, 0))
        self.countText = ttk.Label(status, text="", foreground=GREY)
        self.countText.grid(row=0, column=2, sticky="e")

        self.feed = tk.Text(outer, height=8, width=58, wrap="none",
                            relief="sunken", borderwidth=1,
                            background="#ffffff", foreground="#333333",
                            highlightthickness=0)
        self.feed.grid(row=row, column=0, sticky="nsew", pady=(6, 0))
        outer.rowconfigure(row, weight=1)
        self.feed.configure(state="disabled")

        self.root.update_idletasks()
        try:
            self.root.minsize(self.root.winfo_reqwidth(), self.root.winfo_reqheight())
        except Exception:
            pass
        # Tk on macOS sometimes comes up as an empty white rectangle. The
        # launcher watches for this marker and switches to the dialog version
        # when it never appears, so a broken window is never all you get.
        self.root.after(1200, self._mark_drawn)

    def _settings_shape(self):
        """Strip the window back to the form. The watcher outside is what
        keeps running, so a Start button here would be a second one."""
        self.root.title(APP_TITLE + " - settings")
        for w in (self.startBtn, self.feed, self.lamp, self.statusText,
                  self.countText):
            try:
                w.grid_remove()
            except Exception:
                pass
        self.startBtn.grid()
        self.startBtn.configure(text="Save and close", command=self._save_close)
        self.statusText.grid()
        self.statusText.configure(text="")
        self.log = lambda *_a, **_k: None

    def _save_close(self):
        self.gather()
        # tell whoever is watching to pick the new settings up, then get out
        # of the way: nobody wants a settings window sitting there afterwards
        try:
            engine.send_command("reload")
        except Exception:
            pass
        self.stopping.set()
        self.root.destroy()

    def _mark_drawn(self):
        path = os.environ.get("CHAINPUSH_MARKER")
        if not path:
            return
        try:
            with open(path, "w") as fh:
                fh.write("%dx%d\n" % (self.root.winfo_width(), self.root.winfo_height()))
        except Exception:
            pass

    # -------------------------------------------------------------- state
    def _fill(self):
        self._service_changed()
        self.logEntry.delete(0, "end")
        self.logEntry.insert(0, self.cfg.get("log") or (engine.find_log() or ""))

    def _service_changed(self):
        discord = self.service.get() == "discord"
        current = (self.field.get() or "").strip()
        # keep both values, so switching back and forth loses nothing
        if discord:
            if current and not current.startswith("http"):
                self.cfg["topic"] = current
            self.fieldLabel.configure(text="Webhook URL")
            self.fieldHint.configure(
                text="Discord: Edit channel - Integrations - Webhooks - Copy URL")
            value = self.cfg.get("webhook", "")
        else:
            if current.startswith("http"):
                self.cfg["webhook"] = current
            self.fieldLabel.configure(text="Topic")
            self.fieldHint.configure(
                text="Any name you like, but make it long and odd - anyone who "
                     "knows it can read your alerts.")
            value = self.cfg.get("topic", "")
        self.field.delete(0, "end")
        self.field.insert(0, value)

    def _identity(self):
        return bool((self.cfg.get("webhook") if self.cfg.get("service") == "discord"
                     else self.cfg.get("topic")) or "")

    def gather(self):
        """Read the widgets back into the settings, and save them."""
        value = (self.field.get() or "").strip()
        self.cfg["service"] = self.service.get()
        if self.cfg["service"] == "discord":
            self.cfg["webhook"] = value
        else:
            self.cfg["topic"] = value
        self.cfg["log"] = (self.logEntry.get() or "").strip()
        self.cfg["autostart"] = bool(self.autostart.get())
        engine.save_config(self.cfg)
        return self.cfg

    def save(self):
        self.gather()

    # -------------------------------------------------------------- actions
    def _help(self):
        if self.service.get() == "discord":
            webbrowser.open("https://support.discord.com/hc/en-us/articles/"
                            "228383668-Intro-to-Webhooks")
        else:
            webbrowser.open("https://ntfy.sh/")

    def find_log(self):
        found = engine.find_log()
        if found:
            self.logEntry.delete(0, "end")
            self.logEntry.insert(0, found)
            self.log("found %s" % found)
        else:
            messagebox.showinfo(
                APP_TITLE,
                "No WoWChatLog.txt in the usual places.\n\n"
                "It appears in the Logs folder of your WoW install once chat "
                "logging has been on. Type /chatlog in game, or turn on "
                "\"Marker in the chat log\" in the addon's settings, then press "
                "Find again.")

    def browse(self):
        path = filedialog.askopenfilename(
            title="Find WoWChatLog.txt",
            filetypes=[("Chat log", "WoWChatLog.txt"), ("Text files", "*.txt"),
                       ("All files", "*.*")])
        if path:
            self.logEntry.delete(0, "end")
            self.logEntry.insert(0, path)

    def test(self):
        cfg = self.gather()
        if not self._identity():
            messagebox.showwarning(APP_TITLE, "Fill in the %s first." %
                                   ("webhook URL" if cfg["service"] == "discord"
                                    else "topic"))
            return

        def run():
            try:
                engine.notify(cfg, "Chain",
                              "If you can read this on your phone, it works.")
                self.q.put(("log", "test sent to %s" % engine.describe(cfg)))
            except Exception as err:
                self.q.put(("error", "test failed: %s" % err))

        threading.Thread(target=run, daemon=True).start()
        self.log("sending a test...")

    def toggle(self):
        self.stop() if self.running else self.start()

    def start(self):
        cfg = self.gather()
        if not self._identity():
            messagebox.showwarning(APP_TITLE, "Fill in the %s first." %
                                   ("webhook URL" if cfg["service"] == "discord"
                                    else "topic"))
            return
        path = engine.find_log(cfg.get("log"))
        if not path:
            self.find_log()
            return

        self.stopping.clear()
        self.thread = threading.Thread(target=self._watch, args=(dict(cfg),), daemon=True)
        self.thread.start()
        self.running = True
        self.startBtn.configure(text="Stop")
        self._lamp(GREEN, "Running")
        self.log("watching %s" % path)
        self.log("sending to %s" % engine.describe(cfg))

    def stop(self):
        self.stopping.set()
        self.running = False
        self.startBtn.configure(text="Start")
        self._lamp(RED, "Stopped")
        self.log("stopped")

    def _watch(self, cfg):
        try:
            engine.watch(cfg,
                         on_event=lambda t, b: self.q.put(("event", "%s - %s" % (t, b))),
                         on_error=lambda e: self.q.put(("error", e)),
                         stop=self.stopping.is_set)
        except Exception as err:
            self.q.put(("fatal", str(err)))

    # -------------------------------------------------------------- display
    def toast(self, title, body):
        """
        The same event, on the machine you are sitting at. Free on macOS,
        where every app can post a notification; skipped elsewhere rather
        than dragged in as a dependency.
        """
        if sys.platform != "darwin":
            return
        safe = lambda t: str(t).replace("\\", "").replace('"', "'")
        try:
            subprocess.Popen(
                ["osascript", "-e",
                 'display notification "%s" with title "%s"'
                 % (safe(body), safe(title))],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

    def _lamp(self, colour, text):
        self.lamp.itemconfigure(self.lampDot, fill=colour)
        self.statusText.configure(text=text)
        self.root.title("%s - %s" % (APP_TITLE, text))

    def log(self, text):
        stamp = time.strftime("%H:%M")
        self.feed.configure(state="normal")
        self.feed.insert("end", "%s  %s\n" % (stamp, text))
        # keep the last 200 lines and nothing more
        if float(self.feed.index("end-1c").split(".")[0]) > 200:
            self.feed.delete("1.0", "2.0")
        self.feed.see("end")
        self.feed.configure(state="disabled")

    def _drain(self):
        try:
            while True:
                kind, text = self.q.get_nowait()
                if kind == "event":
                    self.sent += 1
                    self.countText.configure(text="%d sent" % self.sent)
                    self.log("sent: " + text)
                    title, _, body = text.partition(" - ")
                    self.toast(title, body or text)
                elif kind == "error":
                    self.log("could not send: " + text)
                    self._lamp(AMBER, "Running, but the last send failed")
                elif kind == "fatal":
                    self.log("stopped: " + text)
                    self.running = False
                    self.startBtn.configure(text="Start")
                    self._lamp(RED, "Stopped")
                else:
                    self.log(text)
        except queue.Empty:
            pass
        self.root.after(200, self._drain)

    def on_close(self):
        if self.settingsOnly:
            self.gather()
            try:
                engine.send_command("reload")
            except Exception:
                pass
            self.stopping.set()
            self.root.destroy()
            return
        if self.running:
            keep = messagebox.askyesnocancel(
                APP_TITLE,
                "Keep watching in the background?\n\n"
                "Yes  - hide the window, keep sending notifications\n"
                "No   - stop and quit")
            if keep is None:
                return
            if keep:
                self._hide()
                return
        self.gather()
        self.stopping.set()
        self.root.destroy()

    def _hide(self):
        """
        Out of the way but still obviously alive: a tray icon where the
        platform has one, and the dock or taskbar entry where it does not.
        """
        if self._tray():
            self.root.withdraw()
        else:
            self.root.iconify()

    def _tray(self):
        if self.tray:
            return True
        try:
            import io
            import pystray                                   # optional
            from PIL import Image
        except ImportError:
            return False
        try:
            image = Image.open(io.BytesIO(base64.b64decode(ICON_PNG_BASE64)))
        except Exception:
            return False

        def show(_icon=None, _item=None):
            self.root.after(0, lambda: (self.root.deiconify(), self.root.lift()))

        def quit_all(icon=None, _item=None):
            self.stopping.set()
            if icon:
                icon.stop()
            self.root.after(0, self.root.destroy)

        menu = pystray.Menu(
            pystray.MenuItem("Open Chain Push", show, default=True),
            pystray.MenuItem("Quit", quit_all))
        self.tray = pystray.Icon("leveltracker", image, APP_TITLE, menu)
        threading.Thread(target=self.tray.run, daemon=True).start()
        return True


def main():
    settings_only = "--settings-only" in sys.argv[1:]
    # Apple's own python3 carries Tk 8.5.9, which on a modern macOS puts up an
    # empty white window: the widgets are there, none of them are drawn. Say so
    # and stop, so whatever started us can fall back to the dialog version.
    if sys.platform == "darwin" and float(tk.TkVersion) < 8.6:
        print("Tk %s cannot draw on this macOS - use the dialog version "
              "(bash chainpush.sh)" % tk.TkVersion, file=sys.stderr)
        sys.exit(3)

    root = tk.Tk()
    # macOS puts a python rocket in the dock unless the app is told otherwise;
    # harmless everywhere else
    try:
        root.createcommand("tk::mac::ReopenApplication", root.deiconify)
    except Exception:
        pass
    try:
        App(root, settings_only=settings_only)
    except Exception:
        import traceback
        details = traceback.format_exc()
        print(details, file=sys.stderr)
        try:
            messagebox.showerror(APP_TITLE,
                                 "The window could not be built:\n\n" + details)
        except Exception:
            pass
        raise
    root.mainloop()


if __name__ == "__main__":
    main()
