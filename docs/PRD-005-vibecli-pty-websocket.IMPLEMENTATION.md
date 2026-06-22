# PRD-005 Implementation: vibecli PTY WebSocket

## Working Directory
`d:\Projects\New folder\vibecli\.worktrees\vibecli-daemon`

## Steps

### Step 1: Write the Test — `shell/pty_test.go`
```go
package shell

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func TestHandlePty(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(HandlePty))
	defer srv.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http")
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer conn.Close()

	conn.WriteMessage(websocket.TextMessage, []byte(`{"type":"input","data":"echo pty_ok\n"}`))
	conn.SetReadDeadline(time.Now().Add(3 * time.Second))

	found := false
	for i := 0; i < 10; i++ {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			break
		}
		if strings.Contains(string(msg), "pty_ok") {
			found = true
			break
		}
	}
	if !found {
		t.Fatal("expected 'pty_ok' in PTY output")
	}
}
```

### Step 2: Confirm Test Fails
```bash
go test ./shell/... -run TestHandlePty -v
```
Expected: compilation error (pty package import only works on Linux)

### Step 3: Write `shell/pty.go`
```go
package shell

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/exec"

	"github.com/creack/pty"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

func HandlePty(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("pty upgrade: %v", err)
		return
	}
	defer conn.Close()

	shell := "/bin/sh"
	if sh, err := exec.LookPath("bash"); err == nil {
		shell = sh
	}

	cmd := exec.Command(shell)
	cmd.Env = append(os.Environ(), "TERM=xterm-256color")

	ptmx, err := pty.Start(cmd)
	if err != nil {
		conn.WriteMessage(websocket.TextMessage, []byte("pty error: "+err.Error()))
		return
	}
	defer ptmx.Close()

	// PTY output → WebSocket
	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := ptmx.Read(buf)
			if n > 0 {
				conn.WriteMessage(websocket.BinaryMessage, buf[:n])
			}
			if err != nil {
				return
			}
		}
	}()

	// WebSocket input → PTY
	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			break
		}
		var m struct {
			Type string `json:"type"`
			Data string `json:"data"`
			Cols uint16 `json:"cols"`
			Rows uint16 `json:"rows"`
		}
		if err := json.Unmarshal(msg, &m); err != nil {
			ptmx.Write(msg)
			continue
		}
		switch m.Type {
		case "input":
			ptmx.Write([]byte(m.Data))
		case "resize":
			pty.Setsize(ptmx, &pty.Winsize{Rows: m.Rows, Cols: m.Cols})
		}
	}
	cmd.Process.Kill()
}
```

> Note: `shell/pty.go` uses `github.com/creack/pty` which is Linux-only. This file compiles only for `linux/arm64`. On Windows, use build constraints or accept that `go build` will fail locally but succeed in CI/cross-compile.

### Step 4: Remove `HandlePty` Stub from `shell/stub.go`
If `stub.go` is now empty, delete it. Otherwise remove just the `HandlePty` function.

### Step 5: Run Test (Linux only)
```bash
go test ./shell/... -run TestHandlePty -v -timeout 15s
```
Expected: `PASS` on Linux/Android

### Step 6: Commit
```bash
git add shell/pty.go shell/pty_test.go
git commit -m "feat: interactive PTY over WebSocket"
```

## Verification Checklist
- [ ] `shell/pty.go` imports `creack/pty` and `gorilla/websocket`
- [ ] `upgrader.CheckOrigin` always returns `true`
- [ ] Resize message handled via `pty.Setsize`
- [ ] `TestHandlePty` passes on Linux
- [ ] Cross-compile `GOOS=linux GOARCH=arm64 go build .` succeeds
