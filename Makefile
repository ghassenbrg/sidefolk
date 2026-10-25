.PHONY: build test dev app run-dev render clean

build:
	swift build

test:
	swift test

# Debug app with its own data folder (never your real Sidefolk data).
dev:
	scripts/build-app.sh debug
	pkill -f "Sidefolk-dev.app/Contents/MacOS/Sidefolk" || true
	mkdir -p build/dev-home
	SIDEFOLK_HOME="$(CURDIR)/build/dev-home" build/Sidefolk-dev.app/Contents/MacOS/Sidefolk > build/dev.log 2>&1 &
	@echo "Running build/Sidefolk-dev.app (log: build/dev.log, data: build/dev-home)"

app:
	scripts/build-app.sh release

render:
	swift run sidefolk-render build/render

clean:
	rm -rf .build build
