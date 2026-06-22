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
	return append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
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
	out, err := exec.Command("git", "-C", dir, "diff", base).Output()
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
