# macOS Menu-Bar Voice Input Design

## Scope

Build a native macOS 14+ menu-bar app in Swift using Swift Package Manager. The app records while the Fn key is held, streams speech recognition results, optionally refines the transcript through an OpenAI-compatible API, and injects the final text into the focused input field.

## Architecture

- `AppDelegate` owns app startup, status item menu, permission prompts, and service wiring.
- `FnKeyMonitor` installs a global CGEvent tap, detects Fn key down/up, and suppresses Fn events so the emoji picker is not triggered.
- `SpeechTranscriber` uses Apple Speech Recognition with `AVAudioEngine`, defaulting to `zh-CN`, and publishes partial text plus real-time RMS levels from microphone buffers.
- `FloatingPanelController` displays a frameless non-activating `NSPanel` centered near the bottom of the active screen. It contains a HUD material capsule, five RMS-driven waveform bars, and an elastic transcript/status label.
- `TextInjector` saves and restores the clipboard, temporarily switches CJK input methods to an ASCII-capable source, simulates Cmd+V, then restores the original input source.
- `LLMRefiner` calls an OpenAI-compatible chat completions endpoint using a conservative correction-only prompt.
- `SettingsWindowController` exposes API Base URL, API Key, and Model fields with Test and Save buttons. The API Key can be saved as an empty value.

## User Flow

1. User holds Fn.
2. App starts audio capture, streaming recognition, RMS metering, and floating capsule entry animation.
3. User releases Fn.
4. App stops recognition and chooses the best final transcript.
5. If LLM refinement is enabled and configured, the capsule shows `Refining...` until the API returns.
6. App injects final text through clipboard paste and restores clipboard and input source state.
7. Capsule exits with a short scale animation.

## Language And Settings

The default speech locale is Simplified Chinese (`zh-CN`). The language menu supports English (`en-US`), Simplified Chinese (`zh-CN`), Traditional Chinese (`zh-TW`), Japanese (`ja-JP`), and Korean (`ko-KR`). Selection is persisted in `UserDefaults`.

LLM refinement is also persisted in `UserDefaults`. If refinement is enabled but any required setting is missing, the app injects raw transcription instead of blocking.

## Packaging

The Makefile builds the SwiftPM release executable, creates `build/VoiceInput.app`, writes the expected bundle structure, copies `Info.plist`, and signs the app ad hoc. The bundle is LSUIElement-only, so it appears in the menu bar without a Dock icon.

## Error Handling

Permission problems are surfaced through menu actions and system prompts where possible. Speech recognition or LLM failures fall back to the best available raw transcript. Clipboard and input source restoration use deferred cleanup so the user's environment is restored after paste attempts.

## Testing

Verification focuses on successful SwiftPM build, generated `.app` bundle, ad hoc signature, and basic service-level compile coverage. Manual runtime testing is still required for microphone, speech recognition, accessibility/input monitoring permissions, Fn suppression, and focused-field text injection because those behaviors depend on macOS privacy approvals and foreground applications.
