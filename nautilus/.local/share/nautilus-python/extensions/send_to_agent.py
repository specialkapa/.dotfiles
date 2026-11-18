import os
import re
import shutil

from gi import require_version

require_version("Nautilus", "4.1")

from gi.repository import GObject, Gio, Nautilus

# Mention selected files in a live session of the Omarchy default AI agent
# (`omarchy default agent`). The work is done by ~/.local/bin/send-to-agent.

AGENT_FILE = os.path.expanduser("~/.config/omarchy/defaults/agent")
NAMES = {
    "claude": "Claude", "codex": "Codex", "opencode": "OpenCode", "pi": "Pi",
    "omp": "Oh My Pi", "agy": "Antigravity", "copilot": "Copilot",
    "cursor-agent": "Cursor", "amp": "Amp", "qwen": "Qwen", "kimi": "Kimi",
    "crush": "Crush", "grok": "Grok",
}


ACCELS_FILE = os.path.expanduser("~/.config/nautilus/scripts-accels")
HOTKEY_SCRIPT = "Send to AI Agent"  # ~/.local/share/nautilus/scripts/<this>
MODS = {"control": "Ctrl", "primary": "Ctrl", "ctrl": "Ctrl", "alt": "Alt",
        "shift": "Shift", "super": "Super", "meta": "Meta"}


def hotkey():
    """The script's shortcut from scripts-accels, as e.g. "Ctrl+Alt+C".

    Extension menu items can't carry a real accelerator, so the hint goes in
    the label instead; it follows any change made in scripts-accels."""
    try:
        with open(ACCELS_FILE) as f:
            for line in f:
                accel, _, name = line.strip().partition(" ")
                if name == HOTKEY_SCRIPT and accel:
                    mods = re.findall(r"<([^>]+)>", accel)
                    key = re.sub(r"<[^>]+>", "", accel)
                    parts = [MODS.get(m.lower(), m.title()) for m in mods]
                    return "+".join(parts + [key.upper() if len(key) == 1 else key])
    except OSError:
        pass
    return ""


def agent_name():
    try:
        with open(AGENT_FILE) as f:
            agent = f.readline().strip()
    except OSError:
        agent = ""
    return NAMES.get(agent, agent) or "Claude"


class SendToAgentAction(GObject.GObject, Nautilus.MenuProvider):
    def _helper(self):
        return shutil.which("send-to-agent") or os.path.expanduser("~/.local/bin/send-to-agent")

    def _send(self, _menu, files):
        paths = [f.get_location().get_path() for f in files]
        paths = [p for p in paths if p]
        if paths:
            Gio.Subprocess.new([self._helper(), *paths], Gio.SubprocessFlags.NONE)

    def get_file_items(self, *args):
        files = args[-1]
        if not files or not all(f.get_location().get_path() for f in files):
            return []
        name = agent_name()
        item = Nautilus.MenuItem(
            name="SendToAgent::send",
            label=f"Send to {name}" + (f"    ({key})" if (key := hotkey()) else ""),
            tip=f"Mention the selected file(s) in a live {name} session",
        )
        item.connect("activate", self._send, files)
        return [item]
