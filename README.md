<div align="center">

<img src="docs/icon.png" alt="Pillbox app icon" width="128">

# 💊 Pillbox

**A notch island for macOS: music, timers, clipboard, files and system alerts, one hover away.**

![GitHub last commit](https://img.shields.io/github/last-commit/Arrows78/Pillbox?style=for-the-badge&color=FD8494&logoColor=D9E0EE&logo=github)
![GitHub commit activity](https://img.shields.io/github/commit-activity/m/Arrows78/Pillbox?style=for-the-badge&color=FF6022&logoColor=D9E0EE&logo=git)
![GitHub repo size](https://img.shields.io/github/repo-size/Arrows78/Pillbox?style=for-the-badge&color=FECB02&logoColor=D9E0EE&logo=databricks)
![Github open issues](https://img.shields.io/github/issues/Arrows78/Pillbox?style=for-the-badge&color=D9E0EE&logoColor=D9E0EE&logo=jira)

[![Swift](https://img.shields.io/badge/Swift-F05138?style=for-the-badge&logo=swift&logoColor=D9E0EE)](https://www.swift.org/)
[![macOS](https://img.shields.io/badge/macOS-14%2B-000000?style=for-the-badge&logo=apple&logoColor=D9E0EE)](https://www.apple.com/macos/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-AppKit-0D96F6?style=for-the-badge&logo=swift&logoColor=D9E0EE)](https://developer.apple.com/xcode/swiftui/)
[![CI](https://img.shields.io/github/actions/workflow/status/Arrows78/Pillbox/ci.yml?branch=main&style=for-the-badge&label=CI&logo=githubactions&logoColor=D9E0EE)](https://github.com/Arrows78/Pillbox/actions/workflows/ci.yml)

</div>

**Pillbox** turns the notch of your MacBook into a small control centre. Hover it and it opens into tabs for what is playing, your timers, your clipboard history, a shelf for files and your pinned apps. Collapsed, it shows live activity on both sides and pops short islands for events such as a download finishing or the battery reaching a level. On Macs and monitors without a notch it becomes a virtual pill at the top of the screen.

> [!NOTE]
> Pillbox runs entirely on your Mac: no account, no analytics. The only network calls are the lyrics lookup (LRCLIB) and the optional local developer API, which listens on `127.0.0.1` only.

## ✨ Features

### 🏝️ Island

- **Hover to open**, auto-close when the pointer leaves, adjustable delay. A flick to the top edge counts.
- **Tabs**: Home, Music, Timer, Stocks, AI usage, Pull requests, Reminders, Notifications, Notes, Clipboard, Shelf, Launcher, Terminal. Switch with ⌘1–9 or a two-finger swipe.
- **Live wings** on the collapsed pill: album art and equalizer, running timer, keep-awake countdown, microphone and camera dots, a pinned stock.
- **Activity islands**: short messages in place of the pill, with an optional action button.
- **Any Mac**: virtual pill with an adjustable width when there is no hardware notch.
- **English, French, Spanish and German**, following the macOS language. Dates, weekdays and relative times follow it too. The Spanish and German texts are machine translations that no native speaker has reviewed yet.
- **Several islands in a row**: when events pile up (a download, a build, a notification…) they wait their turn instead of replacing each other, an update of the island on screen (a volume bar) replaces it in place, and the backlog is capped.
- **Themes**: black, graphite, translucent glass or accent for the open panel. The collapsed pill stays black so it melts into the notch.
- **Gestures on the pill**: double and triple clicks run an action you choose (play / pause, keep awake, palette, clipboard, shelf, settings), and a right click opens a menu with **Quit Pillbox**, which also works without a menu bar icon.
- **VoiceOver**: icon-only controls carry labels and the toggles announce their state.

### 🎵 Music

- **Spotify and Apple Music**: title, artist, artwork, seek, previous / play / next.
- **Synced lyrics** from LRCLIB, the current line shown under the title.
- **Floating player**: a small always-on-top player in four sizes (right-click to choose), with a swipe on the cover to skip tracks. **Full-screen lyrics** show the current line big and its neighbours dimmed; Esc or a click closes them. Both are in the palette.
- **Shuffle and repeat** for both players (state read back from the app), and a **favourite** heart for Apple Music.

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
- **Volume and brightness style**: bar in the island, a slim **edge bar** on the right of the screen, or a circle. **Brightness island** for the built-in display (private DisplayServices API: silently absent where unavailable).
- **Live audio spectrum** (opt-in): the pill's equalizer follows real system audio through a Core Audio process tap (macOS 14.4+, asks for audio capture).
- **Focus mode island** and **notification mirror** tab: both read system files and need **Full Disk Access**. Everything stays on the Mac. An opt-in setting also shows each new notification as an island.
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

- **File shelf**: drop files on the notch, or drag a file toward it, or shake it, and the shelf opens. Drag items back out later. Items survive relaunches.
- **Shelf actions**: AirDrop, zip and unzip (native `ditto`, archives expand into a new folder and nothing is overwritten), reveal in Finder.
- **Convert** (offline, system frameworks): images between PNG, JPEG, HEIC, TIFF and PDF, background removal (Vision); video to MP4, HEVC or audio only; audio to AAC, WAV or AIFF.
- **Screenshots**: a new screenshot (wherever macOS saves them) becomes an island and is staged on the shelf, ready to drag into any app.
- **Quick actions and web mini-apps**: in **Settings › Quick actions**, add a shell command (run with a 15 s limit and a result island), a link (web and mail only) or a web mini-app that opens in its own small window. They live in the Launcher's **Actions** view and in the palette.
- **Launcher**: pin apps and reorder by dragging, or switch to **Shortcuts** for a one-tap grid of your Apple Shortcuts (run through the system `shortcuts` command, with a result island).
- **Notes**: a quick checklist that stays in the pill.

### 📈 Stocks and weather

- **Watchlist** with day sparklines and pre-market, open, after-hours and closed states (Yahoo Finance).
- **Price alerts** at ±2 % or ±5 % of the current price, and one symbol pinned to the collapsed pill.
- **Weather** on Home from Open-Meteo, using your location (Celsius or Fahrenheit following your region).

### 🤖 AI tools

- **AI usage**: tokens for the last 5 hours, today and 7 days, for **Claude Code** (`~/.claude/projects`) and **Codex** (`~/.codex/sessions`), read from the local logs. For Codex the limit window the CLI reports (percent used, reset time) is shown too. Nothing leaves the Mac, and cache reads are not counted.
- **Limit alert** (opt-in): a warning island when a reported limit window reaches 70, 80 or 90 %, once per window. It uses the limit Codex reports; Claude Code logs carry no limit, so only its token counts are shown.
- **Pull requests**: your open PRs and the ones waiting for your review, through the GitHub CLI (`gh`) and its existing login. Pillbox stores no token. Click one to open it.
- **Terminal**: a real xterm-compatible login shell in its own tab ([SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)). It keeps running when you switch tabs and restarts if you exit it.
- **Long commands**: **Settings › Developer API › Copy zsh hook** gives an opt-in `preexec` / `precmd` snippet that shows an island when a command ran for 15 seconds or more.
- **Agent approvals**: when Claude Code is about to run a tool, an Allow / Deny island appears and your answer goes back through a `PreToolUse` hook. *Ask in terminal*, or two minutes without an answer, hands the decision back to Claude Code's normal prompt. Enable the local API, then **Settings › Developer API › Copy Claude Code approval hook** and paste the result into `~/.claude/settings.json`.

### 🔔 Alerts and tools

- **Battery**: plugged in, unplugged, charged at a level you choose (80–100 %), low battery.
- **Downloads**: the pill shows the size of a download in progress (partial files and Safari's `.download` folders), then an island with a Reveal button when it lands in Downloads, whatever the browser.
- **Builds**: a stopwatch on the pill while `xcodebuild` or `swift build` runs, and its duration when it ends (no error count).
- **Break reminder** (opt-in): after 20, 30, 45 or 60 minutes of activity, one minute without input counts as a break.
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
- **Panel size**: a slider in Settings scales the open panel from 80 to 130 %.
- **Copy stack** (opt-in): copy several things in a row and paste them back in order with `⌃⌥V` (needs Accessibility to type the paste).
- **Calculation history**: the palette keeps your last ten results and lists them when it is empty; pick one to copy it again.
- **Home**: clock, weather, next calendar event, CPU, memory and battery gauges, live network speed, the battery of your Magic Mouse, Keyboard and Trackpad, and your AirPods and other Bluetooth accessories (per bud and case).
- **Sound output switcher**: the speaker menu in the island header (and the palette) changes the output device in one tap.
- **Display options**: choose which display hosts the island, and hide it in full screen.
- **Hide the notch**: an option that paints the top strip black behind the menu bar, so the notch blends into it.
- **Teleprompter**: `Open teleprompter` in the palette shows a script that scrolls under the webcam, with speed, restart and an editor. The panel is excluded from screen sharing and recordings, so only you see it.

### ⌨️ Command palette

`⌃⌥K` opens it from anywhere. Type `event dinner tomorrow 8pm` to add a calendar event (one hour, default calendar) or `note buy milk` to save an Apple Note. Otherwise: jump to a tab, toggle keep awake, start a timer, pick a colour, switch the sound output, run a Shortcut, search the clipboard and paste, or type a calculation.

Anything else becomes a **web search** with your default engine (Google, DuckDuckGo, Bing, Brave, Ecosia, YouTube, Wikipedia, GitHub or Apple Maps, set in Settings). Start with a bang to pick one: `yt lofi`, `gh swiftterm`, `w notch`. `tr good morning` opens a translation in your language.

### 🔌 For AI apps

- **MCP server**: `Pillbox --mcp` speaks the Model Context Protocol over stdio, so an AI app can start or stop a timer, control the music, add a file to the shelf, show a message in the notch or keep the Mac awake. **Settings › Developer API › Copy MCP configuration** gives the JSON to paste into the app. Every call goes through the local API, so it works only while that switch is on. Arguments are validated (timers 1 to 180 minutes, files must exist) and an unknown tool is refused.
- **Turn summary**: a Claude Code `Stop` hook (**Copy Claude Code turn-summary hook**) shows how many tokens the turn that just ended used, cache reads excluded. The API only reads transcripts under `~/.claude`.

### 🔗 Developer API

Off by default. When enabled in **Settings**, scripts and CI can show a message in the notch:

```bash
curl -X POST http://127.0.0.1:9998/notify \
  -H "Authorization: Bearer <token>" \
  -d '{"title":"Build done","message":"main passed","symbol":"hammer.fill","duration":4}'
```

`POST /approve` takes a Claude Code hook payload and answers with its decision (see AI tools). `POST /action` runs one of the tool calls above and `POST /turn` takes a Claude Code `Stop` hook payload. Requests may arrive in several TCP segments: the API reads up to `Content-Length`. The token is generated per install (**Settings › Developer API › Copy example request**). Titles are limited to 120 characters, messages to 500, durations to 1–10 seconds.

## ⌨️ Default shortcuts

| Shortcut | Action |
| --- | --- |
| `⌃⌥K` | Command palette |
| `⌃⌥N` | Toggle the notch |
| `⌃⌥V` | Paste the next item of the copy stack |
| `⌘1`–`⌘9` | Switch tab while the notch is open |

The palette also takes `yt`, `gh`, `w`, `ddg`, `b`, `br`, `e`, `map` search bangs and `tr` to translate.

## 🛠️ Scripts

| Command | Description |
| --- | --- |
| `./build.sh` | Builds `build/Pillbox.app`, then **installs it into `/Applications`** and relaunches it. `PILLBOX_NO_INSTALL=1` skips the install (CI does too), `PILLBOX_UNIVERSAL=1` builds for Apple Silicon and Intel. |
| `./install.sh` | Builds, installs into `/Applications` and relaunches. `--no-launch` skips the relaunch. |
| `./scripts/ci.sh` | Runs the release tool tests, the release files check, the translations check, the build and the self-test in English and French: the same checks as CI. |
| `python3 scripts/check_l10n.py` | Fails when an English text has no French, Spanish or German translation. |
| `python3 scripts/gen_lproj.py` | Rebuilds the Spanish and German strings from `scripts/data/translations.tsv`, refusing missing keys and changed placeholders. |
| `scripts/make_signing_identity.sh` | Creates a self-signed `Pillbox Local Signing` certificate in your login keychain so rebuilds keep their permissions (asks for your password; not a Developer ID). |
| `build/Pillbox.app/Contents/MacOS/Pillbox --selftest` | Non-interactive checks (parsers, maths, timers, stores, shelf zip, conversions, usage scan, SQLite and Keychain access, island geometry, approvals) against a throwaway data folder. |
| `build/Pillbox.app/Contents/MacOS/Pillbox --render <dir>` | Draws the island, activities, approval, snap zones and some tabs to PNG without a screen. |
| `build/Pillbox.app/Contents/MacOS/Pillbox --usage` | Prints the Claude Code and Codex usage scan and how long it took. |
| `build/Pillbox.app/Contents/MacOS/Pillbox --open-tab <tab>` | Opens the notch on a tab and keeps it open (`home`, `music`, `timer`, `stocks`, `ai`, `reminders`, `notifications`, `notes`, `clipboard`, `shelf`, `launcher`, `terminal`). |
| `swift Resources/make_icon.swift <out.png>` | Renders the 1024 px app icon. |
| `python3 scripts/release.py prepare` | Next version, version bump and changelog from the commit messages ([`docs/RELEASING.md`](docs/RELEASING.md)). |

To publish a release (details in [`docs/RELEASING.md`](docs/RELEASING.md)):

1. `python3 scripts/release.py prepare` picks the next version from the commit messages (Conventional Commits), bumps `Resources/Info.plist` and rewrites `CHANGELOG.md`. Add `--dry-run` to preview it.
2. Commit it (`chore(release): X.Y.Z`) and push the matching tag: the [release workflow](.github/workflows/release.yml) builds a universal app and publishes it as a GitHub release (pre-release for `0.x`), with `docs/releases/<version>.md` as notes when that file exists.

## 🔐 Permissions

Pillbox asks for nothing at launch. **Settings › Permissions** (opened on first launch) shows the state of each one with an **Allow** button that triggers the system prompt, or **Open Settings** once macOS has refused.

| Permission | Used by | Why |
| --- | --- | --- |
| Automation (Spotify, Music) | Music | Read the current track and send transport commands. |
| Calendars | Home | Show the next event. |
| Reminders | Reminders tab | List, add and complete reminders. |
| GitHub CLI login (`gh auth login`) | Pull requests tab | Read your PRs. Nothing is stored by Pillbox. |
| Automation (Notes) | `note` in the palette | Create an Apple Note. |
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

### Download

Grab `Pillbox-<version>.zip` from the [latest release](https://github.com/Arrows78/Pillbox/releases/latest), unzip it and move **Pillbox.app** to `/Applications`. Releases are universal (Apple Silicon and Intel) and need macOS 14 or later.

> [!WARNING]
> Releases are signed ad hoc, not notarised, so macOS blocks the first launch. Open **System Settings › Privacy & Security** and click **Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/Pillbox.app`.

On first launch, **Settings › Permissions** opens: grant what you want to use.

### Build from source

You need macOS 14 or later and [Xcode](https://developer.apple.com/xcode/) with its command-line tools.

```bash
git clone git@github.com:Arrows78/Pillbox.git
cd Pillbox
./build.sh        # builds build/Pillbox.app, installs it into /Applications and launches it
```

A local build always ends with the app in `/Applications`, replacing the previous copy (the running one is quit first, and Caps Lock is restored if the Hyper key was on). Use `PILLBOX_NO_INSTALL=1 ./build.sh` to only build `build/Pillbox.app`.

> [!TIP]
> `build.sh` signs with a local identity named `Pillbox Local Signing` when your keychain has one, and falls back to an ad-hoc signature otherwise. An ad-hoc signature changes on every build, so macOS asks for the permissions again after each rebuild. Run `scripts/make_signing_identity.sh` to create that certificate, or set `PILLBOX_SIGN_IDENTITY` to one you already have, to keep them. For distribution you would need an Apple Developer ID and notarisation, which this project does not do.

> [!NOTE]
> `build.sh` uses SwiftPM's native build system so packages are linked statically: the default one would produce a `Lottie.framework` that is not in the app bundle and the packaged app would crash at launch.

## 📂 Project structure

```text
Pillbox/
├── Package.swift          # Swift Package, one executable target
├── build.sh               # Builds and signs build/Pillbox.app, installs it into /Applications
├── install.sh             # Builds, installs into /Applications, relaunches
├── Resources/             # Info.plist, app icon and its generator, en.lproj and fr.lproj
├── scripts/               # ci.sh, release.py and its tests, l10n tools and table, signing helper, claude-hook.sh
├── docs/                  # Releasing guide, app icon
├── .github/workflows/     # CI and release
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
    ├── Mcp.swift                        # MCP server, agent actions, turn tokens
    ├── Player.swift                     # Floating player, full-screen lyrics, copy stack, calculation history
    ├── Extras4.swift                    # Usage limit alert, GitHub pull requests, edge volume bar
    ├── Extras3.swift                    # Activity queue, themes, pill gestures, quick actions and web mini-apps, notification island
    ├── Features2.swift                  # Shake, break reminder, download and build islands, Bluetooth batteries, quick capture
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

Answering calls from the island, message replies, in-app translation (needs Apple's Translation framework and its language downloads), connecting AirPods from the island, browser video speed, clipboard stack and importing other managers' history, keyboard backlight and external display brightness, per-app sound mixer, knock to control, Cursor and Copilot usage, lock-screen and WidgetKit widgets, automatic updates, notarised releases, native review of the Spanish and German texts. Face Unlock is deliberately left out.

## 🙌 Contributing

Issues and pull requests are welcome.

1. Fork the repository and create a branch.
2. Make your change; extend the self-test in `Sources/Pillbox/SelfTest.swift` for anything testable without a screen, and add French strings for new texts.
3. Run the checks:

   ```bash
   ./scripts/ci.sh
   ```

4. Commit using [Conventional Commits](https://www.conventionalcommits.org/): the type decides the version bump and the changelog entry ([`docs/RELEASING.md`](docs/RELEASING.md)), and CI checks it on pull requests.
5. Push the branch and open a pull request. Keep pull requests focused and describe user-facing behaviour changes.

See the [changelog](CHANGELOG.md) for what changed in each version.
