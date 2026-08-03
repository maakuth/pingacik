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

    // A vertical panel has no room beside the dot, so the readout only makes
    // sense laid out horizontally.
    //
    // This deliberately does not test the current width: `width` is driven by
    // Layout.preferredWidth below, which comes from the row's implicit width,
    // which excludes the label while it is hidden. Gating visibility on that
    // width latches the label off permanently — it can never become wide
    // enough to allow the thing that would make it wide enough. Instead the
    // applet asks the panel for the room it needs and the label elides if the
    // panel cannot grant it.
    readonly property bool showText:
        Plasmoid.configuration.showLatencyText && !vertical

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

            // Only bites if the panel hands us less than we asked for; the
            // readout then shortens instead of spilling past the applet.
            elide: Text.ElideRight
        }
    }
}
