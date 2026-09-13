# Qingniao (青鸟)

**English** | [简体中文](README.zh-CN.md)

> Your jade-feathered Mac productivity companion — a local-first macOS productivity center.

Qingniao (青鸟) is a native macOS productivity app. It stays in the menu bar, opens with
`⌥ Space`, and keeps clipboard, screenshot, and settings data on your Mac by default.

## Product page checklist

| Item | Content |
| --- | --- |
| Product name | Qingniao (青鸟) |
| Slogan | Your jade-feathered Mac productivity companion. |
| Core features | Command bar search (apps / commands / files / clipboard / calculator / settings), clipboard history, region/window/full-screen screenshots with annotation, safe built-in commands, and a unified settings center. |
| App icon | Jade `bird` glyph placeholder in `assets/product/` (final icon to follow). |
| Screenshots / demo GIF | `assets/product/` placeholders (`command-bar.png`, `clipboard-history.png`, `screenshot-annotation.gif`). Capture from the v1.2 release build before wider distribution. |
| Download button | [Download the latest release from GitHub Releases](https://github.com/freeabyss/qingniao/releases). |
| Version history | [CHANGELOG.md](CHANGELOG.md) and [GitHub Releases](https://github.com/freeabyss/qingniao/releases). |
| Privacy policy | [PRIVACY.md](PRIVACY.md). |
| Feedback email | [feedback@qingniao.app](mailto:feedback@qingniao.app). |
| FAQ | See [FAQ](#faq). |

## Download

[Download the latest release](https://github.com/freeabyss/qingniao/releases)

Qingniao is distributed as a Developer ID-signed and notarized app via GitHub Releases.
It does not use accounts, payment, subscriptions, license keys, or the Mac App Store.

## Core features

- **`⌥ Space` Command Bar**: A centered command bar that searches apps, commands, files,
  clipboard items, calculator results, and settings from one place. Switch sources with
  `⌘1`–`⌘6` (all / apps / commands / clipboard / files / settings).
- **`⌥⌘C` Clipboard history**: Record text, rich text, images, and Finder file references
  locally, with search, pinning, favorites, and clear-all controls.
- **Screenshots and annotation**: Capture region (`⇧⌃⌘4`), window (`⇧⌃⌘5`), or full-screen
  (`⌃⌥⌘3`); annotate with rectangles, arrows, text, and mosaic; then copy or save as PNG.
- **Safe built-in commands**: Run a fixed whitelist of 14 common macOS commands. Dangerous
  actions require a second confirmation.
- **`⌘,` Settings center**: Manage shortcuts, search sources, appearance, permissions, data,
  and updates in one place.

## Screenshots and demo assets

The product page should include the following launch assets before wider distribution
(placeholders live in `assets/product/`):

1. `assets/product/command-bar.png` — command bar with app, command, file, calculator, and clipboard result examples.
2. `assets/product/clipboard-history.png` — clipboard history window with type filter, search, pin, delete, storage usage, and clear-all entry.
3. `assets/product/screenshot-annotation.gif` — capture preview, annotation toolbar, copy, save, and cancel flow.
4. `assets/product/onboarding-permissions.png` — single-screen onboarding with on-demand permission explanations.

These assets are intentionally placeholders. Capture them from the signed release build during final release preparation.

## Permissions explained

Qingniao asks only for the macOS permissions it needs, and explains them before requesting access:

- **Screen Recording**: required for region, window, and full-screen screenshots. Screenshots are processed locally and are not uploaded.
- **Accessibility**: requested on demand — only when a feature that needs it is actually used, not during onboarding.
- **Apple Events / Automation**: used only for the whitelisted built-in commands that you explicitly trigger. The app does not execute arbitrary shell commands.
- **Clipboard access**: macOS does not show a separate permission prompt for clipboard reads, so onboarding and the privacy policy explicitly state that clipboard history is on by default, stored locally, and can be paused or cleared at any time.

## Privacy-first defaults

- Clipboard metadata and content are stored locally in Core Data and the app support folder (`~/Library/Application Support/Qingniao/`).
- Screenshots are captured, annotated, copied, or saved locally, defaulting to `~/Desktop`.
- File clipboard history stores file references and paths only; it does not copy file contents.
- No account system, cloud sync, analytics backend, payment system, or subscription is connected.
- Feedback is user-initiated email only; no diagnostic data is sent silently.

Read the full [Privacy Policy](PRIVACY.md).

## Version history

See [CHANGELOG.md](CHANGELOG.md) for release notes. The app's **Check for Updates** action opens
[GitHub Releases](https://github.com/freeabyss/qingniao/releases) so users can manually download
updates. Qingniao does not auto-download, auto-install, or restart to update.

## Feedback

Send bug reports, suggestions, and feedback to [feedback@qingniao.app](mailto:feedback@qingniao.app).
The feedback email generated from the app includes app version, build number, macOS version, an
optional error summary, and your notes. It does not attach clipboard history, screenshots, files,
or automatic crash logs.

## FAQ

### Is Qingniao free?

Yes. Qingniao is free and does not include payment, subscription, license-key, account, or Mac App Store flows.

### Where do I download updates?

Use [GitHub Releases](https://github.com/freeabyss/qingniao/releases). The app's **Check for Updates** button opens the same page.

### Does the app upload my clipboard or screenshots?

No. Clipboard history, screenshots, settings, and search usage data are local-first and remain on your Mac unless you manually include information in a feedback email.

### Can I turn off clipboard history?

Yes. You can pause clipboard recording in Settings and clear clipboard history from the clipboard history window or a built-in command.

### Why does the app request Screen Recording?

macOS requires Screen Recording permission for screenshot capture. The permission is used for region, window, and full-screen screenshots only.

### Why does the app request Accessibility?

Qingniao requests Accessibility on demand — only when a feature that needs it is actually used, so you can decide before granting access.

### Does Qingniao support arbitrary shell commands?

No. Only a fixed whitelist of 14 safe built-in commands is available. Arbitrary shell, `sudo`, shutdown, restart system, logout, file deletion, and process killing are out of scope.

### Is this available on the Mac App Store?

No. Qingniao is distributed via GitHub Releases as a Developer ID-signed and notarized app.

## Third-party notices

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
</content>
