# PRD-003: vibecli File Watch SSE

## Overview
Implement the `/fs/watch` endpoint that streams file system change events as Server-Sent Events (SSE) using `fsnotify`.

## Goals
- Replace the `HandleWatch` stub with a real SSE streaming handler
- Send an event whenever a file in the watched directory is created, modified, or deleted
- Keep the connection alive with heartbeat comments every 30 seconds

## Non-Goals
- No recursive watching of subdirectories (single-level watch)
- No filtering by file extension

## Requirements

### Functional
1. `GET /fs/watch?path=<dir>` opens an SSE stream
2. Each file event is sent as: `data: {"path":"<absolute path>","op":"<CREATE|WRITE|REMOVE|RENAME|CHMOD>"}`
3. Heartbeat sent every 30 s: `: keepalive`
4. Stream closes when the client disconnects (`r.Context().Done()`)
5. Watch errors are forwarded as: `data: {"error":"<message>"}`

### Response Headers
```
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive
```

### Non-Functional
- Uses `github.com/fsnotify/fsnotify@v1.7.0`
- Handler must check `http.Flusher` support and return `500` if unavailable

## Acceptance Criteria
- [ ] `TestHandleWatch` passes: write a file while watching → event contains the filename
- [ ] Stream closes cleanly when context is cancelled
- [ ] `go test ./fs/... -run TestHandleWatch -v -timeout 10s` → `PASS`

## Files
| File | Action |
|------|--------|
| `fs/watcher.go` | Create |
| `fs/watcher_test.go` | Create |
| `fs/stub.go` | Remove `HandleWatch` stub |

## Dependencies
- PRD-001 (module with fsnotify dependency)
- PRD-002 (fs package exists, no conflict)
