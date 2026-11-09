#!/usr/bin/env bash
# Merge upstream into the current branch without rewriting personal commits.
set -euo pipefail

# Parse the full workflow before a merge can replace this script on disk.
main() {
  cd "$(dirname "$0")/.."

  push=false
  install=true
  for option in "$@"; do
    case "$option" in
      --push) push=true ;;
      --source-only) install=false ;;
      -h|--help)
        echo 'Usage: scripts/update-fork.sh [--push] [--source-only]'
        echo 'Back up, merge upstream/main, test, then rebuild, install and launch /Applications/Dinky Dev.app.'
        echo '--push also pushes to origin; --source-only skips rebuilding and installing the app.'
        echo 'Commit or stash tracked changes first. Untracked files are left alone.'
        exit 0 ;;
      *) echo "Unknown option: $option" >&2; exit 2 ;;
    esac
  done

  die() { echo "$*" >&2; exit 1; }
  branch="$(git symbolic-ref --quiet --short HEAD)" || die 'Check out a branch first.'
  for state in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer; do
    [[ ! -e "$(git rev-parse --git-path "$state")" ]] || die 'Finish or abort the current Git operation first.'
  done
  git diff --quiet && git diff --cached --quiet || die 'Commit or stash tracked changes first; nothing was changed.'

  # Configure upstream once in a fresh clone. Never alter an existing remote URL.
  git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/mikker/Dinky.git
  git remote get-url origin >/dev/null 2>&1 || die 'Configure origin to point at your fork first.'
  git fetch upstream
  git fetch origin
  git rev-parse --verify refs/remotes/upstream/main >/dev/null

  backup="fix/update-backup-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  git branch "$backup"
  echo "Backup: $backup"

  merge_ref() {
    if ! git -c merge.autoStash=false merge --no-edit "$1"; then
      echo "Merge stopped. Your original commits are saved at $backup." >&2
      if git rev-parse --verify -q MERGE_HEAD >/dev/null; then
        echo 'Resolve the conflicts, git add the resolved files, git commit, then rerun this script.' >&2
        echo 'Or run git merge --abort to cancel this merge.' >&2
      fi
      exit 1
    fi
  }

  # Include another machine's commits before merging upstream; never force push.
  if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    merge_ref "refs/remotes/origin/$branch"
  fi
  merge_ref refs/remotes/upstream/main
  updated="$(git rev-parse HEAD)"

  echo 'Testing the updated fork...'
  test_command=(swift test --jobs 4)
  # Some Command Line Tools releases ship Testing macros but omit their plugin registration.
  # Load that bundled plugin explicitly when present; full Xcode needs no workaround.
  developer_dir="$(xcode-select -p)"
  testing_plugin="$developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
  if [[ "$developer_dir" == */CommandLineTools && -f "$testing_plugin" ]]; then
    test_command+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
  fi
  if ! "${test_command[@]}" || ! python3 -m unittest discover -s scripts/tests -v; then
    echo "Tests failed; nothing was pushed. The pre-update backup is $backup." >&2
    echo 'Fix the failure and rerun this script. Use git switch <backup> to inspect the previous version.' >&2
    exit 1
  fi
  [[ "$(git symbolic-ref --quiet --short HEAD)" == "$branch" && "$(git rev-parse HEAD)" == "$updated" ]] || die 'Branch changed during testing; nothing was pushed.'
  git diff --quiet && git diff --cached --quiet || die 'Tracked files changed during testing; nothing was pushed.'

  if $install; then
    scripts/install-dev.sh
  fi
  if $push; then
    git push --set-upstream origin "HEAD:refs/heads/$branch"
  fi
  echo "Updated $branch successfully. Backup: $backup"
  if ! $push; then
    echo 'Source commits kept local. Add --push next time to also push to your fork.'
  fi
}

main "$@"
