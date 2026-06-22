# PRD-003 Implementation: vibecli File Watch SSE

## Working Directory
`d:\Projects\New folder\vibecli\.worktrees\vibecli-daemon`

## Steps

### Step 1: Write the Failing Test — `fs/watcher_test.go`
```go
package fs

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
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

### Step 2: Confirm Test Fails
```bash
go test ./fs/... -run TestHandleWatch -v
```
Expected: compilation error (`HandleWatch` conflicts with stub or not defined with real body)

### Step 3: Write `fs/watcher.go`
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

### Step 4: Remove `HandleWatch` Stub from `fs/stub.go`
After creating `fs/watcher.go`, remove the `HandleWatch` function from `fs/stub.go`. If `stub.go` only had `HandleWatch`, delete the file entirely.

### Step 5: Run Test
```bash
go test ./fs/... -run TestHandleWatch -v -timeout 10s
```
Expected: `PASS`

### Step 6: Commit
```bash
git add fs/watcher.go fs/watcher_test.go fs/stub.go
git commit -m "feat: file watch SSE endpoint"
```

## Verification Checklist
- [ ] `TestHandleWatch` passes within 10 s
- [ ] No duplicate `HandleWatch` definition (stub removed)
- [ ] fsnotify imported and used correctly
- [ ] Keepalive ticker fires every 30 s (not tested but code-reviewed)
