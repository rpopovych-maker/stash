# Stash

A fast, native clipboard manager for macOS with a Liquid Glass interface.

Stash keeps everything you copy — text, images, links, files and colors — and brings it back with one shortcut. Pin the things you reuse into groups, search everything instantly, and paste straight into the app you're working in.

## Features

- **Clipboard history** for text (with formatting), images, links, files and hex colors, each shown with the app it came from
- **Instant search** across text, file names, source apps and even the text inside images
- **Groups** to pin items you want to keep — drag a card onto a group, or press ⌘P
- **Rename items** to give snippets a memorable name you can search for
- **Paste directly** into the active app, or just copy to the clipboard
- **Automatic cleanup** — keep history for a day, a week, a month, a year or forever; pinned items never expire
- **Privacy** — passwords from 1Password, Bitwarden, Keychain and other password managers are never saved, and you can ignore specific apps or pause capturing
- Lives in the menu bar, launches at login, no Dock icon

## Requirements

- macOS 26 Tahoe or later
- Apple Silicon or Intel Mac

## Install

1. Download **Stash.dmg** from the [latest release](https://github.com/rpopovych-maker/stash/releases/latest).
2. Open it and drag **Stash** onto the **Applications** folder in the window that appears, then eject the disk image.
3. Open Stash from Applications. macOS will warn that it can't verify the developer, because Stash isn't notarized by Apple. To allow it:
   - Open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to the message about Stash, then confirm, **or**
   - run this in Terminal:
     ```sh
     xattr -dr com.apple.quarantine /Applications/Stash.app
     ```
4. Stash appears as a clipboard icon in the menu bar — there's no window or Dock icon.

### Allow pasting into other apps

To paste directly into the app you're using, Stash needs Accessibility access. The first time you paste, macOS asks for it:

**System Settings → Privacy & Security → Accessibility → turn on Stash**

Without it, Stash still copies the item and you can press ⌘V yourself. You can turn direct pasting off in Settings.

### Updating

Download the new release and drag Stash onto Applications again, choosing **Replace**. macOS ties Accessibility access to the exact app build, so after updating, remove Stash from the Accessibility list with **–** and turn it on again.

## Usage

Press **⌥⌘C** to open Stash, then start typing to search. Click an item or press **↩** to paste it.

| Action | Shortcut |
|---|---|
| Open Stash | ⌥⌘C (change it in Settings) |
| Select previous / next item | ← → |
| Paste selected item | ↩ |
| Paste as plain text | ⇧↩ |
| Paste item 1–9 | ⌘1 – ⌘9 |
| Copy without pasting | ⌘C |
| Pin / unpin | ⌘P |
| Rename item | ⌘R |
| Delete from history, or unpin inside a group | ⌘⌫ |
| Next / previous tab | tab / ⇧tab |
| Clear search or close | esc |
| Open Settings | ⌘, |

### Groups and pinning

Pinning an item adds it to a group. Create a group with **+**, then drag a card onto it, right-click a card and choose **Pin to**, or press **⌘P** to pin to the last group you used.

Pinned items stay in your history in their normal order and are also kept in their group. When an item expires from history, it stays in its group. Each item belongs to one group at a time; deleting a group deletes the items in it.

## Build from source

Requires Xcode 26 or its Command Line Tools.

```sh
git clone https://github.com/rpopovych-maker/stash.git
cd stash
./build.sh --install
```

`build.sh` builds a universal app into `build/Stash.app`. Pass `--install` to copy it to Applications and launch it, `--dmg` or `--zip` to package it, or `--release` to create both.

Apps built locally are signed ad-hoc, which means macOS resets Accessibility access on every rebuild. To keep it between builds, create a self-signed certificate named **Stash Local Signing** in Keychain Access (**Certificate Assistant → Create a Certificate…**, type **Code Signing**); `build.sh` uses it automatically.

## Releasing

Push a version tag and GitHub Actions builds the app and publishes a release with `Stash.dmg` and `Stash.zip` attached:

```sh
git tag v1.0.0
git push origin v1.0.0
```

## Privacy

Your history is stored only on your Mac, in `~/Library/Application Support/Stash/`. Stash makes no network requests.

## License

[MIT](LICENSE) © Roman Popovych
