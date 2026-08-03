#!/usr/bin/env node
// Standalone tests for contents/code/pingstate.js.
// The library is plain ES5 with a `.pragma library` header, so we strip that
// line and eval it rather than importing it.
//
//   node tools/test-pingstate.js

const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(
    path.join(__dirname, '..', 'package', 'contents', 'code', 'pingstate.js'),
    'utf8'
).replace(/^\s*\.pragma\s+library\s*$/m, '');

const P = {};
(new Function('exports', src + `
    exports.GREEN = GREEN; exports.YELLOW = YELLOW; exports.RED = RED;
    exports.GOOD = GOOD; exports.SLOW_YELLOW = SLOW_YELLOW;
    exports.SLOW_RED = SLOW_RED; exports.LOST = LOST;
    exports.parsePingOutput = parsePingOutput;
    exports.classify = classify;
    exports.initialState = initialState;
    exports.nextState = nextState;
    exports.nextDelay = nextDelay;
    exports.push = push;
    exports.windowSlice = windowSlice;
    exports.downsample = downsample;
    exports.stats = stats;
`))(P);

let pass = 0, fail = 0;
function check(name, cond, extra) {
    if (cond) { pass++; console.log('  ok   ' + name); }
    else { fail++; console.log('  FAIL ' + name + (extra ? '  -> ' + extra : '')); }
}
function eq(name, actual, expected) {
    check(name, actual === expected, `got ${actual}, want ${expected}`);
}

const CFG = { yellowAfter: 2, redAfter: 5, recoverAfter: 5, yellowMs: 150, redMs: 500 };

console.log('\nparsePingOutput');
{
    const okOut = 'PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.\n' +
                  '64 bytes from 8.8.8.8: icmp_seq=1 ttl=106 time=20.0 ms\n' +
                  '\n--- 8.8.8.8 ping statistics ---\n' +
                  '1 packets transmitted, 1 received, 0% packet loss, time 0ms\n';
    const a = P.parsePingOutput(okOut, 0, 1000);
    check('reply parsed as ok', a.ok === true);
    eq('rtt extracted', a.rtt, 20.0);

    const failOut = 'PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data.\n' +
                    '\n--- 192.0.2.1 ping statistics ---\n' +
                    '1 packets transmitted, 0 received, 100% packet loss, time 0ms\n';
    check('timeout parsed as loss', P.parsePingOutput(failOut, 1, 1000).ok === false);

    // Non-zero exit with a stray rtt in the text must still count as a loss.
    check('exit code wins over stray rtt',
          P.parsePingOutput('time=5 ms', 1, 1000).ok === false);
    // Zero exit but no rtt (shouldn't happen, but must not yield NaN).
    check('missing rtt is a loss', P.parsePingOutput('nothing here', 0, 1000).ok === false);
    // `time<1 ms` form on very fast local links.
    eq('time< form parsed', P.parsePingOutput('time<1 ms', 0, 1000).rtt, 1);
}

console.log('\nclassify');
{
    eq('fast reply is GOOD', P.classify({ ok: true, rtt: 20 }, CFG), P.GOOD);
    eq('at yellow threshold is GOOD', P.classify({ ok: true, rtt: 150 }, CFG), P.GOOD);
    eq('over yellow is SLOW_YELLOW', P.classify({ ok: true, rtt: 151 }, CFG), P.SLOW_YELLOW);
    eq('over red is SLOW_RED', P.classify({ ok: true, rtt: 501 }, CFG), P.SLOW_RED);
    eq('timeout is LOST', P.classify({ ok: false, rtt: -1 }, CFG), P.LOST);
}

// Drive the machine with a compact string: '.' = good reply, 'x' = timeout,
// 'y' = slow (yellow band), 'r' = very slow (red band).
function run(seq, cfg) {
    const st = P.initialState();
    let out = '';
    for (const ch of seq) {
        const sample = ch === 'x' ? { ok: false, rtt: -1 }
                     : ch === 'y' ? { ok: true, rtt: 200 }
                     : ch === 'r' ? { ok: true, rtt: 900 }
                     : { ok: true, rtt: 20 };
        P.nextState(st, sample, cfg || CFG);
        out += 'GYR'[st.status];
    }
    return out;
}

console.log('\nhysteresis - loss');
{
    // yellowAfter=2, redAfter=5, recoverAfter=5
    eq('all good stays green', run('.......'), 'GGGGGGG');
    eq('one loss not enough for yellow', run('..x..'), 'GGGGG');
    eq('two consecutive losses -> yellow', run('..xx'), 'GGGY');
    eq('five consecutive losses -> red', run('xxxxx'), 'GYYYR');
    // Recovery requires recoverAfter=5 consecutive good samples, NOT one.
    eq('single success does not clear yellow', run('..xx.'), 'GGGYY');
    eq('recovers only on the 5th good sample', run('..xx.....'), 'GGGYYYYYG');
    eq('a loss during recovery restarts the count',
       run('..xx...x.....'), 'GGGYYYYYYYYYG');
}

console.log('\nhysteresis - latency');
{
    eq('two slow samples -> yellow', run('..yy'), 'GGGY');
    eq('slow ramps yellow then red', run('rrrrr'), 'GYYYR');
    eq('one slow sample is tolerated', run('..y..'), 'GGGGG');
    eq('slow recovery honours recoverAfter', run('..yy.....'), 'GGGYYYYYG');
    // Latency must degrade with zero packet loss.
    check('latency degrades without any loss', run('yyyyy').includes('Y'));
}

console.log('\nhysteresis - worst-of');
{
    // Losses and slowness interleaved: neither alone reaches red, but the
    // machine must not silently recover mid-run.
    eq('mixed degradation holds', run('..xxyy'), 'GGGYYY');
}

console.log('\nnextDelay (sample cadence)');
{
    const MIN = 50;
    // Scheduling from the *start* of the previous ping keeps the cadence flat:
    // delay + elapsed == interval, whatever the round-trip time was.
    eq('fast reply waits out the remainder', P.nextDelay(1000, 20, MIN), 980);
    eq('slower reply waits less', P.nextDelay(1000, 300, MIN), 700);
    check('cadence is exactly the interval',
          [5, 20, 300, 800, 950].every(rtt => rtt + P.nextDelay(1000, rtt, MIN) === 1000));

    // The outage case this scheduler exists for: at the defaults an
    // unanswered ping burns the full 1 s timeout. A free-running repeating
    // timer would have its 1 s tick swallowed and only fire at 2 s.
    eq('ping that used the whole interval retries after the min gap',
       P.nextDelay(1000, 1000, MIN), MIN);
    eq('outage cadence is timeout + min gap, not 2x interval',
       1000 + P.nextDelay(1000, 1000, MIN), 1050);

    // A timeout longer than the interval bounds the rate, but must not wedge
    // it or produce a negative delay.
    eq('overrunning ping still gets a gap', P.nextDelay(1000, 5000, MIN), MIN);
    check('delay is never below the minimum gap',
          [0, 999, 1000, 1001, 60000].every(e => P.nextDelay(1000, e, MIN) >= MIN));
}

console.log('\nring buffer');
{
    let buf = [];
    for (let i = 0; i < 10; i++) { P.push(buf, { ok: true, rtt: i, t: i }, 5); }
    eq('capped at cap', buf.length, 5);
    eq('keeps newest', buf[4].rtt, 9);
    eq('drops oldest', buf[0].rtt, 5);
}

console.log('\nwindowSlice');
{
    const buf = [];
    for (let i = 0; i < 100; i++) { buf.push({ ok: true, rtt: 1, t: i * 1000 }); }
    const now = 99 * 1000;
    eq('last 10s', P.windowSlice(buf, 10, now).length, 11);
    eq('window larger than buffer returns all', P.windowSlice(buf, 100000, now).length, 100);
}

console.log('\ndownsample');
{
    const small = [];
    for (let i = 0; i < 50; i++) { small.push({ ok: true, rtt: i, t: i }); }
    eq('under target passes through', P.downsample(small, 300).length, 50);

    const big = [];
    for (let i = 0; i < 3600; i++) { big.push({ ok: i % 100 !== 0, rtt: 20, t: i }); }
    const ds = P.downsample(big, 300);
    eq('downsampled to target', ds.length, 300);
    eq('buckets total back to input', ds.reduce((a, b) => a + b.total, 0), 3600);
    eq('losses preserved', ds.reduce((a, b) => a + b.lossCount, 0), 36);
    check('avg ignores lost samples', ds.every(b => b.avg === 20 || b.avg === -1));

    eq('empty input', P.downsample([], 300).length, 0);
    // All-lost bucket must not produce NaN from Infinity bookkeeping.
    const allLost = [];
    for (let i = 0; i < 600; i++) { allLost.push({ ok: false, rtt: -1, t: i }); }
    check('all-lost yields -1 not NaN',
          P.downsample(allLost, 300).every(b => b.avg === -1 && b.min === -1 && b.max === -1));
}

console.log('\nstats');
{
    const s = P.stats([
        { ok: true, rtt: 10 }, { ok: true, rtt: 30 },
        { ok: false, rtt: -1 }, { ok: true, rtt: 20 }
    ]);
    eq('count', s.count, 4);
    eq('received', s.received, 3);
    eq('lost', s.lost, 1);
    eq('lossPercent', s.lossPercent, 25);
    eq('avg', s.avg, 20);
    eq('min', s.min, 10);
    eq('max', s.max, 30);

    const empty = P.stats([]);
    eq('empty avg is -1', empty.avg, -1);
    eq('empty lossPercent is 0', empty.lossPercent, 0);
}

console.log(`\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
