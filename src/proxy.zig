//! Noosphere Proxy Rotation
//! 
//! Rotating proxy endpoints for avoiding rate limits and blocks.
//! Supports HTTP/SOCKS5 proxies with health checking.

const std = @import("std");
const http = @import("http.zig");

/// Proxy configuration
pub const ProxyConfig = struct {
    url: []const u8,
    username: ?[]const u8,
    password: ?[]const u8,
    health_check_url: []const u8 = "https://httpbin.org/ip",
    timeout_ms: u32 = 10000,
};

/// Proxy status
pub const ProxyStatus = enum {
    healthy,
    degraded,
    dead,
};

/// Proxy with health info
pub const Proxy = struct {
    config: ProxyConfig,
    status: ProxyStatus,
    latency_ms: u32,
    last_check: i64,
    success_count: u32,
    fail_count: u32,
};

/// Proxy pool manager
pub const ProxyPool = struct {
    allocator: std.mem.Allocator,
    proxies: std.ArrayList(Proxy),
    current_index: usize,
    rotation_mode: RotationMode,

    pub const RotationMode = enum {
        round_robin,
        random,
        least_latency,
        weighted,
    };

    pub fn init(allocator: std.mem.Allocator) ProxyPool {
        return ProxyPool{
            .allocator = allocator,
            .proxies = std.ArrayList(Proxy).init(allocator),
            .current_index = 0,
            .rotation_mode = .round_robin,
        };
    }

    pub fn deinit(self: *ProxyPool) void {
        for (self.proxies.items) |*proxy| {
            self.allocator.free(proxy.config.url);
            if (proxy.config.username) |u| self.allocator.free(u);
            if (proxy.config.password) |p| self.allocator.free(p);
        }
        self.proxies.deinit();
    }

    /// Add a proxy to the pool
    pub fn add(self: *ProxyPool, config: ProxyConfig) !void {
        var proxy = Proxy{
            .config = .{
                .url = try self.allocator.dupe(u8, config.url),
                .username = if (config.username) |u| try self.allocator.dupe(u8, u) else null,
                .password = if (config.password) |p| try self.allocator.dupe(u8, p) else null,
                .health_check_url = try self.allocator.dupe(u8, config.health_check_url),
                .timeout_ms = config.timeout_ms,
            },
            .status = .healthy,
            .latency_ms = 0,
            .last_check = std.time.timestamp(),
            .success_count = 0,
            .fail_count = 0,
        };

        try self.proxies.append(proxy);
    }

    /// Get next proxy based on rotation mode
    pub fn getProxy(self: *ProxyPool) ?*Proxy {
        if (self.proxies.items.len == 0) return null;

        switch (self.rotation_mode) {
            .round_robin => {
                const proxy = &self.proxies.items[self.current_index];
                self.current_index = (self.current_index + 1) % self.proxies.items.len;
                return proxy;
            },
            .random => {
                const index = std.crypto.random.intRangeAtMost(usize, 0, self.proxies.items.len - 1);
                return &self.proxies.items[index];
            },
            .least_latency => {
                var best: ?*Proxy = null;
                var best_latency: u32 = std.math.maxInt(u32);

                for (self.proxies.items) |*proxy| {
                    if (proxy.status == .healthy and proxy.latency_ms < best_latency) {
                        best_latency = proxy.latency_ms;
                        best = proxy;
                    }
                }

                return best;
            },
            .weighted => {
                var best: ?*Proxy = null;
                var best_score: f32 = -1;

                for (self.proxies.items) |*proxy| {
                    if (proxy.status == .healthy) {
                        // Score = success_rate / latency
                        const success_rate = @as(f32, @floatFromInt(proxy.success_count)) / 
                            @as(f32, @floatFromInt(proxy.success_count + proxy.fail_count + 1));
                        const score = success_rate * 1000.0 / @as(f32, @floatFromInt(proxy.latency_ms + 1));
                        
                        if (score > best_score) {
                            best_score = score;
                            best = proxy;
                        }
                    }
                }

                return best;
            },
        }
    }

    /// Check proxy health
    pub fn checkHealth(self: *ProxyPool, proxy: *Proxy) !void {
        const start = std.time.milliTimestamp();

        // Simple health check - try to connect
        const response = http.fetch(proxy.config.health_check_url);

        proxy.latency_ms = @as(u32, @intCast(std.time.milliTimestamp() - start));
        proxy.last_check = std.time.timestamp();

        if (response.status == 200) {
            proxy.status = .healthy;
            proxy.success_count += 1;
        } else {
            proxy.status = .degraded;
            proxy.fail_count += 1;
        }
    }

    /// Check all proxies
    pub fn checkAll(self: *ProxyPool) !void {
        for (self.proxies.items) |*proxy| {
            self.checkHealth(proxy) catch {
                proxy.status = .dead;
                proxy.fail_count += 1;
            };
        }
    }

    /// Mark proxy as failed
    pub fn markFailed(self: *ProxyPool, proxy: *Proxy) void {
        proxy.fail_count += 1;
        
        // If too many failures, mark as dead
        if (proxy.fail_count > 10) {
            proxy.status = .dead;
        } else if (proxy.fail_count > 3) {
            proxy.status = .degraded;
        }
    }

    /// Mark proxy as successful
    pub fn markSuccess(self: *ProxyPool, proxy: *Proxy) void {
        proxy.success_count += 1;
        proxy.status = .healthy;
        
        // Reset failure count on success
        proxy.fail_count = 0;
    }

    /// Get healthy proxy count
    pub fn healthyCount(self: *ProxyPool) usize {
        var count: usize = 0;
        for (self.proxies.items) |proxy| {
            if (proxy.status == .healthy) count += 1;
        }
        return count;
    }

    /// Remove dead proxies
    pub fn removeDead(self: *ProxyPool) void {
        var i: usize = 0;
        while (i < self.proxies.items.len) {
            if (self.proxies.items[i].status == .dead) {
                const proxy = self.proxies.orderedRemove(i);
                self.allocator.free(proxy.config.url);
                if (proxy.config.username) |u| self.allocator.free(u);
                if (proxy.config.password) |p| self.allocator.free(p);
            } else {
                i += 1;
            }
        }
    }

    /// Fetch through proxy
    pub fn fetchThroughProxy(self: *ProxyPool, url: []const u8) !void {
        const proxy = self.getProxy() orelse return error.NoHealthyProxy;

        // TODO: Implement proxy HTTP client
        // For now, just mark attempt
        _ = proxy;

        // if success: markSuccess
        // if fail: markFailed
    }
};
