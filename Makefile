APP_NAME := VoiceInput
BUNDLE_DIR := build/$(APP_NAME).app
EXECUTABLE := $(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)
RESOURCES := $(BUNDLE_DIR)/Contents/Resources
PLIST := $(BUNDLE_DIR)/Contents/Info.plist
SWIFT_SOURCES := $(wildcard Sources/VoiceInput/*.swift)
VFS_OVERLAY := .build/voiceinput-vfs-overlay.yaml
SDK := $(shell xcrun --sdk macosx --show-sdk-path)
FRAMEWORKS := -framework AppKit -framework ApplicationServices -framework AVFoundation -framework Carbon -framework Speech
SWIFTC_FLAGS := -O -parse-as-library -target arm64-apple-macosx14.0 -sdk $(SDK) -vfsoverlay $(VFS_OVERLAY) $(FRAMEWORKS)

.PHONY: build run install clean

$(VFS_OVERLAY): BuildSupport/empty-swift-module.modulemap
	mkdir -p .build
	printf '{\n  "version": 0,\n  "case-sensitive": "false",\n  "roots": [\n    {\n      "type": "file",\n      "name": "/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap",\n      "external-contents": "%s"\n    }\n  ]\n}\n' "$(CURDIR)/BuildSupport/empty-swift-module.modulemap" > $(VFS_OVERLAY)

build: $(VFS_OVERLAY)
	swift build -c release -Xswiftc -vfsoverlay -Xswiftc $(VFS_OVERLAY) || (mkdir -p .build/release && swiftc $(SWIFTC_FLAGS) $(SWIFT_SOURCES) -o .build/release/$(APP_NAME))
	rm -rf $(BUNDLE_DIR)
	mkdir -p $(RESOURCES) $(BUNDLE_DIR)/Contents/MacOS
	cp .build/release/$(APP_NAME) $(EXECUTABLE)
	cp Resources/Info.plist $(PLIST)
	codesign --force --deep --sign - $(BUNDLE_DIR)

run: build
	open $(BUNDLE_DIR)

install: build
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/$(APP_NAME).app
	cp -R $(BUNDLE_DIR) $(HOME)/Applications/$(APP_NAME).app
	codesign --force --deep --sign - $(HOME)/Applications/$(APP_NAME).app

clean:
	rm -rf .build build
