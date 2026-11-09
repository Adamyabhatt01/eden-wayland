# Upstream Synchronization

## 1. State

| Item | Value |
|---|---|
| Upstream | `https://git.eden-emu.dev/eden-emu/eden.git` (remote `upstream`) |
| Tracking branch | `upstream/master` (never modified locally) |
| Last synchronized upstream commit | `943f1fc76087adcfc893fb1ca3aea507df15d004` (2026-10-30) |
| Fork base commit | same as last synchronized commit |
| Integration branch | `linux-wayland` |
| Custom commits | 18 at the start of the 2026-11-09 docs pass; source patches A1/A2/B1/C1 (see `git log` and `PATCHES.md`) |
| Imported upstream performance work | none yet |
| Pending upstream changes | none recorded; run the audit script |
| Open conflicts | none |
| Known regressions | none known; C1 changed GPU selection (see `TESTING.md`) |
| Latest upstream release | `v0.2.1` (2026-06-01); `master` is 411 commits ahead |

The sync state file is `.git/eden-wayland-upstream-sync` and is intentionally
not committed. The authoritative record for reviewers is this document; update
it whenever the integration branch moves.

## 2. Remotes and branches

- `upstream` — official repository. Fetch only.
- `origin` — **not configured**. No personal fork destination was provided,
  and no URL is invented. Add it only when a real fork exists.
- `upstream/master` — read-only.
- `linux-wayland` — integration branch; all fork work lands here.
- `feature/native-wayland` — Qt QPA selection, WSI/diagnostics, policy.
- `feature/vulkan-presentation` — surface/swapchain/present reliability.
- `feature/linux-optimizations` — measured-only performance changes.
- `packaging/arch` — PKGBUILD and packaging.
- `stable` — tested release states.

Rules:

1. Never commit on `upstream/master` or rewrite it.
2. Never combine unrelated subsystems in one commit (Wayland, Vulkan core,
   emulation core, packaging, UI).
3. No remote push without explicit authorization.
4. Keep fork-specific files under `docs/wayland/`, `tools/wayland/`,
   `tools/upstream-sync/`, `packaging/` where possible to minimize conflicts.

## 3. Synchronization procedure

1. `git fetch upstream --tags --prune`
2. Run `tools/upstream-sync/audit-upstream.sh` (read-only; produces a
   Markdown report under `docs/wayland/reports/`).
3. Review the report:
   - new commits classified by subsystem;
   - performance/fix commits;
   - Vulkan/graphics changes;
   - files also modified by the fork;
   - predicted merge conflicts;
   - dependency/CI changes.
4. Merge the whole of `upstream/master` into `linux-wayland`:
   `git merge --no-ff upstream/master`
   Prefer complete merges over cherry-picks. Cherry-pick only when a change
   must land early or cannot be merged (document the reason).
5. Resolve conflicts without discarding upstream functionality or the
   Wayland work. Re-read both sides; do not accept "ours"/"theirs" wholesale.
6. Build and run the regression suite from `TESTING.md`:
   native Wayland, XWayland, Vulkan init, Intel GPU, NVIDIA GPU, swapchain
   recreate, fullscreen, controller input, game launch, save data.
7. Compare performance with the previous known-good build
   (`BENCHMARKS.md`).
8. Update this document, `PATCHES.md`, and the state file.
9. Tag/advance `stable` only after the matrix passes.

## 4. Commit classification used by the audit script

| Category | Paths (prefix match) |
|---|---|
| Emulation core | `src/core/`, `src/hid_core/`, `src/dynarmic/`, `src/network/` |
| GPU rasterisation / shaders | `src/shader_recompiler/`, `src/video_core/engines/`, `src/video_core/texture_cache/`, `src/video_core/buffer_cache/` |
| Vulkan / presentation | `src/video_core/renderer_vulkan/`, `src/video_core/vulkan_common/` |
| OpenGL | `src/video_core/renderer_opengl/` |
| Audio | `src/audio_core/` |
| Input | `src/input_common/` |
| Qt frontend | `src/yuzu/`, `src/qt_common/` |
| Android | `src/android/` |
| Filesystem | `src/common/fs/`, `src/core/file_sys/` |
| Build / dependencies | `CMakeLists.txt`, `CMakeModules/`, `externals/`, `cpmfile.json` |
| Tests / CI | `src/tests/`, `.ci/`, `.forgejo/`, `.github/` |
| Docs | `docs/`, `README.md`, `CONTRIBUTING.md` |
| Other | everything else |

Performance candidates are additionally flagged by commit subject patterns
(`perf`, `optimiz`, `speed`, `faster`, `latency`, `stutter`, `fps`,
`frame`, `alloc`, `cache`, `thread`). Subject matching is heuristic; classify
by code inspection before merging.

## 5. Conflict policy

- Files most likely to conflict: `src/yuzu/main.cpp`,
  `src/yuzu/main_window.cpp`, `src/yuzu/bootmanager.cpp`,
  `src/qt_common/qt_common.cpp`,
  `src/video_core/renderer_vulkan/vk_swapchain.*`,
  `src/video_core/renderer_vulkan/vk_present_manager.*`,
  `src/video_core/renderer_vulkan/renderer_vulkan.cpp`,
  `src/video_core/vulkan_common/vulkan_device.cpp`,
  `CMakeLists.txt`, `src/video_core/CMakeLists.txt`.
- Keep fork patches small and localized. Prefer adding a small helper or a
  guarded branch over restructuring upstream code.
- If upstream implements the same feature, drop the fork patch and verify
  upstream behaviour; record the removal in `PATCHES.md`.
- Every conflict resolution must be build-tested and runtime-tested before
  committing the merge.

## 6. Automation

`tools/upstream-sync/audit-upstream.sh`:

- fetches upstream (network read-only), never merges/cherry-picks;
- compares the last synced commit with `upstream/master`;
- groups commits by subsystem and flags performance candidates;
- detects files modified by both upstream and the fork;
- predicts merge conflicts with `git merge-tree` without touching the working
  tree;
- writes a timestamped Markdown report;
- prints the report path and exits 0.

Usage:

```sh
tools/upstream-sync/audit-upstream.sh              # audit since last sync state
tools/upstream-sync/audit-upstream.sh --mark-synced # record current upstream/master as synced
tools/upstream-sync/audit-upstream.sh --base <sha>  # audit since a specific commit
```

Approval is still required before merging. The script performs no mutations
other than the optional state-file update with `--mark-synced`.
