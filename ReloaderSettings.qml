import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "reloader"

    StyledText {
        width: parent.width
        text: "Reloader"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Hot-reload plugins without restarting DMS."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "showToasts"
        label: "Show toasts"
        description: "Notify after each reload"
        defaultValue: true
    }

    StringSetting {
        settingKey: "excluded"
        label: "Skip in \"Reload all\""
        description: "Comma-separated plugin ids, e.g. batteryOSD, mediaPlayer"
        placeholder: "id1, id2"
        defaultValue: ""
    }
}
