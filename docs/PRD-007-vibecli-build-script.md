# PRD-007: vibecli Build Script for linux/arm64

## Overview
Create a cross-compilation build script that produces a statically-linked `vibecli` binary for `linux/arm64` (Android/proot target).

## Goals
- Single shell script that produces `dist/vibecli-arm64`
- Binary is statically linked (no glibc dependency) via `CGO_ENABLED=0`
- Symbols stripped for minimal size (`-ldflags="-s -w"`)

## Non-Goals
- No Docker build environment
- No `linux/amd64` or `linux/x86` targets in this task
- No signing or packaging

## Requirements

### Build Environment
- Host: any OS with Go 1.22+ installed
- Target: `GOOS=linux GOARCH=arm64 CGO_ENABLED=0`

### Output
- `dist/vibecli-arm64` — ELF 64-bit LSB executable, ARM aarch64, statically linked

### Script `build.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Building vibecli for linux/arm64..."
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
  go build -ldflags="-s -w" -o dist/vibecli-arm64 .

echo "Binary size: $(du -sh dist/vibecli-arm64 | cut -f1)"
echo "Done: dist/vibecli-arm64"
```

## Acceptance Criteria
- [ ] `./build.sh` exits `0`
- [ ] `dist/vibecli-arm64` exists
- [ ] `file dist/vibecli-arm64` reports `ELF 64-bit LSB executable, ARM aarch64`
- [ ] All tests pass before build: `go test ./... -v`
- [ ] Binary size reported (expected ~5–8 MB)

## Files
| File | Action |
|------|--------|
| `build.sh` | Create |
| `dist/.gitkeep` | Create (track empty dist dir) |

## Next Step After This PRD
Copy `dist/vibecli-arm64` to `vibeide/android/app/src/main/assets/vibecli-arm64` before starting the Flutter plan.

## Dependencies
- PRD-001 through PRD-006 (all code complete and tests passing)
