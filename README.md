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
- English & Russian (open setting and select)
- Media keys support: F7, F8, F9
- Equalizer (custom)
- M3U playlist support
- Drag & Drop files/folders
- Volume control (fixed previous issues)

---

## 🖼️ Screenshots

![1](https://github.com/Yi0027/Melodica/blob/main/screenshots/photo1.jpeg)
![2](https://github.com/Yi0027/Melodica/blob/main/screenshots/photo2.jpeg)
![3](https://github.com/Yi0027/Melodica/blob/main/screenshots/photo3.jpeg)
![4](https://github.com/Yi0027/Melodica/blob/main/screenshots/photo4.jpeg)
![5](https://github.com/Yi0027/Melodica/blob/main/screenshots/photo5.jpeg)


---


## 🔧 Requirements

- macOS 13.0+ (Ventura)
- Recommended: macOS 14.0+ (Sonoma) for best stability

---

## 📦 Download

Grab the latest version from [Releases](https://github.com/Yi0027/Melodica/releases/).

**⚠️ Heads up:** Since I didn't pay Apple for a Developer ID (it's expensive and a pain), macOS might block the app on first launch.

Here's how to open it:

1. Move `Melodica.app` to your `Applications` folder.
2. Open **Terminal** and run:

codesign --force --deep --sign - /Applications/Melodica.app
open /Applications/Melodica.app

If that doesn't work, try:

sudo xattr -cr /Applications/Melodica.app
