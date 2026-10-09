import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import Quickshell

PluginComponent {
    id: root

    layerNamespacePlugin: "reloader"

    // Settings
    property bool showToasts: pluginData.showToasts !== undefined ? pluginData.showToasts : true
    property string excluded: pluginData.excluded || ""   // comma-separated ids to skip in "Reload all"

    // State
    property var plugins: []          // [{ id, state }]
    property var busy: ({})           // id -> true while reloading
    property var selected: ({})       // id -> true when ticked for "Reload selected"
    property bool reloadingAll: false
    property bool shellReloading: false
    readonly property string selfId: "reloader"

    // id -> the QML error from the last failed load, straight from PluginService
    property var loadErrors: ({})

    // Reads `plugins` and `selected`, so bindings on it update with either.
    readonly property int selectedCount: selectedIds().length

    Connections {
        target: root.pluginService
        function onPluginLoadFailed(pluginId, error) {
            const m = Object.assign({}, root.loadErrors)
            m[pluginId] = error
            root.loadErrors = m
        }
        function onPluginLoaded(pluginId) {
            if (root.loadErrors[pluginId] === undefined) return
            const m = Object.assign({}, root.loadErrors)
            delete m[pluginId]
            root.loadErrors = m
        }
    }

    // ---------- helpers ----------
    function excludedList() {
        return excluded.split(",").map(s => s.trim()).filter(s => s.length > 0)
    }

    function isExcluded(id) {
        return excludedList().indexOf(id) !== -1
    }

    function selectedIds() {
        return plugins.map(p => p.id).filter(id => id !== selfId && selected[id] === true)
    }

    function toggleSelected(id) {
        if (id === selfId) return
        const s = Object.assign({}, selected)
        if (s[id]) delete s[id]
        else s[id] = true
        selected = s
    }

    function clearSelection() {
        selected = ({})
    }

    function setBusy(id, value) {
        const b = Object.assign({}, busy)
        if (value) b[id] = true
        else delete b[id]
        busy = b
    }

    function stateOf(id) {
        for (var i = 0; i < plugins.length; i++)
            if (plugins[i].id === id) return plugins[i].state
        return ""
    }

    // The manifest DMS already parsed at scan time: id, name, description,
    // version, author, type, capabilities, permissions, requires_dms, source,
    // pluginDirectory, loaded.
    function pluginInfo(id) {
        if (!id || !pluginService) return null
        const all = pluginService.availablePlugins
        return (all && all[id]) ? all[id] : null
    }

    function parseList(stdout) {
        const out = []
        stdout.split("\n").forEach(line => {
            const m = line.trim().match(/^(\S+)\s+\[(.+)\]$/)
            if (m) out.push({ id: m[1], state: m[2] })
        })
        out.sort((a, b) => a.id.localeCompare(b.id))
        return out
    }

    // ---------- hot reload ----------
    // `dms ipc call plugins reload <id>` cannot reload a plugin that is more than
    // one file. PluginService busts the cache by appending ?t=<now> to the entry
    // file named in the manifest, but a relative import resolves against the base
    // URL with the query dropped, so every sibling the entry file imports keeps
    // its plain file:// URL and comes straight back out of Qt's type cache. The
    // plugin then reloads against stale code and still reports success.
    //
    // Loading it from a directory it has never been loaded from fixes all of it
    // at once: every URL under a fresh directory is new, so nothing there can be
    // cached — imported .js, sibling .qml types, files added since the shell
    // started, and the settings page alike. The directory is a farm of symlinks
    // into the real plugin folder, so it costs nothing and the files stay the ones
    // being edited.
    readonly property string farmRoot: Paths.strip(Paths.cache) + "/reloader"

    // Rewrites a farm path back to the real plugin folder, so reloading twice
    // does not nest one farm inside the next. Stateless on purpose: Reloader
    // reloading itself must not lose track of where a plugin really lives.
    function realPath(src, path) {
        if (path.indexOf(src + "/") === 0)
            return path
        const prefix = farmRoot + "/"
        if (path.indexOf(prefix) === 0) {
            const rest = path.slice(prefix.length)   // "<id>.<token>/<relative path>"
            const slash = rest.indexOf("/")
            if (slash !== -1)
                return src + "/" + rest.slice(slash + 1)
        }
        return path
    }

    // Relative to the plugin folder, so a manifest pointing at ./src/Widget.qml
    // keeps its subdirectory: the farm symlinks the folder's top level, so the
    // subdirectory resolves through it and its files get farm URLs too.
    function relTo(src, path) {
        return path.indexOf(src + "/") === 0 ? path.slice(src.length + 1) : path
    }

    function hotReload(id, silent, done) {
        // Reloading Reloader works, but unloadPlugin() destroys this object
        // mid-callback, so everything after it would run against a dead `root`.
        if (id === selfId) return
        const ps = pluginService
        const info = ps ? ps.availablePlugins[id] : null
        if (!info || !info.pluginDirectory || !info.componentPaths) {
            reloadShell(id)
            return
        }
        const src = info.pluginDirectory
        const farm = farmRoot + "/" + id + "." + Date.now()   // never a path seen before
        setBusy(id, true)
        // $1 = farm prefix, $2 = new farm, $3 = the real plugin folder. Farms are
        // named <id>.<epoch ms>, so sorting them is sorting them by age; the
        // newest is kept because the instance about to be replaced may still load
        // a file from it lazily. Dotfiles are left out, which keeps .git out.
        Proc.runCommand(null, ["sh", "-c",
            'set -e; ls -d -- "$1".* 2>/dev/null | sort | head -n -1 | xargs -r rm -rf --; ' +
            'mkdir -p -- "$2"; ' +
            'for f in "$3"/*; do [ -e "$f" ] && ln -s -- "$f" "$2"/; done; :',
            "reloader-farm", farmRoot + "/" + id, farm, src],
        (stdout, code) => {
            if (code !== 0) {
                root.setBusy(id, false)
                root.reloadShell(id)                  // could not build the farm
                return
            }
            // loadPlugin() reads these, so they have to point at the farm for the
            // duration of the call — and nothing else may ever see them that way.
            // A farm is a snapshot: left in place it hides files added later, and
            // every other way of reloading the plugin (DMS's own reload IPC, a
            // dev script, the button in Settings) would quietly serve that stale
            // snapshot instead of the real folder.
            const realPaths = ({})
            const farmPaths = ({})
            Object.keys(info.componentPaths).forEach(k => {
                realPaths[k] = root.realPath(src, info.componentPaths[k])
                farmPaths[k] = farm + "/" + root.relTo(src, realPaths[k])
            })
            info.componentPaths = farmPaths
            // The settings surface is the one exception, and it is safe: DMS loads
            // settingsPath from a plain file:// URL with no cache bust, so pointing
            // it at the farm is the only way an edit there ever shows up. The farm
            // it names is always the newest one, which pruning keeps.
            if (info.settingsPath)
                info.settingsPath = farm + "/" + root.relTo(src, root.realPath(src, info.settingsPath))
            // `ps`, not `pluginService`: unloadPlugin destroys this object when the
            // plugin being reloaded is Reloader itself, and the local reference
            // outlives it where a property read would not.
            ps.unloadPlugin(id)
            const ok = ps.loadPlugin(id, true)
            // The component is compiled and held by PluginService now, so handing
            // the real paths back costs nothing and leaves no trace behind.
            info.componentPaths = realPaths
            root.setBusy(id, false)
            if (!silent && root.showToasts) {
                if (ok) ToastService.showInfo("Reloaded " + id + " ✓")
                else    ToastService.showError("Reload failed: " + id, root.loadErrors[id] || "")
            }
            if (done) done(id, ok)
            root.refresh()
        }, 0, 10000, root)
    }

    // Rebuilds the QML graph against a fresh engine: DMS itself and every plugin,
    // without restarting the process. The soft form keeps reloadable state, so
    // there is no reason to pass true.
    //
    // `fallbackFor` is a plugin id when this is standing in for a hot reload whose
    // farm could not be built, and empty when the user asked for it outright.
    function reloadShell(fallbackFor) {
        if (shellReloading) return
        shellReloading = true
        if (showToasts) {
            if (fallbackFor)
                ToastService.showWarning("Reloading the shell for " + fallbackFor,
                                         "Could not prepare an isolated reload")
            else
                ToastService.showInfo("Reloading the shell…", "DMS and every plugin")
        }
        shellReloadTimer.restart()
    }

    Timer {
        id: shellReloadTimer
        interval: 150   // let the toast paint before the graph goes away
        onTriggered: Quickshell.reload(false)
    }

    // ---------- actions ----------
    function refresh() {
        Proc.runCommand("reloader.list", ["dms", "ipc", "call", "plugins", "list"], (stdout, code) => {
            if (code !== 0) {
                ToastService.showError("Reloader", "Could not list plugins (exit " + code + ")")
                return
            }
            root.plugins = root.parseList(stdout)
        }, 50, 5000, root)
    }

    // Always toasts: copying leaves no visible trace in the popout, so this is
    // the only feedback that it worked, even with showToasts off.
    function copyText(text, label) {
        Proc.runCommand(null, ["dms", "clipboard", "copy", text], (stdout, code) => {
            if (code !== 0) {
                ToastService.showError("Could not copy " + (label || text), stdout.trim() || ("exit " + code))
                return
            }
            if (label) ToastService.showInfo("Copied " + label, text)
            else       ToastService.showInfo("Copied: " + text)
        }, 0, 5000, root)
    }

    function toggleExcluded(id) {
        if (id === selfId) return
        const list = excludedList()
        const i = list.indexOf(id)
        const adding = i === -1
        if (adding) list.push(id)
        else list.splice(i, 1)
        const value = list.join(", ")
        // savePluginData emits pluginDataChanged, which re-evaluates `excluded`.
        if (pluginService) pluginService.savePluginData(root.pluginId, "excluded", value)
        else excluded = value
        if (showToasts)
            ToastService.showInfo(adding ? id + " skipped in \"Reload all\""
                                         : id + " back in \"Reload all\"")
    }

    function reloadOne(id, silent, done) {
        if (id === selfId) return
        hotReload(id, silent, done)
    }

    function reloadMany(targets, what) {
        if (targets.length === 0) return
        reloadingAll = true
        let remaining = targets.length
        const failed = []
        targets.forEach(id => reloadOne(id, true, (pid, ok) => {
            if (!ok) failed.push(pid)
            remaining -= 1
            if (remaining === 0) {
                root.reloadingAll = false
                if (!root.showToasts) return
                if (failed.length === 0)
                    ToastService.showInfo("Reloaded " + targets.length + " " + what + " ✓")
                else
                    ToastService.showError("Reloaded " + (targets.length - failed.length) + "/" + targets.length,
                                           "Failed: " + failed.join(", "))
            }
        }))
    }

    function reloadAll() {
        const skip = excludedList()
        const targets = plugins
            .map(p => p.id)
            .filter(id => id !== selfId && skip.indexOf(id) === -1)
        if (targets.length === 0) {
            if (showToasts) ToastService.showWarning("Nothing to reload", "Every plugin is excluded")
            return
        }
        reloadMany(targets, "plugins")
    }

    // Ticking a plugin is an explicit choice, so a selection ignores the
    // exclusion list.
    function reloadSelected() {
        reloadMany(selectedIds(), "selected")
    }

    Component.onCompleted: refresh()

    // ---------- bar ----------
    horizontalBarPill: Component {
        DankIcon {
            name: "refresh"
            size: root.iconSize
            color: root.reloadingAll ? Theme.primary : Theme.surfaceText
            RotationAnimation on rotation {
                running: root.reloadingAll
                loops: Animation.Infinite
                from: 0; to: 360; duration: 800
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "refresh"
            size: root.iconSize
            color: root.reloadingAll ? Theme.primary : Theme.surfaceText
            anchors.horizontalCenter: parent.horizontalCenter
            RotationAnimation on rotation {
                running: root.reloadingAll
                loops: Animation.Infinite
                from: 0; to: 360; duration: 800
            }
        }
    }

    // ---------- popout ----------
    popoutWidth: 380
    popoutHeight: 520

    popoutContent: Component {
        PopoutComponent {
            id: pop

            // Non-empty id = the detail view replaces the list.
            property string detailId: ""

            readonly property var detail: root.pluginInfo(detailId)
            readonly property int skippedCount: root.excludedList().length
            readonly property bool showActions: detailId === ""
            readonly property bool showSelection: showActions && root.selectedCount > 0
            readonly property int rowHeight: 36
            readonly property int bodyHeight: root.popoutHeight - pop.headerHeight - pop.detailsHeight
                                            - Theme.spacingXL * 2
                                            - (showActions ? rowHeight + Theme.spacingS : 0)
                                            - (showSelection ? rowHeight + Theme.spacingS : 0)

            readonly property var detailFields: {
                const d = pop.detail
                if (!d) return []
                return [
                    { label: "id",           value: d.id },
                    { label: "version",      value: d.version || "—" },
                    { label: "author",       value: d.author || "—" },
                    { label: "type",         value: d.type || "—" },
                    { label: "state",        value: root.stateOf(d.id) || "unknown" },
                    { label: "source",       value: d.source || "—" },
                    { label: "requires",     value: d.requires_dms ? "dms " + d.requires_dms : "any dms" },
                    { label: "capabilities", value: (d.capabilities && d.capabilities.length) ? d.capabilities.join(", ") : "—" },
                    { label: "permissions",  value: (d.permissions && d.permissions.length) ? d.permissions.join(", ") : "none" },
                    { label: "folder",       value: d.pluginDirectory ? Paths.shortenHome(d.pluginDirectory) : "—" }
                ]
            }

            headerText: pop.detail ? pop.detail.name : (pop.detailId ? pop.detailId : "Reloader")
            detailsText: {
                if (pop.detail)
                    return "v" + (pop.detail.version || "?") + " · " + (pop.detail.author || "unknown author")
                if (pop.detailId)
                    return "no manifest found"
                return pop.skippedCount > 0 ? root.plugins.length + " plugins · " + pop.skippedCount + " skipped"
                                            : root.plugins.length + " plugins"
            }
            showCloseButton: true

            // Shared by every hover label in the popout.
            DankTooltipV2 { id: tip }

            Component.onCompleted: root.refresh()

            Column {
                width: parent.width
                spacing: Theme.spacingS

                // ---- top actions ----
                Row {
                    visible: pop.showActions
                    spacing: Theme.spacingS

                    StyledRect {
                        width: allRow.implicitWidth + Theme.spacingM * 2
                        height: pop.rowHeight
                        radius: Theme.cornerRadius
                        color: allMouse.containsMouse ? Theme.primary : Theme.surfaceContainerHighest
                        opacity: root.reloadingAll ? 0.6 : 1

                        Row {
                            id: allRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS
                            DankIcon {
                                name: "refresh"
                                size: Theme.iconSize - 4
                                color: allMouse.containsMouse ? Theme.surface : Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: root.reloadingAll ? "Reloading…" : "Reload all"
                                font.pixelSize: Theme.fontSizeMedium
                                color: allMouse.containsMouse ? Theme.surface : Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: allMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.reloadingAll
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.reloadAll()
                            onEntered: tip.show("Reloads every plugin except Reloader and your exclusions", parent)
                            onExited: tip.hide()
                        }
                    }

                    StyledRect {
                        id: syncBtn
                        width: pop.rowHeight; height: pop.rowHeight
                        radius: Theme.cornerRadius
                        color: listMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                        DankIcon {
                            anchors.centerIn: parent
                            name: "sync"
                            size: Theme.iconSize - 4
                            color: Theme.surfaceText
                        }
                        MouseArea {
                            id: listMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.refresh()
                            onEntered: tip.show("Refresh the plugin list", syncBtn)
                            onExited: tip.hide()
                        }
                    }

                    // Sits past the sync button on purpose: it is the one action
                    // here that takes the whole shell with it, so it should not be
                    // a near miss for "Reload all".
                    StyledRect {
                        id: shellBtn
                        width: shellRow.implicitWidth + Theme.spacingM * 2
                        height: pop.rowHeight
                        radius: Theme.cornerRadius
                        color: shellMouse.containsMouse ? Theme.warning : Theme.surfaceContainerHigh
                        opacity: root.shellReloading ? 0.6 : 1

                        Row {
                            id: shellRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS
                            DankIcon {
                                name: "bolt"
                                size: Theme.iconSize - 4
                                color: shellMouse.containsMouse ? Theme.surface : Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: root.shellReloading ? "Reloading…" : "Reload shell"
                                font.pixelSize: Theme.fontSizeMedium
                                color: shellMouse.containsMouse ? Theme.surface : Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: shellMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.shellReloading
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.reloadShell("")
                            onEntered: tip.show("Reloads DMS itself and every plugin · needed after editing DMS, not plugins", shellBtn)
                            onExited: tip.hide()
                        }
                    }
                }

                // ---- selection actions (only while something is ticked) ----
                Row {
                    visible: pop.showSelection
                    spacing: Theme.spacingS

                    StyledRect {
                        width: selRow.implicitWidth + Theme.spacingM * 2
                        height: pop.rowHeight
                        radius: Theme.cornerRadius
                        color: selMouse.containsMouse ? Theme.primary : Theme.primarySelected
                        opacity: root.reloadingAll ? 0.6 : 1

                        Row {
                            id: selRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS
                            DankIcon {
                                name: "refresh"
                                size: Theme.iconSize - 4
                                color: selMouse.containsMouse ? Theme.surface : Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: "Reload " + root.selectedCount + " selected"
                                font.pixelSize: Theme.fontSizeMedium
                                color: selMouse.containsMouse ? Theme.surface : Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: selMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !root.reloadingAll
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.reloadSelected()
                            onEntered: tip.show("A selection ignores the exclusion list", parent)
                            onExited: tip.hide()
                        }
                    }

                    StyledRect {
                        id: clearBtn
                        width: clearRow.implicitWidth + Theme.spacingM * 2
                        height: pop.rowHeight
                        radius: Theme.cornerRadius
                        color: clearMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                        Row {
                            id: clearRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS
                            DankIcon {
                                name: "close"
                                size: Theme.iconSize - 6
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: "Clear"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.clearSelection()
                            onEntered: tip.show("Untick every plugin", clearBtn)
                            onExited: tip.hide()
                        }
                    }
                }

                // ---- body: plugin list or detail view ----
                Item {
                    width: parent.width
                    height: Math.max(120, pop.bodyHeight)

                    // --- plugin list ---
                    ListView {
                        anchors.fill: parent
                        visible: pop.detailId === ""
                        clip: true
                        spacing: Theme.spacingXS
                        model: root.plugins

                        delegate: StyledRect {
                            id: row

                            required property var modelData
                            readonly property bool isSelf: modelData.id === root.selfId
                            readonly property bool isBusy: root.busy[modelData.id] === true
                            readonly property bool isLoaded: modelData.state === "loaded"
                            readonly property bool isSkipped: root.isExcluded(modelData.id)
                            readonly property bool isSelected: root.selected[modelData.id] === true

                            width: ListView.view.width
                            height: 44
                            radius: Theme.cornerRadius
                            color: isSelected ? Theme.primarySelected
                                 : rowHover.hovered ? Theme.surfaceContainerHighest
                                 : Theme.surfaceContainerHigh

                            // A HoverHandler keeps reporting hover while the pointer is
                            // over a child MouseArea, which a parent MouseArea would not.
                            HoverHandler { id: rowHover }

                            // Declared before every interactive child so they sit on top
                            // of it; plain Items (icons, labels) fall through to here.
                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                enabled: !row.isBusy
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton)
                                        pop.detailId = row.modelData.id
                                    else if (!row.isSelf)
                                        root.reloadOne(row.modelData.id, false)
                                }
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingS

                                // Tick for "Reload selected"
                                Item {
                                    id: checkBtn
                                    width: 22; height: 22
                                    anchors.verticalCenter: parent.verticalCenter

                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: !row.isSelf
                                        width: 18; height: 18
                                        radius: 4
                                        color: row.isSelected ? Theme.primary : "transparent"
                                        border.width: row.isSelected ? 0 : 2
                                        border.color: checkMouse.containsMouse ? Theme.primary : Theme.surfaceVariantText

                                        DankIcon {
                                            anchors.centerIn: parent
                                            visible: row.isSelected
                                            name: "check"
                                            size: 14
                                            color: Theme.surface
                                        }
                                    }
                                    MouseArea {
                                        id: checkMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: !row.isSelf
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleSelected(row.modelData.id)
                                        onEntered: tip.show(row.isSelected ? "Remove from the selection"
                                                                           : "Add to the selection", checkBtn)
                                        onExited: tip.hide()
                                    }
                                }

                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: row.isLoaded ? Theme.primary : Theme.error
                                    opacity: row.isSkipped ? 0.5 : 1
                                }
                                StyledText {
                                    text: row.modelData.id
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceText
                                    opacity: row.isSkipped ? 0.6 : 1
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    visible: text.length > 0
                                    text: row.isSelf ? "(this)" : (!row.isLoaded ? row.modelData.state : (row.isSkipped ? "skipped" : ""))
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                // Copy the plugin id
                                Item {
                                    id: copyBtn
                                    width: 28; height: 28
                                    opacity: rowHover.hovered ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: "content_copy"
                                        size: Theme.iconSize - 6
                                        color: copyMouse.containsMouse ? Theme.primary : Theme.surfaceVariantText
                                    }
                                    MouseArea {
                                        id: copyMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: copyBtn.opacity > 0
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.copyText(row.modelData.id, "")
                                        onEntered: tip.show("Copy the plugin id", copyBtn)
                                        onExited: tip.hide()
                                    }
                                }

                                // Skip in / restore to "Reload all"
                                Item {
                                    id: skipBtn
                                    width: 28; height: 28
                                    visible: !row.isSelf
                                    opacity: (rowHover.hovered || row.isSkipped) ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.shortDuration } }

                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: "block"
                                        size: Theme.iconSize - 6
                                        color: row.isSkipped ? Theme.error
                                             : skipMouse.containsMouse ? Theme.primary
                                             : Theme.surfaceVariantText
                                    }
                                    MouseArea {
                                        id: skipMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: skipBtn.opacity > 0
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleExcluded(row.modelData.id)
                                        onEntered: tip.show(row.isSkipped ? "Put back in \"Reload all\""
                                                                          : "Skip in \"Reload all\"", skipBtn)
                                        onExited: tip.hide()
                                    }
                                }

                                // Reload. No MouseArea: clicks fall through to the row.
                                Item {
                                    id: reloadBtn
                                    width: 28; height: 28
                                    visible: !row.isSelf

                                    HoverHandler {
                                        onHoveredChanged: {
                                            if (hovered) tip.show("Click to reload · right-click for details", reloadBtn)
                                            else tip.hide()
                                        }
                                    }

                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: "refresh"
                                        size: Theme.iconSize - 4
                                        color: rowHover.hovered ? Theme.primary : Theme.surfaceVariantText
                                        RotationAnimation on rotation {
                                            running: row.isBusy
                                            loops: Animation.Infinite
                                            from: 0; to: 360; duration: 800
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // --- detail view ---
                    Column {
                        anchors.fill: parent
                        visible: pop.detailId !== ""
                        spacing: Theme.spacingS

                        Row {
                            spacing: Theme.spacingXS

                            Item {
                                id: backBtn
                                width: 28; height: 28

                                DankIcon {
                                    anchors.centerIn: parent
                                    name: "arrow_back"
                                    size: Theme.iconSize - 4
                                    color: backMouse.containsMouse ? Theme.primary : Theme.surfaceText
                                }
                                MouseArea {
                                    id: backMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pop.detailId = ""
                                    onEntered: tip.show("Back to the plugin list", backBtn)
                                    onExited: tip.hide()
                                }
                            }
                            StyledText {
                                text: "Back"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        DankFlickable {
                            id: detailFlick
                            width: parent.width
                            height: Math.max(80, pop.bodyHeight - 28 - Theme.spacingS)
                            clip: true
                            contentWidth: width
                            contentHeight: detailCol.implicitHeight

                            Column {
                                id: detailCol
                                width: detailFlick.width
                                spacing: Theme.spacingXS

                                Repeater {
                                    model: pop.detailFields

                                    delegate: Row {
                                        id: field

                                        required property var modelData
                                        spacing: Theme.spacingS

                                        StyledText {
                                            width: 92
                                            text: field.modelData.label
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                        StyledText {
                                            width: detailCol.width - 92 - Theme.spacingS
                                            text: field.modelData.value
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceText
                                            wrapMode: Text.WrapAnywhere
                                        }
                                    }
                                }

                                Item { width: 1; height: Theme.spacingXS }

                                StyledText {
                                    visible: text.length > 0
                                    width: detailCol.width
                                    text: pop.detail ? (pop.detail.description || "") : ""
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                    wrapMode: Text.WordWrap
                                }

                                Item { width: 1; height: Theme.spacingXS }

                                Row {
                                    spacing: Theme.spacingS

                                    StyledRect {
                                        visible: pop.detailId !== root.selfId
                                        width: dReloadRow.implicitWidth + Theme.spacingM * 2
                                        height: 32
                                        radius: Theme.cornerRadius
                                        color: dReloadMouse.containsMouse ? Theme.primary : Theme.surfaceContainerHighest

                                        Row {
                                            id: dReloadRow
                                            anchors.centerIn: parent
                                            spacing: Theme.spacingXS
                                            DankIcon {
                                                name: "refresh"
                                                size: Theme.iconSize - 6
                                                color: dReloadMouse.containsMouse ? Theme.surface : Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            StyledText {
                                                text: "Reload"
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: dReloadMouse.containsMouse ? Theme.surface : Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                        MouseArea {
                                            id: dReloadMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.reloadOne(pop.detailId, false)
                                        }
                                    }

                                    StyledRect {
                                        width: dCopyRow.implicitWidth + Theme.spacingM * 2
                                        height: 32
                                        radius: Theme.cornerRadius
                                        color: dCopyMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                                        Row {
                                            id: dCopyRow
                                            anchors.centerIn: parent
                                            spacing: Theme.spacingXS
                                            DankIcon {
                                                name: "content_copy"
                                                size: Theme.iconSize - 6
                                                color: Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            StyledText {
                                                text: "Copy id"
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                        MouseArea {
                                            id: dCopyMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.copyText(pop.detailId, "")
                                        }
                                    }

                                    StyledRect {
                                        visible: !!(pop.detail && pop.detail.pluginDirectory)
                                        width: dPathRow.implicitWidth + Theme.spacingM * 2
                                        height: 32
                                        radius: Theme.cornerRadius
                                        color: dPathMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                                        Row {
                                            id: dPathRow
                                            anchors.centerIn: parent
                                            spacing: Theme.spacingXS
                                            DankIcon {
                                                name: "folder"
                                                size: Theme.iconSize - 6
                                                color: Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            StyledText {
                                                text: "Copy path"
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceText
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                        MouseArea {
                                            id: dPathMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.copyText(pop.detail.pluginDirectory, "the plugin folder")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
