# #iWasThere

Sports match attendance diary (직관 로그) for iOS.

## Requirements

- macOS with **Xcode 16+** (full Xcode app, not only Command Line Tools)
- iOS **17+** Simulator or device

First-time Xcode setup (if needed):

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
```

## Get the app

```bash
git clone https://github.com/suhholee/i_was_there.git
cd i_was_there
git checkout develop
```

If `IWasThere.xcodeproj` is missing:

```bash
brew install xcodegen   # once
xcodegen generate
```

Open and run:

```bash
open IWasThere.xcodeproj
```

In Xcode: select an **iPhone simulator** → press **⌘R**.

## Optional: verify MLB API

```bash
python3 Scripts/smoke_mlb_api.py
```
