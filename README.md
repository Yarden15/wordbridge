# Wordbridge

**Wordbridge** is a free, open-source macOS menu-bar app
that helps you write and understand English while you work — in any app.

It runs on a **local AI model on your Mac** by default. If you prefer speed over privacy,
you can switch to **Google Gemini** with your own free API key.

> Status: early development. Translate, Improve, word by word and meeting translation work; more is planned.

## What it does

Select text in any app, then:

| Shortcut | Tab | What you get |
|---|---|---|
| `⌘⇧⌥T` | **Translate** | A translation of the selection. Hebrew → English, anything else → Hebrew. |
| `⌘⇧⌥F` | **Improve** | Up to two suggestions for text you wrote: a minimal **correction** and a **more natural** version. Changed words are highlighted and a short explanation (in Hebrew) says what changed and why. Press **Return** to replace your text with the first suggestion, **⌘2** for the second. |

Both open the same floating window, so you can switch between Translate and Improve without
selecting again.

**Word by word** — turn it on in the window and point at any word to see what it means
*in this sentence*, including the idiom or phrasal verb it belongs to
(e.g. `cut` → part of *cut to the chase* = לגשת לעניין). Click a word to keep its meaning shown.

The window can be resized; it remembers the size you choose.

### Meeting translation

`⌘⇧⌥M` (or **Translate Meeting** in the menu) opens a floating window that translates a Zoom or
Google Meet call as it happens: each finished sentence shows up with its Hebrew translation
under it. The text comes from one of two places (switch in the window, or choose a default under
**Meeting Text From**):

- **Captions** — the meeting's own captions, with speaker names.
  - *Google Meet* (Chrome, Edge, Brave, Arc): turn on captions (CC).
  - *Zoom*: open **Captions › View full transcript**. If it's missing, the account owner turns on
    **Meeting transcript** (and "Allow participants to view transcripts") in the Zoom web settings.
    Zoom's caption overlay itself can't be read.
- **Voice** — Wordbridge listens to the sound the meeting app plays (the other people, never your
  microphone) and transcribes it on your Mac. Hebrew speech works too. Works with any app and needs no captions.
  Needs macOS 26 and the **System Audio Recording** permission; English speech recognition is
  downloaded by macOS the first time.

**Automatic** (the default) uses captions when they're on, otherwise voice.

At the top of the window you choose the language people **speak** and the language to
**translate to** (English and Hebrew for now). In Voice mode, the **Me** button also listens to
your microphone, so your own sentences show up too (marked "You"); anything already in the
target language is shown without a translation. With speakers instead of headphones, the
microphone may pick up the other side as well.

### Planned

- **Fix as you type** — spelling and grammar underlines in any text field.
- **Learn while you work** — words you look up are saved for later practice (spaced repetition).
- **Settings window** — meeting source, languages and more in one place.
- More languages (Hebrew ⇄ English first).

## Why

A personal tool I'm building to learn English properly and work faster.
It's open source so anyone who finds it useful can build and use it — free, no strings attached.

## Install

There is no store version or installer. Clone the repo and build it yourself:

```bash
make install   # builds, signs and copies Wordbridge.app to /Applications
make run       # or: build and run from ./build without installing
```

Needs the Xcode Command Line Tools (`xcode-select --install`); full Xcode isn't required.

The build is signed with your "Apple Development" certificate if you have one
(free with any Apple ID: Xcode › Settings › Accounts). Without it the app is ad-hoc
signed and macOS will ask for Accessibility access again after every rebuild.

On first launch, allow Wordbridge in **System Settings › Privacy & Security › Accessibility**
(needed to read the selected text and to paste a suggestion back).

## Choose a model

Pick one in the menu-bar menu under **Choose Model**.

### Local model (default, private)

Wordbridge runs a GGUF model with [llama.cpp](https://github.com/ggml-org/llama.cpp)'s
`llama-server`, only while it's needed. Put the files in either place:

```
~/Library/Application Support/Wordbridge/models/<model>.gguf
/Volumes/<any drive>/Wordbridge/models/<model>.gguf     # an external drive works too
```

`llama-server` is looked for next to the models folder (`<Wordbridge folder>/llama.cpp/…`) and in
Homebrew (`brew install llama.cpp`).

| Model | Download | Memory | Notes |
|---|---|---|---|
| Gemma 4 E4B (Q4_K_M) | ~5 GB | ~5.5 GB | Best quality |
| Gemma 4 E2B (Q4_K_M) | ~3.1 GB | ~3.5 GB | Lighter and faster — good for 16 GB Macs |

Any other GGUF file can be picked with **Choose Model › Other Model File…**.
See [tools/model-bench](tools/model-bench/results.md) for how these were compared.

Loading takes seconds from the internal SSD, but minutes from a slow USB drive. The model stays
loaded between requests and is unloaded after a while (5 min, or 30 min from an external drive).

### Google Gemini (online, optional)

Fast (about a second per request) and uses no memory on your Mac.

1. **Choose Model › Add Gemini API Key…** → **Get a Key…** opens
   [aistudio.google.com/apikey](https://aistudio.google.com/apikey). Creating a key is free.
2. Paste the key and press **Save**. It's stored in your macOS Keychain.

Uses `gemini-3.5-flash` and falls back to `gemini-flash-lite-latest` when Google is busy.
You can set a different model name in the same dialog.

> **Privacy:** on Gemini's free tier, Google may use what you send to improve its products.
> Switch back to a local model for anything private.

## Privacy

- With a local model, nothing leaves your Mac.
- With Gemini, the selected text is sent to Google (see above). In meeting translation, so is
  every sentence of the meeting.
- Meeting audio is transcribed on your Mac and never recorded or saved.
- Wordbridge reads text only when you press a shortcut. It never reads password fields.
- Replacing text uses the clipboard briefly; your previous clipboard contents are restored.

## Requirements

- macOS 15 or later, Apple Silicon recommended
- Accessibility permission
- For meeting voice recognition: macOS 26 or later, System Audio Recording permission, and
  Microphone permission for the **Me** button

## For developers

```bash
B=build/Wordbridge.app/Contents/MacOS/Wordbridge
$B --translate "some text"     # translate and print the result
$B --check "some text"         # writing check; changed words in [brackets]
$B --gloss "some text"         # word-by-word meanings
open build/Wordbridge.app --args --meeting               # open meeting translation
open build/Wordbridge.app --args --listen 30 /tmp/heard.txt [he] [mic]   # transcribe all sound (or the mic) for 30 s
open build/Wordbridge.app --args --ax-dump us.zoom.xos /tmp/tree.txt   # dump an app's accessibility tree
open build/Wordbridge.app --args --improve "some text"   # open the window directly
```

These use the model selected in the menu. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
for how the app is put together.

## License

[MIT](LICENSE)
