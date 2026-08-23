import QtQuick
import "." as Ui

Column {
    id: root
    required property var model
    width: parent ? parent.width : 240
    spacing: 3

    Row {
        width: root.width
        Text {
            id: labelText
            text: root.model.explainable ? root.model.label + " ⓘ" : root.model.label
            color: mouseArea.containsMouse ? Ui.Theme.accent : Ui.Theme.inkDim
            font.family: Ui.Theme.fontFamily
            font.pixelSize: 13
        }
        Item { width: root.width - labelText.width - readout.width; height: 1 }
        Text {
            id: readout
            text: root.model.readoutText + (root.model.qualifier ? " " + root.model.qualifier : "")
            color: Ui.Theme.ink
            font.family: Ui.Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
        }
    }

    Rectangle {
        width: root.width
        height: 5
        radius: 3
        color: Ui.Theme.trackBg

        Rectangle {
            id: fill
            height: parent.height
            radius: 3
            color: root.model.fillColor
            width: parent.width * root.model.value

            Behavior on width { NumberAnimation { duration: root.model.animMs; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: root.model.animMs } }
        }
    }

    Ui.ForceGlyph { forces: root.model.forces }

    MouseArea {
        id: mouseArea
        anchors.top: parent.top
        width: root.width
        height: 20
        hoverEnabled: true
        cursorShape: root.model.explainable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.model.activate()
    }
}
