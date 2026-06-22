# PRD-001: vibecli Server Skeleton

## Overview
Initialize the Go module and create the HTTP server skeleton for `vibecli`, the daemon that runs inside Alpine Linux on Android as part of VibeIDE.

## Goals
- Establish the Go module (`github.com/vibeide/vibecli`) with all required dependencies
- Create a working HTTP server on `localhost:7700`
- Expose a `/health` endpoint returning `{"status":"ok","version":"1.0.0"}`
- Apply CORS middleware so Flutter WebView requests succeed
- Confirm compilation and health test pass

## Non-Goals
- No filesystem, shell, or git handlers in this task
- No Android deployment or cross-compilation

## Requirements

### Functional
1. `GET /health` returns `200 OK` with JSON body `{"status":"ok","version":"1.0.0"}`
2. CORS headers (`Access-Control-Allow-Origin: *`) on every response
3. `OPTIONS` preflight returns `204 No Content`
4. Server binds to `127.0.0.1:7700` by default; port configurable via `--port` flag

### Non-Functional
- Module path: `github.com/vibeide/vibecli`
- Go version: 1.22+
- Dependencies: `gorilla/websocket@v1.5.3`, `fsnotify/fsnotify@v1.7.0`, `creack/pty@v1.1.21`
- All code in `package main`; middleware in `package middleware`

## Acceptance Criteria
- [ ] `go.mod` exists with correct module path and Go 1.22
- [ ] `middleware/cors.go` exports `CORS(next http.Handler) http.Handler`
- [ ] `main.go` contains `handleHealth` function and route registration
- [ ] `main_test.go` `TestHealth` passes with `go test -run TestHealth`
- [ ] Server starts and responds: `curl http://127.0.0.1:7700/health` → `{"status":"ok","version":"1.0.0"}`

## Files
| File | Action |
|------|--------|
| `main.go` | Create |
| `go.mod` | Create |
| `go.sum` | Auto-generated |
| `middleware/cors.go` | Create |
| `main_test.go` | Create |

## Dependencies
None — this is the foundation task.
