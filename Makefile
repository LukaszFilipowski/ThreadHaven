APP_NAME := ThreadHaven
APP := build/$(APP_NAME).app
INSTALL_DIR ?= $(HOME)/Applications

.PHONY: all build test app install run clean

all: app

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build -c release --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/"
	cp Resources/Info.plist "$(APP)/Contents/"
	cp -R Resources/*.lproj "$(APP)/Contents/Resources/"
	codesign --force --sign - "$(APP)"

install: app
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP)" "$(INSTALL_DIR)/"

run: install
	open "$(INSTALL_DIR)/$(APP_NAME).app"

clean:
	rm -rf .build build
