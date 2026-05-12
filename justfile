native:
    zig build release --release=fast

release:
    zig build all --release=fast

default:
    just --list
