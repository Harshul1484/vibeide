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
