import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

Kirigami.FormLayout {
    id: page

    property alias cfg_showLatencyText: showTextBox.checked
    property alias cfg_useCustomColors: customColorsBox.checked
    property alias cfg_okColor: okColorButton.color
    property alias cfg_warningColor: warningColorButton.color
    property alias cfg_criticalColor: criticalColorButton.color
    property alias cfg_useCustomBackgroundOpacity: customBackgroundBox.checked
    property int cfg_defaultTimescale
    // Plain int rather than an alias: the kcfg key is an Int and Slider.value
    // is a real.
    property int cfg_backgroundOpacity

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

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Colours") }

    QQC2.CheckBox {
        id: customColorsBox
        Kirigami.FormData.label: i18n("Indicator:")
        text: i18n("Use custom colours")
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        text: i18n("Left unchecked, the indicator follows the colour scheme and adapts automatically when you switch between light and dark themes.")
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        wrapMode: Text.WordWrap
    }

    KQuickControls.ColorButton {
        id: okColorButton
        Kirigami.FormData.label: i18n("OK:")
        enabled: customColorsBox.checked
        showAlphaChannel: false
        dialogTitle: i18n("Colour for the OK state")
    }

    KQuickControls.ColorButton {
        id: warningColorButton
        Kirigami.FormData.label: i18n("Warning:")
        enabled: customColorsBox.checked
        showAlphaChannel: false
        dialogTitle: i18n("Colour for the Warning state")
    }

    KQuickControls.ColorButton {
        id: criticalColorButton
        Kirigami.FormData.label: i18n("Critical:")
        enabled: customColorsBox.checked
        showAlphaChannel: false
        dialogTitle: i18n("Colour for the Critical state")
    }

    // Preview, so the choice can be judged without closing the dialog. These
    // track the buttons rather than the saved configuration so unapplied edits
    // show up immediately.
    RowLayout {
        Kirigami.FormData.label: i18n("Preview:")
        spacing: Kirigami.Units.largeSpacing

        Repeater {
            model: [
                {
                    label: i18n("OK"),
                    custom: okColorButton.color,
                    theme: Kirigami.Theme.positiveTextColor
                },
                {
                    label: i18n("Warning"),
                    custom: warningColorButton.color,
                    theme: Kirigami.Theme.neutralTextColor
                },
                {
                    label: i18n("Critical"),
                    custom: criticalColorButton.color,
                    theme: Kirigami.Theme.negativeTextColor
                }
            ]

            RowLayout {
                id: swatch
                required property var modelData
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: implicitWidth
                    radius: width / 2
                    color: customColorsBox.checked
                        ? swatch.modelData.custom
                        : swatch.modelData.theme
                }

                QQC2.Label {
                    text: swatch.modelData.label
                    font: Kirigami.Theme.smallFont
                }
            }
        }
    }

    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Background") }

    QQC2.CheckBox {
        id: customBackgroundBox
        Kirigami.FormData.label: i18n("Desktop:")
        text: i18n("Use custom background opacity")
    }

    QQC2.Label {
        Layout.maximumWidth: Kirigami.Units.gridUnit * 20
        text: i18n("Applies to the widget placed on the desktop. A widget cannot change the background of its own panel popup — that one is drawn by the shell — and panels have their own Opacity setting in panel settings.")
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Opacity:")
        spacing: Kirigami.Units.largeSpacing

        QQC2.Slider {
            id: opacitySlider
            enabled: customBackgroundBox.checked
            Layout.minimumWidth: Kirigami.Units.gridUnit * 12

            from: 0
            to: 100
            stepSize: 5

            // Written on user movement and loaded once on completion, the same
            // way timescaleBox does it above. A two-way `value:` binding would
            // be destroyed the moment dragging assigns value imperatively.
            onMoved: page.cfg_backgroundOpacity = value
            Component.onCompleted: value = page.cfg_backgroundOpacity
        }

        QQC2.Label {
            enabled: customBackgroundBox.checked
            text: i18n("%1%", Math.round(opacitySlider.value))
            font.features: ({ "tnum": 1 })   // stop the width jittering
        }
    }
}
