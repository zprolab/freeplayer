# FreePlayer native shell
# Zero-dependency build: system WebKit + Cocoa + sqlite3
#
#   make            build the dev binary (build/FreePlayerShell)
#   make oz         build the size-optimized -Oz binary (build/FreePlayerShell-oz)
#   make bundle     build FreePlayer.app (needs ../dist from `vite build`)
#   make run        run the dev binary
#   make run-app    open the bundled app
#   make asan       AddressSanitizer build for debugging
#   make clean

APP     := build/FreePlayerShell
ASANAPP := build/FreePlayerShell-asan
OZAPP   := build/FreePlayerShell-oz
BUNDLE  := build/FreePlayer.app
SRCS    := src/main.mm src/bridge.mm src/scheme.mm src/db.mm src/metadata.mm src/tray.mm src/webview.mm src/pluginfs.mm src/paths.mm
CXX     := clang++
# Memory/size-oriented build: -Os + section separation + dead-strip shrink
# __TEXT/__DATA (smaller private footprint); release builds drop debug info.
FLAGS   := -std=c++17 -fobjc-arc -Wall -Wextra -Os -g0 \
           -ffunction-sections -fdata-sections \
           -Wl,-dead_strip -mmacosx-version-min=13.0
# -Oz profile: same structure, most-aggressive code-size optimization (shrinks
# __TEXT further at the cost of some runtime speed — for disk/DFU constrained
# distributions).
OZFLAGS := -std=c++17 -fobjc-arc -Wall -Wextra -Oz -g0 \
           -ffunction-sections -fdata-sections \
           -Wl,-dead_strip -mmacosx-version-min=13.0
ASANFLAGS := -std=c++17 -fobjc-arc -Wall -Wextra -O0 -g -mmacosx-version-min=13.0 \
             -fsanitize=address -fno-omit-frame-pointer
LIBS    := -framework Cocoa -framework WebKit -framework AVFoundation \
           -framework CoreMedia -framework AudioToolbox -framework MediaPlayer \
           -framework ServiceManagement -framework UserNotifications -framework UniformTypeIdentifiers -lsqlite3

DIST    := ../dist

# Which binary the bundle packages — override to ship a profile, e.g.
#   make bundle BIN=build/FreePlayerShell-oz
BIN ?= $(APP)

# Default goal is the dev binary (make, make run) — not the first rule
.DEFAULT_GOAL := $(APP)

$(APP): $(SRCS)
	@mkdir -p build
	$(CXX) $(FLAGS) $(SRCS) $(LIBS) -o $(APP)

$(ASANAPP): $(SRCS)
	@mkdir -p build
	$(CXX) $(ASANFLAGS) $(SRCS) $(LIBS) -o $(ASANAPP)

$(OZAPP): $(SRCS)
	@mkdir -p build
	$(CXX) $(OZFLAGS) $(SRCS) $(LIBS) -o $(OZAPP)

# bundle is PHONY: always repackage (cheap — web assets are a few hundred KB).
# A file-target bundle (the old `bundle: build/FreePlayer.app`) silently
# skipped after vite builds (H7) and poisoned the next run after a failure
# (#4) — an unconditional rebuild can't go stale or get stuck.
bundle: $(BIN)
	@test -d $(DIST) || (echo "==> missing $(DIST) — run 'npm run build' first" && exit 2)
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources/web
	cp $(BIN) $(BUNDLE)/Contents/MacOS/FreePlayer
	cp -R $(DIST)/. $(BUNDLE)/Contents/Resources/web/
	cp FreePlayer.icns $(BUNDLE)/Contents/Resources/FreePlayer.icns
	cp ../LICENSE $(BUNDLE)/Contents/Resources/LICENSE
	cp Info.plist $(BUNDLE)/Contents/Info.plist
	# Q12: hardened runtime for release bundles (ad-hoc identity)
	codesign --force --sign - --options runtime $(BUNDLE)
	@echo "==> $(BUNDLE) ready"

run: $(APP)
	$(APP)

asan: $(ASANAPP)

oz: $(OZAPP)

run-app: bundle
	open $(BUNDLE)

clean:
	rm -rf build

.PHONY: run bundle asan oz run-app clean
