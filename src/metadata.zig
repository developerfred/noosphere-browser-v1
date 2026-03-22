//! Noosphere Metadata Extractor
//! 
//! Extract OpenGraph, Schema.org, Dublin Core, and other metadata.
//! For enriching pages with structured data.

const std = @import("std");

/// Page metadata
pub const PageMetadata = struct {
    title: ?[]const u8,
    description: ?[]const u8,
    keywords: ?[]const u8,
    author: ?[]const u8,
    published_time: ?[]const u8,
    modified_time: ?[]const u8,
    og_tags: OpenGraphTags,
    twitter_tags: TwitterTags,
    schema_data: ?[]const u8,
    dublin_core: DublinCoreTags,
    favicon: ?[]const u8,
    canonical_url: ?[]const u8,
};

pub const OpenGraphTags = struct {
    title: ?[]const u8,
    type: ?[]const u8,
    url: ?[]const u8,
    image: ?[]const u8,
    description: ?[]const u8,
    site_name: ?[]const u8,
    locale: ?[]const u8,
    video: ?[]const u8,
    audio: ?[]const u8,
};

pub const TwitterTags = struct {
    card: ?[]const u8,
    site: ?[]const u8,
    creator: ?[]const u8,
    title: ?[]const u8,
    description: ?[]const u8,
    image: ?[]const u8,
};

pub const DublinCoreTags = struct {
    title: ?[]const u8,
    creator: ?[]const u8,
    subject: ?[]const u8,
    description: ?[]const u8,
    publisher: ?[]const u8,
    contributor: ?[]const u8,
    date: ?[]const u8,
    format: ?[]const u8,
    identifier: ?[]const u8,
    source: ?[]const u8,
    language: ?[]const u8,
    relation: ?[]const u8,
    coverage: ?[]const u8,
    rights: ?[]const u8,
};

/// Metadata extractor
pub const MetadataExtractor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MetadataExtractor {
        return MetadataExtractor{ .allocator = allocator };
    }

    /// Extract all metadata from HTML
    pub fn extract(self: *MetadataExtractor, html: []const u8, base_url: []const u8) !PageMetadata {
        return PageMetadata{
            .title = try self.extractTitle(html),
            .description = try self.extractDescription(html),
            .keywords = self.extractMeta(html, "keywords"),
            .author = self.extractMeta(html, "author"),
            .published_time = self.extractMeta(html, "article:published_time") orelse
                             self.extractMeta(html, "date-published"),
            .modified_time = self.extractMeta(html, "article:modified_time") orelse
                            self.extractMeta(html, "date-modified"),
            .og_tags = try self.extractOpenGraph(html),
            .twitter_tags = try self.extractTwitter(html),
            .schema_data = try self.extractSchema(html),
            .dublin_core = try self.extractDublinCore(html),
            .favicon = try self.extractFavicon(html, base_url),
            .canonical_url = self.extractCanonical(html),
        };
    }

    /// Extract page title
    fn extractTitle(self: *MetadataExtractor, html: []const u8) !?[]const u8 {
        // Try og:title first
        if (self.extractOgTag(html, "og:title")) |og_title| {
            return og_title;
        }

        // Then twitter:title
        if (self.extractTwitterTag(html, "twitter:title")) |tw_title| {
            return tw_title;
        }

        // Then <title>
        if (findTagContent(html, "title")) |title| {
            return stripTags(title);
        }

        return null;
    }

    /// Extract description
    fn extractDescription(self: *MetadataExtractor, html: []const u8) !?[]const u8 {
        // Try og:description
        if (self.extractOgTag(html, "og:description")) |og_desc| {
            return og_desc;
        }

        // Try twitter:description
        if (self.extractTwitterTag(html, "twitter:description")) |tw_desc| {
            return tw_desc;
        }

        // Try meta description
        if (self.extractMeta(html, "description")) |meta_desc| {
            return meta_desc;
        }

        return null;
    }

    /// Extract meta tag by property/name
    fn extractMeta(self: *MetadataExtractor, html: []const u8, name: []const u8) ?[]const u8 {
        // Try property (for OpenGraph)
        const prop_pattern = try std.fmt.allocPrint(self.allocator, "property=\"{s}\"", .{name});
        defer self.allocator.free(prop_pattern);

        if (findMetaContent(html, prop_pattern)) |content| {
            return content;
        }

        // Try name attribute
        const name_pattern = try std.fmt.allocPrint(self.allocator, "name=\"{s}\"", .{name});
        defer self.allocator.free(name_pattern);

        return findMetaContent(html, name_pattern);
    }

    /// Extract OpenGraph tags
    fn extractOpenGraph(self: *MetadataExtractor, html: []const u8) !OpenGraphTags {
        return OpenGraphTags{
            .title = self.extractOgTag(html, "og:title"),
            .type = self.extractOgTag(html, "og:type"),
            .url = self.extractOgTag(html, "og:url"),
            .image = self.extractOgTag(html, "og:image"),
            .description = self.extractOgTag(html, "og:description"),
            .site_name = self.extractOgTag(html, "og:site_name"),
            .locale = self.extractOgTag(html, "og:locale"),
            .video = self.extractOgTag(html, "og:video"),
            .audio = self.extractOgTag(html, "og:audio"),
        };
    }

    /// Extract OG tag by name
    fn extractOgTag(self: *MetadataExtractor, html: []const u8, tag: []const u8) ?[]const u8 {
        const pattern = try std.fmt.allocPrint(self.allocator, "property=\"{s}\"", .{tag});
        defer self.allocator.free(pattern);
        return findMetaContent(html, pattern);
    }

    /// Extract Twitter Card tags
    fn extractTwitter(self: *MetadataExtractor, html: []const u8) !TwitterTags {
        return TwitterTags{
            .card = self.extractTwitterTag(html, "twitter:card"),
            .site = self.extractTwitterTag(html, "twitter:site"),
            .creator = self.extractTwitterTag(html, "twitter:creator"),
            .title = self.extractTwitterTag(html, "twitter:title"),
            .description = self.extractTwitterTag(html, "twitter:description"),
            .image = self.extractTwitterTag(html, "twitter:image"),
        };
    }

    /// Extract Twitter tag
    fn extractTwitterTag(self: *MetadataExtractor, html: []const u8, tag: []const u8) ?[]const u8 {
        const pattern = try std.fmt.allocPrint(self.allocator, "name=\"{s}\"", .{tag});
        defer self.allocator.free(pattern);
        return findMetaContent(html, pattern);
    }

    /// Extract Schema.org JSON-LD
    fn extractSchema(self: *MetadataExtractor, html: []const u8) !?[]const u8 {
        const script_open = "<script";
        const script_close = "</script>";
        const json_ld_type = "type=\"application/ld+json\"";

        var i: usize = 0;
        while (i < html.len) {
            const script_pos = std.mem.indexOf(u8, html[i..], script_open) orelse break;
            const start = i + script_pos;

            // Check if this is a JSON-LD script
            const remaining = html[start..];
            if (std.mem.indexOf(u8, remaining, json_ld_type)) |_| {
                const content_start = std.mem.indexOf(u8, remaining, ">").?.+ start + 1;
                const content_end = std.mem.indexOf(u8, html[content_start..], script_close) orelse {
                    i = start + 1;
                    continue;
                };

                return std.mem.trim(u8, html[content_start .. content_start + content_end], " \t\n\r");
            }

            i = start + 1;
        }

        return null;
    }

    /// Extract Dublin Core tags
    fn extractDublinCore(self: *MetadataExtractor, html: []const u8) !DublinCoreTags {
        const prefix = "DC.";
        return DublinCoreTags{
            .title = self.extractMeta(html, prefix ++ "title"),
            .creator = self.extractMeta(html, prefix ++ "creator"),
            .subject = self.extractMeta(html, prefix ++ "subject"),
            .description = self.extractMeta(html, prefix ++ "description"),
            .publisher = self.extractMeta(html, prefix ++ "publisher"),
            .contributor = self.extractMeta(html, prefix ++ "contributor"),
            .date = self.extractMeta(html, prefix ++ "date"),
            .format = self.extractMeta(html, prefix ++ "format"),
            .identifier = self.extractMeta(html, prefix ++ "identifier"),
            .source = self.extractMeta(html, prefix ++ "source"),
            .language = self.extractMeta(html, prefix ++ "language"),
            .relation = self.extractMeta(html, prefix ++ "relation"),
            .coverage = self.extractMeta(html, prefix ++ "coverage"),
            .rights = self.extractMeta(html, prefix ++ "rights"),
        };
    }

    /// Extract favicon
    fn extractFavicon(self: *MetadataExtractor, html: []const u8, base_url: []const u8) !?[]const u8 {
        // Try link rel="icon" or "shortcut icon"
        const patterns = [_][]const u8{
            "rel=\"icon\"",
            "rel=\"shortcut icon\"",
            "rel=\"apple-touch-icon\"",
        };

        for (patterns) |pattern| {
            const link_pos = std.mem.indexOf(u8, html, pattern) orelse continue;
            const href_start = std.mem.indexOf(u8, html[link_pos..], "href=\"") orelse continue;
            const start = link_pos + href_start + 6;
            const end = std.mem.indexOf(u8, html[start..], "\"") orelse continue;

            const favicon = html[start .. start + end];

            // If absolute URL, return it
            if (std.mem.startsWith(u8, favicon, "http")) {
                return favicon;
            }

            // If relative, make absolute
            if (favicon[0] == '/') {
                // Extract origin from base_url
                const path_pos = std.mem.indexOf(u8, base_url, "/") orelse base_url.len;
                const origin = base_url[0..path_pos];
                return try std.fmt.concat(self.allocator, .{ origin, favicon });
            }

            return favicon;
        }

        // Default to /favicon.ico
        const path_pos = std.mem.indexOf(u8, base_url, "/") orelse base_url.len;
        const origin = base_url[0..path_pos];
        return try std.fmt.concat(self.allocator, .{ origin, "/favicon.ico" });
    }

    /// Extract canonical URL
    fn extractCanonical(self: *MetadataExtractor, html: []const u8) ?[]const u8 {
        const link_pos = std.mem.indexOf(u8, html, "rel=\"canonical\"") orelse
                        std.mem.indexOf(u8, html, "rel='canonical'") orelse
                        return null;

        const href_start = std.mem.indexOf(u8, html[link_pos..], "href=\"") orelse
                          std.mem.indexOf(u8, html[link_pos..], "href='") orelse
                          return null;

        const start = link_pos + href_start + 6;
        const quote = html[start - 1];
        const end = std.mem.indexOf(u8, html[start..], &[_]u8{quote}) orelse return null;

        return html[start .. start + end];
    }
});

/// Find content attribute in meta tag
fn findMetaContent(html: []const u8, attr_pattern: []const u8) ?[]const u8 {
    const attr_pos = std.mem.indexOf(u8, html, attr_pattern) orelse return null;
    const content_start = attr_pos + attr_pattern.len;

    // Find content="
    const eq_pos = std.mem.indexOf(u8, html[content_start..], "content=\"") orelse return null;
    const start = content_start + eq_pos + 9;
    const end = std.mem.indexOf(u8, html[start..], "\"") orelse return null;

    return html[start .. start + end];
}

/// Find content of a tag
fn findTagContent(html: []const u8, tag: []const u8) ?[]const u8 {
    const open = "<" ++ tag ++ ">";
    const close = "</" ++ tag ++ ">";

    const start = std.mem.indexOf(u8, html, open) orelse return null;
    const content_start = start + open.len;

    const end = std.mem.indexOf(u8, html[content_start..], close) orelse return null;

    return html[content_start .. content_start + end];
}

/// Strip HTML tags
fn stripTags(html: []const u8) []const u8 {
    var result = std.ArrayList(u8);
    var in_tag = false;

    for (html) |c| {
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            result.append(c);
        }
    }

    return std.mem.trim(u8, result.items, " \t\n\r");
}
