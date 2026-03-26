# Agent Notes

- Claude local skills live in `~/.claude/skills/`. Other agents (Codex, Gemini) can reference these skill files directly.
- If `xcodebuild` fails because of a local Xcode/framework/plug-in mismatch, do not fall back to `swift test` or other substitute commands. Stop and tell Marco to run `sudo xcodebuild -runFirstLaunch` and wait for that to succeed before retrying tests or builds.
- For local build verification in this repo, only use `./resources/scripts/build.sh` unless Marco explicitly asks for a different command. Do not run `swift build`, `xcodebuild`, `swiftlint`, or other separate verification commands on your own.
