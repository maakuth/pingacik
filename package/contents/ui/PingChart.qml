import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.quickcharts as Charts
import "../code/pingstate.js" as PingState

ColumnLayout {
    id: chartRoot

    required property var widget

    property int timescale: 300     // seconds shown
    readonly property int maxPoints: 300
    readonly property int gridLines: 4

    // Recomputed whenever a sample lands (widget.revision) or the timescale
    // changes. Buckets are {t, avg, min, max, lossCount, total}.
    readonly property var points: {
        widget.revision;   // dependency: the sample array mutates in place
        const slice = PingState.windowSlice(widget.samples, timescale, Date.now());
        return PingState.downsample(slice, maxPoints);
    }

    // Line values. Lost buckets carry the previous value forward so the line
    // does not dive to zero — the red band drawn underneath is what marks the
    // outage, which reads more honestly than a spike to the floor.
    readonly property var lineValues: {
        const out = [];
        let carry = 0;
        for (let i = 0; i < points.length; i++) {
            if (points[i].avg >= 0) {
                carry = points[i].avg;
            }
            out.push(carry);
        }
        return out;
    }

    readonly property real dataMax: {
        let m = 0;
        for (let i = 0; i < points.length; i++) {
            if (points[i].max > m) {
                m = points[i].max;
            }
        }
        return m;
    }

    // Round the axis up to something a human would pick, so the gridlines
    // land on readable numbers instead of 173.4 ms.
    readonly property real axisMax: {
        if (dataMax <= 0) {
            return 100;
        }
        const target = dataMax * 1.15;
        const mag = Math.pow(10, Math.floor(Math.log(target) / Math.LN10));
        const steps = [1, 2, 2.5, 5, 10];
        for (let i = 0; i < steps.length; i++) {
            if (mag * steps[i] >= target) {
                return mag * steps[i];
            }
        }
        return mag * 10;
    }

    readonly property real gutterWidth:
        yAxisMetrics.width + Kirigami.Units.smallSpacing

    TextMetrics {
        id: yAxisMetrics
        font: Kirigami.Theme.smallFont
        text: i18n("%1 ms", Math.round(chartRoot.axisMax))
    }

    spacing: Kirigami.Units.smallSpacing

    // ---- header: title + timescale selector ---------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: i18n("Round-trip time")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        Item { Layout.fillWidth: true }

        // No ButtonGroup: `checked` is bound to the current timescale, which
        // makes the selection exclusive by construction.
        Repeater {
            model: [
                { label: i18n("1m"),  seconds: 60 },
                { label: i18n("5m"),  seconds: 300 },
                { label: i18n("15m"), seconds: 900 },
                { label: i18n("1h"),  seconds: 3600 }
            ]

            PlasmaComponents.ToolButton {
                required property var modelData
                text: modelData.label
                checkable: true
                checked: chartRoot.timescale === modelData.seconds
                onClicked: chartRoot.timescale = modelData.seconds
                font: Kirigami.Theme.smallFont
            }
        }
    }

    // ---- plot ---------------------------------------------------------
    Item {
        id: plotContainer
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Kirigami.Units.gridUnit * 7

        Rectangle {
            id: plotArea
            anchors.fill: parent
            anchors.leftMargin: chartRoot.gutterWidth

            color: Qt.rgba(Kirigami.Theme.textColor.r,
                           Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, 0.04)
            radius: Kirigami.Units.cornerRadius
            clip: true

            // Packet-loss bands, drawn beneath the line so the line stays legible.
            Repeater {
                model: chartRoot.points.length

                Rectangle {
                    required property int index
                    readonly property var point: chartRoot.points[index]
                    readonly property real slot:
                        plotArea.width / Math.max(1, chartRoot.points.length)

                    visible: point !== undefined && point.lossCount > 0
                    x: index * slot
                    y: 0
                    width: Math.max(1, slot)
                    height: plotArea.height

                    color: Kirigami.Theme.negativeTextColor
                    // Partially-lost buckets fade in proportion to how bad they
                    // were, so one drop stays visible while a sustained outage
                    // is unmistakable.
                    opacity: point === undefined ? 0
                        : 0.18 + 0.42 * (point.lossCount / Math.max(1, point.total))
                }
            }

            // Gridlines. Labels live outside plotArea because it clips.
            Repeater {
                model: chartRoot.gridLines + 1

                Rectangle {
                    required property int index
                    width: plotArea.width
                    height: 1
                    y: Math.round(plotArea.height * (1 - index / chartRoot.gridLines))
                    color: Kirigami.Theme.textColor
                    opacity: index === 0 ? 0.25 : 0.10
                }
            }

            Charts.LineChart {
                anchors.fill: parent
                anchors.topMargin: 1
                visible: chartRoot.points.length > 1

                valueSources: [
                    Charts.ArraySource { array: chartRoot.lineValues }
                ]
                colorSource: Charts.SingleValueSource {
                    value: chartRoot.widget.statusColor
                }
                fillColorSource: Charts.SingleValueSource {
                    value: Qt.rgba(chartRoot.widget.statusColor.r,
                                   chartRoot.widget.statusColor.g,
                                   chartRoot.widget.statusColor.b, 0.18)
                }

                fillOpacity: 1.0
                lineWidth: 1.5
                interpolate: false

                xRange {
                    from: 0
                    to: Math.max(1, chartRoot.points.length - 1)
                    automatic: false
                }
                yRange {
                    from: 0
                    to: chartRoot.axisMax
                    automatic: false
                }
            }

            PlasmaComponents.Label {
                anchors.centerIn: parent
                visible: chartRoot.points.length <= 1
                text: i18n("Collecting data…")
                font: Kirigami.Theme.smallFont
                opacity: 0.6
            }
        }

        // Y-axis labels, in the gutter to the left of the clipped plot area.
        Repeater {
            model: chartRoot.gridLines

            PlasmaComponents.Label {
                required property int index
                // index 0 is the baseline (0 ms), which needs no label.
                readonly property real fraction: (index + 1) / chartRoot.gridLines

                x: chartRoot.gutterWidth - width - Kirigami.Units.smallSpacing
                y: plotArea.y + plotArea.height * (1 - fraction) - height / 2

                text: i18n("%1 ms", Math.round(chartRoot.axisMax * fraction))
                font: Kirigami.Theme.smallFont
                opacity: 0.55
            }
        }
    }

    // ---- x axis -------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: chartRoot.gutterWidth

        PlasmaComponents.Label {
            text: chartRoot.timescale >= 3600
                ? i18np("%1 hour ago", "%1 hours ago", Math.round(chartRoot.timescale / 3600))
                : i18np("%1 minute ago", "%1 minutes ago", Math.round(chartRoot.timescale / 60))
            font: Kirigami.Theme.smallFont
            opacity: 0.55
        }

        Item { Layout.fillWidth: true }

        PlasmaComponents.Label {
            text: i18n("now")
            font: Kirigami.Theme.smallFont
            opacity: 0.55
        }
    }
}
