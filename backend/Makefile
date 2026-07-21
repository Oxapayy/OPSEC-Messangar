BIN := opsec-backend
GO  := go

.PHONY: build run tidy test clean

build:
	CGO_ENABLED=0 $(GO) build -trimpath -ldflags '-s -w' -o $(BIN) .

run: build
	OPSEC_DATA_DIR=./_data ./$(BIN)

tidy:
	$(GO) mod tidy

test:
	$(GO) test ./...

clean:
	rm -f $(BIN)
	rm -rf _data
