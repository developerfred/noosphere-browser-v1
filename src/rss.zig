//! Noosphere RSS/Atom Feed Parser
//! 
//! Parse RSS and Atom feeds for alternative content access.
//! Many sites offer RSS feeds as an alternative to HTML scraping.

const std = @import("std");
const http = @import("http.zig");

/// Feed item
pub const FeedItem = struct {
    title: []const u8,
    link: []const u8,
    description: []const u8,
    pub_date: ?[]const u8,
    author: ?[]const u8,
    guid: ?[]const u8,
    categories: [][]const u8,
};

/// Feed type
pub const FeedType = enum {
    rss,
    atom,
    unknown,
};

/// Parsed feed
pub const Feed = struct {
    feed_type: FeedType,
    title: []const u8,
    link: []const u8,
    description: ?[]const u8,
    items: []FeedItem,
};

/// Feed parser
pub const FeedParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FeedParser {
        return FeedParser{ .allocator = allocator };
    }

    /// Fetch and parse feed from URL
    pub fn parseUrl(self: *FeedParser, feed_url: []const u8) !Feed {
        const response = try http.fetch(feed_url);
        defer response.deinit();

        return self.parse(response.body);
    }

    /// Detect feed type
    fn detectFeedType(xml: []const u8) FeedType {
        if (std.mem.indexOf(u8, xml, "<rss") != null) return .rss;
        if (std.mem.indexOf(u8, xml, "<feed") != null) return .atom;
        return .unknown;
    }

    /// Parse feed XML content
    pub fn parse(self: *FeedParser, xml: []const u8) !Feed {
        const feed_type = detectFeedType(xml);

        switch (feed_type) {
            .rss => return try self.parseRSS(xml),
            .atom => return try self.parseAtom(xml),
            .unknown => return error.UnknownFeedType,
        }
    }

    /// Parse RSS 2.0 feed
    fn parseRSS(self: *FeedParser, xml: []const u8) !Feed {
        var items = std.ArrayList(FeedItem).init(self.allocator);

        var feed = Feed{
            .feed_type = .rss,
            .title = "",
            .link = "",
            .description = null,
            .items = undefined,
        };

        var current_item: ?FeedItem = null;
        var in_item = false;

        const lines = std.mem.split(u8, xml, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");

            // Channel-level elements
            if (std.mem.startsWith(u8, trimmed, "<title>") and !in_item) {
                feed.title = extractTagValue(trimmed, "title");
            } else if (std.mem.startsWith(u8, trimmed, "<link>") and !in_item) {
                feed.link = extractTagValue(trimmed, "link");
            } else if (std.mem.startsWith(u8, trimmed, "<description>") and !in_item) {
                feed.description = try self.allocator.dupe(u8, extractTagValue(trimmed, "description"));
            }

            // Item elements
            if (std.mem.startsWith(u8, trimmed, "<item>")) {
                in_item = true;
                current_item = FeedItem{
                    .title = "",
                    .link = "",
                    .description = "",
                    .pub_date = null,
                    .author = null,
                    .guid = null,
                    .categories = &.{},
                };
            } else if (std.mem.startsWith(u8, trimmed, "</item>")) {
                in_item = false;
                if (current_item) |item| {
                    try items.append(item);
                }
                current_item = null;
            } else if (current_item) |*item| {
                if (std.mem.startsWith(u8, trimmed, "<title>")) {
                    item.title = extractTagValue(trimmed, "title");
                } else if (std.mem.startsWith(u8, trimmed, "<link>")) {
                    item.link = extractTagValue(trimmed, "link");
                } else if (std.mem.startsWith(u8, trimmed, "<description>")) {
                    item.description = extractTagValue(trimmed, "description");
                } else if (std.mem.startsWith(u8, trimmed, "<pubDate>")) {
                    item.pub_date = try self.allocator.dupe(u8, extractTagValue(trimmed, "pubDate"));
                } else if (std.mem.startsWith(u8, trimmed, "<author>") or
                           std.mem.startsWith(u8, trimmed, "<dc:creator>")) {
                    item.author = try self.allocator.dupe(u8, extractTagValue(trimmed, "author"));
                } else if (std.mem.startsWith(u8, trimmed, "<guid>")) {
                    item.guid = try self.allocator.dupe(u8, extractTagValue(trimmed, "guid"));
                }
            }
        }

        feed.items = try items.toOwnedSlice();
        return feed;
    }

    /// Parse Atom feed
    fn parseAtom(self: *FeedParser, xml: []const u8) !Feed {
        var items = std.ArrayList(FeedItem).init(self.allocator);

        var feed = Feed{
            .feed_type = .atom,
            .title = "",
            .link = "",
            .description = null,
            .items = undefined,
        };

        var current_item: ?FeedItem = null;
        var in_entry = false;

        const lines = std.mem.split(u8, xml, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");

            // Feed-level elements
            if (std.mem.startsWith(u8, trimmed, "<title>") and !in_entry) {
                feed.title = extractTagValue(trimmed, "title");
            } else if (std.mem.startsWith(u8, trimmed, "<subtitle>")) {
                feed.description = try self.allocator.dupe(u8, extractTagValue(trimmed, "subtitle"));
            }

            // Entry elements
            if (std.mem.startsWith(u8, trimmed, "<entry>")) {
                in_entry = true;
                current_item = FeedItem{
                    .title = "",
                    .link = "",
                    .description = "",
                    .pub_date = null,
                    .author = null,
                    .guid = null,
                    .categories = &.{},
                };
            } else if (std.mem.startsWith(u8, trimmed, "</entry>")) {
                in_entry = false;
                if (current_item) |item| {
                    try items.append(item);
                }
                current_item = null;
            } else if (current_item) |*item| {
                if (std.mem.startsWith(u8, trimmed, "<title>")) {
                    item.title = extractTagValue(trimmed, "title");
                } else if (std.mem.startsWith(u8, trimmed, "<link href=\"")) {
                    // Atom link
                    if (std.mem.indexOf(u8, trimmed, "rel=\"alternate\"")) |_| {
                        const href_start = std.mem.indexOf(u8, trimmed, "href=\"").? + 6;
                        const href_end = std.mem.indexOf(u8, trimmed[href_start..], "\"").?;
                        item.link = trimmed[href_start..href_start + href_end];
                    }
                } else if (std.mem.startsWith(u8, trimmed, "<summary>") or
                           std.mem.startsWith(u8, trimmed, "<content>")) {
                    item.description = extractTagValue(trimmed, if (std.mem.startsWith(u8, trimmed, "<summary")) "summary" else "content");
                } else if (std.mem.startsWith(u8, trimmed, "<updated>") or
                           std.mem.startsWith(u8, trimmed, "<published>")) {
                    const tag = if (std.mem.startsWith(u8, trimmed, "<updated")) "updated" else "published";
                    item.pub_date = try self.allocator.dupe(u8, extractTagValue(trimmed, tag));
                } else if (std.mem.startsWith(u8, trimmed, "<name>")) {
                    item.author = try self.allocator.dupe(u8, extractTagValue(trimmed, "name"));
                } else if (std.mem.startsWith(u8, trimmed, "<id>")) {
                    item.guid = try self.allocator.dupe(u8, extractTagValue(trimmed, "id"));
                }
            }
        }

        feed.items = try items.toOwnedSlice();
        return feed;
    }

    /// Discover feeds on a website
    pub fn discoverFeeds(self: *FeedParser, domain: []const u8) ![][]const u8 {
        var results = std.ArrayList([]const u8).init(self.allocator);

        // Common feed locations
        const locations = [_][]const u8{
            "/feed",
            "/feed/",
            "/feed.xml",
            "/rss.xml",
            "/atom.xml",
            "/index.xml",
            "/blog/feed",
            "/posts/feed",
            "/feed/rss",
            "/feed/atom",
        };

        for (locations) |loc| {
            const url = try std.fmt.allocPrint(self.allocator, "https://{s}{s}", .{ domain, loc });
            defer self.allocator.free(url);

            const response = http.fetch(url) catch continue;
            defer response.deinit();

            if (response.status == 200) {
                const content_type = response.headers.get("content-type") orelse "";
                if (std.mem.indexOf(u8, content_type, "xml") != null or
                    std.mem.indexOf(u8, content_type, "rss") != null or
                    std.mem.indexOf(u8, content_type, "atom") != null) {
                    try results.append(url);
                }
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
