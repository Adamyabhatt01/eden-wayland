# Benchmarks

Performance baselines for the Wayland port. Only measured, repeatable
results belong here. Same machine, same game, same run length,
sequential backends.

## How to measure

```
tools/wayland/benchmark.sh <game-file> [seconds]
```

Runs the game unattended for the given duration on native Wayland, then
on XWayland, saving Eden's log for each backend under
`docs/wayland/evidence/benchmark-YYYYMMDD-HHMMSS/`.

What this measures today: Eden's own log (swapchain present mode plus the
in-app FPS printed to the log) and MangoHud per-frame CSV when the user
enables logging themselves. MangoHud writes CSVs only when
`logging=true` is set in `~/.config/MangoHud/MangoHud.conf` before the
run (`MANGOHUD=1` alone shows the overlay; F12 is MangoHud's screenshot
key, not a logging toggle). CSVs land in `~/.local/share/MangoHud/`. The
harness does not switch MangoHud logging on its own. Note the harness
sets `QT_QPA_PLATFORM` explicitly per run (`wayland`, then `xcb`), so the
fork's new `wayland;xcb` default does not affect the XWayland leg. A
scripted run measures mostly the load/boot and title segment; a
user-played session is preferred and should be recorded the same way by
re-running the script while playing.

Metrics to record: average FPS, 1% lows, frame-time p50/p95/p99, CPU/GPU
utilisation, present mode, swapchain recreation count.

## Results

| Date | Backend | Run length | Avg FPS | 1% low | p50 | p95 | Result |
|---|---|---|---|---|---|---|---|
| (not measured yet) | native Wayland | - | - | - | - | - | Pending first user-driven run against a game |

No "Wayland is faster" claim is made until numbers exist.
