# Pre-publication review

Date: 2026-10-18. Scope: the prepared source-only publication directory.
The initial publication contains only the sanitized source inventory. No earlier
private development history is included.

## Completed checks

- Reviewed the publication file inventory and local signing workflow.
- Pattern scan of 24 publishable files found no private-key blocks, recognized
  GitHub/OpenAI/AWS token patterns, embedded URL credentials, personal home paths,
  private project identifiers, or non-license email addresses.
- Font-license attribution and third-party copyright notices were preserved.
- Verified 10 ignore-rule cases covering build products, installers,
  environment files, private keys, keychains, and local diagnostic output.
- Shell syntax validation passed for build, package, and test scripts.
- All 34 policy tests passed with the publication bundle identifier.
- The source compiled successfully and its ad hoc code signature verified.
- No private signing keychain, password file, user preference file, bookmarks,
  or credentials were copied into this publication directory.

## Excluded material

The original local project retains the installed-app copy, installers, build
cache, raw performance logs, personal diagnostic history, branding experiments,
and Figma import plugin/assets. Those files are not part of this publication
copy. The standalone source icon and required fonts are included.

## Deliberate differences

The publication bundle identifier is app.hidecell.Hidecell. It has separate
preferences, login registration, and permissions from earlier private builds.
The private signing script was replaced with configurable development signing.
No app was installed or launched from this publication copy during review.

## Remaining limitations

This was a targeted local scan and review, not an exhaustive vulnerability
assessment or a dedicated secret-scanner run. Pattern scans can miss unusual
secrets, encoded data, or unknown formats. Required icon/font binaries were
selected by provenance rather than scanned as source text.

The app requires Accessibility and menu preference access, uses internal macOS
formats/private APIs, and can write menu settings. It also offers user-triggered
diagnostic export and writes a local temporary layout snapshot. Review such
exports before sharing them. Cross-Mac compatibility and notarization are not
established by a successful local build.

Before public release, select the license for original project code and review
third-party provenance. Preserve all existing license notices. Enable GitHub
secret scanning/push protection where available. Do not add signing secrets to
Git, including in a private repository. The publication remote is https://github.com/umutcaneyriyer/hidecell.
