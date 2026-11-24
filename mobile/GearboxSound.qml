import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.3

Item {
    id: soundPage

    property var mCommands
    property bool connected: false
    property bool active: false
    property bool pending: false
    property bool saving: false
    property string saveResult: ""
    property string configStatus: "Upload and run the updated Smart Traction Preset first"
    property string controllerState: "Controller sound: unknown"
    readonly property var defaults: [1, 10, 60, 4, 358, 0.02, 1.15, 220, 1500, 0.12]
    property var config: defaults.slice(0)
    readonly property var fields: [
        {index: 1, label: "Logarithmic rise starts at", min: 0, max: 100, step: 1, decimals: 1, suffix: " km/h"},
        {index: 2, label: "Full pitch at", min: 1, max: 200, step: 1, decimals: 1, suffix: " km/h"},
        {index: 3, label: "Logarithmic curve", min: 0.1, max: 20, step: 0.1, decimals: 2, suffix: ""},
        {index: 4, label: "Speed calibration", min: 1, max: 10000, step: 1, decimals: 1, suffix: " ERPM/(km/h)"},
        {index: 5, label: "Quiet preload level", min: 0, max: 0.25, step: 0.005, decimals: 3, suffix: " V"},
        {index: 6, label: "Maximum sound level", min: 0, max: 2, step: 0.05, decimals: 2, suffix: " V"},
        {index: 7, label: "Base frequency", min: 50, max: 1000, step: 10, decimals: 0, suffix: " Hz"},
        {index: 8, label: "Frequency rise", min: 0, max: 4000, step: 50, decimals: 0, suffix: " Hz"},
        {index: 9, label: "Response time", min: 0.02, max: 1, step: 0.01, decimals: 2, suffix: " s"}
    ]

    function setConfigValue(index, value) {
        if (config[index] === value) {
            return
        }
        var updated = config.slice(0)
        updated[index] = value
        config = updated
    }

    function validConfig(values) {
        if (values.length !== defaults.length || (values[0] !== 0 && values[0] !== 1)) {
            return false
        }
        for (var i = 0; i < fields.length; i++) {
            var field = fields[i]
            var value = values[field.index]
            if (!isFinite(value) || value < field.min || value > field.max) {
                return false
            }
        }
        return values[2] > values[1] && values[6] >= values[5]
    }

    function requestConfig() {
        if (!connected || pending) {
            return
        }
        pending = true
        saving = false
        saveResult = ""
        controllerState = "Controller sound: reading..."
        configStatus = "Reading from controller..."
        timeoutTimer.restart()
        mCommands.lispSendReplCmd("(gs-get-config)")
    }

    function applyConfig() {
        if (!connected || pending) {
            return
        }
        if (!validConfig(config)) {
            configStatus = "Full pitch speed must exceed start speed; maximum level must be at least the preload level."
            return
        }
        pending = true
        saving = true
        saveResult = ""
        controllerState = "Controller sound: applying..."
        configStatus = "Waiting for controller acknowledgement..."
        timeoutTimer.restart()
        mCommands.lispSetGearboxSoundConfig(config[0] !== 0, config[1], config[2], config[3], config[4],
                                           config[5], config[6], config[7], config[8], config[9])
    }

    function handleReply(str) {
        if (!pending) {
            return
        }
        if (str.indexOf("GS_CONFIG_SAVED") >= 0) {
            saveResult = "Saved to controller EEPROM"
        } else if (str.indexOf("GS_CONFIG_SAVE_FAILED") >= 0) {
            saveResult = "Applied in RAM; EEPROM save failed"
        } else if (str.indexOf("GS_CONFIG_APPLIED_RAM_ONLY") >= 0) {
            saveResult = "Applied in RAM only; stop and release throttle, then apply again to save"
        } else if (str.indexOf("GS_CONFIG_INVALID") >= 0) {
            controllerState = "Controller sound: settings rejected"
            configStatus = "Controller rejected invalid sound settings"
            pending = false
            timeoutTimer.stop()
            return
        }

        // VESC's print extension quotes strings; desktop LispBM may print them
        // verbatim. COMM_LISP_PRINT can also retain the packet's trailing NUL.
        var text = str.replace(/\u0000/g, "")
        var match = text.match(/(?:^|[\r\n])\s*(?:>\s*)?"?GS_CONFIG_V1[ \t]+([^\r\n]+)/)
        if (!match) {
            return
        }
        var payload = match[1].trim().replace(/"$/, "")
        var tokens = payload.trim().split(/\s+/)
        var values = []
        for (var i = 0; i < tokens.length; i++) {
            values.push(Number(tokens[i]))
        }
        if (!validConfig(values)) {
            return
        }
        config = values
        controllerState = "Controller sound: " + (values[0] !== 0 ? "ON" : "OFF")
        configStatus = saveResult.length > 0 ? saveResult :
                       (saving ? "Applied; EEPROM save not confirmed" : "Read from controller")
        pending = false
        timeoutTimer.stop()
    }

    onActiveChanged: {
        if (active) {
            refreshTimer.restart()
        }
    }
    onConnectedChanged: {
        if (!connected) {
            pending = false
            saveResult = ""
            controllerState = "Controller sound: unknown"
            configStatus = "Not connected"
            timeoutTimer.stop()
        } else if (active) {
            refreshTimer.restart()
        }
    }

    Timer {
        id: refreshTimer
        interval: 750
        onTriggered: soundPage.requestConfig()
    }

    Timer {
        id: timeoutTimer
        interval: 6000
        onTriggered: {
            soundPage.controllerState = "Controller sound: no response"
            soundPage.configStatus = saveResult.length > 0 ? saveResult + "; readback timed out" :
                "No acknowledgement. Upload and run the updated Smart Traction Preset; check REPL errors."
            soundPage.pending = false
        }
    }

    Connections {
        target: soundPage.mCommands
        function onLispPrintReceived(str) {
            soundPage.handleReply(str)
        }
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 8

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Straight-cut gearbox sound stays very quiet while preload is active, including with the throttle released. " +
                      "Throttle raises the volume; traction and acceleration limiting lower it as drive current is reduced. " +
                      "Pitch rises logarithmically above the selected speed."
                color: "#bdbdbd"
            }

            Label {
                Layout.fillWidth: true
                text: controllerState
                color: "#80cbc4"
            }

            CheckBox {
                text: "Enable gearbox sound"
                checked: config[0] !== 0
                enabled: !pending
                onToggled: soundPage.setConfigValue(0, checked ? 1 : 0)
            }

            Repeater {
                model: fields

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: modelData.label
                    }

                    DoubleSpinBox {
                        id: valueBox
                        objectName: "gearboxValue" + modelData.index
                        Layout.preferredWidth: modelData.index === 4 ? 185 : 145
                        Layout.preferredHeight: implicitHeight
                        enabled: !pending
                        decimals: modelData.decimals
                        realFrom: modelData.min
                        realTo: modelData.max
                        realStepSize: modelData.step
                        suffix: modelData.suffix
                        onRealValueChanged: soundPage.setConfigValue(modelData.index, realValue)

                        Binding {
                            target: valueBox
                            property: "realValue"
                            value: config[modelData.index]
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Match ERPM per km/h to your wheel and reduction ratio. Levels limit the sum of all four tone amplitudes. " +
                      "Apply changes while stopped with the throttle released to save them across restarts."
                color: "#bdbdbd"
            }

            RowLayout {
                Layout.fillWidth: true

                Button {
                    text: "Apply and save"
                    Layout.fillWidth: true
                    enabled: connected && !pending
                    onClicked: soundPage.applyConfig()
                }

                Button {
                    text: "Defaults"
                    enabled: !pending
                    onClicked: {
                        soundPage.config = defaults.slice(0)
                        soundPage.configStatus = "Defaults selected; press Apply and save"
                    }
                }
            }

            Button {
                text: "Read from controller"
                Layout.fillWidth: true
                enabled: connected && !pending
                onClicked: soundPage.requestConfig()
            }

            Label {
                Layout.fillWidth: true
                text: configStatus
                color: "#80cbc4"
                wrapMode: Text.WordWrap
            }
        }
    }
}
