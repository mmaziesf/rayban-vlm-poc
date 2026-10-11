# iOS companion (M7, optional)

| Path | Status |
|---|---|
| `GlanceCore/` | Pure-Swift port of `core/` (intents, ring buffer, frame source, controller, meal parsing). **Builds and passes 10/10 XCTests on the Linux bot box** (Swift 6.4). |
| `GlanceApp/` | SwiftUI app + DAT adapters + debug MockRig + XCUITests + XcodeGen spec. **Structural only — never compiled** (DAT = iOS-only binary xcframeworks; Xcode/Simulator need macOS). Written against DAT 1.0.1 `.swiftinterface` signatures. |
| `../.github/workflows/ios.yml` | macOS CI (simulator build + UI tests). **Not run.** |

## Run what runs here (Linux box)
    ios/GlanceCore/run-tests.sh          # wraps: swift test --build-system native (6.4 default build system can't find swiftc in the tarball layout)

## On a Mac (first time)
    brew install xcodegen && cd ios/GlanceApp && xcodegen && open GlanceApp.xcodeproj
    # Debug trigger (mirror of Android ADB broadcast):
    xcrun simctl openurl booted 'glance-debug://command?text=what%20am%20I%20seeing'
    xcrun simctl openurl booted 'glance-debug://command?text=log%20this%20meal&viaMockSpeech=true'

Mock assets in `GlanceApp/Resources/` are copies of the Android debug assets (H.265 hvc1 504x896 clip + meal JPEG).
See `docs/IOS_OPTIONS.md` for options, blockers, and the DAT Android↔iOS API map.
