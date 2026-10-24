# `carcot/skhd.zig` app-scoped remap build

This fork extends the upstream skhd grabber with exact-bundle-ID app guards
for tap/hold rules and app-specific `passthrough`. It also ports the virtual
keyboard connection to Karabiner DriverKit 8.5's stream protocol, forwards
frontmost-app changes from the agent, selects one rule per key/device/app, and
reconnects and reapplies rules when the grabber connection drops. See the
[README](../README.md#this-fork-app-specific-low-level-remaps) for an example
and [the design/test record](APP_SCOPED_REMAPS.md) for details.

## What the app bundle contains

The `skhd.app` archive contains the user-session `skhd` binary and the
root-only `skhd-grabber` binary. It is an Apple Silicon, ReleaseSafe build:
normal information and warnings remain, but Debug's per-key HID tracing is
compiled out. It is signed with an Apple Development identity, **not** a
Developer ID distribution certificate, and is **not notarized**. It is a
fork-specific pre-release artifact, not an upstream or Homebrew release.

The archive is not an automatic migration installer. The existing
`--install-service` path handles ordinary skhd but does not turn on the
experimental app-scoped grabber flag or its separate socket. A user must
configure the root grabber with `--experimental-app-scoped-rules` and a
non-default `--socket-path`, then run an agent with `-V -c <config>` and
`--grabber-socket <same-path>`. An exact device guard is required. Do not
run Karabiner's keyboard-owning user agents and this grabber against the
same physical keyboard at once. The Karabiner DriverKit virtual-HID daemon
is still required even when those user agents are disabled.

The current Mac keeps its proven development bundles and dedicated launchd
jobs; downloading this release does **not** replace them. Its local
`skhd --status` checks the default socket, not the custom remap socket; use
`skhd --grabber-status <socket-path>` for the latter.

## Reproduce the artifact

Build with Zig 0.16.0 on Apple Silicon:

```sh
zig build app -Doptimize=ReleaseSafe
SKHD_CERT='Apple Development: ...' \
SKHD_BUNDLE_ID=com.jackielii.skhd \
SKHD_NO_AUTO_GENERATE_CERT=1 \
bash scripts/codesign.sh zig-out/skhd.app
codesign --verify --strict --verbose=2 zig-out/skhd.app
```

The release archive preserves the entire `.app` bundle. Its signing
certificate, architecture, checksums, and exact validation results are in
the GitHub Release notes. The package does not contain a user's private
configuration, macOS permissions, or the Karabiner DriverKit installer.

## Validation and limits

- A guarded one-hour trial of the development build's 24-rule replacement
  configuration completed successfully on one built-in keyboard. The user
  also confirmed normal typing and the Caps, Tab, Right Shift, Right
  Command, and Right Option actions after the permanent local cutover.
- Those physical-input checks were **not** run on this ReleaseSafe bundle.
  Reboot/login, sleep/wake, and Emacs/Portacle exclusions remain unverified.
- The full `zig build test` suite currently has a `Hotload.test.hotload file
  watching` failure on this machine; do not present the suite as passing.
  The release notes should record any final rerun and focused test results.
- The local return-to-Karabiner script at
  `scripts/restore-karabiner.sh` contains this Mac's user ID and account
  name. It is a tested local recovery reference, **not** a portable
  installer or an appropriate command to run unchanged on another Mac.
