# PRD-001 Implementation: vibecli Server Skeleton

## Working Directory
`d:\Projects\New folder\vibecli\.worktrees\vibecli-daemon`
Branch: `feature/vibecli-daemon`

## Steps

### Step 1: Initialize the Go Module
```bash
cd vibecli
go mod init github.com/vibeide/vibecli
go get github.com/gorilla/websocket@v1.5.3
go get github.com/fsnotify/fsnotify@v1.7.0
go get github.com/creack/pty@v1.1.21
```

### Step 2: Create `middleware/cors.go`
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

### Step 3: Create `main.go`
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

> Note: `fs`, `shell`, `git` packages have stub files in place so compilation succeeds before those tasks are implemented.

### Step 4: Create `main_test.go`
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

### Step 5: Run the Test
```bash
go test ./... -run TestHealth -v
```
Expected: `PASS`

### Step 6: Smoke-Test the Server
```bash
go run . &
curl http://127.0.0.1:7700/health
# Expected: {"status":"ok","version":"1.0.0"}
kill %1
```
> On Windows with PowerShell: `Start-Process go -ArgumentList "run","." -PassThru`

### Step 7: Commit
```bash
git add -A
git commit -m "feat: vibecli server skeleton with health endpoint"
```

## Verification Checklist
- [ ] `go.mod` present with `module github.com/vibeide/vibecli`
- [ ] `middleware/cors.go` exports `CORS` middleware
- [ ] `main.go` has `handleHealth` and route stubs
- [ ] `main_test.go` `TestHealth` passes
- [ ] Commit on branch `feature/vibecli-daemon`
