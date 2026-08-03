import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "preferences-system-network"
        source: "config/ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Thresholds")
        icon: "preferences-desktop-color"
        source: "config/ConfigThresholds.qml"
    }
}
