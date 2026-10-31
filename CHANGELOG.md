# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Hand Off button that continues a chat in a fresh session from a handoff note
- A warning before continuing a large chat whose prompt cache has expired
- Handoff notes that let a long chat continue in a fresh session, written by a cheap model from a compact transcript digest

### Changed

- Auto-compact uses an absolute token threshold (150k by default) instead of a share of the context window

### Fixed

- Universal app build on CI runners
- Hook events from concurrent sessions no longer get lost
- Hook installation works with home folders that contain spaces and keeps unrelated hooks, symlinks and permissions in settings.json
- Dictation no longer brings back text after it was sent or polished
- Running chats are detected for Claude Code installed through npm
- A chat whose terminal tab was reused by a new chat no longer shows as running
- Only approval and question prompts mark a chat as waiting for you
- The attention dot clears on the chat you are looking at
- A first message starting with a dash is no longer read as a command-line option

## [0.1.0] - 2026-10-31

### Added

- Session list with running and recent Claude Code chats, search and context usage
- Live status and notifications through a Claude Code hook
- Switching to a chat's tab in Terminal and iTerm2, with ⌘1–⌘9 shortcuts
- New chat in a folder with `claude --continue` and resuming past chats
- Manual and automatic `/compact`
- Dictation with on-device speech recognition and prompt polishing
- Menu bar extra
- English and Polish localization
