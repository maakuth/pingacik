# Pingacik

A KDE Plasma 6 panel widget that monitors internet connection quality by pinging a host.

The panel shows a traffic-light dot and the current round-trip time. Click it for a live ping log
and an RTT chart over a configurable timescale.

<p align="center">
  <img src="screenshots/panel.png" alt="The widget in a panel: a green dot and 20 ms" width="90">
</p>

<p align="center">
  <img src="screenshots/online.png" alt="Popup showing a healthy connection" width="470">
  &nbsp;
  <img src="screenshots/critical.png" alt="Popup showing a failed connection" width="470">
</p>

## Install

```sh
git clone https://github.com/smolamSK/pingacik.git
cd pingacik
./install.sh
```

Then right-click your panel → **Add or Manage Widgets…** → **Pingacik**.

Requires Plasma 6 and `ping` (iputils). It is a pure QML applet — nothing to compile.

To remove it:

```sh
kpackagetool6 --type Plasma/Applet --remove org.smolam.pingacik
```

## How the states work

The widget sends one `ping -c 1` per interval and feeds each result into a hysteresis state machine.

The three states are **OK**, **Warning** and **Critical**.

**It degrades immediately but recovers slowly.** Crossing a threshold changes the state on the very
next sample; returning to OK requires `recoverAfter` consecutive good pings. A "good" ping got a
reply *and* came back faster than the Warning latency threshold.

| Trigger | Default |
|---|---|
| Warning after N consecutive lost pings | 2 |
| Critical after N consecutive lost pings | 5 |
| Warning above | 150 ms |
| Critical above | 500 ms |
| Back to OK after N consecutive good pings | 5 |

Packet loss and latency are evaluated separately and the worse of the two wins, so a link that
delivers every packet but takes 800 ms still reads Critical. A single lost or slow ping never
changes the state — losses must be *consecutive*, and any reply resets the loss count.

Latency reuses the same consecutive counts as packet loss rather than adding separate knobs, so one
RTT spike is ignored while a sustained slowdown ramps OK → Warning → Critical.

## Settings

**In a panel:** right-click the widget → **Configure Pingacik…**

**On the desktop:** click the gear in the widget's own header. Plasma 6 gives widgets on the desktop
no right-click menu of their own, so without that button there is no way in — the handles that carry
the usual wrench appear only after a *press and hold* on the widget, and over the scrollable log that
press often goes to the list instead.

Press-and-hold is still the only way to **move or resize** a desktop widget: hold until the handles
appear, or right-click the desktop → **Enter Edit Mode**, which shows handles for everything at once.

**General** — target host (default `8.8.8.8`), ping interval and reply timeout.

**Appearance** — whether to show the latency text in the panel, the chart range the popup opens
with, and the three state colours.

By default the colours come from your Plasma colour scheme (`positive`, `neutral` and `negative`
text colours), so they follow light/dark theme switches automatically. Tick **Use custom colours**
to pin your own for OK, Warning and Critical; a preview row shows the result before you apply. The
chosen colours are used everywhere — the panel dot, the popup header, the log rows and the
packet-loss bands on the chart.

**Background** — an opacity for the widget's own background, 0–100%, off by default.

This applies to the widget **placed on the desktop**, where the background belongs to the applet.
It deliberately does nothing in a panel, and that is not an oversight: a popup's background is chosen
by the shell from the *containment's* display hints, not the applet's, so no widget can make its own
popup translucent. For panels, use the panel's own **Opacity** setting (Adaptive / Opaque /
Translucent), and for popups generally the Plasma Style plus KWin's Blur and Background Contrast
effects. Plasma itself has no per-widget opacity level anywhere — the nearest native control is a
binary Show/Hide Background button, which this setting's 0% and 100% ends already cover.

Only the background goes translucent; the text, chart and indicator stay fully opaque on top of it.

**Thresholds** — everything in the table above.

Changing the host, interval or timeout clears the collected history, since it is no longer
comparable.

## Notes

- History is kept in memory only — roughly the last hour at the default 1 s interval. It resets when
  the widget or plasmashell restarts. Nothing is written to disk.
- The chart downsamples to ~300 buckets, so the 1 h view stays responsive. Buckets containing lost
  packets are shaded red in proportion to how many were lost.
- Only one ping is ever in flight. The next one is scheduled from when the last one *started*, so a
  reply that took 300 ms is followed 700 ms later — the cadence holds at the configured interval
  instead of drifting, and a stalled link cannot pile up processes.
- **Every instance measures for itself.** Add the widget twice and you get two independent pings, so
  N copies watching the same host means N pings per interval. Each instance tags its pings with its
  own `PINGACIK_ID`, which is what keeps them separate: Plasma's `executable` data engine is shared
  by every applet and keys its sources by command string, so two widgets issuing an identical
  command would be handed one shared result — the second would never ping at all, it would mirror
  the first. The tag lives in the environment rather than the command line (the shell `exec`s ping,
  replacing argv), so `tr '\0' '\n' < /proc/<pid>/environ | grep PINGACIK_ID` on a running `ping` is
  what tells you which instance it belongs to.
- The live ping log opens on the newest result and keeps scrolling as they arrive. Scroll away and it
  stops following so it is not moving under you; scroll back to the bottom, or press **Jump to
  latest**, and it picks up again. Reopening the popup always starts following.
- A failed ping that failed for a reason *other* than going unanswered — no route, no permission, a
  name that would not resolve — shows what `ping` reported instead of a bare "no reply", so a broken
  setup does not hide inside the packet-loss count.
- Thresholds are counted in pings, not seconds. While the link is down, an unanswered ping cannot be
  counted until it times out, so the reply timeout is what bounds the sample rate during an outage.
  That is why it defaults to the same value as the interval: raising it makes every threshold below
  take correspondingly longer to trigger.
- Dropped on the desktop rather than a panel, the widget shows the full view directly.

## Development

```sh
node tools/test-pingstate.js                          # logic tests
plasmoidviewer -a org.smolam.pingacik -f planar       # full view
plasmoidviewer -a org.smolam.pingacik -f horizontal   # panel view
```

All the non-visual logic lives in [`package/contents/code/pingstate.js`](package/contents/code/pingstate.js),
which holds no QML types, so it runs under plain Node. The tests cover ping parsing, the hysteresis
state machine, the sample cadence, the ring buffer and chart downsampling.

Two things worth knowing when hacking on this:

- **QML errors do not always reach stderr.** `plasmawindowed org.smolam.pingacik` renders them in the
  window, which is the fastest way to see what broke.
- **plasmashell caches compiled QML.** After `./install.sh` on an already-added widget, run
  `systemctl --user restart plasma-plasmashell` or you will keep seeing the old version — including
  old error messages.

### Layout

```
package/
  metadata.json                 applet id, icon, category
  contents/
    config/main.xml             KConfigXT schema (defaults live here)
    config/config.qml           config dialog pages
    code/pingstate.js           parsing, state machine, buffering, downsampling
    ui/main.qml                 sampler: DataSource + timer + ring buffer
    ui/CompactRepresentation.qml  panel dot + latency
    ui/FullRepresentation.qml     popup: header, chart, log
    ui/PingChart.qml              RTT chart + loss bands
    ui/StatusDot.qml              shared status circle
    ui/FigureLabel.qml            label with tabular figures
    ui/config/                    General, Appearance and Thresholds pages
tools/test-pingstate.js         standalone logic tests
```

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
