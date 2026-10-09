# 🔁 Reloader

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) bar widget that hot-reloads DMS plugins. Edit your QML, click once, see the change — no shell restart.

Built for plugin authors: the dev loop goes from *"restart DMS, lose your session state, re-open everything"* to *"click the pill"*.

## Features

- Lists every installed plugin with its load state (loaded / error)
- Click a row to reload that plugin
- **Reloads multi-file plugins properly** — imported `.js`, sibling `.qml` types, files you just created and the settings page all come back fresh, with no shell reload (see [How the reload works](#how-the-reload-works))
- **Reload all** in one click, with a single summary toast
- **Reload shell** button for the one case a plugin reload cannot cover: changes to DMS itself
- **Tick several plugins** and reload just those — handy when two plugins talk to each other
- **Right-click a row** for the plugin's details: version, author, description, permissions, folder
- Skips itself — Reloader never pulls the rug out from under the popout
- Per-plugin exclusions, toggled right from the row or typed in settings
- Copy a plugin id (or its folder path) to the clipboard for `dms ipc` calls and `dev.sh` scripts
- Hover labels on every button, so nothing is a mystery icon
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
| Click a plugin row | Reloads that plugin, toast on success or the real QML error on failure |
| **Right-click** a plugin row | Opens its details; the back arrow returns to the list |
| Checkbox on a row | Ticks the plugin for **Reload N selected** |
| **Reload all** | Reloads every plugin except Reloader and your exclusions |
| **Reload shell** | Rebuilds DMS and every plugin via `Quickshell.reload()` — for when you changed DMS, not a plugin |
| **Reload N selected** | Appears once something is ticked; reloads exactly those |
| Sync icon | Re-reads the plugin list |
| 🗐 on a row (hover) | Copies the plugin id to the clipboard |
| 🚫 on a row (hover) | Adds/removes the plugin from the **Reload all** exclusions |

Every button has a hover label, so the icons do not have to be guessed.

**Selections beat exclusions.** Ticking a plugin is an explicit choice, so **Reload N selected** reloads it even if it is in the exclusion list. Excluded plugins keep a 🚫 marker and a `skipped` label, and can always be reloaded individually by clicking the row.

**Details** come from the manifest DMS already parsed, so they cost nothing to show: id, version, author, type, live state, source (user or system), `requires_dms`, capabilities, permissions and the plugin folder — plus buttons to reload it, copy its id, or copy its path.

The copy actions always toast (it is the only feedback that they worked), even with "Show toasts" off.

## How the reload works

`dms ipc call plugins reload <id>` cannot reload a plugin that is more than one file, and this is worth knowing because it is silent. DMS busts the cache by appending `?t=<now>` to the entry file the manifest names — and a relative import resolves against the base URL with the query **dropped**. Inside `Duck.qml?t=1`, `Qt.resolvedUrl("Stats.js")` is a plain `file://…/Stats.js`, which Qt's type loader already has compiled. So `import "Stats.js" as Stats`, a sibling `ConfirmButton.qml` used as a type, and the settings page all come back **stale** while the reload reports `PLUGIN_RELOAD_SUCCESS`. An exception thrown by one of those stale imports during the plugin's `Component.onCompleted` is swallowed too, so nothing lands in the journal either.

Reloader sidesteps all of it by loading the plugin from a directory the engine has never seen. Every URL under a fresh path is new, so nothing there can be cached. The directory is a farm of symlinks into the real plugin folder:

```
~/.cache/DankMaterialShell/reloader/duck.1791510286867/
├── Duck.qml          -> ~/Projects/Duck/Duck.qml
├── DuckStats.js      -> ~/Projects/Duck/DuckStats.js
└── ConfirmButton.qml -> ~/Projects/Duck/ConfirmButton.qml
```

Symlinks, so building one costs nothing and the files stay exactly the ones you are editing. Reloader points the plugin's `componentPaths` and `settingsPath` at the farm, then calls `PluginService.unloadPlugin()` and `loadPlugin()` directly. **No shell reload, no `dms restart`, no lost session state** — and three long-standing traps disappear with it:

- a file you created since the shell started now resolves, instead of failing with a misleading *`Script …/X.js unavailable`* and *`File name case mismatch`*
- the reload after a failed one picks up your fix, instead of silently loading the cached old file and reporting success (DMS reaches an unloaded plugin through `enablePlugin()`, which skips the cache bust entirely — Reloader no longer goes through that IPC at all)
- an edit to the settings page shows up, instead of never reloading

`componentPaths` points at the farm only for the duration of the `loadPlugin()` call, and is handed straight back afterwards. That matters: a farm is a **snapshot**, so leaving it in place would hide files you add later and would quietly feed that stale snapshot to every *other* way of reloading the plugin — DMS's own reload IPC, the button in Settings, your own `dev.sh`. The component is already compiled and held by `PluginService` by then, so restoring it costs nothing and leaves no trace.

The settings page is the one deliberate exception: DMS loads `settingsPath` from a plain `file://` URL with no cache bust at all, so pointing it at the farm is the only way an edit there ever shows up. It always names the newest farm, which pruning keeps. `pluginDirectory` is left alone throughout, so the details view and **copy folder path** stay truthful. Farms are kept two deep per plugin and pruned on the next reload.

One thing this cannot fix: `dms ipc call plugins reload <id>` is still DMS's own reload, with all the limits above. A `dev.sh reload` built on it will not pick up a change to an imported file no matter what — use the popout, or bind a keybind to Reloader.

### Reload shell

Reloading a plugin cannot pick up a change to **DMS itself** — its own QML is compiled into the running engine, outside any plugin folder. That is what the **Reload shell** button is for: it calls `Quickshell.reload(false)`, which rebuilds the whole QML graph against a fresh engine in about two seconds, without restarting the process or dropping your session. Reloader also falls back to it on its own if a farm cannot be built, which in normal use never happens.

It sits past the sync button rather than next to **Reload all**, deliberately: it is the one action in that row that takes the whole shell with it, so it should not be a near miss for the one that does not.

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

Reloader still skips itself in the popout, so `./dev.sh reload` (or `dms ipc call plugins reload reloader`) is how you iterate on Reloader. Self-reload through the farm does work — it is held back only because reloading yourself with a syntax error leaves no button to click.

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

All logic lives in `Reloader.qml` on purpose: an entry file with no imports is the one shape that `dms ipc call plugins reload reloader` can refresh on its own, which is what `./dev.sh reload` relies on. See [How the reload works](#how-the-reload-works) and the notes in [ROADMAP.md](ROADMAP.md#notes--learnings).

## Versioning & releases

Reloader follows [Semantic Versioning](https://semver.org/). The single source of truth for the version is `plugin.json`.

To cut a release:

1. Add your changes under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
2. Run `./dev.sh release 0.2.0`: it bumps `plugin.json`, dates the changelog entry, updates the compare links, commits and creates the `v0.2.0` tag.
3. `git push --follow-tags`. GitHub Actions checks the tag matches `plugin.json`, zips the plugin and publishes a release with the changelog notes.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `chore:` …).

## License

[MIT](LICENSE) © Gamen0ut
