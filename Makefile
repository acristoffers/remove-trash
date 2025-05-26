all: build/share/man/man1/remove-trash.1

build:
	@mkdir -p build

build/remove-trash build/docgen: build $(shell find . -type f -name "*.go")
	go build -o build -ldflags="-s -w" ./...

build/share/man/man1/remove-trash.1: build/docgen
	@build/docgen

clean:
	@rm -rf build
