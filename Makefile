APP_NAME      := OpenGestures
BUNDLE_ID     := io.github.rafaelcaetite.opengestures
VERSION       := $(shell sed -n 's/.*current = "\(.*\)"/\1/p' Sources/OpenGestures/Version.swift)
PREFIX        ?= $(HOME)/Applications
BIN_DIR       ?= $(HOME)/.local/bin
SIGN_IDENTITY ?= -
ARCHS         ?= $(shell uname -m)

BUILD_DIR := .build
APP_DIR   := $(BUILD_DIR)/$(APP_NAME).app
BINARY    := $(BUILD_DIR)/$(APP_NAME)-universal

# Swift Testing lives outside the default search paths when only the Command
# Line Tools are installed. Xcode needs none of this.
CLT := /Library/Developer/CommandLineTools
ifeq ($(shell xcode-select -p 2>/dev/null),$(CLT))
TEST_FLAGS := -Xswiftc -F$(CLT)/Library/Developer/Frameworks \
              -Xlinker -F$(CLT)/Library/Developer/Frameworks \
              -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/Frameworks \
              -Xlinker -rpath -Xlinker $(CLT)/Library/Developer/usr/lib
endif

# Ad-hoc builds pin the designated requirement to the bundle identifier, so
# the Accessibility permission survives rebuilds. Real identities keep their
# own requirement and get the hardened runtime.
ifeq ($(SIGN_IDENTITY),-)
SIGN_FLAGS := --requirements '=designated => identifier "$(BUNDLE_ID)"'
else
SIGN_FLAGS := --options runtime --timestamp
endif

.PHONY: all app build test install uninstall link zip clean

all: app

build:
	@for arch in $(ARCHS); do \
		swift build -c release --triple $$arch-apple-macosx13.0 || exit 1; \
	done
	lipo -create -output $(BINARY) $(foreach arch,$(ARCHS),$(BUILD_DIR)/$(arch)-apple-macosx/release/$(APP_NAME))
	strip -Sx $(BINARY)

app: build
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources
	cp $(BINARY) $(APP_DIR)/Contents/MacOS/$(APP_NAME)
	cp -R Resources/*.lproj $(APP_DIR)/Contents/Resources/
	sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist > $(APP_DIR)/Contents/Info.plist
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) $(APP_DIR)
	@echo "Built $(APP_DIR) $(VERSION) ($(ARCHS))"

test:
	swift test $(TEST_FLAGS)

install: app
	@osascript -e 'tell application id "$(BUNDLE_ID)" to quit' >/dev/null 2>&1 || true
	@sleep 1
	mkdir -p "$(PREFIX)"
	rm -rf "$(PREFIX)/$(APP_NAME).app"
	ditto $(APP_DIR) "$(PREFIX)/$(APP_NAME).app"
	open "$(PREFIX)/$(APP_NAME).app"
	@echo "Installed to $(PREFIX)/$(APP_NAME).app"

link:
	mkdir -p "$(BIN_DIR)"
	ln -sf "$(PREFIX)/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" "$(BIN_DIR)/opengestures"
	@echo "Linked $(BIN_DIR)/opengestures"

uninstall:
	@osascript -e 'tell application id "$(BUNDLE_ID)" to quit' >/dev/null 2>&1 || true
	-launchctl bootout gui/$$(id -u)/$(BUNDLE_ID) 2>/dev/null
	rm -f "$(HOME)/Library/LaunchAgents/$(BUNDLE_ID).plist"
	rm -rf "$(PREFIX)/$(APP_NAME).app"
	rm -f "$(BIN_DIR)/opengestures"
	@echo "Removed. Settings remain in ~/.config/opengestures."
	@echo "Also remove OpenGestures from System Settings > Privacy & Security > Accessibility."

zip: app
	cd $(BUILD_DIR) && ditto -c -k --keepParent $(APP_NAME).app $(APP_NAME)-$(VERSION).zip
	@echo "$(BUILD_DIR)/$(APP_NAME)-$(VERSION).zip"

clean:
	rm -rf $(BUILD_DIR)
