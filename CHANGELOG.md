# Changelog

## 1.5.19 — 2026-10-24

- Reuse the existing header action button style for both permission prompts.
- Share prompt typography, spacing and surface styling; show menu-file access only after Accessibility access.
- Add a Retina drag-to-Applications DMG with a custom lavender background and reproducible packaging script.
- Verify the installed build recognizes permissions and hides selected icons.

## 1.5.18 — 2026-10-24

- Remove assessment-based hiding and all hover/clock interaction workarounds. Use native per-application visibility.
- Start an independent launchd recovery job before hiding; persist original states outside the application and its preferences. Restart recovery on helper crashes and remove the session job after restoration.
- Stop the main writer before restoring after executable removal, preventing an in-flight hide from overwriting restoration.
- Preserve the menu-bar-only lifecycle and background operation after Command-W.
- 46 policy tests and four isolated launchd recovery scenarios pass. On the development Mac, Command-W keeps hiding active; SIGKILL and reversible removal of the installed bundle both restore icons. A subsequent user check reported normal operation; CleanMyMac itself was not used in the removal test.

## 1.5.17 — 2026-10-23

- Run as an accessory menu-bar app with LSUIElement enabled, without a Dock icon.
- Keep the process alive after closing the management window; expose Quit only in the status-item menu.
- Remove event interception and synthetic clock-click replay. Suspend hiding while the pointer approaches the clock and while Notification Center is visible.
- Refresh clock bounds off the main thread instead of retaining a stale position.
- Build and 46 policy tests pass. Accessibility renewal completed; the process and status item remain available after Command-W. Native clock clicks require manual verification because the UI automation tool cannot target the system clock window.

## 1.5.16 — 2026-10-22

- Replace persistent icon-visibility writes with a process-scoped menu assertion. No guardian process is used for new hiding sessions.
- Release hiding on normal exit and detect removal of the running executable. macOS releases the assertion when the process is killed.
- Add clock-click suspension to allow the native Notification Center interaction; live clock interaction verification remains pending.
- Live checks passed: reveal/hide toggle, normal quit, SIGKILL, and reversible removal of the installed bundle. CleanMyMac itself was not used in this verification.

## 1.5.15 — 2026-10-21

- Move guardian requests off the main thread so visibility acknowledgements cannot freeze the interface.
- Serialize visibility changes and coalesce pending requests to the latest requested state.
- Avoid full accessibility menu traversal when the native registry is readable.
- Let guardian EOF recovery handle termination without scheduling new UI work.

## 1.5.14 — 2026-10-21

- Open privacy settings without stacking an AX permission modal over System Settings.
- Wait for Accessibility approval before reading visibility settings or starting hiding.
- Resume setup when access is granted and restore visibility when access is revoked.
- Keep development-signing permission renewal requirements explicit.

## 1.5.13 — 2026-10-20

- Move visibility writes into a session guardian that restores original icon states when the UI exits, crashes, or its executable is removed.
- Keep recovery state in guardian memory so deletion of app preferences cannot erase active-session recovery.
- Refuse new hiding writes if the recovery channel fails; retry temporary restoration failures for up to 30 seconds.
- Preserve originally disabled icons and unrelated Control Center settings during recovery.

## 1.5.12 — 2026-10-20

- Automatically hide newly discovered menu apps without manual selection.
- Preserve previously visible apps across relaunches, including known helper identities.
- Merge automatic discoveries into pending edits without discarding user changes.

## 1.5.11 — 2026-10-20

- Discover running menu apps through the macOS registry even when their accessibility extras bar is unavailable.
- Reapply saved hiding choices after delayed status-item registration.


## V1 Node — 2026-10-18

- Draft visibility selections with Cancel and Save changes.
- Explicit ordering mode with full-row dragging.
- Disabled Save changes when the order is unchanged.
- Compact rows, hover controls, search, and scroll-edge fades.
- Header action buttons use bundled Inter Regular (400), 14 pt, with a 32 pt height.
- English application text and documentation.
- Local regression testing: 34 policy tests passed.

## Publication preparation

- Created a source-only publication copy with an independent, non-personal bundle identifier.
- Excluded installed apps, packages, build caches, raw diagnostics, design-import
  experiments, personal test history, and signing credentials.
- Replaced private signing setup with configurable development signing.
- Added ignore rules and publication security review.
