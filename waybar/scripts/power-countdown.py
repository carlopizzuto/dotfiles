#!/usr/bin/env python3
"""Countdown popup for power actions (shutdown, restart, logout)."""

import subprocess
import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk


class CountdownWindow(Gtk.Window):
    def __init__(self, action_name, command, seconds=60):
        super().__init__(title=action_name)
        self.command = command
        self.remaining = seconds
        self.action_name = action_name

        # Gruvbox Dark CSS
        css = b"""
        window {
            background-color: #282828;
            border: 2px solid #504945;
        }
        label {
            color: #ebdbb2;
        }
        .action-label {
            font-size: 22px;
            font-weight: bold;
            color: #fabd2f;
        }
        .timer-label {
            font-size: 64px;
            font-weight: bold;
            color: #fb4934;
        }
        .message-label {
            font-size: 14px;
            color: #a89984;
        }
        .now-button {
            background-color: #cc241d;
            background-image: none;
            color: #ebdbb2;
            border: 1px solid #fb4934;
            border-radius: 4px;
            padding: 10px 32px;
            font-size: 15px;
            font-weight: bold;
        }
        .now-button:hover {
            background-color: #fb4934;
            background-image: none;
        }
        .cancel-button {
            background-color: #3c3836;
            background-image: none;
            color: #ebdbb2;
            border: 1px solid #504945;
            border-radius: 4px;
            padding: 10px 32px;
            font-size: 15px;
            font-weight: bold;
        }
        .cancel-button:hover {
            background-color: #504945;
            background-image: none;
        }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        # Window setup — DIALOG hint makes i3 float it automatically
        self.set_default_size(380, 240)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_resizable(False)
        self.set_decorated(False)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)
        self.set_keep_above(True)

        # Layout
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        vbox.set_margin_top(30)
        vbox.set_margin_bottom(25)
        vbox.set_margin_start(30)
        vbox.set_margin_end(30)

        # Action name
        action_label = Gtk.Label(label=action_name)
        action_label.get_style_context().add_class("action-label")
        vbox.pack_start(action_label, False, False, 0)

        # Countdown number
        self.timer_label = Gtk.Label(label=str(self.remaining))
        self.timer_label.get_style_context().add_class("timer-label")
        vbox.pack_start(self.timer_label, True, True, 0)

        # Hint text
        hint = Gtk.Label(label="Press Enter to do it now, Escape to cancel")
        hint.get_style_context().add_class("message-label")
        vbox.pack_start(hint, False, False, 0)

        # Buttons
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        btn_box.set_halign(Gtk.Align.CENTER)

        now_btn = Gtk.Button(label=f"{action_name} Now")
        now_btn.get_style_context().add_class("now-button")
        now_btn.connect("clicked", lambda _: self.execute_action())
        btn_box.pack_start(now_btn, False, False, 0)

        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.get_style_context().add_class("cancel-button")
        cancel_btn.connect("clicked", lambda _: Gtk.main_quit())
        btn_box.pack_start(cancel_btn, False, False, 0)

        vbox.pack_start(btn_box, False, False, 5)

        self.add(vbox)

        # Keyboard & close handlers
        self.connect("key-press-event", self.on_key_press)
        self.connect("destroy", lambda _: Gtk.main_quit())

        # Start ticking
        GLib.timeout_add_seconds(1, self.tick)

    def tick(self):
        self.remaining -= 1
        self.timer_label.set_text(str(self.remaining))
        if self.remaining <= 0:
            self.execute_action()
            return False
        return True

    def on_key_press(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            Gtk.main_quit()
        elif event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self.execute_action()

    def execute_action(self):
        subprocess.Popen(self.command, shell=True)
        Gtk.main_quit()


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <action_name> <command> [seconds]")
        sys.exit(1)

    name = sys.argv[1]
    cmd = sys.argv[2]
    secs = int(sys.argv[3]) if len(sys.argv) > 3 else 60

    win = CountdownWindow(name, cmd, secs)
    win.show_all()
    Gtk.main()
