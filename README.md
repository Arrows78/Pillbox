<div align="center">

<img src="docs/icon.png" alt="Pillbox app icon" width="128">

# 💊 Pillbox

**A notch island for macOS: music, timers, clipboard, files and system alerts, one hover away.**

[![Swift](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=D9E0EE)](https://www.swift.org/)
[![macOS](https://img.shields.io/badge/macOS-14%2B-000000?style=for-the-badge&logo=apple&logoColor=D9E0EE)](https://www.apple.com/macos/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-AppKit-0D96F6?style=for-the-badge&logo=swift&logoColor=D9E0EE)](https://developer.apple.com/xcode/swiftui/)

</div>

**Pillbox** turns the notch of your MacBook into a small control centre. Hover it and it opens into tabs for what is playing, your timers, your clipboard history, a shelf for files and your pinned apps. Collapsed, it shows live activity on both sides and pops short islands for events such as a download finishing or the battery reaching a level. On Macs and monitors without a notch it becomes a virtual pill at the top of the screen.

> [!NOTE]
> Pillbox runs entirely on your Mac: no account, no analytics. The only network calls are the lyrics lookup (LRCLIB) and the optional local developer API, which listens on `127.0.0.1` only.

## ✨ Features

### 🏝️ Island

- **Hover to open**, auto-close when the pointer leaves, adjustable delay. A flick to the top edge counts.
- **Tabs**: Home, Music, Timer, Stocks, AI usage, Reminders, Notifications, Notes, Clipboard, Shelf, Launcher, Terminal. Switch with ⌘1–9 or a two-finger swipe.
- **Live wings** on the collapsed pill: album art and equalizer, running timer, keep-awake countdown, microphone and camera dots, a pinned stock.
- **Activity islands**: short messages in place of the pill, with an optional action button.
- **Any Mac**: virtual pill with an adjustable width when there is no hardware notch.
- **English and French**, following the macOS language. Dates, weekdays and relative times follow it too.

### 🎵 Music

- **Spotify and Apple Music**: title, artist, artwork, seek, previous / play / next.
- **Synced lyrics** from LRCLIB, the current line shown under the title.

### ⏱️ Timer

- **Focus, break, countdown and stopwatch**, all wall-clock based so they never drift.
- **Chaining** focus into break, named timers, repeat, daily streak and a 7-day chart.

### 📋 Clipboard

- **History** with pins, search and a cap that never drops pinned items.
- **Smart cards** for links, hex colours and emails, with character and word counts for long text.
- **OCR** (Vision) of copied images, so search finds words inside screenshots.
- **Double-click to paste** into the front app. Concealed items from password managers are skipped.
- **Snippets**: reusable text, pasted from the Snippets view or by name from the command palette.

### 🧩 More from the island

- **Mini player on hover** (opt-in): hovering the pill during playback opens the Music tab.
- **Double-press Control** (opt-in) opens the notch on any Mac.
- **Snap zones** (opt-in): drag a window to the notch and four zones appear (left half, right half, full screen, centre); release over one to snap. A real file drag is told apart from a window drag through the drag pasteboard's change count.
- **Volume and brightness style**: bar or circle. **Brightness island** for the built-in display (private DisplayServices API: silently absent where unavailable).
- **Live audio spectrum** (opt-in): the pill's equalizer follows real system audio through a Core Audio process tap (macOS 14.4+, asks for audio capture).
- **Focus mode island** and **notification mirror** tab: both read system files and need **Full Disk Access**. Everything stays on the Mac.
- **Call island**: while Zoom, Teams, FaceTime, WhatsApp, Slack, Discord or Skype is open and the microphone is live, the pill shows the call and its duration.
- **Timer mascots**: pick an emoji companion for the timer (the plant grows as the session goes on).
- **Idle animation**: choose your own Lottie JSON for the pill (Settings › Island).
- **Hyper key** (opt-in): Caps Lock becomes ⌃⌥⇧⌘, and a quick press sends Escape. It remaps Caps Lock to F18 with `hidutil` and an event tap adds the modifiers; the remap is undone when Pillbox quits and never survives a reboot.
- **Menu bar**: hide icons behind a divider (⌘-drag them to its left), show the next calendar event with a countdown, and pop Timer, Stocks, AI usage, Reminders, Notes or Clipboard out as their own menu bar icons with a popover.
- **Desktop widgets** (opt-in): clock, world clocks, weather and now playing, draggable, sitting under your windows.
- **Window watch**: watch a part of the screen (a percentage, a build status, a price) and get an island when its text changes. Needs Screen Recording.
- **Ask about screen**: pick an area, read its text on device (Vision), then copy it, search it, translate it, open its links, or ask a question with your own Anthropic API key stored in the Keychain. Only the recognised text is sent, never the picture.

### ✅ Reminders

- **Apple Reminders** tab: open reminders sorted by due date (overdue in red), tick to complete, and add one from a single line: `call mum tomorrow at 9am` becomes the title *call mum* with a due date and an alert. It syncs through iCloud like the Reminders app.

### 🗂️ Shelf and apps

- **File shelf**: drop files on the notch, or drag a file toward it and it opens. Drag items back out later. Items survive relaunches.
- **Shelf actions**: AirDrop, zip and unzip (native `ditto`, archives expand into a new folder and nothing is overwritten), reveal in Finder.
- **Convert** (offline, system frameworks): images between PNG, JPEG, HEIC, TIFF and PDF, background removal (Vision); video to MP4, HEVC or audio only; audio to AAC, WAV or AIFF.
- **Screenshots**: a new screenshot (wherever macOS saves them) becomes an island and is staged on the shelf, ready to drag into any app.
- **Launcher**: pin apps and reorder by dragging, or switch to **Shortcuts** for a one-tap grid of your Apple Shortcuts (run through the system `shortcuts` command, with a result island).
- **Notes**: a quick checklist that stays in the pill.

### 📈 Stocks and weather

- **Watchlist** with day sparklines and pre-market, open, after-hours and closed states (Yahoo Finance).
- **Price alerts** at ±2 % or ±5 % of the current price, and one symbol pinned to the collapsed pill.
- **Weather** on Home from Open-Meteo, using your location (Celsius or Fahrenheit following your region).

### 🤖 AI tools

- **AI usage**: tokens for the last 5 hours, today and 7 days, for **Claude Code** (`~/.claude/projects`) and **Codex** (`~/.codex/sessions`), read from the local logs. For Codex the limit window the CLI reports (percent used, reset time) is shown too. Nothing leaves the Mac, and cache reads are not counted.
- **Terminal**: a real xterm-compatible login shell in its own tab ([SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)). It keeps running when you switch tabs and restarts if you exit it.
- **Long commands**: **Settings › Developer API › Copy zsh hook** gives an opt-in `preexec` / `precmd` snippet that shows an island when a command ran for 15 seconds or more.
- **Agent approvals**: when Claude Code is about to run a tool, an Allow / Deny island appears and your answer goes back through a `PreToolUse` hook. *Ask in terminal*, or two minutes without an answer, hands the decision back to Claude Code's normal prompt. Enable the local API, then **Settings › Developer API › Copy Claude Code approval hook** and paste the result into `~/.claude/settings.json`.

### 🔔 Alerts and tools

- **Battery**: plugged in, unplugged, charged at a level you choose (80–100 %), low battery.
- **Downloads**: an island with a Reveal button when a file lands in Downloads, whatever the browser.
- **Privacy indicator**: dots on the pill while any app uses the microphone or the camera.
- **Volume** island with a level bar, **Caps Lock** island.
- **Keystrokes** (off by default): shows the shortcuts you press, or everything you type if you turn *Shortcuts only* off. Never shown while macOS secure input is on (password fields), never stored.
- **Mic mute**: one switch mutes the input device itself, so every call app goes silent.
- **Camera mirror**: a local preview under the notch. Nothing is recorded.
- **Cleaning**: lock the keyboard for 60 s (⌘⎋ unlocks) or black out the displays.
- **Window snapping**: halves, thirds, centre and full screen from the command palette.
- **Keep awake**: indefinite, 30 min, 1 h, 2 h or until 6 pm (right-click the Awake button on Home).
- **Drives**: an island with a one-tap **Eject** when a removable drive is plugged in, then *Safe to disconnect*.
- **Hide from capture**: asks screenshot and screen-sharing tools to leave the island out (some apps may still capture it).
- **Colour eyedropper** (HEX copied), **area screenshot** to the clipboard.
- **Home**: clock, weather, next calendar event, CPU, memory and battery gauges, live network speed, and the battery of your Magic Mouse, Keyboard and Trackpad.
- **Sound output switcher**: the speaker menu in the island header (and the palette) changes the output device in one tap.
- **Hide the notch**: an option that paints the top strip black behind the menu bar, so the notch blends into it.
- **Teleprompter**: `Open teleprompter` in the palette shows a script that scrolls under the webcam, with speed, restart and an editor. The panel is excluded from screen sharing and recordings, so only you see it.

### ⌨️ Command palette

`⌃⌥K` opens it from anywhere: jump to a tab, toggle keep awake, start a timer, pick a colour, switch the sound output, run a Shortcut, search the clipboard and paste, or type a calculation.

Anything else becomes a **web search** with your default engine (Google, DuckDuckGo, Bing, Brave, Ecosia, YouTube, Wikipedia, GitHub or Apple Maps, set in Settings). Start with a bang to pick one: `yt lofi`, `gh swiftterm`, `w notch`. `tr good morning` opens a translation in your language.

### 🔗 Developer API

Off by default. When enabled in **Settings**, scripts and CI can show a message in the notch:

```bash
curl -X POST http://127.0.0.1:9998/notify \
  -H "Authorization: Bearer <token>" \
  -d '{"title":"Build done","message":"main passed","symbol":"hammer.fill","duration":4}'
```

`POST /approve` takes a Claude Code hook payload and answers with its decision (see AI tools). The token is generated per install (**Settings › Developer API › Copy example request**). Titles are limited to 120 characters, messages to 500, durations to 1–10 seconds.

## ⌨️ Default shortcuts

| Shortcut | Action |
| --- | --- |
| `⌃⌥K` | Command palette |
| `⌃⌥N` | Toggle the notch |
| `⌘1`–`⌘9` | Switch tab while the notch is open |

The palette also takes `yt`, `gh`, `w`, `ddg`, `b`, `br`, `e`, `map` search bangs and `tr` to translate.

## 🛠️ Scripts

| Command | Description |
| --- | --- |
| `./build.sh` | Builds `build/Pillbox.app`. |
| `./scripts/ci.sh` | Checks translations, builds, then runs the self-test in English and French: the same checks as CI. |
| `python3 scripts/check_l10n.py` | Fails when an English text has no French translation. |
| `build/Pillbox.app/Contents/MacOS/Pillbox --selftest` | Non-interactive checks (parsers, maths, timers, stores, shelf zip, usage scan, island geometry, approvals) against a throwaway data folder. |
| `build/Pillbox.app/Contents/MacOS/Pillbox --usage` | Prints the Claude Code and Codex usage scan and how long it took. |
| `build/Pillbox.app/Contents/MacOS/Pillbox --open-tab <tab>` | Opens the notch on a tab and keeps it open (`home`, `music`, `timer`, `stocks`, `ai`, `notes`, `clipboard`, `shelf`, `launcher`, `terminal`). |
| `build/Pillbox.app/Contents/MacOS/Pillbox --render <dir>` | Draws the island, activities, approval and some tabs to PNG without a screen. |
| `swift Resources/make_icon.swift <out.png>` | Renders the 1024 px app icon. |

## 🔐 Permissions

Pillbox asks for nothing at launch. **Settings › Permissions** (opened on first launch) shows the state of each one with an **Allow** button that triggers the system prompt, or **Open Settings** once macOS has refused.

| Permission | Used by | Why |
| --- | --- | --- |
| Automation (Spotify, Music) | Music | Read the current track and send transport commands. |
| Calendars | Home | Show the next event. |
| Reminders | Reminders tab | List, add and complete reminders. |
| Location | Home | Local weather. |
| Camera | Camera mirror | Show the preview. |
| Input Monitoring | Keystroke display, double-press Control | Observe key presses system-wide. |
| Screen Recording | Window watch, Ask about screen | Read the pixels of an area you pick. |
| Full Disk Access | Notification mirror, Focus island | Read Notification Center and Do Not Disturb files. |
| Accessibility | Hyper key, keyboard lock, window snapping, clipboard paste | Block keys, move windows, send ⌘V. |
| Downloads and Desktop folders | Download and screenshot alerts | Notice new files. |

## 🧱 Technology stack

| Area | Technologies |
| --- | --- |
| Language | Swift (Swift Package, no Xcode project) |
| Dependencies | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT) for the terminal tab, [lottie-ios](https://github.com/airbnb/lottie-ios) (Apache 2.0) for the idle animation |
| User interface | SwiftUI (island, tabs, settings), AppKit (borderless panel, hover and drag monitors) |
| Media | AppleScript for Spotify and Music, LRCLIB for lyrics, AVFoundation (camera mirror) |
| Web data | Open-Meteo (weather), Yahoo Finance (quotes) |
| System | IOKit (battery, keep awake), Mach (CPU and memory), CoreAudio and CoreMediaIO (volume, mic, camera), EventKit, CoreLocation, Network.framework, Accessibility |
| Recognition | Vision (clipboard OCR) |
| Persistence | JSON files in Application Support, `UserDefaults` for settings |

## 📦 Installation

### Build from source

You need macOS 14 or later and [Xcode](https://developer.apple.com/xcode/) with its command-line tools.

```bash
git clone <repository-url>
cd Pillbox
./build.sh        # -> build/Pillbox.app
open build/Pillbox.app
```

> [!TIP]
> `build.sh` uses SwiftPM's native build system so packages are linked statically (the default one would produce a `Lottie.framework` that is not in the app bundle). `build.sh` signs ad hoc by default, so macOS asks for the permissions again after each rebuild. Set `PILLBOX_SIGN_IDENTITY` to a self-signed code-signing certificate to keep them.

## 📂 Project structure

```text
Pillbox/
├── Package.swift          # Swift Package, one executable target
├── build.sh               # Builds and signs build/Pillbox.app
├── Resources/             # Info.plist, app icon and its generator, en.lproj and fr.lproj
├── scripts/               # ci.sh, check_l10n.py, claude-hook.sh (Claude Code approval hook)
├── .github/workflows/     # CI
└── Sources/Pillbox/
    ├── main.swift, AppDelegate.swift    # Entry point, menu bar, hover and drag monitors
    ├── NotchModel, NotchPanel           # State, geometry, click-through panel
    ├── NotchView, Tabs                  # Island, wings, activities, tab views
    ├── Music, Timers, Clipboard, Shelf  # Feature services
    ├── System.swift                     # Keep awake, battery, stats, downloads, tools, calendar
    ├── Stores.swift                     # Notes and launcher
    ├── Audio, Mirror, Cleaning, WindowSnap  # Volume, mic, privacy, camera, locks, snapping
    ├── Weather, Stocks, AIUsage         # Weather, watchlist, Claude Code and Codex usage
    ├── Terminal, Keystrokes             # Shell tab, keystroke display
    ├── Shortcuts, WebSearch, Devices    # Apple Shortcuts, palette search, accessory battery and network speed
    ├── Overlays.swift                   # Hidden notch, teleprompter
    ├── Hyper, MenuBar, SystemWatch      # Hyper key, menu bar items, brightness, Focus, notifications, calls
    ├── Screen, Spectrum, Gestures       # Region picker, window watch, Ask about screen, audio spectrum, snap zones, Lottie, widgets
    ├── Permissions.swift                # Permissions center
    ├── L10n.swift                       # L() helper for text built in code
    ├── SelfTest.swift                   # Behind --selftest
    ├── Palette, Settings, DevAPI        # Command palette, hotkeys, settings, local API
```

## 💾 Local data

| What | Where |
| --- | --- |
| Settings | `UserDefaults` (bundle identifier `dev.labs.pillbox`) |
| Clipboard, shelf, notes, launcher, sessions, watchlist | `~/Library/Application Support/Pillbox` |

## 🗺️ Roadmap

Answering calls from the island, message replies, keyboard backlight and external display brightness, per-app sound mixer, knock to control, Cursor and Copilot usage, lock-screen and WidgetKit widgets, automatic updates, more languages. Face Unlock is deliberately left out.

## 🙌 Contributing

Issues and pull requests are welcome. Run `./scripts/ci.sh` first, and extend `Sources/Pillbox/SelfTest.swift` for anything testable without a screen. Commit with [Conventional Commits](https://www.conventionalcommits.org/) and keep pull requests focused.
