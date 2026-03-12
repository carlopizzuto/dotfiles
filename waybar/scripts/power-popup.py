#!/usr/bin/env python3
"""GTK popup menu for polybar using layer-shell (Wayland).

Reads items from stdin, prints selection to stdout.
Dismisses on outside click, Escape, or item selection.
"""

import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, Gtk, GtkLayerShell


class Backdrop(Gtk.Window):
    """Full-screen transparent overlay that catches clicks outside the menu."""

    def __init__(self):
        super().__init__()

        css = b"""
        #backdrop {
            background-color: transparent;
        }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        self.set_name("backdrop")

        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.BOTTOM, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_keyboard_mode(
            self, GtkLayerShell.KeyboardMode.NONE
        )

        self.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        self.connect("button-press-event", lambda *_: Gtk.main_quit())


class PopupMenu(Gtk.Window):
    def __init__(self, items):
        super().__init__()
        self.selected = None

        css = b"""
        #popup-frame {
            background-color: #282828;
            border: 1px solid #504945;
            padding: 8px 0;
        }
        row {
            background-color: #282828;
            padding: 0;
        }
        row:hover {
            background-color: #3c3836;
        }
        row label {
            color: #ebdbb2;
            padding: 10px 24px;
            font: 16px "Iosevka Nerd Font";
        }
        row:hover label {
            color: #fabd2f;
        }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        # Layer shell setup: overlay layer, top-right, exclusive keyboard
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 6)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.RIGHT, 10)
        GtkLayerShell.set_keyboard_mode(
            self, GtkLayerShell.KeyboardMode.EXCLUSIVE
        )

        # Build menu items
        frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        frame.set_name("popup-frame")

        listbox = Gtk.ListBox()
        listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        listbox.connect("row-activated", self._on_row_activated)

        for text in items:
            row = Gtk.ListBoxRow()
            label = Gtk.Label(label=text, xalign=0)
            row.add(label)
            listbox.add(row)

        frame.pack_start(listbox, True, True, 0)
        self.add(frame)

        # Dismiss on Escape
        self.connect("key-press-event", self._on_key_press)

    def _on_key_press(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            Gtk.main_quit()

    def _on_row_activated(self, _listbox, row):
        label = row.get_child()
        self.selected = label.get_text()
        Gtk.main_quit()


if __name__ == "__main__":
    items = [line.strip() for line in sys.stdin if line.strip()]
    if not items:
        sys.exit(1)

    backdrop = Backdrop()
    backdrop.show_all()

    pm = PopupMenu(items)
    pm.show_all()
    Gtk.main()

    if pm.selected:
        print(pm.selected)
    else:
        sys.exit(1)
