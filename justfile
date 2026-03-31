set shell := ["zsh", "-cu"]

default:
    just --list

build:
    zig build

test:
    zig build test

run *args:
    zig build run -- {{ args }}

lex file:
    zig build run -- {{ file }}

clean:
    rm -rf .zig-cache zig-out
