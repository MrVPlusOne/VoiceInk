# VoiceInk

macOS app built with Swift/Xcode. Uses whisper.cpp for offline speech-to-text.

## Building

Always use `make local` (not `make build`) to build the app.

- `make build` produces an unsigned binary that **crashes on launch** because the app requires entitlements (accessibility, microphone, etc.) that only work with code signing.
- `make local` uses ad-hoc signing with local entitlements and produces a working app at `~/Downloads/VoiceInk.app`.

To install: copy `~/Downloads/VoiceInk.app` to `/Applications/VoiceInk.app`.

Local builds have these limitations vs signed releases:
- No iCloud dictionary sync
- No automatic updates (pull new code and rebuild to update)

## Testing

For routine pure logic assertions that should not launch the app test host, run:

```bash
swift test
```

This exercises the non-hosted `VoiceInkLogicTests` package target. Keep `xcodebuild ... build-for-testing` for hosted app test compilation, and avoid `xcodebuild test` on the hosted `VoiceInkTests` target during routine agent verification because it launches `VoiceInk.app` as the test host.
