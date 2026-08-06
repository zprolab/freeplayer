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
FLAGS   := -std=c++17 -fobjc-arc -Wall -Wextra -O2 -g -mmacosx-version-min=13.0
ASANFLAGS := -std=c++17 -fobjc-arc -Wall -Wextra -O0 -g -mmacosx-version-min=13.0 \
             -fsanitize=address -fno-omit-frame-pointer
LIBS    := -framework Cocoa -framework WebKit -framework AVFoundation \
           -framework CoreMedia -framework AudioToolbox -framework MediaPlayer \
           -framework ServiceManagement -lsqlite3

DIST    := ../dist

$(APP): $(SRCS)
	@mkdir -p build
	$(CXX) $(FLAGS) $(SRCS) $(LIBS) -o $(APP)

$(ASANAPP): $(SRCS)
	@mkdir -p build
	$(CXX) $(ASANFLAGS) $(SRCS) $(LIBS) -o $(ASANAPP)

$(BUNDLE): $(APP)
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources/web
	cp $(APP) $(BUNDLE)/Contents/MacOS/FreePlayer
	cp -R $(DIST)/. $(BUNDLE)/Contents/Resources/web/
	cp Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force --sign - $(BUNDLE)
	@echo "==> $(BUNDLE) ready"

run: $(APP)
	$(APP)

bundle: $(BUNDLE)

asan: $(ASANAPP)

run-app: $(BUNDLE)
	open $(BUNDLE)

clean:
	rm -rf build

.PHONY: run bundle asan run-app clean
