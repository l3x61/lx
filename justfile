#set shell := ["zsh", "-cu"]

# List the available recipes.
default:
    just --list

# Build the lx binary
build:
    zig build

# Run lx with the given arguments
run *args:
    zig build run -- {{ args }}

# Launch the REPL
repl:
    ./repl.sh

# Run the inline test suite.
test:
    zig build test --summary all

# Build and execute every example program.
examples:
    zig build
    for file in examples/*.lx; do \
        printf "# File: %s\n" $file; \
        if command -v bat >/dev/null 2>&1; then \
            bat --style=plain --paging=never -l rb "$file"; \
        else \
            cat "$file"; \
        fi; \
        echo "# Output:"; \
        ./zig-out/bin/lx "$file"; \
        echo; \
    done

docker-build:
    docker build -t lx .

docker-transcript:
    docker run --rm lx

docker-run *args:
    docker run --rm lx {{ args }}

clean:
    rm -rf .zig-cache zig-out
