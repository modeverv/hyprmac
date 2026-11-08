CLT_FW := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_LIB := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
TEST_FLAGS := $(if $(wildcard $(CLT_FW)/Testing.framework),-Xswiftc -F -Xswiftc $(CLT_FW) -Xlinker -F -Xlinker $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_FW) -Xlinker -rpath -Xlinker $(CLT_LIB))

.PHONY: build app test run install clean

build:
	swift build --build-system native

test:
	swift test --build-system native $(TEST_FLAGS)

app:
	./scripts/build-app.sh

run: app
	./build/HyprMac.app/Contents/MacOS/HyprMac

install: app
	rm -rf /Applications/HyprMac.app
	cp -R build/HyprMac.app /Applications/
	@echo "installed /Applications/HyprMac.app"

clean:
	rm -rf .build build
