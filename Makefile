VERSION   ?= dev
COMMIT    := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
LDFLAGS   := -ldflags "-s -w -X main.version=$(VERSION) -X main.commit=$(COMMIT)"
BINARY    := cbnp
APP_NAME  := cbNP

.PHONY: all build run test lint clean app

all: lint test build

build:
	CGO_ENABLED=1 go build $(LDFLAGS) -o $(BINARY) ./cmd/cbnp

run: build
	./$(BINARY)

test:
	CGO_ENABLED=1 go test -race ./...

lint:
	golangci-lint run ./...

app: build
	bash scripts/build-app.sh $(BINARY) $(APP_NAME) $(VERSION)

clean:
	rm -f $(BINARY)
	rm -rf $(APP_NAME).app
	rm -rf dist/
