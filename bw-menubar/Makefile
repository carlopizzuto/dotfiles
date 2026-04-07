# BWMenuBar — macOS menubar Bitwarden client
# Build, install, and packaging targets

APP_NAME    := BWMenuBar
BUNDLE_ID   := com.carlopizzuto.bw-menubar
INSTALL_DIR := $(HOME)/Applications
APP_BUNDLE  := $(INSTALL_DIR)/$(APP_NAME).app
PLIST_DIR   := $(HOME)/Library/LaunchAgents
PLIST_NAME  := $(BUNDLE_ID).plist

.PHONY: build run install uninstall clean

build:
	swift build -c release

run:
	swift run

install: build
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$$(swift build --show-bin-path -c release)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0">\n\
<dict>\n\
  <key>CFBundleName</key>\n\
  <string>$(APP_NAME)</string>\n\
  <key>CFBundleIdentifier</key>\n\
  <string>$(BUNDLE_ID)</string>\n\
  <key>CFBundleExecutable</key>\n\
  <string>$(APP_NAME)</string>\n\
  <key>CFBundleVersion</key>\n\
  <string>1.0</string>\n\
  <key>LSMinimumSystemVersion</key>\n\
  <string>14.0</string>\n\
  <key>LSUIElement</key>\n\
  <true/>\n\
</dict>\n\
</plist>\n' > "$(APP_BUNDLE)/Contents/Info.plist"
	@mkdir -p "$(PLIST_DIR)"
	@printf '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0">\n\
<dict>\n\
  <key>Label</key>\n\
  <string>$(BUNDLE_ID)</string>\n\
  <key>ProgramArguments</key>\n\
  <array>\n\
    <string>$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)</string>\n\
  </array>\n\
  <key>RunAtLoad</key>\n\
  <true/>\n\
  <key>KeepAlive</key>\n\
  <false/>\n\
</dict>\n\
</plist>\n' > "$(PLIST_DIR)/$(PLIST_NAME)"
	@echo "Installed to $(APP_BUNDLE)"
	@echo "LaunchAgent written to $(PLIST_DIR)/$(PLIST_NAME)"
	@echo "Run: launchctl load $(PLIST_DIR)/$(PLIST_NAME)"

uninstall:
	-launchctl unload "$(PLIST_DIR)/$(PLIST_NAME)" 2>/dev/null
	rm -rf "$(APP_BUNDLE)"
	rm -f "$(PLIST_DIR)/$(PLIST_NAME)"
	@echo "Uninstalled $(APP_NAME)"

clean:
	swift package clean
