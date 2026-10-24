# Built-in keyboard capture: test and rollback checklist

Status: **basic typing pass-through and one paused-grabber rollback passed**.
The rollback killed a SIGSTOP-paused root grabber during active capture and
restored Karabiner. This Mac has no second keyboard; each later
input-affecting test needs a fresh independent rollback and an explicit
typing window. Do not uninstall Karabiner: the development fork shares its
virtual-HID driver, and reinstalling would remove a useful fallback.

## Paused-grabber recovery (2026-10-24)

- The rollback script now kills the grabber before booting out its launchd
  job. A root-owned, one-shot three-second preflight fired once while
  Karabiner owned input and logged `RESTORE_EXIT=0`.
- A fresh 60-second root-owned rollback was armed before switching keyboard
  ownership. The development grabber applied a minimal Left Shift tap-F24
  rule and seized one built-in keyboard. SIGSTOP put its PID in stopped
  state while the subscription and seize were active. The user did not
  press keys during this intentionally frozen interval.
- At the deadline the rollback killed the stopped grabber, removed its
  launchd job, restored both Karabiner agents, and logged `RESTORE_EXIT=0`.
  The rollback ran once and disappeared. The user confirmed typing was
  normal afterward; ordinary skhd remained active and no grabber remained.
- This is one bounded paused-process recovery, not proof against every
  kernel hang or a long unattended run. Emacs/Portacle exclusions and
  sleep/wake behavior are explicitly deferred.

## Isolated tap/hold test (2026-10-24)

- A fresh independent 60-second root rollback was armed before stopping
  Karabiner's user agents. The 20-second signed-grabber test applied one
  temporary rule: Left Shift tap emits F24; hold after 200 ms emits Left
  Shift. The user was told when to start and stop typing in the Codex
  message box. Caps Lock and active configurations were unchanged.
- The grabber exited normally and released the keyboard. Its log showed
  two F24 tap commits and multiple Left Shift hold-down/up commits, with
  `events forwarded=65` and no logged error. The user confirmed held Shift
  produced uppercase `ABC` and released Shift produced lowercase `abc`.
  Basic tap/hold behavior passed in this short observed test.
- Karabiner's agents were restored immediately. The one-shot rollback
  later fired, found no grabber, and completed with `RESTORE_EXIT=0`.
  Karabiner Core and ordinary skhd are running; no grabber remains. The
  user confirmed normal typing after restoration.

## Observed capture window (2026-10-24)

- With a fresh independent 60-second root rollback armed, the actual
  user-session command stopped both Karabiner agents and their absence was
  confirmed in launchd. The user was explicitly told when to start and stop
  typing in the Codex message box.
- The signed development grabber seized the built-in keyboard for 20 seconds,
  logged 473 forwarded HID events, released the seize on schedule, and
  exited with status 0. No capture error or warning was logged. The user
  confirmed that letters appeared normally in the target message box;
  basic typing pass-through passed for this short observed window.
- Karabiner was restored immediately. The one-shot rollback then fired,
  found no grabber, and completed with `RESTORE_EXIT=0`. Karabiner Core
  and ordinary skhd are running. The user confirmed normal typing after
  restoration. Tap/hold, app-scoped behavior, and longer-running capture
  remain untested and must be checked separately.

## Bounded seize result (2026-10-24)

- A separate rollback-guarded check confirmed that the **actual user
  session's** `unregister-core-agents` removes both Karabiner agents and
  `register-core-agents` restores them. A root script using `sudo -u` is not
  equivalent; it printed permission errors despite returning success.
- With a fresh independent 60-second rollback armed, both Karabiner agents
  were confirmed absent. The signed development grabber seized one built-in
  keyboard for 12 seconds and released it on schedule (`CAPTURE_EXIT=0`).
  Karabiner was immediately restored, and the rollback later completed
  with `RESTORE_EXIT=0`. No grabber remained.
- The grabber reported `events forwarded=0`. Whether the user pressed keys
  during the exact capture window is not yet established, so **typing
  pass-through is not validated**. Ask for the user's observation and
  confirmation of normal typing after restoration before another test.
  Do not enable app-scoped remaps on this result.

## Aborted guarded attempt (2026-10-24)

- A newly signed development build and independent 35-second root rollback
  were installed and verified. The attempted 12-second pass-through test
  reached virtual-HID readiness but could not seize the built-in keyboard:
  `IOHIDManagerOpen` returned `DeviceAlreadySeized`. This was **not** a
  successful typing test; Karabiner retained ownership.
- The attempted root-context `unregister-core-agents` printed `Operation not
  permitted` but returned exit code 0. Therefore, checking that command's
  status alone is unsafe. The retry must use the actual user GUI context and
  verify that the Karabiner agent disappeared from launchd **before** running
  the grabber. Do not reuse the temporary capture script unchanged.
- The one-shot rollback fired, found no grabber, and registered Karabiner's
  agents (`RESTORE_EXIT=0`). Subsequent read-only checks found no grabber
  and found the Karabiner agent and Core daemon running. Wait for user
  confirmation of normal typing before any new input-affecting test.

## Post-capture repeated-key recovery (2026-10-24)

- After the root grabber had been killed, the user saw the macOS accent menu
  on quick taps. Disabling the accent menu with the global
  `ApplePressAndHoldEnabled=false` preference only exposed doubled letters;
  it did not repair keyboard delivery. The preference remains disabled.
- No grabber process or service remained, Slow Keys was off, and active
  keyboard configs were unchanged. With the user's approval, restarting
  **only** the launchd-managed Karabiner Core daemon via
  `launchctl kickstart -k system/org.pqrs.service.daemon.Karabiner-Core-Service`
  replaced its root PID. The user confirmed normal typing afterward.
- This suggests stale state in the Core input path but does not establish
  the exact internal cause. The virtual-HID daemon and ordinary skhd were
  left alone; Caps Lock and other custom remaps were not revalidated. Do
  not treat this recovery as a successful grabber pass-through test.

## One-shot rollback redesign and dummy dry-run (later on 2026-10-23)

- `scripts/keyboard-capture-rollback.sh` waits 1–120 seconds, boots out a
  registered grabber service if present, sends SIGKILL to processes named
  `skhd-grabber`, verifies none remain, and only then re-registers the
  Karabiner Core agents as the console user. It requires root and logs the
  result. It must be staged in a **root-owned, non-user-writable directory**;
  never run a root launchd job from the user-writable checkout.
- The tested launchd plist used `RunAtLoad=true`, `KeepAlive=false`, and
  `LaunchOnlyOnce=true`, and was loaded with `launchctl bootstrap system`.
  Do not use `launchctl submit` for this watchdog: the earlier submitted
  job respawned. A fresh unique label and root-owned plist are needed for
  each future attempt.
- For the safe dry-run, a signed no-input `sleep` program named
  `skhd-grabber` ran as root. The one-shot watchdog fired after three
  seconds, killed that dummy, found no matching process, and successfully
  re-registered Karabiner. Twelve seconds later its log still had only one
  execution, and launchd had removed both one-shot test jobs. The temporary
  root-owned directory was deleted. Ordinary skhd and Karabiner remained
  running; no physical keyboard was seized.
- The development grabber now rejects `--seize-test-duration` values outside
  1–60 **seconds** before opening a keyboard. The 18,000-second error exits
  with status 2. This limits duration mistakes but is not a substitute for
  the independent watchdog or proof that a real seized keyboard releases.
- **Live capture remains paused.** The dummy run does not prove that the
  watchdog can recover a hung real HID seize, that character pass-through
  works, or that Karabiner remaps resume without reboot. Require fresh user
  consent and a clearly signaled typing window before considering that test.

## Failed live capture and recovery (later on 2026-10-23)

- The signed development grabber seized one built-in keyboard and logged
  physical events and attempted virtual-HID reports. The user did not
  confirm that characters appeared in Ghostty during the capture.
- The command passed `--seize-test-duration 18000`; that flag accepts
  **seconds**, so the requested duration was 18,000 seconds. An outer
  30-second timeout ended the calling process but did not kill the root
  grabber. The user reported that typing did not work afterward.
- The rollback's ordinary `killall skhd-grabber` did not terminate the
  root grabber, although agent re-registration succeeded. An authenticated
  SIGKILL of the specific grabber PID ended the seize. The user confirmed
  that typing worked again. Karabiner and ordinary high-level skhd were
  running; no skhd grabber service was installed.
- A launchd-owned dry-run executed the rollback script successfully, but
  `launchctl submit` then scheduled the completed job to restart. It is
  **not a proven one-shot watchdog**. All temporary timer jobs were removed.
- Do not repeat physical capture until the watchdog is redesigned to be
  genuinely one-shot, to force-kill a stuck root grabber, and to verify
  release before restoring Karabiner. The duration argument must use
  seconds; its parser should reject dangerous values. Prove the entire
  rollback against a harmless disposable process first, then get fresh
  user consent and a clearly signaled typing window. Treat the live
  pass-through result as inconclusive, not passed.

## Privileged rollback dry run (2026-10-23)

- macOS administrator authorization succeeded through a native prompt; no
  password was stored. A root-owned `launchctl submit` job appeared in the
  **system** domain, waited eight seconds, and wrote a root-owned timestamp.
  That job was removed after verification.
- A second root-owned timer ran `launchctl bootout` against a disposable
  root-owned sleep service. The command returned 0 and the dummy service
  disappeared from the system domain. Both disposable jobs were removed.
- A root-launched, user-session `id -u` check returned 501, proving the
  required user-session dispatch mechanism without changing Karabiner.
- Karabiner's Core daemon remained running and no skhd grabber was installed
  or started. The privileged mechanism is proven against a **dummy**, not
  against a live keyboard seize. Before capture, arm a fresh one-shot root
  rollback that stops the exact skhd grabber service/process **first** and
  re-registers Karabiner agents as user 501 **second**. Verify it is present
  in the system domain and inspect its logs afterward. Do not leave a
  dormant rollback job registered after the test.
- The development `zig-out/bin/skhd-grabber` has only an ad-hoc signature.
  Outside the restricted shell, one Apple Development signing identity is
  available. A stable signed development bundle and its Input Monitoring
  approval were still open preconditions at this checkpoint. Do not replace
  `/Applications/skhd.app` or the working high-level skhd service merely
  to obtain permissions.

## Separate signed development grabber (later on 2026-10-23)

- Built `zig-out/skhd-grabber-dev.app` with bundle ID
  `com.jackielii.skhd.grabber.dev`, then signed it with the existing Apple
  Development identity (team `7CJ3BM3AGT`). Unsandboxed
  `codesign --verify --deep --strict` and plist lint passed. This bundle
  is only in the checkout; the installed skhd app and launchd service were
  not replaced or restarted.
- The signed bundle reported its development version and
  `--match-probe 0:0` found exactly one built-in keyboard **without opening
  it**. Karabiner remained running and no skhd grabber service appeared.
- Input Monitoring for this separate bundle is not yet granted or verified.
  Signing and a device-count probe do not prove capture, typing, or virtual
  HID delivery. The next live phase needs a freshly armed root rollback
  with the actual stop-grabber/restore-Karabiner actions, plus explicit
  privacy approval, before any physical seize. Do not use `zig build
  run-grabber` as a shortcut: it starts a root grabber without that guard.
- Copied the signed bundle to `/Applications/skhd-grabber-dev.app` without
  overwriting `/Applications/skhd.app`. Unsandboxed strict/deep signature
  verification passed at the installed test path. The test app has not
  been launched; Input Monitoring is still unapproved/unverified.

## Input Monitoring and passive observer (later on 2026-10-23)

- The user added `/Applications/skhd-grabber-dev.app` to Input Monitoring;
  System Settings showed its switch enabled. The separate signed app
  continued to pass strict/deep signature verification.
- Armed a 60-second user-session Karabiner-agent restore timer, then briefly
  unregistered Karabiner's agents. Ran the signed grabber's
  `--seize-test 0:0 --seize-test-observe --seize-test-duration 4` as the
  user. `IOHIDManagerOpen` succeeded in **observe** mode (options `0x0`),
  found one built-in keyboard, and exited successfully. Observe mode uses a
  no-op callback: it did not take exclusive ownership, create virtual HID,
  repost keys, or inject input.
- Re-registered both Karabiner agents and verified them, the Core daemon,
  shared virtual-HID daemon, and ordinary skhd agent running. Removed the
  fallback timer. Config hashes were unchanged; no skhd grabber service
  appeared. This validates the privacy grant and passive device access,
  **not** exclusive capture or pass-through typing.
- The next test will briefly seize the built-in keyboard. It needs a newly
  armed root-owned rollback that can kill a foreground test grabber and
  restore Karabiner. Arrange a time when the user can type into a harmless
  text field and report any missing, duplicated, or stuck keys. Do not
  perform that input-affecting test as an unattended probe.

## Preparation completed (2026-10-22)

- Rechecked both Karabiner Core Service labels and the separate virtual-HID
  daemon: all were running. The skhd GUI agent was running and reported
  functional ordinary hotkeys; no skhd grabber service was registered.
  The shell `skhd` still points to `/Applications/skhd.app/Contents/MacOS/skhd`.
- Copied the two active configs into a mode-0700 directory under
  `/private/tmp/skhd-keyboard-baseline.NDGl93`. The copy hashes matched
  their sources: Karabiner `78e791dcc23f8ce2b4e4ddec0e68df6598d42fc221c33330ef2d53357f6f9247`,
  skhd `a651a2e0e9ddfa7232ace3e57576309bacd009c529a9433bdaa87cc825aabca8`.
  This is temporary storage, not a durable backup across reboot or cleanup.
- A user-session launchd job waited eight seconds and wrote a harmless
  timestamp, independently of the invoking shell. Its log was checked and
  the job was removed. This proves only that a **user-level marker timer**
  fired; it does not prove a privileged rollback can stop a root grabber.
- `sudo -n` requires a password on this Mac. A system-owned watchdog has
  **not** been installed or tested. Karabiner's stop/restart commands have
  **not** been run at this checkpoint. Do not proceed to skhd capture until
  the independent privileged rollback is installed and proven with explicit
  administrator authentication.

## Karabiner agent restoration check (later on 2026-10-22)

- With no skhd grabber registered, armed a separate 60-second user-session
  launchd job to run `register-core-agents`. Confirmed it was registered
  before the test. This timer could restore user agents, but **could not
  stop a future root-owned skhd grabber**.
- Ran `unregister-core-agents`: exit 0, and both the Core agent and Console
  User Server agent disappeared from launchd. Ran `register-core-agents`:
  exit 0, and both returned to `state = running`. The privileged Core
  daemon and shared virtual-HID daemon remained running throughout.
- Removed the fallback timer after verifying restoration. Karabiner and
  skhd configs retained their original hashes, and installed skhd reported
  functional high-level hotkeys with no grabber running.
- This verifies service registration, **not** physical typing or the
  user's tap/hold behavior; those require user confirmation. The privileged
  rollback timer, skhd capture, and per-app remaps remain untested.

## Verified read-only baseline (2026-10-20)

- Karabiner-Elements 16.3.0 uses the `Karabiner-Core-Service` daemon at
  `system/org.pqrs.service.daemon.Karabiner-Core-Service` and an agent at
  `gui/501/org.pqrs.service.agent.Karabiner-Core-Service-rev2`. Both were
  running when inspected. The separate `Karabiner-VirtualHIDDevice-Daemon`
  was also running; **leave it and the DriverKit extension alone**.
- Both installed Core Service plists say `KeepAlive=true` and are managed by
  `SMAppService`, so killing a process is not a reliable way to stop capture.
  The old `karabiner_grabber` launchd label does not exist here.
- The installed non-privileged agent binary contains both
  `unregister-core-agents` and `register-core-agents`. Karabiner's official
  quit instructions use the former. The latter's restoration behavior on
  this Mac is **not yet verified**. Neither command has been run here.
- The selected Karabiner profile, including Caps Lock, Tab, Right Command,
  Right Shift, and Right Option rules, is in
  `~/.config/karabiner/karabiner.json`. The active skhd config has no
  `.device` or `.remap`; ordinary hotkeys use `com.jackielii.skhd`.
- The fork still rejects app-scoped rules before seizing a keyboard. The
  non-seizing virtual-keyboard output check is not a capture test.

The installed Core-agent control commands to validate before a test are:

```sh
karabiner_agents='/Library/Application Support/org.pqrs/Karabiner-Elements/Karabiner-Elements Non-Privileged Agents v2.app/Contents/MacOS/Karabiner-Elements Non-Privileged Agents v2'
"$karabiner_agents" unregister-core-agents
"$karabiner_agents" register-core-agents
```

These are **not** instructions to run them now. The first command is in
Karabiner's published quit procedure; the paired registration subcommand
exists in the installed binary but its recovery effect is not yet proven.
The verification targets are `launchctl print
gui/$(id -u)/org.pqrs.service.agent.Karabiner-Core-Service-rev2` and
`launchctl print system/org.pqrs.service.daemon.Karabiner-Core-Service`.

## Preconditions: all must pass before touching keyboard ownership

1. Save a local copy and SHA-256 hash of both active config files. Record
   the selected Karabiner profile, service labels, installed skhd binary,
   current typing behavior, and Input Monitoring approval. Do not overwrite
   the active files with the development examples.
2. Prepare a **separate, privileged, launchd-owned timed rollback** before
   stopping Karabiner. It must not depend on this chat, Ghostty, an interactive
   shell, the keyboard, or skhd's agent. Its first action must release any
   skhd grabber seize (stop `system/com.jackielii.skhd.grabber` if present),
   then restore Karabiner Core agents if needed. Leave the virtual-HID
   daemon running. Use a short timeout and retain a mouse-accessible manual
   trigger. Record all actions and exit codes in a log.
3. Prove the timer independently while Karabiner remains active: a harmless
   marker action must fire on time. Verify the rollback commands' exact
   service-control behavior and required privileges on this installation.
   Karabiner's `register-core-agents` restored the launchd agents in a
   controlled stop/start check; confirm native typing and remaps separately.
   **No capture test proceeds merely because a timer was scheduled.**
4. Verify the development binary's signature/permissions and exact DriverKit
   protocol version; build and run focused offline tests. Resolve the known
   full-suite failures separately rather than counting them as new results.
   Do not remove the app-rule rejection for this first basic-input test.

## Timed test, only after preconditions and explicit go-ahead

1. Start the already-proven rollback timer. Confirm it is armed in launchd
   and its log is writable before changing any service.
2. Use Karabiner's supported Core-agent quit path, not the obsolete
   `karabiner_grabber` bootout command. Confirm the Core agent has stopped
   and normal native typing still works. Abort if it restarts unexpectedly.
3. Start **one** skhd grabber against the built-in keyboard with a minimal
   pass-through configuration, not Caps Lock or app-specific rules. Check
   plain typing, modifiers, key-up/release, and pointer control immediately.
   Do not test sleep/wake or long holds in the first timed window.
4. On any missed, duplicated, stuck, or delayed key, stop testing. Let the
   independent rollback release the seize, and verify native typing before
   considering another attempt. Do not cancel the timer just because a
   status command reports healthy.
5. If basic input works, end the grabber session deliberately, restore the
   original Karabiner service, and verify the original tap/hold keys and
   ordinary skhd hotkeys. Cancel/remove the timer only **after** the
   restoration checks pass. Keep logs and report exactly what was observed.

## Later gates

Only after the basic test passes: test tap/hold without app guards; then
focus changes and app-specific routing; then sleep/wake and failure recovery.
Caps Lock and the live Karabiner profile remain unchanged until their
replacement behavior is independently verified. A failed restoration means
stop work and use the native keyboard/mouse or reboot; do not uninstall the
shared driver or attempt further captures.

References: [Karabiner's quit procedure](https://karabiner-elements.pqrs.org/docs/manual/operation/quit/)
and [service architecture](https://github.com/pqrs-org/Karabiner-Elements/blob/main/DEVELOPMENT.md).
