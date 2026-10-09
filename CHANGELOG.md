# Changelog

All notable changes to Reloader are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).
While Reloader is `0.x`, minor bumps may change settings keys.

## [Unreleased]

### Fixed
- A reload now really reloads plugins that are more than one file. `dms ipc call plugins reload <id>` only cache-busts the entry file the manifest names, and a relative import resolves against the base URL with the query dropped — so every imported `.js`, every sibling `.qml` used as a type, and the settings page all came back out of Qt's type cache. The plugin reloaded against stale code and still reported success.
- Reloading a plugin whose last load failed no longer silently loads the old file. Reloader no longer goes through DMS's reload IPC, so it never hits the `enablePlugin()` branch that skips the cache bust entirely.
- A file added since the shell started now resolves. Previously the import failed with a misleading *`Script …/X.js unavailable`* plus *`File name case mismatch`*.
- Reloader no longer leaves a plugin pointed at its farm once the reload is done. A farm is a snapshot, so leaving it in place hid files added afterwards and made every *other* reload route — DMS's reload IPC, the Settings button, a plugin's own `dev.sh` — serve that stale snapshot instead of the real folder. `componentPaths` is now restored as soon as `loadPlugin()` returns.

### Changed
- Reloads now go through a **symlink farm**: the plugin is loaded from `~/.cache/DankMaterialShell/reloader/<id>.<timestamp>/`, a directory of symlinks into the real plugin folder. Every URL under a path the engine has never seen is new, so nothing there can be cached — which is what makes a single-plugin reload complete. No shell reload, no restart, no lost session state.
- Failure toasts now carry the real QML error from `PluginService.pluginLoadFailed` instead of the text scraped from the IPC reply.

### Added
- **Reload shell** button in the popout's top row, for the one thing a plugin reload cannot cover: a change to DMS itself. It calls `Quickshell.reload(false)` — a fresh QML graph in about two seconds, no process restart and no lost session state. Placed past the sync button so it is not a near miss for "Reload all".
- The same shell reload doubles as a last-resort fallback, used only when a plugin's farm cannot be built.

## [0.2.0] - 2026-10-09

### Added
- Hover labels on every button in the popout, so the icons no longer have to be guessed.
- Multi-select: a checkbox on each row and a "Reload N selected" button that appears once something is ticked. A selection ignores the exclusion list, since ticking a plugin is an explicit choice.
- "Clear" button to drop the whole selection.
- Right-click a row for a details view: name, id, version, author, type, live state, source, `requires_dms`, capabilities, permissions, folder and description, with buttons to reload it, copy its id or copy its folder path.

## [0.1.0] - 2026-10-09

### Added
- 🔁 Bar widget for horizontal and vertical bars; the pill spins while a bulk reload runs.
- Popout listing every installed plugin with its load state, refreshed from `dms ipc call plugins list`.
- Click a row to reload that plugin, with a toast on success or failure.
- "Reload all", which reloads every plugin in one go and reports a single summary (and warns when everything is excluded).
- Reloader always skips itself, so the popout cannot reload itself away.
- Per-row actions on hover: copy the plugin id to the clipboard, and add/remove the plugin from the "Reload all" exclusions.
- Excluded plugins dim, keep a `skipped` label and are counted in the popout header.
- Settings: "Show toasts" toggle and a comma-separated exclusion list.
- `dev.sh` helper to link, reload, check status and cut releases.

[Unreleased]: https://github.com/Gamen0ut/dms-reloader/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Gamen0ut/dms-reloader/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Gamen0ut/dms-reloader/releases/tag/v0.1.0
