#!/usr/bin/env python3
"""Workspace Peek helper.

Follows Hyprland's event socket and prints JSON lines on stdout:

  {"type": "pid", "pid": N}
  {"type": "state", "workspaces": [...], "clients": {"<ws>": [...]}}
  {"type": "snap", "ws": "<ws>", "path": "...", "t": <unix seconds>}

Hyprland does not render workspaces that are not on screen, so a thumbnail is
the last time a workspace was visible: it is captured shortly after the
workspace is shown, again when its windows change, and on a slow timer.

SIGUSR1 pauses capture (the preview panel is open and would be in the shot),
SIGUSR2 resumes it.
"""

import ctypes
import glob
import json
import os
import select
import signal
import socket
import subprocess
import sys
import time

SNAP_DIR = sys.argv[1]
REFRESH_S = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0
SCALE = sys.argv[3] if len(sys.argv) > 3 else "0.25"

SETTLE_WORKSPACE_S = 0.45  # let the workspace-switch animation finish
SETTLE_WINDOW_S = 0.9  # let a new window map and draw its first frame
STATE_DEBOUNCE_S = 0.15
TITLE_DEBOUNCE_S = 1.0

CAPTURE_EVENTS = {
    "workspace", "workspacev2", "focusedmon", "focusedmonv2",
    "openwindow", "closewindow", "movewindow", "movewindowv2",
    "fullscreen", "changefloatingmode", "activespecial", "activespecialv2",
}
STATE_EVENTS = CAPTURE_EVENTS | {
    "createworkspace", "createworkspacev2", "destroyworkspace",
    "destroyworkspacev2", "renameworkspace", "moveworkspace",
    "moveworkspacev2", "monitoradded", "monitorremoved", "activewindow",
    "activewindowv2",
}
TITLE_EVENTS = {"windowtitle", "windowtitlev2"}

paused = False
capture_at = None  # monotonic deadline for the next capture
state_at = None
last_capture = 0.0
snaps = {}  # ws id (str) -> path


def die_with_parent():
    try:
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        libc.prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
    except OSError:
        pass


def emit(obj):
    try:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        sys.exit(0)


def hypr(query):
    try:
        out = subprocess.run(
            ["hyprctl", "-j", query], capture_output=True, text=True, timeout=2
        ).stdout
        return json.loads(out)
    except (subprocess.SubprocessError, json.JSONDecodeError, OSError):
        return None


def socket_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if sig:
        path = os.path.join(runtime, "hypr", sig, ".socket2.sock")
        if os.path.exists(path):
            return path
    found = glob.glob(os.path.join(runtime, "hypr", "*", ".socket2.sock"))
    return max(found, key=os.path.getmtime) if found else None


def publish_state():
    workspaces = hypr("workspaces") or []
    monitors = hypr("monitors") or []
    clients = hypr("clients") or []
    visible = {str(m["activeWorkspace"]["id"]): m["name"] for m in monitors}
    focused_ws = next(
        (str(m["activeWorkspace"]["id"]) for m in monitors if m.get("focused")), None
    )
    out_ws = []
    for w in workspaces:
        if w["id"] < 0:  # special workspaces (scratchpads)
            continue
        wid = str(w["id"])
        out_ws.append({
            "id": wid,
            "num": w["id"],
            "name": w["name"],
            "monitor": w["monitor"],
            "windows": w["windows"],
            "visible": wid in visible,
            "focused": wid == focused_ws,
        })
    out_ws.sort(key=lambda w: w["num"])
    by_ws = {}
    for c in sorted(clients, key=lambda c: (c.get("focusHistoryID", 0))):
        wid = str(c["workspace"]["id"])
        if not c.get("mapped", True):
            continue
        by_ws.setdefault(wid, []).append({
            "class": c.get("class") or c.get("initialClass") or "",
            "title": c.get("title") or "",
        })
    emit({"type": "state", "workspaces": out_ws, "clients": by_ws})
    live = {w["id"] for w in out_ws}
    for wid in list(snaps):
        if wid not in live:
            drop_snap(wid)


def drop_snap(wid):
    path = snaps.pop(wid, None)
    if path:
        try:
            os.remove(path)
        except OSError:
            pass
    emit({"type": "snap", "ws": wid, "path": None, "t": None})


def capture():
    global last_capture
    last_capture = time.monotonic()
    for m in hypr("monitors") or []:
        if m.get("specialWorkspace", {}).get("id"):
            continue  # a scratchpad is covering the real workspace
        wid = m["activeWorkspace"]["id"]
        if wid < 0:
            continue
        wid = str(wid)
        # A fresh name each time: Noctalia only reloads an image when its path changes.
        path = os.path.join(SNAP_DIR, f"ws-{wid}-{int(time.time() * 1000)}.png")
        r = subprocess.run(
            ["grim", "-o", m["name"], "-s", SCALE, "-t", "png", "-l", "1", path],
            capture_output=True,
        )
        if r.returncode != 0:
            continue
        old = snaps.get(wid)
        snaps[wid] = path
        if old and old != path:
            try:
                os.remove(old)
            except OSError:
                pass
        emit({"type": "snap", "ws": wid, "path": path, "t": int(time.time())})


def load_existing():
    for path in glob.glob(os.path.join(SNAP_DIR, "ws-*-*.png")):
        wid = os.path.basename(path).split("-")[1]
        prev = snaps.get(wid)
        if prev is None or os.path.getmtime(path) > os.path.getmtime(prev):
            if prev:
                os.remove(prev)
            snaps[wid] = path
        else:
            os.remove(path)
    for wid, path in snaps.items():
        emit({"type": "snap", "ws": wid, "path": path, "t": int(os.path.getmtime(path))})


def schedule_capture(delay):
    global capture_at
    at = time.monotonic() + delay
    capture_at = at if capture_at is None else max(capture_at, at)


def schedule_state(delay):
    global state_at
    at = time.monotonic() + delay
    if state_at is None or at < state_at:
        state_at = at


def on_pause(*_):
    global paused
    paused = True


def on_resume(*_):
    global paused
    paused = False
    if capture_at is None:
        schedule_capture(0.3)


def main():
    global capture_at, state_at
    die_with_parent()
    os.makedirs(SNAP_DIR, exist_ok=True)
    signal.signal(signal.SIGUSR1, on_pause)
    signal.signal(signal.SIGUSR2, on_resume)
    emit({"type": "pid", "pid": os.getpid()})
    load_existing()
    publish_state()
    last_capture_bump()
    schedule_capture(0.5)

    path = socket_path()
    if not path:
        emit({"type": "error", "message": "Hyprland event socket not found"})
        return
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(path)
    buf = b""
    while True:
        now = time.monotonic()
        deadlines = [d for d in (capture_at, state_at) if d is not None]
        deadlines.append(last_capture + REFRESH_S)
        timeout = max(0.0, min(deadlines) - now)
        try:
            ready, _, _ = select.select([sock], [], [], timeout)
        except InterruptedError:
            continue
        if ready:
            chunk = sock.recv(65536)
            if not chunk:
                return  # Hyprland went away
            buf += chunk
            *lines, buf = buf.split(b"\n")
            for line in lines:
                event = line.split(b">>", 1)[0].decode(errors="replace")
                if event in STATE_EVENTS:
                    schedule_state(STATE_DEBOUNCE_S)
                elif event in TITLE_EVENTS:
                    schedule_state(TITLE_DEBOUNCE_S)
                if event in ("workspace", "workspacev2", "focusedmon", "focusedmonv2"):
                    schedule_capture(SETTLE_WORKSPACE_S)
                elif event in CAPTURE_EVENTS:
                    schedule_capture(SETTLE_WINDOW_S)
        now = time.monotonic()
        if state_at is not None and now >= state_at:
            state_at = None
            publish_state()
        if not paused:
            if capture_at is not None and now >= capture_at:
                capture_at = None
                capture()
            elif now >= last_capture + REFRESH_S:
                capture()
        elif now >= last_capture + REFRESH_S:
            # Keep the timer from spinning while paused; capture on resume.
            last_capture_bump()


def last_capture_bump():
    global last_capture
    last_capture = time.monotonic()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
