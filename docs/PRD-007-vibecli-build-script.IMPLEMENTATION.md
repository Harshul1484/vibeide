# PRD-007 Implementation: vibecli Build Script for linux/arm64

## Working Directory
`d:\Projects\New folder\vibecli\.worktrees\vibecli-daemon`

## Steps

### Step 1: Run the Full Test Suite
```bash
go test ./... -v
```
Expected: all tests pass (skipping pty on Windows)

### Step 2: Create `dist/` directory and `.gitkeep`
```bash
mkdir -p dist
touch dist/.gitkeep
```

### Step 3: Write `build.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Building vibecli for linux/arm64..."
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
  go build -ldflags="-s -w" -o dist/vibecli-arm64 .

echo "Binary size: $(du -sh dist/vibecli-arm64 | cut -f1)"
echo "Done: dist/vibecli-arm64"
```

### Step 4: Run the Build Script
```bash
chmod +x build.sh
./build.sh
```
Expected output:
```
Building vibecli for linux/arm64...
Binary size: ~6M
Done: dist/vibecli-arm64
```

### Step 5: Verify Binary Architecture
```bash
file dist/vibecli-arm64
```
Expected: `dist/vibecli-arm64: ELF 64-bit LSB executable, ARM aarch64, statically linked`

### Step 6: Final Commit
```bash
git add build.sh dist/.gitkeep
git commit -m "build: cross-compile script for linux/arm64"
```

### Step 7: Copy Binary to Flutter Assets
```bash
cp dist/vibecli-arm64 ../../../vibeide/android/app/src/main/assets/vibecli-arm64
```

## Windows Note
On Windows, `build.sh` must be run in WSL, Git Bash, or a Linux container. PowerShell equivalent:
```powershell
$env:GOOS = "linux"
$env:GOARCH = "arm64"
$env:CGO_ENABLED = "0"
go build -ldflags="-s -w" -o dist/vibecli-arm64 .
```

## Verification Checklist
- [ ] All tests pass before build
- [ ] `dist/vibecli-arm64` produced
- [ ] File architecture verified as `ARM aarch64`
- [ ] Binary size logged
- [ ] Committed to `feature/vibecli-daemon` branch
- [ ] Binary copied to Flutter assets path
