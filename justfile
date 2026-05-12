default:
    just release

release:
    zig build release --release=fast

release-all:
    zig build all --release=fast
