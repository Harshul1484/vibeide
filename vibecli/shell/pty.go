//go:build linux || darwin

package shell

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/exec"

	"github.com/creack/pty"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

func HandlePty(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("pty upgrade: %v", err)
		return
	}
	defer conn.Close()

	shell := "/bin/sh"
	if sh, err := exec.LookPath("bash"); err == nil {
		shell = sh
	}

	cmd := exec.Command(shell)
	cmd.Env = append(os.Environ(), "TERM=xterm-256color")

	ptmx, err := pty.Start(cmd)
	if err != nil {
		conn.WriteMessage(websocket.TextMessage, []byte("pty error: "+err.Error()))
		return
	}
	defer ptmx.Close()

	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := ptmx.Read(buf)
			if n > 0 {
				conn.WriteMessage(websocket.BinaryMessage, buf[:n])
			}
			if err != nil {
				return
			}
		}
	}()

	for {
		_, msg, err := conn.ReadMessage()
		if err != nil {
			break
		}
		var m struct {
			Type string `json:"type"`
			Data string `json:"data"`
			Cols uint16 `json:"cols"`
			Rows uint16 `json:"rows"`
		}
		if err := json.Unmarshal(msg, &m); err != nil {
			ptmx.Write(msg)
			continue
		}
		switch m.Type {
		case "input":
			ptmx.Write([]byte(m.Data))
		case "resize":
			pty.Setsize(ptmx, &pty.Winsize{Rows: m.Rows, Cols: m.Cols})
		}
	}
	cmd.Process.Kill()
}
