# Benchmarks

**No benchmark has been run yet.** The environment currently has no legal
bootable test content and no keys; the commercial NSP files present in the
home directory are out of scope and will not be used. Tables below are
templates, not results.

## 1. Variants

| ID | Build | Display path | GPU |
|---|---|---|---|
| U-X | upstream `943f1fc7` | XWayland (`QT_QPA_PLATFORM=xcb`) | Intel / NVIDIA |
| U-W | upstream `943f1fc7` | native Wayland | Intel / NVIDIA |
| F-X | fork integration build | XWayland | Intel / NVIDIA |
| F-W | fork integration build | native Wayland | Intel / NVIDIA |

Native Wayland is **not assumed to be faster**. The comparison determines
whether fork changes and the display path affect performance.

## 2. Controlled variables

- Same binary build type (`RelWithDebInfo` or `Release`, never mixed).
- Same game, version, save state, resolution scale, graphics settings, shader
  cache state (warm/cold documented), vsync mode, frame pacing mode,
  `async_presentation`, and speed limit.
- Same driver versions (Mesa 26.2.5, NVIDIA 615.78.08), kernel, compositor
  config, and monitor mode (1920x1080@120.21, scale 1).
- Close background GPU/CPU load; disable MangoHud overlay in measurement runs
  unless using its logging-only mode.
- Warm up ≥ 60 s before measurement; measure ≥ 120 s per run; 5 runs per cell.
- Record ambient temperature and check for thermal throttling
  (`nvidia-smi -q -d TEMPERATURE`, `sensors` if available).

## 3. Metrics

| Metric | Method |
|---|---|
| Average FPS | MangoHud CSV (`fps`), wall-clock frame count |
| 1% low / 0.1% low | MangoHud CSV percentiles or offline computation |
| Frame time p50/p95/p99 | MangoHud CSV (`frametime`), offline |
| CPU utilisation | MangoHud (`cpu_load`), `pidstat` |
| GPU utilisation / clocks | MangoHud (`gpu_load`, `gpu_core_clock`), `nvidia-smi dmon` |
| VRAM / RSS | MangoHud (`gpu_vram_used`), `/proc/<pid>/status` sampling |
| Presentation mode | Eden diagnostics log; `vulkaninfo` |
| Swapchain recreations | Eden diagnostics (add counter in Phase 3/4) |
| Shader compilation stutter | Frame-time spikes + `shader` logs; cold vs warm cache |
| Presentation latency | Not directly measurable without `presentation-time` instrumentation; report frame-time distribution and note the limitation |

## 4. MangoHud logging

```sh
MANGOHUD=1 \
MANGOHUD_CONFIG="output_folder=$PWD/bench,fps_limit=0,no_display=1,\
log_duration=120,autostart_log=1" \
./eden
```

Parse CSV offline; do not use the on-screen overlay as the sole source. For
NVIDIA, MangoHud's `gpu_load` comes from NVML; for Intel, from sysfs.

## 5. Scenarios

1. **Idle menu** (GUI only): startup time, CPU/GPU idle usage, no renderer
   until a game starts.
2. **Light 2D/60 Hz title**: frame-time consistency.
3. **Heavy 3D title**: GPU-bound; VRAM pressure on 4 GiB.
4. **Shader stress**: first-run vs warm shader cache.
5. **Resize/fullscreen transitions**: swapchain recreation overhead, frame
   drops.
6. **Minimise/restore**: recovery time, no hang.
7. **120 Hz / VRR**: pacing behaviour with FIFO, MAILBOX, IMMEDIATE
   (if exposed by the Wayland WSI), and `async_presentation` on/off.
8. **PRIME offload**: Intel iGPU vs NVIDIA dGPU; power/thermal behaviour if
   readable.

## 6. Results

### 6.1 Environment

To be recorded with the first run: build commit, compiler, Qt, loader, Mesa,
NVIDIA driver, game/version, save point, shader cache state.

### 6.2 Table template

| Variant | GPU | Avg FPS | 1% low | p95 frame (ms) | CPU % | GPU % | VRAM (MiB) | Notes |
|---|---|---|---|---|---|---|---|---|
| U-X | — | — | — | — | — | — | — | not run |
| U-W | — | — | — | — | — | — | — | not run |
| F-X | — | — | — | — | — | — | — | not run |
| F-W | — | — | — | — | — | — | — | not run |

### 6.3 Present mode comparison (fork build)

| Mode | Avg FPS | p99 frame (ms) | Tearing/artefacts | Latency proxy | Decision |
|---|---|---|---|---|---|
| FIFO | — | — | — | — | pending |
| FIFO_RELAXED | — | — | — | — | pending |
| MAILBOX (if exposed) | — | — | — | — | pending |
| IMMEDIATE (if exposed) | — | — | — | — | pending |
| `async_presentation=on` | — | — | — | — | pending |

## 7. Decision rules

- Retain a performance change only if the median improvement exceeds run-to-run
  noise and no correctness/validation regression appears.
- Prefer frame-time consistency and absence of stutter over a small average
  FPS gain.
- Any default change (present mode, async presentation) requires a documented
  comparison and a rationale in `PATCHES.md`.
- Report negative results too. If native Wayland is slower in a scenario, say
  so and investigate before changing defaults.
