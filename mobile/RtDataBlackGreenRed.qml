/*
    Copyright 2024 Benjamin Vedder benjamin@vedder.se
    Customized Realtime Black-Green-Red Dashboard for VESC Tool

    This file is part of VESC Tool.
*/

import QtQuick 2.10
import QtQuick.Controls 2.10
import QtQuick.Layouts 1.3
import QtQuick.Window 2.10
import QtGraphicalEffects 1.0
import Qt.labs.settings 1.0 as QSettings

import Vedder.vesc.vescinterface 1.0
import Vedder.vesc.commands 1.0
import Vedder.vesc.configparams 1.0
import Vedder.vesc.utility 1.0

Item {
    id: rtBlackGreenRedRoot
    anchors.fill: parent

    property bool isHorizontal: width > height
    property bool updateData: true
    property var dialogParent: null

    // View modes
    property bool isMinimalView: false
    property bool isFullscreen: false
    signal fullscreenToggleRequested()

    // VESC interfaces
    property Commands mCommands: VescIf.commands()
    property ConfigParams mMcConf: VescIf.mcConfig()

    // Color Palette
    readonly property color colBg: "#000000"
    readonly property color colCardBg: "#070e09"
    readonly property color colCardBorder: "#122616"
    readonly property color colCardBorderGlow: "#00E676"
    readonly property color colNeonGreen: "#00E676"
    readonly property color colLightGreen: "#69F0AE"
    readonly property color colDarkGreen: "#007038"
    readonly property color colVividRed: "#FF1744"
    readonly property color colDarkRed: "#800B22"
    readonly property color colWarningAmber: "#FFD600"
    readonly property color colTextWhite: "#FFFFFF"
    readonly property color colTextDim: "#7A9582"

    // Configuration overrides (-1 = auto from mcConf, 0 = auto-detect)
    property real customCutoffStart: -1.0
    property real customCutoffEnd: -1.0
    property int customSeriesCells: 0
    property real voltageOffset: 0.0

    // ERPM Speedometer Settings
    property real erpmMax: 20000.0
    property real erpmRedPowerThreshold: 600.0
    property real erpmLowRange: 3000.0

    // Speed Smoothing & Telemetry Polling Rate Settings
    property real speedSmoothing: 0.0 // 0.0 = direct raw telemetry, 0.1-0.9 = smoothed
    property int pollInterval: 50 // ms (20ms to 500ms)

    // Live Telemetry Values
    property real voltageIn: 0.0
    property real batteryPercent: 0.0
    property real batteryWh: 0.0
    property real wattHours: 0.0
    property real wattHoursCharged: 0.0
    property real ampHours: 0.0
    property real ampHoursCharged: 0.0
    property real speedNow: 0.0
    property real speedMax: 0.0
    property real erpmNow: 0.0
    property real powerNow: 0.0
    property real powerMax: 0.0
    property real powerMinRegen: 0.0
    property real currentMotor: 0.0
    property real currentIn: 0.0
    property real dutyNow: 0.0

    // Temperature Sensors & Limits
    property real tempMos: 0.0
    property real tempMotor: 0.0
    property real tempFetLimitStart: 85.0
    property real tempFetLimitEnd: 100.0
    property real tempMotorLimitStart: 80.0
    property real tempMotorLimitEnd: 100.0

    // Energy and Distance
    property real whKmNow: 0.0
    property real whKmAvg: 0.0
    property real totalOdometerKm: 0.0
    property real tripDistanceKm: 0.0
    // Trip baselines live only for this application session. A controller
    // disconnect therefore cannot reset the trip, while a full restart does.
    property bool tripInitialized: false
    property real tripBaseOdometerKm: 0.0
    property real tripBaseTachometerKm: 0.0
    property real tripBaseWh: 0.0
    property real tripBaseWhCharged: 0.0
    property real tachometerAbsKm: 0.0
    property string uptimeString: "00:00:00"
    property string faultString: "FAULT_CODE_NONE"
    property int numControllers: 1

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

    // Detected / configured cells
    property int detectedCells: {
        if (customSeriesCells > 0) return customSeriesCells;
        var cells = Math.round(voltageIn / 3.7);
        if (cells <= 0) {
            cells = Math.round(cutoffStartVal / 3.4);
        }
        return Math.max(1, cells);
    }
    property real cellVoltage: detectedCells > 0 ? (voltageIn / detectedCells) : 0.0

    // Unit conversion
    property bool useImperial: VescIf.useImperialUnits()
    property real speedUnitFact: useImperial ? 2.23694 : 3.6
    property string speedUnitText: useImperial ? "mph" : "km/h"
    property real distUnitFact: useImperial ? 0.621371192 : 1.0
    property string distUnitText: useImperial ? "mi" : "km"
    property string whDistUnitText: useImperial ? "Wh/mi" : "Wh/km"

    // High Load at Low ERPM Condition
    readonly property bool isHighLoadAtLowRpm: (powerNow >= erpmRedPowerThreshold) && (Math.abs(erpmNow) <= erpmLowRange)

    // Persistent Settings
    QSettings.Settings {
        id: hudSettings
        category: "RtDataBlackGreenRed"
        property int seriesCells: 0
        property real cutoffStart: -1.0
        property real cutoffEnd: -1.0
        property real erpmMax: 20000.0
        property real erpmRedPowerThreshold: 600.0
        property real erpmLowRange: 3000.0
        property bool isMinimalView: false
        property real speedSmoothing: 0.0
        property int pollInterval: 50
        property real voltageOffset: 0.0
    }

    Component.onCompleted: {
        mCommands.emitEmptySetupValues();
        if (VescIf.isPortConnected()) {
            mCommands.getValuesSetup();
        }
        customSeriesCells = hudSettings.seriesCells;
        customCutoffStart = hudSettings.cutoffStart;
        customCutoffEnd = hudSettings.cutoffEnd;
        erpmMax = hudSettings.erpmMax > 0 ? hudSettings.erpmMax : 20000.0;
        erpmRedPowerThreshold = hudSettings.erpmRedPowerThreshold > 0 ? hudSettings.erpmRedPowerThreshold : 600.0;
        erpmLowRange = hudSettings.erpmLowRange > 0 ? hudSettings.erpmLowRange : 3000.0;
        isMinimalView = hudSettings.isMinimalView;
        speedSmoothing = (hudSettings.speedSmoothing !== undefined && hudSettings.speedSmoothing >= 0) ? hudSettings.speedSmoothing : 0.0;
        pollInterval = (hudSettings.pollInterval && hudSettings.pollInterval >= 20) ? hudSettings.pollInterval : 50;
        voltageOffset = (hudSettings.voltageOffset !== undefined) ? hudSettings.voltageOffset : 0.0;
    }

    function drawErpmSpeedo(canvas, ctx) {
        var w = canvas.width;
        var h = canvas.height;
        ctx.reset();
        if (w <= 30 || h <= 20) return;

        var padX = Math.max(16.0, w * 0.05);
        var x1 = padX;
        var x2 = w - padX;
        var yEnds = h - 12.0;
        var yTop = 10.0;

        var cx = w / 2.0;
        var dx = cx - x1;
        var dy = yEnds - yTop;

        var r = (dx * dx + dy * dy) / (2.0 * dy);
        var cy = yTop + r;

        var startAngle = Math.atan2(yEnds - cy, x1 - cx);
        var endAngle = Math.atan2(yEnds - cy, x2 - cx);
        var totalSweep = endAngle - startAngle;

        // 1. Background Track Arc
        ctx.lineWidth = 7.0;
        ctx.lineCap = "round";
        ctx.strokeStyle = "#102315";
        ctx.beginPath();
        ctx.arc(cx, cy, r, startAngle, endAngle, false);
        ctx.stroke();

        var absErpm = Math.abs(erpmNow);
        var safeMax = Math.max(100.0, erpmMax);

        // Subtle tick marks along the arc at 0%, 25%, 50%, 75%, 100%
        for (var i = 0; i <= 4; i++) {
            var frac = i / 4.0;
            var tAngle = startAngle + frac * totalSweep;
            var tickInnerR = r - 5.0;
            var tickOuterR = r + 5.0;
            var tx1 = cx + tickInnerR * Math.cos(tAngle);
            var ty1 = cy + tickInnerR * Math.sin(tAngle);
            var tx2 = cx + tickOuterR * Math.cos(tAngle);
            var ty2 = cy + tickOuterR * Math.sin(tAngle);
            ctx.lineWidth = 1.5;
            ctx.strokeStyle = (i === 0 || i === 4) ? "#2a5433" : "#1a3822";
            ctx.beginPath();
            ctx.moveTo(tx1, ty1);
            ctx.lineTo(tx2, ty2);
            ctx.stroke();
        }

        ctx.font = "bold 9px Roboto";
        ctx.fillStyle = "#34663e";
        ctx.textAlign = "center";
        ctx.fillText("0", x1, yEnds + 10);
        var maxK = (safeMax >= 1000) ? Math.round(safeMax / 1000) + "k" : safeMax;
        ctx.fillText(maxK, x2, yEnds + 10);

        // 2. Active ERPM Progress
        var ratio = Math.max(0.0, Math.min(1.0, absErpm / safeMax));

        if (ratio > 0.002) {
            var curAngle = startAngle + ratio * totalSweep;

            var grad = ctx.createLinearGradient(x1, 0, x2, 0);
            if (isHighLoadAtLowRpm) {
                grad.addColorStop(0.0, colVividRed);
                grad.addColorStop(0.20, "#FF5252");
                grad.addColorStop(0.38, colNeonGreen);
                grad.addColorStop(0.75, colNeonGreen);
                grad.addColorStop(0.90, colWarningAmber);
                grad.addColorStop(1.0, colVividRed);
            } else {
                grad.addColorStop(0.0, colNeonGreen);
                grad.addColorStop(0.70, colNeonGreen);
                grad.addColorStop(0.88, colWarningAmber);
                grad.addColorStop(1.0, colVividRed);
            }

            ctx.lineWidth = 7.0;
            ctx.lineCap = "round";
            ctx.strokeStyle = grad;
            ctx.beginPath();
            ctx.arc(cx, cy, r, startAngle, curAngle, false);
            ctx.stroke();

            // 3. Pointer Glow Dot at Current Value
            var curX = cx + r * Math.cos(curAngle);
            var curY = cy + r * Math.sin(curAngle);

            ctx.fillStyle = isHighLoadAtLowRpm ? "rgba(255, 23, 68, 0.4)" : "rgba(0, 230, 118, 0.4)";
            ctx.beginPath();
            ctx.arc(curX, curY, 7.0, 0, 2.0 * Math.PI, false);
            ctx.fill();

            ctx.fillStyle = isHighLoadAtLowRpm ? colVividRed : "#FFFFFF";
            ctx.beginPath();
            ctx.arc(curX, curY, 3.5, 0, 2.0 * Math.PI, false);
            ctx.fill();
        }
    }

    Rectangle {
        id: mainBg
        color: colBg
        x: -20
        y: -20
        width: parent.width + 40
        height: parent.height + 40
    }

    Item {
        id: cockpitContainer
        anchors.fill: parent

        Rectangle {
            color: colBg
            x: -20
            y: -20
            width: parent.width + 40
            height: parent.height + 40
        }

        // Top Controls Header Bar
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
                    Layout.preferredWidth: 76
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
                        isMinimalView = !isMinimalView;
                        hudSettings.isMinimalView = isMinimalView;
                    }
                }

                Button {
                    id: fullscreenBtn
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: 84
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
                        fullscreenToggleRequested();
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
                        settingsPopup.open();
                    }
                }
            }
        }

        // Main Scrollable Area
        Flickable {
            id: mainFlickable
            anchors.top: topControlsBar.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            contentWidth: width
            contentHeight: isHorizontal ? (horizontalContent.height + 24) : (isMinimalView ? (minimalContent.height + 24) : (fullContent.height + 24))
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            // ==================== HORIZONTAL (LANDSCAPE) VIEW ====================
            RowLayout {
                id: horizontalContent
                visible: isHorizontal
                width: parent.width - 24
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                // Left Column: Speed + Speedometer ERPM + Quick Controls
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: 10

                    Item { height: 2 }

                    // Speed Card with Speedometer ERPM
                    Rectangle {
                        Layout.fillWidth: true
                        height: 245
                        color: colCardBg
                        border.color: colCardBorder
                        border.width: 1
                        radius: 8

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            // Speed Digits & Unit
                            Row {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 4

                                Text {
                                    text: speedNow.toFixed(1)
                                    font.family: "Roboto"
                                    font.bold: true
                                    font.pixelSize: 68
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

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var newImp = !useImperial;
                                            VescIf.setUseImperialUnits(newImp);
                                            VescIf.storeSettings();
                                            useImperial = newImp;
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "MAX SPEED: " + speedMax.toFixed(1) + " " + speedUnitText
                                font.family: "Roboto"
                                font.pixelSize: 11
                                color: colLightGreen
                            }

                            // Curved Speedometer ERPM Gauge
                            Item {
                                Layout.fillWidth: true
                                height: 58

                                Canvas {
                                    id: erpmSpeedoCanvasH
                                    anchors.fill: parent
                                    antialiasing: true
                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()

                                    Connections {
                                        target: rtBlackGreenRedRoot
                                        onErpmNowChanged: erpmSpeedoCanvasH.requestPaint()
                                        onPowerNowChanged: erpmSpeedoCanvasH.requestPaint()
                                        onErpmMaxChanged: erpmSpeedoCanvasH.requestPaint()
                                        onErpmRedPowerThresholdChanged: erpmSpeedoCanvasH.requestPaint()
                                    }

                                    onPaint: drawErpmSpeedo(this, getContext("2d"))
                                    Component.onCompleted: requestPaint()
                                }
                            }

                            // ERPM Data & Load Status Row
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 8
                                Layout.rightMargin: 8

                                Row {
                                    spacing: 4
                                    Rectangle {
                                        width: 10; height: 10; radius: 5
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: erpmNow > 10 ? colNeonGreen : (erpmNow < -10 ? colVividRed : colTextDim)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: erpmNow > 10 ? "FWD" : (erpmNow < -10 ? "REV" : "NEUT")
                                        font.bold: true; font.pixelSize: 12
                                        color: erpmNow > 10 ? colNeonGreen : (erpmNow < -10 ? colVividRed : colTextDim)
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Row {
                                    spacing: 4
                                    Layout.alignment: Qt.AlignHCenter
                                    Text {
                                        text: Math.round(Math.abs(erpmNow)).toLocaleString()
                                        font.bold: true
                                        font.pixelSize: 22
                                        font.family: "Roboto"
                                        color: isHighLoadAtLowRpm ? colVividRed : colNeonGreen
                                    }
                                    Text {
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 3
                                        text: " / " + Math.round(erpmMax).toLocaleString() + " ERPM"
                                        font.bold: true
                                        font.pixelSize: 13
                                        font.family: "Roboto"
                                        color: colTextDim
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: "Duty: " + (dutyNow * 100.0).toFixed(1) + "%"
                                    font.pixelSize: 12; font.bold: true; color: colTextDim
                                }
                            }

                            // High Motor Load Alert Banner
                            Rectangle {
                                Layout.fillWidth: true
                                height: 20
                                visible: isHighLoadAtLowRpm
                                color: "#2b0a0a"
                                border.color: colVividRed
                                border.width: 1
                                radius: 3

                                Text {
                                    anchors.centerIn: parent
                                    text: "⚠️ HIGH MOTOR LOAD AT LOW RPM (" + Math.round(powerNow) + " W)"
                                    font.bold: true; font.pixelSize: 10
                                    color: colVividRed
                                }
                            }
                        }
                    }

                    // Quick Action Buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Button {
                            Layout.fillWidth: true
                            text: "Reset Peaks"
                            onClicked: {
                                speedMax = 0.0;
                                powerMax = 0.0;
                                powerMinRegen = 0.0;
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            text: "Reset Trip"
                            onClicked: {
                                tripDistanceKm = 0.0;
                                tripInitialized = true;
                                tripBaseOdometerKm = totalOdometerKm / distUnitFact;
                                tripBaseTachometerKm = tachometerAbsKm / distUnitFact;
                                tripBaseWh = wattHours;
                                tripBaseWhCharged = wattHoursCharged;
                            }
                        }
                    }
                }

                // Right Column: Battery + Power + Temps + Distance
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: 10

                    Item { height: 2 }

                    // Battery Voltage & Cutoff Card
                    Rectangle {
                        Layout.fillWidth: true
                        height: 125
                        color: colCardBg
                        border.color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colCardBorder)
                        border.width: 1.5
                        radius: 8

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 5

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 1
                                    Text {
                                        text: Math.abs(voltageOffset) > 0.001 ?
                                              ("BATTERY VOLTAGE (" + (voltageOffset > 0 ? "+" : "") + voltageOffset.toFixed(2) + "V)") :
                                              "BATTERY VOLTAGE"
                                        font.pixelSize: 10; font.bold: true; color: colTextDim
                                    }
                                    Row {
                                        spacing: 4
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
                                        radius: 4; height: 20; width: hStatusBadge.width + 10
                                        color: voltageIn <= cutoffEndVal ? colDarkRed : (voltageIn <= cutoffStartVal ? "#594200" : colDarkGreen)
                                        border.color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colNeonGreen)
                                        Text {
                                            id: hStatusBadge; anchors.centerIn: parent
                                            text: voltageIn <= cutoffEndVal ? "CUTOFF END" : (voltageIn <= cutoffStartVal ? "CUTOFF ACTIVE" : "OPTIMAL")
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

                            // Cutoff Range Visual Bar
                            Item {
                                Layout.fillWidth: true
                                height: 16
                                Rectangle { anchors.fill: parent; radius: 3; color: "#0c150e"; border.color: "#1c3220"; border.width: 1 }
                                Rectangle {
                                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                    anchors.margins: 2; radius: 2
                                    width: {
                                        var fullV = detectedCells * 4.2;
                                        var minV = cutoffEndVal - 1.0;
                                        var pct = (voltageIn - minV) / Math.max(0.1, (fullV - minV));
                                        return Math.max(0, Math.min(parent.width - 4, (parent.width - 4) * pct));
                                    }
                                    color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colNeonGreen)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Cut End: " + cutoffEndVal.toFixed(1) + " V"; font.pixelSize: 9; color: colVividRed }
                                Item { Layout.fillWidth: true }
                                Text { text: "Cut Start: " + cutoffStartVal.toFixed(1) + " V"; font.pixelSize: 9; color: colWarningAmber }
                                Item { Layout.fillWidth: true }
                                Text { text: "Full: " + (detectedCells * 4.2).toFixed(1) + " V"; font.pixelSize: 9; color: colNeonGreen }
                            }
                        }
                    }

                    // Motor Power & Current Card
                    Rectangle {
                        Layout.fillWidth: true
                        height: 110
                        color: colCardBg
                        border.color: colCardBorder
                        border.width: 1
                        radius: 8

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

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
                                            font.bold: true; font.pixelSize: 30
                                            color: powerNow < -5 ? colVividRed : colNeonGreen
                                        }
                                        Text {
                                            anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                                            text: Math.abs(powerNow) >= 1000 ? "kW" : "W"
                                            font.pixelSize: 14; color: colTextDim
                                        }
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                ColumnLayout {
                                    Layout.alignment: Qt.AlignRight
                                    spacing: 2
                                    Text { text: "Peak: +" + Math.round(powerMax) + " W"; font.pixelSize: 11; font.bold: true; color: colNeonGreen }
                                    Text { text: "Regen: " + Math.round(powerMinRegen) + " W"; font.pixelSize: 11; font.bold: true; color: colVividRed }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: "#142217" }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 1
                                    Text { text: "BATTERY CURRENT"; font.pixelSize: 9; color: colTextDim }
                                    Text { text: currentIn.toFixed(1) + " A"; font.bold: true; font.pixelSize: 14; color: currentIn < -0.2 ? colVividRed : colNeonGreen }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 1
                                    Text { text: "MOTOR CURRENT"; font.pixelSize: 9; color: colTextDim }
                                    Text { text: currentMotor.toFixed(1) + " A"; font.bold: true; font.pixelSize: 14; color: currentMotor < -0.2 ? colVividRed : colNeonGreen }
                                }
                            }
                        }
                    }

                    // Temperatures & Distance Card
                    Rectangle {
                        Layout.fillWidth: true
                        height: 105
                        color: colCardBg
                        border.color: colCardBorder
                        border.width: 1
                        radius: 8

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Text { text: "ESC TEMP"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: tempMos.toFixed(1) + " °C"
                                    font.bold: true; font.pixelSize: 16
                                    color: tempMos >= tempFetLimitStart ? colVividRed : (tempMos >= 65 ? colWarningAmber : colNeonGreen)
                                }
                                Text { text: "Lim: " + Math.round(tempFetLimitStart) + "°"; font.pixelSize: 9; color: colTextDim }
                            }

                            Rectangle { width: 1; Layout.fillHeight: true; color: "#162b1b" }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Text { text: "MOTOR TEMP"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: tempMotor.toFixed(1) + " °C"
                                    font.bold: true; font.pixelSize: 16
                                    color: tempMotor >= tempMotorLimitStart ? colVividRed : (tempMotor >= 65 ? colWarningAmber : colNeonGreen)
                                }
                                Text { text: "Lim: " + Math.round(tempMotorLimitStart) + "°"; font.pixelSize: 9; color: colTextDim }
                            }

                            Rectangle { width: 1; Layout.fillHeight: true; color: "#162b1b" }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Text { text: "TRIP DIST"; font.pixelSize: 9; color: colTextDim }
                                Text { text: tripDistanceKm.toFixed(1) + " " + distUnitText; font.bold: true; font.pixelSize: 16; color: colTextWhite }
                                Text { text: "Odo: " + totalOdometerKm.toFixed(1); font.pixelSize: 9; color: colTextDim }
                            }

                            Rectangle { width: 1; Layout.fillHeight: true; color: "#162b1b" }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Text { text: "EFFICIENCY AVG"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: whKmAvg > 0 ? (whKmAvg * (useImperial ? 1.60934 : 1.0)).toFixed(1) + " " + whDistUnitText : "-- " + whDistUnitText
                                    font.bold: true; font.pixelSize: 14; color: colLightGreen
                                }
                                Text { text: "Trip average"; font.pixelSize: 9; color: colTextDim }
                            }
                        }
                    }
                }
            }

            // ==================== VERTICAL (PORTRAIT) VIEW: MINIMAL ====================
            ColumnLayout {
                id: minimalContent
                visible: !isHorizontal && isMinimalView
                width: parent.width - 24
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                Item { height: 4 }

                // Large Minimal Speed Card with Speedometer ERPM
                Rectangle {
                    Layout.fillWidth: true
                    height: 245
                    color: colCardBg
                    border.color: colCardBorder
                    border.width: 1
                    radius: 8

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 4

                            Text {
                                text: speedNow.toFixed(1)
                                font.family: "Roboto"
                                font.bold: true
                                font.pixelSize: 76
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

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "MAX SPEED: " + speedMax.toFixed(1) + " " + speedUnitText
                            font.family: "Roboto"
                            font.pixelSize: 11
                            color: colLightGreen
                        }

                        // Curved Speedometer ERPM Gauge
                        Item {
                            Layout.fillWidth: true
                            height: 58

                            Canvas {
                                id: erpmSpeedoCanvasMin
                                anchors.fill: parent
                                antialiasing: true
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()

                                Connections {
                                    target: rtBlackGreenRedRoot
                                    onErpmNowChanged: erpmSpeedoCanvasMin.requestPaint()
                                    onPowerNowChanged: erpmSpeedoCanvasMin.requestPaint()
                                    onErpmMaxChanged: erpmSpeedoCanvasMin.requestPaint()
                                    onErpmRedPowerThresholdChanged: erpmSpeedoCanvasMin.requestPaint()
                                }

                                onPaint: drawErpmSpeedo(this, getContext("2d"))
                                Component.onCompleted: requestPaint()
                            }
                        }

                        // ERPM Status Row
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8

                            Row {
                                spacing: 4
                                Rectangle {
                                    width: 10; height: 10; radius: 5
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: erpmNow > 10 ? colNeonGreen : (erpmNow < -10 ? colVividRed : colTextDim)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: erpmNow > 10 ? "FWD" : (erpmNow < -10 ? "REV" : "NEUT")
                                    font.bold: true; font.pixelSize: 12
                                    color: erpmNow > 10 ? colNeonGreen : (erpmNow < -10 ? colVividRed : colTextDim)
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Row {
                                spacing: 4
                                Layout.alignment: Qt.AlignHCenter
                                Text {
                                    text: Math.round(Math.abs(erpmNow)).toLocaleString()
                                    font.bold: true
                                    font.pixelSize: 22
                                    font.family: "Roboto"
                                    color: isHighLoadAtLowRpm ? colVividRed : colNeonGreen
                                }
                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 3
                                    text: " / " + Math.round(erpmMax).toLocaleString() + " ERPM"
                                    font.bold: true
                                    font.pixelSize: 13
                                    font.family: "Roboto"
                                    color: colTextDim
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: "Duty: " + (dutyNow * 100.0).toFixed(1) + "%"
                                font.pixelSize: 12; font.bold: true; color: colTextDim
                            }
                        }

                        // High Load Alert
                        Rectangle {
                            Layout.fillWidth: true
                            height: 20
                            visible: isHighLoadAtLowRpm
                            color: "#2b0a0a"
                            border.color: colVividRed
                            border.width: 1
                            radius: 3

                            Text {
                                anchors.centerIn: parent
                                text: "⚠️ HIGH MOTOR LOAD AT LOW RPM (" + Math.round(powerNow) + " W)"
                                font.bold: true; font.pixelSize: 10
                                color: colVividRed
                            }
                        }
                    }
                }

                // Minimal Power Card
                Rectangle {
                    Layout.fillWidth: true
                    height: 90
                    color: colCardBg
                    border.color: colCardBorder
                    border.width: 1
                    radius: 8

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12

                        ColumnLayout {
                            spacing: 1
                            Text {
                                text: powerNow < -5 ? "REGEN" : "POWER"
                                font.pixelSize: 10; font.bold: true
                                color: powerNow < -5 ? colVividRed : colLightGreen
                            }
                            Row {
                                spacing: 4
                                Text {
                                    text: Math.abs(powerNow) >= 1000 ? (powerNow / 1000.0).toFixed(2) : Math.round(powerNow)
                                    font.bold: true; font.pixelSize: 34
                                    color: powerNow < -5 ? colVividRed : colNeonGreen
                                }
                                Text {
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                                    text: Math.abs(powerNow) >= 1000 ? "kW" : "W"
                                    font.pixelSize: 16; color: colTextDim
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 3
                            Text { text: "PEAK: " + Math.round(powerMax) + " W"; font.pixelSize: 12; color: colNeonGreen }
                            Text { text: "REGEN: " + Math.round(powerMinRegen) + " W"; font.pixelSize: 12; color: colVividRed }
                            Text { text: "CURRENT: " + currentMotor.toFixed(1) + " A"; font.pixelSize: 12; color: colTextWhite }
                        }
                    }
                }

                // Minimal Battery Card
                Rectangle {
                    Layout.fillWidth: true
                    height: 110
                    color: colCardBg
                    border.color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colCardBorder)
                    border.width: 1.5
                    radius: 8

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                spacing: 1
                                Text {
                                    text: Math.abs(voltageOffset) > 0.001 ?
                                          ("BATTERY (" + (voltageOffset > 0 ? "+" : "") + voltageOffset.toFixed(2) + "V)") :
                                          "BATTERY VOLTAGE"
                                    font.pixelSize: 10; color: colTextDim
                                }
                                Row {
                                    spacing: 3
                                    Text {
                                        text: voltageIn.toFixed(1)
                                        font.bold: true; font.pixelSize: 30
                                        color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colNeonGreen)
                                    }
                                    Text { anchors.bottom: parent.bottom; anchors.bottomMargin: 4; text: "V"; font.pixelSize: 14; color: colTextDim }
                                }
                            }
                            Item { Layout.fillWidth: true }
                            ColumnLayout {
                                Layout.alignment: Qt.AlignRight
                                Text {
                                    Layout.alignment: Qt.AlignRight
                                    text: Math.round(batteryPercent) + "% • " + cellVoltage.toFixed(2) + " V/c (" + detectedCells + "S)"
                                    font.bold: true; font.pixelSize: 12; color: colLightGreen
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            height: 16
                            Rectangle { anchors.fill: parent; radius: 3; color: "#111812"; border.color: "#1c2e1f" }
                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                anchors.margins: 2; radius: 2
                                width: {
                                    var fullV = detectedCells * 4.2;
                                    var minV = cutoffEndVal - 1.0;
                                    var pct = (voltageIn - minV) / Math.max(0.1, (fullV - minV));
                                    return Math.max(0, Math.min(parent.width - 4, (parent.width - 4) * pct));
                                }
                                color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colNeonGreen)
                            }
                        }
                    }
                }

                // Minimal Stats Row
                Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    color: colCardBg
                    border.color: colCardBorder
                    border.width: 1
                    radius: 8

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8

                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 1
                            Text { text: "ESC"; font.pixelSize: 9; color: colTextDim }
                            Text { text: tempMos.toFixed(1) + " °C"; font.bold: true; font.pixelSize: 15; color: tempMos >= tempFetLimitStart ? colVividRed : colNeonGreen }
                        }
                        Rectangle { width: 1; height: 26; color: "#1b2c1d" }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 1
                            Text { text: "MOTOR"; font.pixelSize: 9; color: colTextDim }
                            Text { text: tempMotor.toFixed(1) + " °C"; font.bold: true; font.pixelSize: 15; color: tempMotor >= tempMotorLimitStart ? colVividRed : colNeonGreen }
                        }
                        Rectangle { width: 1; height: 26; color: "#1b2c1d" }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 1
                            Text { text: "TRIP"; font.pixelSize: 9; color: colTextDim }
                            Text { text: tripDistanceKm.toFixed(1) + " " + distUnitText; font.bold: true; font.pixelSize: 15; color: colTextWhite }
                        }
                    }
                }
            }

            // ==================== VERTICAL (PORTRAIT) VIEW: FULL ====================
            ColumnLayout {
                id: fullContent
                visible: !isHorizontal && !isMinimalView
                width: parent.width - 24
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                Item { height: 4 }

                // Full Speed & Speedometer ERPM Card
                Rectangle {
                    Layout.fillWidth: true
                    height: 250
                    color: colCardBg
                    border.color: colCardBorder
                    border.width: 1
                    radius: 8

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 4

                            Text {
                                text: speedNow.toFixed(1)
                                font.family: "Roboto"
                                font.bold: true
                                font.pixelSize: 76
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

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var newImp = !useImperial;
                                        VescIf.setUseImperialUnits(newImp);
                                        VescIf.storeSettings();
                                        useImperial = newImp;
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "MAX SPEED: " + speedMax.toFixed(1) + " " + speedUnitText
                            font.family: "Roboto"
                            font.pixelSize: 11
                            color: colLightGreen
                        }

                        // Curved Speedometer ERPM Gauge
                        Item {
                            Layout.fillWidth: true
                            height: 58

                            Canvas {
                                id: erpmSpeedoCanvasFull
                                anchors.fill: parent
                                antialiasing: true
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()

                                Connections {
                                    target: rtBlackGreenRedRoot
                                    onErpmNowChanged: erpmSpeedoCanvasFull.requestPaint()
                                    onPowerNowChanged: erpmSpeedoCanvasFull.requestPaint()
                                    onErpmMaxChanged: erpmSpeedoCanvasFull.requestPaint()
                                    onErpmRedPowerThresholdChanged: erpmSpeedoCanvasFull.requestPaint()
                                }

                                onPaint: drawErpmSpeedo(this, getContext("2d"))
                                Component.onCompleted: requestPaint()
                            }
                        }

                        // ERPM Status Row
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8

                            Row {
                                spacing: 4
                                Rectangle {
                                    width: 10; height: 10; radius: 5
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: erpmNow > 10 ? colNeonGreen : (erpmNow < -10 ? colVividRed : colTextDim)
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: erpmNow > 10 ? "FWD" : (erpmNow < -10 ? "REV" : "NEUT")
                                    font.bold: true; font.pixelSize: 12
                                    color: erpmNow > 10 ? colNeonGreen : (erpmNow < -10 ? colVividRed : colTextDim)
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Row {
                                spacing: 4
                                Layout.alignment: Qt.AlignHCenter
                                Text {
                                    text: Math.round(Math.abs(erpmNow)).toLocaleString()
                                    font.bold: true
                                    font.pixelSize: 22
                                    font.family: "Roboto"
                                    color: isHighLoadAtLowRpm ? colVividRed : colNeonGreen
                                }
                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 3
                                    text: " / " + Math.round(erpmMax).toLocaleString() + " ERPM"
                                    font.bold: true
                                    font.pixelSize: 13
                                    font.family: "Roboto"
                                    color: colTextDim
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: "Duty: " + (dutyNow * 100.0).toFixed(1) + "%"
                                font.pixelSize: 12; font.bold: true; color: colTextDim
                            }
                        }

                        // High Load Alert Banner
                        Rectangle {
                            Layout.fillWidth: true
                            height: 20
                            visible: isHighLoadAtLowRpm
                            color: "#2b0a0a"
                            border.color: colVividRed
                            border.width: 1
                            radius: 3

                            Text {
                                anchors.centerIn: parent
                                text: "⚠️ HIGH MOTOR LOAD AT LOW RPM (" + Math.round(powerNow) + " W)"
                                font.bold: true; font.pixelSize: 10
                                color: colVividRed
                            }
                        }
                    }
                }

                // Battery Voltage & Cutoff Detailed Card
                Rectangle {
                    Layout.fillWidth: true
                    height: 155
                    color: colCardBg
                    border.color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colCardBorder)
                    border.width: 1.5
                    radius: 8

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                spacing: 1
                                Text {
                                    text: Math.abs(voltageOffset) > 0.001 ?
                                          ("BATTERY VOLTAGE (" + (voltageOffset > 0 ? "+" : "") + voltageOffset.toFixed(2) + "V)") :
                                          "BATTERY VOLTAGE & CUTOFF"
                                    font.pixelSize: 10; font.bold: true; color: colTextDim
                                }
                                Row {
                                    spacing: 4
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
                                    radius: 4; height: 20; width: fullStatusBadge.width + 10
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
                            Layout.fillWidth: true
                            height: 20
                            Rectangle { anchors.fill: parent; radius: 4; color: "#0c150e"; border.color: "#1c3220"; border.width: 1 }
                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                anchors.margins: 2; radius: 3
                                width: {
                                    var fullV = detectedCells * 4.2;
                                    var minV = cutoffEndVal - 1.0;
                                    var pct = (voltageIn - minV) / Math.max(0.1, (fullV - minV));
                                    return Math.max(0, Math.min(parent.width - 4, (parent.width - 4) * pct));
                                }
                                color: voltageIn <= cutoffEndVal ? colVividRed : (voltageIn <= cutoffStartVal ? colWarningAmber : colNeonGreen)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Cut End: " + cutoffEndVal.toFixed(1) + " V"; font.pixelSize: 10; color: colVividRed }
                            Item { Layout.fillWidth: true }
                            Text { text: "Cut Start: " + cutoffStartVal.toFixed(1) + " V"; font.pixelSize: 10; color: colWarningAmber }
                            Item { Layout.fillWidth: true }
                            Text { text: "Full: " + (detectedCells * 4.2).toFixed(1) + " V"; font.pixelSize: 10; color: colNeonGreen }
                        }
                    }
                }

                // Motor Power & Current Detailed Card
                Rectangle {
                    Layout.fillWidth: true
                    height: 140
                    color: colCardBg
                    border.color: colCardBorder
                    border.width: 1
                    radius: 8

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

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
                                Layout.alignment: Qt.AlignRight
                                spacing: 3
                                Text { text: "Peak: +" + Math.round(powerMax) + " W"; font.pixelSize: 11; font.bold: true; color: colNeonGreen }
                                Text { text: "Regen: " + Math.round(powerMinRegen) + " W"; font.pixelSize: 11; font.bold: true; color: colVividRed }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#142217" }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "BATTERY CURRENT"; font.pixelSize: 9; color: colTextDim }
                                Text { text: currentIn.toFixed(1) + " A"; font.bold: true; font.pixelSize: 15; color: currentIn < -0.2 ? colVividRed : colNeonGreen }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "MOTOR CURRENT"; font.pixelSize: 9; color: colTextDim }
                                Text { text: currentMotor.toFixed(1) + " A"; font.bold: true; font.pixelSize: 15; color: currentMotor < -0.2 ? colVividRed : colNeonGreen }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "TOTAL ENERGY"; font.pixelSize: 9; color: colTextDim }
                                Text { text: Math.round(wattHours) + " Wh"; font.bold: true; font.pixelSize: 15; color: colLightGreen }
                            }
                        }
                    }
                }

                // Temperatures Card
                Rectangle {
                    Layout.fillWidth: true
                    height: 125
                    color: colCardBg
                    border.color: colCardBorder
                    border.width: 1
                    radius: 8

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "TEMPERATURES & THERMAL LIMITS"; font.pixelSize: 10; font.bold: true; color: colTextDim }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Text { text: "ESC MOS"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: tempMos.toFixed(1) + " °C"
                                    font.bold: true; font.pixelSize: 20
                                    color: tempMos >= tempFetLimitStart ? colVividRed : (tempMos >= 65 ? colWarningAmber : colNeonGreen)
                                }
                                Text { text: "Limit: " + Math.round(tempFetLimitStart) + " - " + Math.round(tempFetLimitEnd) + " °C"; font.pixelSize: 9; color: colTextDim }
                            }

                            Rectangle { width: 1; Layout.fillHeight: true; color: "#162b1b" }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Text { text: "MOTOR"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: tempMotor.toFixed(1) + " °C"
                                    font.bold: true; font.pixelSize: 20
                                    color: tempMotor >= tempMotorLimitStart ? colVividRed : (tempMotor >= 65 ? colWarningAmber : colNeonGreen)
                                }
                                Text { text: "Limit: " + Math.round(tempMotorLimitStart) + " - " + Math.round(tempMotorLimitEnd) + " °C"; font.pixelSize: 9; color: colTextDim }
                            }
                        }
                    }
                }

                // Odometer & Trip Distance Card
                Rectangle {
                    Layout.fillWidth: true
                    height: 135
                    color: colCardBg
                    border.color: colCardBorder
                    border.width: 1
                    radius: 8

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "ODOMETER & EFFICIENCY"; font.pixelSize: 10; font.bold: true; color: colTextDim }
                            Item { Layout.fillWidth: true }
                            Text { text: "Uptime: " + uptimeString; font.pixelSize: 9; color: colTextDim }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "TRIP DISTANCE"; font.pixelSize: 9; color: colTextDim }
                                Text { text: tripDistanceKm.toFixed(2) + " " + distUnitText; font.bold: true; font.pixelSize: 18; color: colTextWhite }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "TOTAL ODOMETER"; font.pixelSize: 9; color: colTextDim }
                                Text { text: totalOdometerKm.toFixed(1) + " " + distUnitText; font.bold: true; font.pixelSize: 18; color: colTextWhite }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "EFFICIENCY AVG"; font.pixelSize: 9; color: colTextDim }
                                Text {
                                    text: whKmAvg > 0 ? (whKmAvg * (useImperial ? 1.60934 : 1.0)).toFixed(1) + " " + whDistUnitText : "-- " + whDistUnitText
                                    font.bold: true; font.pixelSize: 16; color: colLightGreen
                                }
                            }
                        }
                    }
                }

            }
        }

        // ==================== HUD SETTINGS DIALOG (RESPONSIVE AUTO-SCALING) ====================
        Popup {
            id: settingsPopup
            anchors.centerIn: parent
            width: Math.min(parent.width - 24, isHorizontal ? 660 : 440)
            height: Math.min(parent.height - 24, isHorizontal ? (parent.height - 16) : 680)
            modal: true
            focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

            background: Rectangle {
                color: "#08100a"
                border.color: colNeonGreen
                border.width: 1.5
                radius: 10
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Dialog Header
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "HUD SETTINGS & ODOMETER"
                        font.family: "Roboto"
                        font.bold: true
                        font.pixelSize: 15
                        color: colNeonGreen
                        Layout.fillWidth: true
                    }

                    Button {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        text: "✕"
                        font.pixelSize: 14
                        onClicked: settingsPopup.close()
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#162b1b" }

                // Scrollable Settings Content
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: parent.width

                    ColumnLayout {
                        width: settingsPopup.width - 40
                        spacing: 12

                        // --- SECTION 1: UNITS ---
                        GroupBox {
                            title: "Units / Единицы измерения"
                            Layout.fillWidth: true

                            RowLayout {
                                anchors.fill: parent
                                Text {
                                    text: "Speed & Distance:"
                                    color: colTextWhite
                                    font.pixelSize: 12
                                    Layout.fillWidth: true
                                }
                                Button {
                                    text: useImperial ? "Imperial (mph, mi)" : "Metric (km/h, km)"
                                    onClicked: {
                                        var newImp = !useImperial;
                                        VescIf.setUseImperialUnits(newImp);
                                        VescIf.storeSettings();
                                        useImperial = newImp;
                                    }
                                }
                            }
                        }

                        // --- SECTION 2: ODOMETER ADJUSTMENT ---
                        GroupBox {
                            title: "Update Odometer / Пробег одометра"
                            Layout.fillWidth: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    DoubleSpinBox {
                                        id: spinOdoInput
                                        realFrom: 0.0
                                        realTo: 9999999.0
                                        decimals: 1
                                        realStepSize: 1.0
                                        realValue: totalOdometerKm
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        text: distUnitText
                                        color: colNeonGreen
                                        font.bold: true
                                        font.pixelSize: 13
                                    }

                                    Button {
                                        text: "SET"
                                        font.bold: true
                                        onClicked: {
                                            var impFact = useImperial ? 0.621371192 : 1.0;
                                            var meters = Math.round((spinOdoInput.realValue / impFact) * 1000.0);
                                            mCommands.setOdometer(meters);
                                            totalOdometerKm = spinOdoInput.realValue;
                                            mCommands.emitEmptySetupValues();
                                        }
                                    }
                                }

                                Text {
                                    text: "Sets the hardware odometer stored in the VESC controller."
                                    font.pixelSize: 10; color: colTextDim
                                }
                            }
                        }

                        // --- SECTION 3: SPEED SMOOTHING & TELEMETRY ---
                        GroupBox {
                            title: "Speed Smoothing & Polling / Сглаживание и опрос"
                            Layout.fillWidth: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Speed Smoothing / Сглаживание:"
                                        color: colTextWhite
                                        font.pixelSize: 12
                                        Layout.fillWidth: true
                                    }
                                    SpinBox {
                                        id: spinSmoothing
                                        from: 0; to: 90; stepSize: 5
                                        value: Math.round(speedSmoothing * 100)
                                        textFromValue: function(val) {
                                            return val === 0 ? "Off (0%)" : val + "%";
                                        }
                                        valueFromText: function(txt) {
                                            return parseInt(txt);
                                        }
                                        Layout.preferredWidth: 140
                                        onValueChanged: {
                                            speedSmoothing = value / 100.0;
                                            hudSettings.speedSmoothing = speedSmoothing;
                                        }
                                    }
                                }

                                Text {
                                    text: "0% = direct raw speed, 20-50% = smooth jitter-free speed."
                                    font.pixelSize: 10; color: colTextDim
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Polling Rate / Частота опроса:"
                                        color: colTextWhite
                                        font.pixelSize: 12
                                        Layout.fillWidth: true
                                    }
                                    SpinBox {
                                        id: spinPollRate
                                        from: 20; to: 500; stepSize: 10
                                        value: pollInterval
                                        textFromValue: function(val) {
                                            var hz = Math.round(1000.0 / val);
                                            return hz + " Hz (" + val + " ms)";
                                        }
                                        valueFromText: function(txt) {
                                            return parseInt(txt);
                                        }
                                        Layout.preferredWidth: 140
                                        onValueChanged: {
                                            pollInterval = value;
                                            hudSettings.pollInterval = value;
                                        }
                                    }
                                }

                                Text {
                                    text: "BLE/USB update interval (Default: 50 ms / 20 Hz, Fast: 20 ms / 50 Hz)."
                                    font.pixelSize: 10; color: colTextDim
                                }
                            }
                        }

                        // --- SECTION 4: ERPM SPEEDOMETER GAUGE SETTINGS ---
                        GroupBox {
                            title: "ERPM Gauge Settings / Настройки ERPM"
                            Layout.fillWidth: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Max ERPM:"; color: colTextWhite; font.pixelSize: 12; Layout.fillWidth: true }
                                    SpinBox {
                                        id: spinErpmMax
                                        from: 2000; to: 150000; stepSize: 1000
                                        value: erpmMax
                                        Layout.preferredWidth: 140
                                        onValueChanged: {
                                            erpmMax = value;
                                            hudSettings.erpmMax = value;
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Low-RPM Heavy Load Alert (W):"; color: colTextWhite; font.pixelSize: 12; Layout.fillWidth: true }
                                    SpinBox {
                                        id: spinPowerThresh
                                        from: 50; to: 5000; stepSize: 50
                                        value: erpmRedPowerThreshold
                                        Layout.preferredWidth: 140
                                        onValueChanged: {
                                            erpmRedPowerThreshold = value;
                                            hudSettings.erpmRedPowerThreshold = value;
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Low-RPM Alert Range (ERPM):"; color: colTextWhite; font.pixelSize: 12; Layout.fillWidth: true }
                                    SpinBox {
                                        id: spinLowRange
                                        from: 500; to: 10000; stepSize: 250
                                        value: erpmLowRange
                                        Layout.preferredWidth: 140
                                        onValueChanged: {
                                            erpmLowRange = value;
                                            hudSettings.erpmLowRange = value;
                                        }
                                    }
                                }

                                Text {
                                    text: "ERPM arc turns red at start when power exceeds threshold under specified ERPM."
                                    font.pixelSize: 10; color: colTextDim
                                }
                            }
                        }

                        // --- SECTION 5: BATTERY & CUTOFF SETTINGS ---
                        GroupBox {
                            title: "Battery & Cutoff / Батарея и отсечка"
                            Layout.fillWidth: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Voltage Offset / Смещение (V):"; color: colTextWhite; font.pixelSize: 12; Layout.fillWidth: true }
                                    DoubleSpinBox {
                                        id: spinVoltageOffset
                                        realValue: voltageOffset
                                        realFrom: -10.0
                                        realTo: 10.0
                                        realStepSize: 0.05
                                        decimals: 2
                                        suffix: " V"
                                        Layout.preferredWidth: 140
                                        onRealValueChanged: {
                                            voltageOffset = realValue;
                                            hudSettings.voltageOffset = realValue;
                                        }
                                    }
                                }

                                Text {
                                    text: "Corrects hardware ADC measurement error (e.g. +0.30 V or -0.20 V)."
                                    font.pixelSize: 10; color: colTextDim
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Series Cells (S):"; color: colTextWhite; font.pixelSize: 12; Layout.fillWidth: true }
                                    SpinBox {
                                        id: spinCells
                                        from: 0; to: 36; stepSize: 1
                                        value: customSeriesCells
                                        Layout.preferredWidth: 140
                                        onValueChanged: {
                                            customSeriesCells = value;
                                            hudSettings.seriesCells = value;
                                        }
                                    }
                                }

                                Text {
                                    text: "Set Series Cells to 0 to auto-detect from voltage."
                                    font.pixelSize: 10; color: colTextDim
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Cutoff Start (V):"; color: colTextWhite; font.pixelSize: 12; Layout.fillWidth: true }
                                    DoubleSpinBox {
                                        id: spinCutoffStart
                                        realValue: customCutoffStart > 0 ? customCutoffStart : cutoffStartVal
                                        realFrom: 10.0; realTo: 150.0; realStepSize: 0.5; decimals: 1
                                        Layout.preferredWidth: 140
                                        onRealValueChanged: {
                                            customCutoffStart = realValue;
                                            hudSettings.cutoffStart = realValue;
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "Cutoff End (V):"; color: colTextWhite; font.pixelSize: 12; Layout.fillWidth: true }
                                    DoubleSpinBox {
                                        id: spinCutoffEnd
                                        realValue: customCutoffEnd > 0 ? customCutoffEnd : cutoffEndVal
                                        realFrom: 10.0; realTo: 150.0; realStepSize: 0.5; decimals: 1
                                        Layout.preferredWidth: 140
                                        onRealValueChanged: {
                                            customCutoffEnd = realValue;
                                            hudSettings.cutoffEnd = realValue;
                                        }
                                    }
                                }
                            }
                        }

                        // --- SECTION 6: RESETS ---
                        GroupBox {
                            title: "Reset Stats / Сброс статистики"
                            Layout.fillWidth: true

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8

                                Button {
                                    Layout.fillWidth: true
                                    text: "Reset Max Stats"
                                    onClicked: {
                                        speedMax = 0.0;
                                        powerMax = 0.0;
                                        powerMinRegen = 0.0;
                                    }
                                }

                                Button {
                                    Layout.fillWidth: true
                                    text: "Reset Trip"
                                    onClicked: {
                                        tripDistanceKm = 0.0;
                                        tripInitialized = true;
                                        tripBaseOdometerKm = totalOdometerKm / distUnitFact;
                                        tripBaseTachometerKm = tachometerAbsKm / distUnitFact;
                                        tripBaseWh = wattHours;
                                        tripBaseWhCharged = wattHoursCharged;
                                    }
                                }
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            text: "SAVE & CLOSE"
                            font.bold: true
                            onClicked: settingsPopup.close()
                        }
                    }
                }
            }
        }
    }

    // Telemetry Connections: Setup Values & General Values
    Connections {
        id: commandsUpdate
        target: mCommands
        enabled: updateData

        function onValuesSetupReceived(values, mask) {
            voltageIn = values.v_in > 0.5 ? Math.max(0.0, values.v_in + voltageOffset) : 0.0;
            tempMos = values.temp_mos;
            tempMotor = values.temp_motor;
            currentMotor = values.current_motor;
            currentIn = values.current_in;
            dutyNow = values.duty_now;
            erpmNow = values.rpm;
            var fullV = detectedCells * 4.2;
            var minV = cutoffEndVal - 1.0;
            if (Math.abs(voltageOffset) > 0.001) {
                batteryPercent = Math.max(0, Math.min(100, ((voltageIn - minV) / Math.max(0.1, fullV - minV)) * 100.0));
            } else {
                batteryPercent = values.battery_level * 100.0;
            }
            batteryWh = values.battery_wh;
            wattHours = values.watt_hours;
            wattHoursCharged = values.watt_hours_charged;
            ampHours = values.amp_hours;
            ampHoursCharged = values.amp_hours_charged;
            faultString = values.fault_str;
            numControllers = values.num_vescs;

            // Speed from values.speed (m/s * 3.6 -> km/h) with fallback to RPM calculation
            var impFact = useImperial ? 0.621371192 : 1.0;
            var spd = values.speed * 3.6 * impFact;
            if (Math.abs(spd) < 0.01 && Math.abs(values.rpm) > 10) {
                var poles = mMcConf.getParamInt("si_motor_poles");
                var gearRatio = mMcConf.getParamDouble("si_gear_ratio");
                var wheelDiam = mMcConf.getParamDouble("si_wheel_diameter");
                if (poles > 0 && wheelDiam > 0) {
                    var erpmToRpm = values.rpm / (poles / 2.0);
                    var wheelRpm = erpmToRpm / (gearRatio > 0 ? gearRatio : 1.0);
                    var speedKmh = (wheelRpm * wheelDiam * Math.PI * 60.0) / 1000.0;
                    spd = speedKmh * impFact;
                }
            }
            var rawSpeed = Math.abs(spd);
            if (speedSmoothing <= 0.01) {
                speedNow = rawSpeed;
            } else {
                if (rawSpeed < 0.1 && speedNow < 0.5) {
                    speedNow = 0.0;
                } else {
                    speedNow = (speedNow * speedSmoothing) + (rawSpeed * (1.0 - speedSmoothing));
                }
            }
            if (speedNow > speedMax) speedMax = speedNow;

            // Electrical Motor Power (V * I)
            powerNow = values.current_in * voltageIn;
            if (powerNow > powerMax) powerMax = powerNow;
            if (powerNow < powerMinRegen) powerMinRegen = powerNow;

            // Odometer & Trip Distance
            totalOdometerKm = (values.odometer / 1000.0) * distUnitFact;
            var tDist = (values.tachometer_abs / 1000.0) * distUnitFact;
            tachometerAbsKm = tDist;
            var validDistance = values.odometer > 0 || values.tachometer_abs > 0;
            if (!tripInitialized && validDistance) {
                tripInitialized = true;
                tripBaseOdometerKm = values.odometer / 1000.0;
                tripBaseTachometerKm = values.tachometer_abs / 1000.0;
                tripBaseWh = values.watt_hours;
                tripBaseWhCharged = values.watt_hours_charged;
            }
            if (tripInitialized && validDistance) {
                var odoTrip = Math.max(0, values.odometer / 1000.0 - tripBaseOdometerKm);
                var tachoTrip = Math.max(0, values.tachometer_abs / 1000.0 - tripBaseTachometerKm);
                tripDistanceKm = Math.max(odoTrip, tachoTrip) * distUnitFact;
            }

            // Consumption calculation
            var whConsume = tripInitialized ?
                        (values.watt_hours - tripBaseWh) - (values.watt_hours_charged - tripBaseWhCharged) : 0.0;
            var distAbsKm = tripDistanceKm / Math.max(0.000001, distUnitFact);
            if (validDistance && distAbsKm > 0.01) {
                whKmAvg = whConsume / distAbsKm;
            }
            var speedKm = values.speed * 3.6;
            if (Math.abs(speedKm) > 1.0) {
                var inst = powerNow / Math.abs(speedKm);
                whKmNow = (whKmNow * 0.9) + (inst * 0.1);
            }

            // Uptime formatting
            if (values.uptime_ms > 0) {
                var s = Math.floor(values.uptime_ms / 1000) % 60;
                var m = Math.floor(values.uptime_ms / (1000 * 60)) % 60;
                var h = Math.floor(values.uptime_ms / (1000 * 60 * 60));
                uptimeString = (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
            }

            // Thermal limits from mcConf if available
            var fetStart = mMcConf.getParamDouble("l_temp_fet_start");
            var fetEnd = mMcConf.getParamDouble("l_temp_fet_end");
            if (fetStart > 0) tempFetLimitStart = fetStart;
            if (fetEnd > 0) tempFetLimitEnd = fetEnd;

            var motStart = mMcConf.getParamDouble("l_temp_motor_start");
            var motEnd = mMcConf.getParamDouble("l_temp_motor_end");
            if (motStart > 0) tempMotorLimitStart = motStart;
            if (motEnd > 0) tempMotorLimitEnd = motEnd;
        }

        function onValuesReceived(values, mask) {
            voltageIn = values.v_in > 0.5 ? Math.max(0.0, values.v_in + voltageOffset) : 0.0;
            tempMos = values.temp_mos;
            tempMotor = values.temp_motor;
            currentMotor = values.current_motor;
            currentIn = values.current_in;
            dutyNow = values.duty_now;
            erpmNow = values.rpm;
            wattHours = values.watt_hours;
            wattHoursCharged = values.watt_hours_charged;
            ampHours = values.amp_hours;
            ampHoursCharged = values.amp_hours_charged;
            faultString = values.fault_str;

            powerNow = values.current_in * voltageIn;
            if (powerNow > powerMax) powerMax = powerNow;
            if (powerNow < powerMinRegen) powerMinRegen = powerNow;

            var impFact = useImperial ? 0.621371192 : 1.0;
            var poles = mMcConf.getParamInt("si_motor_poles");
            var gearRatio = mMcConf.getParamDouble("si_gear_ratio");
            var wheelDiam = mMcConf.getParamDouble("si_wheel_diameter");
            if (poles > 0 && wheelDiam > 0) {
                var erpmToRpm = values.rpm / (poles / 2.0);
                var wheelRpm = erpmToRpm / (gearRatio > 0 ? gearRatio : 1.0);
                var speedKmh = (wheelRpm * wheelDiam * Math.PI * 60.0) / 1000.0;
                speedNow = Math.abs(speedKmh * impFact);
                if (speedNow > speedMax) speedMax = speedNow;
            }

            var fullV = detectedCells * 4.2;
            var emptyV = detectedCells * 3.2;
            batteryPercent = Math.max(0, Math.min(100, ((voltageIn - emptyV) / Math.max(0.1, fullV - emptyV)) * 100.0));
        }
    }
}
