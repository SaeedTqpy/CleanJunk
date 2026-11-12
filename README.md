# CleanJunk

Native macOS 26+ developer storage intelligence and carefully controlled cleanup.

## Principles
- **Inspect first:** every scan is read-only, with an explicit review before any change.
- **Never infer package safety from age:** Homebrew dependency inspection uses the package manager's own data; package removal is not performed by the app.
- **Conservative filesystem operations:** trash only individually reviewed, policy-approved artifacts; no permanent deletion, no root privileges, no blanket `rm -rf`.
- **Apple-native interface:** SwiftUI + AppKit and system Liquid Glass APIs on macOS 26.
- **Local-first:** no telemetry or network service required.

Implementation, build steps and security details are maintained in this repository.
