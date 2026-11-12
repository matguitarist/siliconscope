# SiliconScope

A Mac app that shows which of your apps still run through Rosetta — and finds
the Apple Silicon versions you could install instead.

- **Installed Apps**: every app in /Applications and ~/Applications (and any
  folder you add), marked Intel, Universal or Apple Silicon, read straight
  from each program's Mach-O header.
- **Apple Silicon versions**: for every Intel-only app, SiliconScope asks
  Homebrew's cask list, the app's own Sparkle update feed and the App Store
  whether a native version exists, with the download page and the
  `brew install --cask` command.
- **Running Processes**: what macOS is translating with Rosetta right now.
- **Log**: every scan and check, with its source.

CrossOver launchers for Windows programs are recognised and labelled.

macOS 14 or later. Download the latest version from
[Releases](https://github.com/matguitarist/siliconscope/releases/latest);
it updates itself.

## Build

    xcodegen generate
    xcodebuild -project SiliconScope.xcodeproj -scheme SiliconScope build
