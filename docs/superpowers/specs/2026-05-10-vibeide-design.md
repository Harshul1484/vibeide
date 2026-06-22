# VibeIDE — Design Spec
**Date:** 2026-05-10
**Status:** Approved

---

## Overview

VibeIDE is a standalone Flutter app for Android (Play Store) that provides a mobile developer environment with a VS Code-style UI. It runs a real Alpine Linux sandbox on-device via proot (no root required), giving developers full access to git, Node.js, and Python in an isolated environment. An integrated multi-provider AI assistant supports vibe-coded development and auto-generates GitHub PRs from diffs.

---

## 1. Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Flutter UI Layer                    │
│  VS Code Shell │ AI Chat Panel │ Terminal Emulator  │
└──────────────────────┬──────────────────────────────┘
                       │ Dart ↔ Platform Channel
┌──────────────────────▼──────────────────────────────┐
│             Android Native Layer (Kotlin)            │
│   proot launcher │ process manager │ port forwarder  │
└──────────────────────┬──────────────────────────────┘
                       │ Unix socket / TCP localhost
┌──────────────────────▼──────────────────────────────┐
│         Alpine Linux Sandbox (proot, no root)        │
│  ┌──────────┐  ┌──────────┐  ┌────────────────────┐ │
│  │   git    │  │  node    │  │  python3 / pip     │ │
│  └──────────┘  └──────────┘  └────────────────────┘ │
│  ┌─────────────────────────────────────────────────┐ │
│  │   vibecli daemon (Go binary, always-on)         │ │
│  │   - file ops  - shell exec  - git ops  - watch  │ │
│  └─────────────────────────────────────────────────┘ │
│  /data/projects/<project-id>/  (app-private storage) │
└─────────────────────────────────────────────────────┘
                       │ HTTPS
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
   GitHub API     AI Provider    internet (npm/pip)
  (OAuth + PR)  (Claude/GPT/Gemini)
```

### Key decisions
- **proot + Alpine Linux ARM64** — user-space chroot, no root required. Termux uses this pattern at 50M+ users. Ships as a tarball (~80MB compressed) in APK assets, extracted on first launch.
- **vibecli daemon** — a small Go binary (compiled `linux/arm64`) that runs inside Alpine on `localhost:7700`. It is the single interface between Flutter and the Linux world. The Flutter layer never touches the filesystem directly.
- **Projects** live at `<app-private>/projects/<uuid>/` — isolated from each other and from the rest of Android.
- **Startup time** — Alpine boot + vibecli ready in ~2–5s on first launch after extraction, ~1–2s on subsequent launches.

---

## 2. vibecli Daemon

### Startup sequence
```
App launch
  → Kotlin checks if Alpine rootfs is extracted
      → First run: extract tarball from assets (~5s, progress shown)
      → Subsequent runs: skip
  → Kotlin spawns: proot --rootfs=<alpine-dir> /bin/vibecli serve --port 7700
  → Flutter polls localhost:7700/health until ready
  → Status bar shows "vibecli ●" green → UI unlocks
```

### HTTP API (localhost:7700 inside Alpine)

| Endpoint | Purpose |
|---|---|
| `GET /health` | Readiness check |
| `GET /fs/tree?path=` | File tree listing |
| `GET /fs/read?path=` | Read file contents |
| `POST /fs/write` | Write file contents |
| `POST /fs/delete` | Delete file or directory |
| `POST /shell/exec` | Run command, stream stdout/stderr via SSE |
| `GET /shell/pty` | WebSocket — full interactive PTY for terminal |
| `POST /git/clone` | Clone repo with progress stream |
| `GET /git/status` | Branch, staged, modified, untracked counts |
| `POST /git/commit` | Stage + commit with message |
| `POST /git/push` | Push to remote |
| `GET /fs/watch` | SSE stream of file change events |

### Why Go
- Single static binary, zero Alpine dependencies
- Goroutines handle concurrent PTY + file watch + HTTP at ~8MB idle RAM
- Compiled once for `linux/arm64`, bundled in APK assets, copied into Alpine on first boot

---

## 3. UI Layout

Matches VS Code desktop aesthetic exactly (dark theme, activity bar, explorer panel, editor, terminal, status bar).

```
┌─────────────────────────────────────────────────────────────┐
│ ● VibeIDE                                   [⚡][👤][⋮]    │  ← Top app bar
├──┬──────────────────────────────┬────────────────────────────┤
│  │  EXPLORER              [+][⋯]│                            │
│🗂│  ▼ my-project (main ▾)       │   index.js           ×    │
│🔍│    ▼ src/                    │  ┌──────────────────────┐  │
│⎇│      index.js               │  │ 1  const x = 1;     │  │
│🤖│      utils.py               │  │ 2                    │  │
│⚙│    package.json              │  │ 3  module.exports=x  │  │
│  │                             │  └──────────────────────┘  │
│  │  BRANCHES                   ├────────────────────────────┤
│  │  ● main                     │ 🤖 AI Assistant            │
│  │    feature/auth             │ ┌──────────────────────┐   │
│  │                             │ │ You: add error       │   │
│  │  PROJECTS            [+]    │ │ handling here        │   │
│  │  ▶ my-project               │ │ Claude: Sure! ...    │   │
│  │  ▶ portfolio-site           │ └──────────────────────┘   │
│  │                             │ [Type a message...][Send]  │
├──┴─────────────────────────────┴────────────────────────────┤
│ TERMINAL                                              [▲][×] │
│ alpine$ git status                                          │
│ alpine$  _                                                  │
├─────────────────────────────────────────────────────────────┤
│ ⎇ main  ✓ 0  ✗ 0  │ Python 3.11 │ Node 20 │  vibecli ●   │
└─────────────────────────────────────────────────────────────┘
```

### UI components
- **Activity bar (left strip):** Explorer, Search, Git/Branches, AI Assistant, Settings
- **Left panel:** File tree with branch switcher + project switcher
- **Editor area:** Syntax-highlighted code editor (`re_editor`), tab bar for open files, pinch-to-zoom
- **AI chat panel:** Collapsible, token-by-token streaming, AI can write files with inline diff preview before applying
- **Terminal drawer:** Full PTY terminal via `xterm.js` in a WebView, connects directly to Alpine shell
- **Status bar:** Branch, git counts, active runtime versions, vibecli connection state

### Gestures
- Pinch-to-zoom on editor
- Swipe left panel closed on small screens
- Long-press file for rename/delete/copy
- Pull terminal drawer up from status bar

---

## 4. GitHub Integration & AI PR Workflow

### OAuth Flow
```
User taps "Connect GitHub"
  → App opens Chrome Custom Tab → github.com/login/oauth/authorize
  → GitHub redirects to vibeide://oauth/callback?code=xxx
  → App intercepts via Android intent filter
  → Exchanges code for access token
  → Token stored encrypted in Android Keystore
  → Status bar shows GitHub avatar + username
```

### Git Operations
All git operations are available via:
1. **Terminal** — raw git commands in the Alpine PTY
2. **Source Control panel** — GUI (VS Code SCM feel): stage, unstage, diff, commit, push, pull, branch, merge, stash
3. **Command palette** — swipe-down or button shortcut

Supported: `clone`, `pull`, `fetch`, `push`, `checkout`, `branch -b`, `merge`, `stash`, `stash pop`, `log`, `diff`, `reset`

### AI-Powered PR Workflow
```
User taps "Raise PR" in Source Control panel
  → vibecli runs: git diff main...HEAD → full diff text
  → Flutter sends diff to AI provider with prompt:
      "Write a GitHub PR title and description for this diff."
  → AI streams back: title + markdown body
  → User sees editable PR preview:
      ┌──────────────────────────────┐
      │ Title: [AI-generated ✏️]    │
      │ Base: main ▾  ← feature/x   │
      │ Body: [AI markdown, editable]│
      │ Labels: [bug][enhancement]   │
      │ [Cancel]        [Create PR]  │
      └──────────────────────────────┘
  → Taps "Create PR" → GitHub API POST /repos/{owner}/{repo}/pulls
  → Success toast with PR URL → tapping opens PR in Chrome Custom Tab
```

### AI Commit Message Assist
- In SCM panel, tapping commit message field shows a ✨ button
- Tap → runs `git diff --staged` → AI generates conventional commit message
- User can accept, edit, or regenerate

---

## 5. Project Manager

VS Code "Open Recent" feel:

```
┌─────────────────────────────────────────┐
│ VibeIDE                          [+ New] │
├─────────────────────────────────────────┤
│ RECENT PROJECTS                         │
│ ┌─────────────────────────────────────┐ │
│ │ 📁 my-project          ⎇ main      │ │
│ │    github.com/user/my-project       │ │
│ │    Last opened: 2h ago    [Open][⋯] │ │
│ └─────────────────────────────────────┘ │
│ [Clone from GitHub] [Open local folder] │
└─────────────────────────────────────────┘
```

Each project record stores: remote URL, active branch, last opened timestamp, Alpine working directory path. Stored in SQLite via `sqflite`.

---

## 6. Multi-Provider AI & Token Budget

### Supported providers

| Provider | Models |
|---|---|
| Anthropic | claude-opus-4-7, claude-sonnet-4-6, claude-haiku-4-5 |
| OpenAI | gpt-4o, gpt-4o-mini |
| Google | gemini-2.0-flash, gemini-1.5-pro |

### Settings UI
```
Settings → AI Assistant
  Provider: [Claude ▾]
  API Key:  [••••••••] 👁
  Model:    [claude-sonnet-4-6 ▾]
  Daily token limit: [100,000 ▾]
  Used today: 34,210 / 100,000  ████░░░ 34%
```

### Token budget enforcement
- Flutter tracks cumulative tokens per provider per day in local SQLite
- Hard cap configurable in Settings (default: 100K tokens/day)
- When cap reached, AI chat shows "Daily limit reached" banner — terminal and git continue working normally
- Resets at midnight local time

---

## 7. Flutter Package Stack

| Concern | Package |
|---|---|
| Code editor | `re_editor` |
| Terminal PTY | `xterm.js` in `flutter_inappwebview` WebView |
| File tree | Custom `TreeView` widget |
| HTTP + SSE (vibecli) | `dio` |
| GitHub OAuth | `flutter_web_auth_2` + Android intent filter |
| Secure token storage | `flutter_secure_storage` (Android Keystore) |
| Local DB | `sqflite` |
| AI streaming (Anthropic) | `anthropic_sdk_dart` |
| AI streaming (OpenAI/Gemini) | Raw `http` SSE |
| State management | `riverpod` |

---

## 8. Folder Structure

```
vibeide/
├── android/
│   └── app/src/main/
│       ├── kotlin/.../
│       │   └── ProotPlugin.kt         ← proot launcher & process manager
│       └── assets/
│           ├── alpine-arm64.tar.gz    ← Alpine Linux rootfs (~80MB compressed)
│           └── vibecli-arm64          ← Go daemon binary
├── lib/
│   ├── main.dart
│   ├── features/
│   │   ├── editor/                    ← code editor + tabs
│   │   ├── terminal/                  ← PTY terminal WebView
│   │   ├── explorer/                  ← file tree + project manager
│   │   ├── git/                       ← SCM panel + PR workflow
│   │   ├── ai/                        ← chat panel + provider clients
│   │   └── sandbox/                   ← vibecli HTTP/SSE/WS client
│   └── shared/
│       ├── settings/
│       └── auth/                      ← GitHub OAuth + token storage
└── vibecli/                           ← Go source for the daemon
    ├── main.go
    ├── fs/
    ├── shell/
    └── git/
```

---

## 9. Constraints & Non-Goals

- **Android only** — no iOS (proot is Android-specific)
- **ARM64 only** — Alpine rootfs and vibecli compiled for `linux/arm64` (covers 99%+ of modern Android devices)
- **No cloud sync** — projects are local to the device; GitHub serves as the remote
- **No extension marketplace** — no VS Code extension support in v1
- **Internet required for** — git clone/push, AI providers, npm/pip installs; terminal + editor + local git work fully offline
