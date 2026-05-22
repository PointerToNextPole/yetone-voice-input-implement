# AGENTS.md

Guidance for coding agents working in this repository.

## Project

VoiceInput is a native macOS 14+ menu-bar app written in Swift/AppKit. It records while the Fn key is held, streams speech recognition, optionally refines the transcript with an OpenAI-compatible API, and injects the final text into the currently focused input field.

The app is intentionally menu-bar only. Keep `LSUIElement` enabled in `Resources/Info.plist`; do not add a Dock icon or primary app window unless the user explicitly asks for that.

## Repository Layout

- `Sources/VoiceInput/main.swift`: App entry point.
- `Sources/VoiceInput/AppDelegate.swift`: App lifecycle, status item menu, permissions, and service wiring.
- `Sources/VoiceInput/AppSettings.swift`: `UserDefaults`-backed settings and language enum.
- `Sources/VoiceInput/FnKeyMonitor.swift`: Global Fn-key `CGEvent` tap.
- `Sources/VoiceInput/SpeechTranscriber.swift`: Apple Speech Recognition streaming and real audio RMS metering.
- `Sources/VoiceInput/FloatingPanelController.swift`: Frameless recording/refining capsule UI.
- `Sources/VoiceInput/TextInjector.swift`: Clipboard paste injection and temporary ASCII input-source switching.
- `Sources/VoiceInput/LLMRefiner.swift`: OpenAI-compatible chat-completions refinement.
- `Sources/VoiceInput/SettingsWindowController.swift`: LLM settings window.
- `Resources/Info.plist`: App bundle metadata, privacy usage strings, and `LSUIElement`.
- `BuildSupport/empty-swift-module.modulemap`: Local CLT workaround used by the Makefile fallback build.
- `docs/superpowers/specs/2026-05-22-voice-input-design.md`: Current design spec.
- `Makefile`: Build, run, install, and clean commands.

## Build And Run

Use the Makefile as the primary interface:

```sh
make build
make run
make install
make clean
```

`make build` first tries `swift build -c release`, then falls back to direct `swiftc` compilation with the VFS overlay in `.build/voiceinput-vfs-overlay.yaml`. Preserve this fallback unless the local Command Line Tools issue is confirmed fixed.

Build output is `build/VoiceInput.app`. The bundle must be ad hoc signed:

```sh
codesign --verify --deep --strict --verbose=2 build/VoiceInput.app
```

Generated directories such as `.build/` and `build/` are ignored and should not be committed.

## Implementation Rules

- Target macOS 14+ and Swift 5.10.
- Prefer AppKit and system frameworks already used by this project.
- Keep the app dependency-light; do not add third-party packages unless they clearly reduce risk.
- Keep the default speech language as Simplified Chinese (`zh-CN`).
- Preserve the language menu options: English, Simplified Chinese, Traditional Chinese, Japanese, Korean.
- Store user-facing settings in `UserDefaults` through `AppSettings`.
- Keep the LLM API OpenAI-compatible and configurable by API Base URL, API Key, and Model.
- The API Key field must remain clearable to an empty string.
- Use conservative LLM correction only. Do not turn refinement into rewriting, translation, summarization, or polishing.

## Fn Key Handling

The Fn key is monitored globally with a `CGEvent` tap in `FnKeyMonitor`.

- Suppress handled Fn events by returning `nil`, so macOS does not open the emoji picker.
- Handle both `keyDown`/`keyUp` and `flagsChanged`, because Fn behavior varies by keyboard and macOS settings.
- Keep event-tap work minimal and dispatch app behavior off the callback path.
- Changes here require manual runtime testing with Input Monitoring and Accessibility permissions granted.

## Speech And Waveform

`SpeechTranscriber` uses `AVAudioEngine` plus `SFSpeechRecognizer` and reports partial transcripts.

- Waveform levels must be driven from real audio RMS values, not fake timers or hardcoded animation loops.
- Preserve the smooth envelope behavior: faster attack than release.
- Preserve the five-bar visual weighting pattern in the floating UI unless the user requests a redesign.
- Speech failures should surface briefly in the floating panel and avoid crashing the app.

## Floating Panel UI

`FloatingPanelController` owns the recording capsule.

- Use a frameless, non-activating `NSPanel`.
- Keep the capsule bottom-centered, 56 px tall, and visually compact.
- Keep the HUD-style material and rounded capsule shape.
- Avoid adding title bars, traffic lights, Dock activation, or a normal document-style window.
- Text should truncate cleanly and the panel width should animate smoothly as text changes.

## Text Injection

`TextInjector` injects text by temporarily writing to the pasteboard and simulating Cmd+V.

- Save and restore the user's pasteboard contents after injection.
- Before paste, detect the current input source and temporarily switch non-ASCII CJK input methods to an ASCII-capable source.
- Restore the previous input source after paste.
- Be conservative with timing changes; paste, input-source switching, and clipboard restoration are sensitive to foreground-app behavior.

## LLM Refinement

`LLMRefiner` calls an OpenAI-compatible `/chat/completions` endpoint.

- If LLM refinement is disabled or configuration is incomplete, inject the raw transcript.
- While waiting for a configured LLM call after Fn release, show `Refining...` in the floating panel.
- On LLM failure, fall back to the raw transcript.
- Keep `temperature` at `0` unless the user explicitly requests more creative behavior.
- Return only the final corrected text from the model; do not expose explanations in the injected output.

## Permissions And Manual Testing

Runtime behavior depends on macOS privacy approvals:

- Microphone
- Speech Recognition
- Accessibility
- Input Monitoring

Manual verification should cover:

- Holding Fn starts recording and showing the capsule.
- Releasing Fn stops recording and injects text into the focused field.
- Fn does not open the emoji picker.
- Simplified Chinese works out of the box.
- All language menu options persist across launches.
- CJK input methods do not intercept Cmd+V paste.
- Clipboard contents are restored after injection.
- LLM settings can be saved, tested, disabled, and cleared.
- LLM refinement shows `Refining...` and falls back safely on API failure.

## Git Hygiene

- Do not commit generated build products from `.build/` or `build/`.
- Do not commit local `.env` files, API keys, certificates, provisioning profiles, or signed release archives.
- Keep changes scoped to the user's request.
- Do not revert user changes unless the user explicitly asks.
- If adding dependencies later, commit `Package.resolved` when it is created so builds remain reproducible.

