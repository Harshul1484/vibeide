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
		"command": "cmd",
		"args":    []string{"/c", "echo hello vibecli"},
	})
	req := httptest.NewRequest(http.MethodPost, "/shell/exec", bytes.NewReader(body))
	w := httptest.NewRecorder()
	HandleExec(w, req)

	out := w.Body.String()
	if !strings.Contains(out, "hello vibecli") {
		t.Fatalf("expected 'hello vibecli' in SSE output, got: %s", out)
	}
	if !strings.Contains(out, `"type":"exit"`) {
		t.Fatalf("expected exit event, got: %s", out)
	}
}

func TestHandleExecExitCode(t *testing.T) {
	body, _ := json.Marshal(map[string]interface{}{
		"command": "cmd",
		"args":    []string{"/c", "exit 42"},
	})
	req := httptest.NewRequest(http.MethodPost, "/shell/exec", bytes.NewReader(body))
	w := httptest.NewRecorder()
	HandleExec(w, req)

	if !strings.Contains(w.Body.String(), `"code":42`) {
		t.Fatalf("expected exit code 42, got: %s", w.Body.String())
	}
}
