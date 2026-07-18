# 🎵 Melodica

> **📌 Quick tip:** If macOS blocks the app on first launch, scroll down to the Download section for two simple Terminal commands to fix it.

No big words or corporate fluff here.  
This is just a solid, good-looking audio player for macOS that I built for myself, because nothing else on the market felt right.

If you've also been looking for a lightweight player that actually handles tags and volume properly — maybe this one will click with you.

---

## ✨ What it can do

- Plays MP3, FLAC, M4A, AAC and other AVAudioEngine formats
- Shows lyrics (synchronized .lrc and embedded ID3)
- ReplayGain so volume doesn't jump between tracks
- Smart library: sort by title, artist, album, genre, year
- Album grid view
- Favorites and playback queue
- Custom colors (background, accent, text and more)
- English & Russian (open settings and select)
- Media keys support: F7, F8, F9
- Equalizer (custom)
- Crossfade between tracks
- Gapless playback
- Skip silence
- M3U playlist support
- Drag & Drop files/folders
- Volume control

---

## 🖼️ Screenshots

![main](https://github.com/Yi0027/Melodica/blob/main/screenshots/main.jpg)
![mini-player](https://github.com/Yi0027/Melodica/blob/main/screenshots/mini-player.jpg)
![customization](https://github.com/Yi0027/Melodica/blob/main/screenshots/customization.jpg)

---

## 🔧 Requirements

- macOS 15.0+ (Sequoia)

---

## 📦 Download

Grab the latest version from [Releases](https://github.com/Yi0027/Melodica/releases/).

**⚠️ Heads up:** Since I didn't pay Apple for a Developer ID (it's expensive and a pain), macOS might block the app on first launch.

Here's how to open it:

1. Move `Melodica.app` to your `Applications` folder.
2. Open **Terminal** and run:

codesign --force --deep --sign - /Applications/Melodica.app

If that doesn't work, try:

sudo xattr -cr /Applications/Melodica.app
