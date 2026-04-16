.PHONY: build install clean

SCHEME = ClaudeMeter
CONFIG = Release
PROJECT = ClaudeMeter.xcodeproj
BUILD_DIR = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -showBuildSettings 2>/dev/null | awk -F= '/ BUILT_PRODUCTS_DIR =/ { gsub(/^[ \t]+|[ \t]+$$/, "", $$2); print $$2 }')

build:
	@echo "Building ClaudeMeter..."
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) build 2>&1 | tail -3
	@echo "Done."

install: build
	@echo "Installing to /Applications..."
	@rm -rf /Applications/ClaudeMeter.app
	@cp -R "$(BUILD_DIR)/ClaudeMeter.app" /Applications/
	@echo "ClaudeMeter installed. Open from Spotlight (Cmd+Space → ClaudeMeter)"

clean:
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean 2>/dev/null
	@echo "Cleaned."
