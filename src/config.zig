//! Noosphere Configuration
//! 
//! Persistent configuration with environment variable support.
//! YAML/TOML/JSON config files.

const std = @import("std");
const fs = std.fs;

pub const Config = struct {
    http: HttpConfig,
    storage: StorageConfig,
    network: NetworkConfig,
    limits: LimitsConfig,
};

pub const HttpConfig = struct {
    user_agent: []const u8,
    timeout_ms: u32,
    max_redirects: u32,
    follow_location: bool,
};

pub const StorageConfig = struct {
    data_dir: []const u8,
    max_size_mb: u32,
    format: StorageFormat,
};

pub const StorageFormat = enum {
    json,
    sqlite,
    badger,
};

pub const NetworkConfig = struct {
    listen_addr: []const u8,
    listen_port: u16,
    peers: [][]const u8,
    enable_p2p: bool,
};

pub const LimitsConfig = struct {
    rate_limit_per_sec: u32,
    rate_limit_per_min: u32,
    rate_limit_per_hour: u32,
    max_entity_age_days: u32,
};

/// Default configuration
pub fn defaultConfig() Config {
    return Config{
        .http = .{
            .user_agent = "Noosphere/1.2.0 (https://noosphere.browser)",
            .timeout_ms = 30000,
            .max_redirects = 5,
            .follow_location = true,
        },
        .storage = .{
            .data_dir = "~/.noosphere",
            .max_size_mb = 1024,
            .format = .json,
        },
        .network = .{
            .listen_addr = "127.0.0.1",
            .listen_port = 8080,
            .peers = &.{},
            .enable_p2p = false,
        },
        .limits = .{
            .rate_limit_per_sec = 10,
            .rate_limit_per_min = 100,
            .rate_limit_per_hour = 1000,
            .max_entity_age_days = 90,
        },
    };
}

/// Load config from file
pub fn loadConfig(allocator: std.mem.Allocator, path: []const u8) !Config {
    var config = defaultConfig();

    // Read file
    const content = try fs.cwd().readFileAlloc(allocator, path, 1024 * 100);
    defer allocator.free(content);

    // Try JSON parse
    if (std.mem.endsWith(u8, path, ".json")) {
        return try parseJsonConfig(allocator, content);
    }

    return config;
}

/// Parse JSON config
fn parseJsonConfig(allocator: std.mem.Allocator, content: []const u8) !Config {
    var config = defaultConfig();

    // Simple JSON parsing - look for known keys
    if (std.mem.indexOf(u8, content, "\"user_agent\":")) |pos| {
        const start = pos + 13;
        if (start < content.len and content[start] == '"') {
            const value_start = start + 1;
            if (std.mem.indexOf(u8, content[value_start..], "\"")) |len| {
                config.http.user_agent = try allocator.dupe(u8, content[value_start..value_start + len]);
            }
        }
    }

    return config;
}

/// Load config from environment
pub fn loadFromEnv(allocator: std.mem.Allocator) Config {
    var config = defaultConfig();

    if (fs.getenv("NOOSPHERE_USER_AGENT")) |ua| {
        config.http.user_agent = ua;
    }

    if (fs.getenv("NOOSPHERE_TIMEOUT_MS")) |timeout| {
        config.http.timeout_ms = std.fmt.parseInt(u32, timeout, 10) catch 30000;
    }

    if (fs.getenv("NOOSPHERE_DATA_DIR")) |dir| {
        config.storage.data_dir = dir;
    }

    if (fs.getenv("NOOSPHERE_PORT")) |port| {
        config.network.listen_port = std.fmt.parseInt(u16, port, 10) catch 8080;
    }

    if (fs.getenv("NOOSPHERE_ENABLE_P2P")) |p2p| {
        config.network.enable_p2p = std.mem.eql(u8, p2p, "true") or std.mem.eql(u8, p2p, "1");
    }

    if (fs.getenv("NOOSPHERE_RATE_LIMIT_SEC")) |rls| {
        config.limits.rate_limit_per_sec = std.fmt.parseInt(u32, rls, 10) catch 10;
    }

    if (fs.getenv("NOOSPHERE_RATE_LIMIT_MIN")) |rlm| {
        config.limits.rate_limit_per_min = std.fmt.parseInt(u32, rlm, 10) catch 100;
    }

    return config;
}

/// Save config to file
pub fn saveConfig(config: *const Config, path: []const u8) !void {
    var content = std.ArrayList(u8).init(std.heap.page_allocator);
    const writer = content.writer();

    try writer.writeAll("{\n");
    try writer.print("  \"user_agent\": \"{s}\",\n", .{config.http.user_agent});
    try writer.print("  \"timeout_ms\": {d},\n", .{config.http.timeout_ms});
    try writer.print("  \"data_dir\": \"{s}\",\n", .{config.storage.data_dir});
    try writer.print("  \"port\": {d},\n", .{config.network.listen_port});
    try writer.print("  \"rate_limit_per_sec\": {d},\n", .{config.limits.rate_limit_per_sec});
    try writer.writeAll("}\n");

    try fs.cwd().writeFile(path, content.items);
}
