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
just update                 # update, test, rebuild, install and relaunch Dinky Dev
just update --push          # also push the tested result to your fork
just update --source-only   # update and test source without replacing the app
```

Without `just`, use `scripts/update-fork.sh [--push] [--source-only]`. Commit or stash tracked
changes first. The script fetches upstream and your fork, creates a `fix/update-backup-*`
branch, and merges without rewriting your commits. Untracked files are left alone;
Git refuses a merge that would overwrite one. Conflicts stop the update for manual
resolution: resolve, `git add`, `git commit`, then rerun; or `git merge --abort`.
Failed tests stop the push and leave the merged code available to fix. To inspect
the previous version, `git switch` to the backup branch printed by the script.

After tests pass, the updater builds the native debug app, quits Dinky cleanly,
installs `/Applications/Dinky Dev.app`, and launches it. Compilation and signing
finish before Dinky quits. The previous installed app is saved under
`build/dev-app-backups/`; installation or launch failures restore it. The dev app
keeps `com.brnbw.dinky.dev` and disables upstream auto-updates to preserve your feature.
It also links `dinky` in `/opt/homebrew/bin` (Apple silicon) or `/usr/local/bin`
(Intel) to the installed app so SketchyBar and other shell integrations use the
matching CLI. Existing CLI symlinks are updated; regular files are left alone.
It uses ad-hoc signing by default, which may require granting Accessibility again;
set `IDENTITY="Apple Development: Your Name (TEAMID)"` to use a stable certificate.
No full Xcode install is needed. To rebuild and install without updating source,
run `scripts/install-dev.sh` (or `just install-dev`).

MIT licensed.
