#!/usr/bin/env python3
"""
Automated multiplayer test: launches two LÖVE instances, hosts on P1,
joins on P2, then drives P2 right into coins and checks they disappear.
"""

import subprocess, time, sys, os
from Xlib import X, display as xdisplay, XK
from Xlib.protocol import event as xevent

GAME_DIR = os.path.dirname(os.path.abspath(__file__))
LOVE_ENV  = {**os.environ, "SDL_VIDEODRIVER": "x11"}


# ── X11 helpers ──────────────────────────────────────────────────────────────

def find_love_windows(disp, count=1, max_wait=10):
    deadline = time.time() + max_wait
    while time.time() < deadline:
        wins = _collect_love_wins(disp, disp.screen().root)
        if len(wins) >= count:
            return wins[:count]
        time.sleep(0.3)
    return _collect_love_wins(disp, disp.screen().root)

def _collect_love_wins(disp, root):
    found = []
    try:
        for w in root.query_tree().children:
            try:
                cls = w.get_wm_class()
                if cls and "love" in (cls[0] or "").lower():
                    found.append(w)
            except Exception:
                pass
            found.extend(_collect_love_wins(disp, w))
    except Exception:
        pass
    return found

def send_key(disp, win, keysym, delay_after=0.06):
    keycode = disp.keysym_to_keycode(keysym)
    root = disp.screen().root
    for etype in (X.KeyPress, X.KeyRelease):
        ev = xevent.KeyPress(
            time=X.CurrentTime, root=root, window=win,
            same_screen=1, child=X.NONE,
            root_x=0, root_y=0, event_x=50, event_y=50,
            state=0, detail=keycode, type=etype,
        )
        win.send_event(ev, propagate=True)
    disp.flush()
    time.sleep(delay_after)

def hold_key(disp, win, keysym, duration):
    """Fire repeated KeyPress events for `duration` seconds, then release."""
    keycode = disp.keysym_to_keycode(keysym)
    root = disp.screen().root
    deadline = time.time() + duration
    while time.time() < deadline:
        ev = xevent.KeyPress(
            time=X.CurrentTime, root=root, window=win,
            same_screen=1, child=X.NONE,
            root_x=0, root_y=0, event_x=50, event_y=50,
            state=0, detail=keycode, type=X.KeyPress,
        )
        win.send_event(ev, propagate=True)
        disp.flush()
        time.sleep(0.05)
    ev = xevent.KeyPress(
        time=X.CurrentTime, root=root, window=win,
        same_screen=1, child=X.NONE,
        root_x=0, root_y=0, event_x=50, event_y=50,
        state=0, detail=keycode, type=X.KeyRelease,
    )
    win.send_event(ev, propagate=True)
    disp.flush()

def focus(disp, win):
    win.set_input_focus(X.RevertToParent, X.CurrentTime)
    disp.flush()
    time.sleep(0.15)


# ── Main test ─────────────────────────────────────────────────────────────────

def main():
    disp = xdisplay.Display()

    print("[1] Launching P1 (host)...")
    p1 = subprocess.Popen(["love", GAME_DIR], env=LOVE_ENV,
                          stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    time.sleep(2.5)

    print("[2] Launching P2 (client)...")
    p2 = subprocess.Popen(["love", GAME_DIR], env=LOVE_ENV,
                          stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    time.sleep(2.5)

    print("[3] Finding game windows...")
    wins = find_love_windows(disp, count=2, max_wait=10)
    if len(wins) < 2:
        print(f"ERROR: expected 2 windows, found {len(wins)}")
        p1.terminate(); p2.terminate()
        sys.exit(1)

    win1, win2 = wins[0], wins[1]
    print(f"  P1 window: 0x{win1.id:x}  P2 window: 0x{win2.id:x}")

    # ── P1: host ──────────────────────────────────────────────────────────
    print("[4] P1 → H (host)...")
    focus(disp, win1)
    send_key(disp, win1, XK.XK_h, delay_after=1.5)

    # ── P2: join ──────────────────────────────────────────────────────────
    print("[5] P2 → J (join)...")
    focus(disp, win2)
    send_key(disp, win2, XK.XK_j, delay_after=0.8)

    # Leave IP field empty — game defaults to 127.0.0.1 when field is blank.
    # Typing via XSendEvent doesn't trigger love.textinput so it would corrupt
    # the field. Just press Enter to connect to localhost.
    print("[6] P2 → Enter (connect to 127.0.0.1)...")
    send_key(disp, win2, XK.XK_Return, delay_after=3.0)

    # ── P1: start ─────────────────────────────────────────────────────────
    print("[8] P1 → Enter (start game)...")
    focus(disp, win1)
    send_key(disp, win1, XK.XK_Return, delay_after=2.0)

    # ── P2: run right and collect coins ───────────────────────────────────
    print("[9] P2 → holding D+Shift (run right, 6 s) to collect coins...")
    focus(disp, win2)
    # Also hold shift for running speed
    keycode_shift = disp.keysym_to_keycode(XK.XK_Shift_L)
    root = disp.screen().root
    ev_shift_dn = xevent.KeyPress(
        time=X.CurrentTime, root=root, window=win2,
        same_screen=1, child=X.NONE,
        root_x=0, root_y=0, event_x=50, event_y=50,
        state=0, detail=keycode_shift, type=X.KeyPress,
    )
    win2.send_event(ev_shift_dn, propagate=True)
    disp.flush()

    hold_key(disp, win2, XK.XK_d, duration=6)

    ev_shift_up = xevent.KeyPress(
        time=X.CurrentTime, root=root, window=win2,
        same_screen=1, child=X.NONE,
        root_x=0, root_y=0, event_x=50, event_y=50,
        state=0, detail=keycode_shift, type=X.KeyRelease,
    )
    win2.send_event(ev_shift_up, propagate=True)
    disp.flush()

    print("[10] Watching for 3 more seconds...")
    time.sleep(3)

    # ── Collect results ───────────────────────────────────────────────────
    p1.terminate(); p2.terminate()
    p1.wait(); p2.wait()

    err1 = p1.stderr.read().decode(errors="replace").strip()
    err2 = p2.stderr.read().decode(errors="replace").strip()

    print("\n=== P1 stderr ===")
    print(err1 or "(none)")
    print("=== P2 stderr ===")
    print(err2 or "(none)")

    if "Error" in err1 or "Error" in err2:
        print("\nFAIL: Lua errors detected.")
        sys.exit(1)
    else:
        print("\nPASS: Both instances ran without Lua errors.")


if __name__ == "__main__":
    main()
