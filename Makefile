DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

PROJECT   := Cadence.xcodeproj
SCHEME    := Cadence
BUILD_DIR := build
APP       := $(BUILD_DIR)/Build/Products/Release/Cadence.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(BUILD_DIR) -destination 'platform=macOS,arch=$(shell uname -m)' -quiet

.PHONY: project build test screenshots icons run install open clean

project:
	xcodegen generate --quiet

build: project
	$(XCODEBUILD) -configuration Release build

test: project
	$(XCODEBUILD) -configuration Debug test

# Renders the README screenshots into docs/screenshots.
screenshots: project
	TEST_RUNNER_CADENCE_SCREENSHOTS=$(CURDIR)/docs/screenshots \
		$(XCODEBUILD) -configuration Debug test -only-testing:CadenceTests/ScreenshotTests

# Regenerates the app icon set from Resources/AppIcon-source.png.
icons:
	swift scripts/make-icons.swift Resources/AppIcon-source.png

run: build
	-pkill -x Cadence
	open $(APP)

# Launch at login works best from /Applications.
install: build
	-pkill -x Cadence
	rm -rf /Applications/Cadence.app
	cp -R $(APP) /Applications/
	open /Applications/Cadence.app

open: project
	open $(PROJECT)

clean:
	rm -rf $(BUILD_DIR) $(PROJECT)
