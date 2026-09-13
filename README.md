# Qingniao (青鸟)

**English** | [简体中文](README.zh-CN.md)

> A local-first macOS productivity tool — lives in the menu bar, opens with `⌥ Space`.

Qingniao collapses "launch an app, find a file, do the math, run a common system
action" into one unified search entry, and keeps your clipboard history on your
Mac. No accounts, no cloud sync, no analytics.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Version](https://img.shields.io/github/v/release/freeabyss/qingniao?label=version)
![License](https://img.shields.io/badge/license-Free%20personal%C2%B7No%20commercial-orange)
![Language](https://img.shields.io/badge/UI-Simplified%20Chinese%20%7C%20English-green)

---

## Download

**[Get the latest release from GitHub Releases →](https://github.com/freeabyss/qingniao/releases)**

- Requires macOS 13 Ventura or later
- Signed with Developer ID and notarized by Apple — drag into Applications and run
- No accounts, payments, subscriptions, or license keys
- The in-app **About → Check for Updates** action opens the Releases page above;
  it never downloads or installs anything automatically

> If macOS blocks the first launch, choose "Open Anyway" under
> **System Settings → Privacy & Security**.

## Features

### `⌥ Space` Unified Search

A centered command bar returning four result types concurrently, up to 12 rows:

| Source | Behavior |
| --- | --- |
| **Apps** | Scans `/Applications`, `~/Applications`, `/System/Applications`; `⏎` launches |
| **Files** | Searches Desktop, Documents, Downloads by default; `⏎` opens, `⌘Enter` reveals in Finder, `⌘C` copies the full path |
| **Calculator** | Parses math expressions and unit conversions locally; results are copyable |
| **Built-in commands** | 12 pre-registered safe actions, listed below |

Search matches English and Chinese keywords, pinyin, and pinyin initials.
With an empty query, the home screen shows **Frequent actions** and
**Recently used**; the ordering data stays on your Mac.

The command bar always appears on the display **where your pointer is** —
on multi-monitor setups you never hunt for the window.

### `⌥⌘C` Clipboard History

- Records text, rich text, images, and Finder file references; one copy that
  yields multiple representations becomes a single record
- Duplicate content is merged by digest, updating its last-seen timestamp
- Search, filter by type, pin, favorite, preview, copy, delete individually
- Retention: 7 / 30 / 90 days or forever, defaulting to 30 days
- Recording can be paused at any time; clearing everything requires confirmation
- File records store paths and metadata only — **never file contents**;
  records are marked unavailable when the source file disappears

Clipboard search is a separate, window-local search. Unified search reaches the
history window through a single built-in command, **Clipboard**.

### Built-in Commands

| Category | Commands |
| --- | --- |
| Navigation | Open System Settings, Open App Settings, Open Downloads, Open Applications, Open Desktop |
| Clipboard | Open Clipboard History, Clear Clipboard History, Pause or Resume Clipboard Recording |
| System | Check Permissions, Restart Finder, Restart Dock, Toggle Appearance |

Only pre-registered fixed actions run — **arbitrary shell commands are never
parsed or executed**. Clearing clipboard history, restarting Finder, and
restarting Dock require a second confirmation.

### `⌥⌘,` Settings

Four pages: **General** (plugin management, appearance, language, storage usage,
permission status), **Quick Launch** (file search directories and index state),
**Clipboard** (recording toggle, retention, clear), and **About** (version,
updates, feedback, privacy policy, open-source licenses).

Features plug in as first-party modules you can enable or disable individually
under **General → Plugin management**. If one plugin fails to start, the rest
keep running, and the failure reason plus a retry action stay in the list.

Interface language offers **Follow System**, **Simplified Chinese**, and
**English**, applied immediately.

## Privacy

Qingniao is local-first and offline by default:

- Clipboard content, usage frequency, and settings all stay on your Mac in
  `~/Library/Application Support/Qingniao/`
- No account system, cloud sync, analytics backend, or payment channel
- The file index is built locally; file names and paths are never uploaded
- Feedback is user-initiated email only. The generated message contains the app
  version, build number, macOS version, and your notes — it **never attaches**
  clipboard history, screenshots, files, or crash logs

Read the full [Privacy Policy](PRIVACY.md).

### Permissions

Qingniao requests only what it uses, and explains it before asking:

| Permission | Purpose | When requested |
| --- | --- | --- |
| **Accessibility** | Keyboard/mouse simulation, auto-paste, window control | On demand, when a related feature is first used |
| **Apple Events** | Built-in commands that control other apps | Before the first such command runs |
| **Clipboard** | macOS shows no separate prompt for clipboard reads | On by default; pausable and clearable anytime |

Declining any permission never blocks you from using the app. The affected
feature stays unavailable and offers **Grant**, **Recheck**, and
**Open System Settings**.

## Roadmap

### Screenshots & Pinning (in development, not yet shipped)

A single capture entry — one hotkey enters capture state, and your pointer
position plus mouse behavior decide the mode automatically:

- Hover a window → window capture; hover the menu bar or empty desktop → full
  display; press and drag → region selection
- Region selection wins over the hover default, wherever the drag starts
- Moving the pointer to another display moves target detection with it
- Annotation: rectangle, arrow, line, polyline, text, mosaic
- Color picker; copy, save (system panel, PNG / JPEG), quick save (fixed directory, PNG)
- Overlay across all displays, with in-session hotkey hints
- **Pinning**: turn a screenshot or clipboard content into a floating window
  above everything else, with scaling, opacity, hide, close, restore queue, and destroy

A capture session is released when it ends. The product keeps no screenshot
history and never deletes image files you saved.

### Context Menu Extension (planned)

Bring Qingniao actions into the system right-click menu so common operations are
available in your current context, without invoking the command bar first.

### Also considered

- Automatic update checks (currently manual navigation to the Releases page; no
  background networking)
- Screenshot OCR text recognition

> Roadmap items and timing are plans, not commitments. The screenshot code is
> implemented and tested but held behind a feature gate; it opens after
> multi-display, TCC, and signing acceptance is completed before release.

## Screenshots

> ⚠️ Real-device screenshots pending. Capture them from a signed release build;
> the list and size requirements live in
> [assets/product/README.md](assets/product/README.md).

Product homepage: <https://freeabyss.github.io/qingniao/>

## License

Qingniao is **free for personal, non-commercial use**, but **commercial use is
prohibited**, and the project owner reserves the right to introduce paid
features or commercial licensing in future versions.

Without prior written permission you may not use this software in any business
operation, sell, redistribute, sublicense, or distribute modified versions.
See [LICENSE](LICENSE).

For commercial licensing: <feedback@qingniao.app>

This software includes third-party open-source components, each under its own
license. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Version History

See [CHANGELOG.md](CHANGELOG.md) and
[GitHub Releases](https://github.com/freeabyss/qingniao/releases).

## Feedback

Bug reports, feature requests, commercial licensing: <feedback@qingniao.app>

Or open an [Issue](https://github.com/freeabyss/qingniao/issues) directly.

## FAQ

**Is Qingniao free?**
Free for personal, non-commercial use — no payments, subscriptions, license keys,
or accounts. Commercial use requires a separate license.

**Why can't I find the screenshot feature?**
Screenshots are finishing acceptance and are not enabled in this release. Once
enabled they appear in the menu bar, hotkeys, and Settings.

**Does it upload my clipboard?**
No. Clipboard history, settings, and usage frequency stay on your Mac — no
networking, syncing, or uploading.

**Can I turn off clipboard recording?**
Yes. Pause it under **Settings → Clipboard**, or use the built-in command
**Pause or Resume Clipboard Recording**.

**Does it support arbitrary shell commands?**
No. Only the 12 pre-registered built-in commands; user input is never executed.

**Is it on the Mac App Store?**
No. Distributed only through GitHub Releases, signed with Developer ID and
notarized by Apple.

**Does `⌥ Space` conflict with Spotlight?**
Qingniao never changes your system shortcuts on its own. If a conflict is
detected, Settings warns you and you can rebind Qingniao to another key.

**Multi-monitor support?**
The command bar appears on the display holding your pointer. Multi-display
support for screenshots ships with the screenshot feature.
