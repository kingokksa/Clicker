"""Screen utilities — position picker overlay and screen info."""

import tkinter as tk
import pyautogui
from typing import Optional


class PositionPicker:
    """Fullscreen overlay for picking a click position.

    Shows a crosshair cursor. User clicks to pick, Esc to cancel.
    """

    def __init__(self, master=None):
        self.master = master
        self.result: Optional[tuple[int, int]] = None
        self._win: Optional[tk.Toplevel] = None
        self._running = False

    def pick(self) -> Optional[tuple[int, int]]:
        """Show picker overlay. Returns (x, y) or None if cancelled."""
        self.result = None
        self._win = tk.Toplevel(self.master)
        self._win.attributes("-fullscreen", True)
        self._win.attributes("-topmost", True)
        self._win.attributes("-alpha", 0.3)
        self._win.configure(bg="black")
        self._win.config(cursor="crosshair")

        # Instructions label
        label = tk.Label(
            self._win,
            text="🖱  Click to pick a position  |  Esc to cancel",
            font=("Segoe UI", 18, "bold"),
            bg="#1a1a2e",
            fg="#00ff88",
            padx=40,
            pady=20,
        )
        label.place(relx=0.5, rely=0.1, anchor="center")

        # Crosshair lines
        canvas = tk.Canvas(self._win, bg="black", highlightthickness=0)
        canvas.place(relx=0, rely=0, relwidth=1, relheight=1)

        win = self._win
        assert win is not None

        def on_motion(e):
            canvas.delete("crosshair")
            w, h = win.winfo_width(), win.winfo_height()
            canvas.create_line(
                e.x, 0, e.x, h, fill="#00ff88", width=2, tags="crosshair"
            )
            canvas.create_line(
                0, e.y, w, e.y, fill="#00ff88", width=2, tags="crosshair"
            )
            # Coordinates label
            canvas.create_text(
                e.x + 20,
                e.y - 20,
                text=f"({e.x}, {e.y})",
                fill="#00ff88",
                font=("Consolas", 14, "bold"),
                tags="crosshair",
                anchor="sw",
            )

        def on_click(e):
            self.result = (e.x, e.y)
            win.destroy()

        def on_key(e):
            if e.keysym == "Escape":
                self.result = None
                win.destroy()

        canvas.bind("<Motion>", on_motion)
        canvas.bind("<Button-1>", on_click)
        self._win.bind("<Key>", on_key)
        self._win.focus_force()
        self._win.grab_set()

        self._win.wait_window()
        return self.result


def get_screen_size() -> tuple[int, int]:
    """Get primary screen size."""
    return pyautogui.size()


def is_point_on_screen(x: int, y: int) -> bool:
    """Check if a point is within screen bounds."""
    w, h = get_screen_size()
    return 0 <= x <= w and 0 <= y <= h
