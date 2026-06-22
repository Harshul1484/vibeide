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
