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
    exports.OK = OK; exports.WARNING = WARNING; exports.CRITICAL = CRITICAL;
    exports.GOOD = GOOD; exports.SLOW_WARNING = SLOW_WARNING;
    exports.SLOW_CRITICAL = SLOW_CRITICAL; exports.LOST = LOST;
    exports.statusName = statusName;
    exports.makeInstanceToken = makeInstanceToken;
    exports.shellQuote = shellQuote;
    exports.buildPingCommand = buildPingCommand;
    exports.describeFailure = describeFailure;
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

// The executable data engine keys its sources by command string and is shared
// across every applet in plasmashell, so two instances producing the same
// command means one of them is handed a cached result instead of a real ping.
// Distinct tokens are what prevent that, which makes these the tests the fix
// rests on.
console.log('\nbuildPingCommand (source-name uniqueness)');
{
    const a = P.buildPingCommand('8.8.8.8', 1, 'tok1');
    check('contains the host, quoted', a.includes("'8.8.8.8'"));
    check('carries the timeout', a.includes('-W 1 '));
    check('sends exactly one packet', a.includes('-c 1'));
    check('tagged for /proc/<pid>/environ', a.startsWith('PINGACIK_ID=tok1 '));
    // The LC_ALL prefix is what forces KProcess to use a shell, which is what
    // makes the env-var tag safe rather than a stray argument to ping.
    check('keeps the shell-forcing locale prefix', a.includes('LC_ALL=C ping'));

    // Stable across ticks: the same instance must reuse one source name, or the
    // engine accumulates a container per ping.
    eq('same inputs are stable', P.buildPingCommand('8.8.8.8', 1, 'tok1'), a);

    check('another instance on the same host differs',
          P.buildPingCommand('8.8.8.8', 1, 'tok2') !== a);
    check('different hosts differ',
          P.buildPingCommand('1.1.1.1', 1, 'tok1') !== a);
    check('different timeouts differ',
          P.buildPingCommand('8.8.8.8', 2, 'tok1') !== a);

    // No two instances watching one host may ever collide.
    const seen = new Set();
    for (let i = 0; i < 100; i++) {
        seen.add(P.buildPingCommand('8.8.8.8', 1, P.makeInstanceToken()));
    }
    check('100 instances yield ~100 distinct sources', seen.size >= 99,
          `got ${seen.size}`);

    // The host is user-supplied and the engine runs the command through a
    // shell, so a quote in it must not break out of the argument.
    const evil = P.buildPingCommand("a'b", 1, 'tok');
    check('quote in host is escaped', evil.endsWith("'a'\\''b'"));
    eq('shellQuote wraps plainly', P.shellQuote('x'), "'x'");
}

console.log('\nmakeInstanceToken');
{
    const tokens = new Set();
    for (let i = 0; i < 200; i++) { tokens.add(P.makeInstanceToken()); }
    check('tokens are distinct', tokens.size >= 199, `got ${tokens.size} of 200`);
    check('tokens are non-empty', [...tokens].every(t => t.length > 0));
    // Must survive being pasted into a shell command unquoted.
    check('tokens are shell-safe', [...tokens].every(t => /^[a-z0-9]+$/.test(t)));
}

console.log('\ndescribeFailure');
{
    // Exit 1 is "sent a packet, heard nothing" — the loss we exist to count.
    eq('plain timeout needs no explanation', P.describeFailure(1, ''), '');
    eq('timeout ignores stray stderr', P.describeFailure(1, 'whatever'), '');
    eq('routing failure is surfaced',
       P.describeFailure(2, 'connect: Network is unreachable'),
       'connect: Network is unreachable');
    eq('only the first useful line',
       P.describeFailure(2, '\n  ping: bad host  \nsecond line\n'),
       'ping: bad host');
    eq('falls back to the exit code', P.describeFailure(127, ''), 'exit 127');
    eq('missing stderr is tolerated', P.describeFailure(2, undefined), 'exit 2');
}

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
    eq('at warning threshold is GOOD', P.classify({ ok: true, rtt: 150 }, CFG), P.GOOD);
    eq('over warning is SLOW_WARNING', P.classify({ ok: true, rtt: 151 }, CFG), P.SLOW_WARNING);
    eq('over critical is SLOW_CRITICAL', P.classify({ ok: true, rtt: 501 }, CFG), P.SLOW_CRITICAL);
    eq('timeout is LOST', P.classify({ ok: false, rtt: -1 }, CFG), P.LOST);
}

// Drive the machine with a compact string. Input: '.' = good reply,
// 'x' = timeout, 'w' = slow (over the warning threshold), 'c' = very slow
// (over the critical one). Output: O = OK, W = Warning, C = Critical.
function run(seq, cfg) {
    const st = P.initialState();
    let out = '';
    for (const ch of seq) {
        const sample = ch === 'x' ? { ok: false, rtt: -1 }
                     : ch === 'w' ? { ok: true, rtt: 200 }
                     : ch === 'c' ? { ok: true, rtt: 900 }
                     : { ok: true, rtt: 20 };
        P.nextState(st, sample, cfg || CFG);
        out += 'OWC'[st.status];
    }
    return out;
}

console.log('\nhysteresis - loss');
{
    // yellowAfter=2, redAfter=5, recoverAfter=5
    eq('all good stays OK', run('.......'), 'OOOOOOO');
    eq('one loss not enough for warning', run('..x..'), 'OOOOO');
    eq('two consecutive losses -> warning', run('..xx'), 'OOOW');
    eq('five consecutive losses -> critical', run('xxxxx'), 'OWWWC');
    // Recovery requires recoverAfter=5 consecutive good samples, NOT one.
    eq('single success does not clear warning', run('..xx.'), 'OOOWW');
    eq('recovers only on the 5th good sample', run('..xx.....'), 'OOOWWWWWO');
    eq('a loss during recovery restarts the count',
       run('..xx...x.....'), 'OOOWWWWWWWWWO');
}

console.log('\nhysteresis - latency');
{
    eq('two slow samples -> warning', run('..ww'), 'OOOW');
    eq('slow ramps warning then critical', run('ccccc'), 'OWWWC');
    eq('one slow sample is tolerated', run('..w..'), 'OOOOO');
    eq('slow recovery honours recoverAfter', run('..ww.....'), 'OOOWWWWWO');
    // Latency must degrade with zero packet loss.
    check('latency degrades without any loss', run('wwwww').includes('W'));
}

console.log('\nhysteresis - worst-of');
{
    // Losses and slowness interleaved: neither alone reaches critical, but the
    // machine must not silently recover mid-run.
    eq('mixed degradation holds', run('..xxww'), 'OOOWWW');
}

console.log('\nstatusName');
{
    eq('ok', P.statusName(P.OK), 'ok');
    eq('warning', P.statusName(P.WARNING), 'warning');
    eq('critical', P.statusName(P.CRITICAL), 'critical');
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
