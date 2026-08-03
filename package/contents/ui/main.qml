import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import "../code/pingstate.js" as PingState

PlasmoidItem {
    id: root

    // ---- configuration ------------------------------------------------
    readonly property string host: Plasmoid.configuration.host
    readonly property int pingInterval: Plasmoid.configuration.pingInterval
    readonly property int pingTimeout: Plasmoid.configuration.pingTimeout

    readonly property var thresholds: ({
        yellowAfter: Plasmoid.configuration.yellowAfter,
        redAfter: Plasmoid.configuration.redAfter,
        recoverAfter: Plasmoid.configuration.recoverAfter,
        yellowMs: Plasmoid.configuration.yellowMs,
        redMs: Plasmoid.configuration.redMs
    })

    // ---- live state ---------------------------------------------------
    // Named connectionStatus rather than status to keep it clearly distinct
    // from Plasmoid.status, which means something else entirely.
    property int connectionStatus: PingState.GREEN
    property real lastRtt: -1
    property bool lastOk: false
    property int sampleCount: 0

    // Aggregate stats over the whole retained buffer, refreshed with each sample.
    property real avgRtt: -1
    property real minRtt: -1
    property real maxRtt: -1
    property real lossPercent: 0

    // Bumped on every new sample so views can react without watching the
    // JS array itself (mutations to it are invisible to the binding engine).
    property int revision: 0

    readonly property int bufferCap: 3600   // 1 h at 1 s
    readonly property int logCap: 500

    property var samples: []
    property var machine: PingState.initialState()

    readonly property string statusText: {
        switch (connectionStatus) {
        case PingState.GREEN: return i18n("Online");
        case PingState.YELLOW: return i18n("Degraded");
        case PingState.RED: return i18n("Critical");
        }
        return i18n("Unknown");
    }

    readonly property color statusColor: {
        switch (connectionStatus) {
        case PingState.GREEN: return Kirigami.Theme.positiveTextColor;
        case PingState.YELLOW: return Kirigami.Theme.neutralTextColor;
        case PingState.RED: return Kirigami.Theme.negativeTextColor;
        }
        return Kirigami.Theme.disabledTextColor;
    }

    // ---- ping plumbing ------------------------------------------------
    readonly property string pingCommand:
        "LC_ALL=C ping -n -c 1 -W " + pingTimeout + " " + shellQuote(host)

    // Only ever wraps the user-supplied host, but the executable engine runs
    // its argument through a shell, so quote it rather than trusting it.
    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    property bool busy: false

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            // The engine keys sources by command string, and ours never
            // changes, so it must be disconnected before the next run or no
            // further data arrives.
            disconnectSource(sourceName);
            root.busy = false;

            const sample = PingState.parsePingOutput(
                data["stdout"], data["exit code"], Date.now());
            root.recordSample(sample);
        }
    }

    Timer {
        id: pingTimer
        interval: root.pingInterval * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.doPing()
    }

    function doPing() {
        // Skip this tick if the previous ping is still outstanding, so a slow
        // link cannot pile up requests when pingTimeout >= pingInterval.
        if (busy) {
            return;
        }
        busy = true;
        executable.connectSource(pingCommand);
    }

    function recordSample(sample) {
        PingState.push(samples, sample, bufferCap);
        PingState.nextState(machine, sample, thresholds);

        connectionStatus = machine.status;
        lastOk = sample.ok;
        lastRtt = sample.rtt;
        sampleCount = samples.length;

        const s = PingState.stats(samples);
        avgRtt = s.avg;
        minRtt = s.min;
        maxRtt = s.max;
        lossPercent = s.lossPercent;

        logModel.append({
            timestamp: sample.t,
            ok: sample.ok,
            rtt: sample.rtt
        });
        while (logModel.count > logCap) {
            logModel.remove(0);
        }

        revision++;
    }

    function resetHistory() {
        samples = [];
        machine = PingState.initialState();
        logModel.clear();
        connectionStatus = PingState.GREEN;
        lastRtt = -1;
        lastOk = false;
        sampleCount = 0;
        avgRtt = -1;
        minRtt = -1;
        maxRtt = -1;
        lossPercent = 0;
        revision++;
    }

    // Changing what or how we measure invalidates the history.
    onHostChanged: restartSampler()
    onPingIntervalChanged: restartSampler()
    onPingTimeoutChanged: restartSampler()

    function restartSampler() {
        pingTimer.stop();
        // Drop any in-flight request so its result is not attributed to the
        // new target.
        executable.connectedSources = [];
        busy = false;
        resetHistory();
        pingTimer.start();
    }

    // Backs the popup log. Kept separate from `samples` because the view
    // wants a real model, while the chart wants a plain array.
    property alias logModel: logModel
    ListModel { id: logModel }

    // ---- plasmoid wiring ----------------------------------------------
    // In a panel or systray the dot is the point; dropped on the desktop
    // there is room for the whole thing, so show it directly.
    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar
        ? fullRepresentation
        : compactRepresentation

    // The representations are separate files, so hand them the root item
    // explicitly rather than relying on QML context chaining to resolve `root`.
    compactRepresentation: CompactRepresentation {
        widget: root
    }
    fullRepresentation: FullRepresentation {
        widget: root
    }

    // Keep the widget visible in the systray overflow while anything is wrong.
    Plasmoid.status: connectionStatus === PingState.GREEN
        ? PlasmaCore.Types.PassiveStatus
        : PlasmaCore.Types.ActiveStatus

    toolTipMainText: i18n("%1: %2", host, statusText)
    toolTipSubText: {
        if (sampleCount === 0) {
            return i18n("Waiting for first reply…");
        }
        const current = lastOk
            ? i18n("Latest: %1 ms", lastRtt.toFixed(1))
            : i18n("Latest: timed out");
        const summary = avgRtt >= 0
            ? i18n("Average: %1 ms · Loss: %2%",
                   avgRtt.toFixed(1), lossPercent.toFixed(1))
            : i18n("Loss: %1%", lossPercent.toFixed(1));
        return current + "\n" + summary;
    }
}
