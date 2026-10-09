# 🔁 Reloader

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) bar widget that hot-reloads DMS plugins. Edit your QML, click once, see the change — no shell restart.

Built for plugin authors: the dev loop goes from *"restart DMS, lose your session state, re-open everything"* to *"click the pill"*.

## Features

- Lists every installed plugin with its load state (loaded / error)
- Click a row to reload that plugin
- **Reload all** in one click, with a single summary toast
- Skips itself — Reloader never pulls the rug out from under the popout
- Per-plugin exclusions, toggled right from the row or typed in settings
- Copy a plugin id to the clipboard for `dms ipc` calls and `dev.sh` scripts
- Works in horizontal and vertical bars; the pill spins while a bulk reload runs

## Requirements

- DankMaterialShell **≥ 1.6.0** with plugin support
- `dms` CLI available in `$PATH` (the widget shells out to `dms ipc call plugins …`)

## Installation

### From source

```bash
git clone https://github.com/Gamen0ut/dms-reloader.git
cd dms-reloader
./dev.sh link      # symlinks this folder into ~/.config/DankMaterialShell/plugins/Reloader
```

Then in DMS: **Settings → Plugins → Scan for plugins**, enable **Reloader**, and add it to a bar section.

### From a release

Download `Reloader-vX.Y.Z.zip` from [Releases](https://github.com/Gamen0ut/dms-reloader/releases) and extract it into `~/.config/DankMaterialShell/plugins/`.

## Usage

Click the pill to open the popout:

| Action | Result |
|---|---|
| Click a plugin row | Reloads that plugin, toast on success or failure |
| **Reload all** | Reloads every plugin except Reloader and your exclusions |
| Sync icon (top right) | Re-reads the plugin list |
| 🗐 on a row (hover) | Copies the plugin id to the clipboard |
| 🚫 on a row (hover) | Adds/removes the plugin from the **Reload all** exclusions |

Excluded plugins keep a 🚫 marker and a `skipped` label, and can still be reloaded individually by clicking the row. The copy action always toasts (it is the only feedback that it worked), even with "Show toasts" off.

## Settings

| Setting                   | Key           | Default | Description                                            |
|---------------------------|---------------|---------|--------------------------------------------------------|
| Show toasts               | `showToasts`  | `true`  | Notify after each reload                               |
| Skip in "Reload all"      | `excluded`    | `""`    | Comma-separated plugin ids, also editable from the rows |

## Development

```bash
./dev.sh link      # symlink the plugin into the DMS plugins folder
./dev.sh reload    # hot-reload Reloader itself after editing its QML
./dev.sh status    # check whether the plugin is loaded
```

Reloader can reload every plugin but itself, so `./dev.sh reload` (or `dms ipc call plugins reload reloader`) is how you iterate on Reloader.

### Project layout

```
dms-reloader/
├── plugin.json           # manifest (id, version, entry points, permissions)
├── Reloader.qml          # widget: bar pills, plugin list, reload logic
├── ReloaderSettings.qml  # settings page
├── dev.sh                # dev helper (link / reload / status / release)
├── CHANGELOG.md
└── ROADMAP.md
```

All logic lives in `Reloader.qml` on purpose: `plugins reload` fails every other time for plugins that import a sibling `.js` or `.qml` file, which would be a poor look on a reloader. See [ROADMAP.md](ROADMAP.md#notes--learnings).

## Versioning & releases

Reloader follows [Semantic Versioning](https://semver.org/). The single source of truth for the version is `plugin.json`.

To cut a release:

1. Add your changes under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
2. Run `./dev.sh release 0.2.0`: it bumps `plugin.json`, dates the changelog entry, updates the compare links, commits and creates the `v0.2.0` tag.
3. `git push --follow-tags`. GitHub Actions checks the tag matches `plugin.json`, zips the plugin and publishes a release with the changelog notes.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `chore:` …).

## License

[MIT](LICENSE) © Gamen0ut
