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
