#!/usr/bin/env python3
"""macOS-inspired screenshot tool for Sway/Wayland.

Usage:
    screenshot.py region       Select a region to capture
    screenshot.py window       Capture the focused window
    screenshot.py screen       Capture the focused output
    screenshot.py all          Capture all outputs
    screenshot.py menu         Open capture mode toolbar

Features:
    - Auto-saves to ~/Pictures/Screenshots/
    - Copies image to clipboard via wl-copy
    - Shows macOS-style floating thumbnail preview
    - Click thumbnail → annotate in swappy
    - Drag thumbnail → drop into apps (ripdrag)
    - Timer support (3s, 5s, 10s) via toolbar
"""

import argparse
import json
import math
import os
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

import cairo
import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, GtkLayerShell

# ── Config ────────────────────────────────────────────────────────────────────

SCREENSHOT_DIR = Path.home() / "Pictures" / "Screenshots"
RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
PID_FILE = os.path.join(RUNTIME_DIR, "screenshot-thumb.pid")
SCRIPT = os.path.abspath(__file__)

THUMB_MAX_W = 260
THUMB_TIMEOUT_MS = 5000
THUMB_MARGIN = 20
CORNER_RADIUS = 10
PROGRESS_HEIGHT = 3
SHADOW_SIZE = 4

# Gruvbox Dark
BG = (0.157, 0.157, 0.157)
BG1 = (0.235, 0.220, 0.212)
FG = (0.922, 0.859, 0.698)
YELLOW = (0.980, 0.741, 0.184)
BORDER = (0.314, 0.286, 0.271)
GRAY = (0.573, 0.514, 0.455)

# Region selector
HANDLE_RADIUS = 5
HANDLE_HIT = 9       # hit-test radius (slightly larger than visual)
MIN_SELECTION = 10    # minimum selection dimension in logical px
GRIM_SCALE = "2"      # capture scale factor
OVERLAY_ALPHA = 0.5   # dimming over non-selected area
HANDLE_CURSORS = [
    "nw-resize", "n-resize", "ne-resize", "e-resize",
    "se-resize", "s-resize", "sw-resize", "w-resize",
]

# Satty annotation args (shared across modes)
SATTY_ARGS = [
    "--copy-command", "wl-copy",
    "--early-exit",
    "--actions-on-enter", "save-to-clipboard",
    "--actions-on-enter", "save-to-file",
    "--actions-on-enter", "exit",
    "--font-family", "Iosevka Nerd Font",
]


# ══════════════════════════════════════════════════════════════════════════════
# Capture
# ══════════════════════════════════════════════════════════════════════════════

def capture(mode: str) -> str | None:
    """Capture screenshot, open satty for annotation, return saved path."""
    SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    path = SCREENSHOT_DIR / f"screenshot-{ts}.png"
    satty_cmd = ["satty", "-o", str(path)] + SATTY_ARGS

    try:
        if mode == "region":
            tmp = _region_select()
            if not tmp:
                return None
            try:
                subprocess.run(satty_cmd + ["-f", tmp], check=True)
            finally:
                os.unlink(tmp)

        else:
            if mode == "window":
                geo = _focused_window_geo()
                if not geo:
                    return None
                grim_cmd = ["grim", "-s", GRIM_SCALE, "-g", geo, "-"]
            elif mode == "screen":
                output = _focused_output_name()
                if not output:
                    return None
                grim_cmd = ["grim", "-s", GRIM_SCALE, "-o", output, "-"]
            elif mode == "all":
                grim_cmd = ["grim", "-s", GRIM_SCALE, "-"]
            else:
                return None

            grim_proc = subprocess.Popen(grim_cmd, stdout=subprocess.PIPE)
            subprocess.run(
                satty_cmd + ["-f", "-"],
                stdin=grim_proc.stdout,
                check=True,
            )
            grim_proc.wait()

    except (subprocess.CalledProcessError, KeyboardInterrupt):
        return None

    return str(path) if path.exists() else None


def _focused_window_geo() -> str | None:
    """Get 'x,y wxh' geometry for the focused sway window."""
    try:
        tree = json.loads(
            subprocess.check_output(["swaymsg", "-t", "get_tree"], text=True)
        )
    except subprocess.CalledProcessError:
        return None
    return _walk_focused(tree)


def _walk_focused(node) -> str | None:
    if node.get("focused") and node.get("type") in ("con", "floating_con"):
        r = node["rect"]
        return f'{r["x"]},{r["y"]} {r["width"]}x{r["height"]}'
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        result = _walk_focused(child)
        if result:
            return result
    return None


def _focused_output_name() -> str | None:
    """Get the name of the focused output."""
    try:
        outputs = json.loads(
            subprocess.check_output(["swaymsg", "-t", "get_outputs"], text=True)
        )
        for o in outputs:
            if o.get("focused"):
                return o["name"]
    except subprocess.CalledProcessError:
        pass
    return None


def copy_to_clipboard(filepath: str):
    """Copy image to Wayland clipboard via wl-copy."""
    try:
        with open(filepath, "rb") as f:
            subprocess.Popen(
                ["wl-copy", "--type", "image/png"],
                stdin=f,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    except OSError:
        pass


# ══════════════════════════════════════════════════════════════════════════════
# Region Selector (replaces slurp — adds resize/move handles)
# ══════════════════════════════════════════════════════════════════════════════

def _region_select() -> str | None:
    """Interactive region selection with resize handles. Returns temp image path."""
    output = _focused_output_name()
    if not output:
        return None

    # Capture as PPM (uncompressed) to stdout — avoids slow PNG encode + disk I/O
    try:
        raw = subprocess.run(
            ["grim", "-t", "ppm", "-s", GRIM_SCALE, "-o", output, "-"],
            capture_output=True, check=True,
        ).stdout
    except subprocess.CalledProcessError:
        return None

    loader = GdkPixbuf.PixbufLoader()
    loader.write(raw)
    loader.close()
    full_pb = loader.get_pixbuf()
    if not full_pb:
        return None

    region = RegionSelector(full_pb).run()
    if not region:
        return None

    # Crop to selected region
    rx, ry, rw, rh = region
    iw, ih = full_pb.get_width(), full_pb.get_height()
    rx = max(0, min(rx, iw - 1))
    ry = max(0, min(ry, ih - 1))
    rw = min(rw, iw - rx)
    rh = min(rh, ih - ry)

    cropped = GdkPixbuf.Pixbuf.new(
        GdkPixbuf.Colorspace.RGB, full_pb.get_has_alpha(), 8, rw, rh
    )
    full_pb.copy_area(rx, ry, rw, rh, cropped, 0, 0)

    tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    tmp.close()
    cropped.savev(tmp.name, "png", [], [])
    return tmp.name


class RegionSelector:
    """Fullscreen overlay for drawing, resizing, and moving a selection."""

    def __init__(self, pixbuf):
        self._full_pb = pixbuf
        self._result = None
        self._win_w = self._win_h = 0
        self._sx = self._sy = 1.0

        # Selection: [x, y, w, h] in window (logical) coords
        self._sel = None
        self._state = "idle"  # idle | drawing | ready | moving | resizing
        self._drag_start = None
        self._drag_sel = None
        self._handle = None

        self._build_ui()

    def run(self) -> tuple[int, int, int, int] | None:
        """Block until confirm/cancel. Returns (x,y,w,h) in image pixels."""
        Gtk.main()
        return self._result

    def _build_ui(self):
        win = Gtk.Window()
        vis = win.get_screen().get_rgba_visual()
        if vis:
            win.set_visual(vis)
        win.set_app_paintable(True)

        GtkLayerShell.init_for_window(win)
        GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY)
        for edge in (
            GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
            GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT,
        ):
            GtkLayerShell.set_anchor(win, edge, True)
        GtkLayerShell.set_exclusive_zone(win, -1)
        GtkLayerShell.set_namespace(win, "screenshot-select")
        GtkLayerShell.set_keyboard_mode(
            win, GtkLayerShell.KeyboardMode.EXCLUSIVE
        )

        area = Gtk.DrawingArea()
        area.set_events(
            Gdk.EventMask.BUTTON_PRESS_MASK
            | Gdk.EventMask.BUTTON_RELEASE_MASK
            | Gdk.EventMask.POINTER_MOTION_MASK
        )
        area.connect("draw", self._on_draw)
        area.connect("button-press-event", self._on_press)
        area.connect("button-release-event", self._on_release)
        area.connect("motion-notify-event", self._on_motion)
        area.connect("size-allocate", self._on_size_allocate)
        area.connect("realize", self._on_realize)

        win.add(area)
        win.connect("key-press-event", self._on_key)
        win.show_all()
        self._win = win
        self._area = area

    def _on_realize(self, widget):
        cursor = Gdk.Cursor.new_from_name(widget.get_display(), "crosshair")
        widget.get_window().set_cursor(cursor)

    def _on_size_allocate(self, widget, alloc):
        if alloc.width == self._win_w and alloc.height == self._win_h:
            return
        self._win_w = alloc.width
        self._win_h = alloc.height
        self._sx = self._full_pb.get_width() / self._win_w
        self._sy = self._full_pb.get_height() / self._win_h

    # ── Drawing ───────────────────────────────────────────────────────────

    def _on_draw(self, _widget, cr):
        if not self._win_w:
            return False

        # Frozen screenshot — render full-res, let cairo handle device scaling
        cr.save()
        cr.scale(1.0 / self._sx, 1.0 / self._sy)
        Gdk.cairo_set_source_pixbuf(cr, self._full_pb, 0, 0)
        cr.get_source().set_filter(cairo.Filter.BILINEAR)
        cr.paint()
        cr.restore()

        # Dark overlay
        cr.set_source_rgba(0, 0, 0, OVERLAY_ALPHA)
        cr.rectangle(0, 0, self._win_w, self._win_h)
        cr.fill()

        if not self._sel:
            return True

        x, y, w, h = self._sel

        # Clear selection (show original brightness)
        cr.save()
        cr.rectangle(x, y, w, h)
        cr.clip()
        cr.scale(1.0 / self._sx, 1.0 / self._sy)
        Gdk.cairo_set_source_pixbuf(cr, self._full_pb, 0, 0)
        cr.get_source().set_filter(cairo.Filter.BILINEAR)
        cr.paint()
        cr.restore()

        # Selection border
        cr.set_source_rgba(*YELLOW, 1.0)
        cr.rectangle(x + 0.5, y + 0.5, w - 1, h - 1)
        cr.set_line_width(2)
        cr.stroke()

        # Resize handles
        if self._state in ("ready", "moving", "resizing"):
            hr = HANDLE_RADIUS
            for hx, hy in self._handles():
                cr.set_source_rgba(1, 1, 1, 0.9)
                cr.rectangle(hx - hr, hy - hr, hr * 2, hr * 2)
                cr.fill()
                cr.set_source_rgba(*YELLOW, 1.0)
                cr.rectangle(hx - hr + 0.5, hy - hr + 0.5,
                             hr * 2 - 1, hr * 2 - 1)
                cr.set_line_width(1)
                cr.stroke()

        # Dimension label
        img_w = int(w * self._sx)
        img_h = int(h * self._sy)
        dim = f"{img_w} \u00d7 {img_h}"
        cr.select_font_face(
            "Iosevka Nerd Font",
            cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL,
        )
        cr.set_font_size(14)
        ext = cr.text_extents(dim)
        tx = x + (w - ext.width) / 2
        ty = (y - 10) if y > 28 else (y + h + 20)

        cr.set_source_rgba(*BG, 0.8)
        _rounded_rect(cr, tx - 8, ty - ext.height - 4,
                       ext.width + 16, ext.height + 8, 4)
        cr.fill()
        cr.set_source_rgba(*FG, 0.9)
        cr.move_to(tx, ty)
        cr.show_text(dim)

        return True

    # ── Handle geometry ───────────────────────────────────────────────────

    def _handles(self):
        """8 positions: TL, TC, TR, RC, BR, BC, BL, LC."""
        x, y, w, h = self._sel
        mx, my = x + w / 2, y + h / 2
        return [
            (x, y), (mx, y), (x + w, y), (x + w, my),
            (x + w, y + h), (mx, y + h), (x, y + h), (x, my),
        ]

    def _hit_handle(self, mx, my):
        if not self._sel:
            return None
        for i, (hx, hy) in enumerate(self._handles()):
            if abs(mx - hx) < HANDLE_HIT and abs(my - hy) < HANDLE_HIT:
                return i
        return None

    def _inside(self, mx, my):
        if not self._sel:
            return False
        x, y, w, h = self._sel
        return x <= mx <= x + w and y <= my <= y + h

    # ── Mouse ─────────────────────────────────────────────────────────────

    def _on_press(self, _widget, event):
        if event.button != 1:
            return True
        mx, my = event.x, event.y
        self._drag_start = (mx, my)

        handle = self._hit_handle(mx, my)
        if handle is not None:
            self._state = "resizing"
            self._handle = handle
            self._drag_sel = list(self._sel)
        elif self._inside(mx, my):
            self._state = "moving"
            self._drag_sel = list(self._sel)
        else:
            self._state = "drawing"
            self._sel = [mx, my, 0, 0]
        return True

    def _on_release(self, _widget, event):
        if event.button != 1:
            return True
        if self._sel:
            self._normalize()
            if self._sel[2] >= MIN_SELECTION and self._sel[3] >= MIN_SELECTION:
                self._state = "ready"
            else:
                self._sel = None
                self._state = "idle"
        else:
            self._state = "idle"
        self._area.queue_draw()
        self._update_cursor(event.x, event.y)
        return True

    def _on_motion(self, _widget, event):
        mx, my = event.x, event.y

        if self._state == "drawing":
            sx, sy = self._drag_start
            self._sel = [min(sx, mx), min(sy, my),
                         abs(mx - sx), abs(my - sy)]
            self._area.queue_draw()

        elif self._state == "moving":
            dx = mx - self._drag_start[0]
            dy = my - self._drag_start[1]
            ox, oy, ow, oh = self._drag_sel
            nx = max(0, min(ox + dx, self._win_w - ow))
            ny = max(0, min(oy + dy, self._win_h - oh))
            self._sel = [nx, ny, ow, oh]
            self._area.queue_draw()

        elif self._state == "resizing":
            dx = mx - self._drag_start[0]
            dy = my - self._drag_start[1]
            self._apply_resize(dx, dy)
            self._area.queue_draw()

        else:
            self._update_cursor(mx, my)

        return True

    def _apply_resize(self, dx, dy):
        ox, oy, ow, oh = self._drag_sel
        h = self._handle
        x, y, w, ht = ox, oy, ow, oh

        if h in (0, 6, 7):
            x += dx; w -= dx
        if h in (2, 3, 4):
            w += dx
        if h in (0, 1, 2):
            y += dy; ht -= dy
        if h in (4, 5, 6):
            ht += dy

        self._sel = [x, y, w, ht]

    def _normalize(self):
        x, y, w, h = self._sel
        if w < 0:
            x += w; w = -w
        if h < 0:
            y += h; h = -h
        x = max(0, x)
        y = max(0, y)
        w = min(w, self._win_w - x)
        h = min(h, self._win_h - y)
        self._sel = [x, y, w, h]

    def _update_cursor(self, mx, my):
        handle = self._hit_handle(mx, my)
        if handle is not None:
            name = HANDLE_CURSORS[handle]
        elif self._inside(mx, my):
            name = "move"
        else:
            name = "crosshair"
        cursor = Gdk.Cursor.new_from_name(self._area.get_display(), name)
        self._area.get_window().set_cursor(cursor)

    # ── Keyboard ──────────────────────────────────────────────────────────

    def _on_key(self, _widget, event):
        key = event.keyval
        shift = bool(event.state & Gdk.ModifierType.SHIFT_MASK)

        if key == Gdk.KEY_Escape:
            self._cancel()
        elif key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self._confirm()
        elif self._sel and key in (
            Gdk.KEY_Left, Gdk.KEY_Right, Gdk.KEY_Up, Gdk.KEY_Down,
        ):
            step = 10 if shift else 1
            x, y, w, h = self._sel
            if key == Gdk.KEY_Left:
                x = max(0, x - step)
            elif key == Gdk.KEY_Right:
                x = min(self._win_w - w, x + step)
            elif key == Gdk.KEY_Up:
                y = max(0, y - step)
            elif key == Gdk.KEY_Down:
                y = min(self._win_h - h, y + step)
            self._sel = [x, y, w, h]
            self._area.queue_draw()

    def _confirm(self):
        if self._sel and self._sel[2] >= MIN_SELECTION and self._sel[3] >= MIN_SELECTION:
            x, y, w, h = self._sel
            self._result = (
                int(x * self._sx), int(y * self._sy),
                int(w * self._sx), int(h * self._sy),
            )
        self._win.hide()
        self._win.destroy()
        Gtk.main_quit()

    def _cancel(self):
        self._result = None
        self._win.hide()
        self._win.destroy()
        Gtk.main_quit()


# ══════════════════════════════════════════════════════════════════════════════
# Thumbnail Overlay
# ══════════════════════════════════════════════════════════════════════════════

class ThumbnailOverlay:
    """macOS-style floating screenshot preview — bottom-right corner."""

    def __init__(self, filepath: str):
        self._filepath = filepath
        self._progress = 1.0
        self._tick_id = None
        self._gtk_dragging = False
        self._build_ui()
        self._start_countdown()

    def _build_ui(self):
        # Load & scale image
        pixbuf = GdkPixbuf.Pixbuf.new_from_file(self._filepath)
        scale = min(THUMB_MAX_W / pixbuf.get_width(), 1.0)
        self._thumb_w = int(pixbuf.get_width() * scale)
        self._thumb_h = int(pixbuf.get_height() * scale)
        self._pixbuf = pixbuf.scale_simple(
            self._thumb_w, self._thumb_h, GdkPixbuf.InterpType.BILINEAR
        )

        pad = SHADOW_SIZE + 2
        win_w = self._thumb_w + pad * 2
        win_h = self._thumb_h + pad * 2 + PROGRESS_HEIGHT + 4

        # Window
        win = Gtk.Window()
        vis = win.get_screen().get_rgba_visual()
        if vis:
            win.set_visual(vis)
        win.set_app_paintable(True)
        win.set_size_request(win_w, win_h)

        # Layer shell — bottom-right overlay
        GtkLayerShell.init_for_window(win)
        GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.BOTTOM, True)
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_margin(win, GtkLayerShell.Edge.BOTTOM, THUMB_MARGIN)
        GtkLayerShell.set_margin(win, GtkLayerShell.Edge.RIGHT, THUMB_MARGIN)
        GtkLayerShell.set_namespace(win, "screenshot-thumb")
        GtkLayerShell.set_keyboard_mode(
            win, GtkLayerShell.KeyboardMode.NONE
        )

        # Drawing
        area = Gtk.DrawingArea()
        area.set_size_request(win_w, win_h)
        area.connect("draw", self._on_draw)

        # Events
        ebox = Gtk.EventBox()
        ebox.add(area)

        # GTK native drag-and-drop (drag directly from thumbnail)
        ebox.drag_source_set(
            Gdk.ModifierType.BUTTON1_MASK,
            [Gtk.TargetEntry.new("text/uri-list", 0, 0)],
            Gdk.DragAction.COPY,
        )
        ebox.connect("drag-begin", self._on_drag_begin)
        ebox.connect("drag-data-get", self._on_drag_data_get)
        ebox.connect("drag-end", self._on_drag_end)

        # Click handling (release without drag = click)
        ebox.connect("button-press-event", self._on_press)
        ebox.connect("button-release-event", self._on_release)
        ebox.connect("realize", self._set_cursor)

        win.add(ebox)
        win.connect("draw", self._clear_bg)
        win.show_all()
        self._win = win
        self._area = area

    def _set_cursor(self, widget):
        cursor = Gdk.Cursor.new_from_name(widget.get_display(), "pointer")
        widget.get_window().set_cursor(cursor)

    @staticmethod
    def _clear_bg(_widget, cr):
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        return False

    def _on_draw(self, _widget, cr):
        pad = SHADOW_SIZE + 2
        x0, y0 = pad, pad
        w, h = self._thumb_w, self._thumb_h
        r = CORNER_RADIUS

        # Shadow
        for i in range(1, SHADOW_SIZE + 1):
            alpha = 0.12 * (1 - i / (SHADOW_SIZE + 1))
            cr.set_source_rgba(0, 0, 0, alpha)
            _rounded_rect(cr, x0 - i, y0 - i, w + i * 2, h + i * 2, r + i)
            cr.fill()

        # Clipped image
        _rounded_rect(cr, x0, y0, w, h, r)
        cr.clip()
        Gdk.cairo_set_source_pixbuf(cr, self._pixbuf, x0, y0)
        cr.paint()
        cr.reset_clip()

        # Border
        cr.set_source_rgba(*BORDER, 0.8)
        _rounded_rect(cr, x0 + 0.5, y0 + 0.5, w - 1, h - 1, r)
        cr.set_line_width(1)
        cr.stroke()

        # Progress bar
        bar_y = y0 + h + 4
        bar_w = w * self._progress
        if bar_w > 1:
            cr.set_source_rgba(*YELLOW, 0.85)
            _rounded_rect(
                cr, x0, bar_y, bar_w, PROGRESS_HEIGHT, PROGRESS_HEIGHT / 2
            )
            cr.fill()

        return True

    # ── Interaction ───────────────────────────────────────────────────────

    def _on_press(self, _widget, event):
        self._gtk_dragging = False
        self._stop_countdown()
        return False  # let GTK DnD machinery process the press too

    def _on_release(self, _widget, event):
        if self._gtk_dragging:
            return True
        if event.button == 1:
            self._open_editor()
        elif event.button == 2:
            # Middle-click → ripdrag fallback
            self._ripdrag_fallback()
        elif event.button == 3:
            self._dismiss()
        return True

    # ── GTK native drag-and-drop ──────────────────────────────────────────

    def _on_drag_begin(self, widget, context):
        """Drag started — set thumbnail as drag icon."""
        self._gtk_dragging = True
        Gtk.drag_set_icon_pixbuf(context, self._pixbuf, 0, 0)

    def _on_drag_data_get(self, _widget, _context, data, _info, _time):
        """Provide file URI to the drop target."""
        data.set_uris([f"file://{self._filepath}"])

    def _on_drag_end(self, _widget, _context):
        """Drag finished (successful or cancelled) — dismiss."""
        self._dismiss()

    def _ripdrag_fallback(self):
        """Middle-click fallback: spawn ripdrag window."""
        self._win.hide()
        try:
            subprocess.Popen(
                ["ripdrag", "-x", self._filepath],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except FileNotFoundError:
            pass
        GLib.timeout_add(300, self._quit)

    def _open_editor(self):
        """Re-open in satty for further annotation."""
        self._win.hide()
        subprocess.Popen(
            [
                "satty",
                "-f", self._filepath,
                "-o", self._filepath,
                "--copy-command", "wl-copy",
                "--early-exit",
                "--font-family", "Iosevka Nerd Font",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        GLib.timeout_add(200, self._quit)

    def _dismiss(self):
        self._stop_countdown()
        self._win.hide()
        self._quit()

    @staticmethod
    def _quit():
        Gtk.main_quit()
        return False

    # ── Countdown ─────────────────────────────────────────────────────────

    def _start_countdown(self):
        interval = 50  # ms — smooth animation
        step = interval / THUMB_TIMEOUT_MS

        def tick():
            self._progress -= step
            if self._progress <= 0:
                self._dismiss()
                return False
            self._area.queue_draw()
            return True

        self._tick_id = GLib.timeout_add(interval, tick)

    def _stop_countdown(self):
        if self._tick_id:
            GLib.source_remove(self._tick_id)
            self._tick_id = None


# ══════════════════════════════════════════════════════════════════════════════
# Capture Toolbar  (macOS Cmd+Shift+5 equivalent)
# ══════════════════════════════════════════════════════════════════════════════

class CaptureToolbar:
    """Screenshot mode-picker toolbar — bottom-center overlay."""

    MODES = [
        ("region", "\U000f0643", "Region"),   # 󰙃  nf-md-crop
        ("window", "\U000f1066", "Window"),   # 󱁦  nf-md-dock_window
        ("screen", "\U000f0379", "Screen"),   # 󰍹  nf-md-monitor
    ]
    TIMERS = [0, 3, 5, 10]

    def __init__(self):
        self._timer_idx = 0
        self._build_ui()

    def _build_ui(self):
        css = Gtk.CssProvider()
        css.load_from_data(self._css())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        # ── Backdrop ──────────────────────────────────────────────────────
        self._backdrop = Gtk.Window()
        vis = self._backdrop.get_screen().get_rgba_visual()
        if vis:
            self._backdrop.set_visual(vis)
        self._backdrop.set_app_paintable(True)

        GtkLayerShell.init_for_window(self._backdrop)
        GtkLayerShell.set_layer(self._backdrop, GtkLayerShell.Layer.OVERLAY)
        for edge in (
            GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
            GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT,
        ):
            GtkLayerShell.set_anchor(self._backdrop, edge, True)
        GtkLayerShell.set_namespace(self._backdrop, "screenshot-backdrop")
        GtkLayerShell.set_keyboard_mode(
            self._backdrop, GtkLayerShell.KeyboardMode.NONE
        )
        self._backdrop.connect("draw", self._draw_backdrop)
        self._backdrop.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self._backdrop.connect(
            "button-press-event", lambda *_: self._cancel()
        )

        # ── Toolbar window ────────────────────────────────────────────────
        win = Gtk.Window()
        vis = win.get_screen().get_rgba_visual()
        if vis:
            win.set_visual(vis)
        win.set_app_paintable(True)
        win.connect("draw", self._clear_bg)
        win.connect("key-press-event", self._on_key)

        GtkLayerShell.init_for_window(win)
        GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.BOTTOM, True)
        GtkLayerShell.set_margin(win, GtkLayerShell.Edge.BOTTOM, 80)
        GtkLayerShell.set_namespace(win, "screenshot-toolbar")
        GtkLayerShell.set_keyboard_mode(
            win, GtkLayerShell.KeyboardMode.EXCLUSIVE
        )

        # ── Buttons ───────────────────────────────────────────────────────
        frame = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        frame.get_style_context().add_class("tb-frame")

        for mode_id, icon, label in self.MODES:
            btn = self._make_button(icon, label)
            btn.connect("clicked", self._on_mode, mode_id)
            frame.pack_start(btn, False, False, 0)

        # Separator
        sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        sep.get_style_context().add_class("tb-sep")
        frame.pack_start(sep, False, False, 0)

        # Timer toggle
        self._timer_btn = self._make_button("\U000f13ab", "Off")  # 󰎫 timer
        self._timer_btn.get_style_context().add_class("timer")
        self._timer_btn.connect("clicked", self._on_timer)
        frame.pack_start(self._timer_btn, False, False, 0)
        self._timer_label = (
            self._timer_btn.get_child().get_children()[1]
        )

        win.add(frame)
        self._backdrop.show_all()
        win.show_all()
        self._win = win

    @staticmethod
    def _make_button(icon_text: str, label_text: str) -> Gtk.Button:
        btn = Gtk.Button()
        btn.get_style_context().add_class("tb-btn")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        icon = Gtk.Label(label=icon_text)
        icon.get_style_context().add_class("tb-icon")
        text = Gtk.Label(label=label_text)
        text.get_style_context().add_class("tb-text")
        box.pack_start(icon, False, False, 0)
        box.pack_start(text, False, False, 0)
        btn.add(box)
        return btn

    @staticmethod
    def _css() -> bytes:
        return b"""
        .tb-frame {
            background-color: rgba(40, 40, 40, 0.92);
            border: 1px solid rgba(80, 73, 69, 0.6);
            border-radius: 14px;
            padding: 8px 4px;
        }
        .tb-btn {
            background: none;
            background-image: none;
            border: none;
            box-shadow: none;
            border-radius: 10px;
            padding: 10px 20px;
            min-width: 56px;
        }
        .tb-btn:hover {
            background-color: rgba(60, 56, 54, 0.8);
            background-image: none;
        }
        .tb-icon {
            font-family: "Iosevka Nerd Font", "Symbols Nerd Font Mono";
            font-size: 24px;
            color: #ebdbb2;
        }
        .tb-text {
            font-family: "Iosevka Nerd Font";
            font-size: 11px;
            color: #a89984;
        }
        .tb-sep {
            background-color: #504945;
            min-width: 1px;
            margin: 8px 2px;
        }
        .timer.active .tb-icon,
        .timer.active .tb-text {
            color: #fabd2f;
        }
        """

    @staticmethod
    def _clear_bg(_widget, cr):
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        return False

    @staticmethod
    def _draw_backdrop(_widget, cr):
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0.15)
        cr.paint()
        return False

    def _on_key(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            self._cancel()

    def _on_mode(self, _btn, mode_id: str):
        delay = self.TIMERS[self._timer_idx]
        self._win.hide()
        self._backdrop.hide()
        args = [SCRIPT, mode_id]
        if delay > 0:
            args += ["--delay", str(delay)]
        subprocess.Popen(args)
        GLib.timeout_add(100, Gtk.main_quit)

    def _on_timer(self, _btn):
        self._timer_idx = (self._timer_idx + 1) % len(self.TIMERS)
        val = self.TIMERS[self._timer_idx]
        ctx = self._timer_btn.get_style_context()
        if val > 0:
            self._timer_label.set_text(f"{val}s")
            ctx.add_class("active")
        else:
            self._timer_label.set_text("Off")
            ctx.remove_class("active")

    def _cancel(self):
        self._win.hide()
        self._backdrop.hide()
        Gtk.main_quit()


# ══════════════════════════════════════════════════════════════════════════════
# Countdown Overlay
# ══════════════════════════════════════════════════════════════════════════════

class CountdownOverlay:
    """Large centered countdown number before timed capture."""

    def __init__(self, seconds: int, on_done):
        self._remaining = seconds
        self._on_done = on_done
        self._build_ui()

    def _build_ui(self):
        css = Gtk.CssProvider()
        css.load_from_data(b"""
        .cd-num {
            font-family: "Iosevka Nerd Font";
            font-size: 140px;
            font-weight: bold;
            color: rgba(235, 219, 178, 0.65);
        }
        """)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        win = Gtk.Window()
        vis = win.get_screen().get_rgba_visual()
        if vis:
            win.set_visual(vis)
        win.set_app_paintable(True)
        win.connect("draw", self._clear_bg)

        GtkLayerShell.init_for_window(win)
        GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_namespace(win, "screenshot-countdown")
        GtkLayerShell.set_keyboard_mode(
            win, GtkLayerShell.KeyboardMode.NONE
        )
        # Anchor all edges → fullscreen transparent, label centered
        for edge in (
            GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
            GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT,
        ):
            GtkLayerShell.set_anchor(win, edge, True)

        self._label = Gtk.Label(label=str(self._remaining))
        self._label.get_style_context().add_class("cd-num")
        self._label.set_valign(Gtk.Align.CENTER)
        self._label.set_halign(Gtk.Align.CENTER)
        win.add(self._label)

        win.show_all()
        self._win = win
        GLib.timeout_add(1000, self._tick)

    @staticmethod
    def _clear_bg(_widget, cr):
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        return False

    def _tick(self):
        self._remaining -= 1
        if self._remaining <= 0:
            self._win.hide()
            self._win.destroy()
            GLib.idle_add(self._on_done)
            return False
        self._label.set_text(str(self._remaining))
        return True


# ══════════════════════════════════════════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════════════════════════════════════════

def _rounded_rect(cr, x, y, w, h, r):
    """Draw a rounded-rectangle path."""
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


def _kill_existing():
    """Kill a previously running thumbnail overlay."""
    try:
        with open(PID_FILE) as f:
            os.kill(int(f.read().strip()), signal.SIGTERM)
        time.sleep(0.1)
    except (FileNotFoundError, ProcessLookupError, ValueError, OSError):
        pass


def _write_pid():
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))


def _cleanup_pid():
    try:
        os.unlink(PID_FILE)
    except FileNotFoundError:
        pass


# ══════════════════════════════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="Screenshot tool for Sway")
    parser.add_argument(
        "mode", choices=["region", "window", "screen", "all", "menu"],
    )
    parser.add_argument("--delay", type=int, default=0)
    args = parser.parse_args()

    # ── Menu mode ─────────────────────────────────────────────────────────
    if args.mode == "menu":
        _kill_existing()
        CaptureToolbar()
        Gtk.main()
        return

    # ── Capture helpers ───────────────────────────────────────────────────
    def show_thumbnail(filepath: str):
        _kill_existing()
        _write_pid()

        def quit_handler(*_):
            _cleanup_pid()
            Gtk.main_quit()
            return False

        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, quit_handler)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, quit_handler)
        ThumbnailOverlay(filepath)

    def do_capture():
        filepath = capture(args.mode)
        if not filepath:
            Gtk.main_quit()
            return
        show_thumbnail(filepath)

    # ── Timed capture ─────────────────────────────────────────────────────
    if args.delay > 0:
        CountdownOverlay(args.delay, do_capture)
        Gtk.main()
    else:
        # Capture synchronously first (slurp runs before GTK)
        filepath = capture(args.mode)
        if not filepath:
            sys.exit(0)
        _kill_existing()
        _write_pid()

        def quit_handler(*_):
            _cleanup_pid()
            Gtk.main_quit()
            return False

        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, quit_handler)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, quit_handler)
        ThumbnailOverlay(filepath)
        Gtk.main()


if __name__ == "__main__":
    main()