# Claude Code Integration — Design Spec
**Date:** 2026-06-22
**Status:** Approved (build in layers: 0 → 1 → 2)

## Goal
Let users connect their Claude account and use **the real Claude Code agent**
inside VibeIDE — it edits/creates/updates files in the sandbox, with the same
permission modes as the VS Code extension (Ask before edits / Edit automatically
/ Plan / Auto). Claude Code runs as the genuine CLI inside the Alpine sandbox.

## Verified feasibility (on-device test, 2026-06-22)
- Sandbox is aarch64 Alpine. Node 20 + npm install fine.
- `npm install -g @anthropic-ai/claude-code` ships a `linux-arm64-musl` build.
- It needs **musl ≥ 1.2.5** (exports `statx`). Alpine 3.19's musl 1.2.4 fails with
  `Error relocating claude: statx: symbol not found`.
- After `apk upgrade musl musl-utils` → musl 1.2.6 → `claude --version` prints
  `2.1.185 (Claude Code)`. **Confirmed working.**
- CLI exposes: `-p/--print`, `--output-format stream-json`, `--input-format`,
  `--permission-mode <mode>`, `--verbose`, `auth`, `setup-token`.

## Layered build plan

### Layer 0 — Alpine 3.21 base (prerequisite)
Replace the bundled `android/app/src/main/assets/alpine-rootfs.dat` with **Alpine
3.21 aarch64 minirootfs** (musl 1.2.6) so `statx` is present out of the box — no
runtime musl upgrade needed. Update repo URLs in the extracted `/etc/apk/repositories`
to v3.21. Verify the existing clone/extension/terminal flows still work on 3.21.

### Layer 1 — Connect Claude Code (terminal-driven)
A "Connect Claude Code" entry point (in the AI panel header and/or Settings):
- **Setup step** (idempotent, like `ensureGit`): ensure Node + npm installed
  (`apk add nodejs npm`), then `npm install -g @anthropic-ai/claude-code` if
  `command -v claude` fails. Show progress (rotating phrases + log line).
- **Login:** open the Terminal panel and run `claude` (interactive). The user sees
  Claude Code's real login screen → picks "Claude.ai Subscription" → completes
  OAuth in the browser (Custom Tab/external). Auth persists in the sandbox
  (`~/.claude` / `~/.config`). A "Login with Claude" button just sends `claude`
  to the terminal.
- **Connection status:** a provider checks `claude auth` / a lightweight
  `claude -p "ok"` to detect logged-in state; reflect it in the UI (Connected ✓
  / Not connected).
- This layer alone makes the real Claude Code usable in the terminal.

### Layer 2 — Native Claude Code chat UI
A dedicated **"Claude Code"** view (own activity-bar tab, distinct from the
existing BYO-key AI chat):
- **Mode selector** (bottom bar, like the screenshot): Ask before edits /
  Edit automatically / Plan / Auto. Maps to `--permission-mode`:
  - Ask before edits → `default` (prompts for each edit/command)
  - Edit automatically → `acceptEdits`
  - Plan mode → `plan`
  - Auto → `default` + our own classifier OR just `acceptEdits` (document the
    mapping; "Auto" = acceptEdits for v1).
- **Driving Claude Code:** run
  `claude -p "<prompt>" --output-format stream-json --input-format stream-json
   --permission-mode <mode> --verbose` in the project dir via a long-running
  `exec` stream. Feed the user's message as stream-json input; parse the
  stream-json output events.
- **Rendering events:**
  - assistant text deltas → chat bubble (streamed)
  - tool_use events (Edit/Write/Read/Bash) → tool cards ("✎ Editing src/x.js",
    "▶ Running npm test")
  - permission requests (when mode=default) → an inline **Allow / Allow always /
    Deny** prompt; the answer is sent back via stream-json input
  - result event → finalize the turn
- **File-change surfacing:** after edits, refresh `fileTreeProvider` +
  `gitStatusProvider` and reload open tabs so the editor/SCM show what Claude
  changed (reuse the existing invalidation pattern). The user then reviews in
  SCM and can create a PR with the existing flow.
- **Session continuity:** support `--resume`/`--continue` so the conversation
  persists across turns (Claude Code manages session state in the sandbox).

## Components / files (rough)
- `vibecli` / SandboxClient: a long-running exec with **bidirectional stdin**
  for stream-json input. NOTE: the current `/shell/exec` is one-shot (args only,
  no stdin streaming). Layer 2 needs either (a) a new vibecli endpoint that keeps
  stdin open for stream-json, or (b) drive Claude Code via the PTY/WebSocket
  (which already supports bidirectional I/O). Decide during Layer 2 planning;
  PTY reuse is likely simplest but stream-json over a clean pipe is cleaner to
  parse. Flag for the implementation plan.
- `lib/features/claude_code/` — connect flow, status provider, chat UI, mode
  selector, stream-json parser, permission-prompt widget.
- Activity bar: add a "Claude Code" tab (distinct icon).
- Settings: "Claude Code" section (connection status, logout, model/mode default).

## Constraints / non-goals
- v1 "Auto" mode = `acceptEdits` (no custom classifier).
- Login is interactive via the terminal once; we don't reimplement Anthropic OAuth.
- Keep the existing BYO-key AI chat as-is (separate feature). Claude Code is additive.
- Requires the user's own Claude subscription (or Console/API via `setup-token`).
- Native APK builds etc. remain out of scope (sandbox limitation, unrelated).

## Risks
- stream-json bidirectional I/O needs a sandbox channel that keeps stdin open —
  the biggest unknown for Layer 2 (addressed above).
- Alpine 3.21 swap must not regress clone/extensions/terminal (verify in Layer 0).
- Claude Code version drift (CLI flags can change) — pin a known-good version
  or handle gracefully.
