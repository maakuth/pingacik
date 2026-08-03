import QtQuick
import org.kde.kirigami as Kirigami

// The traffic-light circle, shared by the panel and the popup header.
Rectangle {
    id: dot

    property color statusColor: Kirigami.Theme.disabledTextColor
    property bool pulsing: false

    implicitWidth: Kirigami.Units.iconSizes.small
    implicitHeight: implicitWidth

    radius: width / 2
    color: statusColor

    // A subtle ring keeps the dot legible against panel backgrounds that
    // happen to sit close to the status colour.
    border.width: Math.max(1, width / 12)
    border.color: Qt.rgba(statusColor.r, statusColor.g, statusColor.b, 0.35)

    Behavior on color {
        ColorAnimation { duration: Kirigami.Units.longDuration }
    }

    // Breathe while degraded so a problem is noticeable out of the corner of
    // the eye, without being as obnoxious as a hard blink.
    SequentialAnimation on opacity {
        running: dot.pulsing
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1.0;  duration: 900; easing.type: Easing.InOutQuad }
        onStopped: dot.opacity = 1.0
    }
}
