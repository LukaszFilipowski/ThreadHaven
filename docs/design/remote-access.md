# Remote access from a phone

Status: stage 1 implemented (preview)

## Goal

Check on chats, get notified and send the next prompt from a phone, also when the phone is not on the same network as the Mac. The Mac stays the only place where sessions run.

## Stages

1. **Tailscale companion (first).** ThreadHaven serves a small web app (PWA) on the Mac, published to your tailnet with `tailscale serve`. Works on iPhone and Android without app stores.
2. **Self-hostable relay (later).** An open-source relay for teams that do not use Tailscale. Mac and phone both connect out to it, and everything is end-to-end encrypted so the relay only sees ciphertext.
3. **Native apps (later).** iPhone and Android apps on top of the same API, for richer notifications and approvals.

## Stage 1 design

```
phone (tailnet) ──HTTPS──▶ tailscale serve ──HTTP──▶ 127.0.0.1:<port> ThreadHaven
```

- ThreadHaven listens on `127.0.0.1` only, on a random free port, and only while "Remote access" is turned on in Settings.
- `tailscale serve --bg --https=443 http://127.0.0.1:<port>` publishes it inside the tailnet with a valid TLS certificate. It is never exposed to the public internet; `tailscale funnel` is not used and the app refuses to start when it detects a funnel on that port.
- The web app is static HTML, CSS and JavaScript bundled with ThreadHaven. No third-party scripts, no CDN.

### Pairing and authentication

- Turning remote access on creates a random 256-bit device token, stored in the macOS Keychain.
- Settings show a QR code with the tailnet URL and the token in the URL fragment, so it never reaches server logs. The web app moves it to local storage and sends it as a bearer token.
- Each paired device has its own token and appears in Settings with its last use; any device can be revoked. Turning remote access off revokes all of them.
- Tailscale identity headers (`Tailscale-User-Login`) are checked as a second factor when present, and can be limited to an allowlist of tailnet users.

### API

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/sessions` | Running and recent chats with status, title, project and context usage |
| `GET` | `/api/sessions/:id/messages` | Recent user and assistant messages |
| `GET` | `/api/events` | Server-sent events for live status changes |
| `POST` | `/api/sessions/:id/prompt` | Send a prompt to a running chat |
| `GET` | `/api/push/key` | VAPID public key for subscribing |
| `POST` | `/api/push/subscribe` | Register the device for Web Push |

Not in stage 1: approving permission prompts, starting new chats, handoff, any file access. Approvals type keys into a terminal, so they wait until the prompt flow has been proven safe.

### Notifications

Web Push with VAPID keys generated on the Mac. iOS supports it for web apps added to the home screen (iOS 16.4 and later); Android browsers support it directly. Notification bodies contain only the chat title and status unless the user opts into message previews.

### Safety rules

- Requests need a valid token; failures are rate limited and logged locally.
- Prompts are limited in size, sent only to chats whose Claude Code process runs in the foreground of its terminal (same rule as the Mac app), and every remote prompt shows a local notification on the Mac.
- No endpoint runs shell commands or reads arbitrary files. Transcript text is returned as plain text and rendered without HTML in the web app, with a strict Content Security Policy.
- Remote access is off by default and turns itself off after a configurable idle period.

## Decisions in stage 1

- ThreadHaven shows the one-line `tailscale serve` command with a copy button and never runs Tailscale commands that change state. It only reads `tailscale status --json` and `tailscale funnel status --json`.
- Rejected requests are counted in Settings and written to the unified log, which handles retention, instead of a separate log file.
- The listening port is chosen at random once and reused, so the `tailscale serve` command keeps working across restarts.
- Prompts starting with `!` are refused, because Claude Code runs them as shell commands without asking.
