# App-scoped HID remaps: design and rollout

Status: DriverKit v8 transport, exact app-guard parsing, foreground identity,
and selected-slot routing are implemented in the fork. The daemon still
rejects app-scoped rules by default; the separate, signed development
grabber uses `--experimental-app-scoped-rules`. After a successful one-hour
trial and guarded cutover on 2026-10-24, that development grabber and its
remap-only agent are the current long-lived local keyboard setup. This is
not a release/default-enable decision for other machines. Ordinary skhd
hotkeys still run in the separate, unchanged production service.

## 2026-10-24 local permanent setup

- `com.jackielii.skhd` keeps the existing high-level bindings and its
  original `~/.config/skhd/skhdrc`. The separate user LaunchAgent
  `com.jackielii.skhd.remap-agent` runs
  `/Applications/skhd-agent-dev.app` with the 24-rule
  `~/.config/skhd/remap.skhdrc` and `/private/tmp/skhd-remap.sock`.
  The root LaunchDaemon `com.jackielii.skhd.grabber` runs the separately
  signed `/Applications/skhd-grabber-dev.app` on that socket. Both jobs
  have `RunAtLoad` and `KeepAlive`; service files are in the normal
  `~/Library/LaunchAgents` and `/Library/LaunchDaemons` directories.
- Karabiner's two **user** agents are disabled and unregistered, so they
  do not compete for the physical keyboard. Karabiner-Elements remains
  installed as the fallback. Its **system** VirtualHIDDevice daemon stays
  enabled because this skhd grabber uses its DriverKit injection channel.
- The unchanged production `skhd --status` checks the default grabber
  socket and therefore misleadingly reports this custom-socket grabber as
  "not running." Use
  `/Applications/skhd-agent-dev.app/Contents/MacOS/skhd --grabber-status /private/tmp/skhd-remap.sock`
  instead; it returned five OK checks after cutover.
- The one-hour trial ended with the independent rollback restoring
  Karabiner. The subsequent permanent cutover used a separate 15-minute
  rollback; the user confirmed normal typing and the Caps, Tab, Right
  Shift, Right Command, and Right Option actions before it was canceled.
  A reboot/login startup has not yet been observed. Emacs/Portacle
  exclusions and sleep/wake behavior remain unverified by user choice.
- To return to Karabiner, run
  `sudo /usr/local/sbin/skhd-restore-karabiner`. This disables the new
  startup jobs, releases the skhd grabber, and re-enables/re-registers
  Karabiner's two user agents; it leaves ordinary high-level skhd alone.
  The root-owned installed script matches `scripts/restore-karabiner.sh`
  and passed a harmless preflight before the cutover. Re-enabling the
  low-level grabber afterward should use a fresh guarded cutover rather
  than starting both keyboard owners together.
- The development grabber is a Debug build and logs HID usage codes for
  individual keys. Its active `/var/log/skhd-remap-grabber.log` is mode
  `0600` (root-only), but a non-debug signed build or bounded logging is
  still needed before treating this as a polished release deployment.

The virtual-keyboard output path now has one non-seizing delivery check:
after matching the installed Karabiner keyboard's Apple vendor/product IDs,
the fork posted `a` into a temporary TextEdit document. This is not a
physical-keyboard capture test. TextEdit crashed during the subsequent
automation-driven document close, so live tests stopped. Do not remove the
daemon's app-rule rejection or install the fork on the working keyboard on
the strength of that single output check.

## 2026-10-24 experimental runtime gate

- A short observed pass-through test and a separate Left Shift tap/hold test
  both passed with the signed development grabber. Karabiner was restored
  after each; these tests did not exercise app-specific selection or
  foreground-app updates.
- The IPC server continues to reject app-scoped and passthrough rules by
  default. Only a grabber launched with
  `--experimental-app-scoped-rules` and a separate `--socket-path` accepts
  them. The flag cannot be combined with standalone `--seize-test`, and
  it cannot use the ordinary default socket. The opt-in rejects scoped
  rules without a device guard, invalid bundle IDs, duplicate exact-app
  scopes, and passthrough rules without an app ID. Focused gate tests and
  `zig build` pass; no active service or config was changed.
- The flag is a test gate, not a release decision. Before a live scoped
  test, use an isolated development socket/client, a fresh independent
  rollback, a deliberately harmless non-Caps-Lock rule, and explicit
  user START/STOP signals. Confirm app changes and loss-of-client behavior
  before considering default enablement.
- The development agent now has `--grabber-socket <path>`, accepted only
  with `-V` (foreground mode) and an explicit `-c` config file. This lets
  a minimal, separately launched agent send real foreground-app updates
  to the isolated grabber without redirecting the installed high-level
  skhd service. The option and IPC gate build and pass focused checks;
  neither side has been connected for a physical app-scoped test.
- Standard HID F21–F24 names were added to the config key map. An isolated
  fixture parsed successfully and reached a deliberate `FileNotFound` on
  its nonexistent custom socket; it did not start a grabber or capture
  input. The fixture uses Left Shift so Caps Lock remains untouched:

```text
.device builtin { vendor: 0x05AC, product: 0x0343 }
.remap lshift [device builtin] {
    tap: f24
    hold: lshift
    timeout: 200ms
    permissive_hold: off
}
.remap lshift [device builtin] [app "com.mitchellh.ghostty"] {
    tap: f23
    hold: lshift
    timeout: 200ms
    permissive_hold: off
}
```

  The intended observable distinction is F23 on a quick Left Shift tap
  in Ghostty versus F24 elsewhere, checked in the development grabber's
  event log. Both holds retain normal Left Shift behavior. The actual
  foreground update and selected-slot behavior remain untested on input.
- The installed ordinary `/Applications/skhd.app` is signed with
  `skhd-cert`, while the separate development grabber uses an Apple
  Development identity. A second development agent may not inherit the
  installed app's Accessibility/Input Monitoring grants. Verify its own
  permission and signing state without replacing the working app before
  attempting an end-to-end foreground-app test.
- A separate Apple Development-signed agent is now installed at
  `/Applications/skhd-agent-dev.app` with bundle ID
  `com.jackielii.skhd.agent.dev`. Its listen-only `-o` event tap opened for
  a bounded seven-second probe and was terminated by the test timeout.
  No keyboard events were requested, and no scoped remap was exercised.
- The first rollback-guarded physical test accepted both temporary Left
  Shift rules and logged F24 fallback taps and normal Left Shift holds.
  It logged no F23 app-specific tap; the agent log showed only ChatGPT as
  frontmost. Whether the user brought Ghostty forward is unconfirmed, so
  foreground updates and app-specific selection remain unvalidated. The
  test agent/grabber were stopped, Karabiner restored, and the independent
  rollback completed successfully. The experimental gate remains default-off.
- A subsequent no-capture mock-socket test received the agent's initial
  `com.openai.codex` identity and live foreground updates for
  `com.mitchellh.ghostty` and back to `com.openai.codex` while the apps
  were activated. This verifies the agent's foreground message path only;
  it isolated that path before the next physical test.
- A fresh rollback-guarded physical test then activated Ghostty
  automatically during a 14-second typing window. The development grabber
  logged four Ghostty-specific F23 taps, normal Left Shift holds, and
  forwarded letter events; the agent identified Ghostty as frontmost. The
  user confirmed held Shift produced uppercase `ABC` and typing remained
  normal after Karabiner was restored. The earlier ChatGPT window logged
  F24 fallback taps. This validates the temporary exact-app/fallback
  selection in short observed runs, not long-term stability or full
  Karabiner migration. The experimental flag remains default-off.

## Baseline and constraints

- On 2026-10-20 the local checkout was clean at `e4770df`; Karabiner-Elements
  16.3.0 owned Caps Lock tap/hold behavior and its installed virtual-HID daemon
  was version 8.5.0. The installed skhd 0.2.0 reported no running service or
  grabber in this environment. No live input changes were made during inspection.
- At baseline, the `.remap` parser required `[device alias]` and rejected a second rule
  for the same source/device, and sends tap/hold rules to a root grabber. The
  grabber builds one engine slot per rule and dispatches every input event to
  those slots. App-scoped duplicates therefore require explicit selection;
  merely relaxing the parser conflict check would emit duplicate keys.
- At baseline, the agent cached the frontmost process *name* for high-level hotkeys,
  but not a bundle ID. The grabber expected no agent messages after
  `apply_rules` and uses read readiness only to detect disconnection.
- At baseline, the virtual-HID client was hard-coded to the old datagram transport and
  protocol version 5. DriverKit v8 changed to `unix_domain_stream`, protocol
  version 7, and renumbered requests; the installed daemon is v8.5.0.
  Changing only a version constant would be incorrect. DriverKit
  compatibility and exclusive keyboard ownership must be resolved before
  attempting a live grabber test. Do not uninstall Karabiner as a way to make
  a test pass.

## Proposed configuration

Preserve the device guard; add an optional exact bundle-ID guard after it:

```text
.device builtin { vendor: 0x05AC, product: 0x0343 }

.remap caps_lock [device builtin] [app "com.mitchellh.ghostty"] {
    tap: f20
    hold: rctrl
}
.remap caps_lock [device builtin] [app "org.gnu.Emacs"] : passthrough
.remap caps_lock [device builtin] {
    tap: f20
    hold: lcmd
}
```

These examples parse in the development fork but are *not yet usable*:
the daemon rejects app-scoped rules before seizing a keyboard. The application
guard compares a literal bundle identifier, not a regex or display name.
The device IDs above describe the built-in keyboard on the current Mac;
they are not portable to every model. The `(0,0)` built-in alias also
matches this keyboard by internal-bus transport. The grabber now passes
the configured alias, rather than the reported hardware ID, to rule
selection when there is exactly one matched device class. This has an
offline unit test but has not been validated with physical capture.
Multiple app guards for the same source/device are legal only when their IDs
are distinct. At most one unguarded fallback is legal. An explicit
`passthrough` app rule overrides the fallback without rewriting that app's
key. Missing or invalid app identity fails open to physical-key behavior,
not to an arbitrary fallback. Existing configurations remain valid.

The complete migration must first enumerate the actual Karabiner rules,
including Terminal, Ghostty, Screen Sharing, Emacs/Portacle exclusions, and
other tap/hold keys. The example above is deliberately incomplete and must
not be installed as a replacement configuration.

## Runtime design

1. The user-session agent obtains the frontmost application's bundle ID and
   sends an initial identity with `apply_rules`, then sends changes over the
   existing persistent IPC connection. Version the agent/grabber protocol.
   The root grabber must accept only updates from the active subscription and
   must not infer the foreground app from a process display name.
2. The grabber stores app identity per subscription. On physical key-down it
   selects one exact app rule, then the fallback, or passes the key through.
   Latch that choice by physical device and source key through key-up, even
   if focus changes or the agent disconnects while a key is held. Feed
   non-source events only to the selected tap/hold engine as appropriate.
3. On lost/stale identity, agent death, console-user change, or failed virtual
   HID delivery, release synthesized held keys and stop seizing or pass raw
   events through. Never leave the keyboard captured with no working output.
   An app change must not rebuild/seize the keyboard; it changes only the
   selection context.
4. Keep the high-level skhd hotkey path independent. BetterTouchTool,
   YabaiSpaces, yabai, Hammerspoon, and the installed Karabiner configuration
   are outside this change.

## Test and rollout gates

1. Run `zig build test` and `zig build` with the pinned Zig 0.16.0 toolchain.
   Test parser precedence/conflicts, unknown app, passthrough, focus changes
   during a hold, agent disconnect, and duplicate physical devices. Add IPC
   tests for initial and changed app identity.
2. Update the virtual-HID protocol from upstream's source and test framing,
   enum values, readiness, and failure behavior against the installed
   DriverKit version. A successful `--status` alone is not a keyboard test.
3. Test in an isolated session/keyboard with a physical fallback, first
   verifying normal typing, then tap/hold, focus switches, sleep/wake, and
   recovery. Do not run two grabbers seizing the same keyboard. This Mac
   has no spare external keyboard, so any built-in-keyboard test needs an
   explicitly approved short timeout and automatic rollback; do not
   disable Karabiner merely to make an observe probe pass.
4. Only after all checks pass, stage a reversible local install and compare
   every migrated binding to Karabiner. Keep Karabiner as the rollback until
   the replacement is proven in daily use. If typing or modifiers become
   flaky, stop the grabber immediately and restore the prior state.

At baseline, `zig build` passed. `zig build test` compiled but failed three
pre-existing tests (two hotload tests require an event stream unavailable in
this execution environment; one hot-reload test failed command-template
parsing). These failures preceded implementation and must not be reported as
new regressions or silently "fixed" while working on this feature.

## 2026-10-20 transport progress

- The fork now uses DriverKit 8.5.0's fixed Unix stream socket, four-byte
  big-endian frame lengths, request IDs, protocol 7 payloads, and current
  request numbers. The old datagram socket search and wire decoder were
  removed. Incoming stream frames are buffered across partial reads.
- The grabber responds to server requests and heartbeats, and its watchdog
  releases the seize on stream failure or keyboard-not-ready status. This
  path has been build-tested and the codec/socket exercised with a local
  socket pair, but **not** tested against a live root DriverKit session.
- `zig build` and both relevant transport module tests pass. The full test
  suite still has the same three pre-existing failures as baseline. No
  app-specific parser, foreground identity transfer, or runtime dispatch
  exists yet.
- Do not install this fork or activate its grabber on the user's keyboard.
  The separate Karabiner ownership and live-injection gates remain open.

## 2026-10-20 app-rule model checkpoint

- `Mappings.TapHoldDecl` can retain an owned optional bundle ID and a
  passthrough flag. It allows distinct app IDs plus one fallback for a
  device/source pair while continuing to reject duplicate scopes and any
  collision with an old colon-form remap.
- `AppRuleSelector` specifies exact-app precedence over fallback, explicit
  passthrough, unknown-app fail-open behavior, and per-device/source
  key-down latching. These are isolated unit-tested policies, **not** live
  keyboard behavior. At this checkpoint the parser still rejected `[app ...]` syntax; accepting
  it before the grabber can enforce it would silently misapply bindings.
- Verification: `zig test src/Mappings.zig` with macOS frameworks passed
  41/41 tests; the selector's standalone tests passed 3/3. The agent-to-
  grabber identity path, physical-device identity, selected-slot dispatch,
  and fail-open recovery still need implementation and testing before any
  live rollout.

## 2026-10-20 protocol checkpoint

- At this historical checkpoint, the grabber IPC protocol was version 3 and could serialize the optional
  bundle-ID and passthrough fields on a tap-hold rule. The agent forwards
  those model fields, and the server owns copied bundle IDs for the
  lifetime of a subscription. Framing and rejection have focused tests.
- HID input events now carry the sending device's pointer identity, so a
  future selector can keep separate key latches for separate keyboards.
  The event does not yet carry a validated device alias or vendor/product
  match, and the selector is still not wired into live dispatch.
- The daemon **explicitly rejects** app-scoped rules rather than running
  them as unscoped rules. At this checkpoint the parser did not yet accept `[app ...]` syntax.
  Protocol v3 required matching agent and grabber builds; this fork must
  not be installed or mixed with the existing live service.

## 2026-10-20 foreground identity channel

- The agent now caches the exact bundle ID of the frontmost process using
  the Carbon event's process serial number, the process PID, and AppKit's
  running-application identity. The initial ID accompanies `apply_rules`;
  subsequent focus changes send framed `foreground_app` updates on the
  persistent socket. Unknown or invalid IDs become null, which is the
  fail-open state.
- The daemon buffers partial and consecutive update frames, validates their
  type and length, and stores the ID on the owning subscription. A malformed
  update closes that subscription so its seize is released. The decoder has
  offline tests; no live focus-switch or root-grabber test was run.
- HID events now carry a per-device pointer identity and cached vendor/product
  match. Unknown devices are explicitly marked unknown rather than being
  confused with a legitimate built-in `(0,0)` keyboard.
- App-scoped rules remain **rejected**. The existing grabber has one tap-hold
  engine per rule, not per physical keyboard. Sending one source event to
  every duplicate engine would emit duplicate keys, and even a selector
  alone cannot represent two keyboards holding the same source key at once.
  Selected-slot dispatch, per-device engine ownership, caps-lock passthrough
  behavior, and failure recovery must be solved and tested before accepting
  app guards in the parser or enabling them in the daemon.

Upstream protocol source: <https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/tag/v8.0.0>.

## 2026-10-20 parser and selected-slot checkpoint

- The parser accepts one optional `[app "bundle.id"]` guard after a required
  device guard. A scoped colon form accepts only `: passthrough`; other
  app-scoped actions use tap-hold blocks. Duplicate scopes, malformed IDs,
  and unsupported colon destinations fail parsing. Existing unscoped rules
  retain their previous grammar.
- Pure routing tests cover exact-app precedence, fallback, unknown-app
  passthrough, focus changes while held, legacy unscoped sources, and
  per-device latches. The dormant grabber path feeds only the selected slot
  for a scoped source and preserves the old loop when no scoped rules exist.
- Before scoped dispatch could start, it requires exactly one matched
  physical keyboard and one matching rule-device class. This temporary
  restriction avoids claiming multi-keyboard support while each tap-hold
  engine still owns only one physical press state.
- The IPC rejection remains intentional. Offline tests do not establish that
  DriverKit injection, Caps Lock passthrough, modifier release on failure,
  or focus updates work on real hardware. Do not install or enable the fork
  until those checks pass and the rejection is deliberately removed.

## 2026-10-20 offline readiness checkpoint

- Fixed the agent's `(0,0)` built-in presence gate. It previously looked
  for a keyboard without a VendorID, but this Mac reports `0x05ac:0x0343`.
  The gate now recognizes FIFO/SPI transport, matching the grabber's
  built-in device filter. The read-only live presence test passed while
  the installed Karabiner setup remained active.
- `--match-probe 0:0` found one built-in keyboard without opening it.
  An actual passive `IOHIDManagerOpen(.observe)` could not open that
  keyboard while Karabiner owned it; no service was stopped to force it.
- `zig build` and all changed-file format checks pass. Full `zig build
  test` reached 731/738 passed, four skipped, with the same three
  pre-existing hot-reload/event-stream failures. The generated test
  file was removed. Physical capture is still untested.

## 2026-10-20 active-configuration inventory and test boundary

- The selected Karabiner profile has seven single-manipulator rules:
  Caps Lock tap sends F20 with Control hold in terminals and Screen Sharing,
  and Command hold elsewhere with exclusions; Tab taps Tab and holds Control
  in terminals; Right Command taps F19; Right Shift taps F18; Right Option
  taps F19. The actual conditions include additional app identifiers and
  exclusions, so this summary is not a drop-in replacement configuration.
- Ordinary skhd hotkeys remain active in `com.jackielii.skhd`; the active
  `skhdrc` has no `.device` or `.remap` directive. The development fork is
  not installed. No Karabiner or skhd input service was changed.
- This installation uses Karabiner Core Service v2 agents and a privileged
  Core Service daemon, not the old `karabiner_grabber` launchd label shown
  in older repository instructions. Those commands must not be used as a
  rollback plan. Before any physical test, verify the *current* service
  control and an automatic timed restoration path without relying on a
  working keyboard. With no external keyboard available, defer the test
  until that restoration path is established and explicitly approved.
- A successful non-seizing virtual-keyboard output check and offline tests
  do not prove that exclusive capture, app switching, sleep/wake, or recovery
  work. Keep app-scoped rule rejection enabled until those gates pass.

## 2026-10-24 replacement-config draft

- `docs/KARABINER_MIGRATION.skhdrc` stages all seven active Karabiner
  manipulator behaviors as 24 `.remap` rules for this Mac's built-in keyboard,
  plus the four existing high-level skhd hotkeys. It is **not** installed.
- Protocol version 4 adds an optional `tap_modifier` HID usage so a tap can
  synthesize Right Command–F19 or Right Option–F19. Rebuild the agent and
  grabber together; do not mix protocol versions.
- The rule timing is an approximation of Karabiner's `to`/`to_if_alone`
  semantics, not a demonstrated match. Karabiner's modifier eligibility,
  the Fn/function-key mappings, unknown foreground apps, and physical
  behavior of the new modifier-tap output still require comparison.
- The development grabber remains default-off and Karabiner remains the
  keyboard owner. No active config, service, or Caps Lock behavior changes
  until physical tests with an independently verified timed rollback pass.

## 2026-10-24 additional guarded checks

- Short physical tests confirmed the staged Right Shift, Ghostty Tab,
  Ghostty Caps Lock Control hold, and ChatGPT Caps Lock Command fallback
  tap/hold outputs. Right Shift tap opened the YabaiSpaces panel. A
  focus-switch attempt for Caps fallback was ambiguous; the fallback
  was instead verified in a fresh ChatGPT-only run.
- Offline selector, foreground-update, bundle-ID, and parser tests passed
  for explicit passthrough, unknown-app fail-open, and identity updates.
  Emacs and Portacle exclusions have not been physically tested in their
  target apps; the local Emacs alias is unresolved and Portacle was absent.
- In one guarded physical test, SIGKILL of only the development agent
  closed its subscription and the root grabber logged `released seize`.
  The user confirmed normal typing before and after; Karabiner and the
  independent one-shot rollback both restored successfully. This does
  not establish recovery from a hung/root-killed grabber, a disconnect
  with a modifier held, sleep/wake, or an unattended one-hour session.
- A later guarded root-grabber test exposed an unresolved termination
  issue: SIGTERM did not promptly stop the grabber while it held an
  active capture/subscription. The separate one-shot watchdog then
  force-killed it and restored Karabiner (`RESTORE_EXIT=0`); the user
  confirmed normal typing. SIGTERM did stop an isolated no-rules grabber.
  The planned SIGSTOP simulation was not run after this unexpected
  result. Do not treat one successful forced rollback as sufficient for
  an unattended one-hour trial.
- A later guarded comparison found Karabiner's active root Core Service
  exited promptly on SIGTERM while the development grabber had not. The
  fork's custom TERM/INT/HUP handler was removed; stale IPC sockets are
  already removed on startup, and default process termination releases
  the HID seize. The rebuilt, signed development grabber exited within
  two seconds of SIGTERM while actively seized and subscribed. The
  temporary launchd test job respawned it and was explicitly removed;
  the one-shot rollback then found no grabber and restored Karabiner.
  Offline build/rebind checks passed; full tests retained the three
  documented hot-reload failures. The exact old-handler blocking point
  remains unproven, and this single live success is not a long-run or
  hung-process recovery guarantee.
- The user confirmed normal typing after restoration but did not type
  during that capture window; it was a shutdown test, not a new
  pass-through test. They chose to defer Emacs/Portacle exclusions and
  sleep/wake checks. Neither is a gate for the next reversible trial,
  but both remain unverified.
- A subsequent guarded SIGSTOP test paused the root grabber while it had
  one active subscription and one seized built-in keyboard. The independent
  one-shot rollback killed it at its 60-second deadline, removed the test
  job, and restored both Karabiner agents (`RESTORE_EXIT=0`). The user
  confirmed normal typing after STOP. The rollback script was changed to
  kill before bootout so a frozen process cannot delay keyboard release.
  This is one successful paused-process recovery, not proof against every
  hung state or an unattended trial.
