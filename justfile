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

# Run the transcript
transcript:
    ./transcript.sh

# Build and execute every example program.
examples:
    zig build
    for file in examples/*.lx; do \
        printf "# File: %s\n" $file; \
        if command -v bat >/dev/null 2>&1; then \
            bat --style=plain --paging=never -l ml "$file"; \
        else \
            cat "$file"; \
        fi; \
        echo "# Output:"; \
        ./zig-out/bin/lx "$file"; \
        echo; \
    done

# Build the Docker image and open a shell inside it.
docker:
    docker build -t lx .
    docker run --rm -it --entrypoint /bin/bash lx

clean:
    rm -rf .zig-cache zig-out
