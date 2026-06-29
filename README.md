# 🎵 Melodica

> **📌 Quick tip:** If macOS blocks the app on first launch, scroll down to the [Download] section for two simple Terminal commands to fix it.

No big words or corporate fluff here.  
This is just a solid, good-looking audio player for macOS that I built for myself, because nothing else on the market felt right.

If you've also been looking for a lightweight player that actually handles tags and volume properly — maybe this one will click with you.

---

## ✨ What it can do
To start the song 2 times, click on its title
- Plays MP3, FLAC, M4A, AAC, OPUS, OGG — no issues
- Shows lyrics (synchronized .lrc and embedded ID3)
- ReplayGain so volume doesn't jump between tracks
- Smart library: sort by title, artist, album, genre, year
- Album grid view
- Favorites and playback queue
- Custom colors (background, accent, text)
- English & Russian (open setting and select)
- Media keys support: ⌘F7, F8, F9

---

## 🖼️ Screenshots

![1](<img width="1710" height="1073" alt="Снимок экрана — 2026-06-29 в 17 04 29" src="https://github.com/user-attachments/assets/1a45f79b-6486-4308-8526-5955e973738c" />)
![2](<img width="1710" height="1073" alt="Снимок экрана — 2026-06-29 в 17 08 37" src="https://github.com/user-attachments/assets/d7379d61-5d31-4ee0-8bb4-7758e9160964" />)
![3](<img width="1710" height="1073" alt="Снимок экрана — 2026-06-29 в 17 10 10" src="https://github.com/user-attachments/assets/b86329cb-3974-466e-a81d-246663577929" />)
![4](<img width="1710" height="1073" alt="Снимок экрана — 2026-06-29 в 17 16 08" src="https://github.com/user-attachments/assets/514c7c64-8263-480b-b2e3-2e4ca34f1cdd" />)
![5](<img width="1710" height="1112" alt="Снимок экрана — 2026-06-29 в 17 17 08" src="https://github.com/user-attachments/assets/6189f717-a98f-4748-8b73-b79608004598" />)


---


## 🔧 Requirements

- macOS 13.0+ (Ventura)
- Recommended: macOS 14.0+ (Sonoma) for best stability

---

## 📦 Download

Grab the latest version from [Releases].

**⚠️ Heads up:** Since I didn't pay Apple for a Developer ID (it's expensive and a pain), macOS might block the app on first launch.

Here's how to open it:

1. Move `Melodica.app` to your `Applications` folder.
2. Open **Terminal** and run:

codesign --force --deep --sign - /Applications/Melodica.app
open /Applications/Melodica.app

If that doesn't work, try:

sudo xattr -cr /Applications/Melodica.app
