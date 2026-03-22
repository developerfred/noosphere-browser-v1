//! Noosphere Sitemap Parser
//! 
//! Parse XML sitemaps to discover pages on a website.
//! Alternative to direct crawling when sites block bots.

const std = @import("std");
const http = @import("http.zig");

/// Sitemap URL entry
pub const SitemapUrl = struct {
    loc: []const u8,
    lastmod: ?[]const u8,
    changefreq: ?ChangeFreq,
    priority: ?f32,
};

pub const ChangeFreq = enum {
    always,
    hourly,
    daily,
    weekly,
    monthly,
    yearly,
    never,
};

/// Parsed sitemap
pub const Sitemap = struct {
    urls: []SitemapUrl,
    sitemaps: [][]const u8, // Nested sitemaps
};

/// Sitemap parser
pub const SitemapParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SitemapParser {
        return SitemapParser{ .allocator = allocator };
    }

    /// Fetch and parse sitemap from URL
    pub fn parseUrl(self: *SitemapParser, sitemap_url: []const u8) !Sitemap {
        // Validate URL
        if (!std.mem.startsWith(u8, sitemap_url, "http://") and
            !std.mem.startsWith(u8, sitemap_url, "https://")) {
            return error.InvalidUrl;
        }

        const response = try http.fetch(sitemap_url);
        defer response.deinit();

        return self.parse(response.body);
    }

    /// Parse sitemap XML content
    pub fn parse(self: *SitemapParser, xml: []const u8) !Sitemap {
        var urls = std.ArrayList(SitemapUrl).init(self.allocator);
        var sitemaps = std.ArrayList([]const u8).init(self.allocator);
        defer urls.deinit();
        defer sitemaps.deinit();

        // Check if this is a sitemap index
        const is_index = std.mem.indexOf(u8, xml, "<sitemapindex") != null;

        // Parse line by line
        var current_url: ?SitemapUrl = null;

        const lines = std.mem.split(u8, xml, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");

            if (std.mem.startsWith(u8, trimmed, "<url>")) {
                current_url = SitemapUrl{
                    .loc = "",
                    .lastmod = null,
                    .changefreq = null,
                    .priority = null,
                };
            } else if (std.mem.startsWith(u8, trimmed, "<sitemap>")) {
                current_url = SitemapUrl{
                    .loc = "",
                    .lastmod = null,
                    .changefreq = null,
                    .priority = null,
                };
            } else if (std.mem.startsWith(u8, trimmed, "</url>") or
                       std.mem.startsWith(u8, trimmed, "</sitemap>")) {
                if (current_url) |url| {
                    if (url.loc.len > 0) {
                        if (is_index) {
                            try sitemaps.append(try self.allocator.dupe(u8, url.loc));
                        } else {
                            try urls.append(url);
                        }
                    }
                }
                current_url = null;
            } else if (current_url) |*url| {
                if (std.mem.startsWith(u8, trimmed, "<loc>")) {
                    url.loc = extractTagValue(trimmed, "loc");
                } else if (std.mem.startsWith(u8, trimmed, "<lastmod>")) {
                    url.lastmod = try self.allocator.dupe(u8, extractTagValue(trimmed, "lastmod"));
                } else if (std.mem.startsWith(u8, trimmed, "<changefreq>")) {
                    const freq_str = extractTagValue(trimmed, "changefreq");
                    url.changefreq = parseChangeFreq(freq_str);
                } else if (std.mem.startsWith(u8, trimmed, "<priority>")) {
                    const pri_str = extractTagValue(trimmed, "priority");
                    url.priority = std.fmt.parseFloat(f32, pri_str) catch null;
                }
            }
        }

        return Sitemap{
            .urls = try urls.toOwnedSlice(),
            .sitemaps = try sitemaps.toOwnedSlice(),
        };
    }

    /// Discover sitemaps for a domain
    pub fn discoverSitemaps(self: *SitemapParser, domain: []const u8) ![][]const u8 {
        var results = std.ArrayList([]const u8).init(self.allocator);

        // Common sitemap locations
        const locations = [_][]const u8{
            "/sitemap.xml",
            "/sitemap_index.xml",
            "/wp-sitemap.xml",
            "/sitemap/index.xml",
            "/sitemap.xml.gz",
            "/sitemap_index.xml.gz",
            "/sitemaps.xml",
        };

        for (locations) |loc| {
            const url = try std.fmt.allocPrint(self.allocator, "https://{s}{s}", .{ domain, loc });
            defer self.allocator.free(url);

            // Try to fetch
            const response = http.fetch(url) catch continue;
            defer response.deinit();

            if (response.status == 200) {
                try results.append(url);
                // Found sitemap, don't need to check more
                break;
            }
        }

        return results.toOwnedSlice();
    }
};

/// Extract value from XML tag
fn extractTagValue(line: []const u8, tag: []const u8) []const u8 {
    const start_tag = "<" ++ tag ++ ">";
    const end_tag = "</" ++ tag ++ ">";

    if (std.mem.indexOf(u8, line, start_tag)) |start| {
        const value_start = start + start_tag.len;
        if (std.mem.indexOf(u8, line[value_start..], end_tag)) |end| {
            return line[value_start..value_start + end];
        }
    }
    return "";
}

/// Parse changefreq string
fn parseChangeFreq(s: []const u8) ?ChangeFreq {
    if (std.mem.eql(u8, s, "always")) return .always;
    if (std.mem.eql(u8, s, "hourly")) return .hourly;
    if (std.mem.eql(u8, s, "daily")) return .daily;
    if (std.mem.eql(u8, s, "weekly")) return .weekly;
    if (std.mem.eql(u8, s, "monthly")) return .monthly;
    if (std.mem.eql(u8, s, "yearly")) return .yearly;
    if (std.mem.eql(u8, s, "never")) return .never;
    return null;
}
