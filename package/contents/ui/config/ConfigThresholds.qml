import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_yellowAfter: yellowAfterBox.value
    property alias cfg_redAfter: redAfterBox.value
    property alias cfg_recoverAfter: recoverAfterBox.value
    property alias cfg_yellowMs: yellowMsBox.value
    property alias cfg_redMs: redMsBox.value

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        text: i18n("The indicator turns yellow or red as soon as a threshold is crossed, but only returns to green after the link has proven itself again.")
        wrapMode: Text.WordWrap
        opacity: 0.8
    }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Packet loss") }

    QQC2.SpinBox {
        id: yellowAfterBox
        Kirigami.FormData.label: i18n("Yellow after:")
        from: 1
        to: 100
        textFromValue: (value) => i18np("%1 lost ping", "%1 lost pings", value)
        valueFromText: (text) => parseInt(text, 10)
    }

    QQC2.SpinBox {
        id: redAfterBox
        Kirigami.FormData.label: i18n("Red after:")
        from: 1
        to: 100
        textFromValue: (value) => i18np("%1 lost ping", "%1 lost pings", value)
        valueFromText: (text) => parseInt(text, 10)
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        text: i18n("Counted consecutively — a single reply resets the count.")
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        wrapMode: Text.WordWrap
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        visible: redAfterBox.value <= yellowAfterBox.value
        text: i18n("Red triggers at or before yellow, so the indicator will never show yellow for packet loss.")
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.neutralTextColor
        wrapMode: Text.WordWrap
    }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Latency") }

    QQC2.SpinBox {
        id: yellowMsBox
        Kirigami.FormData.label: i18n("Yellow above:")
        from: 1
        to: 100000
        stepSize: 10
        textFromValue: (value) => i18n("%1 ms", value)
        valueFromText: (text) => parseInt(text, 10)
    }

    QQC2.SpinBox {
        id: redMsBox
        Kirigami.FormData.label: i18n("Red above:")
        from: 1
        to: 100000
        stepSize: 10
        textFromValue: (value) => i18n("%1 ms", value)
        valueFromText: (text) => parseInt(text, 10)
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        text: i18n("Slow replies must also occur consecutively, using the same counts as packet loss, so a single spike is ignored.")
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        wrapMode: Text.WordWrap
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        visible: redMsBox.value <= yellowMsBox.value
        text: i18n("The red latency threshold is not above the yellow one.")
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.neutralTextColor
        wrapMode: Text.WordWrap
    }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Recovery") }

    QQC2.SpinBox {
        id: recoverAfterBox
        Kirigami.FormData.label: i18n("Back to green after:")
        from: 1
        to: 100
        textFromValue: (value) => i18np("%1 good ping", "%1 good pings", value)
        valueFromText: (text) => parseInt(text, 10)
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        text: i18n("Consecutive replies that are neither lost nor slower than the yellow latency threshold.")
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        wrapMode: Text.WordWrap
    }
}
