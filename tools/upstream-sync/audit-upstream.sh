#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Eden-Wayland upstream audit.
#
# Fetches upstream, classifies new commits, detects files touched by both
# upstream and the fork, predicts merge conflicts (without touching the
# working tree), and writes a Markdown report. It NEVER merges, rebases or
# cherry-picks.
#
# Usage:
#   tools/upstream-sync/audit-upstream.sh
#   tools/upstream-sync/audit-upstream.sh --base <commit>
#   tools/upstream-sync/audit-upstream.sh --mark-synced
#
# Environment:
#   UPSTREAM_REMOTE     (default: upstream)
#   INTEGRATION_BRANCH  (default: linux-wayland)
#   REPORT_DIR          (default: <repo>/docs/wayland/reports)

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

UPSTREAM_REMOTE=${UPSTREAM_REMOTE:-upstream}
INTEGRATION_BRANCH=${INTEGRATION_BRANCH:-linux-wayland}
STATE_FILE=${STATE_FILE:-"$REPO_ROOT/.git/eden-wayland-upstream-sync"}
REPORT_DIR=${REPORT_DIR:-"$REPO_ROOT/docs/wayland/reports"}

BASE_OVERRIDE=""
MARK_SYNCED=0

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while (($#)); do
    case "$1" in
        --base)
            [[ $# -ge 2 ]] || { echo "--base requires a commit" >&2; exit 2; }
            BASE_OVERRIDE=$2
            shift 2
            ;;
        --mark-synced)
            MARK_SYNCED=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
    echo "Remote '$UPSTREAM_REMOTE' does not exist." >&2
    exit 2
fi

echo "Fetching $UPSTREAM_REMOTE ..." >&2
git fetch "$UPSTREAM_REMOTE" --tags --prune

UPSTREAM_REF="$UPSTREAM_REMOTE/master"
UPSTREAM_SHA=$(git rev-parse "$UPSTREAM_REF")

if ((MARK_SYNCED)); then
    printf '%s\n' "$UPSTREAM_SHA" > "$STATE_FILE"
    echo "Recorded $UPSTREAM_SHA as the last synced upstream commit." >&2
    echo "Update docs/wayland/UPSTREAM_SYNC.md as well." >&2
    exit 0
fi

if [[ -n "$BASE_OVERRIDE" ]]; then
    BASE=$(git rev-parse --verify "$BASE_OVERRIDE^{commit}")
elif [[ -f "$STATE_FILE" ]]; then
    BASE=$(<"$STATE_FILE")
else
    BASE=$(git merge-base "$INTEGRATION_BRANCH" "$UPSTREAM_REF")
fi

if ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
    echo "Base commit '$BASE' is not present in this repository." >&2
    exit 2
fi

FORK_BASE=$(git merge-base "$INTEGRATION_BRANCH" "$UPSTREAM_REF")
COMMIT_COUNT=$(git rev-list --count --no-merges "$BASE..$UPSTREAM_SHA")

mkdir -p "$REPORT_DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
REPORT="$REPORT_DIR/upstream-audit-$STAMP.md"
SHORT_BASE=$(git rev-parse --short "$BASE")
SHORT_UP=$(git rev-parse --short "$UPSTREAM_SHA")

classify_path() {
    local p=$1
    case "$p" in
        src/core/*|src/hid_core/*|src/dynarmic/*|src/network/*) echo "Emulation core" ;;
        src/shader_recompiler/*|src/video_core/engines/*|src/video_core/texture_cache/*|src/video_core/buffer_cache/*|src/video_core/host_shaders/*) echo "GPU rasterisation / shaders" ;;
        src/video_core/renderer_vulkan/*|src/video_core/vulkan_common/*) echo "Vulkan / presentation" ;;
        src/video_core/renderer_opengl/*) echo "OpenGL" ;;
        src/audio_core/*) echo "Audio" ;;
        src/input_common/*) echo "Input" ;;
        src/yuzu/*|src/qt_common/*) echo "Qt frontend" ;;
        src/android/*) echo "Android" ;;
        src/common/fs/*|src/core/file_sys/*) echo "Filesystem" ;;
        CMakeLists.txt|CMakeModules/*|externals/*|cpmfile.json|.ci/*|.forgejo/*|.github/*) echo "Build / CI / dependencies" ;;
        src/tests/*) echo "Tests" ;;
        docs/*|README.md|CONTRIBUTING.md|LICENSE*) echo "Docs" ;;
        *) echo "Other" ;;
    esac
}

# Category -> commit lines (sha<TAB>short<TAB>date<TAB>subject<TAB>nfiles)
declare -A CATEGORY_COMMITS
declare -a PERF_COMMITS=()
declare -a VULKAN_COMMITS=()
declare -a FEATURE_COMMITS=()

UPSTREAM_FILES=$(mktemp)
FORK_FILES=$(mktemp)
COMMIT_LIST=$(mktemp)
trap 'rm -f "$UPSTREAM_FILES" "$FORK_FILES" "$COMMIT_LIST"' EXIT

git diff --name-only "$BASE" "$UPSTREAM_SHA" | sort -u > "$UPSTREAM_FILES"
git diff --name-only "$FORK_BASE" "$INTEGRATION_BRANCH" | sort -u > "$FORK_FILES"

git log --no-merges --reverse \
    --format='%H%x09%h%x09%ad%x09%s' --date=short \
    "$BASE..$UPSTREAM_SHA" > "$COMMIT_LIST"

while IFS=$'\t' read -r sha short date subject; do
    [[ -n "$sha" ]] || continue
    mapfile -t files < <(git show --pretty=format: --name-only "$sha" | sed '/^$/d' | sort -u)
    declare -A counts=()
    for f in "${files[@]}"; do
        c=$(classify_path "$f")
        counts["$c"]=$(( ${counts["$c"]:-0} + 1 ))
    done
    best="Other"; best_n=0
    for c in "${!counts[@]}"; do
        if (( counts["$c"] > best_n )); then best=$c; best_n=${counts["$c"]}; fi
    done
    line=$(printf '%s\t%s\t%s\t%s\t%d' "$short" "$date" "$subject" "$best" "${#files[@]}")
    CATEGORY_COMMITS["$best"]+="$line"$'\n'

    if grep -Eiq 'perf|optimiz|optimis|speed|faster|latency|stutter|fps|frame.?time|allocat|cache|thread' <<<"$subject"; then
        PERF_COMMITS+=("$short $date $subject")
    fi
    if [[ "$best" == "Vulkan / presentation" ]]; then
        VULKAN_COMMITS+=("$short $date $subject")
    fi
    if grep -Eiq '^feat' <<<"$subject"; then
        FEATURE_COMMITS+=("$short $date $subject")
    fi
done < "$COMMIT_LIST"

OVERLAP=$(comm -12 "$UPSTREAM_FILES" "$FORK_FILES" || true)

set +e
MERGE_TREE_OUT=$(git merge-tree --write-tree --name-only "$INTEGRATION_BRANCH" "$UPSTREAM_REF" 2>/dev/null)
MERGE_TREE_RC=$?
set -e
CONFLICTED=""
if ((MERGE_TREE_RC != 0)); then
    CONFLICTED=$(printf '%s\n' "$MERGE_TREE_OUT" | tail -n +2 | sed '/^$/d')
fi

{
    echo "# Upstream Audit — $STAMP"
    echo
    echo "- Integration branch: \`$INTEGRATION_BRANCH\`"
    echo "- Upstream ref: \`$UPSTREAM_REF\` @ \`$UPSTREAM_SHA\`"
    echo "- Audit base: \`$BASE\`"
    echo "- Fork merge-base: \`$FORK_BASE\`"
    echo "- New upstream commits (non-merge): **$COMMIT_COUNT**"
    echo "- Predicted merge conflicts: **$( [[ -n "$CONFLICTED" ]] && echo yes || echo no )**"
    echo
    echo "This report is advisory. It does not merge, rebase or cherry-pick."
    echo

    echo "## Commits by subsystem"
    echo
    echo "| Subsystem | Commits |"
    echo "|---|---:|"
    for c in "Emulation core" "GPU rasterisation / shaders" "Vulkan / presentation" "OpenGL" "Audio" "Input" "Qt frontend" "Android" "Filesystem" "Build / CI / dependencies" "Tests" "Docs" "Other"; do
        n=$(grep -c . <<<"${CATEGORY_COMMITS[$c]:-}" || true)
        echo "| $c | $n |"
    done
    echo

    echo "## Performance candidates (subject heuristic)"
    echo
    if ((${#PERF_COMMITS[@]})); then
        printf -- '- `%s`\n' "${PERF_COMMITS[@]}"
    else
        echo "_None matched._"
    fi
    echo

    echo "## Vulkan / presentation commits"
    echo
    if ((${#VULKAN_COMMITS[@]})); then
        printf -- '- `%s`\n' "${VULKAN_COMMITS[@]}"
    else
        echo "_None._"
    fi
    echo

    echo "## Feature commits"
    echo
    if ((${#FEATURE_COMMITS[@]})); then
        printf -- '- `%s`\n' "${FEATURE_COMMITS[@]}"
    else
        echo "_None._"
    fi
    echo

    echo "## Conflict prediction"
    echo
    if [[ -n "$CONFLICTED" ]]; then
        echo "Merging \`$UPSTREAM_REF\` into \`$INTEGRATION_BRANCH\` is predicted to conflict in:"
        echo
        sed 's/^/- `&`/' <<<"$CONFLICTED"
    else
        echo "No textual conflicts predicted by \`git merge-tree\`."
    fi
    echo

    echo "## Files changed by both upstream and the fork"
    echo
    if [[ -n "$OVERLAP" ]]; then
        sed 's/^/- `&`/' <<<"$OVERLAP"
        echo
        echo "These paths need the most careful review; conflict prediction is textual only."
    else
        echo "_No overlapping files._"
    fi
    echo

    echo "## Dependency and build changes"
    echo
    DEP_FILES=$(grep -E '(^|/)(CMakeLists\.txt|CMakeModules/|cpmfile\.json|externals/)' "$UPSTREAM_FILES" || true)
    if [[ -n "$DEP_FILES" ]]; then
        sed 's/^/- `&`/' <<<"$DEP_FILES"
    else
        echo "_None._"
    fi
    echo

    echo "## Detailed commit list"
    echo
    for c in "Emulation core" "GPU rasterisation / shaders" "Vulkan / presentation" "OpenGL" "Audio" "Input" "Qt frontend" "Android" "Filesystem" "Build / CI / dependencies" "Tests" "Docs" "Other"; do
        [[ -n "${CATEGORY_COMMITS[$c]:-}" ]] || continue
        echo "### $c"
        echo
        echo "| Commit | Date | Subject | Files |"
        echo "|---|---|---|---:|"
        while IFS=$'\t' read -r short date subject _best nfiles; do
            [[ -n "$short" ]] || continue
            subj=${subject//|/\\|}
            echo "| \`$short\` | $date | $subj | $nfiles |"
        done <<<"${CATEGORY_COMMITS[$c]}"
        echo
    done

    echo "## Next steps"
    echo
    echo "1. Review performance and Vulkan commits manually; subject heuristics are not authoritative."
    echo "2. Merge \`$UPSTREAM_REF\` into \`$INTEGRATION_BRANCH\` if appropriate: \`git merge --no-ff $UPSTREAM_REF\`."
    echo "3. Resolve conflicts preserving both upstream behaviour and fork Wayland patches."
    echo "4. Rebuild and run the regression matrix in \`docs/wayland/TESTING.md\`."
    echo "5. Update \`UPSTREAM_SYNC.md\` and \`PATCHES.md\`; then run this script with \`--mark-synced\`."
} > "$REPORT"

echo "Report: $REPORT"
echo "New upstream commits: $COMMIT_COUNT"
if [[ -n "$CONFLICTED" ]]; then
    echo "Predicted conflicts: yes"
    printf '%s\n' "$CONFLICTED" | sed 's/^/  /'
else
    echo "Predicted conflicts: no"
fi
echo "No merge or cherry-pick was performed."
