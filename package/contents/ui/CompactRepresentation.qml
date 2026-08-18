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

    // Nothing inside may ever paint outside the slot the panel granted. This
    // is the guarantee that a squeezed applet cannot spill its dot over the
    // neighbouring widgets, whatever the cause.
    clip: true

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

    // The panel imposes the cross dimension, so the applet only ever asks for
    // room along its own axis and can always shrink: the label elides instead
    // of the row spilling past the slot the panel actually granted.
    Layout.minimumWidth: 0
    Layout.minimumHeight: 0
    Layout.preferredWidth: vertical ? -1 : layout.implicitWidth
    Layout.preferredHeight: vertical ? layout.implicitHeight : -1

    acceptedButtons: Qt.LeftButton
    onClicked: widget.expanded = !widget.expanded

    RowLayout {
        id: layout
        // Fill the slot rather than centring a content-sized row in it:
        // centring pins the dot to the row's left edge, so its position rides
        // the readout's width as the text changes between samples — which is
        // how the blob ended up somewhere else on a timeout. Filling keeps the
        // dot anchored to the slot itself; the label takes the slack and elides.
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        StatusDot {
            id: dot
            // Horizontal: the row's left edge, vertically centred. Vertical:
            // the only child, filling the width and centring itself within it.
            Layout.alignment: compact.vertical ? Qt.AlignHCenter : Qt.AlignVCenter
            Layout.fillWidth: compact.vertical
            // Without this the dot's minimum width defaults to its implicit
            // width, so a panel that squeezes the applet below the dot's size
            // has nowhere to shrink it and the dot spills over the neighbours.
            // Allowing it to shrink (with clip on the applet as the backstop)
            // keeps it inside its own slot.
            Layout.minimumWidth: 0
            Layout.minimumHeight: 0
            statusColor: compact.widget.statusColor
            pulsing: compact.widget.connectionStatus !== PingState.OK

            // Track the panel thickness, but never grow past what a small
            // icon would occupy.
            implicitWidth: Math.min(
                Kirigami.Units.iconSizes.small,
                Math.max(6, (compact.vertical ? compact.width : compact.height) * 0.5))
        }

        PlasmaComponents.Label {
            id: label
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
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
                : compact.widget.colorCritical

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
