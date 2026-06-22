package main

import (
	"encoding/json"
	"flag"
	"log"
	"net/http"

	"github.com/vibeide/vibecli/fs"
	"github.com/vibeide/vibecli/git"
	"github.com/vibeide/vibecli/middleware"
	"github.com/vibeide/vibecli/shell"
)

func main() {
	port := flag.String("port", "7700", "listen port")
	flag.Parse()

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handleHealth)
	mux.HandleFunc("GET /fs/tree", fs.HandleTree)
	mux.HandleFunc("GET /fs/read", fs.HandleRead)
	mux.HandleFunc("POST /fs/write", fs.HandleWrite)
	mux.HandleFunc("POST /fs/delete", fs.HandleDelete)
	mux.HandleFunc("GET /fs/watch", fs.HandleWatch)
	mux.HandleFunc("POST /shell/exec", shell.HandleExec)
	mux.HandleFunc("GET /shell/pty", shell.HandlePty)
	mux.HandleFunc("POST /git/clone", git.HandleClone)
	mux.HandleFunc("GET /git/status", git.HandleStatus)
	mux.HandleFunc("GET /git/diff", git.HandleDiff)
	mux.HandleFunc("GET /git/log", git.HandleLog)
	mux.HandleFunc("POST /git/commit", git.HandleCommit)
	mux.HandleFunc("POST /git/push", git.HandlePush)
	mux.HandleFunc("POST /git/checkout", git.HandleCheckout)

	log.Printf("vibecli listening on :%s", *port)
	log.Fatal(http.ListenAndServe("127.0.0.1:"+*port, middleware.CORS(mux)))
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "version": "1.0.0"})
}
