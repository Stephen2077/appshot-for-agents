# appshot-for-agents

An open-source **Appshots for any AI agent** on macOS. Press a hotkey and get a screenshot of the frontmost window **plus the window's text** (read through the macOS Accessibility API — not OCR) — ready to paste into Claude, ChatGPT in the browser, or any chat window, and saved to disk for agents like Claude Code to read.

- **Based on [EYHN/appshots](https://github.com/EYHN/appshots)** (MIT) — hotkey detection and the overall idea come from there; this version is a small self-contained rewrite with no external dependencies.
- **Relationship to OpenAI Codex Appshots:** this is an independent, 1:1-in-spirit clone of the [Codex Appshots](https://developers.openai.com/codex/appshots) workflow (press both modifier keys → window image + AX text + a capture animation), but agent-agnostic. It is not affiliated with or endorsed by OpenAI.

## How it works

1. Hotkey pressed (default: **left ⌥ + right ⌥** together).
2. Front window is captured with ScreenCaptureKit.
3. Window text is read via the Accessibility (AX) tree. **Only if AX returns (almost) nothing** does it fall back to Apple Vision OCR.
4. The image goes to the **clipboard**, and appshot **auto-pastes it (simulated ⌘V) into the input box you were typing in** — Claude/ChatGPT web, the Claude desktop app, Slack, … A small “Pasted into <app>” pill confirms it. Both files are also written:
   - `~/.appshot/latest.png`
   - `~/.appshot/latest.json` — `{ app, bundle_id, window_title, text, text_source, char_count, nodes_visited, truncated, timestamp, image_path, json_path }` (`text_source` is `accessibility`, `ocr` or `none`; `truncated: true` means a safety limit cut the walk short)
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

## Telling any agent about the capture

You can't change how someone else's agent UI works, so appshot also pastes **one short hint line** (no Enter is pressed) right after the image, with the real absolute paths:

```
[appshot] Screenshot of "Safari – Deploy Guide" saved at /Users/you/.appshot/latest.png ; extracted text and metadata in /Users/you/.appshot/latest.json
```

Order: image → hint line (after ~0.3 s) → window text (only with `--paste-text`). Agents that can read local files (Claude Code, Codex CLI, Cursor, …) can open those two files; chat apps that accept the pasted image just see it plus the line. Turn it off with `--no-hint` or `APPSHOT_HINT=0`.

For Claude Code / Codex, add this to your `CLAUDE.md` / `AGENTS.md`:

```md
## appshot
When a message contains a line starting with `[appshot]`, the user captured a window.
Read the PNG path (view the image) and the JSON path (`app`, `window_title`, `text`, `text_source`,
`truncated`) from that line and use them as context for the request.
```

If an app can't take pasted images or text, just tell the agent: *"read ~/.appshot/latest.json and ~/.appshot/latest.png"*.

## How the window text is extracted (and its limits)

appshot walks the **entire** Accessibility tree of the focused window (not only the visible part): every element's `AXChildren`, plus `AXRows` / `AXContents` for lists, tables and scroll areas, reading `AXValue`, `AXTitle` and `AXDescription`. Elements are de-duplicated, order is kept. Limits: 50,000 nodes, 200,000 characters, depth 60, 3 s total (`truncated` in the JSON tells you if one was hit). For Chromium/Electron apps (Claude/ChatGPT web, Slack, VS Code, …) it first sets `AXManualAccessibility` and `AXEnhancedUserInterface` so the web tree exists; the first capture of such an app waits ~0.5 s for it to build.

Honest limitation: appshot can only read what the target app *exposes*. Chat UIs built on Chromium/Electron usually **virtualize long lists** — messages scrolled far out of view are not in the DOM, so they are not in the AX tree either, and no AX-based tool can read them. If a capture is shorter than the whole conversation, that is why. (An optional "auto-scroll and stitch" capture is a possible follow-up; it is not implemented.) If AX yields almost nothing, Vision OCR of the screenshot is used instead.

## Auto-paste into the focused input

Like Codex Appshots, the capture goes where you are typing: start writing your message in any chat box, press the hotkey, and the window screenshot appears as an attachment in that box.

- Default: paste the **image** only. `--paste-text` additionally pastes the window **text** right after the image (your clipboard ends up holding the screenshot). `--no-paste` turns auto-paste off (clipboard + `~/.appshot` files only). Env: `APPSHOT_PASTE=0`, `APPSHOT_PASTE_TEXT=1`.
- It waits until you release the hotkey (so it sends a clean ⌘V, not ⌘⌥V), and only pastes if the same app is still frontmost. The animation overlay and the pill are non-activating, click-through windows, so focus never leaves your input.
- Needs the **Accessibility** permission (same one used to read window text). Without it, the image is still on the clipboard and the pill says so.
- Apps that don't accept pasted images simply ignore it; use `latest.png`/`latest.json` there.

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
