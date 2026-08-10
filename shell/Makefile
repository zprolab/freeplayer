# FreePlayer native shell
# Zero-dependency build: system WebKit + Cocoa + sqlite3
#
#   make            build the dev binary (build/FreePlayerShell)
#   make bundle     build FreePlayer.app (needs ../dist from `vite build`)
#   make run        run the dev binary
#   make run-app    open the bundled app
#   make asan       AddressSanitizer build for debugging
#   make clean

APP     := build/FreePlayerShell
ASANAPP := build/FreePlayerShell-asan
BUNDLE  := build/FreePlayer.app
SRCS    := src/main.mm src/bridge.mm src/scheme.mm src/db.mm src/metadata.mm src/tray.mm src/webview.mm
CXX     := clang++
# Memory/size-oriented build: -Os + section separation + dead-strip shrink
# __TEXT/__DATA (smaller private footprint); release builds drop debug info.
FLAGS   := -std=c++17 -fobjc-arc -Wall -Wextra -Os -g0 \
           -ffunction-sections -fdata-sections \
           -Wl,-dead_strip -mmacosx-version-min=13.0
ASANFLAGS := -std=c++17 -fobjc-arc -Wall -Wextra -O0 -g -mmacosx-version-min=13.0 \
             -fsanitize=address -fno-omit-frame-pointer
LIBS    := -framework Cocoa -framework WebKit -framework AVFoundation \
           -framework CoreMedia -framework AudioToolbox -framework MediaPlayer \
           -framework ServiceManagement -framework UserNotifications -framework UniformTypeIdentifiers -lsqlite3

DIST    := ../dist

# Default goal is the dev binary (make, make run) — not the first rule
.DEFAULT_GOAL := $(APP)

$(APP): $(SRCS)
	@mkdir -p build
	$(CXX) $(FLAGS) $(SRCS) $(LIBS) -o $(APP)

$(ASANAPP): $(SRCS)
	@mkdir -p build
	$(CXX) $(ASANFLAGS) $(SRCS) $(LIBS) -o $(ASANAPP)

# bundle is PHONY: always repackage (cheap — web assets are a few hundred KB).
# A file-target bundle (the old `bundle: build/FreePlayer.app`) silently
# skipped after vite builds (H7) and poisoned the next run after a failure
# (#4) — an unconditional rebuild can't go stale or get stuck.
bundle: $(APP)
	@test -d $(DIST) || (echo "==> missing $(DIST) — run 'npm run build' first" && exit 2)
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources/web
	cp $(APP) $(BUNDLE)/Contents/MacOS/FreePlayer
	cp -R $(DIST)/. $(BUNDLE)/Contents/Resources/web/
	cp ../LICENSE $(BUNDLE)/Contents/Resources/LICENSE
	cp Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force --sign - $(BUNDLE)
	@echo "==> $(BUNDLE) ready"

run: $(APP)
	$(APP)

asan: $(ASANAPP)

run-app: bundle
	open $(BUNDLE)

clean:
	rm -rf build

.PHONY: run bundle asan run-app clean
