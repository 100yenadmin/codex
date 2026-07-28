#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  refresh.sh <check|test|build> --repo PATH --patch-branch BRANCH [options]

Options:
  --upstream-remote NAME   Remote that tracks openai/codex (default: origin)
  --upstream-branch NAME   Upstream default branch (default: main)
  --no-fetch               Inspect existing refs without network access
  -h, --help               Show this help

The script is intentionally fail-closed. It never rebases, pushes, installs,
restarts ChatGPT, edits live Codex configuration, or replaces an app binary.
EOF
}

die() {
  printf 'refresh error: %s\n' "$*" >&2
  exit 2
}

mode="${1:-}"
case "$mode" in
  check|test|build)
    shift
    ;;
  -h|--help|"")
    usage
    exit 0
    ;;
  *)
    usage >&2
    die "unknown mode: $mode"
    ;;
esac

repo_path=""
patch_branch=""
upstream_remote="origin"
upstream_branch="main"
fetch_refs=1

while (($# > 0)); do
  case "$1" in
    --repo)
      (($# >= 2)) || die "--repo requires a path"
      repo_path="$2"
      shift 2
      ;;
    --patch-branch)
      (($# >= 2)) || die "--patch-branch requires a branch"
      patch_branch="$2"
      shift 2
      ;;
    --upstream-remote)
      (($# >= 2)) || die "--upstream-remote requires a remote name"
      upstream_remote="$2"
      shift 2
      ;;
    --upstream-branch)
      (($# >= 2)) || die "--upstream-branch requires a branch name"
      upstream_branch="$2"
      shift 2
      ;;
    --no-fetch)
      fetch_refs=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$repo_path" ]] || die "--repo is required"
[[ -n "$patch_branch" ]] || die "--patch-branch is required"

for required_command in git rg just shasum; do
  command -v "$required_command" >/dev/null 2>&1 \
    || die "required command is unavailable: $required_command"
done

if [[ "$mode" != "check" ]]; then
  command -v cargo >/dev/null 2>&1 \
    || die "Cargo is unavailable; install or activate the repository Rust toolchain"
fi

repo_root="$(git -C "$repo_path" rev-parse --show-toplevel 2>/dev/null)" \
  || die "not a Git checkout: $repo_path"

if [[ -n "$(git -C "$repo_root" status --porcelain)" ]]; then
  die "worktree is dirty; preserve or commit existing changes before refresh"
fi

git -C "$repo_root" remote get-url "$upstream_remote" >/dev/null 2>&1 \
  || die "missing upstream remote: $upstream_remote"

if ((fetch_refs)); then
  git -C "$repo_root" fetch "$upstream_remote" "$upstream_branch"
fi

upstream_ref="$upstream_remote/$upstream_branch"
git -C "$repo_root" rev-parse --verify --quiet "$upstream_ref^{commit}" >/dev/null \
  || die "missing upstream ref: $upstream_ref"
git -C "$repo_root" rev-parse --verify --quiet "$patch_branch^{commit}" >/dev/null \
  || die "missing patch branch: $patch_branch"

upstream_sha="$(git -C "$repo_root" rev-parse "$upstream_ref")"
patch_sha="$(git -C "$repo_root" rev-parse "$patch_branch")"
base_sha="$(git -C "$repo_root" merge-base "$patch_branch" "$upstream_ref")"

if [[ "$base_sha" != "$upstream_sha" ]]; then
  printf 'refresh required: patch branch is not based on current %s\n' "$upstream_ref" >&2
  printf 'upstream_sha=%s\npatch_sha=%s\nmerge_base=%s\n' \
    "$upstream_sha" "$patch_sha" "$base_sha" >&2
  printf 'Create a new candidate worktree, rebase there, resolve deliberately, and rerun this check.\n' >&2
  exit 3
fi

git -C "$repo_root" diff --check "$upstream_ref...$patch_branch"

rg -q 'gpt-5\.6-luna' \
  "$repo_root/codex-rs/core/src/tools/handlers/multi_agents_common.rs" \
  || die "Luna V2 compatibility fallback is missing"
rg -q 'agent_depth_routing' "$repo_root/codex-rs/core/src/config/mod.rs" \
  || die "depth-routing configuration is missing"
rg -q 'Agent depth limit reached' \
  "$repo_root/codex-rs/core/src/tools/handlers/multi_agents_v2/spawn.rs" \
  || die "V2 handler depth enforcement is missing"
rg -q 'multi_agent_v2_leaf_omits_spawn_but_keeps_communication_tools' \
  "$repo_root/codex-rs/core/src/tools/spec_plan_tests.rs" \
  || die "leaf tool-surface regression is missing"

printf 'refresh_check=pass\nupstream_ref=%s\nupstream_sha=%s\npatch_branch=%s\npatch_sha=%s\n' \
  "$upstream_ref" "$upstream_sha" "$patch_branch" "$patch_sha"

if [[ "$mode" == "check" ]]; then
  exit 0
fi

focused_tests=(
  multi_agent_v2_accepts_luna_from_a_legacy_v1_catalog_only
  multi_agent_v2_spawn_agent_rejects_depth_beyond_configured_max_depth
  multi_agent_v2_depth_routing_enforces_hierarchy_and_leaf
  multi_agent_v2_leaf_omits_spawn_but_keeps_communication_tools
  agents_depth_routing_deserializes_quoted_depths
  load_config_rejects_conflicting_depth_reasoning_constraints
)

for test_filter in "${focused_tests[@]}"; do
  just --justfile "$repo_root/justfile" test -p codex-core "$test_filter"
done

printf 'focused_tests=pass\n'

if [[ "$mode" == "test" ]]; then
  exit 0
fi

(
  cd "$repo_root/codex-rs"
  cargo build -p codex-cli --bin codex
)

binary_path="$repo_root/codex-rs/target/debug/codex"
[[ -x "$binary_path" ]] || die "build completed without expected binary: $binary_path"
binary_sha="$(shasum -a 256 "$binary_path" | awk '{print $1}')"
printf 'build=pass\nbinary_path=%s\nbinary_sha256=%s\n' "$binary_path" "$binary_sha"
