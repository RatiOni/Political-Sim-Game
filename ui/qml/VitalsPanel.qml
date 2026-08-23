import QtQuick
import "." as Ui

Column {
    width: parent ? parent.width : 240
    spacing: 8

    Ui.VitalStat { model: approvalModel; width: parent.width }
    Ui.VitalStat { model: stabilityModel; width: parent.width }
    Ui.VitalStat { model: pcModel; width: parent.width }
    Ui.VitalStat { model: attentionModel; width: parent.width }
}
