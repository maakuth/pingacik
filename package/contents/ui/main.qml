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
    property int connectionStatus: PingState.OK
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
        case PingState.OK: return i18n("OK");
        case PingState.WARNING: return i18n("Warning");
        case PingState.CRITICAL: return i18n("Critical");
        }
        return i18n("Unknown");
    }

    // The three state colours, resolved once here so the panel dot, the popup
    // header, the log rows and the chart bands all agree. Following the colour
    // scheme by default means the widget tracks light/dark switches; custom
    // colours are a deliberate opt-out of that.
    readonly property color colorOk: Plasmoid.configuration.useCustomColors
        ? Plasmoid.configuration.okColor
        : Kirigami.Theme.positiveTextColor
    readonly property color colorWarning: Plasmoid.configuration.useCustomColors
        ? Plasmoid.configuration.warningColor
        : Kirigami.Theme.neutralTextColor
    readonly property color colorCritical: Plasmoid.configuration.useCustomColors
        ? Plasmoid.configuration.criticalColor
        : Kirigami.Theme.negativeTextColor

    readonly property color statusColor: {
        switch (connectionStatus) {
        case PingState.OK: return colorOk;
        case PingState.WARNING: return colorWarning;
        case PingState.CRITICAL: return colorCritical;
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
    property double lastStart: 0

    // Never fire two pings back to back with no gap at all, even when the
    // previous one overran the interval completely.
    readonly property int minGapMs: 50

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            // The engine keys sources by command string, and ours never
            // changes, so it must be disconnected before the next run or no
            // further data arrives.
            disconnectSource(sourceName);

            // Dropped by the watchdog already: ignore the late arrival rather
            // than attributing it to whatever request is outstanding now.
            if (!root.busy) {
                return;
            }
            root.busy = false;
            watchdog.stop();

            root.recordSample(PingState.parsePingOutput(
                data["stdout"], data["exit code"], Date.now()));
            root.scheduleNext();
        }
    }

    // Single-shot and rescheduled after every result, rather than free-running.
    // A repeating timer would have its ticks swallowed while a ping is still
    // outstanding, so during an outage — when each ping burns the full timeout
    // — the sample rate would collapse to a multiple of the interval just when
    // samples matter most. Measuring from completion keeps the cadence at the
    // configured interval whenever the timeout allows it.
    Timer {
        id: pingTimer
        repeat: false
        onTriggered: root.doPing()
    }

    // The executable engine should always report back, since the process
    // exits either way. If it ever does not, this keeps the widget measuring
    // instead of silently freezing on the last known state.
    Timer {
        id: watchdog
        interval: (root.pingTimeout + 5) * 1000
        repeat: false
        onTriggered: {
            executable.connectedSources = [];
            root.busy = false;
            root.recordSample({ ok: false, rtt: -1, t: Date.now() });
            root.scheduleNext();
        }
    }

    function doPing() {
        if (busy) {
            return;
        }
        busy = true;
        lastStart = Date.now();
        watchdog.restart();
        executable.connectSource(pingCommand);
    }

    function scheduleNext() {
        pingTimer.interval = PingState.nextDelay(
            pingInterval * 1000, Date.now() - lastStart, minGapMs);
        pingTimer.restart();
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
        connectionStatus = PingState.OK;
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
        watchdog.stop();
        // Drop any in-flight request so its result is not attributed to the
        // new target. Clearing busy first also makes onNewData discard it if
        // the engine reports back anyway.
        busy = false;
        executable.connectedSources = [];
        resetHistory();
        doPing();
    }

    // The timer no longer free-runs, so the first ping needs an explicit kick.
    // Guarded by `busy`, so this is harmless if a configuration change already
    // started one during initialisation.
    Component.onCompleted: doPing()

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
    Plasmoid.status: connectionStatus === PingState.OK
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
