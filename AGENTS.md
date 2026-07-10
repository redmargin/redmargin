# Agent Notes

- Claude local skills live in `~/.claude/skills/`. Other agents (Codex, Gemini) can reference these skill files directly.
- If `xcodebuild` fails because of a local Xcode/framework/plug-in mismatch, do not fall back to `swift test` or other substitute commands. Stop and tell Marco to run `sudo xcodebuild -runFirstLaunch` and wait for that to succeed before retrying tests or builds.
- For local build verification in this repo, only use `./resources/scripts/build.sh` unless Marco explicitly asks for a different command. Do not run `swift build`, `xcodebuild`, `swiftlint`, or other separate verification commands on your own. `build.sh` runs the WebRenderer and Swift suites and fails the build on any test failure; pass `--no-test` to build without them.
- NEVER run XCUITest, `resources/scripts/uitest.sh`, or any UI automation on Spectre. UI automation runs on the Foundry build host only, via `resources/scripts/uitest-foundry.sh`, which syncs the tree, signs with Foundry's Developer ID identity, and drives the suite over SSH. Foundry is provisioned to run it prompt-free.
- The Linux-only test target runs on `devtest` via `resources/scripts/test-linux.sh`, with a timeout guard.
