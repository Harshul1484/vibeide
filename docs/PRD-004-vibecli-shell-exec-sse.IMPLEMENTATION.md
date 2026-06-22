# PRD-004 Implementation: vibecli Shell Exec SSE

## Working Directory
`d:\Projects\New folder\vibecli\.worktrees\vibecli-daemon`

## Steps

### Step 1: Write the Failing Tests — `shell/exec_test.go`
```go
package shell

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandleExec(t *testing.T) {
	body, _ := json.Marshal(map[string]interface{}{
		"command": "echo",
		"args":    []string{"hello vibecli"},
	})
	req := httptest.NewRequest(http.MethodPost, "/shell/exec", bytes.NewReader(body))
	w := httptest.NewRecorder()
	HandleExec(w, req)

	out := w.Body.String()
	if !strings.Contains(out, "hello vibecli") {
		t.Fatalf("expected 'hello vibecli' in SSE output, got: %s", out)
	}
	if !strings.Contains(out, `"type":"exit"`) {
		t.Fatalf("expected exit event in SSE output, got: %s", out)
	}
}

func TestHandleExecExitCode(t *testing.T) {
	body, _ := json.Marshal(map[string]interface{}{
		"command": "sh",
		"args":    []string{"-c", "exit 42"},
	})
	req := httptest.NewRequest(http.MethodPost, "/shell/exec", bytes.NewReader(body))
	w := httptest.NewRecorder()
	HandleExec(w, req)

	out := w.Body.String()
	if !strings.Contains(out, `"code":42`) {
		t.Fatalf("expected exit code 42, got: %s", out)
	}
}
```

### Step 2: Confirm Tests Fail
```bash
go test ./shell/... -run "TestHandleExec" -v
```
Expected: compilation error

### Step 3: Write `shell/exec.go`
```go
package shell

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net/http"
	"os/exec"
)

type execEvent struct {
	Type string `json:"type"`
	Data string `json:"data,omitempty"`
	Code int    `json:"code,omitempty"`
}

func HandleExec(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Command string   `json:"command"`
		Args    []string `json:"args"`
		Cwd     string   `json:"cwd"`
		Env     []string `json:"env"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	cmd := exec.CommandContext(r.Context(), req.Command, req.Args...)
	if req.Cwd != "" {
		cmd.Dir = req.Cwd
	}
	if len(req.Env) > 0 {
		cmd.Env = req.Env
	}

	stdout, _ := cmd.StdoutPipe()
	stderr, _ := cmd.StderrPipe()

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", http.StatusInternalServerError)
		return
	}

	send := func(ev execEvent) {
		data, _ := json.Marshal(ev)
		fmt.Fprintf(w, "data: %s\n\n", data)
		flusher.Flush()
	}

	if err := cmd.Start(); err != nil {
		send(execEvent{Type: "exit", Code: 1, Data: err.Error()})
		return
	}

	done := make(chan struct{}, 2)
	stream := func(scanner *bufio.Scanner, streamType string) {
		for scanner.Scan() {
			send(execEvent{Type: streamType, Data: scanner.Text() + "\n"})
		}
		done <- struct{}{}
	}
	go stream(bufio.NewScanner(stdout), "stdout")
	go stream(bufio.NewScanner(stderr), "stderr")
	<-done
	<-done

	code := 0
	if err := cmd.Wait(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			code = exitErr.ExitCode()
		} else {
			code = 1
		}
	}
	send(execEvent{Type: "exit", Code: code})
}
```

### Step 4: Remove `HandleExec` Stub from `shell/stub.go`
Keep only `HandlePty` stub until PRD-005 replaces it:
```go
package shell

import "net/http"

func HandlePty(w http.ResponseWriter, r *http.Request) {}
```

### Step 5: Run Tests
```bash
go test ./shell/... -run "TestHandleExec" -v
```
Expected: both `TestHandleExec` and `TestHandleExecExitCode` → `PASS`

### Step 6: Commit
```bash
git add shell/exec.go shell/exec_test.go shell/stub.go
git commit -m "feat: shell exec with SSE stdout/stderr streaming"
```

## Verification Checklist
- [ ] `TestHandleExec` passes (stdout streaming + exit event)
- [ ] `TestHandleExecExitCode` passes (exit code 42)
- [ ] `HandlePty` stub still compiles
- [ ] No duplicate `HandleExec` definitions
