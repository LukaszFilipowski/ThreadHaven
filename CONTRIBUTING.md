# Contributing

Thanks for helping out. A few simple rules keep the project easy to work on.

## Principles

- **Keep it simple.** Small types, plain functions, no dependencies unless they clearly pay off.
- **Read-only by default.** Never modify Claude Code transcripts. The only file ThreadHaven writes outside its own folder is `~/.claude/settings.json`, and only when the user installs or removes the hook.
- **Native first.** SwiftUI and system frameworks.
- **Self-explanatory code.** Clear names instead of comments.

## Workflow

1. Create a branch from `main` named `feature/…`, `fix/…` or `chore/…`.
2. Make small, focused commits with messages in the imperative mood, for example `Add iTerm2 tab focusing`.
3. Update `CHANGELOG.md` and make sure `swift build`, `swift test` and `make app` pass.
4. Open a merge request against `main`.

## Versioning and releases

ThreadHaven follows [Semantic Versioning](https://semver.org). The current version lives in `VERSION` and is written into the app bundle at build time. The build number is the commit count.

Every merge request that changes behavior adds a line to the `[Unreleased]` section of `CHANGELOG.md` under `Added`, `Changed`, `Fixed` or `Removed`.

To cut a release from an up-to-date `main`:

```sh
scripts/release.sh 0.2.0
git push origin main v0.2.0
```

The script runs the tests, moves the `Unreleased` notes into a dated `0.2.0` section, bumps `VERSION`, commits `Release 0.2.0` and creates the annotated tag `v0.2.0`. Pushing the tag triggers the release workflow, which builds `ThreadHaven-0.2.0.zip` and publishes a GitHub release with the changelog notes.

### Signing and notarization

Release builds are signed with a Developer ID and notarized when these repository secrets are set. Without them the workflow publishes an ad-hoc signed build.

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12` | Base64 of the exported Developer ID Application certificate (`base64 -i cert.p12`) |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password of the `.p12` file |
| `DEVELOPER_ID_IDENTITY` | Signing identity, e.g. `Developer ID Application: Name (TEAMID)` |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_TEAM_ID` | Team ID |
| `APPLE_APP_PASSWORD` | App-specific password for that Apple ID |

To sign and notarize locally, store credentials once with `xcrun notarytool store-credentials threadhaven` and run `make notarize SIGN_IDENTITY="Developer ID Application: …"`.

## Translations

User-facing strings are written in English in code. Translations live in `Resources/<language>.lproj/Localizable.strings`. To add a language, copy `pl.lproj`, translate the values and add the language code to `CFBundleLocalizations` in `Resources/Info.plist`.
