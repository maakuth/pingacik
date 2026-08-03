import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// Small label with tabular figures, so live-updating numbers keep a constant
// width instead of jittering as the digits change.
//
// The font sub-properties are set individually rather than assigning
// `font: Kirigami.Theme.smallFont` outright: QML rejects assigning a property
// group and one of its members on the same object.
PlasmaComponents.Label {
    font.family: Kirigami.Theme.smallFont.family
    font.pointSize: Kirigami.Theme.smallFont.pointSize
    font.features: ({ "tnum": 1 })
}
