DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

PROJECT   := Cadence.xcodeproj
SCHEME    := Cadence
BUILD_DIR := build
APP       := $(BUILD_DIR)/Build/Products/Release/Cadence.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(BUILD_DIR) -destination 'platform=macOS,arch=$(shell uname -m)' -quiet

.PHONY: project build test run install open clean

project:
	xcodegen generate --quiet

build: project
	$(XCODEBUILD) -configuration Release build

test: project
	$(XCODEBUILD) -configuration Debug test

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
