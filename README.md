# ClaudeMeter

A macOS menu bar app that shows your Claude session (5h) and weekly (7d) usage at a glance.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)

## Features

- **Menu bar indicator** with colored progress bars (green / yellow / red) and percentages
- **5-hour session** and **7-day rolling** usage tracking
- **Real-time data** from Claude.ai API (no token cost — uses the same internal endpoint as the Claude web app)
- **Auto-refresh** every 30 seconds
- **Multi-org support** with automatic organization detection
- **Launch at login** option
- Light/dark mode support

## Screenshot

```
5h [████░░] 11%    7d [█░░░░░] 5%     ← menu bar
```

Click to expand:
- Session (5h): **11%** — Resets at 4/16 18:00
- Weekly (7d): **5%** — Resets at 4/23 10:00

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+

## Install

### Option 1: Download (recommended)

1. Download `ClaudeMeter.zip` from the [latest release](https://github.com/seolsnow/ClaudeMeter/releases/latest)
2. Unzip and drag `ClaudeMeter.app` to `/Applications`
3. On first launch, macOS will show a security warning — this is normal for open-source apps without Apple Developer signing ($99/yr). To open:
   - **macOS Sequoia (15+):** System Settings → Privacy & Security → scroll down → click **"Open Anyway"** next to ClaudeMeter
   - **macOS Sonoma (14):** System Settings → Privacy & Security → click **"Open Anyway"**
   - Or: right-click the app → **Open** → click **Open** in the dialog

### Option 2: Homebrew

```bash
brew tap seolsnow/tap
brew install --cask claudemeter
```

### Option 3: Build from source

```bash
git clone https://github.com/seolsnow/ClaudeMeter.git
cd ClaudeMeter
make install
```

## Setup

1. **Launch the app** — a widget appears in your menu bar
2. **Click the widget** → click **"Log in to Claude"**
3. **Sign in** via the browser window that opens
4. Done — your usage appears automatically

The app auto-selects the first organization with active usage. If you have multiple orgs, use the dropdown in the panel to switch.

## How It Works

The widget polls `https://claude.ai/api/organizations/{orgId}/usage` every 30 seconds using your Claude.ai session cookies (obtained via in-app login). This is the same endpoint the Claude web app uses to display your usage bar — **no API tokens are consumed**.

The API returns:
- `five_hour.utilization` — percentage of your 5h session limit used
- `seven_day.utilization` — percentage of your 7d rolling limit used
- Reset timestamps for each window

## Color Coding

| Usage | Color |
|-------|-------|
| < 75% | Green |
| 75% - 90% | Yellow |
| >= 90% | Red |

## Privacy

- All data stays local on your machine
- Cookies are stored in the app's own cookie storage
- No data is sent anywhere except to `claude.ai` (your existing account)
- No analytics or telemetry

## Known Limitations

- **Google Passkey login is not supported.** macOS WKWebView does not support platform passkeys (Touch ID) without a special Apple entitlement reserved for browser apps. When logging in with Google, use password authentication instead of passkey — click "Try another way" on the Google passkey prompt.

## Troubleshooting

**Widget shows 0% 0%**
- Click the widget and check if you're logged in
- Try clicking "Refresh"
- If you have multiple orgs, switch to the one with your active plan

**Login window closes immediately**
- This was fixed — the login opens as a standalone window

**"Log in to Claude" button doesn't appear**
- The app may have cached cookies from a previous session
- Click "Log out" in the panel, then log in again

## Tech Stack

- Swift 6 / SwiftUI
- `MenuBarExtra` with `.window` style
- `WKWebView` for in-app Claude.ai login
- `URLSession` with shared cookie storage
- `XcodeGen` for project generation

## License

MIT
