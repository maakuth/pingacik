import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    // KCM convention: cfg_<key> properties are read and written automatically
    // by the Plasma configuration dialog.
    property alias cfg_host: hostField.text
    property alias cfg_pingInterval: intervalBox.value
    property alias cfg_pingTimeout: timeoutBox.value
    property alias cfg_showLatencyText: showTextBox.checked
    property int cfg_defaultTimescale

    QQC2.TextField {
        id: hostField
        Kirigami.FormData.label: i18n("Host to ping:")
        placeholderText: "8.8.8.8"
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        text: i18n("A hostname or IP address. Changing it clears the collected history.")
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        wrapMode: Text.WordWrap
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.SpinBox {
        id: intervalBox
        Kirigami.FormData.label: i18n("Ping every:")
        from: 1
        to: 60
        textFromValue: (value) => i18np("%1 second", "%1 seconds", value)
        valueFromText: (text) => parseInt(text, 10)
    }

    QQC2.SpinBox {
        id: timeoutBox
        Kirigami.FormData.label: i18n("Reply timeout:")
        from: 1
        to: 60
        textFromValue: (value) => i18np("%1 second", "%1 seconds", value)
        valueFromText: (text) => parseInt(text, 10)
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 18
        visible: timeoutBox.value > intervalBox.value
        text: i18n("The timeout is longer than the interval, so each unanswered ping will skip the ticks that fall inside it — measurements thin out exactly while the connection is failing.")
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.neutralTextColor
        wrapMode: Text.WordWrap
    }

    Item { Kirigami.FormData.isSection: true }

    QQC2.CheckBox {
        id: showTextBox
        Kirigami.FormData.label: i18n("Panel:")
        text: i18n("Show latency next to the indicator")
    }

    QQC2.ComboBox {
        id: timescaleBox
        Kirigami.FormData.label: i18n("Default chart range:")

        textRole: "label"
        valueRole: "seconds"
        model: [
            { label: i18n("1 minute"),   seconds: 60 },
            { label: i18n("5 minutes"),  seconds: 300 },
            { label: i18n("15 minutes"), seconds: 900 },
            { label: i18n("1 hour"),     seconds: 3600 }
        ]

        onActivated: page.cfg_defaultTimescale = currentValue

        Component.onCompleted: {
            currentIndex = indexOfValue(page.cfg_defaultTimescale);
        }
    }
}
