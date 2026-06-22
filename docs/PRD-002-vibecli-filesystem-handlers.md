# PRD-002: vibecli Filesystem Handlers

## Overview
Implement the filesystem HTTP handlers for vibecli: directory tree listing, file read, write, and delete operations.

## Goals
- Expose `/fs/tree`, `/fs/read`, `/fs/write`, `/fs/delete` endpoints
- Each handler is tested with `httptest` and passes
- Replace the stub implementations in `fs/stub.go` with real code in `fs/handler.go`

## Non-Goals
- No file watching (SSE) — covered in PRD-003
- No authentication or path sandboxing beyond what the OS provides

## Requirements

### Functional
1. `GET /fs/tree?path=<dir>` returns a JSON `FileNode` tree up to 3 levels deep; hidden files (`.`-prefixed) excluded
2. `GET /fs/read?path=<file>` returns file contents as `text/plain`; `404` if not found
3. `POST /fs/write` with `{"path":"...","content":"..."}` writes the file (creates parent dirs); `204` on success
4. `POST /fs/delete` with `{"path":"..."}` removes the path recursively; `204` on success

### FileNode Schema
```json
{
  "name": "string",
  "path": "string",
  "isDir": true,
  "size": 0,
  "children": []
}
```

### Non-Functional
- `HandleWatch` stub must remain in place until PRD-003 replaces it
- No external dependencies beyond the Go standard library

## Acceptance Criteria
- [ ] `TestHandleTree` passes: returns 2 children for a dir with 1 file + 1 subdir
- [ ] `TestHandleReadWrite` passes: write then read round-trips correctly
- [ ] `TestHandleDelete` passes: file removed after delete call
- [ ] All 3 tests pass with `go test ./fs/... -v`

## Files
| File | Action |
|------|--------|
| `fs/handler.go` | Create |
| `fs/handler_test.go` | Create |
| `fs/stub.go` | Remove `HandleTree`, `HandleRead`, `HandleWrite`, `HandleDelete` stubs (keep `HandleWatch` stub) |

## Dependencies
- PRD-001 must be complete (module and server skeleton exist)
