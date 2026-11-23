# Wordbridge — Architecture

## Goals

1. Free for the user. The default needs no account and no API key.
2. Private by default: a local model; online models only if the user opts in.
3. Light on memory and CPU: heavy work happens only when the user actually asks for it.

## What's built and what's planned

| Area | Status | Tech |
|---|---|---|
| Menu-bar app shell | Built | Swift + SwiftUI/AppKit, `LSUIElement`; launch at login via `SMAppService` |
| Global shortcuts | Built | Carbon `RegisterEventHotKey`: `⌘⇧⌥T` translate, `⌘⇧⌥F` improve |
| Reading the selection | Built | Accessibility (`kAXSelectedTextAttribute`), falling back to a simulated `⌘C` with the clipboard restored |
| Replacing the selection | Built | Paste (`⌘V`) into the original app, clipboard restored afterwards |
| Assistant window | Built | Non-activating, resizable `NSPanel` hosting SwiftUI; Translate / Improve tabs; word by word |
| Translation, writing check, word meanings | Built | One LLM, through a local `llama-server` or Google Gemini |
| Fix as you type | Built | Polls the focused text field via Accessibility, checks the sentence on pause, badge overlay |
| My Words / practice | Built | JSON word book, Leitner spaced repetition, daily `UserNotifications` reminder |
| How do I say… | Built | One prompt, two phrasings (spoken / professional) with Hebrew notes |
| Meeting summary | Built | Whole transcript → JSON summary, decisions, action items |
| Meeting translation | Built | Captions via Accessibility (Meet, Zoom transcript), or a Core Audio process tap + `SpeechTranscriber` |
| Settings window | Built | SwiftUI `TabView` + grouped `Form`: General, Model, Meetings |

## Source layout

| File | Responsibility |
|---|---|
| `AppDelegate.swift` | Menu, shortcuts, model menu, Gemini key dialog |
| `AssistantPanel.swift` | `AssistantModel` (state per selection), all SwiftUI views, `AssistantPanelController` (window) |
| `AI.swift` | `AI.complete` / `AI.json` — routes every request to the selected backend; `Translator` |
| `WritingAssistant.swift` | Writing-check prompt and `Suggestion`s; word-by-word `Glossary` |
| `WordTokens.swift` | Splitting text into words, word-level diff for highlighting, `FlowLayout` |
| `LLMEngine.swift` | Local `llama-server` process lifecycle |
| `CloudEngine.swift` | `Backend` choice, `GeminiEngine`, Keychain storage for the key |
| `ModelLocator.swift` | Finding model files and `llama-server` |
| `SelectionReader.swift` | Reading and replacing selected text |
| `Languages.swift` | Languages and direction detection |
| `MeetingTranslator.swift` | `MeetingSession` (lines, when a line is finished, translation queue), meeting window |
| `MeetingCaptions.swift` | Finding the meeting (`MeetingApp`), reading Meet/Zoom captions (`CaptionReader`), `AXTree` helpers |
| `MeetingAudio.swift` | `MeetingListener`: process tap on the meeting app's audio → `SpeechAnalyzer` |
| `SettingsWindow.swift` | `SettingsModel` (reads/writes UserDefaults and the Keychain) and the Settings window |
| `SayIt.swift` | "How do I say…" prompt, its views and standalone panel |
| `WordBook.swift` | My Words store, spaced repetition, daily reminder, practice window |
| `TypingAssistant.swift` | Fix as you type: watching the focused field, checking, the badge |
| `AXDump.swift` | Developer tool: dumps an app's accessibility tree (`--ax-dump`) |

## Backends

All features use one chat-completion call (OpenAI-compatible API on both backends), so
adding a feature means writing a prompt, not engine code.

- **Local (default).** `llama-server` from llama.cpp, started as a child process on a free
  localhost port, with the model on the GPU (`-ngl 99`). Thinking is turned off with
  `chat_template_kwargs.enable_thinking = false`.
- **Google Gemini (opt-in).** The user's own key, kept in the Keychain. Default model
  `gemini-3.5-flash` with `reasoning_effort: "low"` (≈1 s per request). If it's busy (5xx/429),
  slow (12 s timeout) or missing, the request is retried on `gemini-flash-lite-latest`.
  Learned the hard way: `reasoning_effort: "none"` made some models hang, `gemini-flash-latest`
  pointed at an overloaded model, and `max_tokens` counts thinking tokens on Gemini, so it isn't sent.

Structured answers (writing check, word meanings) are requested as JSON in the prompt;
`AI.json` decodes the outermost `{…}`/`[…]` in the reply, since models sometimes add prose or fences.

## Features

**Translate.** Direction from the script: more Hebrew letters → English, otherwise → Hebrew.

**Improve.** Returns `{ok, suggestions: [{text, explanation}]}`: a minimal correction and a more
natural version, with a short Hebrew explanation. Suggestions identical to the input or to each
other are dropped. Changed words are found with a word-level LCS diff against the original.

**Word by word.** The text is split into whitespace-separated tokens and sent numbered; the model
returns, per word, its meaning in context plus the idiom or phrasal verb it belongs to (if any).
Results are cached per text. Hover state lives in its own `WordFocus` object so moving the mouse
doesn't re-render or re-measure the whole window.

**Languages.** `AppLanguage` lists 17 languages (code, prompt name, native name, speech locale,
direction). Two settings drive everything: *my language* and *the language I'm learning*.
`AppLanguage.detect` uses `NLLanguageRecognizer` limited to the supported languages, with hints
towards those two so short text isn't misread; text in your language goes to the learning one,
anything else to yours. Prompts name the languages explicitly. Speech recognition picks
`SpeechTranscriber` when it supports the locale, otherwise `DictationTranscriber` (Hebrew, Arabic,
Dutch, Polish, Russian, Ukrainian, Turkish on macOS 27). Saved words store the language of the word
and of its meaning; older words get them detected once on load.

**Mixed Hebrew/English text.** macOS picks a paragraph's direction from its first letter, so Hebrew
that starts with an English word gets scrambled. Each paragraph is prefixed with an invisible
RLM/LRM mark for its language.

**Meeting translation.** Two sources feed the same `MeetingSession`:

- *Captions*, polled every 0.5 s through Accessibility. Google Meet exposes a "Captions" landmark
  region (one group per speaker turn: name, then one static text per sentence); Chromium builds the
  web tree only after `AXManualAccessibility` is set on the app. Zoom draws its caption overlay as
  an image, but its **Transcript** panel is a table: rows of `[avatar, name]` or `[time, text]`.
  The table is found by its time-stamped rows, not by its (localized) label.
- *Voice*: a Core Audio process tap (`CATapDescription`, macOS 14.2+) on the meeting app's
  processes, found by bundle-ID prefix (Chrome's sound comes from its helper), or on all output
  if none are found. The tap is unmuted and private, read through a private aggregate device,
  converted to the analyzer's format and fed to `SpeechTranscriber` (macOS 26, on-device), whose
  final results are sentence-sized. Only the other side is heard: the tap sees what the app plays,
  not the microphone.
  English uses `SpeechTranscriber`; it has no Hebrew, so Hebrew uses `DictationTranscriber`.
  With **Me** on, a second listener runs on the microphone (`AVAudioEngine` input tap; the
  hardened runtime needs the `com.apple.security.device.audio-input` entitlement).
- Translation always goes into the chosen target language; a line already in that language
  (detected from its script) is shown as is.

Caption lines grow and get corrected while someone speaks. A line counts as finished when a newer
line follows it or it hasn't changed for 1.5 s; only then is it translated (up to three at a time,
with the previous three lines as context). Lines are matched across polls by Zoom's timestamp, or
by speaker and shared prefix for Meet.

**Fix as you type.** A 0.6 s timer reads the focused element (system-wide `AXFocusedUIElement`):
text areas and fields only, never `AXSecureTextField`, and not in terminals, code editors or
password managers. When the value hasn't changed for 1.3 s, the sentence around the caret
(`enumerateSubstrings(.bySentences)`, UTF-16 offsets like Accessibility) is checked if it's English
and at least three words; results are cached per sentence. Only real mistakes (`ok == false`)
show the badge, placed with `AXBoundsForRange` when the app supports it, else at the field's corner.
Clicking selects the sentence (`AXSelectedTextRange`) so **Replace** pastes over exactly it.
Chromium/Electron apps get `AXManualAccessibility` so their fields expose text.

**My Words.** Leitner boxes with 1, 2, 4, 8, 16, 32, 64-day intervals: *Got it* moves a word up a
box, *Hard* waits half the interval, *Again* goes back to box 0 and returns in 10 minutes.

**Word by word everywhere.** `GlossStore` holds meanings per text; the selection panel's model
inherits from it and the meeting window has its own, so both use the same `TextBlock`/`WordInfoBar`.

## Local model lifecycle (the "only when needed" rule)

```
 unloaded ──request──▶ loading ──▶ ready ──no requests for N min──▶ unloaded
                                     ▲                                   │
                                     └──────────── next request ◀────────┘
```

- **Lazy load:** nothing is loaded at app start.
- **Idle unload:** after 5 minutes without requests, or 30 minutes when the model is on an external
  drive (`/Volumes/…`), where loading is slow.
- **Memory pressure:** unload on *critical* pressure only, and never in the middle of a load or a
  request. (Loading a multi-GB model triggers a *warning* by itself; unloading then would cancel
  the load and leave the user waiting forever.)
- **Drive unplugged:** `NSWorkspace.didUnmountNotification` stops the server and shows an error.
- **Crash recovery:** the server's PID is stored; on launch an *orphaned* `llama-server`
  (parent PID 1) is killed. A server owned by another running instance is left alone.
- **Progress:** load time is remembered per model file and shown as a progress bar.

### Models on a slow external drive

Measured from a USB HDD: Gemma 4 E4B ≈ 175 s to load, Gemma 4 E2B ≈ 88 s. macOS doesn't keep the
file cached, so every reload pays this again. On a 16 GB Mac the larger model also pushed other
apps into swap (its GPU memory is wired and can't be swapped), which is why E2B is the suggested
choice there.

## Model choice

Benchmarked in `tools/model-bench` (translation both ways, word in context, grammar):
**Gemma 4 E4B** Q4_K_M (Apache-2.0) has the best Hebrew; **Gemma 4 E2B** is close and much lighter.
Qwen 3.5 (2B/4B) had weak Hebrew; TranslateGemma translated the instructions instead of the text.

## Distribution

Wordbridge is a personal project shared as open source. There is no store listing and no
official installer: anyone who wants it clones the repo and builds it locally (`make install`).

- No paid Apple Developer account and no notarization needed — apps you build yourself run fine.
- The app is signed with a stable identity (a free Apple ID "Apple Development" certificate) when
  available. macOS ties the Accessibility permission to the signature, so an ad-hoc build loses
  the permission on every rebuild.
- Building uses Command Line Tools only (`swift build --build-system native`). Without Xcode, the
  SwiftUI macro plugin is missing, so views use `ObservableObject` instead of `@State`.
