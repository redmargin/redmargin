---
description: Build and compile Redmargin. MANDATORY for any build operation. Never use swift build or xcodebuild directly.
---

# Build Redmargin

**CRITICAL: Never run `swift build` or `xcodebuild` directly.**

Always use the build script:

```bash
resources/scripts/build.sh
```

The script:
1. Quits Redmargin if running
2. Compiles with `swift build -c release`
3. Bundles WebRenderer assets (JS, CSS, HTML)
4. Bundles app icon
5. Code signs with entitlements
6. Installs to /Applications

Raw xcodebuild will NOT bundle WebRenderer assets correctly.

Do not launch the app after building - Marco will do that.
