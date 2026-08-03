import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import "../code/pingstate.js" as PingState

MouseArea {
    id: compact

    // The root PlasmoidItem, injected by main.qml.
    required property var widget

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

    // The latency readout is the first thing to go when space runs out: on a
    // vertical panel there is no room beside the dot, and on a narrow
    // horizontal one the text would be clipped to uselessness.
    readonly property bool showText:
        Plasmoid.configuration.showLatencyText
        && !vertical
        && width >= dot.implicitWidth + label.implicitWidth
                    + Kirigami.Units.smallSpacing * 3

    Layout.minimumWidth: vertical ? 0 : layout.implicitWidth
    Layout.minimumHeight: vertical ? layout.implicitHeight : 0
    Layout.preferredWidth: Layout.minimumWidth
    Layout.preferredHeight: Layout.minimumHeight

    acceptedButtons: Qt.LeftButton
    onClicked: widget.expanded = !widget.expanded

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing

        StatusDot {
            id: dot
            Layout.alignment: Qt.AlignVCenter
            statusColor: compact.widget.statusColor
            pulsing: compact.widget.connectionStatus !== PingState.GREEN

            // Track the panel thickness, but never grow past what a small
            // icon would occupy.
            implicitWidth: Math.min(
                Kirigami.Units.iconSizes.small,
                Math.max(6, (compact.vertical ? compact.width : compact.height) * 0.5))
        }

        PlasmaComponents.Label {
            id: label
            Layout.alignment: Qt.AlignVCenter
            visible: compact.showText

            text: {
                if (compact.widget.sampleCount === 0) {
                    return "—";
                }
                return compact.widget.lastOk
                    ? i18n("%1 ms", Math.round(compact.widget.lastRtt))
                    : i18n("lost");
            }

            color: compact.widget.lastOk || compact.widget.sampleCount === 0
                ? Kirigami.Theme.textColor
                : Kirigami.Theme.negativeTextColor

            font.pixelSize: Math.max(
                Kirigami.Theme.smallFont.pixelSize,
                Math.min(Kirigami.Theme.defaultFont.pixelSize, compact.height * 0.5))
            font.features: ({ "tnum": 1 })  // stop the width jittering per digit
        }
    }
}
