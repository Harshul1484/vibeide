# PRD-002 Implementation: vibecli Filesystem Handlers

## Working Directory
`d:\Projects\New folder\vibecli\.worktrees\vibecli-daemon`

## Steps

### Step 1: Write the Failing Tests — `fs/handler_test.go`
```go
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

	body, _ := json.Marshal(map[string]string{"path": path, "content": "hello world"})
	req := httptest.NewRequest(http.MethodPost, "/fs/write", bytes.NewReader(body))
	w := httptest.NewRecorder()
	HandleWrite(w, req)
	if w.Code != http.StatusNoContent {
		t.Fatalf("write: expected 204, got %d", w.Code)
	}

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

### Step 2: Confirm Tests Fail
```bash
go test ./fs/... -v
```
Expected: compilation error (`FileNode` not defined)

### Step 3: Write `fs/handler.go`
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

### Step 4: Update `fs/stub.go`
Remove the 4 handler stubs that are now in `handler.go`; keep only `HandleWatch`:
```go
package fs

import "net/http"

func HandleWatch(w http.ResponseWriter, r *http.Request) {}
```

### Step 5: Run Tests
```bash
go test ./fs/... -v -run "TestHandleTree|TestHandleReadWrite|TestHandleDelete"
```
Expected: all 3 tests `PASS`

### Step 6: Commit
```bash
git add fs/
git commit -m "feat: filesystem handlers (tree, read, write, delete)"
```

## Verification Checklist
- [ ] `TestHandleTree` passes
- [ ] `TestHandleReadWrite` passes
- [ ] `TestHandleDelete` passes
- [ ] `fs/handler.go` exports `FileNode` type
- [ ] `HandleWatch` stub still compiles in `fs/stub.go`
