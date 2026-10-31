APP_NAME := ThreadHaven
VERSION := $(shell cat VERSION)
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
ARCHS := arm64 x86_64
APP := build/$(APP_NAME).app
ZIP := build/$(APP_NAME)-$(VERSION).zip
INSTALL_DIR ?= $(HOME)/Applications
SIGN_IDENTITY ?= -
NOTARY_PROFILE ?= threadhaven

ifeq ($(SIGN_IDENTITY),-)
CODESIGN_FLAGS := --force --sign -
else
CODESIGN_FLAGS := --force --timestamp --options runtime --entitlements Resources/$(APP_NAME).entitlements --sign "$(SIGN_IDENTITY)"
endif

.PHONY: all build test stats app zip notarize install run clean

all: app

build:
	mkdir -p build
	for arch in $(ARCHS); do \
		swift build -c release --arch $$arch && \
		cp "$$(swift build -c release --arch $$arch --show-bin-path)/$(APP_NAME)" "build/$(APP_NAME)-$$arch" || exit 1; \
	done

test:
	swift test

stats:
	swift run -c release threadhaven-stats

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	lipo -create -output "$(APP)/Contents/MacOS/$(APP_NAME)" $(foreach arch,$(ARCHS),"build/$(APP_NAME)-$(arch)")
	cp Resources/Info.plist "$(APP)/Contents/"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/"
	cp -R Resources/*.lproj "$(APP)/Contents/Resources/"
	cp -R Resources/Web "$(APP)/Contents/Resources/"
	sips -s format png -Z 192 Resources/AppIcon.icns --out "$(APP)/Contents/Resources/Web/icon-192.png" >/dev/null
	sips -s format png -Z 512 Resources/AppIcon.icns --out "$(APP)/Contents/Resources/Web/icon-512.png" >/dev/null
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(APP)/Contents/Info.plist"
	plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" "$(APP)/Contents/Info.plist"
	codesign $(CODESIGN_FLAGS) "$(APP)"

zip: app
	rm -f "$(ZIP)"
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"

notarize: zip
	xcrun notarytool submit "$(ZIP)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP)"
	rm -f "$(ZIP)"
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"

install: app
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP)" "$(INSTALL_DIR)/"

run: install
	open "$(INSTALL_DIR)/$(APP_NAME).app"

clean:
	rm -rf .build build
