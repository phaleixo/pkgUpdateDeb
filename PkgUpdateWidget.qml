import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // ── State ────────────────────────────────────────────────────────────────
    property var aptUpdates: []
    property var flatpakUpdates: []
    property bool aptChecking: true
    property bool flatpakChecking: true

    // ── Settings (from plugin data) ───────────────────────────────────────────
    property string terminalApp: pluginData.terminalApp || "alacritty"
    property int refreshMins: pluginData.refreshMins || 60
    property bool showFlatpak: pluginData.showFlatpak !== undefined ? pluginData.showFlatpak : true

    property int totalUpdates: aptUpdates.length + (showFlatpak ? flatpakUpdates.length : 0)

    popoutWidth: 480

    // ── Periodic refresh ──────────────────────────────────────────────────────
    Timer {
        interval: root.refreshMins * 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkUpdates()
    }

    // Fallback timers: if a command never returns, ensure UI stops showing 'checking'
    Timer {
        id: aptFallbackTimer
        interval: 15000
        running: false
        repeat: false
        onTriggered: {
            if (root.aptChecking) {
                console.log("pkgUpdate: apt fallback timer triggered — clearing aptChecking")
                root.aptChecking = false
                root.aptUpdates = []
            }
        }
    }

    Timer {
        id: flatpakFallbackTimer
        interval: 15000
        running: false
        repeat: false
        onTriggered: {
            if (root.flatpakChecking) {
                console.log("pkgUpdate: flatpak fallback timer triggered — clearing flatpakChecking")
                root.flatpakChecking = false
                root.flatpakUpdates = []
            }
        }
    }

    // ── Update check functions ────────────────────────────────────────────────
    function checkUpdates() {
        // APT
        root.aptChecking = true
        aptFallbackTimer.restart()
        Proc.runCommand("pkgUpdate.apt", ["sh", "-c", "apt list --upgradable 2>/dev/null"], (stdout, exitCode) => {
            console.log("pkgUpdate.apt callback: exitCode=", exitCode)
            console.log("pkgUpdate.apt stdout:\n", stdout)
            try {
                root.aptUpdates = parseAptPackages(stdout)
            } catch (e) {
                console.log("pkgUpdate: parseAptPackages failed:", e)
                root.aptUpdates = []
            }
            root.aptChecking = false
            aptFallbackTimer.stop()
        }, 60000)

        // Flatpak
        if (root.showFlatpak) {
            root.flatpakChecking = true
            flatpakFallbackTimer.restart()
            Proc.runCommand("pkgUpdate.flatpak", ["sh", "-c", "flatpak remote-ls --updates 2>/dev/null"], (stdout, exitCode) => {
                console.log("pkgUpdate.flatpak callback: exitCode=", exitCode)
                console.log("pkgUpdate.flatpak stdout:\n", stdout)
                try {
                    root.flatpakUpdates = parseFlatpakApps(stdout)
                } catch (e) {
                    console.log("pkgUpdate: parseFlatpakApps failed:", e)
                    root.flatpakUpdates = []
                }
                root.flatpakChecking = false
                flatpakFallbackTimer.stop()
            }, 60000)
        } else {
            root.flatpakChecking = false
        }
    }

    function parseAptPackages(stdout) {
        // Adapted for output of `apt list --upgradable`
        if (!stdout || stdout.trim().length === 0)
            return []
        return stdout.trim().split('\n').filter(line => {
            const t = line.trim()
            return t.length > 0 && !t.startsWith('Listing...') && !t.startsWith('N:')
        }).map(line => {
            const parts = line.trim().split(/\s+/)
            // parts[0] tem formato 'nome/remote' -> extrair nome
            const namePart = parts[0] || ''
            const name = namePart.split('/')[0]
            const version = parts[1] || ''
            return {
                name: name,
                version: version,
                repo: ''
            }
        }).filter(p => p.name.length > 0)
    }

    function parseFlatpakApps(stdout) {
        if (!stdout || stdout.trim().length === 0)
            return []
        return stdout.trim().split('\n').filter(line => line.trim().length > 0).map(line => {
            const parts = line.trim().split(/\t|\s{2,}/)
            return {
                name: parts[0] || '',
                branch: parts[1] || '',
                origin: parts[2] || ''
            }
        }).filter(a => a.name.length > 0)
    }

    // ── Terminal launch ───────────────────────────────────────────────────────
    function runAptUpdate() {
        root.closePopout()
        const cmd = "sudo apt update && sudo apt upgrade -y; echo; echo '=== Done. Press Enter to close. ==='; read"
        Quickshell.execDetached(["sh", "-c", root.terminalApp + " -e sh -c '" + cmd + "'"])
    }

    function runFlatpakUpdate() {
        root.closePopout()
        const cmd = "flatpak update -y; echo; echo '=== Done. Press Enter to close. ==='; read"
        Quickshell.execDetached(["sh", "-c", root.terminalApp + " -e sh -c '" + cmd + "'"])
    }

    // ── Bar pills ─────────────────────────────────────────────────────────────
    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.totalUpdates > 0 ? "system_update" : "check_circle"
                color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                size: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.aptChecking || (root.showFlatpak && root.flatpakChecking)) ? "…" : root.totalUpdates.toString()
                    color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                    font.pixelSize: Theme.fontSizeMedium
                }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2
            anchors.horizontalCenter: parent.horizontalCenter

            DankIcon {
                name: root.totalUpdates > 0 ? "system_update" : "check_circle"
                color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                size: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
            }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (root.aptChecking || (root.showFlatpak && root.flatpakChecking)) ? "…" : root.totalUpdates.toString()
                    color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                    font.pixelSize: Theme.fontSizeSmall
                }
        }
    }

    // ── Popout ────────────────────────────────────────────────────────────────
    popoutContent: Component {
        Column {
            width: parent.width
            spacing: Theme.spacingM
            topPadding: Theme.spacingM
            bottomPadding: Theme.spacingM

            // Header card
            Item {
                width: parent.width
                height: 68

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.cornerRadius * 1.5
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.08)
                        }
                    }
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingM

                    Item {
                        width: 40
                        height: 40
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: 20
                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2)
                        }

                        DankIcon {
                            name: "system_update"
                            size: 22
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        StyledText {
                            text: "Package Updates"
                            font.bold: true
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.surfaceText
                        }

                        StyledText {
                            text: root.totalUpdates > 0 ? root.totalUpdates + " update" + (root.totalUpdates !== 1 ? "s" : "") + " available" : "System is up to date"
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.totalUpdates > 0 ? Theme.primary : Theme.secondary
                        }
                    }
                }

                // Refresh button
                Item {
                    width: 32
                    height: 32
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: refreshArea.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.2) : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    DankIcon {
                        name: "refresh"
                        size: 20
                        color: Theme.primary
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: refreshArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.checkUpdates()
                    }
                }
            }

            // ── APT section header ───────────────────────────────────────────
            Item {
                width: parent.width
                height: 36

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 4
                        height: 22
                        radius: 2
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankIcon {
                        name: "archive"
                        size: 20
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "APT"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: aptCountLabel.width + 14
                        height: 20
                        radius: 10
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: aptCountLabel
                            text: root.aptChecking ? "…" : root.aptUpdates.length.toString()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }
                }

                // Update APT button
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: aptBtnRow.width + Theme.spacingM * 2
                    height: 30
                    visible: !root.aptChecking && root.aptUpdates.length > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: aptBtnArea.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    Row {
                        id: aptBtnRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "download"
                            size: 14
                            color: aptBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Update APT"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: aptBtnArea.containsMouse ? "white" : Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: aptBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runAptUpdate()
                    }
                }
            }

                // ── APT update list ──────────────────────────────────────────────
            StyledRect {
                width: parent.width
                height: root.aptChecking ? 52 : (root.aptUpdates.length === 0 ? 46 : Math.min(root.aptUpdates.length * 38 + 8, 180))
                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.aptChecking

                    DankIcon {
                        name: "sync"
                        size: 16
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Checking for updates…"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.aptChecking && root.aptUpdates.length === 0

                    DankIcon {
                        name: "check_circle"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "No updates available"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: root.aptUpdates
                    spacing: 2
                    visible: !root.aptChecking && root.aptUpdates.length > 0

                    delegate: Item {
                        width: ListView.view.width
                        height: 36

                            property string pkgName: modelData.name
                            property string pkgVersion: modelData.version

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "upgrade"
                                size: 14
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: pkgName
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: parent.width - pkgVersionText.implicitWidth - 14 - Theme.spacingS * 2
                            }

                            StyledText {
                                id: pkgVersionText
                                text: pkgVersion
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }

            // ── Flatpak section header ────────────────────────────────────────
            Item {
                width: parent.width
                height: 36
                visible: root.showFlatpak

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 4
                        height: 22
                        radius: 2
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankIcon {
                        name: "apps"
                        size: 20
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Flatpak"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: flatpakCountLabel.width + 14
                        height: 20
                        radius: 10
                        color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: flatpakCountLabel
                            text: root.flatpakChecking ? "…" : root.flatpakUpdates.length.toString()
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.secondary
                            anchors.centerIn: parent
                        }
                    }
                }

                // Update Flatpak button
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: flatpakBtnRow.width + Theme.spacingM * 2
                    height: 30
                    visible: !root.flatpakChecking && root.flatpakUpdates.length > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: flatpakBtnArea.containsMouse ? Theme.secondary : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.4)
                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }

                    Row {
                        id: flatpakBtnRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "download"
                            size: 14
                            color: flatpakBtnArea.containsMouse ? "white" : Theme.secondary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Update Flatpak"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: flatpakBtnArea.containsMouse ? "white" : Theme.secondary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: flatpakBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runFlatpakUpdate()
                    }
                }
            }

            // ── Flatpak update list ──────────────────────────────────────────
            StyledRect {
                width: parent.width
                height: root.flatpakChecking ? 52 : (root.flatpakUpdates.length === 0 ? 46 : Math.min(root.flatpakUpdates.length * 38 + 8, 180))
                radius: Theme.cornerRadius * 1.5
                color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.5)
                border.width: 1
                border.color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.1)
                clip: true
                visible: root.showFlatpak

                Behavior on height {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: root.flatpakChecking

                    DankIcon {
                        name: "sync"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Checking for updates…"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    visible: !root.flatpakChecking && root.flatpakUpdates.length === 0

                    DankIcon {
                        name: "check_circle"
                        size: 16
                        color: Theme.secondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "No updates available"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                ListView {
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    model: root.flatpakUpdates
                    spacing: 2
                    visible: !root.flatpakChecking && root.flatpakUpdates.length > 0

                    delegate: Item {
                        width: ListView.view.width
                        height: 36

                        property string appId: modelData.name
                        property string appOrigin: modelData.origin

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingM
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            DankIcon {
                                name: "extension"
                                size: 14
                                color: Theme.secondary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: appId
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: parent.width - appOriginText.implicitWidth - 14 - Theme.spacingS * 2
                            }

                            StyledText {
                                id: appOriginText
                                text: appOrigin
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}