# Changelog

All notable changes to Qingyu (清羽) are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Public downloads are published on
[GitHub Releases](https://github.com/freeabyss/qingyu/releases).

## [Unreleased]

### Added

- **Automated release pipeline.** `.github/workflows/release.yml` builds a
  universal binary, signs and notarizes it, packages a `.dmg`, and uploads it to
  a GitHub Release when a `v*` tag is pushed (or via manual dispatch).
- **Local packaging script.** `scripts/package-release.sh` (also exposed as
  `./start.sh package`) produces a notarized universal `.dmg` and can upload it
  with `gh`.
- **Installer self-cleanup.** After the app is installed under `/Applications`,
  the first launch moves a downloaded `Qingyu-*.dmg` from `~/Downloads` /
  `~/Desktop` to the Trash (recoverable), at most once per version.
- **First real-device screenshot.** `assets/product/command-bar.png` (the
  `⌥ Space` command bar) is wired into the READMEs and the product page.

### Changed

- **Distribution is now a universal-binary `.dmg`.** The minimum system
  requirement is lowered from macOS 13 Ventura to **macOS 12 Monterey**, and the
  release binary now contains both `arm64` (Apple Silicon) and `x86_64` (Intel)
  slices. `LaunchAtLoginService` degrades gracefully on macOS 12, where
  `SMAppService` is unavailable.
- **Marketing copy.** The "没有账号，没有云同步，没有埋点" slogan is replaced by
  the simpler "无需账号" / "No account required" across the README and website.

### Fixed

- **Clipboard "Show in Finder" no longer fails silently.** When a file or folder
  copied earlier has since been moved or deleted, the row icon, the context menu
  item, the detail-pane button and the preview sheet now report it with an error
  toast ("文件已不存在，可能已被移动或删除" / "File or folder no longer exists…")
  instead of doing nothing. The toast auto-dismisses after a short delay.

### Changed

- **Product rename: 青鸟 Qingniao → 清羽 Qingyu.** App display name, module,
  Xcode project/targets/scheme, source directories, data directory
  (`~/Library/Application Support/Qingyu/`), Bundle Identifier
  (`com.freeabyss.qingyu`), feedback address (`qingyu_freeabyss@163.com`), GitHub
  repository (`freeabyss/qingyu`), website, docs, and scripts are updated.
  Launch-time migration still moves an existing `Qingniao/` (or older
  `Assistant/`) data directory into `Qingyu/` and renames the Core Data store.

## [1.2.1] - 2026-08-11

Patch release fixing two first-run onboarding bugs that blocked all app entry
points for new users (issue #7).

### Fixed

- **All feature entry points no longer redirect to onboarding.** Removed the
  onboarding gate that hijacked the search / clipboard / screenshot / settings /
  about menu items and forced the onboarding window back on screen whenever setup
  was incomplete. Entry points now route to their own panels; onboarding shows
  only on first launch or when explicitly opened from the menu.
- **Onboarding footer buttons are always visible.** The first-run view's fixed
  520pt height clipped the "开始使用" / "跳过设置" buttons out of the viewport on
  the default and enlarged font sizes. The middle content is now wrapped in a
  `ScrollView` with the header and footer pinned, so the buttons stay reachable
  at any font size and in both appearances.
- Closing the onboarding window (including the title-bar close button) now clears
  its reference, so it cannot be resurrected as a zombie window; re-opening it
  from the menu no longer changes the completed state.
- Full-experience service startup (clipboard monitor, cleanup, global shortcuts)
  is now idempotent, so completing onboarding a second time via the menu does not
  double-start them.

### Added

- A "欢迎向导" menu item that re-opens the onboarding guide without resetting
  completion state.
- XCUITest infrastructure: a `QingyuUITests` target, DEBUG-only launch-argument
  hooks (`--uitest-reset-onboarding`, `--uitest-mock-screen-recording-*`,
  `--uitest-trigger`, `--uitest-data-dir`, `--uitest-large-text`,
  `--uitest-skip-shortcuts` / `--uitest-skip-screenshot-capture`), and
  `accessibilityIdentifier` on key onboarding, menu, command-bar, clipboard and
  settings controls. 22 UI test cases (TC-UI-001~022) are implemented and
  compile; running them is gated behind a one-time macOS UI automation
  authorization in System Settings.

## [1.2.0] - 2026-07-06

Public release of **Qingyu (清羽)** — a full product review and brand rename from the
earlier SnapVault/Assistant MVP.

### Added

- File search across `~/Desktop`, `~/Documents`, and `~/Downloads` in the command bar
  (open with `⏎`, reveal in Finder with `⌘R`, copy path with `⌘C`).
- Full-screen screenshot hotkey `⌃⌥⌘3`.
- Single-screen onboarding with per-permission, on-demand requests.
- `⌘1`–`⌘6` source switching in the command bar (all / apps / commands / clipboard / files / settings).
- "Clear all data" and "Open data folder" actions in Settings.
- Jade design system (color / radius / spacing / font / shadow / material tokens) and a
  unified Jade component library.
- Redesigned 11-page settings center.
- New shortcuts: `⌥⌘C` (clipboard history) and `⌥⌘,` (settings).
- `AppContainer` dependency-injection container and dedicated window controllers.

### Changed

- Brand name is now **Qingyu (清羽)**; project renamed SnapVault → Qingyu.
- Default screenshot directory changed to `~/Desktop`.
- Region / window screenshot hotkeys changed to `⇧⌃⌘4` / `⇧⌃⌘5`.
- Accessibility permission is now requested on demand instead of during onboarding.
- UI fully migrated to Jade design tokens.

### Fixed

- Refactored `AppDelegate` from 955 lines down to ~150 by extracting window controllers.
- Removed force-unwraps in favor of safe unwrapping.
- Version number unified to `1.2.0` across all three sources (Info.plist / project / about page).
- Restarting the app no longer re-triggers onboarding.
- Hotkey conflict detection with in-line warnings in Settings.
- Consolidated duplicate clipboard, search, and toast implementations.

### Removed

- App Sandbox (now distributed via Developer ID signing + notarization).
- Sparkle auto-update placeholder.
- OCR (deferred to a future V2.x release).
- Dead code: `UnifiedSearch*`, `MenuBarView`, `UnitConverterSource`, GRDB `ContentRepository`.
- Screenshot blur tool (deferred to v1.3).

### Security

- With the sandbox disabled, the `apple-events` entitlement is enabled to support the
  14 whitelisted built-in commands.

## [1.1.0] - 2026-07-03

### Fixed

- Resolved an onboarding deadlock when requesting Screen Recording permission
  (now uses `CGRequestScreenCaptureAccess`).
- Added a "Skip setup" entry point to onboarding.

## [1.0.1] - 2026-07-02

### Fixed

- Removed the "Cannot launch the update program" alert shown on startup.

## [1.0.0] - 2026-07-02

### Added

- MVP release: menu bar app, `⌥Space` search, clipboard history (text / rich text / image / file),
  screenshot capture with mosaic annotation, 14 whitelisted built-in commands,
  calculator / unit conversion, settings center, and an onboarding wizard.

---

## Early drafts

### 0.1.0-mvp — Public beta preparation (superseded by 1.0.0)

- Added menu bar app shell with Spotlight-style unified search entry.
- Added application launch search for standard macOS app directories.
- Added local clipboard history for text, rich text, images, and Finder file references.
- Added clipboard history management with search, type filter, pinning, delete, clear-all, retention, and storage usage.
- Added region, full-screen, and window screenshot capture with preview toolbar.
- Added lightweight screenshot annotation tools: rectangle, arrow, text, mosaic, undo, and redo.
- Added safe built-in command source with confirmation for medium-risk actions.
- Added calculator and unit conversion search results.
- Added onboarding, permission gate, settings, language selection, privacy policy, feedback email, about page, and update link.
