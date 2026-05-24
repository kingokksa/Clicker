"""Configuration persistence module.

Saves/loads app settings as JSON profiles.
"""

import json
import os
from dataclasses import dataclass, field, asdict
from typing import Optional


PROFILES_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "profiles"
)
MACROS_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "macros"
)


@dataclass
class ClickerConfig:
    """Auto-clicker configuration."""

    click_type: str = "single"  # single | double
    mouse_button: str = "left"  # left | right | middle
    position_mode: str = "current"  # current | fixed
    fixed_x: int = 0
    fixed_y: int = 0
    interval_ms: int = 100  # milliseconds between clicks
    repeat_mode: str = "infinite"  # infinite | count | duration
    repeat_count: int = 100
    duration_seconds: int = 60


@dataclass
class HotkeyConfig:
    """Hotkey configuration."""

    start_stop_clicker: str = "f6"
    start_stop_recording: str = "f8"
    emergency_stop: str = "f12"
    play_macro: str = "f9"


@dataclass
class MacroEvent:
    """A single recorded macro event."""

    event_type: str  # click | key_press | key_release | scroll | wait
    timestamp: float = 0.0
    button: Optional[str] = None  # left | right | middle
    x: int = 0
    y: int = 0
    pressed: bool = True
    key: Optional[str] = None
    dx: int = 0  # scroll delta
    dy: int = 0


@dataclass
class MacroConfig:
    """A saved macro."""

    name: str = "Unnamed"
    events: list = field(default_factory=list)
    repeat: int = 1
    speed: float = 1.0  # playback speed multiplier
    created_at: str = ""

    def to_dict(self) -> dict:
        d = asdict(self)
        return d

    @classmethod
    def from_dict(cls, d: dict) -> "MacroConfig":
        events = []
        for e in d.get("events", []):
            events.append(MacroEvent(**e))
        return cls(
            name=d.get("name", "Unnamed"),
            events=events,
            repeat=d.get("repeat", 1),
            speed=d.get("speed", 1.0),
            created_at=d.get("created_at", ""),
        )


@dataclass
class AppConfig:
    """Full application configuration."""

    clicker: ClickerConfig = field(default_factory=ClickerConfig)
    hotkeys: HotkeyConfig = field(default_factory=HotkeyConfig)
    theme: str = "dark"  # dark | light | system
    always_on_top: bool = True

    def to_dict(self) -> dict:
        return {
            "clicker": asdict(self.clicker),
            "hotkeys": asdict(self.hotkeys),
            "theme": self.theme,
            "always_on_top": self.always_on_top,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "AppConfig":
        clicker = ClickerConfig(**d.get("clicker", {}))
        hotkeys = HotkeyConfig(**d.get("hotkeys", {}))
        return cls(
            clicker=clicker,
            hotkeys=hotkeys,
            theme=d.get("theme", "dark"),
            always_on_top=d.get("always_on_top", True),
        )


def ensure_dirs():
    """Ensure required directories exist."""
    os.makedirs(PROFILES_DIR, exist_ok=True)
    os.makedirs(MACROS_DIR, exist_ok=True)


def load_app_config() -> AppConfig:
    """Load app config from default location."""
    ensure_dirs()
    path = os.path.join(PROFILES_DIR, "config.json")
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return AppConfig.from_dict(json.load(f))
    return AppConfig()


def save_app_config(config: AppConfig):
    """Save app config to default location."""
    ensure_dirs()
    path = os.path.join(PROFILES_DIR, "config.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(config.to_dict(), f, indent=2, ensure_ascii=False)


def load_profile(name: str) -> AppConfig:
    """Load a named profile."""
    path = os.path.join(PROFILES_DIR, f"{name}.json")
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return AppConfig.from_dict(json.load(f))
    raise FileNotFoundError(f"Profile '{name}' not found")


def save_profile(name: str, config: AppConfig):
    """Save a named profile."""
    ensure_dirs()
    path = os.path.join(PROFILES_DIR, f"{name}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(config.to_dict(), f, indent=2, ensure_ascii=False)


def list_profiles() -> list:
    """List all saved profiles."""
    ensure_dirs()
    profiles = []
    for f in os.listdir(PROFILES_DIR):
        if f.endswith(".json") and f != "config.json":
            profiles.append(f.replace(".json", ""))
    return profiles


def save_macro(macro: MacroConfig, filename: str = None):
    """Save a macro to disk."""
    ensure_dirs()
    if filename is None:
        filename = f"{macro.name}.json"
    path = os.path.join(MACROS_DIR, filename)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(macro.to_dict(), f, indent=2, ensure_ascii=False)
    return filename


def load_macro(filename: str) -> MacroConfig:
    """Load a macro from disk."""
    path = os.path.join(MACROS_DIR, filename)
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return MacroConfig.from_dict(json.load(f))
    raise FileNotFoundError(f"Macro '{filename}' not found")


def list_macros() -> list:
    """List all saved macros."""
    ensure_dirs()
    macros = []
    for f in os.listdir(MACROS_DIR):
        if f.endswith(".json"):
            macros.append(f)
    return macros


def delete_macro(filename: str):
    """Delete a macro file."""
    path = os.path.join(MACROS_DIR, filename)
    if os.path.exists(path):
        os.remove(path)
