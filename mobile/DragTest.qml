/*
    Drag/acceleration test for the mobile HUD.

    The component deliberately keeps the measurement in QML.  The HUD already
    receives a high-rate speed signal, so this avoids adding another polling
    path while still making the feature available on Android and iOS.
*/

import QtQuick 2.10
import QtQuick.Controls 2.10
import QtQuick.Layouts 1.3
import QtQuick.Dialogs 1.3 as Dl

import Vedder.vesc.logwriter 1.0
import Vedder.vesc.utility 1.0

Popup {
    id: dragTest

    property real currentSpeed: 0.0
    property real currentPowerW: 0.0
    property real currentWattHours: 0.0
    property real currentWattHoursCharged: 0.0
    property real currentVoltageV: 0.0
    property real currentTempMosC: 0.0
    property real currentTempMotorC: 0.0
    property real speedUnitFact: 3.6
    property string speedUnitText: "km/h"
    property bool runningTest: false
    property bool armed: false
    property bool finished: false
    property string statusText: "Ready / Готово"
    property var samples: []
    property var accelerationSamples: []
    property var resultTimes: ({})
    property int resultVersion: 0
    property real testStartMs: 0.0
    property real lastSampleTime: 0.0
    property real previousSpeed: 0.0
    property real maxTestSpeed: 0.0
    property real maxSpeedTime: 0.0
    property real maxAcceleration: 0.0
    property real distanceMeters: 0.0
    property real startWattHours: 0.0
    property real startWattHoursCharged: 0.0
    property real energyUsedWh: 0.0
    property real energyRegenWh: 0.0
    property real energyNetWh: 0.0
    property real peakPowerW: 0.0
    property real minVoltageV: 0.0
    property real maxTempC: 0.0
    // The clock starts when the measured speed crosses 0.5 km/h. Keep the
    // trigger physical when the HUD is switched to imperial units.
    property real launchSpeedKmh: 0.5
    readonly property real launchSpeedThreshold: launchSpeedKmh * speedUnitFact / 3.6
    property real armedPreviousSpeed: 0.0
    property real armedPreviousMs: 0.0
    property bool launchReady: false
    property real maxDuration: 60.0
    property var thresholdValues: [15, 20, 25, 30, 35, 40, 45, 50]
    property int chartMode: 0

    readonly property bool testActive: visible && (runningTest || armed)

    readonly property color panelBg: "#100d18"
    readonly property color cardBg: "#1b1626"
    readonly property color cardBorder: "#3a2d4d"
    readonly property color violet: "#8c42ff"
    readonly property color violetLight: "#c7aaff"
    readonly property color green: "#45d47b"
    readonly property color amber: "#ffc857"
    readonly property color white: "#f4f1fa"
    readonly property color textDim: "#a39bad"

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 14 : 480, 920)
    height: Math.min(parent ? parent.height - 14 : 760, 820)
    padding: 0

    background: Rectangle {
        color: panelBg
        radius: 14
        border.color: violet
        border.width: 1
    }

    function copyTimes() {
        var copy = {};
        for (var key in resultTimes) {
            copy[key] = resultTimes[key];
        }
        return copy;
    }

    function resetTest() {
        runningTest = false;
        armed = false;
        finished = false;
        statusText = "Ready / Готово — press Start and accelerate";
        samples = [];
        accelerationSamples = [];
        resultTimes = ({});
        resultVersion++;
        testStartMs = 0.0;
        lastSampleTime = 0.0;
        previousSpeed = 0.0;
        maxTestSpeed = 0.0;
        maxSpeedTime = 0.0;
        maxAcceleration = 0.0;
        distanceMeters = 0.0;
        startWattHours = 0.0;
        startWattHoursCharged = 0.0;
        energyUsedWh = 0.0;
        energyRegenWh = 0.0;
        energyNetWh = 0.0;
        peakPowerW = 0.0;
        minVoltageV = 0.0;
        maxTempC = 0.0;
        armedPreviousSpeed = 0.0;
        armedPreviousMs = 0.0;
        launchReady = false;
        chartVersion++;
    }

    function openTest() {
        if (!visible) {
            open();
        }
    }

    function startTest() {
        resetTest();
        armed = true;
        armedPreviousSpeed = Math.max(0.0, Math.abs(Number(currentSpeed)));
        armedPreviousMs = Date.now();
        launchReady = armedPreviousSpeed < launchSpeedThreshold;
        statusText = launchReady ?
                    "Armed / Готово — timer starts at 0.5 km/h" :
                    "Waiting / Остановитесь — speed must drop below 0.5 km/h";
    }

    function beginRun(now, speed) {
        runningTest = true;
        armed = false;
        finished = false;
        statusText = "Running / Разгон измеряется…";
        testStartMs = now;
        lastSampleTime = 0.0;
        previousSpeed = Math.max(0.0, speed);
        maxTestSpeed = previousSpeed;
        maxSpeedTime = 0.0;
        maxAcceleration = 0.0;
        distanceMeters = 0.0;
        startWattHours = Number(currentWattHours);
        startWattHoursCharged = Number(currentWattHoursCharged);
        energyUsedWh = 0.0;
        energyRegenWh = 0.0;
        energyNetWh = 0.0;
        peakPowerW = Math.max(0.0, Number(currentPowerW));
        minVoltageV = Math.max(0.0, Number(currentVoltageV));
        maxTempC = Math.max(Number(currentTempMosC), Number(currentTempMotorC));
        samples = [{
                       t: 0.0,
                       s: previousSpeed,
                       a: 0.0,
                       p: Number(currentPowerW),
                       e: 0.0,
                       r: 0.0,
                       n: 0.0,
                       v: Number(currentVoltageV),
                       tm: Number(currentTempMosC),
                       te: Number(currentTempMotorC),
                       d: 0.0
                   }];
        accelerationSamples = [{t: 0.0, a: 0.0}];
        resultTimes = ({});
        resultVersion++;
        chartVersion++;
    }

    function stopTest() {
        if (runningTest) {
            runningTest = false;
            armed = false;
            finished = true;
            statusText = "Finished / Завершено";
            resultVersion++;
            chartVersion++;
        } else if (armed) {
            armed = false;
            statusText = "Cancelled / Отменено — press Start to try again";
        }
    }

    function recordTelemetry(speedValue) {
        if (!visible || (!runningTest && !armed)) {
            return;
        }

        var speed = Number(speedValue);
        if (!isFinite(speed)) {
            return;
        }
        speed = Math.max(0.0, Math.abs(speed));
        var now = Date.now();

        if (armed) {
            if (!launchReady) {
                if (speed < launchSpeedThreshold) {
                    launchReady = true;
                    statusText = "Armed / Готово — timer starts at 0.5 km/h";
                }
                armedPreviousSpeed = speed;
                armedPreviousMs = now;
                return;
            }

            if (armedPreviousSpeed < launchSpeedThreshold && speed >= launchSpeedThreshold) {
                var launchRange = speed - armedPreviousSpeed;
                var launchFraction = launchRange > 0.0001 ?
                            (launchSpeedThreshold - armedPreviousSpeed) / launchRange : 1.0;
                var launchMs = armedPreviousMs +
                        (now - armedPreviousMs) * Math.max(0.0, Math.min(1.0, launchFraction));

                // t=0 is the interpolated instant at which speed crossed
                // exactly 0.5 km/h, not the time the Start button was pressed.
                beginRun(launchMs, launchSpeedThreshold);
            } else {
                armedPreviousSpeed = speed;
                armedPreviousMs = now;
                return;
            }
        }

        if (!runningTest) {
            return;
        }

        var elapsed = Math.max(0.0, (now - testStartMs) / 1000.0);
        var dt = elapsed - lastSampleTime;
        if (dt <= 0.001) {
            return;
        }

        var speedMs = speed / Math.max(0.001, speedUnitFact);
        var previousSpeedMs = previousSpeed / Math.max(0.001, speedUnitFact);
        var acceleration = (speedMs - previousSpeedMs) / dt;
        distanceMeters += ((speedMs + previousSpeedMs) * 0.5) * dt;
        energyUsedWh = Math.max(0.0, Number(currentWattHours) - startWattHours);
        energyRegenWh = Math.max(0.0, Number(currentWattHoursCharged) - startWattHoursCharged);
        energyNetWh = energyUsedWh - energyRegenWh;

        // Interpolate threshold crossings between two telemetry packets.  It
        // makes 0-20 times useful even when the BLE interval is 50-100 ms.
        var crossed = copyTimes();
        for (var i = 0; i < thresholdValues.length; i++) {
            var threshold = thresholdValues[i];
            var key = String(threshold);
            if (crossed[key] === undefined && previousSpeed < threshold && speed >= threshold) {
                var fraction = (threshold - previousSpeed) / Math.max(0.0001, speed - previousSpeed);
                crossed[key] = lastSampleTime + (dt * Math.max(0.0, Math.min(1.0, fraction)));
            }
        }
        resultTimes = crossed;

        var nextSamples = samples.slice(0);
        nextSamples.push({
                             t: elapsed,
                             s: speed,
                             a: acceleration,
                             p: Number(currentPowerW),
                             e: energyUsedWh,
                             r: energyRegenWh,
                             n: energyNetWh,
                             v: Number(currentVoltageV),
                             tm: Number(currentTempMosC),
                             te: Number(currentTempMotorC),
                             d: distanceMeters
                         });
        // Keep a complete one-minute run even at the fastest supported 50 Hz
        // polling rate, while still bounding memory use on Android.
        if (nextSamples.length > 3200) {
            nextSamples.shift();
        }
        samples = nextSamples;

        var nextAcceleration = accelerationSamples.slice(0);
        nextAcceleration.push({t: elapsed, a: acceleration});
        if (nextAcceleration.length > 3200) {
            nextAcceleration.shift();
        }
        accelerationSamples = nextAcceleration;

        if (speed > maxTestSpeed) {
            maxTestSpeed = speed;
            maxSpeedTime = elapsed;
        }
        if (acceleration > maxAcceleration) {
            maxAcceleration = acceleration;
        }
        if (Number(currentPowerW) > peakPowerW) {
            peakPowerW = Number(currentPowerW);
        }
        if (Number(currentVoltageV) > 0.0 &&
                (minVoltageV <= 0.0 || Number(currentVoltageV) < minVoltageV)) {
            minVoltageV = Number(currentVoltageV);
        }
        maxTempC = Math.max(maxTempC, Number(currentTempMosC), Number(currentTempMotorC));
        previousSpeed = speed;
        lastSampleTime = elapsed;
        resultVersion++;
        chartVersion++;

        if (elapsed >= maxDuration) {
            stopTest();
        }
    }

    function formatTime(value) {
        return value === undefined || value === null ? "—" : Number(value).toFixed(2) + " s";
    }

    function launchSpeedText() {
        return launchSpeedThreshold.toFixed(speedUnitText === "km/h" ? 1 : 2);
    }

    function thresholdTime(threshold) {
        // resultVersion is intentionally read here so delegates are refreshed
        // when a threshold is crossed (the values are held in a JS object).
        var version = resultVersion;
        return formatTime(resultTimes[String(threshold)]);
    }

    function finiteNumber(value, fallback) {
        var number = Number(value);
        return isFinite(number) ? number : fallback;
    }

    function csvNumber(value) {
        return finiteNumber(value, 0.0).toFixed(6);
    }

    function chooseCsvExport() {
        if (samples.length < 2) {
            statusText = "Nothing to export / Нет данных для экспорта";
            return;
        }

        if (Utility.requestFilePermission()) {
            csvSaveDialog.open();
        } else {
            statusText = "CSV export failed: no file permission";
        }
    }

    function exportCsv(filePath) {
        var path = String(filePath);
        if (path.toLowerCase().slice(-4) !== ".csv") {
            path += ".csv";
        }

        var lines = [];
        lines.push("# VESC Drag Test CSV v1");
        lines.push("# generated_utc," + new Date().toISOString());
        lines.push("# timer_trigger_kmh," + launchSpeedKmh.toFixed(3));
        lines.push("# display_speed_unit," + speedUnitText);
        for (var ti = 0; ti < thresholdValues.length; ti++) {
            var threshold = thresholdValues[ti];
            var result = resultTimes[String(threshold)];
            lines.push("# result_0_to_" + threshold + "_display_s," +
                       (result === undefined ? "" : Number(result).toFixed(6)));
        }
        lines.push("time_s,speed_kmh,speed_display,speed_unit,acceleration_m_s2,power_w," +
                   "energy_used_wh,energy_regen_wh,energy_net_wh,battery_voltage_v," +
                   "mos_temp_c,motor_temp_c,distance_m");

        for (var i = 0; i < samples.length; i++) {
            var sample = samples[i];
            var speedKmh = finiteNumber(sample.s, 0.0) * 3.6 / Math.max(0.001, speedUnitFact);
            lines.push(csvNumber(sample.t) + "," +
                       csvNumber(speedKmh) + "," +
                       csvNumber(sample.s) + "," + speedUnitText + "," +
                       csvNumber(sample.a) + "," +
                       csvNumber(sample.p) + "," +
                       csvNumber(sample.e) + "," +
                       csvNumber(sample.r) + "," +
                       csvNumber(sample.n) + "," +
                       csvNumber(sample.v) + "," +
                       csvNumber(sample.tm) + "," +
                       csvNumber(sample.te) + "," +
                       csvNumber(sample.d));
        }

        var opened = csvWriter.openLogFileFullPath(path);
        var written = opened && csvWriter.writeToLogFile(lines.join("\n") + "\n");
        csvWriter.closeLogFile();
        statusText = written ? "CSV saved / CSV сохранён" : "CSV export failed / Ошибка экспорта CSV";
        return written;
    }

    function chartDefinition(mode) {
        if (mode === 1) {
            return {title: "ACCELERATION (m/s²)", decimals: 1, includeZero: true,
                    symmetric: true, series: [{field: "a", name: "Acceleration", color: amber}]};
        }
        if (mode === 2) {
            return {title: "BATTERY POWER (W)", decimals: 0, includeZero: true,
                    series: [{field: "p", name: "Power", color: "#29b6f6"}]};
        }
        if (mode === 3) {
            return {title: "ENERGY (Wh)", decimals: 3, includeZero: true,
                    series: [{field: "e", name: "Used", color: green},
                             {field: "r", name: "Regen", color: "#29b6f6"},
                             {field: "n", name: "Net", color: violetLight}]};
        }
        if (mode === 4) {
            return {title: "BATTERY VOLTAGE (V)", decimals: 1, pad: 0.5,
                    series: [{field: "v", name: "Voltage", color: "#42a5f5"}]};
        }
        if (mode === 5) {
            return {title: "TEMPERATURES (°C)", decimals: 1, pad: 2.0,
                    series: [{field: "tm", name: "MOS", color: "#ff5252"},
                             {field: "te", name: "Motor", color: amber}]};
        }
        return {title: "SPEED (" + speedUnitText + ")", decimals: 0, includeZero: true,
                speedChart: true, series: [{field: "s", name: "Speed", color: green}]};
    }

    function drawChart(canvas, ctx, mode) {
        var w = canvas.width;
        var h = canvas.height;
        ctx.reset();
        if (w < 80 || h < 60) {
            return;
        }

        var left = 42;
        var right = 12;
        var top = 18;
        var bottom = 28;
        var plotW = Math.max(10, w - left - right);
        var plotH = Math.max(10, h - top - bottom);
        var data = samples;
        var definition = chartDefinition(mode);
        var xMax = 1.0;
        if (data.length > 0) {
            xMax = Math.max(1.0, data[data.length - 1].t);
        }

        var yMin = 0.0;
        var yMax = 1.0;
        var hasValue = false;
        for (var si = 0; si < definition.series.length; si++) {
            var field = definition.series[si].field;
            for (var di = 0; di < data.length; di++) {
                var candidate = Number(data[di][field]);
                if (isFinite(candidate)) {
                    if (!hasValue) {
                        yMin = candidate;
                        yMax = candidate;
                        hasValue = true;
                    } else {
                        yMin = Math.min(yMin, candidate);
                        yMax = Math.max(yMax, candidate);
                    }
                }
            }
        }

        if (definition.speedChart) {
            yMin = 0.0;
            yMax = Math.max(10.0, maxTestSpeed * 1.12, thresholdValues[thresholdValues.length - 1] * 1.08);
        } else if (definition.symmetric) {
            var absoluteMax = Math.max(1.0, Math.abs(yMin), Math.abs(yMax)) * 1.12;
            yMin = -absoluteMax;
            yMax = absoluteMax;
        } else {
            if (definition.includeZero) {
                yMin = Math.min(0.0, yMin);
                yMax = Math.max(0.0, yMax);
            }
            var padding = definition.pad !== undefined ? definition.pad : Math.max(0.05, (yMax - yMin) * 0.12);
            if (Math.abs(yMax - yMin) < 0.0001) {
                padding = Math.max(padding, Math.abs(yMax) * 0.05, 0.1);
            }
            yMin -= padding;
            yMax += padding;
        }

        ctx.fillStyle = "#0c0912";
        ctx.fillRect(0, 0, w, h);
        ctx.strokeStyle = "#382c48";
        ctx.lineWidth = 1;
        ctx.font = "10px Roboto";
        ctx.fillStyle = textDim;

        for (var gy = 0; gy <= 4; gy++) {
            var gyPos = top + plotH * gy / 4.0;
            ctx.beginPath();
            ctx.moveTo(left, gyPos);
            ctx.lineTo(left + plotW, gyPos);
            ctx.stroke();
            var gyValue = yMax - (yMax - yMin) * gy / 4.0;
            ctx.fillText(gyValue.toFixed(definition.decimals), 4, gyPos + 3);
        }

        for (var gx = 0; gx <= 4; gx++) {
            var gxPos = left + plotW * gx / 4.0;
            ctx.beginPath();
            ctx.moveTo(gxPos, top);
            ctx.lineTo(gxPos, top + plotH);
            ctx.stroke();
            ctx.fillText((xMax * gx / 4.0).toFixed(1), gxPos - 8, h - 8);
        }

        // Threshold guides make the speed plot readable while riding.
        if (definition.speedChart) {
            ctx.strokeStyle = "#5a4373";
            for (var ti = 0; ti < thresholdValues.length; ti++) {
                var thresholdY = top + plotH * (1.0 - thresholdValues[ti] / yMax);
                if (thresholdY >= top && thresholdY <= top + plotH) {
                    ctx.beginPath();
                    ctx.moveTo(left, thresholdY);
                    ctx.lineTo(left + plotW, thresholdY);
                    ctx.stroke();
                }
            }
        }

        if (definition.includeZero && yMin < 0.0 && yMax > 0.0) {
            var zeroY = top + plotH * (1.0 - (0.0 - yMin) / (yMax - yMin));
            ctx.strokeStyle = "#776b85";
            ctx.beginPath();
            ctx.moveTo(left, zeroY);
            ctx.lineTo(left + plotW, zeroY);
            ctx.stroke();
        }

        ctx.lineWidth = 2.2;
        ctx.lineJoin = "round";
        for (var seriesIndex = 0; seriesIndex < definition.series.length; seriesIndex++) {
            var series = definition.series[seriesIndex];
            ctx.strokeStyle = series.color;
            if (data.length > 0) {
                ctx.beginPath();
                var pointStarted = false;
                for (var p = 0; p < data.length; p++) {
                    var value = Number(data[p][series.field]);
                    if (!isFinite(value)) {
                        continue;
                    }
                    var px = left + plotW * Math.max(0.0, Math.min(1.0, data[p].t / xMax));
                    var py = top + plotH * (1.0 - (value - yMin) / Math.max(0.001, yMax - yMin));
                    if (!pointStarted) {
                        ctx.moveTo(px, py);
                        pointStarted = true;
                    } else {
                        ctx.lineTo(px, py);
                    }
                }
                ctx.stroke();
            }
        }

        ctx.fillStyle = definition.series[0].color;
        ctx.font = "bold 10px Roboto";
        ctx.fillText(definition.title, left, 11);

        var legendX = Math.max(left + 100, w - 12);
        ctx.textAlign = "right";
        for (var legendIndex = definition.series.length - 1; legendIndex >= 0; legendIndex--) {
            var legend = definition.series[legendIndex];
            ctx.fillStyle = legend.color;
            ctx.fillText(legend.name, legendX, 11);
            legendX -= ctx.measureText(legend.name).width + 14;
        }
        ctx.textAlign = "left";
        ctx.fillStyle = textDim;
        ctx.font = "10px Roboto";
        ctx.fillText("time (s)", w - 49, h - 8);
    }

    onClosed: {
        if (runningTest || armed) {
            stopTest();
        }
    }

    LogWriter {
        id: csvWriter
    }

    Dl.FileDialog {
        id: csvSaveDialog
        title: "Export drag test CSV"
        nameFilters: ["CSV files (*.csv)"]
        selectExisting: false
        selectMultiple: false
        onAccepted: {
            dragTest.exportCsv(fileUrl.toString());
            close();
        }
        onRejected: close()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 9
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Drag test / Тест разгона"
                color: white
                font.bold: true
                font.pixelSize: 17
                Layout.fillWidth: true
            }
            Text {
                text: runningTest ? "● REC" : (armed ? "● ARMED" : "")
                color: runningTest ? "#ff5575" : amber
                font.bold: true
                font.pixelSize: 11
            }
            Button {
                text: "×"
                Layout.preferredWidth: 34
                Layout.preferredHeight: 28
                onClicked: dragTest.close()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Button {
                id: startButton
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                text: armed ? "CANCEL" : (finished ? "NEW TEST" : "START")
                enabled: !runningTest
                onClicked: armed ? resetTest() : startTest()
                background: Rectangle {
                    radius: 5
                    color: startButton.enabled ? (startButton.down ? "#265d3c" : "#193b29") : "#241d2c"
                    border.color: green
                    border.width: 1
                }
                contentItem: Text {
                    text: startButton.text
                    color: white
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Button {
                id: stopButton
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                text: "STOP"
                enabled: runningTest
                onClicked: stopTest()
                background: Rectangle {
                    radius: 5
                    color: stopButton.enabled ? (stopButton.down ? "#6f2132" : "#421b2a") : "#241d2c"
                    border.color: "#ff5575"
                    border.width: 1
                }
                contentItem: Text {
                    text: stopButton.text
                    color: white
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Button {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 30
                text: "RESET"
                onClicked: resetTest()
            }
            Button {
                Layout.preferredWidth: 92
                Layout.preferredHeight: 30
                text: "EXPORT CSV"
                enabled: samples.length > 1
                onClicked: chooseCsvExport()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 5
            color: cardBg
            border.color: finished ? green : (runningTest ? violet : cardBorder)
            Text {
                anchors.fill: parent
                anchors.leftMargin: 10
                verticalAlignment: Text.AlignVCenter
                text: statusText
                color: finished ? green : (runningTest ? violetLight : textDim)
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        GridLayout {
            id: summaryGrid
            Layout.fillWidth: true
            Layout.preferredHeight: columns === 8 ? 50 : 100
            columns: dragTest.width >= 680 ? 8 : 4
            rowSpacing: 4
            columnSpacing: 4

            Repeater {
                model: ["MAX", "MAX TIME", "DIST", "ACC", "POWER", "ENERGY", "V MIN", "TEMP MAX"]
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    radius: 5
                    color: cardBg
                    border.color: cardBorder
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: modelData === "MAX TIME" ? "0→MAX" : modelData
                            color: textDim
                            font.pixelSize: 8
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            Layout.fillWidth: true
                            color: white
                            font.bold: true
                            font.pixelSize: summaryGrid.columns === 8 ? 11 : 13
                            horizontalAlignment: Text.AlignHCenter
                            text: {
                                var version = resultVersion;
                                if (modelData === "MAX") return maxTestSpeed.toFixed(1) + " " + speedUnitText;
                                if (modelData === "MAX TIME") return maxSpeedTime.toFixed(2) + " s";
                                if (modelData === "DIST") return distanceMeters.toFixed(1) + " m";
                                if (modelData === "ACC") return maxAcceleration.toFixed(1) + " m/s²";
                                if (modelData === "POWER") return Math.round(peakPowerW) + " W";
                                if (modelData === "ENERGY") return energyUsedWh.toFixed(3) + " Wh";
                                if (modelData === "V MIN") return minVoltageV.toFixed(1) + " V";
                                return maxTempC.toFixed(1) + " °C";
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: thresholdPanel
            Layout.fillWidth: true
            Layout.preferredHeight: thresholdGrid.columns === 8 ? 42 : 82
            radius: 6
            color: cardBg
            border.color: cardBorder

            GridLayout {
                id: thresholdGrid
                anchors.fill: parent
                anchors.margins: 5
                columns: dragTest.width >= 680 ? 8 : 4
                rowSpacing: 4
                columnSpacing: 4
                Repeater {
                    model: thresholdValues
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        radius: 4
                        color: resultTimes[String(modelData)] === undefined ? "#15111d" : "#173c28"
                        border.color: resultTimes[String(modelData)] === undefined ? cardBorder : green
                        Text {
                            anchors.fill: parent
                            anchors.margins: 1
                            text: "0 → " + modelData + " " + speedUnitText + "\n" + thresholdTime(modelData)
                            color: white
                            font.pixelSize: 9
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        TabBar {
            id: chartTabs
            Layout.fillWidth: true
            Layout.preferredHeight: 31
            onCurrentIndexChanged: {
                if (chartMode !== currentIndex) {
                    chartMode = currentIndex;
                }
                telemetryChart.requestPaint();
            }

            Repeater {
                model: ["SPEED", "ACCEL", "POWER", "ENERGY", "VOLTAGE", "TEMPS"]
                TabButton {
                    width: chartTabs.width / 6.0
                    text: modelData
                    font.pixelSize: 9
                    padding: 2
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 90
            color: "#0c0912"
            radius: 5
            border.color: cardBorder
            clip: true

            Canvas {
                    id: telemetryChart
                    anchors.fill: parent
                    Layout.fillWidth: true
                    antialiasing: true
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: dragTest.drawChart(this, getContext("2d"), chartMode)
                    Component.onCompleted: requestPaint()
                }
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: 11
            text: "Reported as 0–X • timer trigger: 0.5 km/h • " + samples.length + " samples"
            color: textDim
            font.pixelSize: 8
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    property int chartVersion: 0
    Connections {
        target: dragTest
        function onChartVersionChanged() {
            telemetryChart.requestPaint();
        }
        function onSpeedUnitTextChanged() {
            telemetryChart.requestPaint();
        }
        function onChartModeChanged() {
            if (chartTabs.currentIndex !== chartMode) {
                chartTabs.setCurrentIndex(chartMode);
            }
            telemetryChart.requestPaint();
        }
    }
}
