import QtQuick 2.15
import QtTest 1.2
import "../../mobile" as Mobile

TestCase {
    name: "GearboxSound"
    width: 420
    height: 780
    when: windowShown

    QtObject {
        id: commands
        property string lastCommand: ""
        property var lastConfig: []
        signal lispPrintReceived(string str)
        function lispSendReplCmd(command) { lastCommand = command }
        function lispSetGearboxSoundConfig() { lastConfig = Array.prototype.slice.call(arguments) }
    }

    Mobile.GearboxSound {
        id: page
        anchors.fill: parent
        mCommands: commands
        connected: true
    }

    function init() {
        page.connected = false
        page.connected = true
        page.config = page.defaults.slice(0)
        commands.lastCommand = ""
        commands.lastConfig = []
    }

    function reply(values) {
        // Match the actual VESC print extension and COMM_LISP_PRINT payload.
        commands.lispPrintReceived('"GS_CONFIG_V1 ' + values.join(" ") + '"\u0000')
    }

    function test_readback_formats_data() {
        return [
            {tag: "desktop", prefix: "", suffix: ""},
            {tag: "firmware", prefix: '"', suffix: '"'},
            {tag: "firmware_nul", prefix: '"', suffix: '"\u0000'},
            {tag: "repl", prefix: '> "', suffix: '"\r\n'},
            {tag: "combined_messages", prefix: '"GS_CONFIG_SAVED"\r\n"', suffix: '"\u0000'}
        ]
    }

    function test_readback_formats(data) {
        page.requestConfig()
        commands.lispPrintReceived(data.prefix + "GS_CONFIG_V1 " + page.defaults.join(" ") + data.suffix)
        verify(!page.pending)
        compare(page.controllerState, "Controller sound: ON")
        compare(page.config[9], 0.12)
    }

    function test_readback() {
        page.requestConfig()
        compare(commands.lastCommand, "(gs-get-config)")
        verify(page.pending)
        reply([0, 12, 70, 3, 380, 0.01, 1, 200, 1200, 0.15])
        compare(page.config[1], 12)
        compare(page.config[5], 0.01)
        compare(page.controllerState, "Controller sound: OFF")
        compare(page.configStatus, "Read from controller")
        verify(!page.pending)
    }

    function test_save_requires_acknowledgement() {
        page.applyConfig()
        compare(commands.lastConfig.length, 10)
        compare(commands.lastConfig[0], true)
        reply(page.defaults)
        compare(page.configStatus, "Applied; EEPROM save not confirmed")
    }

    function test_eeprom_save() {
        page.applyConfig()
        commands.lispPrintReceived("GS_CONFIG_SAVED")
        verify(page.pending)
        reply(page.defaults)
        compare(page.configStatus, "Saved to controller EEPROM")
    }

    function test_ram_only_and_save_failure_data() {
        return [
            {tag: "moving", marker: "GS_CONFIG_APPLIED_RAM_ONLY_STOP_VEHICLE_TO_SAVE", status: "Applied in RAM only"},
            {tag: "failure", marker: "GS_CONFIG_SAVE_FAILED", status: "EEPROM save failed"}
        ]
    }

    function test_ram_only_and_save_failure(data) {
        page.applyConfig()
        commands.lispPrintReceived(data.marker + "\nGS_CONFIG_V1 " + page.defaults.join(" "))
        verify(page.configStatus.indexOf(data.status) >= 0)
        verify(!page.pending)
    }

    function test_invalid_settings() {
        page.setConfigValue(2, page.config[1])
        page.applyConfig()
        verify(!page.pending)
        compare(commands.lastConfig.length, 0)
        page.config = page.defaults.slice(0)
        page.setConfigValue(6, 0.001)
        page.applyConfig()
        compare(commands.lastConfig.length, 0)
    }

    function test_malformed_readback() {
        page.requestConfig()
        reply([1, 10, 60])
        verify(page.pending)
        reply([1, 10, 60, 4, 358, "NaN", 1.15, 220, 1500, 0.12])
        verify(page.pending)
        reply([1, 60, 10, 4, 358, 0.02, 1.15, 220, 1500, 0.12])
        verify(page.pending)
        reply(page.defaults)
        verify(!page.pending)
    }

    function test_disconnect_and_unsolicited_reply() {
        page.requestConfig()
        page.connected = false
        verify(!page.pending)
        compare(page.controllerState, "Controller sound: unknown")
        reply([0, 12, 70, 3, 380, 0.01, 1, 200, 1200, 0.15])
        compare(page.config[0], 1)
        compare(page.configStatus, "Not connected")
    }

    function test_controls_follow_readback_after_edit() {
        var preload = findChild(page, "gearboxValue5")
        verify(preload !== null)
        preload.realValue = 0.03
        compare(page.config[5], 0.03)
        page.requestConfig()
        reply([1, 10, 60, 4, 358, 0.01, 1.15, 220, 1500, 0.12])
        compare(preload.realValue, 0.01)
        page.config = page.defaults.slice(0)
        compare(preload.realValue, 0.02)
    }

    function test_controller_rejects_settings() {
        page.applyConfig()
        commands.lispPrintReceived('"GS_CONFIG_INVALID"\u0000')
        verify(!page.pending)
        compare(page.controllerState, "Controller sound: settings rejected")
    }

    function test_timeout() {
        page.requestConfig()
        compare(page.controllerState, "Controller sound: reading...")
        tryCompare(page, "pending", false, 6500)
        compare(page.controllerState, "Controller sound: no response")
        verify(page.configStatus.indexOf("No acknowledgement") >= 0)
    }
}
