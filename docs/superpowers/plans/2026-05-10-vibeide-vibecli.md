# VibeIDE — vibecli Daemon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `vibecli`, a Go HTTP daemon that runs inside Alpine Linux on Android, exposing file system, shell execution, interactive PTY, file watching, and git operations over a local HTTP/WebSocket API on `localhost:7700`.

**Architecture:** Single Go binary. Each domain (fs, shell, git) is a package with its own HTTP handlers. The main package wires them into a `net/http` ServeMux. Shell commands stream stdout/stderr via SSE. The PTY terminal uses a WebSocket. File changes are streamed via SSE using fsnotify. All handlers are tested with `httptest`.

**Tech Stack:** Go 1.22, `github.com/gorilla/websocket`, `github.com/fsnotify/fsnotify`, `github.com/creack/pty`

---

## File Map

```
vibecli/
├── main.go                  ← HTTP server, route registration, health handler
├── go.mod
├── middleware/
│   └── cors.go              ← CORS headers for Flutter WebView requests
├── fs/
│   ├── handler.go           ← /fs/tree, /fs/read, /fs/write, /fs/delete
│   ├── handler_test.go
│   ├── watcher.go           ← /fs/watch SSE stream
│   └── watcher_test.go
├── shell/
│   ├── exec.go              ← /shell/exec SSE stream
│   ├── exec_test.go
│   ├── pty.go               ← /shell/pty WebSocket PTY
│   └── pty_test.go
└── git/
    ├── handler.go           ← /git/clone, /git/status, /git/commit, /git/push, /git/checkout, /git/diff, /git/log
    ├── handler_test.go
    └── build.sh             ← cross-compile to linux/arm64
```

---

## Task 1: Go Module & Server Skeleton

**Files:**
- Create: `vibecli/main.go`
- Create: `vibecli/go.mod`
- Create: `vibecli/middleware/cors.go`

- [ ] **Step 1: Initialise the Go module**

```bash
cd vibecli
go mod init github.com/vibeide/vibecli
go get github.com/gorilla/websocket@v1.5.3
go get github.com/fsnotify/fsnotify@v1.7.0
go get github.com/creack/pty@v1.1.21
```

- [ ] **Step 2: Write `middleware/cors.go`**

```go
package middleware

import "net/http"

func CORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
```

- [ ] **Step 3: Write `main.go`**

```go
package main

import (
	"encoding/json"
	"flag"
	"log"
	"net/http"

	"github.com/vibeide/vibecli/fs"
	"github.com/vibeide/vibecli/git"
	"github.com/vibeide/vibecli/middleware"
	"github.com/vibeide/vibecli/shell"
)

func main() {
	port := flag.String("port", "7700", "listen port")
	flag.Parse()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handleHealth)
	mux.HandleFunc("GET /fs/tree", fs.HandleTree)
	mux.HandleFunc("GET /fs/read", fs.HandleRead)
	mux.HandleFunc("POST /fs/write", fs.HandleWrite)
	mux.HandleFunc("POST /fs/delete", fs.HandleDelete)
	mux.HandleFunc("GET /fs/watch", fs.HandleWatch)
	mux.HandleFunc("POST /shell/exec", shell.HandleExec)
	mux.HandleFunc("GET /shell/pty", shell.HandlePty)
	mux.HandleFunc("POST /git/clone", git.HandleClone)
	mux.HandleFunc("GET /git/status", git.HandleStatus)
	mux.HandleFunc("GET /git/diff", git.HandleDiff)
	mux.HandleFunc("GET /git/log", git.HandleLog)
	mux.HandleFunc("POST /git/commit", git.HandleCommit)
	mux.HandleFunc("POST /git/push", git.HandlePush)
	mux.HandleFunc("POST /git/checkout", git.HandleCheckout)

	log.Printf("vibecli listening on :%s", *port)
	log.Fatal(http.ListenAndServe("127.0.0.1:"+*port, middleware.CORS(mux)))
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "version": "1.0.0"})
}
```

- [ ] **Step 4: Write the health test in `main_test.go`**

```go
package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHealth(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()
	handleHealth(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if !strings.Contains(w.Body.String(), `"status":"ok"`) {
		t.Fatalf("unexpected body: %s", w.Body.String())
	}
}
```

- [ ] **Step 5: Run the test**

```bash
go test ./... -run TestHealth -v
```
Expected: `PASS`

- [ ] **Step 6: Smoke-test the server**

```bash
go run . &
curl http://127.0.0.1:7700/health
# Expected: {"status":"ok","version":"1.0.0"}
kill %1
```

- [ ] **Step 7: Commit**

```bash
git init && git add -A
git commit -m "feat: vibecli server skeleton with health endpoint"
```

---

## Task 2: Filesystem Handlers

**Files:**
- Create: `vibecli/fs/handler.go`
- Create: `vibecli/fs/handler_test.go`

- [ ] **Step 1: Write the failing tests**

```go
// fs/handler_test.go
package fs

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestHandleTree(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "hello.go"), []byte("package main"), 0644)
	os.Mkdir(filepath.Join(dir, "sub"), 0755)
	os.WriteFile(filepath.Join(dir, "sub", "util.go"), []byte("package sub"), 0644)

	req := httptest.NewRequest(http.MethodGet, "/fs/tree?path="+dir, nil)
	w := httptest.NewRecorder()
	HandleTree(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var node FileNode
	json.NewDecoder(w.Body).Decode(&node)
	if len(node.Children) != 2 {
		t.Fatalf("expected 2 children, got %d", len(node.Children))
	}
}

func TestHandleReadWrite(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "test.txt")

	// Write
	body, _ := json.Marshal(map[string]string{"path": path, "content": "hello world"})
	req := httptest.NewRequest(http.MethodPost, "/fs/write", bytes.NewReader(body))
	w := httptest.NewRecorder()
	HandleWrite(w, req)
	if w.Code != http.StatusNoContent {
		t.Fatalf("write: expected 204, got %d", w.Code)
	}

	// Read
	req = httptest.NewRequest(http.MethodGet, "/fs/read?path="+path, nil)
	w = httptest.NewRecorder()
	HandleRead(w, req)
	if w.Body.String() != "hello world" {
		t.Fatalf("read: expected 'hello world', got %q", w.Body.String())
	}
}

func TestHandleDelete(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "todelete.txt")
	os.WriteFile(path, []byte("bye"), 0644)

	body, _ := json.Marshal(map[string]string{"path": path})
	req := httptest.NewRequest(http.MethodPost, "/fs/delete", bytes.NewReader(body))
	w := httptest.NewRecorder()
	HandleDelete(w, req)

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", w.Code)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("file should be deleted")
	}
}
```

- [ ] **Step 2: Run tests — confirm they fail**

```bash
go test ./fs/... -v
```
Expected: compilation error (`FileNode` not defined, handlers not found)

- [ ] **Step 3: Write `fs/handler.go`**

```go
package fs

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type FileNode struct {
	Name     string     `json:"name"`
	Path     string     `json:"path"`
	IsDir    bool       `json:"isDir"`
	Size     int64      `json:"size,omitempty"`
	Children []FileNode `json:"children,omitempty"`
}

func HandleTree(w http.ResponseWriter, r *http.Request) {
	root := r.URL.Query().Get("path")
	if root == "" {
		root = "/root"
	}
	node, err := buildTree(root, 3)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(node)
}

func buildTree(path string, depth int) (FileNode, error) {
	info, err := os.Stat(path)
	if err != nil {
		return FileNode{}, err
	}
	node := FileNode{Name: info.Name(), Path: path, IsDir: info.IsDir(), Size: info.Size()}
	if !info.IsDir() || depth == 0 {
		return node, nil
	}
	entries, _ := os.ReadDir(path)
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].IsDir() != entries[j].IsDir() {
			return entries[i].IsDir()
		}
		return entries[i].Name() < entries[j].Name()
	})
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".") {
			continue
		}
		child, err := buildTree(filepath.Join(path, e.Name()), depth-1)
		if err == nil {
			node.Children = append(node.Children, child)
		}
	}
	return node, nil
}

func HandleRead(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Query().Get("path")
	if path == "" {
		http.Error(w, "path required", http.StatusBadRequest)
		return
	}
	f, err := os.Open(path)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}
	defer f.Close()
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	io.Copy(w, f)
}

func HandleWrite(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Path    string `json:"path"`
		Content string `json:"content"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if err := os.MkdirAll(filepath.Dir(req.Path), 0755); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err := os.WriteFile(req.Path, []byte(req.Content), 0644); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func HandleDelete(w http.ResponseWriter, r *http.Request) {
	var req struct{ Path string `json:"path"` }
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if err := os.RemoveAll(req.Path); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
```

- [ ] **Step 4: Run tests — confirm pass**

```bash
go test ./fs/... -v -run "TestHandleTree|TestHandleReadWrite|TestHandleDelete"
```
Expected: `PASS` for all 3 tests

- [ ] **Step 5: Commit**

```bash
git add fs/ && git commit -m "feat: filesystem handlers (tree, read, write, delete)"
```

---

## Task 3: File Watch SSE

**Files:**
- Create: `vibecli/fs/watcher.go`
- Create: `vibecli/fs/watcher_test.go`

- [ ] **Step 1: Write the failing test**

```go
// fs/watcher_test.go
package fs

import (
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
	"net/http"
)

func TestHandleWatch(t *testing.T) {
	dir := t.TempDir()
	req := httptest.NewRequest(http.MethodGet, "/fs/watch?path="+dir, nil)
	ctx, cancel := req.Context(), func() {}
	req, cancel2 := req.WithContext(req.Context()), cancel
	_ = cancel2

	w := httptest.NewRecorder()

	done := make(chan struct{})
	go func() {
		defer close(done)
		HandleWatch(w, req)
	}()

	time.Sleep(100 * time.Millisecond)
	os.WriteFile(filepath.Join(dir, "newfile.txt"), []byte("hi"), 0644)
	time.Sleep(200 * time.Millisecond)
	cancel()
	<-done

	body := w.Body.String()
	if !strings.Contains(body, "newfile.txt") {
		t.Fatalf("expected file event in SSE output, got: %s", body)
	}
}
```

- [ ] **Step 2: Run test — confirm fail**

```bash
go test ./fs/... -run TestHandleWatch -v
```
Expected: compilation error (`HandleWatch` not defined)

- [ ] **Step 3: Write `fs/watcher.go`**

```go
package fs

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/fsnotify/fsnotify"
)

func HandleWatch(w http.ResponseWriter, r *http.Request) {
	root := r.URL.Query().Get("path")
	if root == "" {
		root = "/root"
	}
	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer watcher.Close()

	if err := watcher.Add(root); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", http.StatusInternalServerError)
		return
	}

	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-r.Context().Done():
			return
		case event, ok := <-watcher.Events:
			if !ok {
				return
			}
			data, _ := json.Marshal(map[string]string{"path": event.Name, "op": event.Op.String()})
			fmt.Fprintf(w, "data: %s\n\n", data)
			flusher.Flush()
		case <-ticker.C:
			fmt.Fprintf(w, ": keepalive\n\n")
			flusher.Flush()
		case err := <-watcher.Errors:
			fmt.Fprintf(w, "data: {\"error\":%q}\n\n", err.Error())
			flusher.Flush()
		}
	}
}
```

- [ ] **Step 4: Run test — confirm pass**

```bash
go test ./fs/... -run TestHandleWatch -v -timeout 10s
```
Expected: `PASS`

- [ ] **Step 5: Commit**

```bash
git add fs/watcher.go fs/watcher_test.go && git commit -m "feat: file watch SSE endpoint"
```

---

## Task 4: Shell Exec SSE

**Files:**
- Create: `vibecli/shell/exec.go`
- Create: `vibecli/shell/exec_test.go`

- [ ] **Step 1: Write the failing test**

```go
// shell/exec_test.go
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

- [ ] **Step 2: Run — confirm fail**

```bash
go test ./shell/... -run "TestHandleExec" -v
```
Expected: compilation error

- [ ] **Step 3: Write `shell/exec.go`**

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

- [ ] **Step 4: Run tests — confirm pass**

```bash
go test ./shell/... -run "TestHandleExec" -v
```
Expected: `PASS` for both tests

- [ ] **Step 5: Commit**

```bash
git add shell/exec.go shell/exec_test.go && git commit -m "feat: shell exec with SSE stdout/stderr streaming"
```

---

## Task 5: PTY WebSocket

**Files:**
- Create: `vibecli/shell/pty.go`
- Create: `vibecli/shell/pty_test.go`

- [ ] **Step 1: Write the test**

```go
// shell/pty_test.go
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

	// Send a command
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

- [ ] **Step 2: Run — confirm fail**

```bash
go test ./shell/... -run TestHandlePty -v
```
Expected: compilation error

- [ ] **Step 3: Write `shell/pty.go`**

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

- [ ] **Step 4: Run test — confirm pass**

```bash
go test ./shell/... -run TestHandlePty -v -timeout 15s
```
Expected: `PASS`

- [ ] **Step 5: Commit**

```bash
git add shell/pty.go shell/pty_test.go && git commit -m "feat: interactive PTY over WebSocket"
```

---

## Task 6: Git Handlers

**Files:**
- Create: `vibecli/git/handler.go`
- Create: `vibecli/git/handler_test.go`

- [ ] **Step 1: Write the failing tests**

```go
// git/handler_test.go
package git

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func makeGitRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	run := func(args ...string) {
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		cmd.Env = append(os.Environ(), "GIT_AUTHOR_NAME=test", "GIT_AUTHOR_EMAIL=t@t.com",
			"GIT_COMMITTER_NAME=test", "GIT_COMMITTER_EMAIL=t@t.com")
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v: %s", args, out)
		}
	}
	run("init")
	run("checkout", "-b", "main")
	os.WriteFile(filepath.Join(dir, "README.md"), []byte("# test"), 0644)
	run("add", ".")
	run("commit", "-m", "init")
	return dir
}

func TestHandleStatus(t *testing.T) {
	dir := makeGitRepo(t)
	os.WriteFile(filepath.Join(dir, "new.txt"), []byte("new"), 0644)

	req := httptest.NewRequest(http.MethodGet, "/git/status?dir="+dir, nil)
	w := httptest.NewRecorder()
	HandleStatus(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp GitStatus
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.Branch != "main" {
		t.Fatalf("expected branch 'main', got %q", resp.Branch)
	}
	if len(resp.Untracked) == 0 {
		t.Fatal("expected untracked files")
	}
}

func TestHandleCommit(t *testing.T) {
	dir := makeGitRepo(t)
	os.WriteFile(filepath.Join(dir, "file.txt"), []byte("content"), 0644)

	body, _ := json.Marshal(CommitRequest{Dir: dir, Message: "test commit", Files: []string{"file.txt"}})
	req := httptest.NewRequest(http.MethodPost, "/git/commit", bytes.NewReader(body))
	w := httptest.NewRecorder()
	HandleCommit(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp map[string]string
	json.NewDecoder(w.Body).Decode(&resp)
	if !strings.Contains(resp["output"], "test commit") {
		t.Fatalf("unexpected commit output: %s", resp["output"])
	}
}

func TestHandleCheckout(t *testing.T) {
	dir := makeGitRepo(t)

	body, _ := json.Marshal(map[string]interface{}{"dir": dir, "branch": "feature/x", "create": true})
	req := httptest.NewRequest(http.MethodPost, "/git/checkout", bytes.NewReader(body))
	w := httptest.NewRecorder()
	HandleCheckout(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	out, _ := exec.Command("git", "-C", dir, "branch", "--show-current").Output()
	if strings.TrimSpace(string(out)) != "feature/x" {
		t.Fatalf("expected branch feature/x, got %q", string(out))
	}
}
```

- [ ] **Step 2: Run — confirm fail**

```bash
go test ./git/... -v
```
Expected: compilation error

- [ ] **Step 3: Write `git/handler.go`**

```go
package git

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"strings"
)

type GitStatus struct {
	Branch    string   `json:"branch"`
	Staged    []string `json:"staged"`
	Modified  []string `json:"modified"`
	Untracked []string `json:"untracked"`
}

type CommitRequest struct {
	Dir     string   `json:"dir"`
	Message string   `json:"message"`
	Files   []string `json:"files"`
}

func gitEnv() []string {
	return append(os.Environ(),
		"GIT_TERMINAL_PROMPT=0",
	)
}

func HandleStatus(w http.ResponseWriter, r *http.Request) {
	dir := r.URL.Query().Get("dir")
	branchOut, _ := exec.Command("git", "-C", dir, "rev-parse", "--abbrev-ref", "HEAD").Output()
	branch := strings.TrimSpace(string(branchOut))

	out, err := exec.Command("git", "-C", dir, "status", "--porcelain").Output()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	resp := GitStatus{Branch: branch}
	for _, line := range strings.Split(string(out), "\n") {
		if len(line) < 3 {
			continue
		}
		xy, file := line[:2], strings.TrimSpace(line[3:])
		switch {
		case xy == "??":
			resp.Untracked = append(resp.Untracked, file)
		case xy[0] != ' ':
			resp.Staged = append(resp.Staged, file)
		case xy[1] != ' ':
			resp.Modified = append(resp.Modified, file)
		}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func HandleDiff(w http.ResponseWriter, r *http.Request) {
	dir := r.URL.Query().Get("dir")
	base := r.URL.Query().Get("base")
	if base == "" {
		base = "HEAD"
	}
	args := []string{"-C", dir, "diff", base}
	out, err := exec.Command("git", args...).Output()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/plain")
	w.Write(out)
}

func HandleLog(w http.ResponseWriter, r *http.Request) {
	dir := r.URL.Query().Get("dir")
	out, err := exec.Command("git", "-C", dir, "log", "--oneline", "-20").Output()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/plain")
	w.Write(out)
}

func HandleCommit(w http.ResponseWriter, r *http.Request) {
	var req CommitRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	addArgs := append([]string{"-C", req.Dir, "add"}, req.Files...)
	if len(req.Files) == 0 {
		addArgs = []string{"-C", req.Dir, "add", "-A"}
	}
	if out, err := exec.Command("git", addArgs...).CombinedOutput(); err != nil {
		http.Error(w, string(out), http.StatusInternalServerError)
		return
	}
	cmd := exec.Command("git", "-C", req.Dir, "commit", "-m", req.Message)
	cmd.Env = gitEnv()
	out, err := cmd.CombinedOutput()
	if err != nil {
		http.Error(w, string(out), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"output": string(out)})
}

func HandleClone(w http.ResponseWriter, r *http.Request) {
	var req struct {
		URL   string `json:"url"`
		Dir   string `json:"dir"`
		Token string `json:"token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	cloneURL := req.URL
	if req.Token != "" {
		cloneURL = strings.Replace(req.URL, "https://", "https://oauth2:"+req.Token+"@", 1)
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	flusher := w.(http.Flusher)

	cmd := exec.CommandContext(r.Context(), "git", "clone", "--progress", cloneURL, req.Dir)
	cmd.Env = gitEnv()
	stderr, _ := cmd.StderrPipe()
	if err := cmd.Start(); err != nil {
		fmt.Fprintf(w, "data: {\"error\":%q}\n\n", err.Error())
		flusher.Flush()
		return
	}
	scanner := bufio.NewScanner(stderr)
	for scanner.Scan() {
		data, _ := json.Marshal(map[string]string{"progress": scanner.Text()})
		fmt.Fprintf(w, "data: %s\n\n", data)
		flusher.Flush()
	}
	if err := cmd.Wait(); err != nil {
		data, _ := json.Marshal(map[string]string{"error": err.Error()})
		fmt.Fprintf(w, "data: %s\n\n", data)
	} else {
		fmt.Fprintf(w, "data: {\"done\":true}\n\n")
	}
	flusher.Flush()
}

func HandlePush(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Dir    string `json:"dir"`
		Remote string `json:"remote"`
		Branch string `json:"branch"`
		Token  string `json:"token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if req.Remote == "" {
		req.Remote = "origin"
	}
	args := []string{"-C", req.Dir}
	if req.Token != "" {
		args = append(args,
			"-c", "credential.helper=",
			"-c", fmt.Sprintf("http.extraHeader=Authorization: Bearer %s", req.Token),
		)
	}
	args = append(args, "push", req.Remote, req.Branch)
	out, err := exec.Command("git", args...).CombinedOutput()
	if err != nil {
		http.Error(w, string(out), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"output": string(out)})
}

func HandleCheckout(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Dir    string `json:"dir"`
		Branch string `json:"branch"`
		Create bool   `json:"create"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	args := []string{"-C", req.Dir, "checkout"}
	if req.Create {
		args = append(args, "-b")
	}
	args = append(args, req.Branch)
	out, err := exec.Command("git", args...).CombinedOutput()
	if err != nil {
		http.Error(w, string(out), http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"output": string(out)})
}
```

- [ ] **Step 4: Run tests — confirm pass**

```bash
go test ./git/... -v
```
Expected: `PASS` for all git tests

- [ ] **Step 5: Commit**

```bash
git add git/ && git commit -m "feat: git handlers (status, diff, log, commit, push, clone, checkout)"
```

---

## Task 7: Build Script for linux/arm64

**Files:**
- Create: `vibecli/build.sh`

- [ ] **Step 1: Run the full test suite one last time**

```bash
go test ./... -v
```
Expected: all tests pass

- [ ] **Step 2: Write `build.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Building vibecli for linux/arm64..."
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
  go build -ldflags="-s -w" -o dist/vibecli-arm64 .

echo "Binary size: $(du -sh dist/vibecli-arm64 | cut -f1)"
echo "Done: dist/vibecli-arm64"
```

- [ ] **Step 3: Run the build**

```bash
mkdir -p dist
chmod +x build.sh && ./build.sh
```
Expected output:
```
Building vibecli for linux/arm64...
Binary size: ~6M
Done: dist/vibecli-arm64
```

- [ ] **Step 4: Verify the binary is the correct architecture**

```bash
file dist/vibecli-arm64
```
Expected: `dist/vibecli-arm64: ELF 64-bit LSB executable, ARM aarch64`

- [ ] **Step 5: Final commit**

```bash
git add build.sh dist/.gitkeep && git commit -m "build: cross-compile script for linux/arm64"
```

---

**vibecli is complete.** Copy `dist/vibecli-arm64` to `vibeide/android/app/src/main/assets/vibecli-arm64` before starting the Flutter plan.
