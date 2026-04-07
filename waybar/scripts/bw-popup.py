#!/usr/bin/env python3
"""Bitwarden vault popup using GTK3 layer-shell (Wayland).

Lists vault entries via rbw, supports search filtering,
left-click/Enter copies password, right-click copies username.
Clipboard auto-clears after 30 seconds.
"""

import subprocess

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, Gtk, GtkLayerShell


def load_entries():
    """Load vault entries from rbw list."""
    try:
        result = subprocess.run(
            ["rbw", "list", "--fields", "name,user,folder"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return []
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return []

    entries = []
    for line in result.stdout.strip().splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        entry = {
            "name": parts[0] if len(parts) > 0 else "",
            "user": parts[1] if len(parts) > 1 else "",
            "folder": parts[2] if len(parts) > 2 else "",
        }
        if entry["name"]:
            entries.append(entry)
    return entries


class Backdrop(Gtk.Window):
    """Full-screen transparent overlay that catches clicks outside the popup."""

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


class BitwardenPopup(Gtk.Window):
    def __init__(self, entries):
        super().__init__()
        self.entries = entries

        css = b"""
        #bw-popup {
            background-color: #282828;
            border: 1px solid #504945;
            padding: 8px 0;
        }
        #bw-search {
            background-color: #3c3836;
            color: #ebdbb2;
            border: 1px solid #504945;
            border-radius: 4px;
            padding: 8px 12px;
            margin: 4px 8px 8px 8px;
            font: 16px "Iosevka Nerd Font";
        }
        row {
            background-color: #282828;
            padding: 0;
        }
        row:hover {
            background-color: #3c3836;
        }
        .entry-name {
            color: #ebdbb2;
            padding: 6px 12px 0 12px;
            font: 15px "Iosevka Nerd Font";
        }
        row:hover .entry-name {
            color: #fabd2f;
        }
        .entry-user {
            color: #a89984;
            padding: 0 12px 6px 12px;
            font: 12px "Iosevka Nerd Font";
        }
        #empty-label {
            color: #928374;
            padding: 24px 12px;
            font: 14px "Iosevka Nerd Font";
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

        self.set_size_request(380, -1)

        # Main container
        frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        frame.set_name("bw-popup")

        # Search bar
        self.search = Gtk.Entry()
        self.search.set_name("bw-search")
        self.search.set_placeholder_text("Search vault...")
        self.search.connect("changed", self._on_search_changed)
        self.search.connect("activate", self._on_search_activate)
        frame.pack_start(self.search, False, False, 0)

        # Scrolled window for the list
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_max_content_height(560)
        scrolled.set_propagate_natural_height(True)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        # List box
        self.listbox = Gtk.ListBox()
        self.listbox.set_selection_mode(Gtk.SelectionMode.BROWSE)
        self.listbox.connect("row-activated", self._on_row_activated)
        self.listbox.set_filter_func(self._filter_func)

        for entry in self.entries:
            row = Gtk.ListBoxRow()
            row.entry_data = entry

            vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

            name_label = Gtk.Label(label=entry["name"], xalign=0)
            name_label.set_ellipsize(3)  # PANGO_ELLIPSIZE_END
            name_label.get_style_context().add_class("entry-name")
            vbox.pack_start(name_label, False, False, 0)

            user_text = entry.get("user", "")
            user_label = Gtk.Label(label=user_text if user_text else " ", xalign=0)
            user_label.set_ellipsize(3)
            user_label.get_style_context().add_class("entry-user")
            vbox.pack_start(user_label, False, False, 0)

            row.add(vbox)

            # Right-click to copy username
            row.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
            row.connect("button-press-event", self._on_row_button_press)

            self.listbox.add(row)

        scrolled.add(self.listbox)
        frame.pack_start(scrolled, True, True, 0)

        # Empty state label
        self.empty_label = Gtk.Label(label="No matching entries")
        self.empty_label.set_name("empty-label")
        self.empty_label.set_no_show_all(True)
        frame.pack_start(self.empty_label, False, False, 0)

        self.add(frame)

        # Dismiss on Escape
        self.connect("key-press-event", self._on_key_press)

    def _filter_func(self, row):
        query = self.search.get_text().lower()
        if not query:
            return True
        entry = row.entry_data
        name = entry.get("name", "").lower()
        user = entry.get("user", "").lower()
        return query in name or query in user

    def _on_search_changed(self, _entry):
        self.listbox.invalidate_filter()
        self._update_empty_state()

    def _update_empty_state(self):
        has_visible = False
        for row in self.listbox.get_children():
            if row.get_child_visible():
                # Check if the row passes the filter
                if self._filter_func(row):
                    has_visible = True
                    break
        if has_visible:
            self.empty_label.hide()
        else:
            self.empty_label.show()

    def _on_search_activate(self, _entry):
        """Enter in search bar activates first visible row."""
        for row in self.listbox.get_children():
            if self._filter_func(row):
                self.listbox.row_activated(row)
                return

    def _on_key_press(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            Gtk.main_quit()

    def _on_row_button_press(self, row, event):
        """Right-click copies username."""
        if event.button == 3:
            entry = row.entry_data
            user = entry.get("user", "")
            if user:
                self._copy_to_clipboard(user)
                subprocess.Popen(
                    ["notify-send", "-t", "3000", "Bitwarden", f"Username copied: {user}"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                self._schedule_clipboard_clear()
                Gtk.main_quit()
            return True
        return False

    def _on_row_activated(self, _listbox, row):
        """Left-click or Enter copies password."""
        entry = row.entry_data
        cmd = ["rbw", "get"]
        if entry.get("folder"):
            cmd.extend(["--folder", entry["folder"]])
        cmd.append(entry["name"])

        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                password = result.stdout.strip()
                self._copy_to_clipboard(password)
                subprocess.Popen(
                    ["notify-send", "-t", "3000", "Bitwarden", f"Password copied: {entry['name']}"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                self._schedule_clipboard_clear()
        except (subprocess.TimeoutExpired, FileNotFoundError):
            subprocess.Popen(
                ["notify-send", "-u", "critical", "-t", "5000", "Bitwarden", "Failed to get password"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )

        Gtk.main_quit()

    def _copy_to_clipboard(self, text):
        subprocess.Popen(
            ["wl-copy", text],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def _schedule_clipboard_clear(self):
        subprocess.Popen(
            ["bash", "-c", "sleep 30 && wl-copy --clear"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )


if __name__ == "__main__":
    entries = load_entries()
    if not entries:
        subprocess.run(
            ["notify-send", "-u", "critical", "-t", "5000", "Bitwarden", "No vault entries found (is rbw unlocked?)"],
        )
        raise SystemExit(1)

    backdrop = Backdrop()
    backdrop.show_all()

    popup = BitwardenPopup(entries)
    popup.show_all()

    popup.search.grab_focus()

    Gtk.main()
