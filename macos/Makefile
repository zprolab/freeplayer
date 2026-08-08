# FreePlayer (SwiftUI) — build pipeline
#   make            swift build (debug)
#   make run        run the built binary directly
#   make bundle     build FreePlayer.app (release)
#   make run-app    open the bundled app
#   make clean

APP     := build/FreePlayer.app
BIN     := .build/release/FreePlayer

all: bundle

build:
	swift build -c release

$(BIN): build

$(APP): $(BIN)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BIN) $(APP)/Contents/MacOS/FreePlayer
	cp Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)
	@echo "==> $(APP) ready"

bundle: $(APP)

test:
	swift test

run: build
	$(BIN)

run-app: $(APP)
	open $(APP)

clean:
	rm -rf .build build

.PHONY: all build bundle test run run-app clean
