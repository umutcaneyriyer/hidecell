# Hidecell — V1 Node

A local macOS application for selecting which third-party menu bar icons to
hide and arranging their order. Changes are applied with Save changes.

## Download

[Download for Mac (.dmg)](https://github.com/umutcaneyriyer/hidecell/releases/download/v1.5.19/Hidecell-1.5.19.dmg)

Open the disk image and drag Hidecell into Applications. This is a development
build with ad hoc signing, not Developer ID signed or notarized. macOS may require
approval to open it and renewal of Accessibility permission after updating.

## A closer look

![Hidecell applications window on a violet satin wallpaper](docs/images/applications.png)

### At home in the menu bar

Hidecell lives alongside your macOS status icons. Click its menu bar icon to
reveal or hide your saved selection.

[Watch the menu bar demo (MP4, 15 seconds)](docs/videos/hidecell-menu-bar-demo.mp4)

An unedited screen recording of Hidecell in use.

![Hidecell's purple icon in the macOS menu bar](docs/images/menu-bar.png)

### Put your apps in order

Choose Order applications, drag rows into place, and choose Save changes.
Cancel leaves the saved order unchanged.

![Hidecell's Order Applications view](docs/images/ordering.png)

These are styled product illustrations based on actual application screenshots,
with AI-assisted wallpaper and presentation edits. They are not unmodified
screen captures; system icons and appearance may vary by macOS version.

## Requirements

- Apple Silicon and macOS 27 or later for the current build configuration.
- Xcode command-line developer tools with the macOS 27 SDK, plus Python 3.
- Accessibility permission; explicit access to the menu layout file when
  changing icon order and native visibility settings.

## Development

```sh
./test.sh
./build.sh
./package.sh ./Installers
# For the custom drag-to-Applications DMG, see Packaging/README.md.
./package-dmg.sh
```

The default build uses an ad hoc development signature. To use a certificate
already present in your local Keychain, set HIDECELL_SIGNING_IDENTITY to its
identity name or fingerprint before running build.sh. Never store private keys,
passwords, or notarization credentials in this repository.

The generated local package is unsigned as an installer and is not notarized.
Developer ID distribution requires a Developer ID Application signature, a
Developer ID Installer signature, notarization, and verification of the result.
The scripts do not perform notarization or upload anything.

## Application workflow

Click a row to change its draft hidden selection, then choose Save changes.
Cancel restores saved selections. Choose Order applications, drag rows, and
save to apply the menu order. The menu bar icon reveals or hides the saved
selection. Launch at login is configured by the application.

## Publication copy and compatibility

This sanitized publication copy uses app.hidecell.Hidecell, an independent
bundle identifier. It is not a drop-in update for earlier private builds:
preferences, login registration, and permissions are separate. Quit other
menu bar managers and private Hidecell builds before testing it. Existing
private builds and their data have not been changed by this preparation.

Menu visibility and ordering rely on internal macOS preference formats and
private APIs. Future OS releases may require changes. Other Macs, Intel builds,
and older macOS releases are not validated. A successful local build does not
establish release readiness across supported systems.

## Licensing

Third-party license notices are retained in THIRD-PARTY-LICENSE.txt and Fonts/.
No additional license grant has been selected for Hidecell's original code.
Choose a project license before presenting this repository as open source.
See THIRD-PARTY-NOTICES.md and SECURITY-REVIEW.md.

### Legacy visibility recovery (1.5.13–1.5.15)

Version 1.5.13 uses a session guardian for menu visibility writes. It restores original states on UI exit, force termination, or removal of the app executable, even if app preferences were deleted. It exits after recovery and installs no login agent. New hiding writes require a responsive guardian.

Recovery cannot run if the guardian itself is forcibly killed (SIGKILL), the machine loses power, or macOS denies preference access. Saved recovery preferences can be used by the legacy recovery tooling when available. No application can guarantee cleanup when all its processes and recovery data are removed together.

Run isolated crash/removal integration tests with:

```sh
xcrun swiftc -D RECOVERY_TESTING -module-cache-path .build/ModuleCache Sources/NativeVisibility.swift Sources/VisibilityGuardian.swift Tests/Recovery/main.swift -o .build/HidecellRecoveryTests
python3 Tests/Recovery/integration.py
```


### Native visibility with session recovery (1.5.18)

Hiding uses per-application native visibility settings. It does not use assessment
mode, intercept clock clicks, or reveal icons when the pointer approaches the clock.
A launchd job is prepared before the first visibility change. Its recovery journal
and executable are copied outside the app bundle and app preferences. On quit,
process death, or executable removal it restores only the original managed states.
launchd restarts the recovery process if it crashes. It removes itself after recovery;
no login item or persistent LaunchAgents file is installed.

Recovery still requires access to the native preference domain. Power loss, logout
before recovery, or removal of the recovery directory itself are not covered by this
session job. This is not a claim that every third-party uninstaller was tested.

Run the new isolated launchd integration tests with:

```sh
xcrun swiftc -D RECOVERY_TESTING -module-cache-path .build/ModuleCache Sources/NativeVisibility.swift Sources/VisibilityGuardian.swift Sources/SessionRecovery.swift Tests/SessionRecovery/main.swift -o .build/HidecellSessionTests
python3 Tests/SessionRecovery/integration.py
```

Validated: normal termination, main-process kill, simultaneous main/helper kill,
and executable plus app-preferences deletion, all against an isolated test domain.
Live Notification Center and uninstall checks are recorded separately in CHANGELOG.md.
