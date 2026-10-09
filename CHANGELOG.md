# Changelog

All notable changes to Reloader are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/).
While Reloader is `0.x`, minor bumps may change settings keys.

## [Unreleased]

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
