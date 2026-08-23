import QtQuick
import "." as Ui

// Root is a plain Item, not a Column: Qt disallows top/bottom/verticalCenter/
// fill/centerIn anchors on children of a Column, and silently disables the
// WHOLE positioner if one is used — that was the bug here (the MouseArea used
// to be a Column child with anchors.top, collapsing every vital to height 0).
// The MouseArea now anchors.fill the Item, layered over a Column that holds
// only genuine flow children (header row, bar, force glyph).
Item {
    id: root
    required property var model
    width: parent ? parent.width : 240
    implicitWidth: width
    height: column.height
    implicitHeight: column.height

    // Declared before the label Row below (rather than relying on QML's
    // two-pass binding evaluation) so the containsMouse reference above it
    // reads top-to-bottom.
    MouseArea {
        id: mouseArea
        anchors.fill: root
        hoverEnabled: true
        cursorShape: root.model.explainable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.model.activate()
    }

    Column {
        id: column
        width: root.width
        spacing: 3

        // An Item, not a Row: the readout+qualifier need to be right-anchored
        // to the row's own width rather than sized via a manual
        // `width: root.width - labelText.width - readout.width` spacer, which
        // can go negative (and silently collapse/overlap) for a long label
        // plus a long readout+qualifier, e.g. opposition's "Gov. stability ⓘ".
        Item {
            id: headerRow
            width: parent.width
            height: Math.max(labelText.implicitHeight, valueRow.implicitHeight)

            Text {
                id: labelText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.model.explainable ? root.model.label + " ⓘ" : root.model.label
                color: mouseArea.containsMouse ? Ui.Theme.accent : Ui.Theme.inkDim
                font.family: Ui.Theme.fontFamily
                font.pixelSize: 13
            }

            // Right-anchored to headerRow's own width, so it can never
            // underflow regardless of label/readout length.
            Row {
                id: valueRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Text {
                    id: readout
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.model.readoutText
                    color: Ui.Theme.ink
                    font.family: Ui.Theme.fontFamily
                    // The number is the message: matches the old Widgets
                    // hierarchy (FONT_SIZE_LG = 14pt =~ 18.7px readout against
                    // a 10pt/13px label) rather than the flattened 14px this
                    // file originally shipped with.
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignRight
                }

                // Qualifier gets its own element (rather than being
                // concatenated into `readout`'s text) so it can carry its own
                // colour — model.qualifierColor was computed by
                // ui/panel_left.py (e.g. theme.CRITICAL for Attention at
                // zero remaining) but had no QML binding consuming it.
                Text {
                    id: qualifierText
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.model.qualifier.length > 0
                    text: root.model.qualifier
                    color: root.model.qualifierColor
                    font.family: Ui.Theme.fontFamily
                    font.pixelSize: 11
                }
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
    }
}
