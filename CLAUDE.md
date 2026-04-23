# CLAUDE.md

Engineering notes for Claude Code. User-facing docs live in `README.md` — do not duplicate them here.

## What this is

macOS menu bar app (Swift 6 / SwiftUI, `MenuBarExtra` `.window` style). Reads the Claude Code CLI's OAuth token from Keychain (`Claude Code-credentials`) and polls Anthropic's metadata endpoints (`/api/oauth/profile`, `/api/oauth/usage`) every 60s. **No model tokens are consumed.** Deployment target: macOS 14.

## Layout

```
Sources/ClaudeMeter/
  ClaudeMeterApp.swift          # @main, MenuBarExtra wiring; owns the @AppStorage menu-bar visibility flags
  Models/
    UsageSnapshot.swift         # 5h / 7d window values (plain struct)
    Settings.swift              # launch-at-login only (SMAppService wrapper) — NOT a generic prefs bag
  Domain/
    AnthropicOAuthClient.swift  # HTTP + token refresh + Keychain read (259 lines — main complexity)
    UsageStore.swift            # @MainActor @Observable; 60s timer, refresh coalescing, 429 suppression, cold-start warmup, setup-reason state machine
  Views/
    MenuBarLabel.swift          # the tiny gauge in the menu bar
    DetailPanelView.swift       # click-open panel
    ProgressBarView.swift
  Resources/                    # AppIcon.icns + iconset (iconset is excluded from build)
  Info.plist                    # LSUIElement: true
Tests/ClaudeMeterTests/         # placeholder only — no real tests yet
scripts/release.sh              # cuts a release + updates Homebrew tap
project.yml                     # XcodeGen spec (source of truth for build settings)
```

## Build / run

```bash
make build         # xcodebuild Release
make install       # build + copy to /Applications (replaces existing)
make clean
```

After editing `project.yml`, regenerate the Xcode project:

```bash
xcodegen           # reads project.yml → ClaudeMeter.xcodeproj
```

Tests: target exists but only `PlaceholderTests.swift`. Don't claim "tests pass" as verification — there's nothing to run.

## Release flow

```bash
./scripts/release.sh 0.2.6      # version arg required
```

Script: clean build → zip via `ditto` → `gh release create` → clone `seolsnow/homebrew-tap` → rewrite `Casks/claudemeter.rb` with new version + sha256 → push. Pins `user.name`/`user.email` locally in the tap clone so commits are attributed to `seolsnow`, not whatever the global git config says.

**Before running the release script, bump both version fields in `project.yml`, then regenerate the Xcode project:**

`project.yml` has two separate version fields — both must be bumped:

- `MARKETING_VERSION` — user-visible version string shown in README, Homebrew, GitHub release, and the app's About window. Bump semver-style (e.g. `0.2.5` → `0.2.6`).
- `CURRENT_PROJECT_VERSION` — internal build number macOS uses to decide "is this newer?". Just a monotonically increasing integer. Bump by 1 every release (e.g. `7` → `8`), regardless of how `MARKETING_VERSION` changes.

Common mistake: bumping only `MARKETING_VERSION` and forgetting the build number. Installed users' macOS may then treat it as "same build" and the upgrade won't cleanly replace the app.

After editing, run `xcodegen` so `ClaudeMeter.xcodeproj` picks up the new values, then run the release script.

## Commit & release-notes conventions

- Imperative, no trailing period. Examples from history: `Coalesce refreshes, cap profile retries, classify setup failures`, `Log OAuth HTTP outcomes with status, duration, Retry-After`.
- Release commits are titled `Release v<version>: <short summary>` and typically include a dash-bulleted body listing each change.
- Non-release commits describe the change directly — no `feat:`/`fix:` prefixes.
- **Do include the `Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>` trailer** on commits authored with Claude. Nearly every recent commit in this repo has it; follow the existing convention unless told otherwise.

## Signing / distribution gotchas

- Ad-hoc signed (`CODE_SIGN_IDENTITY: "-"`), hardened runtime on. No Apple Developer cert ($99/yr) — so Gatekeeper warnings and occasional Keychain re-prompts are **expected, not bugs**. The README's "macOS Security Warning" and "Known Limitations" sections cover the user-facing story; don't try to "fix" these in code.
- Bundle id: `com.devsisters.claudemeter` (historical — don't rename without discussing; Homebrew cask `zap` paths and existing users' prefs depend on it).

## API behavior worth knowing

- 429 from `/api/oauth/usage` is common and transient. `UsageStore.performRefresh` always suppresses the error banner on 429; the panel surfaces `Refresh delayed · updated Nm ago` only once `lastSuccessAt` crosses the staleness threshold. Don't add another layer of error UI for 429s without reading `UsageStore.swift` first.
- **Profile is fetched at most once per app launch**, and that logic lives in `UsageStore.performRefresh` (guarded by `accountLabel == nil` and capped at `profileMaxAttempts = 3`), *not* in `AnthropicOAuthClient`. `AnthropicOAuthClient.fetchProfile()` has no caching of its own.
- `AnthropicOAuthClient` does hold two separate caches, which are easy to confuse: (a) a process-wide `static let decoder = JSONDecoder()` reused across all decode sites, and (b) an in-memory `cachedCreds` (the OAuth credentials loaded from Keychain), invalidated on 401/403 so the next call re-reads Keychain.
- Token refresh uses `console.anthropic.com/v1/oauth/token` (different host from the data endpoints on `api.anthropic.com`).
- `URLSession` is configured with `timeoutIntervalForRequest = 15s` so a hung request can't overlap the next 60s tick. Don't raise this without also re-thinking the coalescing logic.

## When doing UI work

This is a menu-bar-only app (`LSUIElement: true` — no Dock icon, no main window). Visual changes need the actual app running to verify; `make install` then launch from Spotlight. Xcode previews work for individual views but don't capture the `MenuBarExtra` integration.
