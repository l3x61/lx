#set shell := ["zsh", "-cu"]

default:
    just --list

build:
    zig build

run *args:
    zig build run -- {{ args }}

repl:
    ./repl.sh

test:
    zig build test --summary all

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

clean:
    rm -rf .zig-cache zig-out
