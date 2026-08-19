# 🎵 Melodica

> **📌 Quick tip:** If macOS blocks the app on first launch, scroll down to the Download section for two simple Terminal commands to fix it.

No big words or corporate fluff here.  
This is just a solid, good-looking audio player for macOS that I built for myself, because nothing else on the market felt right.

If you've also been looking for a lightweight player that actually handles tags and volume properly — maybe this one will click with you.

---

## ✨ What it can do

- Two interface themes: classic and new Liquid Glass (macOS 26+)
- Plays MP3, FLAC, M4A, AAC and other AVAudioEngine formats
- Shows lyrics (synchronized .lrc and embedded ID3)
- ReplayGain so volume doesn't jump between tracks
- Rating support (read from tags)
- Smart library: sort by title, artist, album, genre, year, rating
- Album grid view
- Favorites and playback queue
- Custom colors (background, accent, text and more)
- English & Russian (open settings and select)
- Media keys support: F7, F8, F9
- Equalizer (custom)
- Crossfade between tracks
- Gapless playback
- Silence Skip
- M3U playlist support
- Smart playlists (rules-based)
- CUE sheet support
- Drag & Drop files/folders
- Volume control

---

## 🖼️ Screenshots

*Screenshots use royalty-free music from [Jamendo](https://www.jamendo.com).*

![Right panel](https://github.com/Yi0027/Melodica/blob/main/screenshots/right%20panel.jpg)
![Spectrum](https://github.com/Yi0027/Melodica/blob/main/screenshots/spectrum.jpg)
![MiniPlayer](https://github.com/Yi0027/Melodica/blob/main/screenshots/miniplayer.jpg)

---

## 🔧 Requirements

- macOS 15.0+ (Sequoia) — minimum
- macOS 26.0+ (Tahoe) — recommended: enables the new Liquid Glass design

---

## 📦 Download

Grab the latest version from [Releases](https://github.com/Yi0027/Melodica/releases/).

**⚠️ Heads up:** Since I didn't pay Apple for a Developer ID (it's expensive and a pain), macOS might block the app on first launch.

Here's how to open it:

1. Move `Melodica.app` to your `Applications` folder.
2. Open **Terminal** and run:

```bash
codesign --force --deep --sign - /Applications/Melodica.app
```

 If that doesn't work, try:

```bash
sudo xattr -cr /Applications/Melodica.app
```

