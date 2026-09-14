/*
    Copyright 2024 Benjamin Vedder benjamin@vedder.se
    Customized Realtime Black-Green-Red Dashboard for VESC Tool

    This file is part of VESC Tool.

    VESC Tool is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    VESC Tool is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import QtQuick 2.10
import QtQuick.Controls 2.10
import QtQuick.Layouts 1.3
import QtQuick.Window 2.10
import QtGraphicalEffects 1.0

import Vedder.vesc.vescinterface 1.0
import Vedder.vesc.commands 1.0
import Vedder.vesc.configparams 1.0
import Vedder.vesc.utility 1.0

Item {
    id: rtBlackGreenRedRoot
    anchors.fill: parent

    property bool isHorizontal: false
    property bool updateData: true
    property var dialogParent: null

    // View modes
    property bool isMinimalView: false
    property bool isFullscreen: false

    // Color Palette: Black, Neon Green, Vivid Red, Amber Warning
    readonly property color colBg: "#000000"
    readonly property color colCardBg: "#080e09"
    readonly property color colCardBorder: "#132817"
    readonly property color colCardBorderGlow: "#00E676"
    readonly property color colNeonGreen: "#00E676"
    readonly property color colLightGreen: "#69F0AE"
    readonly property color colDarkGreen: "#007038"
    readonly property color colVividRed: "#FF1744"
    readonly property color colDarkRed: "#800B22"
    readonly property color colWarningAmber: "#FFD600"
    readonly property color colTextWhite: "#FFFFFF"
    readonly property color colTextDim: "#7A9582"

    // Configuration overrides (-1 = auto from mcConf)
    property real customCutoffStart: -1
    property real customCutoffEnd: -1
    property int customSeriesCells: 0

    // Live Telemetry Values
    property real voltageIn: 0.0
    property real batteryPercent: 0.0
    property real batteryWh: 0.0
    property real speedNow: 0.0
    property real speedMax: 0.0
    property real erpmNow: 0.0
    property real powerNow: 0.0
    property real powerMax: 0.0
    property real powerMinRegen: 0.0
    property real currentMotor: 0.0
    property real currentIn: 0.0
    property real dutyNow: 0.0

    // Temperature Sensors
    property real tempMos: 0.0
    property real tempMos1: 0.0
    property real tempMos2: 0.0
    property real tempMos3: 0.0
    property real tempMotor: 0.0
    property real tempFetLimitStart: 85.0
    property real tempFetLimitEnd: 100.0
    property real tempMotorLimitStart: 80.0
    property real tempMotorLimitEnd: 100.0

    // Cutoff Thresholds
    property real cutoffStartVal: {
        if (customCutoffStart > 0) return customCutoffStart;
        var val = mMcConf.getParamDouble("l_battery_cut_start");
        return val > 0 ? val : 34.0;
    }
    property real cutoffEndVal: {
        if (customCutoffEnd > 0) return customCutoffEnd;
        var val = mMcConf.getParamDouble("l_battery_cut_end");
        return val > 0 ? val : 31.0;
    }

    // Cells count calculation
    property int detectedCells: {
        if (customSeriesCells > 0) return customSeriesCells;
        if (voltageIn <= 0) return 12;
        var cells = Math.round(voltageIn / 3.7);
        return Math.max(1, cells);
    }
    property real cellVoltage: detectedCells > 0 ? (voltageIn / detectedCells) : 0.0

    // Energy and Distance
    property real whKmNow: 0.0
    property real whKmAvg: 0.0
    property real totalOdometerKm: 0.0
    property real tripDistanceKm: 0.0
    property real tripDistanceOffset: 0.0
    property string uptimeString: "00:00:00"
    property string faultString: "FAULT_CODE_NONE"
    property int numControllers: 1

    // Unit conversion
    property bool useImperial: VescIf.useImperialUnits()
    property real speedUnitFact: useImperial ? 2.23694 : 3.6
    property string speedUnitText: useImperial ? "mph" : "km/h"
    property real distUnitFact: useImperial ? 0.621371 : 1.0
    property string distUnitText: useImperial ? "mi" : "km"
    property string whDistUnitText: useImperial ? "Wh/mi" : "Wh/km"

    Rectangle {
        id: mainBg
        anchors.fill: parent
        color: colBg
    }

    Item {
        id: cockpitContainer
        parent: isFullscreen && Overlay.overlay ? Overlay.overlay : rtBlackGreenRedRoot
        anchors.fill: parent
        z: isFullscreen ? 10000 : 1

        Rectangle {
            anchors.fill: parent
            color: colBg
        }

        Rectangle {
            id: topControlsBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 48
            color: "#050a06"
            border.color: "#112214"
            border.width: 1
            z: 10

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                Row {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 6

                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        anchors.verticalCenter: parent.verticalCenter
                        color: VescIf.isPortConnected() ? colNeonGreen : colVividRed

                        SequentialAnimation on opacity {
                            running: VescIf.isPortConnected()
                            loops: Animation.Infinite
                            PropertyAnimation { from: 1.0; to: 0.4; duration: 1000; easing.type: Easing.InOutQuad }
                            PropertyAnimation { from: 0.4; to: 1.0; duration: 1000; easing.type: Easing.InOutQuad }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "VESC HUD"
                        font.family: "Roboto"
                        font.bold: true
                        font.pixelSize: 15
                        color: colNeonGreen
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: faultString !== "FAULT_CODE_NONE"
                        color: colVividRed
                        radius: 3
                        height: 18
                        width: faultTextLabel.width + 10

                        Text {
                            id: faultTextLabel
                            anchors.centerIn: parent
                            text: faultString
                            font.family: "Roboto"
                            font.bold: true
                            font.pixelSize: 10
                            color: colTextWhite
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Button {
                    id: viewModeBtn
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: 80
                    padding: 0

                    contentItem: Text {
                        text: isMinimalView ? "MINIMAL" : "FULL"
                        font.family: "Roboto"
                        font.bold: true
                        font.pixelSize: 11
                        color: isMinimalView ? colWarningAmber : colNeonGreen
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        color: viewModeBtn.down ? "#1b3320" : "#0d1d11"
                        border.color: isMinimalView ? colWarningAmber : colNeonGreen
                        border.width: 1
                        radius: 4
                    }

                    onClicked: {
                        isMinimalView = !isMinimalView
                    }
                }

                Button {
                    id: fullscreenBtn
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: 80
                    padding: 0

                    contentItem: Text {
                        text: isFullscreen ? "EXIT FS" : "FULLSCREEN"
                        font.family: "Roboto"
                        font.bold: true
                        font.pixelSize: 10
                        color: isFullscreen ? colVividRed : colNeonGreen
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        color: fullscreenBtn.down ? "#1b3320" : "#0d1d11"
                        border.color: isFullscreen ? colVividRed : colNeonGreen
                        border.width: 1
                        radius: 4
                    }

                    onClicked: {
                        isFullscreen = !isFullscreen
                    }
                }

                Button {
                    id: settingsBtn
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: 36
                    padding: 0

                    contentItem: Text {
                        text: "⚙"
                        font.pixelSize: 16
                        color: colNeonGreen
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        color: settingsBtn.down ? "#1b3320" : "#0d1d11"
                        border.color: colNeonGreen
                        border.width: 1
                        radius: 4
                    }

                    onClicked: {
                        settingsPopup.open()
                    }
                }
            }
        }
        Flickable {
            id: mainFlickable
            anchors.top: topControlsBar.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            contentHeight: isMinimalView ? minimalContent.height + 20 : fullContent.height + 20
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: minimalContent
                visible: isMinimalView
                width: parent.width - 24
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                Item { height: 4 }
                // Large Minimal Speed Card
                Rectangle {
                    Layout.fillWidth: true
                    height: 180
                    color: colCardBg
                    border.color: colCardBorder
                    border.width: 1
                    radius: 8

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2

                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 4

                            Text {
                                text: speedNow.toFixed(1)
                                font.family: "Roboto"
                                font.bold: true
                                font.pixelSize: 84
                                color: colNeonGreen
                            }

                            Text {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 14
                                text: speedUnitText
                                font.family: "Roboto"
                                font.bold: true
                                font.pixelSize: 22
                                color: colTextDim
                            }
                        }

                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 16

                            Text {
                                text: "MAX: " + speedMax.toFixed(1) + " " + speedUnitText
                                font.family: "Roboto"
                                font.pixelSize: 13
                                color: colLightGreen
                            }

                            Text {
                                text: "ERPM: " + Math.round(erpmNow).toLocaleString()
                                font.family: "Roboto"
                                font.bold: true
                                font.pixelSize: 13
                                color: erpmNow >= 0 ? colNeonGreen : colVividRed
                            }
                        }
                    }
                }

                // Minimal Power Card (Green Motor, Red Regen)
                Rectangle {
                    Layout.fillWidth: true
                    height: 100
                    color: colCardBg
                    border.color: powerNow < -5 ? colVividRed : (powerNow > 10 ? colCardBorderGlow : colCardBorder)
                    border.width: 1.5
                    radius: 8

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4

                            Text {
                                text: powerNow < -5 ? "REGEN BRAKING" : "MOTOR POWER"
                                font.family: "Roboto"
                                font.bold: true
                                font.pixelSize: 12
                                color: powerNow < -5 ? colVividRed : colLightGreen
                            }

                            Row {
                                spacing: 4
                                Text {
                                    text: Math.abs(powerNow) >= 1000 ? (powerNow / 1000.0).toFixed(2) : Math.round(powerNow)
                                    font.family: "Roboto"
                                    font.bold: true
                                    font.pixelSize: 40
                                    color: powerNow < -5 ? colVividRed : colNeonGreen
                                }
                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 8
                                    text: Math.abs(powerNow) >= 1000 ? "kW" : "W"
                                    font.family: "Roboto"
                                    font.bold: true
                                    font.pixelSize: 18
                                    color: colTextDim
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4

                            Text {
                                text: "PEAK: " + Math.round(powerMax) + " W"
                                font.family: "Roboto"
                                font.pixelSize: 13
                                color: colNeonGreen
                            }

                            Text {
                                text: "REGEN: " + Math.round(powerMinRegen) + " W"
                                font.family: "Roboto"
                                font.pixelSize: 13
                                color: colVividRed
                            }

                            Text {
                                text: "CURRENT: " + currentMotor.toFixed(1) + " A"
                                font.family: "Roboto"
                                font.pixelSize: 13
                                color: colTextWhite
                            }
                        }
                    }
                }

                // Minimal Battery Voltage & Cutoff Card
                Rectangle {
                    Layout.fillWidth: true
                    height: 120
                    color: colCardBg
                    border.color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colCardBorder)
                    border.width: 1.5
                    radius: 8

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                spacing: 1
                                Text { text: "BATTERY VOLTAGE"; font.pixelSize: 10; color: colTextDim }
                                Row {
                                    spacing: 3
                                    Text {
                                        text: voltageIn.toFixed(1)
                                        font.bold: true; font.pixelSize: 32
                                        color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colNeonGreen)
                                    }
                                    Text { anchors.bottom: parent.bottom; anchors.bottomMargin: 4; text: "V"; font.pixelSize: 14; color: colTextDim }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            ColumnLayout {
                                Layout.alignment: Qt.AlignRight
                                Rectangle {
                                    Layout.alignment: Qt.AlignRight
                                    radius: 4; height: 20; width: statusText.width + 10
                                    color: voltageIn <= cutoffEndVal ? colDarkRed : (voltageIn <= cutoffStartVal ? "#594200" : colDarkGreen)
                                    border.color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colNeonGreen)
                                    Text {
                                        id: statusText; anchors.centerIn: parent
                                        text: voltageIn <= cutoffEndVal ? "CUTOFF END!" : (voltageIn <= cutoffStartVal ? "CUTOFF ACTIVE" : "OPTIMAL")
                                        font.bold: true; font.pixelSize: 9; color: colTextWhite
                                    }
                                }
                                Text {
                                    Layout.alignment: Qt.AlignRight
                                    text: Math.round(batteryPercent) + "% • " + cellVoltage.toFixed(2) + "V/c (" + detectedCells + "S)"
                                    font.pixelSize: 11; color: colLightGreen
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            height: 18
                            Rectangle { anchors.fill: parent; radius: 3; color: "#111812"; border.color: "#1c2e1f" }
                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                anchors.margins: 2; radius: 2
                                width: {
                                    var fullV = detectedCells * 4.2;
                                    var minV = cutoffEndVal - 1.0;
                                    var pct = (voltageIn - minV) / Math.max(0.1, (fullV - minV));
                                    return Math.min(parent.width - 4, Math.max(0, pct * (parent.width - 4)));
                                }
                                color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colNeonGreen)
                            }
                            Rectangle {
                                anchors.top: parent.top; anchors.bottom: parent.bottom; width: 2; color: colWarningAmber
                                x: {
                                    var fullV = detectedCells * 4.2;
                                    var minV = cutoffEndVal - 1.0;
                                    var pct = (cutoffStartVal - minV) / Math.max(0.1, (fullV - minV));
                                    return Math.min(parent.width - 2, Math.max(0, pct * parent.width));
                                }
                            }
                            Rectangle {
                                anchors.top: parent.top; anchors.bottom: parent.bottom; width: 2; color: colVividRed
                                x: {
                                    var fullV = detectedCells * 4.2;
                                    var minV = cutoffEndVal - 1.0;
                                    var pct = (cutoffEndVal - minV) / Math.max(0.1, (fullV - minV));
                                    return Math.min(parent.width - 2, Math.max(0, pct * parent.width));
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "End: " + cutoffEndVal.toFixed(1) + "V"; font.pixelSize: 9; color: colVividRed }
                            Item { Layout.fillWidth: true }
                            Text { text: "Start: " + cutoffStartVal.toFixed(1) + "V"; font.pixelSize: 9; color: colWarningAmber }
                            Item { Layout.fillWidth: true }
                            Text { text: "Full: " + (detectedCells * 4.2).toFixed(1) + "V"; font.pixelSize: 9; color: colNeonGreen }
                        }
                    }
                }

                // Minimal Temps Overview Card
                Rectangle {
                    Layout.fillWidth: true
                    height: 60
                    color: colCardBg
                    border.color: (tempMos > tempFetLimitStart || tempMotor > tempMotorLimitStart) ? colVividRed : colCardBorder
                    border.width: 1
                    radius: 8

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { text: "MOSFET"; font.pixelSize: 9; color: colTextDim }
                            Text {
                                text: tempMos.toFixed(1) + " °C"
                                font.bold: true; font.pixelSize: 15
                                color: tempMos >= tempFetLimitStart ? colVividRed : (tempMos >= 60 ? colWarningAmber : colNeonGreen)
                            }
                        }

                        Rectangle { width: 1; height: 28; color: "#1b2c1d" }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { text: "MOTOR"; font.pixelSize: 9; color: colTextDim }
                            Text {
                                text: tempMotor.toFixed(1) + " °C"
                                font.bold: true; font.pixelSize: 15
                                color: tempMotor >= tempMotorLimitStart ? colVividRed : (tempMotor >= 65 ? colWarningAmber : colNeonGreen)
                            }
                        }

                        Rectangle { width: 1; height: 28; color: "#1b2c1d" }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { text: "TRIP"; font.pixelSize: 9; color: colTextDim }
                            Text {
                                text: tripDistanceKm.toFixed(1) + " " + distUnitText
                                font.bold: true; font.pixelSize: 15; color: colTextWhite
                            }
                        }
                    }
                }

            }

            ColumnLayout {
                id: fullContent
                visible: !isMinimalView
                width: parent.width - 24
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                Item { height: 4 }
                // Full Speed & ERPM Card
                Rectangle {
                    Layout.fillWidth: true
                    height: 190
                    color: colCardBg
                    border.color: colCardBorder
                    border.width: 1
                    radius: 8

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            Row {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 4

                                Text {
                                    text: speedNow.toFixed(1)
                                    font.family: "Roboto"
                                    font.bold: true
                                    font.pixelSize: 72
                                    color: colNeonGreen
                                }

                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 12
                                    text: speedUnitText
                                    font.family: "Roboto"
                                    font.bold: true
                                    font.pixelSize: 20
                                    color: colTextDim
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "MAX SPEED: " + speedMax.toFixed(1) + " " + speedUnitText
                                font.family: "Roboto"
                                font.pixelSize: 12
                                color: colLightGreen
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            color: "#0a130c"
                            border.color: "#182c1b"
                            border.width: 1
                            radius: 4

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12

                                Row {
                                    spacing: 6
                                    Rectangle {
                                        width: 8; height: 8; radius: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: erpmNow > 10 ? colNeonGreen : (erpmNow < -10 ? colVividRed : colTextDim)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: erpmNow > 10 ? "FWD" : (erpmNow < -10 ? "REV" : "NEUTRAL")
                                        font.bold: true; font.pixelSize: 12
                                        color: erpmNow > 10 ? colNeonGreen : (erpmNow < -10 ? colVividRed : colTextDim)
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: Math.round(erpmNow).toLocaleString() + " ERPM"
                                    font.bold: true; font.pixelSize: 14
                                    color: erpmNow >= 0 ? colNeonGreen : colVividRed
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: "Duty: " + (dutyNow * 100.0).toFixed(1) + "%"
                                    font.pixelSize: 12; color: colTextDim
                                }
                            }
                        }
                    }
                }
                // Full Battery Voltage & Cutoff Detailed Card
                Rectangle {
                    Layout.fillWidth: true; height: 165
                    color: colCardBg; border.color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colCardBorder)
                    border.width: 1.5; radius: 8
                    ColumnLayout {
                        id: battCardCol
                        anchors.fill: parent; anchors.margins: 10; spacing: 5
                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                spacing: 1
                                Text { text: "BATTERY VOLTAGE & CUTOFF"; font.pixelSize: 10; font.bold: true; color: colTextDim }
                                Row {
                                    spacing: 3
                                    Text {
                                        text: voltageIn.toFixed(1); font.bold: true; font.pixelSize: 32
                                        color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colNeonGreen)
                                    }
                                    Text { anchors.bottom: parent.bottom; anchors.bottomMargin: 4; text: "V"; font.pixelSize: 14; color: colTextDim }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            ColumnLayout {
                                Layout.alignment: Qt.AlignRight
                                Rectangle {
                                    Layout.alignment: Qt.AlignRight; radius: 4; height: 20; width: fullStatusBadge.width + 10
                                    color: voltageIn <= cutoffEndVal ? colDarkRed : (voltageIn <= cutoffStartVal ? "#594200" : colDarkGreen)
                                    border.color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colNeonGreen)
                                    Text {
                                        id: fullStatusBadge; anchors.centerIn: parent
                                        text: voltageIn <= cutoffEndVal ? "CUTOFF END HIT" : (voltageIn <= cutoffStartVal ? "CUTOFF THROTTLING" : "VOLTAGE HEALTHY")
                                        font.bold: true; font.pixelSize: 9; color: colTextWhite
                                    }
                                }
                                Text {
                                    Layout.alignment: Qt.AlignRight
                                    text: Math.round(batteryPercent) + "% • " + cellVoltage.toFixed(2) + " V/c (" + detectedCells + "S)"
                                    font.bold: true; font.pixelSize: 11; color: colLightGreen
                                }
                            }
                        }
                        Item {
                            Layout.fillWidth: true; height: 22
                            Rectangle { anchors.fill: parent; radius: 4; color: "#0c150e"; border.color: "#1c3220"; border.width: 1 }
                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.margins: 2; radius: 3
                                width: {
                                    var fullV = detectedCells * 4.2; var minV = cutoffEndVal - 1.0;
                                    var pct = (voltageIn - minV) / Math.max(0.1, (fullV - minV));
                                    return Math.min(parent.width - 4, Math.max(0, pct * (parent.width - 4)));
                                }
                                color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colNeonGreen)
                            }
                            Rectangle {
                                anchors.top: parent.top; anchors.bottom: parent.bottom; width: 3; color: colVividRed
                                x: {
                                    var fullV = detectedCells * 4.2; var minV = cutoffEndVal - 1.0;
                                    var pct = (cutoffEndVal - minV) / Math.max(0.1, (fullV - minV));
                                    return Math.min(parent.width - 3, Math.max(0, pct * parent.width));
                                }
                            }
                            Rectangle {
                                anchors.top: parent.top; anchors.bottom: parent.bottom; width: 3; color: colWarningAmber
                                x: {
                                    var fullV = detectedCells * 4.2; var minV = cutoffEndVal - 1.0;
                                    var pct = (cutoffStartVal - minV) / Math.max(0.1, (fullV - minV));
                                    return Math.min(parent.width - 3, Math.max(0, pct * parent.width));
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Min: " + cutoffEndVal.toFixed(1) + " V"; font.pixelSize: 9; font.bold: true; color: colVividRed }
                            Item { Layout.fillWidth: true }
                            Text { text: "Start: " + cutoffStartVal.toFixed(1) + " V"; font.pixelSize: 9; font.bold: true; color: colWarningAmber }
                            Item { Layout.fillWidth: true }
                            Text { text: "Full: " + (detectedCells * 4.2).toFixed(1) + " V"; font.pixelSize: 9; font.bold: true; color: colNeonGreen }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Remaining: " + batteryWh.toFixed(1) + " Wh"; font.pixelSize: 9; color: colTextDim }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: customCutoffStart > 0 ? "Cutoff: Manual" : "Cutoff: Auto (mcConf)"
                                font.pixelSize: 9; color: customCutoffStart > 0 ? colWarningAmber : colLightGreen
                            }
                        }

                    }
                }

                // Full Power & Current Card
                Rectangle {
                    Layout.fillWidth: true; height: 160
                    color: colCardBg
                    border.color: powerNow < -5 ? colVividRed : (powerNow > 10 ? colCardBorderGlow : colCardBorder)
                    border.width: 1.5; radius: 8

                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                spacing: 1
                                Text {
                                    text: powerNow < -5 ? "REGENERATIVE POWER" : "MOTOR POWER"
                                    font.pixelSize: 10; font.bold: true
                                    color: powerNow < -5 ? colVividRed : colLightGreen
                                }
                                Row {
                                    spacing: 4
                                    Text {
                                        text: Math.abs(powerNow) >= 1000 ? (powerNow / 1000.0).toFixed(2) : Math.round(powerNow)
                                        font.bold: true; font.pixelSize: 32
                                        color: powerNow < -5 ? colVividRed : colNeonGreen
                                    }
                                    Text {
                                        anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                                        text: Math.abs(powerNow) >= 1000 ? "kW" : "W"
                                        font.pixelSize: 15; color: colTextDim
                                    }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            ColumnLayout {
                                Layout.alignment: Qt.AlignRight; spacing: 3
                                Text {
                                    text: "Peak: +" + Math.round(powerMax) + " W"
                                    font.pixelSize: 11; font.bold: true; color: colNeonGreen
                                }
                                Text {
                                    text: "Regen: " + Math.round(powerMinRegen) + " W"
                                    font.pixelSize: 11; font.bold: true; color: colVividRed
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#142217" }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "BATTERY CURRENT"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: currentIn.toFixed(1) + " A"
                                    font.bold: true; font.pixelSize: 15
                                    color: currentIn < -0.2 ? colVividRed : colNeonGreen
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "MOTOR CURRENT"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: currentMotor.toFixed(1) + " A"
                                    font.bold: true; font.pixelSize: 15
                                    color: currentMotor < -0.2 ? colVividRed : colNeonGreen
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "NET AH USED"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: (ampHours - ampHoursCharged).toFixed(2) + " Ah"
                                    font.bold: true; font.pixelSize: 15; color: colTextWhite
                                }
                            }
                        }
                    }
                }
                // Full Multi-Channel Temperatures Card
                Rectangle {
                    Layout.fillWidth: true; height: 130
                    color: colCardBg
                    border.color: (tempMos > tempFetLimitStart || tempMotor > tempMotorLimitStart) ? colVividRed : colCardBorder
                    border.width: 1.5; radius: 8

                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "TEMPERATURE MONITORS"; font.pixelSize: 10; font.bold: true; color: colTextDim }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "FET Limit: " + Math.round(tempFetLimitStart) + "°C | Motor Limit: " + Math.round(tempMotorLimitStart) + "°C"
                                font.pixelSize: 9; color: colTextDim
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8

                            Rectangle {
                                Layout.fillWidth: true; height: 75; color: "#0c150e"; border.color: "#182c1b"; border.width: 1; radius: 6
                                ColumnLayout {
                                    anchors.centerIn: parent; spacing: 2
                                    Text { text: "MOSFET (MAX)"; font.pixelSize: 9; color: colTextDim; Layout.alignment: Qt.AlignHCenter }
                                    Text {
                                        text: tempMos.toFixed(1) + " °C"
                                        font.bold: true; font.pixelSize: 20
                                        color: tempMos >= tempFetLimitStart ? colVividRed : (tempMos >= 65 ? colWarningAmber : colNeonGreen)
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Text {
                                        visible: tempFet1 > 0 || tempFet2 > 0
                                        text: "F1:" + Math.round(tempFet1) + " F2:" + Math.round(tempFet2) + (tempFet3 > 0 ? " F3:" + Math.round(tempFet3) : "")
                                        font.pixelSize: 9; color: colTextDim; Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true; height: 75; color: "#0c150e"; border.color: "#182c1b"; border.width: 1; radius: 6
                                ColumnLayout {
                                    anchors.centerIn: parent; spacing: 2
                                    Text { text: "MOTOR"; font.pixelSize: 9; color: colTextDim; Layout.alignment: Qt.AlignHCenter }
                                    Text {
                                        text: tempMotor.toFixed(1) + " °C"
                                        font.bold: true; font.pixelSize: 20
                                        color: tempMotor >= tempMotorLimitStart ? colVividRed : (tempMotor >= 70 ? colWarningAmber : colNeonGreen)
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                    Text {
                                        text: tempMotor >= tempMotorLimitStart ? "THROTTLING!" : "NORMAL"
                                        font.bold: true; font.pixelSize: 9
                                        color: tempMotor >= tempMotorLimitStart ? colVividRed : colLightGreen
                                        Layout.alignment: Qt.AlignHCenter
                                    }
                                }
                            }
                        }
                    }
                }


                // Full Energy, Efficiency & Distance Card
                Rectangle {
                    Layout.fillWidth: true; height: 160
                    color: colCardBg; border.color: colCardBorder; border.width: 1; radius: 8

                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "ODOMETER & EFFICIENCY"; font.pixelSize: 10; font.bold: true; color: colTextDim }
                            Item { Layout.fillWidth: true }
                            Text { text: "Uptime: " + uptimeString; font.pixelSize: 9; color: colTextDim }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "EFFICIENCY NOW"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: whKmNow > 0 ? (whKmNow * (useImperial ? 1.60934 : 1.0)).toFixed(1) + " " + whDistUnitText : "-- " + whDistUnitText
                                    font.bold: true; font.pixelSize: 15; color: colNeonGreen
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "EFFICIENCY AVG"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: whKmAvg > 0 ? (whKmAvg * (useImperial ? 1.60934 : 1.0)).toFixed(1) + " " + whDistUnitText : "-- " + whDistUnitText
                                    font.bold: true; font.pixelSize: 15; color: colLightGreen
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#142217" }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "TRIP DISTANCE"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: tripDistanceKm.toFixed(2) + " " + distUnitText
                                    font.bold: true; font.pixelSize: 15; color: colTextWhite
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "TOTAL ODOMETER"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: totalOdometerKm.toFixed(1) + " " + distUnitText
                                    font.bold: true; font.pixelSize: 15; color: colTextWhite
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "NET WH CONSUMED"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: (wattHours - wattHoursCharged).toFixed(1) + " Wh"
                                    font.bold: true; font.pixelSize: 15
                                    color: (wattHours - wattHoursCharged) >= 0 ? colLightGreen : colVividRed
                                }
                            }
                        }
                    }
                }


            }
        }
        // Floating Exit Fullscreen Button
        RoundButton {
            id: exitFsFloatingBtn
            visible: isFullscreen
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            width: 48; height: 48
            text: "✖"
            font.pixelSize: 18
            z: 999
            palette.buttonText: colVividRed
            background: Rectangle {
                radius: 24
                color: "#180505"
                border.color: colVividRed
                border.width: 1.5
            }
            onClicked: isFullscreen = false
        }

        // Settings Dialog / Popup
        Popup {
            id: settingsPopup
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 380)
            height: Math.min(parent.height - 32, 460)
            modal: true
            focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

            background: Rectangle {
                color: "#080f0a"
                border.color: colNeonGreen
                border.width: 1.5
                radius: 8
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Text {
                    text: "HUD DASHBOARD SETTINGS"
                    font.bold: true; font.pixelSize: 15
                    color: colNeonGreen
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#162b1b" }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Cutoff Start (V):"; color: colTextWhite; font.pixelSize: 12; Layout.fillWidth: true }
                    DoubleSpinBox {
                        id: spinCutoffStart
                        realValue: customCutoffStart > 0 ? customCutoffStart : cutoffStartVal
                        realFrom: 10.0; realTo: 150.0; realStepSize: 0.5; decimals: 1
                        Layout.preferredWidth: 120
                        onRealValueChanged: customCutoffStart = realValue
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Cutoff End (V):"; color: colTextWhite; font.pixelSize: 12; Layout.fillWidth: true }
                    DoubleSpinBox {
                        id: spinCutoffEnd
                        realValue: customCutoffEnd > 0 ? customCutoffEnd : cutoffEndVal
                        realFrom: 10.0; realTo: 150.0; realStepSize: 0.5; decimals: 1
                        Layout.preferredWidth: 120
                        onRealValueChanged: customCutoffEnd = realValue
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Series Cells (S):"; color: colTextWhite; font.pixelSize: 12; Layout.fillWidth: true }
                    SpinBox {
                        id: spinCells
                        from: 0; to: 36; stepSize: 1
                        value: customSeriesCells
                        Layout.preferredWidth: 120
                        onValueChanged: customSeriesCells = value
                    }
                }

                Text {
                    text: "Note: Set Series Cells to 0 to auto-detect."
                    font.pixelSize: 10; color: colTextDim
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#162b1b" }

                Button {
                    Layout.fillWidth: true
                    text: "Reset Max / Peak Stats"
                    onClicked: {
                        speedMax = 0.0
                        powerMax = 0.0
                        powerMinRegen = 0.0
                    }
                }

                Button {
                    Layout.fillWidth: true
                    text: "Reset Trip Distance"
                    onClicked: {
                        tripDistanceOffset = totalOdometerKm
                        tripDistanceKm = 0.0
                    }
                }

                Item { Layout.fillHeight: true }

                Button {
                    Layout.fillWidth: true
                    text: "CLOSE"
                    onClicked: settingsPopup.close()
                }
            }
        }


    }
    Component.onCompleted: {
        mCommands.emitEmptySetupValues()
    }

    Connections {
        id: commandsUpdate
        target: mCommands
        enabled: updateData

        function onValuesSetupReceived(values, mask) {
            voltageIn = values.v_in
            tempMos = values.temp_mos
            tempFet1 = (values.temp_fet1 !== undefined) ? values.temp_fet1 : 0.0
            tempFet2 = (values.temp_fet2 !== undefined) ? values.temp_fet2 : 0.0
            tempFet3 = (values.temp_fet3 !== undefined) ? values.temp_fet3 : 0.0
            tempMotor = values.temp_motor
            currentMotor = values.current_motor
            currentIn = values.current_in
            dutyNow = values.duty_now
            erpmNow = values.rpm
            batteryPercent = values.battery_level * 100.0
            batteryWh = values.battery_wh
            wattHours = values.watt_hours
            wattHoursCharged = values.watt_hours_charged
            ampHours = values.amp_hours
            ampHoursCharged = values.amp_hours_charged
            faultString = values.fault_str
            numControllers = values.num_vescs

            var speedKm = values.speed * 3.6
            speedNow = speedKm * (useImperial ? 0.621371 : 1.0)
            if (speedNow > speedMax) speedMax = speedNow

            powerNow = values.current_in * values.v_in
            if (powerNow > powerMax) powerMax = powerNow
            if (powerNow < powerMinRegen) powerMinRegen = powerNow

            totalOdometerKm = (values.odometer / 1000.0) * distUnitFact
            var tDist = (values.tachometer_abs / 1000.0) * distUnitFact
            tripDistanceKm = tripDistanceOffset > 0 ? Math.max(0, totalOdometerKm - tripDistanceOffset) : tDist

            var whConsume = values.watt_hours - values.watt_hours_charged
            var distAbsKm = values.tachometer_abs / 1000.0
            if (distAbsKm > 0.01) {
                whKmAvg = whConsume / distAbsKm
            }
            if (Math.abs(speedKm) > 1.0) {
                var inst = powerNow / Math.abs(speedKm)
                whKmNow = (whKmNow * 0.9) + (inst * 0.1)
            }
            if (values.uptime_ms > 0) {
                var s = Math.floor(values.uptime_ms / 1000) % 60
                var m = Math.floor(values.uptime_ms / (1000 * 60)) % 60
                var h = Math.floor(values.uptime_ms / (1000 * 60 * 60))
                uptimeString = (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
            }
        }

        function onValuesReceived(values, mask) {
            voltageIn = values.v_in
            tempMos = values.temp_mos
            tempMotor = values.temp_motor
            currentMotor = values.current_motor
            currentIn = values.current_in
            dutyNow = values.duty_now
            erpmNow = values.rpm
            wattHours = values.watt_hours
            wattHoursCharged = values.watt_hours_charged
            ampHours = values.amp_hours
            ampHoursCharged = values.amp_hours_charged
            faultString = values.fault_str

            powerNow = values.current_in * values.v_in
            if (powerNow > powerMax) powerMax = powerNow
            if (powerNow < powerMinRegen) powerMinRegen = powerNow

            var poles = mMcConf.getParamInt("si_motor_poles")
            var gearRatio = mMcConf.getParamDouble("si_gear_ratio")
            var wheelDiam = mMcConf.getParamDouble("si_wheel_diameter")
            if (poles > 0 && wheelDiam > 0) {
                var erpmToRpm = values.rpm / (poles / 2.0)
                var wheelRpm = erpmToRpm / (gearRatio > 0 ? gearRatio : 1.0)
                var speedKmh = (wheelRpm * wheelDiam * Math.PI * 60.0) / 1000.0
                speedNow = speedKmh * (useImperial ? 0.621371 : 1.0)
                if (speedNow > speedMax) speedMax = speedNow
            }

            var fullV = detectedCells * 4.2
            var emptyV = detectedCells * 3.2
            batteryPercent = Math.max(0, Math.min(100, ((voltageIn - emptyV) / Math.max(0.1, fullV - emptyV)) * 100.0))
        }
    }

}
