# PRD-005: vibecli PTY WebSocket

## Overview
Implement `/shell/pty` — a WebSocket endpoint that attaches a pseudo-terminal (PTY) to a shell process, enabling interactive terminal sessions from Flutter.

## Goals
- Upgrade HTTP connections to WebSocket
- Spawn a shell (`/bin/bash` if available, else `/bin/sh`) inside a PTY
- Bidirectional streaming: PTY output → WebSocket binary frames; WebSocket text frames → PTY input or resize

## Non-Goals
- No session persistence (each WebSocket connection is a fresh shell)
- No authentication
- Not tested on Windows (PTY is Linux-only; test runs on Linux/Android)

## Requirements

### WebSocket Message Format (client → server)
```json
{"type": "input", "data": "ls -la\n"}
{"type": "resize", "cols": 80, "rows": 24}
```

### WebSocket Messages (server → client)
Raw bytes (terminal output) as binary WebSocket frames.

### Environment
- `TERM=xterm-256color` set on the spawned shell
- `upgrader.CheckOrigin` returns `true` (Flutter WebView origin bypass)

### Non-Functional
- Uses `github.com/creack/pty@v1.1.21` and `github.com/gorilla/websocket@v1.5.3`
- PTY is Linux-only — cross-compiled but not unit-tested on Windows

## Acceptance Criteria
- [ ] `TestHandlePty` passes (Linux/Android only): send `echo pty_ok\n`, receive output containing `pty_ok`
- [ ] `go test ./shell/... -run TestHandlePty -v -timeout 15s` → `PASS` on Linux
- [ ] Binary compiles for `linux/arm64` without errors

## Files
| File | Action |
|------|--------|
| `shell/pty.go` | Create |
| `shell/pty_test.go` | Create |
| `shell/stub.go` | Remove `HandlePty` stub (delete file if empty) |

## Dependencies
- PRD-001 (gorilla/websocket and creack/pty in go.mod)
- PRD-004 (HandleExec already in shell package)
