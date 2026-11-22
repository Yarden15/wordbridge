# Wordbridge

**Wordbridge** is a free, open-source macOS menu-bar app
that helps you write and understand English while you work — in any app.

Everything runs **on your Mac**. No account, no subscription, no text sent to a server.

> Status: early development. Not ready for use yet.

## Features (planned)

- **Fix as you type** — spelling, capitalization and grammar suggestions in any text field
  (e.g. `please fix that santence` → `Please fix this sentence.`).
- **Translate selection** — select text anywhere and press `⌘⇧⌥T` to open a translation window.
- **Word tooltips** — select a word you don't know and see its meaning *in the context of the sentence*.
- **Learn while you work** — words you look up are saved for later practice (spaced repetition).
- **Live captions translation** (later) — translate Zoom / Google Meet captions in real time.

Languages: Hebrew ⇄ English first. More languages later.

## Why

A personal tool I'm building to learn English properly and work faster.
It's open source so anyone who finds it useful can build and use it — free, no strings attached.

## Install

There is no store version or installer. Clone the repo and build it yourself
(build instructions will be added once the app is runnable).

## Requirements

- macOS 14 or later, Apple Silicon recommended
- Accessibility permission (to read and suggest fixes in text fields)

## Privacy

- All processing is local, using small open models downloaded on first launch.
- Password fields are never read.
- You can exclude any app from Wordbridge.

## How it stays light

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). In short: the AI model is loaded
**only when needed** and unloaded automatically after a short idle period.

## License

[MIT](LICENSE)
