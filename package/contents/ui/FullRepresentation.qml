import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import "../code/pingstate.js" as PingState

PlasmaExtras.Representation {
    id: full

    required property var widget

    Layout.minimumWidth: Kirigami.Units.gridUnit * 22
    Layout.minimumHeight: Kirigami.Units.gridUnit * 20
    Layout.preferredWidth: Kirigami.Units.gridUnit * 28
    Layout.preferredHeight: Kirigami.Units.gridUnit * 26

    collapseMarginsHint: true

    function formatMs(v) {
        return v >= 0 ? i18n("%1 ms", v.toFixed(1)) : "—";
    }

    readonly property bool onDesktop:
        Plasmoid.formFactor === PlasmaCore.Types.Planar

    // Only on the desktop, where the background belongs to the applet. In a
    // panel the popup's background is picked by the shell from the containment's
    // hints, so there is nothing here for this to act on.
    readonly property bool customBackground:
        onDesktop && Plasmoid.configuration.useCustomBackgroundOpacity

    // Representation is a PlasmaComponents.Page, so this fills the whole control
    // behind both the header and the content. Putting the alpha here rather than
    // on the item's `opacity` is the point: the surface goes translucent while
    // the text and chart on top of it stay fully opaque.
    background: Rectangle {
        visible: full.customBackground
        radius: Kirigami.Units.cornerRadius

        color: Qt.rgba(Kirigami.Theme.backgroundColor.r,
                       Kirigami.Theme.backgroundColor.g,
                       Kirigami.Theme.backgroundColor.b,
                       Plasmoid.configuration.backgroundOpacity / 100)

        // A translucent surface over a busy wallpaper needs an edge, or it stops
        // reading as a surface at all.
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                              Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b, 0.15)
    }

    header: PlasmaExtras.PlasmoidHeading {
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                StatusDot {
                    Layout.alignment: Qt.AlignVCenter
                    statusColor: full.widget.statusColor
                    pulsing: full.widget.connectionStatus !== PingState.OK
                }

                PlasmaComponents.Label {
                    text: full.widget.statusText
                    font.weight: Font.Bold
                    color: full.widget.statusColor
                }

                PlasmaComponents.Label {
                    text: "·"
                    opacity: 0.4
                }

                PlasmaComponents.Label {
                    text: full.widget.host
                    opacity: 0.7
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                PlasmaComponents.Label {
                    text: full.widget.lastOk
                        ? full.formatMs(full.widget.lastRtt)
                        : i18n("timed out")
                    font.weight: Font.Bold
                    color: full.widget.lastOk
                        ? Kirigami.Theme.textColor
                        : full.widget.colorCritical
                    font.features: ({ "tnum": 1 })
                }

                // Desktop only. Plasma 6 gives widgets on the desktop no
                // right-click menu of their own — the handles that carry the
                // wrench appear only after a press and hold, and over the
                // scrollable log below that press is unreliable. In a panel this
                // is unnecessary, since right-clicking the icon already offers
                // Configure, and the header there is tight enough already.
                PlasmaComponents.ToolButton {
                    id: configureButton
                    visible: full.onDesktop && Plasmoid.hasConfigurationInterface

                    icon.name: "configure"
                    icon.width: Kirigami.Units.iconSizes.small
                    icon.height: Kirigami.Units.iconSizes.small
                    display: PlasmaComponents.ToolButton.IconOnly
                    flat: true

                    // Must not take focus, or Esc stops dismissing the popup.
                    focusPolicy: Qt.NoFocus

                    text: i18n("Configure Pingacik…")
                    PlasmaComponents.ToolTip { text: configureButton.text }

                    onClicked: {
                        const action = Plasmoid.internalAction("configure");
                        if (!action) {
                            return;
                        }
                        // The action can arrive disabled, and QAction::trigger()
                        // is a silent no-op while it is — Plasma's own
                        // ConfigOverlay force-enables it for the same reason.
                        action.enabled = true;
                        action.trigger();
                    }
                }
            }

            // Summary over everything still in the buffer.
            // A Flow rather than a RowLayout: in a narrow popup the five stats
            // wrap onto a second line instead of the last ones being clipped.
            Flow {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Repeater {
                    model: [
                        { label: i18n("avg"),  value: full.formatMs(full.widget.avgRtt) },
                        { label: i18n("min"),  value: full.formatMs(full.widget.minRtt) },
                        { label: i18n("max"),  value: full.formatMs(full.widget.maxRtt) },
                        { label: i18n("loss"), value: i18n("%1%", full.widget.lossPercent.toFixed(1)) },
                        { label: i18n("sent"), value: String(full.widget.sampleCount) }
                    ]

                    Row {
                        id: statItem
                        required property var modelData
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.Label {
                            text: statItem.modelData.label
                            font: Kirigami.Theme.smallFont
                            opacity: 0.55
                        }
                        FigureLabel {
                            text: statItem.modelData.value
                        }
                    }
                }
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        PingChart {
            id: chart
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 9
            widget: full.widget
            timescale: Plasmoid.configuration.defaultTimescale
        }

        // ---- live ping log --------------------------------------------
        PlasmaComponents.Label {
            text: i18n("Live ping")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        // Wrapper so the "jump to latest" button can sit *over* the list rather
        // than inside it, where it would scroll away with the content.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 5

            PlasmaComponents.ScrollView {
                id: logScroll
                anchors.fill: parent

                contentItem: ListView {
                    id: logView
                    model: full.widget.logModel
                    clip: true
                    reuseItems: true

                    // Following the newest row is explicit state, deliberately not
                    // re-derived from the geometry on each append. Deriving it was
                    // the bug: the widget samples whether or not the popup is open,
                    // so by the first expand the model already holds hundreds of
                    // rows. A view created at contentY 0 is nowhere near the tail,
                    // the check failed on the very first append, and since that was
                    // the only place it was consulted it never recovered — the log
                    // opened on a row from minutes ago and sat there.
                    property bool followTail: true

                    // Set only while we are the ones moving the view, so our own
                    // scrolling is not mistaken for the user taking over.
                    property bool selfScrolling: false

                    function jumpToTail() {
                        selfScrolling = true;
                        positionViewAtEnd();
                        selfScrolling = false;
                    }

                    // Driven from contentY rather than onMovementEnded because that
                    // is the one thing every way of scrolling has in common:
                    // dragging the scrollbar moves contentY without ever starting a
                    // flick, so a movement-based handler would miss it entirely.
                    // Wheel, drag, flick, scrollbar and keyboard all land here.
                    //
                    // isAtTail is called directly rather than read from a bound
                    // property: a binding on contentY is not guaranteed to have
                    // been re-evaluated by the time this handler runs, and reading
                    // the stale value left following switched on after the user had
                    // scrolled away, so the next row yanked the view back.
                    onContentYChanged: {
                        if (!selfScrolling) {
                            followTail = PingState.isAtTail(
                                contentY, contentHeight, height,
                                Kirigami.Units.gridUnit);
                        }
                    }

                    // Deferred so the new row is laid out and contentHeight updated
                    // before we measure the end; it also coalesces a burst of rows
                    // into a single scroll.
                    onCountChanged: if (followTail) { Qt.callLater(jumpToTail); }

                    Component.onCompleted: Qt.callLater(jumpToTail)

                    // Reopening the popup is a fresh look at the connection, so it
                    // starts following again wherever the view had been left. This
                    // also absorbs any stray contentY change from while the popup
                    // was collapsed and this had no meaningful height.
                    Connections {
                        target: full.widget

                        function onExpandedChanged() {
                            if (full.widget.expanded) {
                                logView.followTail = true;
                                Qt.callLater(logView.jumpToTail);
                            }
                        }
                    }

                    delegate: RowLayout {
                        id: logRow
                        required property var model
                        width: logView.width
                        spacing: Kirigami.Units.largeSpacing

                        FigureLabel {
                            text: Qt.formatTime(new Date(logRow.model.timestamp), "hh:mm:ss")
                            opacity: 0.55
                        }

                        FigureLabel {
                            Layout.fillWidth: true

                            text: {
                                if (logRow.model.ok) {
                                    return i18n("reply from %1: %2 ms",
                                                full.widget.host,
                                                logRow.model.rtt.toFixed(1));
                                }
                                // A packet that simply went unanswered needs no
                                // explanation. Anything else — no route, no
                                // permission — would otherwise be indistinguishable
                                // from ordinary loss, so say what ping said.
                                return logRow.model.err
                                    ? i18n("%1: %2", full.widget.host, logRow.model.err)
                                    : i18n("no reply from %1", full.widget.host);
                            }

                            // Same thresholds the state machine uses, so a row's
                            // colour matches the verdict that sample contributed.
                            color: {
                                if (!logRow.model.ok) {
                                    return full.widget.colorCritical;
                                }
                                if (logRow.model.rtt > Plasmoid.configuration.redMs) {
                                    return full.widget.colorCritical;
                                }
                                if (logRow.model.rtt > Plasmoid.configuration.yellowMs) {
                                    return full.widget.colorWarning;
                                }
                                return Kirigami.Theme.textColor;
                            }
                        }
                    }
                }
            }

            // Only offered while following is paused, so the newest result is
            // one click away instead of a scroll back through the backlog.
            PlasmaComponents.Button {
                anchors.right: logScroll.right
                anchors.bottom: logScroll.bottom
                anchors.rightMargin: Kirigami.Units.gridUnit
                anchors.bottomMargin: Kirigami.Units.smallSpacing

                icon.name: "go-bottom"
                text: i18n("Jump to latest")

                // Must not take focus from the popup, or dismissing it with Esc
                // stops working while the button is showing.
                focusPolicy: Qt.NoFocus

                visible: opacity > 0
                opacity: logView.followTail ? 0 : 1
                Behavior on opacity {
                    NumberAnimation { duration: Kirigami.Units.shortDuration }
                }

                onClicked: {
                    logView.followTail = true;
                    logView.jumpToTail();
                }
            }
        }
    }
}
