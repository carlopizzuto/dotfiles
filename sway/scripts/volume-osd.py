#!/usr/bin/env python3
"""Volume OSD for Sway — GTK3 + gtk-layer-shell overlay triggered by PulseAudio events."""

import os
import signal
import subprocess

import cairo
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell

# ── Config ───────────────────────────────────────────────────────────────────
HIDE_MS = 1500  # auto-hide delay
DEBOUNCE_MS = 16  # coalesce rapid events (~one frame at 60 fps)
GAP = 10  # px between waybar and OSD (exclusive-zone aware)

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
PID_FILE = os.path.join(RUNTIME, "volume-osd.pid")

ICONS = {
    "muted": "\U000f075f",  # 󰝟
    "off": "\U000f0581",  # 󰖁
    "low": "\U000f057f",  # 󰕿
    "mid": "\U000f0580",  # 󰖀
    "high": "\U000f057e",  # 󰕾
}

CSS = b"""\
window {
    background-color: transparent;
}

.osd {
    background-color: rgba(40, 40, 40, 0.92);
    border: 1px solid rgba(80, 73, 69, 0.6);
    border-radius: 12px;
    padding: 10px 20px;
}

.osd-icon {
    color: #ebdbb2;
    font-family: "Iosevka Nerd Font", "Symbols Nerd Font Mono";
    font-size: 20px;
}
.osd-icon.muted {
    color: #928374;
}

.osd-pct {
    color: #ebdbb2;
    font-family: "Iosevka Nerd Font";
    font-size: 14px;
    min-width: 3.2em;
}
.osd-pct.muted {
    color: #928374;
}

progressbar trough {
    min-height: 6px;
    min-width: 150px;
    background-color: #3c3836;
    border-radius: 3px;
}
progressbar progress {
    min-height: 6px;
    background-color: #fabd2f;
    border-radius: 3px;
}
progressbar.muted progress {
    background-color: #928374;
}
"""


class VolumeOSD:
    def __init__(self):
        self._hide_id = None
        self._debounce_id = None
        self._pactl = None
        self._build_ui()
        self._start_monitor()

    # ── UI ────────────────────────────────────────────────────────────────
    def _build_ui(self):
        w = Gtk.Window()

        # RGBA visual for transparency
        vis = w.get_screen().get_rgba_visual()
        if vis:
            w.set_visual(vis)
        w.set_app_paintable(True)
        w.connect("draw", self._clear_bg)

        # Layer-shell
        GtkLayerShell.init_for_window(w)
        GtkLayerShell.set_layer(w, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(w, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_margin(w, GtkLayerShell.Edge.TOP, GAP)
        GtkLayerShell.set_namespace(w, "volume-osd")
        GtkLayerShell.set_keyboard_mode(w, GtkLayerShell.KeyboardMode.NONE)

        # CSS
        prov = Gtk.CssProvider()
        prov.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            prov,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        # Widgets
        box = Gtk.Box(spacing=12)
        box.get_style_context().add_class("osd")

        self._icon = Gtk.Label()
        self._icon.get_style_context().add_class("osd-icon")

        self._bar = Gtk.ProgressBar()
        self._bar.set_valign(Gtk.Align.CENTER)

        self._pct = Gtk.Label()
        self._pct.get_style_context().add_class("osd-pct")
        self._pct.set_xalign(1.0)

        box.pack_start(self._icon, False, False, 0)
        box.pack_start(self._bar, True, True, 0)
        box.pack_start(self._pct, False, False, 0)

        w.add(box)
        w.show_all()
        w.hide()
        self._win = w

    @staticmethod
    def _clear_bg(_widget, cr):
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        return False

    # ── PulseAudio monitoring ─────────────────────────────────────────────
    def _start_monitor(self):
        self._pactl = subprocess.Popen(
            ["pactl", "subscribe"],
            stdout=subprocess.PIPE,
            text=True,
        )
        GLib.io_add_watch(
            self._pactl.stdout.fileno(),
            GLib.IO_IN | GLib.IO_HUP,
            self._on_pa_event,
        )

    def _on_pa_event(self, _fd, cond):
        if cond & GLib.IO_HUP:
            GLib.timeout_add(2000, self._start_monitor)
            return False
        line = self._pactl.stdout.readline()
        if "'change' on sink #" in line:
            if self._debounce_id:
                GLib.source_remove(self._debounce_id)
            self._debounce_id = GLib.timeout_add(DEBOUNCE_MS, self._refresh)
        return True

    def _refresh(self):
        self._debounce_id = None
        try:
            out = subprocess.check_output(
                ["wpctl", "get-volume", "@DEFAULT_SINK@"],
                text=True,
                timeout=1,
            ).strip()
            # "Volume: 0.75" or "Volume: 0.75 [MUTED]"
            vol = float(out.split()[1])
            muted = "[MUTED]" in out
            self._update(vol, muted)
        except Exception:
            pass
        return False

    # ── Display ───────────────────────────────────────────────────────────
    def _update(self, vol, muted):
        pct = round(vol * 100)

        if muted:
            glyph = ICONS["muted"]
        elif pct == 0:
            glyph = ICONS["off"]
        elif pct < 30:
            glyph = ICONS["low"]
        elif pct < 70:
            glyph = ICONS["mid"]
        else:
            glyph = ICONS["high"]

        self._icon.set_text(glyph)
        self._bar.set_fraction(min(vol, 1.0))
        self._pct.set_text(f"{pct}%")

        for w in (self._icon, self._pct, self._bar):
            ctx = w.get_style_context()
            if muted:
                ctx.add_class("muted")
            else:
                ctx.remove_class("muted")

        self._win.show()

        if self._hide_id:
            GLib.source_remove(self._hide_id)
        self._hide_id = GLib.timeout_add(HIDE_MS, self._hide)

    def _hide(self):
        self._win.hide()
        self._hide_id = None
        return False

    # ── Cleanup ───────────────────────────────────────────────────────────
    def cleanup(self):
        if self._pactl:
            self._pactl.terminate()
        try:
            os.unlink(PID_FILE)
        except FileNotFoundError:
            pass


def _kill_existing():
    """Stop any previously running instance."""
    try:
        with open(PID_FILE) as f:
            os.kill(int(f.read().strip()), signal.SIGTERM)
    except (FileNotFoundError, ProcessLookupError, ValueError):
        pass


def main():
    _kill_existing()
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))

    osd = VolumeOSD()

    def _quit(*_):
        osd.cleanup()
        Gtk.main_quit()
        return False

    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, _quit)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, _quit)

    Gtk.main()


if __name__ == "__main__":
    main()
