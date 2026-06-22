package fs

import (
	"context"
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
	ctx, cancel := context.WithCancel(context.Background())
	req := httptest.NewRequest(http.MethodGet, "/fs/watch?path="+dir, nil).WithContext(ctx)

	w := httptest.NewRecorder()
	done := make(chan struct{})
	go func() {
		defer close(done)
		HandleWatch(w, req)
	}()

	time.Sleep(100 * time.Millisecond)
	os.WriteFile(filepath.Join(dir, "newfile.txt"), []byte("hi"), 0644)
	time.Sleep(300 * time.Millisecond)
	cancel()
	<-done

	if !strings.Contains(w.Body.String(), "newfile.txt") {
		t.Fatalf("expected file event in SSE output, got: %s", w.Body.String())
	}
}
