//! Noosphere HTTP Cache
//! 
//! In-memory and disk caching for HTTP responses.
//! Reduces redundant requests and improves performance.

const std = @import("std");
const fs = std.fs;

/// Cache entry
pub const CacheEntry = struct {
    key: []const u8,
    data: []u8,
    headers: []u8,
    status_code: u16,
    created_at: i64,
    expires_at: i64,
    etag: ?[]const u8,
    last_modified: ?[]const u8,
};

/// HTTP cache
pub const HTTPCache = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(CacheEntry),
    max_size_bytes: usize,
    current_size: usize,
    cache_dir: ?[]const u8,
    hits: u64,
    misses: u64,

    pub fn init(allocator: std.mem.Allocator, max_size_mb: usize) HTTPCache {
        return HTTPCache{
            .allocator = allocator,
            .entries = std.StringHashMap(CacheEntry).init(allocator),
            .max_size_bytes = max_size_mb * 1024 * 1024,
            .current_size = 0,
            .cache_dir = null,
            .hits = 0,
            .misses = 0,
        };
    }

    pub fn deinit(self: *HTTPCache) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.data);
            self.allocator.free(entry.value_ptr.headers);
        }
        self.entries.deinit();
    }

    /// Set cache directory for persistence
    pub fn setCacheDir(self: *HTTPCache, dir: []const u8) !void {
        try fs.cwd().makeDir(dir);
        self.cache_dir = try self.allocator.dupe(u8, dir);
    }

    /// Get cached response
    pub fn get(self: *HTTPCache, url: []const u8) ?*const CacheEntry {
        const entry = self.entries.get(url) orelse {
            self.misses += 1;
            return null;
        };

        // Check expiration
        const now = std.time.timestamp();
        if (entry.expires_at > 0 and entry.expires_at < now) {
            // Expired
            self.remove(url);
            self.misses += 1;
            return null;
        }

        self.hits += 1;
        return entry;
    }

    /// Store response in cache
    pub fn put(self: *HTTPCache, url: []const u8, data: []const u8, headers: []const u8, status_code: u16, max_age: u32) !void {
        // Check if we need to evict
        while (self.current_size + data.len > self.max_size_bytes) {
            if (!self.evictOldest()) break;
        }

        // Parse cache-control for expiration
        var max_age_sec = max_age;
        if (parseMaxAge(headers)) |parsed| {
            max_age_sec = parsed;
        }

        const now = std.time.timestamp();
        const expires_at = if (max_age_sec > 0) now + @as(i64, @intCast(max_age_sec)) else 0;

        // Extract etag and last-modified
        const etag = parseHeader(headers, "etag");
        const last_modified = parseHeader(headers, "last-modified");

        // Create entry
        var entry = CacheEntry{
            .key = try self.allocator.dupe(u8, url),
            .data = try self.allocator.dupe(u8, data),
            .headers = try self.allocator.dupe(u8, headers),
            .status_code = status_code,
            .created_at = now,
            .expires_at = expires_at,
            .etag = if (etag) |e| try self.allocator.dupe(u8, e) else null,
            .last_modified = if (last_modified) |lm| try self.allocator.dupe(u8, lm) else null,
        };

        // Remove old entry if exists
        if (self.entries.contains(url)) {
            self.remove(url);
        }

        try self.entries.put(entry.key, entry);
        self.current_size += data.len;

        // Persist to disk
        if (self.cache_dir) |dir| {
            try self.persistEntry(dir, &entry);
        }
    }

    /// Check if URL needs revalidation (304 handling)
    pub fn needsRevalidation(self: *HTTPCache, url: []const u8) bool {
        const entry = self.entries.get(url) orelse return false;
        return entry.etag != null or entry.last_modified != null;
    }

    /// Get cache headers for conditional request
    pub fn getConditionalHeaders(self: *HTTPCache, url: []const u8) ?[]const u8 {
        const entry = self.entries.get(url) orelse return null;

        if (entry.etag) |etag| {
            return etag;
        }

        if (entry.last_modified) |lm| {
            return lm;
        }

        return null;
    }

    /// Handle 304 Not Modified
    pub fn updateFrom304(self: *HTTPCache, url: []const u8, headers: []const u8) !void {
        var entry_ptr = self.entries.getPtr(url) orelse return;

        // Update expiration from new headers
        if (parseMaxAge(headers)) |max_age| {
            const now = std.time.timestamp();
            entry_ptr.expires_at = now + @as(i64, @intCast(max_age));
        }
    }

    /// Remove entry
    fn remove(self: *HTTPCache, url: []const u8) void {
        const entry = self.entries.get(url) orelse return;
        self.current_size -%= entry.data.len;
        self.allocator.free(entry.key);
        self.allocator.free(entry.data);
        self.allocator.free(entry.headers);
        if (entry.etag) |e| self.allocator.free(e);
        if (entry.last_modified) |lm| self.allocator.free(lm);
        self.entries.remove(url);
    }

    /// Evict oldest entry
    fn evictOldest(self: *HTTPCache) bool {
        var oldest: ?*CacheEntry = null;
        var oldest_key: ?[]const u8 = null;

        var it = self.entries.iterator();
        while (it.next()) |entry| {
            if (oldest == null or entry.value_ptr.created_at < oldest.?.created_at) {
                oldest = entry.value_ptr;
                oldest_key = entry.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            self.remove(key);
            return true;
        }

        return false;
    }

    /// Persist entry to disk
    fn persistEntry(self: *HTTPCache, dir: []const u8, entry: *const CacheEntry) !void {
        // Create safe filename from URL
        const safe_name = createSafeFilename(entry.key);
        const filepath = try std.fmt.allocPrint(self.allocator, "{s}/{s}.cache", .{ dir, safe_name });
        defer self.allocator.free(filepath);

        const file = try fs.cwd().createFile(filepath, .{});
        defer file.close();

        // Write header info
        try file.writeAll(entry.headers);
        try file.writeAll("\n\n");
        try file.writeAll(entry.data);
    }

    /// Load from disk cache
    pub fn loadFromDisk(self: *HTTPCache) !void {
        if (self.cache_dir == null) return;

        const dir = self.cache_dir.?;
        const cache_dir = try fs.cwd().openDir(dir, .{ .iterate = true });
        defer cache_dir.close();

        var it = cache_dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".cache")) {
                const filepath = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir, entry.name });
                defer self.allocator.free(filepath);

                const content = try fs.cwd().readFileAlloc(self.allocator, filepath, 10 * 1024 * 1024);

                // Find separator
                const sep = std.mem.indexOf(u8, content, "\n\n") orelse {
                    self.allocator.free(content);
                    continue;
                };

                const headers = content[0..sep];
                const data = content[sep + 2..];

                // Extract URL from headers
                if (parseHeader(headers, "x-cache-url")) |url| {
                    try self.put(url, data, headers, 200, 3600);
                }

                self.allocator.free(content);
            }
        }
    }

    /// Get cache statistics
    pub fn stats(self: *HTTPCache) CacheStats {
        return CacheStats{
            .entries = self.entries.count(),
            .size_bytes = self.current_size,
            .max_bytes = self.max_size_bytes,
            .hits = self.hits,
            .misses = self.misses,
            .hit_rate = if (self.hits + self.misses > 0)
                @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(self.hits + self.misses))
            else 0,
        };
    }

    /// Clear all cache
    pub fn clear(self: *HTTPCache) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.data);
            self.allocator.free(entry.value_ptr.headers);
        }
        self.entries.clear();
        self.current_size = 0;
        self.hits = 0;
        self.misses = 0;
    }
};

pub const CacheStats = struct {
    entries: usize,
    size_bytes: usize,
    max_bytes: usize,
    hits: u64,
    misses: u64,
    hit_rate: f64,
};

/// Cache control flags
pub const CacheControl = struct {
    max_age: ?u32,
    no_cache: bool,
    no_store: bool,
    must_revalidate: bool,
    private: bool,
    public: bool,
};

/// Parse cache-control header
pub fn parseCacheControl(header: []const u8) CacheControl {
    return CacheControl{
        .max_age = parseMaxAge(header),
        .no_cache = contains(header, "no-cache"),
        .no_store = contains(header, "no-store"),
        .must_revalidate = contains(header, "must-revalidate"),
        .private = contains(header, "private"),
        .public = contains(header, "public"),
    };
}

/// Parse max-age from headers
fn parseMaxAge(headers: []const u8) ?u32 {
    const max_age_pos = std.mem.indexOf(u8, headers, "max-age=") orelse return null;
    const start = max_age_pos + 8;
    var end = start;
    
    while (end < headers.len and std.ascii.isDigit(headers[end])) {
        end += 1;
    }

    if (end == start) return null;

    const num_str = headers[start..end];
    return std.fmt.parseInt(u32, num_str, 10) catch null;
}

/// Parse specific header
fn parseHeader(headers: []const u8, name: []const u8) ?[]const u8 {
    const search = try std.fmt.allocPrint(std.heap.page_allocator, "{s}: ", .{name});
    defer std.heap.page_allocator.free(search);

    const pos = std.mem.indexOf(u8, headers, search) orelse return null;
    const start = pos + search.len;
    var end = start;

    while (end < headers.len and headers[end] != '\n' and headers[end] != '\r') {
        end += 1;
    }

    return std.mem.trim(u8, headers[start..end], " \t");
}

/// Check if header contains value
fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

/// Create safe filename from URL
fn createSafeFilename(url: []const u8) []u8 {
    var result = std.ArrayList(u8);
    
    for (url) |c| {
        if (std.ascii.isAlphanumeric(c)) {
            result.append(c);
        } else {
            result.append('_');
        }
    }

    return result.items[0..@min(result.items.len, 64)];
}
