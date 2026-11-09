<img src="docs/assets/icon.png" alt="dinky" width="128">

# dinky

> oh wow. you moved a rectangle.

A tiling window manager for macOS that leaves System Integrity Protection on.

```sh
brew install --cask mikker/tap/dinky
```

[Documentation](https://dinky.rodeo)

## Quick start

Open dinky and grant Accessibility when asked. Windows tile as they open.

- `dinky workspace 3`: Switch to workspace 3.
- `dinky layout accordion`: Stack the focused container.
- `dinky doctor`: Check the config, the macOS settings dinky needs, and that no other tiler is running.

Learn more:

- [Concepts](https://dinky.rodeo/concepts/) and [Layouts](https://dinky.rodeo/layouts/)
- [Configuration](https://dinky.rodeo/configuration/)
- [Commands](https://dinky.rodeo/commands/)

Window rules can match or exclude Accessibility identifiers to distinguish auxiliary
windows from documents with the same title. See [window rules](https://dinky.rodeo/configuration/#rules).

## Updating this fork

This fork keeps the opt-in `mouse-follows-focus` feature alongside upstream Dinky.
The focused-window type guard is included upstream too. Set `mouse-follows-focus = true`
in `~/.config/dinky/dinky.toml` to enable pointer movement between displays.

From your personal branch (`feat/personal`), run:

```sh
just update          # merge the latest upstream/main and run tests locally
just update --push   # also push the tested result to your fork
```

Without `just`, use `scripts/update-fork.sh [--push]`. Commit or stash tracked
changes first. The script fetches upstream and your fork, creates a `fix/update-backup-*`
branch, and merges without rewriting your commits. Untracked files are left alone;
Git refuses a merge that would overwrite one. Conflicts stop the update for manual
resolution: resolve, `git add`, `git commit`, then rerun; or `git merge --abort`.
Failed tests stop the push and leave the merged code available to fix. To inspect
the previous version, `git switch` to the backup branch printed by the script.

This updates source code and optionally the GitHub fork. To build and install the
app afterward, use the existing `IDENTITY="Apple Development: Your Name (TEAMID)" just install`
workflow described in the [build instructions](docs/index.md#from-source).

MIT licensed.
