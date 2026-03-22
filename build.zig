{
    "name": "noosphere",
    "version": "0.1.0",
    "description": "Semantic-native browser for agents",
    "main": "src/main.zig",
    "dependencies": {
        "sqlite": "https://github.com/vrischmann/sqlite3.git",
        "zlm": "https://github.com/kivikakk/ziglm.git"
    },
    "build": {
        "target": "x86_64-unknown-linux-gnu+aarch64-unknown-linux-gnu",
        "optimize": "ReleaseFast"
    }
}
