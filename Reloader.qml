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
            headerText: "Reloader"
            detailsText: root.plugins.length + " plugins"
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
                            required property var modelData
                            readonly property bool isSelf: modelData.id === root.selfId
                            readonly property bool isBusy: root.busy[modelData.id] === true
                            readonly property bool isLoaded: modelData.state === "loaded"

                            width: ListView.view.width
                            height: 44
                            radius: Theme.cornerRadius
                            color: rowMouse.containsMouse && !isSelf ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingS

                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: isLoaded ? Theme.primary : Theme.error
                                }
                                StyledText {
                                    text: modelData.id
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    visible: !isLoaded || isSelf
                                    text: isSelf ? "(this)" : modelData.state
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            DankIcon {
                                visible: !isSelf
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingM
                                anchors.verticalCenter: parent.verticalCenter
                                name: "refresh"
                                size: Theme.iconSize - 4
                                color: rowMouse.containsMouse ? Theme.primary : Theme.surfaceVariantText
                                RotationAnimation on rotation {
                                    running: isBusy
                                    loops: Animation.Infinite
                                    from: 0; to: 360; duration: 800
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !isSelf && !isBusy
                                cursorShape: isSelf ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: root.reloadOne(modelData.id, false)
                            }
                        }
                    }
                }
            }
        }
    }
}
