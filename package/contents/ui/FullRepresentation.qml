import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
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

    header: PlasmaExtras.PlasmoidHeading {
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                StatusDot {
                    Layout.alignment: Qt.AlignVCenter
                    statusColor: full.widget.statusColor
                    pulsing: full.widget.connectionStatus !== PingState.GREEN
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
                        : Kirigami.Theme.negativeTextColor
                    font.features: ({ "tnum": 1 })
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

        PlasmaComponents.ScrollView {
            id: logScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 5

            contentItem: ListView {
                id: logView
                model: full.widget.logModel
                clip: true
                reuseItems: true

                // Follow the tail, but stop fighting the user the moment they
                // scroll back to read something.
                readonly property bool atTail:
                    contentY >= contentHeight - height - Kirigami.Units.gridUnit

                onCountChanged: if (atTail) { positionViewAtEnd(); }

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

                        text: logRow.model.ok
                            ? i18n("reply from %1: %2 ms",
                                   full.widget.host, logRow.model.rtt.toFixed(1))
                            : i18n("no reply from %1", full.widget.host)

                        color: {
                            if (!logRow.model.ok) {
                                return Kirigami.Theme.negativeTextColor;
                            }
                            if (logRow.model.rtt > Plasmoid.configuration.redMs) {
                                return Kirigami.Theme.negativeTextColor;
                            }
                            if (logRow.model.rtt > Plasmoid.configuration.yellowMs) {
                                return Kirigami.Theme.neutralTextColor;
                            }
                            return Kirigami.Theme.textColor;
                        }
                    }
                }
            }
        }
    }
}
