# SiliconScope

Shows which installed apps and running processes are Intel-only (Rosetta),
universal, or Apple Silicon, and finds Apple Silicon versions of Intel apps.

## Build

    xcodegen generate     # after editing project.yml (the .xcodeproj is generated)
    xcodebuild -project SiliconScope.xcodeproj -scheme SiliconScope -configuration Debug \
      -derivedDataPath ~/Library/Developer/SiliconScope/DerivedData build

Swift 6 language mode, zero warnings. macOS 14+.

## Layout

- `AppModel` holds the scans, native-version results and the log model for the app's lifetime.
- `Services/NativeVersionChecker` asks, best evidence first: Homebrew's cask index
  (`caveats_rosetta`, arch-specific downloads; cached a day in ~/Library/Caches/SiliconScope),
  the app's Sparkle feed (`sparkle:hardwareRequirements`), the App Store lookup (App Store apps only).
  Casks are matched by app file name *and* bundle ID, since names collide (Cemu vs CEmu).
  CrossOver launchers (`com.codeweavers.CrossOverHelper*`) are Windows programs: never checked.
- Logging: `AppLog.post` → LogKit `LogStore` (~/Library/Logs/SiliconScope), shown on the Log page.
- Updates: Sparkle via `AppUpdater`; key account `siliconscope` in the login Keychain.
- Settings keys live in `Preferences`; Help topics in `Views/HelpView.swift` (update them with every feature).

## Release

`tools/release.sh X.Y.Z` (shared script, settings in `release.conf`); see the mac-release skill.
