# PRD-004: vibecli Shell Exec SSE

## Overview
Implement `/shell/exec` — an endpoint that runs an arbitrary shell command and streams its stdout and stderr as Server-Sent Events, closing the stream with an exit-code event.

## Goals
- Real-time streaming of stdout and stderr via SSE
- Report the process exit code when the command finishes
- Handle context cancellation (client disconnect kills the process)

## Non-Goals
- No interactive PTY (covered in PRD-005)
- No shell built-in support (commands must be executable binaries)

## Requirements

### Request Body (JSON)
```json
{
  "command": "echo",
  "args": ["hello"],
  "cwd": "/optional/working/dir",
  "env": ["KEY=val"]
}
```

### SSE Event Types
| `type` field | Description |
|---|---|
| `stdout` | A line from standard output |
| `stderr` | A line from standard error |
| `exit` | Process finished; includes `"code"` field |

### Example SSE Stream
```
data: {"type":"stdout","data":"hello\n"}

data: {"type":"exit","code":0}
```

### Non-Functional
- Uses `os/exec` from standard library only
- Scanner-based line-by-line streaming (not byte-by-byte)
- Both stdout and stderr piped in parallel goroutines

## Acceptance Criteria
- [ ] `TestHandleExec`: output contains `hello vibecli` and a `"type":"exit"` event
- [ ] `TestHandleExecExitCode`: exit code `42` appears in the stream as `"code":42`
- [ ] `go test ./shell/... -run "TestHandleExec" -v` → both tests `PASS`

## Files
| File | Action |
|------|--------|
| `shell/exec.go` | Create |
| `shell/exec_test.go` | Create |
| `shell/stub.go` | Remove `HandleExec` stub |

## Dependencies
- PRD-001 (module and server skeleton)
