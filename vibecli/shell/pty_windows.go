//go:build windows

package shell

import (
	"net/http"
)

func HandlePty(w http.ResponseWriter, r *http.Request) {
	http.Error(w, "PTY not supported on Windows — runs on Android/Linux", http.StatusNotImplemented)
}
