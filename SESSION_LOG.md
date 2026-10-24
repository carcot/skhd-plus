# Session log

## 2026-10-24: default-off app-scoped runtime test gate

- After the user's confirmation that the Left Shift tap/hold test behaved
  correctly and ordinary typing recovered, inspected the development
  fork's app-scoped IPC rejection and selected-slot routing. Added
  `--experimental-app-scoped-rules` to the grabber; without this explicit
  flag, IPC still rejects app-scoped and passthrough rules. The flag has
  not been used on a live grabber or installed into the signed test app.
- The opt-in validates device guards, exact bundle IDs, duplicate app
  scopes, and passthrough app identity before accepting rules. The focused
  IPC gate test passed, `zig fmt --check` passed after each source edit,
  and an offline `zig build` passed. A CLI preflight confirmed the flag is
  listed in help, requires a separate socket, rejects combination with
  standalone `--seize-test`, and that invalid duration still aborts before
  capture.
- No active keyboard service, configuration, or installed binary changed.
  App switching, foreground IPC, fail-open behavior, and client disconnect
  remain untested on physical input. Default enablement remains blocked.
- Added `--grabber-socket <path>` to the development agent so a separate
  `-V -c <minimal-config>` process can connect to the isolated test daemon
  while the installed ordinary skhd service keeps its default socket.
  The option refuses to run without foreground mode and an explicit
  config. Offline `zig build`, CLI rejection checks, and the focused IPC
  gate test passed. No second agent or test daemon was started.
- Added F21–F24 names to the HID key map and unit-tested F23/F24 lookup.
  Prepared a minimal Left Shift fixture with a Ghostty-specific F23 tap,
  an F24 fallback tap, and identical Left Shift holds. The rebuilt
  development agent parsed it and attempted to forward two rules to a
  deliberately nonexistent custom socket, then exited; no grabber or
  input capture ran. `zig ast-check` and the two `HidKeyMap` unit tests
  passed. `zig fmt --check` on that file reports existing whole-file
  spacing differences, which were left untouched to keep the patch
  focused. A subsequent offline `zig build` passed.
- Read-only signing inspection found the installed ordinary skhd app uses
  `skhd-cert`, while the separate development grabber uses the available
  Apple Development identity. Do not assume a newly built second agent
  inherits the installed app's event-tap privacy grants. No second agent
  was launched, and no active keyboard process or config was replaced.

## 2026-10-24: isolated Left Shift tap/hold capture

- With a fresh 60-second independent root rollback armed, stopped both
  Karabiner user agents from the actual user session and confirmed they
  were absent. Ran a 20-second development-grabber test with one temporary
  rule: Left Shift (`0xE1`) taps F24 (`0x73`) and holds Left Shift after
  200 ms. F24 had no active high-level skhd binding. This did not change
  Caps Lock, the active configs, or the installed ordinary skhd service.
- The user received separate START and STOP signals to tap Left Shift,
  then hold it while typing `abc`, in the Codex message box. The grabber
  exited normally and released the physical keyboard. Its log recorded
  two tap commits emitting F24 down/up and multiple hold commits emitting
  Left Shift down/up; `events forwarded=65`, with no logged error. The user
  subsequently confirmed that held Shift produced uppercase `ABC` and
  released Shift produced lowercase `abc`. This verifies basic tap/hold
  behavior for the temporary rule in one short observed test.
- Restored Karabiner's agents immediately. The one-shot rollback later
  fired, found no grabber process, and completed with `RESTORE_EXIT=0`.
  Read-only checks showed Karabiner Core and ordinary skhd running, with
  no grabber. The user confirmed normal typing after restoration.

## 2026-10-24: observed typing window recorded HID events

- After the user confirmed the previous window had no intentional typing,
  prepared another 60-second independent root rollback and verified the
  signed development app and active service state. From the actual user
  session, stopped both Karabiner agents and confirmed both launchd labels
  absent before capture. The user received separate do-not-type, START,
  and STOP signals for typing into the Codex message box without Return.
- The 20-second `--seize-test 0:0` exited normally, released the physical
  keyboard on schedule, and reported `events forwarded=473` with no error
  or warning in the capture log. This establishes that the grabber received
  and attempted to forward physical HID events during the observed window.
  The user subsequently confirmed that letters appeared normally in the
  message box, establishing basic typing pass-through for this short test.
- Karabiner's agents were immediately restored from the user session.
  The one-shot rollback later fired, found no grabber, and registered
  both agents with `RESTORE_EXIT=0`. Read-only checks showed Karabiner
  Core and ordinary skhd running, with no grabber process. The user also
  confirmed that typing remained normal after restoration. This does not
  validate tap/hold, app-scoped remaps, sleep/wake, or prolonged use.

## 2026-10-24: bounded seize reached physical keyboard; input unverified

- A separate, rollback-guarded control check showed that running
  `unregister-core-agents` in the actual user session removes both
  Karabiner agents from launchd. Running `register-core-agents` in that
  session restored them. This differs from invoking the same subcommand
  under `sudo -u` inside a root script, which printed an error but returned
  success. The independent agent-check rollback also fired and completed.
- Armed a fresh 60-second one-shot root rollback, used the verified
  user-session command to stop Karabiner's agents, and confirmed both
  labels were absent before capture. A signed development grabber then
  seized one built-in keyboard for 12 seconds and released it on schedule
  (`CAPTURE_EXIT=0`). The user was told when to start and stop typing.
- The grabber log recorded **zero forwarded events** during that window.
  Therefore this proves bounded physical seize/release, not typing
  pass-through. It is not yet known whether keys were actually pressed
  while the grabber owned the keyboard; obtain the user's observation
  before deciding whether to investigate event delivery or repeat the
  test. No tap/hold or app-scoped rule was tested.
- Karabiner's agents were immediately restored from the user session.
  The independent rollback later fired once, found no grabber, and
  registered the agents with `RESTORE_EXIT=0`. Read-only checks showed
  Karabiner Core and ordinary skhd running with no grabber process.
  Physical typing after the attempt still needs user confirmation.

## 2026-10-24: guarded capture attempt aborted before keyboard ownership

- Built the development fork, installed a newly Apple Development-signed
  `/Applications/skhd-grabber-dev.app`, and verified its designated
  requirement outside the restricted shell. The installed executable now
  includes the 1–60-second duration limit and explicit virtual-keyboard
  termination. The ordinary skhd app and active configs were not replaced.
- Armed a root-owned, launchd-managed, 35-second one-shot rollback before a
  proposed 12-second pass-through test. The user was told when to type and
  when to stop. The test initialized virtual HID but `IOHIDManagerOpen`
  returned `0xE00002C5` (`DeviceAlreadySeized`); no physical keyboard
  capture occurred and no typing pass-through was established.
- Root cause of this aborted attempt: the root script's
  `sudo -u carlcotner ... unregister-core-agents` printed `Operation not
  permitted` but returned success, so its exit-code check was inadequate.
  Karabiner remained the keyboard owner. The script's immediate register
  step likewise printed errors despite returning success. Do not rerun it
  unchanged. Service-control success must be confirmed by launchd state,
  using the user's actual GUI session, before any grabber is launched.
- The independent rollback fired once, found no grabber process, and
  successfully re-registered both Karabiner agents (`RESTORE_EXIT=0`).
  Read-only checks then found no grabber process and showed the Karabiner
  agent and Core daemon running. Physical typing after the attempt still
  needs user confirmation. No further capture attempt was made.

## 2026-10-24: offline seize-test virtual keyboard cleanup

- The standalone exclusive-capture test initialized Karabiner's virtual
  keyboard but only closed the vhidd socket on exit. Unlike the existing
  vhidd readiness probes, it did not send
  `virtual_hid_keyboard_terminate`. The test now sends that request on
  normal return and error unwinding after initialization, after releasing
  its physical HID seize and before closing the socket.
- Verification: `zig fmt --check src/grabber/main.zig` and an offline
  `zig build` passed. No physical keyboard was seized, no installed binary
  was replaced, and no input service was restarted. This does not prove
  recovery after `SIGKILL`, which cannot execute process cleanup, or
  explain the prior repeated-key symptom. Live capture remains paused.

## 2026-10-24: repeated typing recovered by restarting Karabiner Core

- After the failed live grabber test and its SIGKILL recovery, quick letter
  taps began showing macOS's accent picker. There was no custom global
  press-and-hold preference, Slow Keys was off, the active Karabiner/skhd
  config hashes were unchanged, and no skhd grabber process or service
  remained. Setting `ApplePressAndHoldEnabled=false` removed the picker in
  a newly opened TextEdit, but exposed doubled letters there and in the
  other affected apps; it did not fix the input fault.
- With the user's explicit approval to restart keyboard processes one at
  a time, ran `launchctl kickstart -k` only for
  `system/org.pqrs.service.daemon.Karabiner-Core-Service`. Its root PID
  changed from 538 to 95878 and the service returned to `state = running`.
  The user then confirmed that typing worked normally. The shared virtual-
  HID daemon, ordinary skhd service, Caps Lock config, and active mappings
  were not changed. A stale Karabiner Core input state is plausible, not
  proven; app-specific hotkeys and tap/hold remaps were not retested.
- Verification: confirmed no skhd grabber process or service, checked the
  restarted Karabiner Core service, and received the user's physical typing
  confirmation. No reboot or further capture was needed. The global
  `ApplePressAndHoldEnabled=false` preference remains in place by request
  to avoid the accent picker; remove that preference to restore macOS's
  default accent-picker behavior if desired later.

## 2026-10-23: one-shot rollback dry-run, no keyboard capture

- Replaced the failed `launchctl submit` timer design with a root-owned
  launchd plist using `RunAtLoad=true`, `KeepAlive=false`, and
  `LaunchOnlyOnce=true`. The rollback script lives in the checkout but was
  copied to a root-owned private directory before launch. It boots out a
  grabber service, force-kills any `skhd-grabber`, verifies none remain,
  and then restores Karabiner agents.
- A signed dummy `sleep` executable named `skhd-grabber` ran as root; it
  never touched HID. The watchdog killed it after three seconds and
  returned `RESTORE_EXIT=0`. Both test jobs disappeared from launchd, the
  log recorded only one execution after a further 12-second wait, and the
  temporary root-owned directory was removed. Karabiner and ordinary skhd
  stayed running.
- Root cause of the prior excessively long test was the CLI duration unit:
  `--seize-test-duration` accepts seconds, so `18000` meant 18,000 seconds.
  The development grabber now rejects values outside 1–60 seconds before
  capture. `zig fmt --check`, `zig build`, and CLI checks passed: 18 seconds
  is accepted, while 0 and 18,000 seconds return exit code 2. The installed
  grabber binary was not replaced.
- This validates only the independent one-shot timer and process-kill path
  against a harmless dummy. Real HID release, typing pass-through, and
  post-capture Karabiner remaps are still unverified. No further physical
  capture was attempted; that stop gate remains in force.

## 2026-10-23: exclusive capture failed; keyboard recovered

- A signed development grabber seized the built-in keyboard and received
  physical key events. Its debug log recorded emitted key reports, but this
  does not establish that characters reached Ghostty.
- The test command mistakenly passed `--seize-test-duration 18000`, which
  means **18,000 seconds**, not 18 seconds. The outer 30-second timeout
  ended the invoking command but left the root grabber process alive and
  the user unable to type. Karabiner's agents were running, but could not
  recover the keyboard while that process still owned it.
- The initial root rollback script's `killall skhd-grabber` sent a normal
  termination signal that did not stop the grabber. A corrected script
  restored Karabiner agents, but it was not sufficient to release input.
  An authenticated `kill -KILL` of the specific root grabber PID did stop
  it. The user then confirmed that typing worked again.
- A separate launchd dry-run also showed that `launchctl submit` restarted
  a completed timer job rather than making it one-shot. All test timer jobs
  were removed. The regular `com.jackielii.skhd` agent, Karabiner Core
  daemon and agents remain running; no skhd grabber service was installed.
- **Stop gate:** no more exclusive grabber tests or Karabiner replacement
  attempts. Before any later test, redesign and prove a genuinely one-shot,
  independent rollback that force-kills a stuck root grabber, then restores
  Karabiner; separately fix duration units and obtain a fresh user go-ahead.
  Today's capture cannot be counted as a successful pass-through test.
- Verification: read the capture log and process list, confirmed the root
  grabber PID disappeared after SIGKILL, confirmed Karabiner and ordinary
  skhd services running, and received the user's confirmation of restored
  typing. No source, active config, Caps Lock rule, or installed production
  binary was changed.

## 2026-10-23: signed grabber privacy grant and passive HID access

- System Settings visibly showed `skhd-grabber-dev` enabled in Input
  Monitoring. The signed bundle at `/Applications/skhd-grabber-dev.app`
  still passed strict/deep signature verification.
- Armed an independent Karabiner-agent restore timer, paused Karabiner's
  agents, and ran the signed bundle in four-second **observe-only** mode.
  It opened one built-in keyboard with non-seizing options `0x0`, used a
  no-op callback, and exited successfully. No virtual keyboard, reposting,
  physical seize, or test key was involved.
- Restored both Karabiner agents and verified all prior services running;
  removed the timer. Config hashes stayed unchanged and no skhd grabber
  service was installed. Exclusive capture and typing remain untested and
  require a fresh root rollback plus the user's active participation.
- `zig build` and `git diff --check` passed after documentation edits.

## 2026-10-23: separate signed grabber prepared, no capture

- Created `zig-out/skhd-grabber-dev.app` with its own bundle ID and signed
  it using the existing Apple Development identity (team `7CJ3BM3AGT`).
  Plist lint and unsandboxed strict/deep signature verification passed.
- The signed development executable reported its version and found one
  built-in keyboard via `--match-probe 0:0` without opening a device.
  Karabiner remained active; no skhd grabber was installed or started.
- Input Monitoring for this separate bundle remains ungranted/unverified.
  The real root rollback action has not run, and physical capture remains
  blocked. Do not launch the grabber via `zig build run-grabber` yet.
- Copied the signed bundle to `/Applications/skhd-grabber-dev.app` under its
  distinct development bundle ID; unsandboxed strict/deep signature
  verification passed there. It was not launched and did not replace the
  installed skhd app. Privacy approval remains a user-facing step.
- `zig build` and `git diff --check` passed after documentation edits.

## 2026-10-23: privileged rollback mechanics proven on dummy services

- Native macOS administrator authorization worked without storing a
  password. A root-owned launchd job in the system domain wrote a marker
  after eight seconds. A second timed root job booted out a disposable
  root-owned sleep service (`bootout_rc=0`); the target disappeared.
- Root-to-user-session dispatch returned UID 501. Removed all disposable
  jobs and verified the Karabiner Core daemon remained running and no skhd
  grabber existed. No keyboard service or mapping changed.
- The development grabber remains ad-hoc signed; a separate Apple
  Development identity exists outside the restricted shell, but a stable
  development bundle and Input Monitoring grant still need preparation.
  The actual stop-grabber/restore-Karabiner rollback command has not run,
  and no physical capture has been attempted.
- `zig build` and `git diff --check` passed after the runbook update.

## 2026-10-22: Karabiner agent restoration verified, capture still gated

- Armed an independent 60-second user-session launchd restore timer before
  temporarily unregistering Karabiner Core agents. Both the Core agent and
  Console User Server disappeared from launchd; `register-core-agents`
  returned success and both came back running. Removed the timer after
  verification. The root Core daemon and shared virtual-HID daemon stayed
  running; no skhd grabber was registered or started.
- Active Karabiner/skhd config hashes were unchanged and installed skhd
  still reported functional high-level hotkeys. Physical typing and the
  user's tap/hold behavior remain unverified until user confirmation.
- The user-session timer cannot stop a root-owned grabber. A privileged,
  independent rollback still needs administrator authentication and proof
  before any skhd keyboard capture. App-scoped rules remain rejected.
- `zig build` and `git diff --check` passed after documenting this check.

## 2026-10-22: keyboard rollback preflight, no input changes

- Reconfirmed Karabiner Core daemon/agent and shared virtual-HID daemon
  running; installed skhd agent hotkeys functional; no skhd grabber service.
  Shell `skhd` resolves to the app-bundled binary.
- Saved matching copies of the active Karabiner and skhd configs in a
  private temporary directory. The current Karabiner profile is `Default
  profile`. A launchd-owned, user-session eight-second marker timer fired
  and was removed; Karabiner remained active throughout.
- `sudo -n` requires a password, so a root-owned rollback timer has not
  been installed or validated. Do not stop Karabiner or seize the built-in
  keyboard until that independent privileged fallback is proven. No
  Karabiner control subcommand was executed.
- Verification: `zig build` and `git diff --check` passed after documenting
  the preflight. No active mapping, service, Caps Lock behavior, or keyboard
  ownership changed.

## 2026-10-20: reversible built-in-keyboard test plan

- Created `docs/KEYBOARD_CAPTURE_TEST.md` after read-only inspection of
  this Mac's Karabiner Core Service v2 launchd registrations, installed
  plists, active configs, and upstream quit/service documentation.
- The old `karabiner_grabber` label is absent. Karabiner's current Core
  agent and privileged daemon are SMAppService-managed with KeepAlive;
  killing a process or uninstalling the shared virtual-HID driver is not
  a safe test plan. The installed agent binary has paired unregister and
  register subcommands, but restoration has not been tested locally.
- The runbook requires an independently proven, privileged timed rollback
  that releases a skhd seize first, then restores Karabiner; it separates
  basic pass-through input from later tap/hold and app-scope testing.
- Verification: `zig build` and `git diff --check` passed after writing
  the runbook. No service, active config, keyboard ownership, or Caps Lock
  behavior was changed; no live test was attempted.

## 2026-10-20: built-in alias routing and no-keyboard rollback gate

- Root cause: the built-in `(0,0)` alias matches by FIFO/SPI transport,
  but its input events report the real `0x05ac:0x0343` hardware ID.
  App-scoped candidates keyed to `(0,0)` would not route those events.
  When exactly one device class is configured, HID events now use that
  configured alias for rule selection. Multi-class events retain their
  reported IDs; app-scoped multi-class capture is still rejected.
- Verification: `zig build`, `zig fmt --check` for `HidSeize.zig`, and its
  focused tests passed (3 passed, one opt-in live test skipped). The daemon
  still rejects app-scoped rules before capture, so this is offline-only.
- Read-only inventory found seven active Karabiner rules and no active
  `.device`/`.remap` in skhd. Current Karabiner uses Core Service v2; the
  repository's old `karabiner_grabber` bootout instruction names no service
  on this installation. The fork's conflict check now recognizes both
  `Karabiner-Core-Service` and legacy `karabiner_grabber` process names.
  Updated rollout docs and README to require verified service control and
  automatic rollback before any built-in-keyboard test.
- Verification: the final build, source formatting, and diff whitespace
  checks passed. The sandbox cannot query processes (`pgrep` reports no
  process list), so the revised conflict warning was not live-verified.
- No installed service, configuration, Caps Lock behavior, or live keyboard
  capture was changed. With no external keyboard, physical testing remains
  deferred; the development tree is uncommitted.

## 2026-10-20: built-in presence gate and offline readiness

- Root cause: `DeviceCheck.isPresent(0,0)` treated a missing VendorID as
  proof of an internal keyboard. This Mac's built-in SPI keyboard does
  report `0x05ac:0x0343`, so that gate could skip the grabber even while
  the matching physical keyboard was connected.
- The agent now recognizes FIFO/SPI transport for the `(0,0)` alias,
  matching the grabber's filter. An opt-in, read-only live test passed
  while Karabiner stayed active; focused tests passed 4/4.
- Full `zig build test` reached 731/738 passed, four skipped, with the
  same three known hot-reload/event-stream failures. Its generated file
  was removed. `zig build`, all changed-file format checks, and
  `git diff --check` pass. The stale hardware example and rollout gate
  were corrected in `docs/APP_SCOPED_REMAPS.md`.
- No installed service, key mapping, Caps Lock behavior, or physical
  keyboard capture was changed. The working tree remains uncommitted.

## 2026-10-20: read-only device-match preflight

- Outside the restricted shell, installed `skhd --status` reports the
  app-bundled service enabled, hotkeys functional, Input Monitoring
  granted, and no skhd grabber running. This corrects the misleading
  sandbox-only status in the earlier checkpoint.
- The corrected passive observer still cannot open the built-in
  keyboard while Karabiner owns it: `IOHIDManagerOpen(.observe)` returned
  `DeviceAlreadySeized`. We did not stop Karabiner or alter its rules.
- Added `--match-probe V:P`, which uses the same HID matching filter but
  only copies the matched-device set; it does not open a device, watch
  input, initialize virtual HID, or require root. It reports one match
  for built-in `(0,0)`, one for `0x05ac:0x0343`, one for Karabiner's
  `0x05ac:0x024f` virtual keyboard, and zero for an absent alias.
  This verifies the built-in transport match excludes the virtual HID.
- Verification: `zig build`, formatter for `HidSeize.zig`, and
  `git diff --check` passed after edits. No physical keyboard capture
  or installed-service change was made. A true input-path test remains
  gated on an isolated keyboard/session and a safe fallback.

## 2026-10-20: passive-probe permission boundary

- A one-second `--seize-test-observe` attempt returned
  `IOHIDManagerOpen(.observe) = NotPermitted` before any capture, virtual
  keyboard initialization, or key reposting. The Codex shell also could
  not query processes or the window server reliably; these sandboxed
  results do not establish the installed service's desktop status.
- Read-only `skhd --list-devices` did enumerate the built-in SPI keyboard
  (`0x05ac:0x0343`) and Karabiner virtual keyboard (`0x05ac:0x024f`).
  The shell's `skhd` symlink still resolves to the app-bundled binary.
- Corrected the grabber's open-error log to name `.observe` rather than
  incorrectly saying seize failed. `zig build`, formatter, and
  `git diff --check` passed. No permission setting or installed service
  was changed; do not repeat the denied probe in this environment.

## 2026-10-20: genuinely passive observe diagnostic

- Root cause: `--seize-test-observe` previously followed the seize-test
  path: it demanded root, initialized virtual HID, and reposted copied
  physical events. Because observe mode also lets macOS receive those
  events, running it could duplicate keystrokes.
- Observe mode now opens only an IOHIDManager observer with a no-op
  callback. It does not initialize virtual HID, repost keys, or apply
  tap-hold rules, and it requires no root. The CLI rejects an observe
  flag without a device and rejects rules in observe mode before opening
  any device. The actual passive match probe was not run, to avoid a
  new macOS Input Monitoring prompt during this offline checkpoint.
- Verification: `zig build`, `git diff --check`, and both early-rejection
  CLI cases passed. No physical keyboard capture or installed change.

## 2026-10-20: disable capture on unrecoverable report errors

- Root cause: virtual-HID report construction errors such as
  `TooManyKeys` and `PayloadTooLarge` were intentionally excluded from
  transport reconnects, but the daemon then kept the keyboard seized
  while the rejected report could not reach macOS.
- The daemon now latches a capture-disabled state for these errors and
  schedules teardown between run-loop callbacks. It does not reconnect
  or re-seize on later rule updates, wake, or device changes; a manual
  daemon restart is required. Transport errors retain normal recovery.
- Verification: `zig build`, all 12 focused virtual-HID tests, and
  `git diff --check` passed. This is offline safety work; no live
  capture or installed-service change.

## 2026-10-20: heartbeat-only liveness deadline

- Root cause: the virtual-HID read loop renewed its liveness deadline
  for every incoming frame, including replies to requests. Such traffic
  could mask missing heartbeats and delay release of a stale seize.
- Only actual heartbeat frames now renew the deadline. Ready=false and
  driver-version-mismatch responses still trigger immediate recovery;
  unrelated frames do not certify session liveness.
- Verification: `zig build` and `git diff --check` passed. No live
  grabber, service, or keyboard configuration was changed.

## 2026-10-20: bound virtual-HID socket writes

- Root cause: the grabber posted keyboard reports over a blocking Unix
  socket from its HID input callback. If the virtual-HID server stopped
  reading without closing the socket, that callback could block and
  prevent the same run loop's heartbeat watchdog from releasing seize.
- The DriverKit socket now has a 500 ms send timeout set before a
  keyboard can be captured. A timed-out send follows the existing
  transport-error recovery path, which releases seize between callbacks.
- Verification: all 6 focused stream tests passed, including a macOS
  `getsockopt` check of the timeout; `zig build`, formatter, and
  `git diff --check` passed. No live capture or installed-service change.

## 2026-10-20: fail-open post-wake verification

- Root cause: after wake, the grabber could keep a keyboard seized if
  its verification timer allocation failed. A stale seize would then
  have no scheduled self-healing check.
- Timer creation failure now tears down the seize immediately, returning
  physical keyboard input to macOS rather than relying on a check that
  cannot run. This does not change Caps Lock rules or the installed service.
- Verification: `zig build` and `git diff --check` passed. No live
  keyboard capture or service change was made.

## 2026-10-20: fail-closed HID device matching

- Root cause: a CoreFoundation allocation failure while constructing a
  keyboard match dictionary silently omitted the failed key. Omitting a
  vendor, product, transport, or keyboard-usage constraint could broaden
  the IOHIDManager filter and capture unintended devices.
- Match-key builders now return errors, so dictionary construction stops
  before the manager can open with a partially constrained filter.
- Verification: `zig build`, `zig fmt --check src/grabber/HidSeize.zig`,
  and `git diff --check` passed. The full `zig build test` reached
  725/729 passed, one skipped, with the same three pre-existing
  hot-reload/event-stream failures and six leaks. Its generated test
  file was removed. No physical keyboard was captured and no installed
  service or mapping changed.

## 2026-10-20: post-ready settle before capture

- Root cause of a remaining first-key race: the validated debug probe
  waited 500 ms after DriverKit reported the virtual keyboard ready,
  but the daemon would capture a physical keyboard immediately. The
  service logs showed macOS/Karabiner device observation lagging the
  ready signal, so an early physical key could be lost.
- The daemon now waits 500 ms before installing the watchdog and
  capturing a keyboard when it creates a new virtual-HID client. The
  physical keyboard remains unseized during the wait; a failed wait
  aborts before capture. Existing ready clients on rule re-apply do
  not incur another delay.
- Verification: `zig build`, 11/11 focused virtual-HID tests, and
  `git diff --check` passed. This is an offline safety change only;
  no physical-keyboard capture or installed-service change was made.

## 2026-10-20: fail-closed virtual-HID watchdog setup

- Root cause: the daemon could proceed to physical-keyboard capture if
  its virtual-HID read source or heartbeat deadline timer could not be
  created. If recovery-timer allocation also failed later, it logged
  an error but left the keyboard captured.
- Watchdog setup now returns an error before publishing the virtual-HID
  client or starting capture; partial run-loop resources are released.
  A failed deadline re-arm triggers the existing recovery path. If the
  recovery timer cannot be created, the daemon immediately stops the
  physical-keyboard capture and requires a manual restart.
- Verification: `zig build` passed after each source edit; full
  `zig build test` reached 725/729 passed, one skipped, with only the
  same three pre-existing hot-reload/event-stream failures and six
  leaks. The generated test file was removed; `git diff --check` passed.
  No live keyboard test or installed-service change was made.

## 2026-10-20: post-crash offline safety checkpoint

- Kept the app-scoped rule rejection in place: selected-slot routing is
  tested, but a slot still owns one tap/hold engine shared across physical
  keyboards. The current one-keyboard check occurs after capture starts,
  so it is not a sufficient preflight for general deployment.
- Updated the rollout document to distinguish one delivered virtual key
  from a safe physical-keyboard capture test. No live input test, installed
  service, or Karabiner setting was changed in this checkpoint.
- Verification: `zig build` and all 7 focused selector tests passed;
  `git diff --check` passed. Full `zig build test` reached 725/729 tests
  passed, one skipped, with the same three existing hot-reload/event-stream
  failures and six leaks. Removed the test-generated file afterward.

## 2026-10-20: virtual-keyboard identity and delivery

- Root cause of the setup prompt: both the fork and a minimal upstream
  DriverKit client used the old default vendor/product IDs `0x16c0:0x27db`.
  The user's active Karabiner virtual keyboard advertises Apple
  `0x05ac:0x024f`; Karabiner's release notes document this identity
  change. The upstream client also sent `a` successfully while TextEdit
  remained blank, so the old fork's report codec alone did not explain
  the failure.
- Aligned the fork's virtual-keyboard default IDs with the currently
  active Karabiner keyboard and added byte-level assertions to the
  initialization test. All 11 focused virtual-HID tests and `zig build`
  passed immediately after the edit.
- A single non-seizing TextEdit probe with the new IDs visibly entered
  `a`; the probe logged ready, keydown, keyup, and normal completion.
  This verifies one delivered virtual key without physical capture.
- TextEdit subsequently crashed while the test automation attempted to
  read/close its unsaved document. The crash report shows an
  `NSRangeException` in TextEdit's document-save path; causality with
  virtual input is not established. Stopped the stuck automation and
  all live keyboard testing. No grabber, service, or input mapping was
  installed or changed. Physical seize and app-scoped rules remain
  blocked pending a safer end-to-end test.

## 2026-10-20: permission hypothesis checked

- Rechecked the failed 09:55 test against Karabiner service logs and the
  macOS unified log. The virtual keyboard was created, opened by the
  system HID event driver, and observed by Karabiner before the probe
  closed it. No relevant report-post error or permission denial appeared.
- `systemextensionsctl list` reports the Karabiner DriverKit extension
  as `[activated enabled]`. This makes an unapproved extension dialog an
  unlikely explanation for the blank text dialog, though it does not
  establish where the key was lost.
- The Ghostty execution prompt was a separate, app-local permission for
  the temporary observer script. That test was aborted before injection.
  No settings, installed services, physical keyboard capture, or live
  input mapping were changed.

## 2026-10-20: clean delivery check still failed (fork only)

- Repeated the app-local text-dialog test with no user typing or app switch.
  The probe received virtual-keyboard readiness and sent `a` down/up,
  but the dialog timed out empty. A System Events `a` control entered
  `a` in the same dialog, confirming that it could accept synthetic text.
- Increased the debug probe's post-ready wait to 500 ms, keydown hold to
  200 ms, and post-keyup lifetime to 2 s. `zig build` passed after each
  source edit. Repeating the clean test still produced no text.
- The local DriverKit v8 source matches the fork's request number and
  67-byte keyboard-report layout. Service logs show readiness and a
  connected peer, without a report error; socket-send success is not
  proof of delivery to macOS.
- Added an offline socket-pair test asserting the exact keyboard report
  request bytes (protocol, request, report ID, modifier, key, padding).
  All 11 focused virtual-HID tests and `zig build` passed. Corrected the
  debug command's help text to match its current `a` probe.
- Attempted a one-key Ghostty observer, but Ghostty showed a script
  execution-permission prompt instead of a ready terminal. Aborted the
  armed sender before any key was injected and dismissed the prompt.
- Root cause remains undetermined. Virtual-key delivery is **not**
  verified, so physical-keyboard seizure and installation remain blocked.
  The user's Karabiner, high-level skhd, and YabaiSpaces setup was not
  changed. No commit or push was made.

## 2026-10-20: attempted app-visible virtual-key delivery

- Tried Karabiner EventViewer as a non-invasive observer, but it lacked
  Input Monitoring permission. Closed it without changing privacy settings.
- Used a temporary self-closing text dialog as an app-local target and
  ran the existing `--inject-test-key` command twice under administrator
  authentication. Both runs reported ready and sent `a` down/up without
  socket errors; neither seized the physical keyboard.
- The first dialog timed out empty. The second returned `asdf`, but a
  different application was frontmost in the post-send screenshot and
  the text cannot be attributed solely to the injector. Delivery is
  therefore **inconclusive**, not passed. No more keys were injected.
- Confirmed the Karabiner virtual-HID service remained running and
  removed the temporary dialogs, screenshots, FIFOs, and markers.
  No installed service, keyboard binding, or privacy permission changed.

## 2026-10-20: virtual-keyboard F24 post probe

- Added `skhd-grabber --vhidd-post-probe` to initialize the virtual
  keyboard, wait for readiness, send F24 down/up reports, terminate, and
  disconnect. The physical keyboard is never seized. F24 was chosen
  after checking the active Karabiner, skhd, and Hammerspoon config files
  for an F24 binding; no match was found there.
- `zig build` passed immediately after the edit. The authenticated probe
  completed without a send error; the Karabiner virtual-HID service
  remained running. All 10 focused virtual-HID tests and
  `git diff --check` passed.
- This verifies acceptance of the down/up reports by the socket client,
  not that macOS delivered an observable F24 event. Physical seize,
  tap/hold behavior, and recovery remain untested. No installed service
  or input configuration was changed.

## 2026-10-20: non-capturing virtual-keyboard readiness probe

- Added `skhd-grabber --vhidd-ready-probe` to connect, initialize a
  virtual keyboard, wait up to five seconds for the DriverKit ready
  signal, then terminate that virtual keyboard and disconnect. It does
  not inject keys or seize a physical keyboard.
- `zig build` passed immediately after the source edit. The authenticated
  probe reported `vhidd virtual keyboard ready`, exited successfully,
  and Karabiner's virtual-HID service remained running. All 10 focused
  virtual-HID tests passed; `git diff --check` passed.
- This verifies initialization and readiness, not actual key injection,
  physical-keyboard seizure, tap/hold dispatch, or failure recovery.
  The installed input configuration was not changed.

## 2026-10-20: non-capturing DriverKit connection probe

- Added `skhd-grabber --vhidd-probe`, which only opens and closes the
  virtual-HID service socket. It does not initialize a virtual keyboard,
  inject a key, seize a device, or modify an installed service.
- `zig build` passed immediately after the edit. Running the probe both in
  and outside the sandbox as the normal user returned `ConnectFailed`.
  The service is running, but its socket is inside a root-owned `0700`
  directory. Passwordless administrator access is unavailable, so this is
  an access boundary, not evidence of a DriverKit protocol failure.
- No administrator prompt was opened and no privileged probe was run.
  The next live check requires an authenticated administrator invocation
  of this connect-only command before attempting initialization or seize.
- Follow-up: with user approval, ran the connect-only command through the
  macOS administrator authentication dialog. It exited successfully and
  logged `vhidd connection succeeded (no keyboard initialized or captured)`.
  This verifies socket access only, not DriverKit readiness, injection,
  seize, or recovery. The installed setup remains unchanged.

## 2026-10-20: virtual-HID failure recovery audit (fork only)

- Root cause: keyboard-page send failures triggered seize recovery, but
  consumer, Apple-vendor, F-row media, and Caps Lock neutralization sends
  merely logged or ignored failures. A broken virtual-HID connection could
  therefore leave a physical keyboard seized until a later heartbeat or
  keyboard-page event detected the failure.
- Routed those send failures through the same transport-error recovery path
  and stopped forwarding events while recovery is pending. Non-transport
  validation errors remain logged without forcing a reconnect.
- Verification: `zig build` passed after the source edit; all 10 focused
  virtual-HID tests passed. `zig build test` reached 723/727 passing (one
  skipped) with the same three pre-existing hot-reload/event-stream failures
  and six leaks. The installed service and keyboard input path were not
  changed.
- App-scoped rules remain rejected by the daemon; no live grabber test or
  install was attempted.

## 2026-10-20: app-scoped remap design

- Inspected the clean fork, parser, agent-to-grabber IPC, grabber dispatch,
  Karabiner configuration, and installed service state before changing code.
- Chose exact bundle-ID app guards, one device/source fallback, explicit
  passthrough, key-down selection latched to key-up, and fail-open behavior.
  Rationale and rollout gates are in `docs/APP_SCOPED_REMAPS.md`.
- Root cause of the currently unsafe migration path: the grabber uses the old
  datagram virtual-HID transport/protocol 5, while the installed DriverKit is
  v8.5.0 (stream transport/protocol 7); its current dispatch also cannot
  distinguish multiple app-specific rules for one physical key. A numeric
  version bump alone would not repair this.
- Verification: temporary Zig 0.16.0 toolchain from ziglang.org; `zig build`
  passed. Baseline `zig build test` compiled but had three existing failures:
  two hotload/event-stream tests and one hot-reload command-template test.
  No executable code, installed services, input settings, or Karabiner rules
  changed. The unsafe low-level grabber was not installed or started.

## 2026-10-20: DriverKit 8.5 transport port (fork only)

- Verified the installed DriverKit daemon is 8.5.0 and upstream v8.5.0 embeds
  client protocol 7 and publishes the package name now pinned in `build.zig`.
- Replaced the grabber's old datagram client with Unix stream framing,
  request IDs, partial-read buffering, protocol 7 requests, and corrected
  request enum values. The watchdog now reads framed messages and echoes
  heartbeats/acknowledges server requests. Kept all changes in the clone;
  no installed binary, service, or keyboard configuration was changed.
- Verification: `zig build` passed; `zig test src/grabber/Vhidd.zig -lc` passed
  (ten tests, including imported stream tests); `zig test src/grabber/VhiddStream.zig -lc`
  passed (five tests, including partial and consecutive socket-pair frames).
  Full `zig build test` retained the same
  three baseline failures. Live DriverKit compatibility remains unverified.
- App-specific `.remap` syntax and dispatch are not yet implemented. Do not
  install the fork as a Karabiner replacement at this stage.

## 2026-10-20: app-rule selection model (fork only)

- Added optional exact bundle-ID and passthrough fields to the tap-hold
  declaration model. Distinct app guards can coexist with one fallback;
  duplicate scopes and collisions with legacy colon remaps remain errors.
- Added a pure selector that gives an exact app match precedence over the
  fallback, honors explicit passthrough, fails open when app identity is
  unknown, and latches a selected rule per physical device and source key
  until release. This isolates precedence before modifying input dispatch.
- Verification: 41/41 `Mappings.zig` tests and 3/3 selector tests passed;
  `zig build` passed after the model change. No live keyboard or service
  changes. The parser does not accept app guards yet, and the runtime does
  not use the selector, so app-specific remaps are **not implemented**.
- Remaining safety gates: deliver the foreground bundle ID through
  versioned IPC; identify the physical keyboard per event; dispatch only
  the selected slot while latching through key-up; fail open on identity,
  IPC, or virtual-HID failures; run isolated hardware tests before install.
- Final verification: `zig build` passed; the focused mapping, selector, and
  stream tests passed. `zig build test` reached 699/703 passing (one skipped,
  three failures), with the same two event-stream failures and one command-
  template failure seen before these changes. The test-generated file was
  removed. No commit or push was made.

## 2026-10-20: protocol and device-identity groundwork (fork only)

- Added the sending HID device's pointer identity to input events, without
  changing how the grabber currently dispatches those events.
- Bumped agent/grabber IPC to version 3 and carried optional bundle-ID and
  passthrough fields through the agent's rule serialization. The server
  deep-copies and frees bundle IDs with subscription ownership.
- Added a hard server-side rejection for app-scoped rules because current
  dispatch still sends a source event to every matching slot. This prevents
  a partly implemented feature from remapping keys in the wrong app.
- Verification: `zig build`, protocol framing tests (3/3), and IPC rule-
  validation test (1/1) passed. No service, installed binary, Karabiner
  setting, or physical keyboard was changed. Foreground app identity,
  per-device rule matching, selected-slot dispatch, and live validation
  remain open gates; do not install this fork yet.
- Full `zig build test`: 700/704 passed, one skipped, with the same three
  previously observed hot-reload/event-stream failures. Removed the
  test-generated file afterward; no commit or push was made.

## 2026-10-20: foreground identity transport (fork only)

- Added a cached exact bundle ID to the existing Carbon front-app tracker,
  keyed from the event's process serial number rather than querying an
  earlier foreground app. The agent sends its initial ID with `apply_rules`
  and sends framed changes over the persistent subscription socket.
- The daemon buffers and validates updates, owns the current ID per
  subscription, and drops a malformed or disconnected subscription.
  Unknown/invalid IDs fail open to null. HID events now include cached
  physical device ID and vendor/product data, with an explicit unknown flag.
- Root cause of the remaining runtime gap: current tap-hold slots are per
  rule, not per physical keyboard. Merely choosing one app rule per source
  still cannot represent simultaneous holds on two identical keyboards or
  preserve caps-lock passthrough safely. The daemon therefore continues to
  reject app-scoped rules; no new parser syntax was enabled.
- Verification: `zig build` and focused foreground-decoder/Carbon cache
  tests passed. No installed binary, service, Karabiner rule, or live input
  setting was changed. The AppKit lookup and daemon focus stream have not
  been exercised against a live root grabber.
- Full `zig build test`: 705/709 passed, one skipped, with only the same
  three prior hot-reload/event-stream failures. The test-generated file was
  removed; no commit or push was made.

## 2026-10-20: app-guard parser and dormant selected-slot routing

- Added exact `[app "bundle.id"]` parsing after the required device guard,
  scoped `: passthrough`, and duplicate/malformed-guard tests. Shared a
  bounded bundle-ID validator with foreground IPC. Updated `SYNTAX.md` to
  make the parser/runtime distinction explicit.
- Added offline-tested routing decisions for app precedence, fallback,
  unknown identity, passthrough, per-device key-down latching, and
  release after a focus change. The grabber has a selected-slot branch
  but preserves the previous dispatch when no app-scoped rule exists.
- Root cause of the conservative rollout gate: each tap-hold engine still
  represents one source-key state, so two physical keyboards cannot safely
  share it. The dormant branch requires exactly one matched keyboard and
  one rule-device class. The IPC server still rejects every app-scoped rule
  before the keyboard can be seized; no live behavior was enabled.
- Verification: `zig build` and 125/125 direct parser tests passed; 7/7
  focused selector tests passed. Final `zig build test` passed 723/727,
  with one skipped and the same three
  pre-existing hot-reload/event-stream failures. No installed binary,
  service, Karabiner setting, or keyboard input path was changed.
## 2026-10-24: non-suppressing observe mode (fork only)

- Root cause: `skhd -o` created a filtering event tap, and its key-down and
  mouse callbacks returned null, which can suppress ordinary input. It was
  unsafe as a keyboard-permission probe.
- The observer now requests CoreGraphics' listen-only tap option and returns
  every event. The shared event-tap default remains filtering for normal skhd
  hotkey dispatch.
- Verification: `zig ast-check` passed for changed Zig files and the offline
  `zig build` passed. No observer was launched, no physical input was tested,
  and no installed service, Karabiner rule, or keyboard setting was changed.
  A live permission check remains pending and must be user-coordinated.

## 2026-10-24: development-agent listen-only permission probe

- Ran the separately built, ad-hoc-signed development agent with `-o` for a
  bounded probe. Its listen-only event tap could not be created after ten
  attempts and exited with `AccessibilityPermissionDenied`; it never opened
  an event tap or captured input. No typing was requested.
- This is not a failure of app-scoped routing. The ad-hoc development binary
  has no established macOS privacy grant, unlike the installed skhd app.
  A stable separately signed development agent and its own Accessibility
  approval are needed before any foreground-identity live test. Do not
  replace the installed service or reuse its bundle identifier to bypass
  that gate.
- Built a separate `com.jackielii.skhd.agent.dev` app from the current
  development binary in `/private/tmp`, signed it with the existing Apple
  Development identity, verified its strict/deep signature, and installed
  it at `/Applications/skhd-agent-dev.app` without replacing the ordinary
  `/Applications/skhd.app` or registering a service.
- The installed development app ran `-o` for seven seconds with a listen-only
  event tap; the external timeout ended the probe normally. No keyboard
  events were requested or tested, and no physical HID grabber was started.
  This establishes that its event tap can open in this session, not that
  app-scoped remaps or end-to-end foreground updates work.

## 2026-10-24: isolated app-rule preflight and PID-file safety

- Launched the development grabber unprivileged on a private test socket
  with `--experimental-app-scoped-rules` but no rules. The development
  agent's status command reached protocol v3, and the daemon exited cleanly.
  The missing LaunchDaemon reported by `--grabber-status` is intentional;
  no HID seize, virtual-keyboard posting, or installed service occurred.
- Packaged the current development grabber as a separately signed test app
  under `/private/tmp/skhd-app-scope-grabber.qxFgzd`; plist lint and
  strict/deep signature verification passed. It was not installed or run.
- Root cause found while preparing the second agent: `-V` skipped the
  existing-instance check but still wrote and removed the production PID
  file. A concurrent foreground test could therefore erase the active
  service's PID file. Foreground mode now leaves that file alone; service
  mode retains its normal write/deferred-remove behavior.
- Verification: `zig ast-check`, `zig fmt --check` for the changed source,
  offline `zig build`, and a foreground fixture smoke run passed. The
  smoke run reached a deliberately nonexistent socket and created no PID
  file. No active keyboard process or configuration was changed.
- Refreshed only `/Applications/skhd-agent-dev.app` with the new PID-safe
  build; strict/deep signature verification passed, and its listen-only tap
  remained open for a bounded six-second probe. Refreshed only
  `/Applications/skhd-grabber-dev.app` with the staged app-rule-gated
  build; signature verification passed, and its non-opening match probe
  found one built-in keyboard. Both test app replacements had rollback
  backups. The ordinary skhd and Karabiner launchd agents stayed running.
  No grabber was started or physical input remapped in this step.

## 2026-10-24: first guarded app-scope capture attempt

- Armed a fresh independent 120-second, one-shot root launchd rollback from
  a root-owned private directory, then launched the separately signed
  development grabber on an isolated socket with the experimental app-rule
  gate. Verified it had no rules before stopping Karabiner's two user agents
  in the actual user session; confirmed both labels absent.
- Launched the separate development agent with the temporary Left Shift
  fixture. The grabber acknowledged both rules and seized one built-in
  keyboard. The user received explicit START and STOP messages for tapping
  Left Shift and typing with it held, including a requested switch to
  Ghostty. The agent was stopped, the test grabber booted out, and Karabiner
  immediately restored. No Caps Lock rule or active skhd config changed.
- Logs show six Left Shift tap commits to F24 and at least one Left Shift
  hold-down/up with `a`, `b`, and `c` forwarded. The agent log names only
  ChatGPT as frontmost; there is no F23 commit or confirmed Ghostty identity
  update. **The app-specific branch is not validated.** The user's visible
  typing and whether Ghostty actually came forward still need confirmation.
- The independent rollback later fired once, found no remaining grabber,
  re-registered Karabiner, and logged `RESTORE_EXIT=0`. Read-only checks show
  ordinary skhd and both Karabiner user agents running, with no grabber.
  Do not treat this as evidence for installing or enabling scoped rules by
  default; the next test needs a clear, verified foreground-app transition.

## 2026-10-24: foreground identity without capture

- The user reported being on another desktop and not seeing the prior
  typing instruction; whether Ghostty came forward during the capture is
  uncertain. No repeat capture was started.
- Ran the separately signed development agent against a temporary mock
  protocol-v3 Unix socket, with the normal Karabiner and skhd services still
  active. The mock only acknowledged the agent's `hello` and `apply_rules`;
  it had no HID or virtual-keyboard access. Programmatically activated
  Ghostty, then restored ChatGPT after two seconds each.
- Captured `apply_rules` with initial `com.openai.codex`, followed by exact
  `foreground_app` updates for `com.mitchellh.ghostty` and
  `com.openai.codex`. `lsappinfo front` also changed and returned. This
  validates the agent's real foreground-ID IPC emission, but not the root
  grabber's selected-slot behavior or physical F23 output. The user was
  asked to confirm normal typing before any further capture.

## 2026-10-24: guarded Ghostty app-specific Left Shift test

- After the user confirmed normal typing, armed a fresh independent
  120-second root launchd rollback from a root-owned private directory.
  Launched the separately signed development grabber on a new isolated
  socket with the experimental gate but no rules. Stopped the two Karabiner
  user agents from the actual user session and confirmed them absent.
- Started the separate development agent with the temporary Left Shift
  fixture. It acknowledged both rules. Before capture, the user was told
  that Ghostty would come forward automatically and to tap Left Shift twice,
  then hold it while typing `abc`. A bounded script activated Ghostty,
  verified the foreground app changed, returned focus to ChatGPT after
  14 seconds, and terminated the agent. The user received a STOP signal.
- The grabber log records four F23 tap commits (`0x72`) while Ghostty was
  frontmost, plus Left Shift hold-down/up events. The agent log identifies
  Ghostty for the typed `a`, `b`, and `c`; the user confirmed held Shift
  produced uppercase `ABC` and ordinary typing was normal afterward.
  Combined with the earlier ChatGPT F24 fallback and the no-capture IPC
  app-ID transition test, this is one successful short physical test of
  exact-app selection and fallback for the temporary Left Shift rule.
- The test agent was terminated, the isolated root grabber booted out,
  Karabiner immediately restored, and read-only checks found no grabber.
  Caps Lock and the active skhd/YabaiSpaces setup were not changed.
  This short test does not establish long-running stability, disconnect
  recovery under failure, or migration readiness; the experimental gate
  stays default-off.
- The independent one-shot rollback later fired, found no grabber process,
  re-registered Karabiner, and logged `RESTORE_EXIT=0`. Its launchd job
  disappeared, the isolated socket was removed, both Karabiner user agents
  and ordinary skhd were still running, and `git diff --check` passed.
- Final offline verification passed: AppRuleSelector 7/7,
  ForegroundUpdate 3/3, BundleId 1/1, HidKeyMap 2/2, `zig build`,
  `zig ast-check` for the changed agent entry point, Zig formatting checks
  for that entry point and EventTap, and `git diff --check`. No production
  binary or configuration was installed.

## 2026-10-24: staged Karabiner replacement configuration

- Root cause of the migration gap: the active skhd config only handles
  high-level F18/F19/Command hotkeys. Karabiner still owns seven low-level
  tap/hold manipulators, including two tap outputs that require a modifier
  (Right Command–F19 and Right Option–F19). The development `.remap` grammar
  previously had no way to express those modified taps.
- Added optional `tap_modifier` to the parser, mapping model, IPC protocol
  (version 4), runtime validation, and tap/retro-tap emitter. The emitter
  presses the requested HID modifier only around the tap key; hold behavior
  is unchanged. Agent and grabber must be rebuilt together.
- Staged `docs/KARABINER_MIGRATION.skhdrc`: four existing high-level
  bindings and 24 low-level rules for the built-in Apple keyboard. It covers
  the active profile's Caps Lock Control/Command app branches, Emacs/Portacle
  passthrough, terminal Tab, and Right Command/Shift/Option taps. It does
  not alter `~/.config/skhd/skhdrc`, Karabiner, launchd, or Caps Lock live.
- Verification: `zig build` passed; focused `TapHold` modified-tap and
  `Parser` modifier-validation tests passed; the isolated-socket startup
  parsed and forwarded all 24 rules, then exited because the deliberately
  nonexistent grabber socket was absent. The draft's first four lines match
  the active skhd hotkeys. `git diff --check` passed. Direct `zig test
  src/Parser.zig` requires linking Carbon and CoreFoundation on this Mac;
  with those frameworks it passed. Full `zig build test` reached 740/747
  passed, four skipped, with the same three pre-existing hot-reload failures.
- Unverified: exact Karabiner timing/optional-modifier semantics, this
  profile's Fn/function-key mappings, modifier-tap delivery to ordinary
  skhd, app-ID fail-open behavior under real use, capture recovery, and
  long-running stability. The development grabber stays default-off.
  Do not replace Karabiner until an independent timed rollback and explicit
  START/STOP physical-key test are arranged; there is no external keyboard.

## 2026-10-24: guarded physical modifier-tap test

- Built and Apple-Development-signed separate protocol-v4 agent/grabber
  test apps, verified their signatures, and refreshed only their existing
  `/Applications/*-dev.app` copies. The production skhd app and config were
  not replaced. A no-rules isolated IPC probe connected at protocol v4.
- For each of two short attempts, armed a fresh root-owned, one-shot
  120-second rollback before stopping Karabiner's two user agents. The
  isolated grabber then captured only the built-in keyboard for two
  `.remap` rules: Right Command tap Right Command–F19/hold Right Command,
  and Right Option tap Right Option–F19/hold Right Option. Caps Lock was
  not remapped. Explicit START/STOP messages bounded physical input.
- The user missed the first window; its four Left Shift events do not
  validate either requested key. The second window received two physical
  Right Command taps and two Right Option taps. For each, the grabber log
  shows the expected modifier down, F19 down/up, modifier up sequence.
  This validates modified-tap emission on this keyboard, not every rule
  in the staged migration config.
- The separate test agent logged `rcmd + fn - f19` and `ralt + fn - f19`.
  Its fixture had no high-level F19 bindings, so its “No matching hotkey”
  message was expected and is **not** evidence of high-level failure.
  Parser tests show F19 hotkeys include the Fn flag by design. Whether the
  unchanged production skhd hotkeys fired is left to the user's observed
  behavior; no claim of end-to-end YabaiSpaces switching is made here.
- After each window the test agent and root grabber were stopped, then both
  Karabiner user agents were restored. Both independent one-shot timers
  subsequently fired with `RESTORE_EXIT=0` and disappeared. Read-only
  checks found ordinary `com.jackielii.skhd` and both Karabiner agents
  running, with no skhd grabber. The user confirmed typing was normal
  after the second window. No active keyboard configuration was changed.
- The user thinks both YabaiSpaces actions worked but was surprised by
  the desktop switch and is unsure about the Option action. Therefore
  the low-level modified-tap result is confirmed by the grabber log;
  the end-to-end high-level Option action remains observationally uncertain.

## 2026-10-24: guarded Shift, Tab, and Caps Lock checks

- With separate signed development agent/grabber apps and a fresh
  root-owned 120-second one-shot rollback, tested only Right Shift and
  Ghostty-scoped Tab. In Ghostty, the grabber recorded two Tab taps as
  Tab down/up, a one-second Tab hold as Left Control down/up, two Right
  Shift taps as F18 down/up, and a one-second Right Shift hold as Right
  Shift down/up. The user saw the YabaiSpaces panel open on Right Shift
  tap and confirmed typing remained normal after Karabiner restoration.
  The rollback later fired with `RESTORE_EXIT=0` and disappeared.
- A separate guarded Caps Lock test selected the Ghostty branch: two
  taps emitted F20, and holding emitted Right Control down/up. After
  an automated focus switch to ChatGPT, a later Caps hold still emitted
  Right Control; the timing of the focus update versus the key press
  was ambiguous, so the test was stopped before the announced fallback
  phase. This is not proof of a selector bug or a successful fallback.
  Karabiner was restored, typing was normal, and the independent timer
  later completed with `RESTORE_EXIT=0`.
- A fresh ChatGPT-only guarded run, with ChatGPT verified frontmost
  before activating the two-rule fixture, recorded Caps taps as F20
  down/up and held Caps as Left Command down/up. This validates the
  fallback branch without an app transition. The test agent had no
  high-level F20 binding, so its “No matching hotkey” lines are expected.
  The grabber and agent were stopped and Karabiner restored immediately.
  The user confirmed typing and modifiers were normal afterward. The
  final one-shot rollback then completed with `RESTORE_EXIT=0` and
  disappeared; ordinary skhd and both Karabiner user agents remained
  running, with no skhd grabber process.
- These bounded tests validate selected physical tap/hold outputs, not
  every application identifier, passthrough rule, modifier combination,
  long-running stability, sleep/wake, or unattended recovery. Active
  skhd/Karabiner configs and services were not replaced. Keep the
  staged migration disabled pending the remaining rollout gates.

## 2026-10-24: exclusion logic and forced agent-disconnect recovery

- Offline checks passed: `AppRuleSelector` 7/7, including explicit
  passthrough overriding fallback, latching across focus changes, and
  unknown-app fail-open; `ForegroundUpdate` and bundle-ID checks 3/3;
  the parser's app-scoped passthrough test 1/1. Emacs could not be
  launched because `/Applications/Emacs.app` is an unresolved alias,
  and no Portacle app was found, so neither exclusion was physically
  validated in its real target app.
- With a fresh root-owned 120-second one-shot rollback, ran the
  separately signed development grabber and an app-scoped Left Shift
  fixture on an isolated socket. The user typed `abc` normally while
  the built-in keyboard was seized. The test agent alone was then
  stopped with SIGKILL while no key was held. The grabber logged the
  subscription closing and `released seize` immediately, without
  requiring the watchdog to kill it.
- Stopped the now-unsubscribed grabber, restored both Karabiner user
  agents, and verified ordinary `com.jackielii.skhd` was still running
  with no grabber process. The user confirmed typing was normal during
  the capture and afterward. The independent one-shot rollback later
  fired, logged `RESTORE_EXIT=0`, and disappeared.
- This validates one no-key-held agent-disconnect path, not a hung or
  SIGKILLed root grabber, a held-modifier disconnect, live Emacs/Portacle
  passthrough, sleep/wake, or one-hour unattended operation. The working
  Karabiner/skhd configuration remains active; no migration was installed.

## 2026-10-24: root-grabber termination and watchdog recovery

- Prepared a minimal Left Shift tap-F24 fixture, a separately signed
  development agent/grabber, and a fresh root-owned, one-shot 60-second
  rollback. The physical grabber acknowledged one rule and seized one
  built-in keyboard. The user was given START/STOP instructions and
  pressed keys during the capture window.
- Sent SIGTERM to the identified root grabber while the agent still held
  an active subscription. The grabber **did not exit promptly**: it was
  still running more than a second later and again several seconds later.
  Do not count this as a clean-stop success. The independently armed
  watchdog fired at its deadline, force-killed the remaining grabber,
  registered both Karabiner user agents, logged `RESTORE_EXIT=0`, and
  disappeared. Read-only checks found no grabber, with Karabiner and
  ordinary `com.jackielii.skhd` running. The user confirmed ordinary
  typing was normal after restoration.
- A separate **no-rules, no-seize** grabber exited promptly on SIGTERM.
  The cause of the active-capture TERM delay is not established; this
  comparison narrows it to the capture/subscription path or its context.
- The watchdog's forced-kill recovery worked once in this short test.
  Because graceful termination unexpectedly failed, the planned
  SIGSTOP/hang simulation was **not run**. One successful forced rollback
  does not prove recovery from every hang or make an unattended one-hour
  replacement safe. No production app, config, or service was replaced.

## 2026-10-24: SIGTERM comparison and development-grabber fix

- An equivalent SIGTERM check on Karabiner's active root Core Service
  exited within two seconds and launchd restarted it. Both user agents
  remained running; the user confirmed `abc` and subsequent typing were
  normal. This contrasted with the prior development-grabber result.
- Removed the development grabber's custom TERM/INT/HUP handler. It
  modified shared state, unlinked the socket, and called `_exit` from
  signal context; the daemon already unlinks a stale socket on startup.
  macOS's default termination now closes the physical HID seize and
  virtual-HID connection. The exact operation that caused the earlier
  delay was not isolated, so this is a targeted fix validated by the
  active-capture retest, not proof of a particular handler-line deadlock.
- Zig 0.16.0 `zig build` passed after the source edit. Two isolated
  no-seize SIGTERM/rebind runs exited with status 143 and rebound the same
  socket. `zig build test` reported 740/747 passed, four skipped, and
  the same three pre-existing hot-reload failures.
- Re-signed only `/Applications/skhd-grabber-dev.app` with the existing
  Apple Development identity; production skhd and Karabiner binaries,
  configurations, and services were not replaced. Under an independent
  root rollback, the test agent applied one Left Shift tap-F24 rule and
  the grabber seized one built-in keyboard. SIGTERM to the identified
  active-capture PID returned success; the old PID was absent two seconds
  later and launchd recorded `Terminated: 15`. `launchctl submit` restarted
  the temporary test job, so that job was explicitly booted out and any
  test grabber killed before Karabiner's user agents were registered.
  The independent rollback fired, found no grabber, and logged
  `RESTORE_EXIT=0`; its submitted job was then removed to prevent repeat.
  The user did not type during the capture window, so this run did not
  recheck typing pass-through. They confirmed ordinary typing was normal
  after Karabiner restoration, with no doubled, missing, or stuck keys.
- This validates one active-capture SIGTERM exit, not every shutdown or
  hang path. Do not enable an unattended one-hour Karabiner replacement
  on this result alone.
- The user deferred physical Emacs/Portacle exclusion and sleep/wake
  testing. Those are no longer gates for the next guarded, reversible
  trial; their behavior remains unverified. Keep Karabiner as the fallback.

## 2026-10-24: guarded paused-grabber rollback

- Before testing, corrected `scripts/keyboard-capture-rollback.sh` to send
  SIGKILL before launchd bootout, so a stopped grabber cannot make
  keyboard release wait for bootout. A second SIGKILL closes a possible
  respawn race. `/bin/sh -n` and `git diff --check` passed after the edit.
- Installed root-owned temporary copies of the rollback script and
  three `LaunchOnlyOnce` launchd plists. `plutil -lint` passed for every
  plist. A separate three-second preflight ran once with Karabiner
  active, found no grabber, registered both agents, and logged
  `RESTORE_EXIT=0`; its launchd job then disappeared.
- Armed a fresh root-owned 60-second rollback, unregistered only the two
  Karabiner user agents, and started the separately signed development
  grabber with the minimal Left Shift tap-F24 rule. Logs confirmed one
  active subscription and one built-in keyboard seized. After the START
  signal, SIGSTOP put the identified root grabber in process state `T`
  while it still owned capture; the user was told not to press keys.
- At the timer deadline, the independent rollback killed that paused
  grabber, removed its launchd job, restored both Karabiner agents, and
  logged `RESTORE_EXIT=0`. The rollback itself ran once and disappeared.
  Read-only checks found no grabber; both Karabiner agents and ordinary
  `com.jackielii.skhd` were running. After STOP, the user confirmed
  ordinary typing was normal, with no doubled, missing, or stuck keys.
- This proves one recovery from a SIGSTOP-paused grabber under an active
  seize. It does not prove recovery from a kernel-uninterruptible hang,
  held keys at failure, or long-run stability. Emacs/Portacle and
  sleep/wake behavior remain deferred by user choice. Production input
  services and configurations were not replaced; no one-hour trial was
  started.

## 2026-10-24: one-hour trial aborted before START

- With the user's explicit readiness, staged the 24-rule migration config
  without duplicate high-level hotkeys. A non-capture parser run accepted
  it. Root-owned `LaunchOnlyOnce` rollback and grabber jobs and a temporary
  user-agent job passed `plutil -lint`; a harmless three-second rollback
  preflight restored Karabiner and removed its test agent successfully.
- Armed the independent ~61-minute restore timer and verified it running
  before unregistering Karabiner's two user agents. The development grabber
  started, and the test agent forwarded 24 tap-hold rules; logs showed one
  built-in keyboard seized. The agent then failed all ten Accessibility
  event-tap attempts and exited. Its subscription closed, and the grabber
  released the keyboard. The agent's signed bundle ID is
  `com.jackielii.skhd.agent.dev`, distinct from production skhd's ID, so
  production's permission does not establish the development app's grant.
- Aborted before telling the user START. Immediately killed and booted out
  the development grabber, re-registered both Karabiner agents, verified
  both running, then canceled the unused restore timer. The temporary agent
  and grabber were absent; production `com.jackielii.skhd` remained running.
  The user confirmed ordinary typing was normal afterward.
- No one-hour stability result was obtained. Grant Accessibility to
  `/Applications/skhd-agent-dev.app` (without resetting production skhd's
  permissions), then rerun a short guarded permission/capture check before
  another long trial. Emacs/Portacle and sleep/wake remain deferred.

## 2026-10-24: short guarded migration-rule test passed

- After the user enabled the development app's Accessibility permission,
  started it briefly with a comment-only config while Karabiner remained
  active. It created its event tap successfully, then was stopped. No
  keyboard capture occurred during this permission check.
- Staged and linted a root-owned, one-shot, three-minute rollback. With
  the user ready and typing normally, verified the timer running before
  unregistering Karabiner's two user agents. Started the development
  grabber and agent. Logs showed 24 tap-hold rules acknowledged, the app's
  event tap created, and one built-in keyboard seized.
- Sent explicit START and STOP signals around a 30-second user test.
  Immediately killed and booted out the test grabber, re-registered both
  Karabiner agents, removed the test agent, verified ordinary skhd still
  running and no grabber process, then canceled the unused rollback timer.
  The user reported normal typing and correct behavior for Caps, Tab,
  Right Shift, Right Command, and Right Option during the test, with normal
  typing afterward.
- This is a short functional check, not an hour of stability testing.
  Production binaries and configs remained unchanged. Emacs/Portacle and
  sleep/wake remain deferred by user choice.

## 2026-10-24: one-hour migration-rule trial started

- On explicit user request, verified production skhd and both Karabiner
  user agents running, no old test grabber/timer, matching staged 24-rule
  config, valid trial plists/script syntax, and valid development app
  signatures. The separate development app's Accessibility event tap had
  passed the preceding short test.
- Armed and verified the root-owned, one-shot 3660-second rollback at
  approximately 02:26:52 EDT (expected restoration about 03:27:52 EDT).
  Only then unregistered Karabiner's two user agents and verified them
  absent. Started the development grabber and test agent; logs confirmed
  24 tap-hold rules acknowledged, the event tap created, one built-in
  keyboard seized, and virtual-HID heartbeats flowing. Ordinary production
  skhd and the rollback timer remained running.
- Sent explicit START at approximately 02:27 EDT. The trial is in progress;
  do not call it successful until the independent rollback restores
  Karabiner and the user confirms normal typing after the hour. On any
  flaky input, stop the trial and restore immediately rather than waiting
  for the timer. Emacs/Portacle and sleep/wake remain deferred.

## 2026-10-24: permanent migration staged, not activated

- The one-hour rollback fired at 03:27:51 EDT, logged `RESTORE_EXIT=0` and
  `TEST_AGENT_BOOTOUT_EXIT=0`, and left both Karabiner user agents running,
  with no test grabber or agent. The user reported the hour went well and
  requested skhd as the normal keyboard owner, while retaining an easy
  way to return temporarily to Karabiner.
- Installed a copy of the exact tested 24-rule config at
  `~/.config/skhd/remap.skhdrc`; byte comparison passed, and the agent
  parsed and attempted to forward all 24 rules to a deliberately absent
  socket without seizing any keyboard. The existing production high-level
  skhd service and config were not changed.
- Installed a dedicated user LaunchAgent plist at
  `~/Library/LaunchAgents/com.jackielii.skhd.remap-agent.plist` and a root
  LaunchDaemon plist at
  `/Library/LaunchDaemons/com.jackielii.skhd.grabber.plist`, both using the
  signed development binaries, a dedicated `/private/tmp/skhd-remap.sock`,
  `RunAtLoad`, and `KeepAlive`. Both plists passed `plutil -lint`.
- Staged a root-owned 15-minute one-shot rollback that disables the new
  launchd jobs, kills and boots out the grabber, then re-enables and
  registers Karabiner's user agents. `/bin/sh -n` and invalid-argument
  checks passed. A harmless immediate preflight while Karabiner owned the
  keyboard logged `RESTORE_EXIT=0`; the new jobs were re-enabled afterward.
- The user has not yet confirmed being at the keyboard for the final
  cutover. Neither new service was bootstrapped. To prevent an unexpected
  reboot from starting the new root daemon alongside Karabiner, both new
  launchd labels were **disabled** as boot overrides. Karabiner's two user
  agents and ordinary high-level skhd remain enabled and running. No
  keyboard ownership change has occurred. At cutover, arm and verify the
  rollback timer first, then disable/unregister Karabiner user agents,
  enable/bootstrap the new jobs, send START, and seek user input checks
  before canceling the timer. Preserve the Karabiner DriverKit daemon.

## 2026-10-24: permanent local skhd cutover completed

- After the user confirmed readiness and normal typing, rechecked both
  Karabiner user agents running, the new jobs absent/disabled, matching
  24-rule config, and all plists/script syntax. Armed and verified the
  independent root-owned 15-minute rollback at approximately 07:46 EDT.
- Persistently disabled both Karabiner user-agent launchd labels, then
  unregistered them and verified them absent. The Karabiner system
  VirtualHIDDevice daemon was left untouched. Enabled/bootstrapped the
  root `com.jackielii.skhd.grabber` and user
  `com.jackielii.skhd.remap-agent` jobs. Logs confirmed the dedicated
  socket listening, 24 rules acknowledged, event tap created, one built-in
  keyboard seized, and virtual-HID heartbeats. Ordinary production
  `com.jackielii.skhd` continued running with unchanged high-level config.
- Sent explicit START. The user reported normal typing and correct Caps,
  Tab, Right Shift, Right Command, and Right Option behavior, without
  doubled, missing, or stuck keys. Rechecked both new jobs and ordinary
  skhd running, new launchd labels enabled, Karabiner user labels disabled,
  and no agent warnings/errors. Canceled and verified removal of the
  temporary rollback at approximately 07:51 EDT. The new services remain
  active with `RunAtLoad` and `KeepAlive` for future logins/reboots.
- Installed the preflight-tested rollback script as root-owned
  `/usr/local/sbin/skhd-restore-karabiner` and kept an identical source
  at `scripts/restore-karabiner.sh`. `/bin/sh -n`, byte comparison, and
  invalid-argument checks passed. The script was not invoked after the
  permanent cutover because that would undo the requested setup.
- The development grabber Debug build logs HID usage codes for each key.
  Its active log was initially mode `0644`; this was corrected to `0600`
  root-only without restarting capture. A release-mode signed deployment
  or bounded logging remains future work. Reboot/login startup,
  Emacs/Portacle exclusions, and sleep/wake are not yet validated.

## 2026-10-24: fork pre-release preparation

- The user requested an updated README, a non-Debug app bundle, and
  publication on `carcot/skhd.zig` rather than upstream. The checkout is
  local `main`, with `origin` set to the user's GitHub fork and `upstream`
  set to `jackielii/skhd.zig`. The active keyboard services are deliberately
  not replaced during release preparation.
- Added a concise README feature summary, an Unreleased changelog entry,
  and `docs/FORK_RELEASE.md` covering app-guard syntax, DriverKit 8.5
  transport, separate-socket activation, packaging, and limitations.
- Zig 0.16.0's full `zig build test` compiled but reported 742/747 tests
  passed, four skipped, and one failure in
  `Hotload.test.hotload file watching`; earlier runs had failures in the
  same hot-reload area. Do not claim a clean full suite. Focused tests and
  the ReleaseSafe bundle build needed separate verification.
- `zig test` passed for the four new focused modules: app-rule selection
  (7/7), bundle-ID validation (1/1), foreground updates (3/3), and
  DriverKit stream framing (6/6). `zig build app -Doptimize=ReleaseSafe`
  produced both binaries in `zig-out/skhd.app`. The ReleaseSafe agent's
  read-only custom-socket status check returned five OK results, and its
  parser reached the deliberately absent socket after accepting all 24
  staged rules. No release binary was installed or granted input capture.
- `zig fmt --check` reports three source files that were already
  unformatted in the checked-in baseline (`HidKeyMap.zig`, `echo.zig`, and
  `TapHold.zig`); no broad formatting rewrite was made for this release.
- The existing `v*` release workflow is upstream-oriented and attempts to
  update `jackielii/homebrew-tap`; it must not be triggered or used
  unchanged for this fork's pre-release. A manually published fork-only
  tag outside that pattern can attach a locally signed app archive without
  touching upstream or the current working keyboard apps.
