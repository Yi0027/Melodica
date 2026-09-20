# 🎵 Melodica

> **📌 Installation:** Available via [Homebrew](#option-1--homebrew-recommended) or [direct download](#option-2--direct-download). See [Download](#-download) below.

No big words or corporate fluff here.  
This is just a solid, good-looking audio player for macOS that I built for myself, because nothing else on the market felt right.

If you've also been looking for a lightweight player that actually handles tags and volume properly — maybe this one will click with you.

---

**Jump to:**
- [✨ What it can do](#-what-it-can-do)
- [⚠️ Beta Features](#️-beta-features)
- [🖼️ Screenshots](#️-screenshots)
- [🔧 Requirements](#-requirements)
- [📝 About `-pre` versions](#-about--pre-versions)
- [📦 Download](#-download)

---

## ✨ What it can do

- Two interface themes: classic and new **Liquid Glass**
- Plays MP3, FLAC, M4A, AAC and other formats supported by the playback engine
*(tested with MP3, FLAC, M4A, OGG and OPUS)*
- Shows lyrics (synchronized .lrc and embedded ID3)
- **Custom LRC engine** built on Core Animation with **word-by-word highlighting** and **full LRC metadata support**
- ReplayGain so volume doesn't jump between tracks
- Rating support (read and write tags)
- Smart library: sort by title, artist, album, genre, year, rating
- Album grid view
- Favorites and playback queue
- Custom colors (background, accent, text and more)
- English & Russian (open settings and select)
- Media keys support: F7, F8, F9
- **Menu bar player** (control from the menu bar)
- Equalizer (custom) with **presets** and **auto-apply by genre**
- Crossfade between tracks
- Gapless playback
- Silence Skip
- M3U playlist support
- Smart playlists (rules-based)
- CUE sheet support
- **Library statistics** (top artists, genres, formats, etc.)
- **Custom artwork** for genres and artists
- Drag & Drop files/folders
- Volume control

---

## ⚠️ Beta Features

- **Writing rating tags to files** — currently in beta. It works, but there is a small chance it may corrupt the file. Use with caution, and keep backups of your library.

---

## 🖼️ Screenshots

*Screenshots use royalty-free music from [Jamendo](https://www.jamendo.com).*

![Right panel](https://github.com/Yi0027/Melodica/blob/main/screenshots/right%20panel.jpg)
![Spectrum](https://github.com/Yi0027/Melodica/blob/main/screenshots/spectrum.jpg)
![MiniPlayer](https://github.com/Yi0027/Melodica/blob/main/screenshots/miniplayer.jpg)

---

## 🔧 Requirements

- macOS 13.0+ (Ventura) — minimum
- macOS 26.0+ (Tahoe) — recommended: enables the new Liquid Glass design

---

### 📝 About `-pre` versions

Some releases are tagged `v1.4.3-pre` instead of `v1.4.3`.

**`-pre` doesn't mean "broken" or "unstable"** — it means I tested it enough to be confident it works, but didn't run a full pass through every feature before publishing.

For a personal project like this, waiting for a "complete" test cycle would mean no releases at all. So I ship when it feels right, and fix bugs as they surface.

- ✅ **`-pre`** — works, some edge cases may have slipped through
- ✅ **no suffix** — extra bug sweep before release

Either way, if you find something broken — open an issue.

---

## 📦 Download

### Option 1 — Homebrew (recommended)

The easiest way. Homebrew installs the app and handles the macOS quarantine + ad-hoc signing automatically — no Terminal commands needed after install.

> **Don't have Homebrew yet?**  
> Install it first — it's one command and takes a few minutes:  
> https://brew.sh

To install:

```bash
brew tap yi0027/melodica
brew install --cask yi0027/melodica/melodica
```

To update later:

```bash
brew upgrade --cask yi0027/melodica/melodica
```

To uninstall:

```bash
brew uninstall --cask melodica
brew untap yi0027/melodica
```

### Option 2 — Direct download

Grab the latest `.dmg` from [Releases](https://github.com/Yi0027/Melodica/releases/), open it, and drag `Melodica.app` into your `Applications` folder.

Since I didn't pay Apple for a Developer ID (it's expensive and a pain), macOS will show a warning on first launch: *"Melodica cannot be opened because the developer cannot be verified."* This is expected — the app is ad-hoc signed, just not notarized by Apple.

**To open it:**

1. Try to open `Melodica.app` from your `Applications` folder. You'll see the warning — dismiss it (click **Done** or **Cancel**).
2. Open **System Settings** → **Privacy & Security**.
3. Scroll down to the **Security** section. You'll see a message like *"Melodica.app was blocked from use because it is not from an identified developer."*
4. Click **Open Anyway**.
5. Enter your password if prompted, then click **Open** in the final dialog.

You only need to do this once. After that, the app opens normally with a double-click.

> **Note:** The **Open Anyway** button is only available for about an hour after you try to open the app. If you don't see it, try launching `Melodica.app` again, then go back to System Settings → Privacy & Security.

---

#### If that doesn't work

On some macOS versions, the **Open Anyway** button doesn't appear reliably. In that case, open **Terminal** and run:

```bash
sudo xattr -cr /Applications/Melodica.app
```

This removes the quarantine flag that macOS adds to files downloaded from the internet. After that, the app opens normally.

> **Note:** `xattr` ships with macOS by default — no additional install needed.

---

#### Last resort: re-signing the app

> ⚠️ **You almost certainly don't need this.** Try the steps above first. Re-signing is only useful if the app genuinely refuses to launch *and* `xattr` didn't help.

The app ships with a valid ad-hoc signature, so macOS can verify its integrity. But if something went wrong during download or extraction, you can re-sign it locally:

1. Make sure `codesign` is available on your Mac. It ships with either **Xcode** or **Command Line Tools**. If you've never installed either, open Terminal and run:

```bash
xcode-select --install
```

A system dialog will appear — click Install and wait a few minutes.  
Requires ~2 GB of free disk space. You don't need an Apple ID — just click Install in the dialog.

2. Then re-sign the app:

```bash
codesign --force --sign - /Applications/Melodica.app
```

> **Note:** This overwrites the app's original signature with a fresh ad-hoc one, generated on your machine. It works in most cases, but if the app contains nested frameworks, re-signing can occasionally break them. Prefer the System Settings method whenever possible.

Alternative: if you'd rather not touch Terminal at all, clone the repository in Xcode and hit **Cmd+R**. Xcode will ad-hoc sign the build automatically.

---

*Thanks for stopping by. Hope this player brings you as much joy as I had building it.* 🎵
