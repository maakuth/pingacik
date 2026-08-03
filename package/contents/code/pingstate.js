.pragma library

// Pure data logic for Pingacik. Deliberately free of QML types so it can be
// exercised standalone (see tools/test-pingstate.js).

var OK = 0;
var WARNING = 1;
var CRITICAL = 2;

// Sample verdicts
var GOOD = 0;
var SLOW_WARNING = 1;
var SLOW_CRITICAL = 2;
var LOST = 3;

/**
 * Parse the output of `ping -n -c 1 -W <t> <host>`.
 * Success requires a zero exit code *and* an rtt in the output; anything else
 * counts as a lost packet.
 * @returns {{ok: boolean, rtt: number, t: number}}
 */
function parsePingOutput(stdout, exitCode, timestamp) {
    var t = timestamp !== undefined ? timestamp : Date.now();
    if (exitCode !== 0) {
        return { ok: false, rtt: -1, t: t };
    }
    var m = /time[=<]\s*([\d.]+)\s*ms/.exec(stdout || "");
    if (!m) {
        return { ok: false, rtt: -1, t: t };
    }
    return { ok: true, rtt: parseFloat(m[1]), t: t };
}

/**
 * Classify a single sample against the latency thresholds.
 * @returns one of GOOD / SLOW_WARNING / SLOW_CRITICAL / LOST
 */
function classify(sample, cfg) {
    if (!sample.ok) {
        return LOST;
    }
    if (sample.rtt > cfg.redMs) {
        return SLOW_CRITICAL;
    }
    if (sample.rtt > cfg.yellowMs) {
        return SLOW_WARNING;
    }
    return GOOD;
}

/** A fresh state object for the hysteresis machine. */
function initialState() {
    return {
        status: OK,
        consecutiveLoss: 0,
        consecutiveSlowWarning: 0,
        consecutiveSlowCritical: 0,
        consecutiveGood: 0
    };
}

/**
 * Advance the hysteresis state machine by one sample.
 *
 * Degrade immediately, recover slowly: a worse verdict applies at once, but
 * returning to OK requires `recoverAfter` consecutive fully-good samples.
 *
 * Mutates and returns `state`.
 */
function nextState(state, sample, cfg) {
    var verdict = classify(sample, cfg);

    // Counters. Each is reset by any sample that does not extend its run.
    if (verdict === LOST) {
        state.consecutiveLoss++;
    } else {
        state.consecutiveLoss = 0;
    }

    // A critical-level sample also extends the warning-level run: it is over
    // both thresholds, so a slow link ramps OK -> Warning -> Critical rather
    // than flapping.
    if (verdict === SLOW_CRITICAL) {
        state.consecutiveSlowCritical++;
        state.consecutiveSlowWarning++;
    } else if (verdict === SLOW_WARNING) {
        state.consecutiveSlowCritical = 0;
        state.consecutiveSlowWarning++;
    } else {
        state.consecutiveSlowCritical = 0;
        state.consecutiveSlowWarning = 0;
    }

    state.consecutiveGood = (verdict === GOOD) ? state.consecutiveGood + 1 : 0;

    var lossState = state.consecutiveLoss >= cfg.redAfter ? CRITICAL
                  : state.consecutiveLoss >= cfg.yellowAfter ? WARNING
                  : OK;

    var latencyState = state.consecutiveSlowCritical >= cfg.redAfter ? CRITICAL
                     : state.consecutiveSlowWarning >= cfg.yellowAfter ? WARNING
                     : OK;

    var target = Math.max(lossState, latencyState);

    if (target > state.status) {
        // Worse than now: apply immediately.
        state.status = target;
    } else if (state.status !== OK && state.consecutiveGood >= cfg.recoverAfter) {
        // Better than now, and the link has proven itself: go straight to OK.
        state.status = OK;
    }
    // Otherwise hold the current (degraded) status.

    return state;
}

/**
 * How long to wait before starting the next ping, measured from when the
 * previous one *started* rather than when it finished.
 *
 * This keeps the cadence at `intervalMs` regardless of how long a reply took,
 * instead of drifting by the round-trip time on every sample. When a ping
 * overruns the interval — which is what happens during an outage, where every
 * ping burns the full timeout — the next one follows after `minGapMs`, so the
 * sample rate degrades to the timeout rather than collapsing to a multiple of
 * the interval.
 */
function nextDelay(intervalMs, elapsedMs, minGapMs) {
    return Math.max(minGapMs, intervalMs - elapsedMs);
}

/** Append to a ring buffer capped at `cap` entries. Mutates and returns it. */
function push(buffer, sample, cap) {
    buffer.push(sample);
    while (buffer.length > cap) {
        buffer.shift();
    }
    return buffer;
}

/** The tail of `buffer` covering the last `seconds`, relative to now. */
function windowSlice(buffer, seconds, now) {
    var cutoff = (now !== undefined ? now : Date.now()) - seconds * 1000;
    var i = buffer.length;
    while (i > 0 && buffer[i - 1].t >= cutoff) {
        i--;
    }
    return buffer.slice(i);
}

/**
 * Bucket `slice` down to at most `targetPoints` points so the chart stays
 * readable and cheap on long timescales.
 * @returns {Array<{t, avg, min, max, lossCount, total}>}
 */
function downsample(slice, targetPoints) {
    if (slice.length === 0) {
        return [];
    }
    if (slice.length <= targetPoints) {
        return slice.map(function (s) {
            return {
                t: s.t,
                avg: s.ok ? s.rtt : -1,
                min: s.ok ? s.rtt : -1,
                max: s.ok ? s.rtt : -1,
                lossCount: s.ok ? 0 : 1,
                total: 1
            };
        });
    }

    var bucketSize = slice.length / targetPoints;
    var out = [];
    for (var b = 0; b < targetPoints; b++) {
        var start = Math.floor(b * bucketSize);
        var end = Math.floor((b + 1) * bucketSize);
        if (end <= start) {
            end = start + 1;
        }

        var sum = 0, n = 0, lost = 0;
        var mn = Infinity, mx = -Infinity;
        for (var i = start; i < end && i < slice.length; i++) {
            var s = slice[i];
            if (s.ok) {
                sum += s.rtt;
                n++;
                if (s.rtt < mn) { mn = s.rtt; }
                if (s.rtt > mx) { mx = s.rtt; }
            } else {
                lost++;
            }
        }

        out.push({
            t: slice[start].t,
            avg: n > 0 ? sum / n : -1,
            min: n > 0 ? mn : -1,
            max: n > 0 ? mx : -1,
            lossCount: lost,
            total: Math.min(end, slice.length) - start
        });
    }
    return out;
}

/** Aggregate stats over a slice, for the popup header. */
function stats(slice) {
    var sum = 0, n = 0, lost = 0;
    var mn = Infinity, mx = -Infinity;
    for (var i = 0; i < slice.length; i++) {
        var s = slice[i];
        if (s.ok) {
            sum += s.rtt;
            n++;
            if (s.rtt < mn) { mn = s.rtt; }
            if (s.rtt > mx) { mx = s.rtt; }
        } else {
            lost++;
        }
    }
    return {
        count: slice.length,
        received: n,
        lost: lost,
        lossPercent: slice.length > 0 ? (lost * 100 / slice.length) : 0,
        avg: n > 0 ? sum / n : -1,
        min: n > 0 ? mn : -1,
        max: n > 0 ? mx : -1
    };
}

function statusName(status) {
    switch (status) {
    case OK: return "ok";
    case WARNING: return "warning";
    case CRITICAL: return "critical";
    }
    return "unknown";
}
