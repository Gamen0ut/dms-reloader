import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "reloader"

    // Settings
    property bool showToasts: pluginData.showToasts !== undefined ? pluginData.showToasts : true
    property string excluded: pluginData.excluded || ""   // comma-separated ids to skip in "Reload all"

    // State
    property var plugins: []          // [{ id, state }]
    property var busy: ({})           // id -> true while reloading
    property bool reloadingAll: false
    readonly property string selfId: "reloader"

    // ---------- helpers ----------
    function excludedList() {
        return excluded.split(",").map(s => s.trim()).filter(s => s.length > 0)
    }

    function isExcluded(id) {
        return excludedList().indexOf(id) !== -1
    }

    function setBusy(id, value) {
        const b = Object.assign({}, busy)
        if (value) b[id] = true
        else delete b[id]
        busy = b
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
    function copyId(id) {
        Proc.runCommand(null, ["dms", "clipboard", "copy", id], (stdout, code) => {
            if (code === 0) ToastService.showInfo("Copied: " + id)
            else ToastService.showError("Could not copy " + id, stdout.trim() || ("exit " + code))
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
        setBusy(id, true)
        Proc.runCommand(null, ["dms", "ipc", "call", "plugins", "reload", id], (stdout, code) => {
            root.setBusy(id, false)
            const ok = code === 0 && !/error|fail/i.test(stdout)
            if (!silent && root.showToasts) {
                if (ok) ToastService.showInfo("Reloaded " + id + " ✓")
                else    ToastService.showError("Reload failed: " + id, stdout.trim() || ("exit " + code))
            }
            if (done) done(id, ok, stdout)
            root.refresh()
        }, 0, 10000, root)
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
                    ToastService.showInfo("Reloaded " + targets.length + " plugins ✓")
                else
                    ToastService.showError("Reloaded " + (targets.length - failed.length) + "/" + targets.length,
                                           "Failed: " + failed.join(", "))
            }
        }))
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

            readonly property int skippedCount: root.excludedList().length

            headerText: "Reloader"
            detailsText: skippedCount > 0 ? root.plugins.length + " plugins · " + skippedCount + " skipped"
                                          : root.plugins.length + " plugins"
            showCloseButton: true

            Component.onCompleted: root.refresh()

            Column {
                width: parent.width
                spacing: Theme.spacingS

                // Top actions
                Row {
                    spacing: Theme.spacingS

                    StyledRect {
                        width: allRow.implicitWidth + Theme.spacingM * 2
                        height: 36
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
                        }
                    }

                    StyledRect {
                        width: 36; height: 36
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
                        }
                    }
                }

                // Plugin list
                Item {
                    width: parent.width
                    height: root.popoutHeight - pop.headerHeight - pop.detailsHeight - 36 - Theme.spacingXL * 2

                    ListView {
                        anchors.fill: parent
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

                            width: ListView.view.width
                            height: 44
                            radius: Theme.cornerRadius
                            color: rowHover.hovered && !isSelf ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                            // A HoverHandler keeps reporting hover while the pointer is
                            // over a child MouseArea, which a parent MouseArea would not.
                            HoverHandler { id: rowHover }

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingS

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

                            // Declared before the action buttons so they sit on top of it;
                            // the reload icon has no MouseArea and falls through to here.
                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                enabled: !row.isSelf && !row.isBusy
                                cursorShape: row.isSelf ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: root.reloadOne(row.modelData.id, false)
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
                                        onClicked: root.copyId(row.modelData.id)
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
                                    }
                                }

                                // Reload (click anywhere on the row)
                                Item {
                                    width: 28; height: 28
                                    visible: !row.isSelf

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
                }
            }
        }
    }
}
