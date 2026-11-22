# Wordbridge — Architecture

## Goals

1. Free for the user, forever. No paid API keys.
2. Fully local and private.
3. Light on memory and CPU: heavy work happens only when the user actually needs it.

## Components

| Component | Tech | Notes |
|---|---|---|
| App shell | Swift + SwiftUI, menu-bar app (`LSUIElement`) | Launch at login via `SMAppService` |
| Text field access | Accessibility API (`AXUIElement`, `AXObserver`) | Reads focused field, selection, word bounds. Skips `AXSecureTextField`. |
| Overlay UI | Borderless `NSPanel` windows | Underlines, suggestion popover, word tooltip, translation window |
| Global hotkey | `RegisterEventHotKey` (Carbon) | `⌘⇧⌥T` → translate selection |
| Spell check | `NSSpellChecker` (built into macOS) | Instant, zero extra memory, always on |
| Translation | Apple Translation framework (on-device) | Free, offline, managed by macOS — zero memory when idle. Hebrew ⇄ English supported. |
| Grammar / context | Small local LLM (≈1–4B params, 4-bit quantized) via llama.cpp or MLX | Loaded on demand only |
| Learning data | SQLite (local) | Looked-up words, review schedule |
| Captions (later) | `ScreenCaptureKit` audio + on-device speech-to-text | Works with any meeting app |

## Tiered engine: cheapest tool first

Every request goes to the cheapest engine that can answer it:

1. **Tier 0 — always on, ~0 cost:** `NSSpellChecker` for spelling and basic capitalization.
   Runs on every pause in typing.
2. **Tier 1 — on demand, light:** Apple's on-device translation. Used when the user translates
   or hovers a word.
3. **Tier 2 — on demand, heavier:** LLM for grammar and context-aware meaning.
   Called only when:
   - the user stops typing for ~800 ms **and** the sentence is complete (ends with `.?!` or a newline), or
   - the user explicitly asks (clicks "Improve" / opens a word tooltip that needs context).

## Model lifecycle (the "only when needed" rule)

```
 idle ──request──▶ loading ──▶ ready ──no requests for N min──▶ unloaded
                                 ▲                                   │
                                 └──────────── next request ◀────────┘
```

- **Lazy load:** no model is in memory at app start.
- **Idle unload:** after `N` minutes without requests (default 5, configurable) the model is freed.
- **Memory pressure:** listen to `DispatchSource.makeMemoryPressureSource`; on `.warning` / `.critical`
  unload immediately.
- **Battery:** on low-power mode, use Tier 0 only unless the user explicitly asks.
- **One at a time:** at most one heavy model resident; requests are queued and debounced,
  stale requests (text changed since) are cancelled.
- **Separate process (planned):** run inference in a helper process (XPC). Killing it returns
  all memory to the OS and a crash never takes down the main app.

## Model download

Models are **not** bundled in the installer (keeps the download small and lets users choose).
On first launch an onboarding screen downloads the default models into
`~/Library/Application Support/Wordbridge/Models`, with size shown up front and checksum verification.
Models must have a license that allows free redistribution and use.

Candidates to evaluate (pick by Hebrew quality vs. size at implementation time):

- Translation: Helsinki-NLP Opus-MT `en-he` / `he-en` (Marian, CC-BY 4.0)
- LLM: small multilingual instruction models with good Hebrew, e.g. Qwen (Apache-2.0) or Gemma 3 1B/4B,
  quantized to 4-bit GGUF / MLX.
- Optional: Apple Foundation Models (macOS 26+) when available — zero download, if language support fits.

## Distribution

Wordbridge is a personal project shared as open source. There is no store listing and no
official installer: anyone who wants it clones the repo and builds it locally.

- No paid Apple Developer account and no notarization needed — apps you build yourself run fine.
- The app is signed locally with a stable identity (a free Apple ID "Apple Development"
  certificate, or a self-signed code-signing certificate). This matters: macOS ties the
  Accessibility permission to the signature, and an unsigned/ad-hoc build loses the permission
  on every rebuild.
- A `make install` style script will build the app and copy it to `/Applications`.
