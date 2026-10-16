# appshot-for-agents

An open-source **Appshots for any AI agent** on macOS. Press a hotkey and get a screenshot of the frontmost window **plus the window's text** (read through the macOS Accessibility API — not OCR) — ready to paste into Claude, ChatGPT in the browser, or any chat window, and saved to disk for agents like Claude Code to read.

- **Based on [EYHN/appshots](https://github.com/EYHN/appshots)** (MIT) — hotkey detection and the overall idea come from there; this version is a small self-contained rewrite with no external dependencies.
- **Relationship to OpenAI Codex Appshots:** this is an independent, 1:1-in-spirit clone of the [Codex Appshots](https://developers.openai.com/codex/appshots) workflow (press both modifier keys → window image + AX text + a capture animation), but agent-agnostic. It is not affiliated with or endorsed by OpenAI.

## How it works

1. Hotkey pressed (default: **left ⌥ + right ⌥** together).
2. Front window is captured with ScreenCaptureKit.
3. Window text is read via the Accessibility (AX) tree. **Only if AX returns (almost) nothing** does it fall back to Apple Vision OCR.
4. The image goes to the **clipboard** (just ⌘V it into any chat) and both files are written:
   - `~/.appshot/latest.png`
   - `~/.appshot/latest.json` — `{ app, bundle_id, window_title, text, text_source, char_count, timestamp, image_path, json_path }`
5. A short transition plays *after* the capture (see below).

## Install & run (macOS 14+, Swift 5.9+ / Xcode CLT)

```sh
git clone https://github.com/Stephen2077/appshot-for-agents && cd appshot-for-agents && swift run -c release appshot
```

(It's a private repo for now: use `gh repo clone Stephen2077/appshot-for-agents`.) A 📸 icon appears in the menu bar.

### Permissions

On first run macOS asks for two permissions — grant them to the app that launched it (Terminal, iTerm, …) in **System Settings → Privacy & Security**:

- **Accessibility** — to read window text.
- **Screen Recording** — to capture the window image.

Restart `appshot` after granting. `appshot --check` prints the current status.

## Hotkeys

| `--hotkey` | Trigger |
|---|---|
| `option` (default) | hold left ⌥ + right ⌥ together |
| `command` / `shift` / `control` | left + right of that key |
| `double-command` (also `double-option`, …) | tap the key twice quickly |

Also settable with `APPSHOT_HOTKEY=double-command`. Menu bar → "Capture frontmost window now" works too, and `appshot --once` captures after 3 seconds and exits.

## Capture animation

After the screenshot is taken and saved, the captured window flashes white once and shrinks into a thumbnail that flies to the bottom-right corner of the screen (~0.5 s, macOS-screenshot-thumbnail style). It is a borderless, click-through overlay window animated with Core Animation, and it is only ever shown **after** the capture, so it never ends up in the image. Disable with `--no-animation` or `APPSHOT_ANIMATION=0`.

*Basis:* OpenAI does not document the Codex animation. What is publicly known (from Codex GitHub issues such as [openai/codex#33914](https://github.com/openai/codex/issues/33914) and the decompiled desktop app) is that Codex shows a native borderless overlay window with the captured window's image and that image transitions toward the composer's attachment slot. The flash, easing, timing, and bottom-right destination here are our own design, not a measured copy. The overlay also has guard rails (single overlay at a time, hard timeout) because Codex has had stuck-overlay bugs.

## Using it with agents

- **Any chat window** (Claude.ai, ChatGPT, …): trigger the hotkey, then ⌘V — the window image is on your clipboard. Paste `~/.appshot/latest.json`'s `text` if you want the exact text too.
- **Claude Code / Codex CLI / other local agents**: tell them to read the latest capture:

  ```
  Look at ~/.appshot/latest.png and ~/.appshot/latest.json (the window I just captured), then ...
  ```

  or in `CLAUDE.md` / `AGENTS.md`: *"When I say 'appshot', read ~/.appshot/latest.json (app, window_title, text) and view ~/.appshot/latest.png."*

## Security & privacy

- Captures **only when you press the hotkey** (or click the menu item). Nothing runs in the background besides listening for modifier-key state.
- Everything is stored **locally** in `~/.appshot` (directory mode 0700), overwritten on each capture. Nothing is uploaded by appshot.
- appshot makes **no network calls at all**.
- Treat `latest.json` as sensitive: it contains the text of whatever window you captured.

## Development

```sh
swift build            # CI runs this on macos-latest
swift run appshot --help
```

## License

MIT — see [LICENSE](LICENSE). Contains code adapted from [EYHN/appshots](https://github.com/EYHN/appshots) (© 2026 EYHN, MIT).
