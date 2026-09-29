# VibeIDE — Product Analysis

Working notes behind the README. Everything here was checked against the source and against the running app, on a real Android phone and in a browser harness (see [How screenshots were captured](#how-screenshots-were-captured)).

---

## Product

| | |
|---|---|
| **Name** | VibeIDE |
| **One-liner** | A VS Code-style IDE for Android, with a real Linux sandbox and an AI agent whose edits you review before they land. |
| **Description** | VibeIDE runs an Alpine Linux userland on the phone through proot, so no root is needed. The Flutter UI talks to a small Go daemon (`vibecli`) inside that sandbox, which gives it a real filesystem, a real PTY, and real git. On top of that it adds GitHub sign-in, a bring-your-own-key AI assistant with a review-before-apply agent mode, and a GitHub pull-request flow. |
| **Target users** | Developers who want to make real changes to real repos away from a laptop: fix a bug, review or merge a PR, or have an AI make a change and ship it as a PR. |
| **Core problem** | Mobile code editors are usually either toys with no toolchain or thin remote clients that need a server. Neither lets you clone, edit, run, commit and open a PR entirely on the device. |
| **Solution** | Ship a sandboxed Linux on the phone and drive it from an IDE that follows desktop VS Code conventions (activity bar, explorer, tabs, bottom panel, status bar, command palette). |
| **Key differentiator** | Everything runs locally in a real Linux environment, with no remote dev box. The AI agent proposes whole-file edits that you approve, reject, or undo per file before anything is written. |

---

## Features (verified)

| # | Feature | What it does | Why it matters | Where in the UI | Best visual |
|---|---|---|---|---|---|
| 1 | **On-device Linux sandbox** | Extracts a bundled Alpine 3.21.3 rootfs (`alpine-rootfs.dat`, ~3.8 MB gzip) and boots it with proot (`libproot.so`, no root). `vibecli` listens on `127.0.0.1:7700`. | Real `git`, `apk`, `node` and `python` on the phone. | Onboarding "Set up sandbox"; status bar `● vibecli` | Phone status bar; terminal |
| 2 | **VS Code-style editor** | `re_editor` + `re_highlight`: syntax highlighting, code folding, tabs, and a long-press menu with Format / Run / Lint / Open with Live Server. | Familiar layout, usable on a phone. | Editor activity tab | `tablet-workspace.png`, `phone-editor.png` |
| 3 | **Adaptive layout** | A single full-width panel below 720 dp; a resizable side panel + editor at 720 dp and above (tablet / landscape). Draggable splitter and bottom-panel height. | Same app on phones and tablets. | Whole shell | Phone vs. tablet shots |
| 4 | **Real terminal** | xterm.js 5.3.0 in a WebView over a WebSocket PTY (`/shell/pty`), `cd`'d into the project. | Anything the UI doesn't cover, you can type. | Bottom panel → TERMINAL | `tablet-workspace.png` |
| 5 | **AI assistant + Agent mode** | Claude, OpenAI or Gemini with your own key; streaming chat. Agent mode sends the file list and asks the model for full-file `VIBE_EDIT` blocks. These become a **Proposed changes** card with Approve all / Reject all, per-file approve/reject/diff, and Undo. | AI changes are reviewable and reversible. | AI Assistant tab | `tablet-ai-agent.png` |
| 6 | **Daily token budget** | Estimated tokens per day, stored in SQLite, with a configurable cap (50k / 100k / 200k / 500k) and a "Daily token limit reached" banner. | Keeps BYO-key spend predictable. | AI header counter; Settings → Usage Today | `phone-settings.png` |
| 7 | **Source control** | Staged / changes / untracked lists, commit, pull, fetch, merge, abort. AI commit message button. Conflict resolution in the editor (Accept Current / Incoming / Both). Commit graph with branch chips. | A full git loop without the terminal. | Source Control tab | `tablet-source-control.png`, `phone-source-control.png` |
| 8 | **Pull requests** | Compare any two branches (commits, files changed, unified/split diff), create a branch from local changes, AI-written title + body, Create PR. PR list and PR detail with CI status and merge / squash / rebase. | Ship from the phone. | SCM header icons | `tablet-pull-request.png` |
| 9 | **Extensions (dev tools)** | A curated catalog of 32 tools (runtimes, languages, formatters/linters, utilities) installed globally via `apk` / `npm` / `pip`, with official logos. They power Run File, Format Document, and Lint → Problems. | Adds a toolchain on demand. | Extensions tab | `phone-extensions.png` |
| 10 | **Projects & GitHub** | GitHub Device Flow sign-in (token in encrypted storage). Browse your and your orgs' repos, clone by URL. Project list with sort (name / date opened), list or large-icon view, rename, remove. | Getting code onto the device. | Home screen (Projects / GitHub tabs) | `phone-projects.png` |
| 11 | **Search, Command Palette, Live Server** | Workspace search (case / regex). `Ctrl+Shift+P` palette. Live Server preview on port 5500 (`python3 http.server`, busybox `httpd` fallback). | Everyday workflow speed. | Search tab; ✨ activity icon; editor menu | `tablet-search.png`, `tablet-command-palette.png` |

### In the repo but **not** built (kept out of the README)

- `docs/superpowers/specs/2026-06-22-claude-code-integration-design.md`: running the real Claude Code CLI in the sandbox. Only **Layer 0** (the Alpine 3.21 base) is present. There is no `lib/features/claude_code/`.
- The design spec mentions Chrome Custom Tab OAuth with a `vibeide://oauth` redirect. The implemented sign-in is **GitHub Device Flow**. The intent filter still exists in the manifest.
- Some packages are declared but unused in `lib/`: `flutter_web_auth_2`, `web_socket_channel`.

---

## Product story

1. **Problem:** you can't really code on a phone. There's no toolchain, or you need a remote box.
2. **Product:** VibeIDE puts a real Linux sandbox and a VS Code-style IDE on the device.
3. **Experience:** clone → edit (by hand or with the AI agent, reviewing its changes) → commit → open a PR.
4. **Features:** editor, terminal, agent review, git + PRs, extensions.
5. **Technology:** Flutter UI → platform channel → Kotlin proot launcher → Alpine → Go `vibecli` (HTTP / SSE / WebSocket).
6. **Getting started:** build `vibecli`, then `flutter run` on an ARM64 Android device.

---

## Selected screens

| Screen | Purpose | Why it matters | What's visible | Mockup style | README placement |
|---|---|---|---|---|---|
| Tablet workspace | Hero / overview | The whole IDE in one frame | Explorer, 3 tabs, highlighted JS, terminal running real `git log --graph`, status bar | Tablet + phone hero; 2:1 banner | Top of README |
| Phone editor | Proves it's a phone app | Real-device capture | `index.html` with highlighting and soft wrap | Phone overlapping the hero | Hero |
| AI agent review | Most distinctive feature | Reviewable AI edits | Prompt, AI reply, "Proposed changes (1 file)", Approve / Reject | Single framed tablet | AI feature section |
| Source control | Core workflow | Real git state + graph | AI-generated commit message, staged/changes/untracked, branch graph | Layered with PR + phone | Git section |
| Pull request compare | Shipping | End of the loop | base → compare, files changed, diff, AI title/body, Create PR | Layered (above); workflow step 3 | Git section, workflow |
| Extensions (phone) | Toolchain on demand | Visual, logo-rich | Installed Node.js/tree, 30 available | Phone lineup | Extensions section |
| Project manager (phone) | Entry point | Where you start | Project row with remote URL | Phone lineup | Showcase |
| Onboarding | First run | Sets the promise | "Welcome to VibeIDE" slide | Phone lineup | Showcase |

---

## How screenshots were captured

**Real device (`phone-*.png`, except onboarding).** Samsung Galaxy A12s (SM-A127F), Android 13, arm64, 720×1600. This is the installed VibeIDE 1.0.0 build, last updated 2026-06-22, driven over `adb`. The project is GitHub's public sample repo `octocat/Spoon-Knife`, cloned in the app. The Android status bar is cropped off; nothing else is edited.

**Browser harness (`tablet-*.png`, `phone-onboarding.png`).** No emulator or tablet was available, so the app's own Flutter widgets were built for web and run against a **real `vibecli`** compiled from `vibecli/`. `vibecli` ran in an Alpine 3.21 container, mirroring the on-device `vibecli serve --port 7700`. File tree, editor contents, git status, graph, diffs, search and the PTY terminal are all real responses from that daemon. The harness lived in a throwaway copy outside the repo and replaced only the Android-specific pieces:

- `ProjectRepo` → in-memory (sqflite has no web backend)
- Sandbox boot → marked ready (proot is Android-only; `vibecli` was already running)
- `AiClient` → a **scripted response**. No API key was used. The AI reply text, the commit message `feat(timer): cycle focus and break sessions` and the PR title/body are stand-ins; the chat bubbles, review card and form filling are the real UI.
- `monospace` → Noto Sans Mono (the successor to Android's Droid Sans Mono), because Flutter web can't use system fonts.

Wide shots are 1280×800 dp @1.5× (the ≥720 dp tablet layout). Onboarding is rendered at the test phone's content area below its 24 dp status bar (384×829 dp @1.875×). The sample project `focus-timer` (author "Demo User") was created for the screenshots.

**Mockups (`docs/mockups/`)** are HTML/CSS compositions around the unmodified screenshots: generic tablet and phone frames, the app's own `#1E1E1E` / `#0078D4` palette, and a soft accent glow, rendered with headless Chrome. The UI inside the frames isn't retouched. The phone frames add a generic Android status bar (`12:00`, Wi-Fi, signal, battery) in place of the cropped real one, on the real background colour sampled from each capture.

---

## Issues observed while testing

These are real behaviours, noted here instead of being shown in the README.

1. **Agent diff shows the whole tail of the file as changed.** `parseEdits()` (`lib/features/ai/ai_edits.dart`) strips the trailing newline from AI content. The file on disk ends with `\n`, so `simpleUnifiedDiff()` finds no common suffix and marks every line after the first change as removed and re-added. Applying the edit also drops the file's final newline.
2. **Diff views drop the first character of git header lines** ("iff --git", "ew file mode", "-- a/…") in both the agent diff sheet and the PR compare view.
3. **Phone portrait + terminal open: the activity bar overflows.** Ten 48 dp icons don't fit above a 40% bottom panel; a debug build shows the overflow stripe.
4. **Terminal init on device:** the injected `PS1`/`cd` line failed once with `/bin/sh: syntax error: unexpected ")"`. The same page initialised correctly in the browser run.
5. **The AI API key isn't persisted.** `aiConfigProvider` is an in-memory `StateProvider`, so the key must be re-entered each launch. The GitHub token *is* persisted in encrypted storage.
6. **The terminal loads xterm.js from jsDelivr,** so the first terminal load needs network access.
7. **Tests:** `go test ./...` passes on Windows but not on Linux: `shell` tests call `cmd`, and the `git` commit test needs a global git identity. `flutter test`: 6 pass, `test/widget_test.dart` ("VibeIDE smoke test") fails.
8. **Branding:** the launcher icon and splash are still Flutter defaults, and `vibeide/README.md` is the Flutter template.
