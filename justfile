set shell := ["zsh", "-cu"]

default:
    just --list

build:
    zig build

test:
    zig build test --summary all

examples:
    zig build
    for file in examples/*.lx; do printf '\n== %s ==\n' "$file"; ./zig-out/bin/lx --ast-tree "$file"; done

run *args:
    zig build run -- {{ args }}

lex file:
    zig build run -- {{ file }}

clean:
    rm -rf .zig-cache zig-out
