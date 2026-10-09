# 🔁 Reloader Roadmap

Reloader exists to shorten one loop: **edit QML → see it in the shell**. Every idea below is judged on that, so features that save a plugin author seconds rank above features that look clever.

Legend: 🟢 easy · 🟡 medium · 🔴 hard. **Needs** = the DMS/Quickshell API an item depends on.

> API names here come from DMS 1.6.2 (`/usr/share/quickshell/dms/PLUGINS/`). Check the shipped docs and example plugins before starting an item — things move.

---

## 0.1.0 — Click to reload ✅

- [x] Bar pill for horizontal and vertical bars
- [x] Plugin list with load state, from `dms ipc call plugins list`
- [x] Reload one plugin by clicking its row
- [x] Reload all, with a single summary toast
- [x] Never reload itself
- [x] Exclusion list, editable from settings and from each row
- [x] Copy a plugin id to the clipboard
- [x] `dev.sh` link / reload / status / release

---

## 0.2.0 — A usable list

Everything that hurts once you have 15 plugins installed.

- [x] 🟢 **Hover labels** on every button in the popout. *Needs:* `DankTooltipV2.show(text, item)`
- [x] 🟡 **Multi-select** with a checkbox per row and a "Reload N selected" button, overriding the exclusion list
- [x] 🟡 **Plugin details on right-click**: version, author, description, permissions, source, folder. *Needs:* `pluginService.availablePlugins[id]`
- [ ] 🟢 **Filter field** at the top of the popout. *Needs:* `DankTextField`, a filtered list model
- [ ] 🟢 **Sort errored plugins first**, then alphabetically, so breakage is at the top
- [ ] 🟢 **Keyboard navigation** in the popout: ↑/↓ to move, Enter to reload, Esc to close. *Needs:* `Keys`, focus handling in popouts
- [ ] 🟢 **Favourites / pinned plugins** kept at the top — usually the one you are working on
- [ ] 🟡 **Last reloaded marker** ("3 s ago") per row. *Needs:* `savePluginState` for timestamps, a shared ticking clock
- [ ] 🟢 **Reload the last plugin again** on middle-click of the bar pill. *Needs:* `MouseArea.acceptedButtons`, `pillRightClickAction`

## 0.3.0 — Watch mode 🎯

The headline feature: stop clicking entirely.

- [ ] 🔴 **Watch a plugin folder** and reload on save. *Needs:* a file watcher — `FileView` polling, or `inotifywait` via `Process` with the `process` permission
- [ ] 🟡 **Debounce** bursts of writes (editors write several times per save) so one save is one reload
- [ ] 🟡 **Per-plugin watch toggle**, with watched rows marked in the list
- [ ] 🟡 **Watch indicator in the bar**: a dot on the pill while any watch is live
- [ ] 🟡 **Pause watching** while a bulk reload runs, to avoid reload storms
- [ ] 🟢 **Ignore list** for paths that should not trigger (`.git/`, `*.qmlc`, editor swap files)
- [ ] 🔴 **Resolve symlinked plugin folders** to their real path before watching — the usual dev setup is a symlink into `~/.config/DankMaterialShell/plugins/` — though the farm sidesteps it for reloading, since the symlinks it builds point at the real files

## 0.4.0 — Diagnostics

Make a failed reload tell you why.

- [ ] 🟡 **Expandable error details** on a row that failed, instead of a toast that disappears
- [ ] 🟡 **Capture the QML error output** from the reload so type errors are readable in the popout. *Needs:* finding where DMS surfaces plugin load errors (`pluginLoadFailed`)
- [ ] 🟢 **Reload history**: last N reloads with result and duration. *Needs:* `savePluginState`
- [ ] 🟢 **Reload duration** per plugin, to spot the slow ones
- [x] 🟡 **Retry on failure is unnecessary** — the farm gives a failed reload a fresh path, so fixing the error and clicking again just works (see Notes)
- [ ] 🟢 **Copy the error** to the clipboard, next to the copy-id button

## 0.5.0 — Plugin management

`dms ipc call plugins` also exposes `enable`, `disable` and `toggle`.

- [ ] 🟢 **Enable / disable a plugin** from its row. *Needs:* `plugins enable|disable|toggle`
- [ ] 🟢 **Scan for plugins** button, for a plugin folder you just created. *Needs:* `PluginService.scanPlugins()`
- [ ] 🟡 **Open the plugin folder** in a file manager or `$EDITOR`. *Needs:* `Quickshell.execDetached`, resolving the plugin path
- [ ] 🟡 **Show id, version and path** per row, from the manifest rather than the IPC list — `plugins status <id>` only prints the state
- [ ] 🟡 **Disabled plugins section**, collapsed, so the main list stays short

## 0.6.0 — Automation

- [ ] 🟡 **`dms ipc call reloader all`** to reload everything from a terminal or a keybind. *Needs:* exposing an `IpcHandler` from a plugin
- [ ] 🟡 **`dms ipc call reloader one <id>`**, respecting the exclusion list. *Needs:* IPC arguments
- [ ] 🟢 **Compositor keybind** example in the README (niri / Hyprland) for reload-all
- [ ] 🟡 **Post-reload hook**: run a command after a successful reload (e.g. notify a build script)
- [ ] 🔴 **Reload on git checkout**: watch `.git/HEAD` and reload when the branch changes

## 0.7.0 — Other surfaces

- [ ] 🟡 **Control Center tile** with a reload-all toggle. *Needs:* `ccWidget*` properties
- [ ] 🔴 **Launcher plugin**: type `rl duck` to reload a plugin by name. *Needs:* launcher plugin type, `trigger`, item lists
- [ ] 🟡 **Variants**: a pill bound to one specific plugin, for the one you work on all day. *Needs:* plugin variants / per-instance data
- [ ] 🟢 **Icon state in the bar**: error colour when the last reload failed

## 1.0.0 — Polished & published

- [ ] 🟢 Screenshots / a GIF of the popout in the README
- [ ] 🟡 Handle a missing `dms` binary and a stopped shell with a clear message instead of a bare exit code
- [ ] 🟡 Check performance: no busy timers, no leaked `Process` instances across reloads
- [ ] 🟢 Translations for the settings labels. *Needs:* `I18n.trFor` (and a `requires_dms` bump)
- [ ] 🟡 Submit Reloader to the DMS plugin registry
- [ ] 🟢 Decide whether watch mode is on by default for 1.0

---

## Unscheduled ideas

- 🧪 **Dry run**: show which plugins *would* reload, without reloading
- 📦 **Install from a zip or a git URL**, next to the reload list
- 🧹 **Clear `*.qmlc` caches** before a reload, for the stubborn cases
- 🔔 **Reload-all on shell theme change**, for plugins that cache theme values
- 🐢 **Stagger bulk reloads** by N ms instead of firing them all at once
- 📊 **Session counter**: "47 reloads today" — the plugin-author version of Duck's quack stats
- 🪞 **Self-reload**: reload Reloader itself via a detached process that survives its own unload

---

## Notes & learnings

DMS plugin API facts worth remembering, verified against DMS 1.6.2.

- **`plugins reload <id>` only re-reads the manifest's entry file.** `PluginService.reloadPlugin()` unloads, then calls `loadPlugin(id, bustCache=true)`, and that bust is one `?t=<now>` appended to each path in `component`/`components`. A relative import resolves against the base URL with the query **dropped** — verified: inside `Entry.qml?t=1`, `Qt.resolvedUrl("Lib.js")` returns a plain `file://…/Lib.js`. So every sibling comes straight back out of Qt's type cache and the plugin reloads against stale code while reporting `PLUGIN_RELOAD_SUCCESS`. It applies equally to `.pragma library` scripts, plain `.js`, and sibling `.qml` used as a type — all three were stale in one probe while the entry file updated. Three corollaries:
  - **A file added since the shell started cannot be resolved at all.** Qt already has the directory cached, so the import fails with a misleading *`Script …/X.js unavailable`* plus *`File name case mismatch`* — the file is right there, correctly cased.
  - **After any failed load the plugin is left unloaded, and `plugins reload` then takes a different branch**: `enablePlugin() → runStartupGate() → loadPlugin(id)`, *without* `bustCache`. So the reload right after you fix a syntax error silently loads the cached old file and reports success. That, not an alternating bug, is what "fails every other time" really was.
  - **The settings surface is never busted at all.** `Modules/Settings/PluginListItem.qml` loads `settingsPath` from a plain `file://` URL with no `?t=`.
- **An exception from a stale import inside a plugin's `Component.onCompleted` is swallowed** — nothing reaches the journal. The plugin reports loaded and is half-initialised, which is what "I reloaded and nothing changed" usually looks like.
- **Loading a plugin from a directory the engine has never seen reloads it completely**, with no shell reload. Every URL under a fresh directory is new, so nothing there can be cached. **Qt does not canonicalise symlinks for its type-cache key** — a farm of symlinks at `<cache>/reloader/<id>.<epoch ms>/` pointing into the real plugin folder loads the files you are editing under brand-new URLs, costs nothing to build, and refreshed all three import kinds plus a newly added file in one go. This is how Reloader reloads; see `hotReload()`.
- **A plugin can drive `PluginService` directly**: `unloadPlugin(id)` then `loadPlugin(id, true)`, having rewritten `availablePlugins[id].componentPaths` (and `settingsPath`) to the farm. The objects in `availablePlugins` are plain JS, so they can be mutated in place; DMS rebuilds them from the manifest on its next scan, so the override is temporary and `dms ipc call plugin-scan rescan <id>` is the escape hatch. Leave `pluginDirectory` alone — the details view and translations read it.
- **Reloader can hot-reload itself this way** (verified), as long as `PluginService` is captured into a local *before* `unloadPlugin` destroys the plugin instance: a local reference survives the destruction where a property read on the dead object would not. Still gated behind `selfId` for now, since reloading itself with a syntax error leaves no button to click.
- **Put the farm override back as soon as `loadPlugin()` returns.** A farm is a snapshot of the folder at reload time. Left in `availablePlugins`, it hides files added afterwards and hands that stale snapshot to every other reload route — DMS's reload IPC, the Settings button, a plugin's own `dev.sh` — which looks exactly like "I reloaded and nothing changed". The component is compiled and held by `PluginService` by then, so restoring the real paths costs nothing. `settingsPath` is the one worthwhile exception, since DMS loads it from a plain `file://` URL that is never cache-busted.
- **Never reuse a farm path.** An in-memory counter is not enough: Reloader reloading itself resets it, the path gets reused, and Qt serves the cached unit from the first time that URL was loaded. The token has to be a timestamp.

- **`capabilities` is required** by `plugin-schema.json` even though a plugin loads happily without it. Worth adding before submitting anywhere.
- **`plugins list` prints `id [state]`** per line, nothing else — no name, version or path. `plugins status <id>` prints just `loaded`. Anything richer has to come from reading each plugin's `plugin.json`.
- **`plugins reload` output** is `PLUGIN_RELOAD_SUCCESS: <id>` or a line containing `FAILED`, so exit code alone is not enough to detect failure.
- **Copy to the clipboard** with `dms clipboard copy <text>` (what `Paths.copyPathToClipboard` does internally) — no `wl-copy` dependency, and it lands in DMS's own clipboard history.
- **A plugin writes its own settings** with `pluginService.savePluginData(pluginId, key, value)`; there is no wrapper on `PluginComponent`, so guard against `pluginService` being null. The write emits `pluginDataChanged`, which re-evaluates `pluginData` bindings — so a row toggling an exclusion updates the settings page live, and vice versa.
- **Settings vs state**: `savePluginData` = user settings (DMS settings file, edited by the settings page). `savePluginState` = runtime data (counters, history) in `~/.local/state/DankMaterialShell/plugins/<id>_state.json`.
- **A child `MouseArea` with `hoverEnabled` steals hover from a parent `MouseArea`**, so hover-revealed row buttons flicker if visibility is bound to the parent's `containsMouse`. A `HoverHandler` on the row keeps reporting hover over children. An `Item` with no `MouseArea` does not accept clicks, so they fall through to the row below it — handy for a decorative icon inside a clickable row.
- **Later siblings are on top** in QML, so action buttons must be declared *after* the row's full-size `MouseArea` to receive their own clicks.
- **QML tracks dependencies through function calls**, so `isSkipped: root.isExcluded(id)` re-evaluates when `root.excluded` changes — no manual signal needed.
- **`MouseArea.cursorShape` works without `hoverEnabled`**, so a click-only row still gets a pointing hand.
- **Use `!== undefined` (or `??`) for boolean settings**: `pluginData.showToasts || true` would ignore a saved `false`.
- **The parsed manifest is already in memory**: `pluginService.availablePlugins[id]` holds every manifest field plus `pluginDirectory`, `manifestPath`, `source` (`user`/`system`), `surfaces` and `loaded`. A plugin never has to read another plugin's `plugin.json` itself. `WidgetHost` assigns the real `PluginService` singleton, not a trimmed wrapper, so its properties are all reachable.
- **`plugins list` is the only live state source**: `availablePlugins[id].loaded` is a snapshot from scan time, so pair the manifest with the IPC list for the current state.
- **`DankTooltipV2.show(text, item)`** parents a `Popup` into the window containing `item` and positions it on the side with room. It is single-line and elides at 500px, so hover labels have to stay short. One instance per popout can serve every button.
- **A `HoverHandler` gives a tooltip to a click-through item**: pointer handlers observe hover without accepting clicks, so an icon can show a label while its clicks still fall through to the row's `MouseArea` underneath.
- **Children of a `Flickable` are parented to its `contentItem`**, whose width is `contentWidth` — unset by default. `width: parent.width` on a child silently collapses to 0; bind to the flickable's own id (or set `contentWidth`) instead.
- **`visible` wants a real bool**: `visible: obj && obj.someString` warns about assigning a string. `!!(…)` fixes it.
- **A popout can be opened from code** with `PluginComponent`'s `triggerPopout()` / `closePopout()` — there is no IPC for a plugin's own popout. Worth knowing for smoke tests: `popoutContent` is a lazy `Component`, so a successful `plugins reload` proves nothing about it. Open it once and check `niri msg layers` for `dms:plugins:<id>` plus the journal for QML errors.
- **Docs ship with DMS**: `/usr/share/quickshell/dms/PLUGINS/` has a README, the manifest JSON schema and ~12 example plugins; settings components live in `/usr/share/quickshell/dms/Modules/Plugins/`.
