DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

PROJECT   := Cadence.xcodeproj
SCHEME    := Cadence
BUILD_DIR := build
APP       := $(BUILD_DIR)/Build/Products/Release/Cadence.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(BUILD_DIR) -destination 'platform=macOS,arch=$(shell uname -m)' -quiet

.PHONY: project build test dist screenshots icons run install open clean

project:
	xcodegen generate --quiet

build: project
	$(XCODEBUILD) -configuration Release build

test: project
	$(XCODEBUILD) -configuration Debug test

# Universal (arm64 + x86_64) Release build zipped for distribution, e.g.
#   make dist VERSION=0.2.0  ->  build/Cadence-0.2.0.zip
# Ad-hoc signed by default. To sign for notarization, pass e.g.
#   DIST_FLAGS='CADENCE_SIGN_IDENTITY="Developer ID Application" CADENCE_TEAM=ABCDE12345'
VERSION ?= $(shell awk -F'"' '/MARKETING_VERSION/ {print $$2}' project.yml)
BUILD_NUMBER ?= 1
DIST_FLAGS ?=
dist: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(BUILD_DIR) \
		-destination 'generic/platform=macOS' -configuration Release -quiet \
		MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) \
		ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp $(DIST_FLAGS) build
	rm -f $(BUILD_DIR)/Cadence-$(VERSION).zip
	ditto -c -k --sequesterRsrc --keepParent $(APP) $(BUILD_DIR)/Cadence-$(VERSION).zip

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
