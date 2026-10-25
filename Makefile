APP := build/YouCam.app
SOURCES := $(wildcard Sources/*.swift)
CORE_SOURCES := $(filter-out Sources/main.swift,$(SOURCES))
TEST_SOURCES := $(wildcard Tests/*.swift)
ARCH := $(shell uname -m)
SWIFT_FLAGS := -swift-version 6 -target $(ARCH)-apple-macosx14.0
SIGN_IDENTITY ?= -

.PHONY: all run test smoke-test clean

all: $(APP)/Contents/MacOS/YouCam

$(APP)/Contents/MacOS/YouCam: $(SOURCES) Resources/Info.plist Resources/YouCam.entitlements Scripts/make-icon.swift Makefile
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources .build
	xcrun swiftc $(SWIFT_FLAGS) -O $(SOURCES) -o $@
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	xcrun swift Scripts/make-icon.swift .build/AppIcon.iconset
	xcrun iconutil -c icns .build/AppIcon.iconset -o $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign "$(SIGN_IDENTITY)" --options runtime --entitlements Resources/YouCam.entitlements $(APP)
	touch $@

run: all
	open $(APP)

test: .build/YouCamTests
	.build/YouCamTests

.build/YouCamTests: $(CORE_SOURCES) $(TEST_SOURCES) Makefile
	mkdir -p .build
	xcrun swiftc $(SWIFT_FLAGS) -g $(CORE_SOURCES) $(TEST_SOURCES) -o $@

smoke-test: all
	$(APP)/Contents/MacOS/YouCam --smoke-test

clean:
	rm -rf build .build
