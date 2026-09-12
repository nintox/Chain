"""
A small fake Tk: enough widget API for the push window to be built and driven
without a display. Same trick as wowstub.lua - the point is that the logic and
the wiring get exercised, not the pixels.

    import tkstub; tkstub.install()
    import chainpush_gui
"""

import sys
import types


class Var:
    def __init__(self, value=None, **kw):
        self._v = kw.get("value", value)

    def get(self):
        return self._v

    def set(self, v):
        self._v = v


class Widget:
    def __init__(self, master=None, **kw):
        self.master = master
        self.opts = dict(kw)
        self.children = []
        self.packed = False
        self.bindings = {}
        if isinstance(master, Widget):
            master.children.append(self)

    # layout and configuration
    def pack(self, **kw):
        self.packed = True

    grid = place = pack

    def configure(self, **kw):
        self.opts.update(kw)

    config = configure

    def cget(self, key):
        return self.opts.get(key)

    def __getitem__(self, key):
        return self.opts.get(key, "#000000")

    def bind(self, event, fn):
        self.bindings[event] = fn

    def invoke(self):
        fn = self.opts.get("command")
        if fn:
            fn()

    def winfo_children(self):
        return self.children

    def __getattr__(self, name):
        # anything we did not implement is a no-op, as in the real thing
        def nothing(*a, **kw):
            return None
        return nothing


class Entry(Widget):
    def __init__(self, master=None, **kw):
        Widget.__init__(self, master, **kw)
        self.text = ""

    def get(self):
        return self.text

    def insert(self, index, value):
        self.text = self.text + value if index == "end" else value + self.text

    def delete(self, first, last=None):
        self.text = ""


class Text(Widget):
    def __init__(self, master=None, **kw):
        Widget.__init__(self, master, **kw)
        self.lines = []

    def insert(self, index, value):
        self.lines.append(value)

    def delete(self, first, last=None):
        if first == "1.0" and last == "2.0" and self.lines:
            self.lines.pop(0)
        else:
            self.lines = []

    def index(self, _what):
        return "%d.0" % (len(self.lines) + 1)

    def get(self, *a):
        return "".join(self.lines)


class Canvas(Widget):
    def __init__(self, master=None, **kw):
        Widget.__init__(self, master, **kw)
        self.items = {}

    def create_oval(self, *a, **kw):
        key = len(self.items) + 1
        self.items[key] = dict(kw)
        return key

    def itemconfigure(self, key, **kw):
        self.items.setdefault(key, {}).update(kw)


class Tk(Widget):
    def __init__(self, **kw):
        Widget.__init__(self, None, **kw)
        self.opts.setdefault("bg", "#000000")
        self.pending = []
        self.titleText = ""
        self.destroyed = False
        self.hidden = False

    def title(self, text=None):
        if text is None:
            return self.titleText
        self.titleText = text

    def protocol(self, name, fn):
        self.bindings[name] = fn

    def after(self, _ms, fn=None, *a):
        if fn:
            self.pending.append((fn, a))
        return len(self.pending)

    def destroy(self):
        self.destroyed = True

    def withdraw(self):
        self.hidden = True

    def iconify(self):
        self.hidden = True

    def deiconify(self):
        self.hidden = False

    def mainloop(self):
        pass

    # drive whatever the app has scheduled, a bounded number of times
    def pump(self, rounds=3):
        for _ in range(rounds):
            todo, self.pending = self.pending, []
            for fn, a in todo:
                fn(*a)


class PhotoImage:
    def __init__(self, **kw):
        self.data = kw.get("data")


ASKED = []
ANSWERS = {"askyesnocancel": False}


def _record(kind):
    def fn(*a, **kw):
        ASKED.append((kind, a, kw))
        return ANSWERS.get(kind)
    return fn


def install():
    """Put the fakes into sys.modules, in place of the real tkinter."""
    tk = types.ModuleType("tkinter")
    for name in ("Frame", "Label", "Button", "Radiobutton", "Checkbutton",
                 "Listbox", "Scrollbar", "LabelFrame"):
        setattr(tk, name, type(name, (Widget,), {}))
    tk.Tk = Tk
    tk.Entry = Entry
    tk.Text = Text
    tk.Canvas = Canvas
    tk.StringVar = Var
    tk.BooleanVar = Var
    tk.IntVar = Var
    tk.PhotoImage = PhotoImage

    ttk = types.ModuleType("tkinter.ttk")
    for name in ("Frame", "Label", "Button", "Radiobutton", "Checkbutton",
                 "LabelFrame", "Combobox", "Separator", "Style", "Notebook"):
        setattr(ttk, name, type(name, (Widget,), {}))
    # the themed entry has to behave like a real one: the window reads it back
    ttk.Entry = type("Entry", (Entry,), {})

    filedialog = types.ModuleType("tkinter.filedialog")
    filedialog.askopenfilename = _record("askopenfilename")

    messagebox = types.ModuleType("tkinter.messagebox")
    messagebox.showinfo = _record("showinfo")
    messagebox.showwarning = _record("showwarning")
    messagebox.showerror = _record("showerror")
    messagebox.askyesnocancel = _record("askyesnocancel")

    tk.ttk, tk.filedialog, tk.messagebox = ttk, filedialog, messagebox
    sys.modules["tkinter"] = tk
    sys.modules["tkinter.ttk"] = ttk
    sys.modules["tkinter.filedialog"] = filedialog
    sys.modules["tkinter.messagebox"] = messagebox
    return tk
