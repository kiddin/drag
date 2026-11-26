APP     := Screech
VERSION := 1.0.0
BUILD   := $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

BUNDLE  := dist/$(APP).app
BINARY  := $(BUNDLE)/Contents/MacOS/$(APP)
ARCHIVE := dist/$(APP)-v$(VERSION).zip
# Universal binary, so the release zip runs on Apple Silicon and Intel Macs.
ARCHS   := --arch arm64 --arch x86_64
TARGET  := $(shell [ -w /Applications ] && echo /Applications || echo $(HOME)/Applications)

.PHONY: app run test install uninstall release previews icon demo samples clean

app:
	swift build -c release --product $(APP) $(ARCHS)
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp "$$(swift build -c release --product $(APP) $(ARCHS) --show-bin-path)/$(APP)" "$(BINARY)"
	strip -S -x "$(BINARY)"
	@if LC_ALL=C grep -aq "$(HOME)" "$(BINARY)"; then echo "error: $(BINARY) contains $(HOME)" >&2; exit 1; fi
	sed -e 's/__VERSION__/$(VERSION)/' -e 's/__BUILD__/$(BUILD)/' Resources/Info.plist > "$(BUNDLE)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/"
	cp -R Resources/Samples "$(BUNDLE)/Contents/Resources/Samples"
	codesign --force --sign - --options runtime --timestamp=none "$(BUNDLE)"

run: app
	"$(BINARY)"

test:
	swift test

install: app
	pkill -x $(APP) || true
	mkdir -p "$(TARGET)"
	rm -rf "$(TARGET)/$(APP).app"
	ditto "$(BUNDLE)" "$(TARGET)/$(APP).app"
	open "$(TARGET)/$(APP).app"

uninstall:
	for bundle in "/Applications/$(APP).app" "$(HOME)/Applications/$(APP).app"; do \
		[ -x "$$bundle/Contents/MacOS/$(APP)" ] && "$$bundle/Contents/MacOS/$(APP)" --unregister-login-item; \
		rm -rf "$$bundle"; \
	done
	pkill -x $(APP) || true

release: test app
	rm -rf dist/release "$(ARCHIVE)"
	mkdir -p "dist/release/$(APP)-v$(VERSION)"
	ditto "$(BUNDLE)" "dist/release/$(APP)-v$(VERSION)/$(APP).app"
	cp install.sh README.md "dist/release/$(APP)-v$(VERSION)/"
	cd dist/release && ditto -c -k --norsrc --noextattr --keepParent "$(APP)-v$(VERSION)" "../$(APP)-v$(VERSION).zip"
	rm -rf dist/release

previews:
	swift run -c release screech-render previews

icon:
	swift scripts/icon.swift

# docs/demo.mp4 (with sound) and docs/hand.png for the README. Needs ffmpeg.
# GitHub only plays video uploaded through its website, so the README links an uploaded copy.
demo:
	swift run -c release screech-render --demo .build/demo
	swift scripts/demo.swift .build/demo
	mkdir -p docs
	ffmpeg -loglevel error -y -framerate 30 -i .build/demo/frames/%05d.png -i .build/demo/audio.wav \
		-c:v libx264 -pix_fmt yuv420p -crf 26 -preset slow -c:a aac -b:a 160k -movflags +faststart -shortest docs/demo.mp4
	cp .build/demo/hand.png docs/hand.png

# Rebuild Resources/Samples from the original downloads (48 kHz mono 16-bit WAVs in SRC).
samples:
	python3 scripts/prepare_samples.py "$(SRC)" Resources/Samples

clean:
	rm -rf .build dist build
