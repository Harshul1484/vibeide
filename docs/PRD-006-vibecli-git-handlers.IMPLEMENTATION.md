# PRD-006 Implementation: vibecli Git Handlers

## Working Directory
`d:\Projects\New folder\vibecli\.worktrees\vibecli-daemon`

## Steps

### Step 1: Write the Failing Tests — `git/handler_test.go`
```go
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

### Step 2: Confirm Tests Fail
```bash
go test ./git/... -v
```
Expected: compilation error (`GitStatus` and `CommitRequest` not defined)

### Step 3: Write `git/handler.go`
(See full implementation in plan `2026-05-10-vibeide-vibecli.md` Task 6, Step 3)

Key types:
```go
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
```

### Step 4: Remove All Stubs from `git/stub.go`
Delete `git/stub.go` entirely — all handlers are now in `git/handler.go`.

### Step 5: Run Tests
```bash
go test ./git/... -v
```
Expected: `TestHandleStatus`, `TestHandleCommit`, `TestHandleCheckout` all `PASS`

### Step 6: Commit
```bash
git add git/
git commit -m "feat: git handlers (status, diff, log, commit, push, clone, checkout)"
```

## Verification Checklist
- [ ] `TestHandleStatus` passes (branch = main, untracked detected)
- [ ] `TestHandleCommit` passes (commit output contains message)
- [ ] `TestHandleCheckout` passes (branch switched to feature/x)
- [ ] `git/stub.go` deleted (no duplicate definitions)
- [ ] `GIT_TERMINAL_PROMPT=0` set in `gitEnv()` helper
