set shell := ["zsh", "-cu"]

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
    for file in examples/*.lx; do printf '\n== %s ==\n' "$file"; ./zig-out/bin/lx "$file"; done

docs:
    cd docs
    npm run docs:dev -- --open

clean:
    rm -rf .zig-cache zig-out
