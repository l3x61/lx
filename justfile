#set shell := ["zsh", "-cu"]

default:
    just --list

run *args:
    zig build run -- {{ args }}

repl:
    zig build run --

test:
    zig build test --summary all

examples:
    zig build
    for file in examples/*.lx; do \
        if command -v bat >/dev/null 2>&1; then \
            bat --paging=never -l rb "$file"; \
        else \
            cat "$file"; \
        fi; \
        ./zig-out/bin/lx "$file"; \
    done

clean:
    rm -rf .zig-cache zig-out
