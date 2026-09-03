# Quetta

Quetta is an open-source, **personal-use** native macOS app (macOS 14+) that follows
meetings using only two audio sources — your selected microphone and the audio playing
on your Mac. **It never records or persists raw audio.** It offers:

- **Simple transcription** — live transcript, saved locally, with an AI-generated
  structured summary on finish.
- **Simultaneous translation** — everything above, plus a low-latency text translation
  shown in a parallel column.

The app lives in the menu bar. Starting a session opens a draggable floating panel at the
bottom-center of the screen, which can be hidden without stopping the session.

## Privacy

- No raw audio is ever written to disk, cache, diagnostics or exports.
- Working buffers are discarded on stop, pause-on-failure, or failed startup.
- Transcribed **text** is only sent to an external AI provider when you enable it in
  Settings and select a provider. The provider name is shown before the first send.
- API keys and OAuth tokens are stored **only** in the macOS Keychain and are masked in
  the UI and logs.
- All network calls use HTTPS with standard certificate validation via `URLSession`.

## Requirements

- macOS 14 or later.
- Xcode 15+ to build.
- An internet connection is required to start or continue a session.

## Building

1. Open `quetta.xcodeproj` in Xcode.
2. Confirm the build settings listed in **Project configuration** below.
3. Build & run. No third-party software (Pi Agent, Codex CLI, ChatGPT app, etc.) is
   required for the app to function.

### Project configuration

The app target needs these settings (Signing & Capabilities / Build Settings):

- **App Sandbox** enabled with entitlements: Audio Input, Outgoing Network Connections,
  Incoming Network Connections (loopback OAuth callback for Codex sign-in), and User
  Selected File (Read/Write). These are in `quetta/quetta.entitlements` — set
  **Code Signing Entitlements** to `quetta/quetta.entitlements`.
- **Info.plist keys**:
  - `NSMicrophoneUsageDescription`
  - `NSSpeechRecognitionUsageDescription`
  - `LSUIElement = YES` (menu-bar agent, no Dock icon)
- **Deployment target**: macOS 14.0.

Screen/System-audio capture (ScreenCaptureKit) and Speech Recognition use runtime TCC
permissions, granted the first time you start a session (or from the Permissions tab).

## AI providers

- **Apple Speech** is the transcription engine (local/system), kept separate from the
  LLM layer.
- **OpenAI (API key)** — used for summary and/or translation. You provide the key; it is
  stored in the Keychain.
- **Codex OAuth (experimental, personal)** — an isolated adapter that performs its **own**
  OAuth (authorization code + PKCE) login in your browser, receives the callback on a
  local loopback listener (`localhost:1455`), and keeps tokens **only** in the macOS
  Keychain, refreshing them itself. It **does not** read or depend on Pi Agent, the Codex
  CLI, or the ChatGPT app, and never extracts credentials from other apps. Text requests
  stream from the ChatGPT subscription backend. If the subscription contract becomes
  incompatible, the adapter is disabled via a single availability flag
  (`CodexOAuthProvider.isAvailable`), reporting **"Unavailable in this version"** — the
  API-key provider remains the stable alternative. Personal use only; you are responsible
  for complying with the terms of your subscription.

## Not in the MVP

Audio recording/playback/export, diarization/speaker identification, text search, tags,
projects, iCloud sync, session sharing, calendar/Zoom/Meet/Teams/Slack integration,
spoken translation, editing of transcript/translation/summary, and non-Markdown export
formats. Gemini and Ollama providers are architecturally supported but not delivered.

## License

Personal use. See repository for details.
