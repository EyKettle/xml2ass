# 构建
build:
    zig build

# 测试
test:
    zig build test

# 运行
run:
    zig build run

# 发布构建
release:
    zig build all --release=fast

# 查看全部入口
default:
    just --list
