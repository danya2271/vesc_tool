import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.3
import QtQuick.Dialogs 1.3 as Dl
import Qt.labs.folderlistmodel 2.1
import Qt.labs.settings 1.0 as QSettings

import Vedder.vesc.vescinterface 1.0
import Vedder.vesc.commands 1.0
import Vedder.vesc.utility 1.0
import Vedder.vesc.codeloader 1.0
import Vedder.vesc.logwriter 1.0

Item {
    id: lispPageItem

    property var dialogParent: ApplicationWindow.overlay
    property Commands mCommands: VescIf.commands()
    property string currentFilePath: ""
    property string consoleText: ""
    property real lispCpuUse: 0
    property real lispHeapUse: 0
    property real lispMemUse: 0
    property real lispStackUse: 0
    property string lispDoneCtxR: ""
    property bool lispHeaderStatsVisible: true
    property int statsPollHz: 2
    property int editorFontSize: 12
    property bool tractionControlEnabled: true
    property bool accelerationLimitEnabled: true
    property real tractionMaxAccelMs2: 1.5
    property real tractionAccelSoftBandMs2: 0.5
    property real tractionSlipThresholdErpm: 400.0
    property real tractionPenaltyFactor: 0.1
    property real tractionRecoveryRate: 0.02
    property real tractionEnvelopeSoftBandErpm: 200.0
    property string tractionConfigStatus: "Load the traction preset first"
    property string tractionControllerState: "Controller state: unknown"
    property bool tractionConfigPending: false
    property bool tractionConfigReadPending: false
    property string tractionSaveResult: ""

    function requestTractionConfig() {
        if (!VescIf.isPortConnected() || tractionConfigPending || tractionConfigReadPending) {
            return
        }
        tractionConfigReadPending = true
        tractionSaveResult = ""
        tractionConfigStatus = "Reading from LispBM..."
        tractionConfigTimeoutTimer.restart()
        mCommands.lispSendReplCmd("(tc-get-config)")
    }

    function handleTractionReply(str) {
        if (!tractionConfigPending && !tractionConfigReadPending) {
            return
        }
        if (str.indexOf("TC_CONFIG_SAVED") >= 0) {
            tractionSaveResult = "Saved to controller EEPROM"
        } else if (str.indexOf("TC_CONFIG_SAVE_FAILED") >= 0) {
            tractionSaveResult = "Applied in RAM; EEPROM save failed"
        } else if (str.indexOf("TC_CONFIG_APPLIED_RAM_ONLY") >= 0) {
            tractionSaveResult = "Applied in RAM only; stop and release throttle to save"
        }

        var match = str.match(/TC_CONFIG\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)/)
        if (match) {
            var values = []
            for (var index = 1; index <= 8; index++) {
                var value = Number(match[index])
                if (!isFinite(value)) {
                    return
                }
                values.push(value)
            }
            tractionControlEnabled = values[0] !== 0
            accelerationLimitEnabled = values[1] !== 0
            tractionMaxAccelMs2 = values[2]
            tractionAccelSoftBandMs2 = values[3]
            tractionSlipThresholdErpm = values[4]
            tractionPenaltyFactor = values[5]
            tractionRecoveryRate = values[6]
            tractionEnvelopeSoftBandErpm = values[7]
            tractionControllerState = "Controller: TC " + (values[0] !== 0 ? "ON" : "OFF") +
                                     "; acceleration limit " + (values[1] !== 0 ? "ON" : "OFF")
            tractionConfigStatus = tractionSaveResult.length > 0 ? tractionSaveResult :
                                   (tractionConfigPending ? "Applied; EEPROM save not confirmed" : "Read from LispBM")
            tractionConfigPending = false
            tractionConfigReadPending = false
            tractionConfigTimeoutTimer.stop()
        }
    }

    function fileUrlToPath(url) {
        var path = decodeURIComponent(url.toString())
        if (path.startsWith("file://")) {
            path = path.substring(7)
        }

        if (Qt.platform.os === "windows" && path.length > 2 && path[0] === "/" && path[2] === ":") {
            path = path.substring(1)
        }

        return path
    }

    function pathDir(path) {
        var slash = path.lastIndexOf("/")
        var backslash = path.lastIndexOf("\\")
        var ind = Math.max(slash, backslash)
        if (ind > 0) {
            return path.substring(0, ind)
        }

        return ""
    }

    function addRecent(path) {
        if (path.length === 0) {
            return
        }

        var arr = []
        try {
            arr = JSON.parse(recentSettings.recentFiles)
        } catch (e) {
            arr = []
        }

        var filtered = []
        for (var i = 0; i < arr.length; i++) {
            if (arr[i] !== path) {
                filtered.push(arr[i])
            }
        }

        filtered.unshift(path)
        if (filtered.length > 40) {
            filtered = filtered.slice(0, 40)
        }

        recentSettings.recentFiles = JSON.stringify(filtered)
        updateRecentModel("")
    }

    function updateRecentModel(filter) {
        recentModel.clear()

        var arr = []
        try {
            arr = JSON.parse(recentSettings.recentFiles)
        } catch (e) {
            arr = []
        }

        var flt = filter.toLowerCase()

        for (var i = 0; i < arr.length; i++) {
            var path = arr[i]
            if (flt.length === 0 || path.toLowerCase().indexOf(flt) >= 0) {
                recentModel.append({"path": path})
            }
        }
    }

    function openFilePath(path) {
        var data = Utility.readAllFromFile(path)
        editorText.text = Utility.arr2str(data)
        currentFilePath = path
        addRecent(path)
    }

    function appendConsole(text) {
        if (consoleText.length > 0) {
            consoleText += "\n"
        }
        consoleText += text

        var lines = consoleText.split("\n")
        if (lines.length > 5000) {
            lines = lines.slice(lines.length - 5000)
            consoleText = lines.join("\n")
        }
    }

    function increaseEditorFont() {
        editorFontSize = Math.min(36, editorFontSize + 1)
    }

    function decreaseEditorFont() {
        editorFontSize = Math.max(8, editorFontSize - 1)
    }

    Timer {
        id: workaroundTimerUpload
        interval: 0
        repeat: false
        running: false
        onTriggered: {
            var editorPath = currentFilePath.length > 0 ? pathDir(currentFilePath) : ""

            disableDialog()
            dlDialog.title = "Uploading..."
            var ok = mLoader.lispUploadString(editorText.text, editorPath, reduceLispBox.checked)
            enableDialog()

            if (ok && autoRunBox.checked) {
                mCommands.lispSetRunning(1)
            }
        }
    }

    Timer {
        id: workaroundTimerStream
        interval: 0
        repeat: false
        running: false
        onTriggered: {
            var editorPath = currentFilePath.length > 0 ? pathDir(currentFilePath) : ""

            disableDialog()
            dlDialog.title = "Streaming..."
            dlProgBar.indeterminate = true
            mLoader.lispStreamString(editorText.text, 0)
            enableDialog()
        }
    }

    Timer {
        id: workaroundTimerRead
        interval: 0
        repeat: false
        running: false
        onTriggered: {
            var editorPath = currentFilePath.length > 0 ? pathDir(currentFilePath) : ""

            disableDialog()
            dlDialog.title = "Reading..."
            var res = mLoader.lispReadWithPath()
            if (res.code && res.code.length > 0) {
                editorText.text = res.code
                currentFilePath = res.path
            }
            enableDialog()
        }
    }

    Timer {
        id: tractionConfigRefreshTimer
        interval: 750
        repeat: false
        onTriggered: requestTractionConfig()
    }

    Timer {
        id: tractionConfigTimeoutTimer
        interval: 6000
        repeat: false
        onTriggered: {
            tractionConfigStatus = tractionSaveResult.length > 0 ? tractionSaveResult + "; readback timed out" :
                                   "No acknowledgement. Upload and run the updated smart traction preset; check REPL errors."
            tractionConfigPending = false
            tractionConfigReadPending = false
        }
    }

    QSettings.Settings {
        id: recentSettings
        property string recentFiles: "[]"
    }

    ListModel {
        id: recentModel
    }

    ListModel {
        id: bindingModel
    }

    CodeLoader {
        id: mLoader
        Component.onCompleted: {
            mLoader.setVesc(VescIf)
            updateRecentModel("")
        }
    }

    Connections {
        target: mLoader

        function onDownloadProgress (bytesReceived, bytesTotal) {
            dlProgBar.indeterminate = false
            dlProgBar.to = bytesTotal
            dlProgBar.value = bytesReceived
        }

        function onLispUploadProgress (bytes, bytesTotal) {
            dlProgBar.indeterminate = false
            dlProgBar.to = bytesTotal
            dlProgBar.value = bytes
        }
    }

    Dialog {
        id: dlDialog
        title: "Processing..."
        closePolicy: Popup.NoAutoClose
        standardButtons: Dialog.Cancel
        modal: true
        focus: true
        Overlay.modal: Rectangle {
            color: "#AA000000"
        }

        width: parent.width - 20
        x: 10
        y: parent.height / 2 - height / 2
        parent: dialogParent

        ProgressBar {
            id: dlProgBar
            anchors.fill: parent
            indeterminate: false
            from: 0
            to: 1000
            value: 100
        }

        onRejected: {
            mLoader.abortDownloadUpload()
        }
    }

    function disableDialog() {
        dlDialog.open()
        column.enabled = false
    }

    function enableDialog() {
        dlDialog.close()
        column.enabled = true
    }

    Timer {
        id: statsPollTimer
        interval: Math.max(50, Math.round(1000 / Math.max(1, statsPollHz)))
        repeat: true
        running: lispPageItem.visible && pollStatsBox.checked
        onTriggered: {
            if (VescIf.isPortConnected() && pollStatsBox.checked) {
                mCommands.lispGetStats(lispTabBar.currentIndex === 2 && allGlobalsBox.checked)
            }
        }
    }

    ColumnLayout {
        id: column

        anchors.fill: parent
        anchors.leftMargin: 10 + notchLeft
        anchors.rightMargin: 10 + notchRight
        spacing: 0

        // Live Telemetry Banner
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            color: "#161b17"
            radius: 3
            visible: lispHeaderStatsVisible

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 10

                RowLayout {
                    spacing: 4
                    Label {
                        text: "CPU:"
                        font.pixelSize: 11
                        color: "#9e9e9e"
                    }
                    Label {
                        text: lispCpuUse.toFixed(1) + "%"
                        font.pixelSize: 11
                        font.bold: true
                        color: lispCpuUse > 85 ? "#ff5252" : (lispCpuUse > 60 ? "#ffb300" : "#00e676")
                    }
                }

                RowLayout {
                    spacing: 4
                    Label {
                        text: "Heap:"
                        font.pixelSize: 11
                        color: "#9e9e9e"
                    }
                    Label {
                        text: lispHeapUse.toFixed(1) + "%"
                        font.pixelSize: 11
                        font.bold: true
                        color: lispHeapUse > 85 ? "#ff5252" : (lispHeapUse > 60 ? "#ffb300" : "#00e676")
                    }
                }

                RowLayout {
                    spacing: 4
                    Label {
                        text: "Mem:"
                        font.pixelSize: 11
                        color: "#9e9e9e"
                    }
                    Label {
                        text: lispMemUse.toFixed(1) + "%"
                        font.pixelSize: 11
                        font.bold: true
                        color: lispMemUse > 85 ? "#ff5252" : (lispMemUse > 60 ? "#ffb300" : "#00e676")
                    }
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: lispDoneCtxR.length > 0 ? ("Res: " + lispDoneCtxR) : ""
                    font.pixelSize: 10
                    color: "#80cbc4"
                    elide: Text.ElideRight
                    Layout.maximumWidth: 140
                }
            }
        }

        TabBar {
            id: lispTabBar
            Layout.fillWidth: true
            onCurrentIndexChanged: {
                if (currentIndex === 3) {
                    tractionConfigRefreshTimer.restart()
                } else if (currentIndex === 2 && VescIf.isPortConnected()) {
                    mCommands.lispGetStats(allGlobalsBox.checked)
                }
            }

            TabButton {
                text: "Editor"
            }

            TabButton {
                text: "REPL"
            }

            TabButton {
                text: "Stats"
            }

            TabButton {
                text: "Traction"
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: lispTabBar.currentIndex

            // === Editor tab ===
            ColumnLayout {
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true

                    CheckBox {
                        id: autoRunBox
                        text: "Auto Run"
                        checked: true
                    }

                    CheckBox {
                        id: reduceLispBox
                        text: "Reduce"
                        checked: false
                    }

                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: currentFilePath.length > 0 ? currentFilePath : "Unnamed"
                        elide: Text.ElideLeft
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    TextArea {
                        id: editorText
                        wrapMode: TextArea.NoWrap
                        font.family: "DejaVu Sans Mono"
                        font.pointSize: editorFontSize
                        selectByMouse: (Qt.platform.os === "ios" || Qt.platform.os === "android") ? false : true
                        persistentSelection: true
                        color: Utility.getAppHexColor("lightText")
                        inputMethodHints: Qt.ImhNoPredictiveText
                        readOnly: false
                        activeFocusOnPress: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8

                    Button {
                        text: "Upload"
                        Layout.fillWidth: true
                        onClicked: workaroundTimerUpload.start()
                    }

                    Button {
                        text: "Read"
                        Layout.fillWidth: true
                        onClicked: workaroundTimerRead.start()
                    }

                    Button {
                        text: "Erase"
                        Layout.fillWidth: true
                        onClicked: mLoader.lispErase(16)
                    }

                    Button {
                        text: "Stream"
                        Layout.fillWidth: true
                        onClicked: workaroundTimerStream.start()
                    }

                    Button {
                        text: "..."
                        Layout.preferredWidth: 52
                        onClicked: pageMenu.open()

                        Menu {
                            id: pageMenu
                            leftPadding: notchLeft
                            rightPadding: notchRight
                            parent: lispPageItem
                            y: parent.height - implicitHeight
                            width: parent.width

                            MenuItem {
                                text: "Run"
                                onTriggered: mCommands.lispSetRunning(1)
                            }

                            MenuItem {
                                text: "Stop"
                                onTriggered: mCommands.lispSetRunning(0)
                            }

                            MenuItem {
                                text: "Open File..."
                                onTriggered: {
                                    if (Utility.requestFilePermission()) {
                                        fileDialogLoad.close()
                                        fileDialogLoad.open()
                                    } else {
                                        VescIf.emitMessageDialog(
                                                    "File Permissions",
                                                    "Unable to request file system permission.",
                                                    false, false)
                                    }
                                }
                            }

                            MenuItem {
                                text: "Save File as..."
                                onTriggered: {
                                    if (Utility.requestFilePermission()) {
                                        fileDialogSave.close()
                                        fileDialogSave.open()
                                    } else {
                                        VescIf.emitMessageDialog(
                                                    "File Permissions",
                                                    "Unable to request file system permission.",
                                                    false, false)
                                    }
                                }

                                LogWriter {
                                    id: mLogWriter
                                }

                                Dl.FileDialog {
                                    id: fileDialogSave
                                    title: "Please choose a file"
                                    nameFilters: ["LBM files (*.lbm *.lisp)"]
                                    selectExisting: false
                                    selectMultiple: false
                                    onAccepted: {
                                        var path = fileUrl.toString()

                                        var okOpen = mLogWriter.openLogFileFullPath(path)
                                        var okWrite = mLogWriter.writeToLogFile(editorText.text)
                                        mLogWriter.closeLogFile()

                                        if (okOpen && okWrite) {
                                            VescIf.emitStatusMessage("LBM-file Saved", true)
                                        } else {
                                            VescIf.emitStatusMessage("LBM-file Save Failed", false)
                                        }

                                        close()
                                        parent.forceActiveFocus()
                                    }

                                    onRejected: {
                                        close()
                                        parent.forceActiveFocus()
                                    }
                                }
                            }

                            MenuItem {
                                text: "Open Recent..."
                                onTriggered: {
                                    updateRecentModel(recentFilter.text)
                                    recentDialog.open()
                                }
                            }

                            MenuItem {
                                text: "Open Example..."
                                onTriggered: {
                                    exampleDialog.open()
                                }
                            }

                            MenuItem {
                                text: "Open Smart Traction Preset"
                                onTriggered: {
                                    editorText.text = Utility.arr2str(
                                                Utility.readAllFromFile(
                                                    ":/res/LispBM/Presets/smart_throttle_traction_control.lbm"))
                                    currentFilePath = ""
                                }
                            }

                            MenuItem {
                                text: "Close File"
                                enabled: currentFilePath.length > 0 || editorText.text.length > 0
                                onTriggered: {
                                    editorText.text = ""
                                    currentFilePath = ""
                                }
                            }

                            MenuItem {
                                text: "Text Size +"
                                onTriggered: increaseEditorFont()
                            }

                            MenuItem {
                                text: "Text Size -"
                                onTriggered: decreaseEditorFont()
                            }

                            MenuItem {
                                text: "Help"
                                onTriggered: {
                                    VescIf.emitMessageDialog(
                                                "VESC LispBM Editor",
                                                "For documentation, see:<br>" +
                                                "<a href=\"https://github.com/vedderb/bldc/blob/master/lispBM/README.md\">" +
                                                "https://github.com/vedderb/bldc/blob/master/lispBM/README.md</a>",
                                                true,
                                                true)
                                }
                            }
                        }
                    }
                }
            }

            // === REPL tab ===
            ColumnLayout {
                ScrollView {
                    id: replScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    TextArea {
                        text: consoleText
                        readOnly: true
                        wrapMode: TextArea.NoWrap
                        font.family: "DejaVu Sans Mono"
                        color: Utility.getAppHexColor("lightText")
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    TextField {
                        id: replInput
                        Layout.fillWidth: true
                        placeholderText: "REPL command"
                        onAccepted: {
                            if (text.length > 0) {
                                mCommands.lispSendReplCmd(text)
                                text = ""
                            }
                        }
                    }

                    Button {
                        text: "Send"
                        onClicked: {
                            if (replInput.text.length > 0) {
                                mCommands.lispSendReplCmd(replInput.text)
                                replInput.text = ""
                            }
                        }
                    }

                    Button {
                        text: "..."
                        Layout.preferredWidth: 52
                        onClicked: replMenu.open()

                        Menu {
                            id: replMenu
                            leftPadding: notchLeft
                            rightPadding: notchRight
                            parent: replScroll
                            y: parent.height - implicitHeight
                            width: parent.width

                            MenuItem {
                                text: ":help"
                                onTriggered: mCommands.lispSendReplCmd(":help")
                            }

                            MenuItem {
                                text: "Clear"
                                onTriggered: consoleText = ""
                            }
                        }
                    }
                }
            }

            // === Stats tab ===
            ColumnLayout {
                id: statsTabItem
                spacing: 8

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    rowSpacing: 4
                    columnSpacing: 10

                    Label {
                        text: "CPU Usage:"
                        font.bold: true
                    }
                    Label {
                        Layout.alignment: Qt.AlignRight
                        text: lispCpuUse.toFixed(1) + "%"
                        font.bold: true
                        color: lispCpuUse > 85 ? "#ff5252" : (lispCpuUse > 60 ? "#ffb300" : "#00e676")
                    }

                    ProgressBar {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        from: 0
                        to: 100
                        value: lispCpuUse
                    }

                    Label {
                        text: "Heap Usage:"
                        font.bold: true
                    }
                    Label {
                        Layout.alignment: Qt.AlignRight
                        text: lispHeapUse.toFixed(1) + "%"
                        font.bold: true
                        color: lispHeapUse > 85 ? "#ff5252" : (lispHeapUse > 60 ? "#ffb300" : "#00e676")
                    }

                    ProgressBar {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        from: 0
                        to: 100
                        value: lispHeapUse
                    }

                    Label {
                        text: "Memory Usage:"
                        font.bold: true
                    }
                    Label {
                        Layout.alignment: Qt.AlignRight
                        text: lispMemUse.toFixed(1) + "%"
                        font.bold: true
                        color: lispMemUse > 85 ? "#ff5252" : (lispMemUse > 60 ? "#ffb300" : "#00e676")
                    }

                    ProgressBar {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        from: 0
                        to: 100
                        value: lispMemUse
                    }

                    Label {
                        text: "Stack Usage:"
                        font.bold: true
                    }
                    Label {
                        Layout.alignment: Qt.AlignRight
                        text: lispStackUse.toFixed(1) + "%"
                        font.bold: true
                        color: lispStackUse > 85 ? "#ff5252" : (lispStackUse > 60 ? "#ffb300" : "#00e676")
                    }

                    ProgressBar {
                        Layout.columnSpan: 2
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        from: 0
                        to: 100
                        value: lispStackUse
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: lispDoneCtxR.length > 0
                    Label {
                        text: "Last Eval Result:"
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        text: lispDoneCtxR
                        color: "#80cbc4"
                        elide: Text.ElideRight
                    }
                }

                Label {
                    text: "Global Variables (" + bindingModel.count + ")"
                    font.bold: true
                    Layout.fillWidth: true
                }

                ListView {
                    id: bindingListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 1
                    model: bindingModel

                    delegate: Rectangle {
                        width: bindingListView.width
                        height: 26
                        color: "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4

                            Label {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1500
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: name + ": "
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1500
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignLeft
                                text: parseFloat(value).toFixed(6)
                            }
                        }
                    }
                }

                CheckBox {
                    id: allGlobalsBox
                    text: "All globals (firmware may truncate the list)"
                    checked: false
                    onCheckedChanged: {
                        if (VescIf.isPortConnected()) {
                            mCommands.lispGetStats(checked)
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    CheckBox {
                        id: pollStatsBox
                        text: "Auto Poll"
                        checked: true
                    }

                    Label {
                        text: "Hz"
                    }

                    ComboBox {
                        id: pollHzBox
                        Layout.fillWidth: true
                        model: [1, 2, 5, 10]
                        currentIndex: 1
                        onCurrentTextChanged: {
                            statsPollHz = parseInt(currentText)
                        }
                    }

                    Button {
                        text: "Refresh"
                        onClicked: mCommands.lispGetStats(allGlobalsBox.checked)
                    }
                }
            }

            // === Traction control tab ===
            ColumnLayout {
                spacing: 8

                ScrollView {
                    id: tractionScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth
                    clip: true

                    ColumnLayout {
                        width: tractionScroll.availableWidth
                        spacing: 8

                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: "These controls configure the smart throttle preset. " +
                                  "Without a wheel-speed sensor, traction control is an ERPM-based estimate."
                            color: "#bdbdbd"
                        }

                        Label {
                            Layout.fillWidth: true
                            text: tractionControllerState
                            color: "#80cbc4"
                        }

                        CheckBox {
                            id: tractionEnabledBox
                            text: "Enable traction control"
                            checked: tractionControlEnabled
                            onCheckedChanged: tractionControlEnabled = checked
                        }

                        CheckBox {
                            id: accelerationLimitEnabledBox
                            text: "Enable maximum acceleration limit"
                            checked: accelerationLimitEnabled
                            onCheckedChanged: accelerationLimitEnabled = checked
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: "Maximum acceleration"
                            }
                            DoubleSpinBox {
                                id: tractionMaxAccelBox
                                Layout.preferredWidth: 145
                                Layout.preferredHeight: implicitHeight
                                decimals: 2
                                realFrom: 0.1
                                realTo: 10.0
                                realStepSize: 0.1
                                realValue: tractionMaxAccelMs2
                                suffix: " m/s²"
                                onRealValueChanged: tractionMaxAccelMs2 = realValue
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: "Acceleration recovery band"
                            }
                            DoubleSpinBox {
                                id: tractionAccelBandBox
                                Layout.preferredWidth: 145
                                Layout.preferredHeight: implicitHeight
                                decimals: 2
                                realFrom: 0.1
                                realTo: 3.0
                                realStepSize: 0.1
                                realValue: tractionAccelSoftBandMs2
                                suffix: " m/s²"
                                onRealValueChanged: tractionAccelSoftBandMs2 = realValue
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: "TC intervention threshold"
                            }
                            DoubleSpinBox {
                                id: tractionSlipThresholdBox
                                Layout.preferredWidth: 145
                                Layout.preferredHeight: implicitHeight
                                decimals: 0
                                realFrom: 0.0
                                realTo: 3000.0
                                realStepSize: 25.0
                                realValue: tractionSlipThresholdErpm
                                suffix: " ERPM"
                                onRealValueChanged: tractionSlipThresholdErpm = realValue
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: "Slip penalty"
                            }
                            DoubleSpinBox {
                                id: tractionPenaltyBox
                                Layout.preferredWidth: 145
                                Layout.preferredHeight: implicitHeight
                                decimals: 2
                                realFrom: 0.01
                                realTo: 1.0
                                realStepSize: 0.01
                                realValue: tractionPenaltyFactor
                                onRealValueChanged: tractionPenaltyFactor = realValue
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: "Recovery rate"
                            }
                            DoubleSpinBox {
                                id: tractionRecoveryBox
                                Layout.preferredWidth: 145
                                Layout.preferredHeight: implicitHeight
                                decimals: 3
                                realFrom: 0.001
                                realTo: 1.0
                                realStepSize: 0.005
                                realValue: tractionRecoveryRate
                                onRealValueChanged: tractionRecoveryRate = realValue
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true
                                text: "TC reduction band"
                            }
                            DoubleSpinBox {
                                id: tractionEnvelopeBandBox
                                Layout.preferredWidth: 145
                                Layout.preferredHeight: implicitHeight
                                decimals: 0
                                realFrom: 1.0
                                realTo: 3000.0
                                realStepSize: 25.0
                                realValue: tractionEnvelopeSoftBandErpm
                                suffix: " ERPM"
                                onRealValueChanged: tractionEnvelopeSoftBandErpm = realValue
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            Button {
                                text: "Apply and save"
                                Layout.fillWidth: true
                                enabled: !tractionConfigPending && !tractionConfigReadPending
                                onClicked: {
                                    if (!VescIf.isPortConnected()) {
                                        tractionConfigStatus = "Not connected"
                                        return
                                    }
                                    tractionConfigPending = true
                                    tractionSaveResult = ""
                                    tractionConfigStatus = "Waiting for controller acknowledgement..."
                                    tractionConfigTimeoutTimer.restart()
                                    mCommands.lispSetTractionControlConfig(
                                                tractionControlEnabled,
                                                accelerationLimitEnabled,
                                                tractionMaxAccelMs2,
                                                tractionAccelSoftBandMs2,
                                                tractionSlipThresholdErpm,
                                                tractionPenaltyFactor,
                                                tractionRecoveryRate,
                                                tractionEnvelopeSoftBandErpm)
                                }
                            }

                            Button {
                                text: "Defaults"
                                enabled: !tractionConfigPending && !tractionConfigReadPending
                                onClicked: {
                                    tractionControlEnabled = true
                                    accelerationLimitEnabled = true
                                    tractionMaxAccelMs2 = 1.5
                                    tractionAccelSoftBandMs2 = 0.5
                                    tractionSlipThresholdErpm = 400.0
                                    tractionPenaltyFactor = 0.1
                                    tractionRecoveryRate = 0.02
                                    tractionEnvelopeSoftBandErpm = 200.0
                                    tractionConfigStatus = "Defaults selected; press Apply and save"
                                }
                            }
                        }

                        Button {
                            text: "Read from controller"
                            Layout.fillWidth: true
                            enabled: !tractionConfigPending && !tractionConfigReadPending
                            onClicked: requestTractionConfig()
                        }

                        Label {
                            Layout.fillWidth: true
                            text: tractionConfigStatus
                            color: "#80cbc4"
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: mCommands

        function onLispPrintReceived(str) {
            appendConsole(str)
            handleTractionReply(str)
        }

        function onLispRunningResRx(ok) {
            if (!ok) {
                VescIf.emitMessageDialog("Start/Stop LispBM",
                                         "Start/Stop LispBM failed. Did you forget to upload the code?",
                                         false, false)
            }
        }

        function onLispStatsRxMap(stats) {
            if (stats.cpu_use !== undefined) {
                lispCpuUse = stats.cpu_use
            }

            if (stats.heap_use !== undefined) {
                lispHeapUse = stats.heap_use
            }

            if (stats.mem_use !== undefined) {
                lispMemUse = stats.mem_use
            }

            if (stats.stack_use !== undefined) {
                lispStackUse = stats.stack_use
            }

            if (stats.done_ctx_r !== undefined) {
                lispDoneCtxR = stats.done_ctx_r
            }

            if (lispTabBar.currentIndex !== 2 || stats.globals === undefined || stats.globals === null) {
                return
            }

            bindingModel.clear()
            for (var i = 0; i < stats.globals.length; i++) {
                var g = stats.globals[i]
                if (g.name !== undefined && g.value !== undefined) {
                    bindingModel.append({"name": g.name, "value": g.value})
                }
            }
        }

        function onLispStatsRx(stats) {
            if (stats.cpu_use !== undefined) {
                lispCpuUse = stats.cpu_use
            }
            if (stats.heap_use !== undefined) {
                lispHeapUse = stats.heap_use
            }
            if (stats.mem_use !== undefined) {
                lispMemUse = stats.mem_use
            }
            if (stats.stack_use !== undefined) {
                lispStackUse = stats.stack_use
            }
            if (stats.done_ctx_r !== undefined) {
                lispDoneCtxR = stats.done_ctx_r
            }
        }
    }

    Dl.FileDialog {
        id: fileDialogLoad
        title: "Open LispBM File"
        nameFilters: ["LispBM files (*.lbm *.lisp)", "All files (*)"]
        selectExisting: true
        selectMultiple: false

        onAccepted: {
            var path = fileUrlToPath(fileUrl)
            openFilePath(path)
            close()
            parent.forceActiveFocus()
        }

        onRejected: {
            close()
            parent.forceActiveFocus()
        }
    }

    Dialog {
        id: recentDialog
        modal: true
        focus: true
        title: "Recent Files"
        closePolicy: Popup.CloseOnEscape
        standardButtons: Dialog.Cancel
        Overlay.modal: Rectangle { color: "#AA000000" }
        parent: lispPageItem

        width: parent.width - 20 - notchLeft - notchRight
        height: Math.min(parent.height - 40, 450)
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        ColumnLayout {
            anchors.fill: parent

            TextField {
                id: recentFilter
                Layout.fillWidth: true
                placeholderText: "Filter"
                onTextChanged: updateRecentModel(text)
            }

            ListView {
                id: recentListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: recentModel

                delegate: ItemDelegate {
                    width: recentListView.width
                    text: path
                    onClicked: {
                        openFilePath(path)
                        recentDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: exampleDialog
        modal: true
        focus: true
        title: "Examples"
        closePolicy: Popup.CloseOnEscape
        standardButtons: Dialog.Cancel
        Overlay.modal: Rectangle { color: "#AA000000" }
        parent: lispPageItem

        width: parent.width - 20 - notchLeft - notchRight
        height: Math.min(parent.height - 40, 500)
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        ColumnLayout {
            anchors.fill: parent

            TextField {
                id: exampleFilter
                Layout.fillWidth: true
                placeholderText: "Filter"
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: FolderListModel {
                    id: exampleModel
                    folder: "qrc:/res/LispBM/Examples"
                    nameFilters: ["*.lbm", "*.lisp"]
                    showDirs: false
                    sortField: FolderListModel.Name
                }

                delegate: ItemDelegate {
                    visible: exampleFilter.text.length === 0 ||
                             fileName.toLowerCase().indexOf(exampleFilter.text.toLowerCase()) >= 0
                    height: visible ? implicitHeight : 0
                    text: fileName
                    onClicked: {
                        editorText.text = Utility.arr2str(Utility.readAllFromFile(filePath))
                        currentFilePath = ""
                        exampleDialog.close()
                    }
                }
            }
        }
    }
}
