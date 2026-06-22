# PRD-006: vibecli Git Handlers

## Overview
Implement HTTP handlers for common git operations: status, diff, log, commit, push, clone, and checkout. The handlers shell out to the `git` binary.

## Goals
- Expose all git operations listed in the route table in `main.go`
- Each handler tested with a real git repository created in `t.TempDir()`
- Clone streams progress via SSE

## Non-Goals
- No git credential storage
- No rebase, merge, or stash operations
- No in-process git library (uses `git` binary exclusively)

## Requirements

### Endpoints
| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/git/status?dir=<path>` | Returns branch, staged, modified, untracked |
| `GET` | `/git/diff?dir=<path>&base=HEAD` | Returns raw diff text |
| `GET` | `/git/log?dir=<path>` | Returns last 20 commits oneline |
| `POST` | `/git/commit` | Stage files and commit with message |
| `POST` | `/git/push` | Push branch to remote (supports Bearer token) |
| `POST` | `/git/clone` | Clone repo, streams progress as SSE |
| `POST` | `/git/checkout` | Checkout or create branch |

### `GitStatus` Response Schema
```json
{
  "branch": "main",
  "staged": [],
  "modified": [],
  "untracked": ["new.txt"]
}
```

### `CommitRequest` Body
```json
{
  "dir": "/path/to/repo",
  "message": "feat: my change",
  "files": ["file.txt"]
}
```

### Non-Functional
- `GIT_TERMINAL_PROMPT=0` set to prevent hanging on credential prompts
- All exec calls use `exec.Command("git", ...)` — no shell wrapping

## Acceptance Criteria
- [ ] `TestHandleStatus`: branch is `main`, untracked contains `new.txt`
- [ ] `TestHandleCommit`: response output contains the commit message
- [ ] `TestHandleCheckout`: branch switched to `feature/x`
- [ ] `go test ./git/... -v` → all 3 tests `PASS`

## Files
| File | Action |
|------|--------|
| `git/handler.go` | Create |
| `git/handler_test.go` | Create |
| `git/stub.go` | Remove all stubs |

## Dependencies
- PRD-001 (module setup)
- `git` binary must be available in `$PATH` on test machine
