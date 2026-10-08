# Privacy Policy for Qingyu (清羽)

**English** | [简体中文](PRIVACY.zh-CN.md)

Last updated: 2026-07-06

Qingyu (清羽) is a local-first macOS productivity app. It is designed so clipboard history,
screenshots, settings, and usage data stay on your Mac by default.

## Data stored locally

Qingyu may store the following data locally:

- Clipboard records: text, rich text plain-text summaries, image resources, and Finder file references.
- Clipboard resources: image originals, thumbnails, and rich text RTF/HTML resources in the app support folder.
- Settings: hotkeys, launch-at-login preference, search source display settings, clipboard retention, screenshot save directory, appearance, and language preference.
- Search metadata: local blacklist entries and app/command usage counts used for result ordering.
- Screenshot files: PNG screenshots saved to the directory you choose, defaulting to `~/Desktop`.

All app data is stored under `~/Library/Application Support/Qingyu/`.

## Clipboard history

Clipboard history is enabled by default after onboarding confirmation. You can pause clipboard recording, adjust retention, delete individual items, or clear all clipboard history from the app.

File clipboard history stores file references and paths only. It does not copy file contents into the app database.

## Screenshots

Screenshots and annotations are processed locally. Copying a screenshot writes it to the system clipboard and may add it to local clipboard history. Saving a screenshot writes a PNG file to your configured screenshot directory (defaulting to `~/Desktop`) and does not create a separate screenshot history.

## Permissions

- **Screen Recording** is required for screenshot capture.
- **Accessibility** is requested on demand — only when a feature that needs it is actually used, not during onboarding.
- **Apple Events / Automation** may be used only for the whitelisted built-in commands that you explicitly trigger.
- **Clipboard access** is explained in onboarding because macOS does not show a separate prompt for clipboard reads.

## Network and uploads

Qingyu does not upload clipboard history, screenshots, files, settings, search usage data, or diagnostics automatically. It does not sync data to a cloud service and does not use your data to train models.

The app's **Check for Updates** action opens the GitHub Releases page in your browser for manual download. Qingyu does not auto-download, auto-install, or restart to update.

## Feedback email

Feedback is user-initiated email only. Before opening your mail app, Qingyu shows the data scope and lets you cancel. The generated email may include:

- App version and build number.
- macOS version.
- Optional error summary.
- Notes you type yourself.

The generated email does not attach clipboard history, screenshots, files, or automatic crash logs.

## Accounts, payment, and subscriptions

Qingyu does not include accounts, login, registration, payment, subscriptions, license keys, or Mac App Store purchase flows.

## Contact

For privacy questions or feedback, email [qingyu_freeabyss@163.com](mailto:qingyu_freeabyss@163.com).
</content>
