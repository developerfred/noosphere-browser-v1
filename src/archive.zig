//! Noosphere Archive Access
//! 
//! Wayback Machine and Google Cache fallback access.
//! For when sites block bots or content is behind paywalls.

const std = @import("std");
const http = @import("http.zig");

/// Archive source
pub const ArchiveSource = enum {
    wayback,
    google_cache,
    archive_is,
};

/// Archived page
pub const ArchivedPage = struct {
    url: []const u8,
    archive_url: []const u8,
    timestamp: ?[]const u8,
    available: bool,
    status: u16,
};

/// Archive access
pub const ArchiveAccess = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ArchiveAccess {
        return ArchiveAccess{ .allocator = allocator };
    }

    /// Check if URL is available in Wayback Machine
    pub fn waybackCheck(self: *ArchiveAccess, url: []const u8) !ArchivedPage {
        const archive_url = try std.fmt.allocPrint(
            self.allocator,
            "https://archive.org/wayback/available?url={s}",
            .{url}
        );
        defer self.allocator.free(archive_url);

        const response = try http.fetch(archive_url);
        defer response.deinit();

        if (response.status != 200) {
            return ArchivedPage{
                .url = try self.allocator.dupe(u8, url),
                .archive_url = "",
                .timestamp = null,
                .available = false,
                .status = response.status,
            };
        }

        // Parse JSON response
        const parsed = try parseWaybackJson(self.allocator, response.body);
        
        return ArchivedPage{
            .url = try self.allocator.dupe(u8, url),
            .archive_url = parsed.archive_url,
            .timestamp = parsed.timestamp,
            .available = parsed.available,
            .status = 200,
        };
    }

    /// Get Wayback Machine snapshot URL
    pub fn waybackGet(self: *ArchiveAccess, url: []const u8, timestamp: []const u8) ![]const u8 {
        // Format: YYYYMMDDHHMMSS
        if (timestamp.len < 14) {
            return error.InvalidTimestamp;
        }

        return try std.fmt.allocPrint(
            self.allocator,
            "https://webcache.googleusercontent.com/search?q=cache:{s}",
            .{url}
        );
    }

    /// Get latest Wayback snapshot
    pub fn waybackLatest(self: *ArchiveAccess, url: []const u8) !ArchivedPage {
        const check = try self.waybackCheck(url);
        
        if (!check.available) {
            return check;
        }

        // Construct timestamp URL
        const ts = check.timestamp orelse "";
        
        // Build Wayback URL
        const year = ts[0..4];
        const month = ts[4..6];
        const day = ts[6..8];

        const wayback_url = try std.fmt.allocPrint(
            self.allocator,
            "https://webcache.googleusercontent.com/search?q=cache:{s}",
            .{url}
        );

        // Actually use Wayback CDX API
        const cdx_url = try std.fmt.allocPrint(
            self.allocator,
            "https://web.archive.org/cdx/search/cdx?url={s}&output=json&limit=1&fl=timestamp,original,statuscode",
            .{url}
        );
        defer self.allocator.free(cdx_url);

        const cdx_response = http.fetch(cdx_url) catch return check;
        defer cdx_response.deinit();

        // Parse CDX response (JSON array)
        // Format: [["timestamp","original","statuscode"],...]
        if (cdx_response.body.len < 10) {
            return check;
        }

        // Simple parse
        var ts_found: ?[]const u8 = null;
        var status_found: u16 = 200;

        // Look for timestamp in response
        if (std.mem.indexOf(u8, cdx_response.body, "\"")) |start| {
            const content = cdx_response.body[start..];
            ts_found = extractJsonString(content, 0);
        }

        if (ts_found) |ts_str| {
            if (ts_str.len >= 14) {
                const final_url = try std.fmt.allocPrint(
                    self.allocator,
                    "https://web.archive.org/web/{s}/{s}",
                    .{ ts_str[0..14], url }
                );
                return ArchivedPage{
                    .url = try self.allocator.dupe(u8, url),
                    .archive_url = final_url,
                    .timestamp = try self.allocator.dupe(u8, ts_str[0..14]),
                    .available = true,
                    .status = 200,
                };
            }
        }

        return check;
    }

    /// Get Google Cache URL
    pub fn googleCache(self: *ArchiveAccess, url: []const u8) !ArchivedPage {
        const cache_url = try std.fmt.allocPrint(
            self.allocator,
            "https://webcache.googleusercontent.com/search?q=cache:{s}",
            .{url}
        );

        return ArchivedPage{
            .url = try self.allocator.dupe(u8, url),
            .archive_url = cache_url,
            .timestamp = null,
            .available = true, // Assume available, check on fetch
            .status = 0, // Not fetched yet
        };
    }

    /// Try all archive sources
    pub fn tryAll(self: *ArchiveAccess, url: []const u8) !ArchivedPage {
        // Try Wayback first
        const wayback = self.waybackLatest(url) catch {
            return ArchivedPage{
                .url = try self.allocator.dupe(u8, url),
                .archive_url = "",
                .timestamp = null,
                .available = false,
                .status = 0,
            };
        };

        if (wayback.available) {
            return wayback;
        }

        // Fallback to Google Cache
        return self.googleCache(url);
    }
};

/// Parse Wayback availability response
fn parseWaybackJson(allocator: std.mem.Allocator, json: []const u8) !struct {
    archive_url: []const u8,
    timestamp: ?[]const u8,
    available: bool,
} {
    var archive_url: []const u8 = "";
    var timestamp: ?[]const u8 = null;
    var available = false;

    // Simple JSON parsing
    if (std.mem.indexOf(u8, json, "\"available\":true")) |_| {
        available = true;
    }

    if (std.mem.indexOf(u8, json, "\"archive_url\":\"")) |start| {
        const url_start = start + 15;
        if (std.mem.indexOf(u8, json[url_start..], "\"")) |end| {
            archive_url = json[url_start..url_start + end];
        }
    }

    if (std.mem.indexOf(u8, json, "\"timestamp\":\"")) |start| {
        const ts_start = start + 14;
        if (std.mem.indexOf(u8, json[ts_start..], "\"")) |end| {
            timestamp = json[ts_start..ts_start + end];
        }
    }

    return .{
        .archive_url = archive_url,
        .timestamp = timestamp,
        .available = available,
    };
}

/// Extract string from JSON array at index
fn extractJsonString(json: []const u8, index: usize) ?[]const u8 {
    var current_index: usize = 0;
    var in_string = false;
    var string_start: ?usize = null;

    for (json, 0..) |c, i| {
        if (c == '"' and (i == 0 or json[i-1] != '\\')) {
            if (in_string) {
                if (current_index == index) {
                    return json[string_start.?..i];
                }
                current_index += 1;
                string_start = null;
            } else {
                in_string = true;
                string_start = i + 1;
            }
        }
    }

    return null;
}
