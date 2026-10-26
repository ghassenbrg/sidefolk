.PHONY: build test dev app run-dev render strings brand-assets clean

build:
	swift build

test:
	swift test --no-parallel

# Debug app with its own data folder (never your real Sidefolk data).
dev:
	scripts/build-app.sh debug
	pkill -f "Sidefolk-dev.app/Contents/MacOS/Sidefolk" || true
	mkdir -p build/dev-home
	SIDEFOLK_HOME="$(CURDIR)/build/dev-home" build/Sidefolk-dev.app/Contents/MacOS/Sidefolk > build/dev.log 2>&1 &
	@echo "Running build/Sidefolk-dev.app (log: build/dev.log, data: build/dev-home)"

app:
	scripts/build-app.sh release

# Collect strings to translate into Resources/Localization/Localizable.xcstrings.
strings:
	scripts/strings.sh

render:
	swift run sidefolk-render build/render

brand-assets:
	swift scripts/wordmark.swift
	swift run sidefolk-render --brand-mascot Resources/Brand/exports
	swift scripts/brand-assets.swift
	swift run sidefolk-render --menu-bar Resources/MenuBar
	swift scripts/brand-preview.swift

clean:
	rm -rf .build build
