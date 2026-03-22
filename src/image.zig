//! Noosphere Image/Figure Extraction
//! 
//! Extract images and figures from HTML/markdown.
//! Capture alt-text, captions, and figure numbers.

const std = @import("std");

/// Extracted figure
pub const Figure = struct {
    url: []const u8,
    alt_text: ?[]const u8,
    caption: ?[]const u8,
    figure_num: ?u32,
    width: ?u32,
    height: ?u32,
    format: []const u8,
};

/// Figure extractor
pub const FigureExtractor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FigureExtractor {
        return FigureExtractor{ .allocator = allocator };
    }

    /// Extract all figures from HTML
    pub fn extractFromHtml(self: *FigureExtractor, html: []const u8) ![]Figure {
        var figures = std.ArrayList(Figure).init(self.allocator);
        var figure_num: u32 = 0;

        // Find all img tags
        var i: usize = 0;
        while (i < html.len) {
            if (std.mem.startsWith(u8, html[i..], "<img")) {
                const end = findTagEnd(html, i) orelse {
                    i += 1;
                    continue;
                };

                const tag = html[i..end];
                var figure = try self.parseImgTag(tag);
                
                figure_num += 1;
                figure.figure_num = figure_num;

                try figures.append(figure);
                i = end;
            } else if (std.mem.startsWith(u8, html[i..], "<figure")) {
                const end = findMatchingTag(html, i, "figure") orelse {
                    i += 1;
                    continue;
                };

                const figure_html = html[i..end];
                var figure = try self.parseFigureElement(figure_html, figure_num);
                figure_num += 1;
                figure.figure_num = figure_num;

                try figures.append(figure);
                i = end;
            } else {
                i += 1;
            }
        }

        return figures.toOwnedSlice();
    }

    /// Parse img tag
    fn parseImgTag(self: *FigureExtractor, tag: []const u8) !Figure {
        var figure = Figure{
            .url = "",
            .alt_text = null,
            .caption = null,
            .figure_num = null,
            .width = null,
            .height = null,
            .format = "unknown",
        };

        // Extract src
        if (findAttr(tag, "src")) |src| {
            figure.url = src;
            figure.format = extractFormat(src);
        } else if (findAttr(tag, "data-src")) |src| {
            figure.url = src;
            figure.format = extractFormat(src);
        }

        // Extract alt
        figure.alt_text = findAttr(tag, "alt");

        // Extract dimensions
        if (findAttr(tag, "width")) |w| {
            figure.width = parseDimension(w);
        }
        if (findAttr(tag, "height")) |h| {
            figure.height = parseDimension(h);
        }

        return figure;
    }

    /// Parse figure element with figcaption
    fn parseFigureElement(self: *FigureExtractor, html: []const u8, current_num: u32) !Figure {
        var figure = Figure{
            .url = "",
            .alt_text = null,
            .caption = null,
            .figure_num = null,
            .width = null,
            .height = null,
            .format = "unknown",
        };

        // Find img inside
        if (findTagContent(html, "img")) |img_tag| {
            const parsed = try self.parseImgTag(img_tag);
            figure.url = parsed.url;
            figure.format = parsed.format;
            figure.alt_text = parsed.alt_text;
            figure.width = parsed.width;
            figure.height = parsed.height;
        }

        // Find figcaption
        if (findTagContent(html, "figcaption")) |caption| {
            figure.caption = stripTags(caption);
        }

        return figure;
    }

    /// Extract from markdown
    pub fn extractFromMarkdown(self: *FigureExtractor, md: []const u8) ![]Figure {
        var figures = std.ArrayList(Figure).init(self.allocator);
        var figure_num: u32 = 0;

        // Find markdown images: ![alt](url)
        var i: usize = 0;
        while (i < md.len - 4) {
            if (md[i] == '!' and md[i + 1] == '[') {
                const close_bracket = findChar(md, ']', i + 2) orelse {
                    i += 1;
                    continue;
                };

                const alt_text = md[i + 2 .. close_bracket];

                if (close_bracket + 1 < md.len and md[close_bracket + 1] == '(') {
                    const close_paren = findChar(md, ')', close_bracket + 2) orelse {
                        i += 1;
                        continue;
                    };

                    const url = md[close_bracket + 2 .. close_paren];

                    figure_num += 1;
                    try figures.append(Figure{
                        .url = url,
                        .alt_text = if (alt_text.len > 0) alt_text else null,
                        .caption = null,
                        .figure_num = figure_num,
                        .width = null,
                        .height = null,
                        .format = extractFormat(url),
                    });

                    i = close_paren + 1;
                } else {
                    i += 1;
                }
            } else {
                i += 1;
            }
        }

        return figures.toOwnedSlice();
    }

    /// Export figures to markdown
    pub fn toMarkdown(self: *FigureExtractor, figures: []Figure) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);

        for (figures) |fig| {
            try result.appendSlice("## Figure ");
            if (fig.figure_num) |num| {
                try std.fmt.formatInt(num, 10, .lower, .{}, result.writer());
            }
            try result.append('\n');

            if (fig.caption) |cap| {
                try result.appendSlice("*");
                try result.appendSlice(cap);
                try result.appendSlice("*\n\n");
            }

            try result.appendSlice("![");
            if (fig.alt_text) |alt| {
                try result.appendSlice(alt);
            }
            try result.append(']');
            try result.append('(');
            try result.appendSlice(fig.url);
            try result.append(')');
            try result.append('\n');

            if (fig.width) |w| {
                try std.fmt.format("Width: {}px\n", .{w}, result.writer());
            }
            if (fig.height) |h| {
                try std.fmt.format("Height: {}px\n", .{h}, result.writer());
            }
            try result.append('\n');
        }

        return result.toOwnedSlice();
    }

    /// Export figures to JSON
    pub fn toJSON(self: *FigureExtractor, figures: []Figure) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        try result.appendSlice("[\n");

        for (figures, 0..) |fig, idx| {
            try result.appendSlice("  {\n");
            try std.fmt.format("    \"url\": \"{s}\",\n", .{fig.url}, result.writer());
            if (fig.alt_text) |alt| {
                try std.fmt.format("    \"alt\": \"{s}\",\n", .{alt}, result.writer());
            }
            if (fig.caption) |cap| {
                try std.fmt.format("    \"caption\": \"{s}\",\n", .{cap}, result.writer());
            }
            if (fig.figure_num) |num| {
                try std.fmt.format("    \"figure_num\": {},\n", .{num}, result.writer());
            }
            if (fig.width) |w| {
                try std.fmt.format("    \"width\": {},\n", .{w}, result.writer());
            }
            if (fig.height) |h| {
                try std.fmt.format("    \"height\": {}\n", .{h}, result.writer());
            }
            try result.appendSlice("  }");
            if (idx < figures.len - 1) try result.append(',');
            try result.append('\n');
        }

        try result.appendSlice("]\n");
        return result.toOwnedSlice();
    }
});

/// Find end of tag
fn findTagEnd(html: []const u8, start: usize) ?usize {
    var i = start + 4; // Skip <img
    while (i < html.len - 1) {
        if (html[i] == '>' and html[i - 1] != '\\') {
            return i + 1;
        }
        i += 1;
    }
    return null;
}

/// Find matching closing tag
fn findMatchingTag(html: []const u8, start: usize, tag: []const u8) ?usize {
    const open_tag = "<" ++ tag;
    const close_tag = "</" ++ tag ++ ">";

    var depth: usize = 1;
    var i = start + open_tag.len;

    while (i < html.len and depth > 0) {
        if (std.mem.startsWith(u8, html[i..], close_tag)) {
            depth -= 1;
            if (depth == 0) return i + close_tag.len;
            i += close_tag.len;
        } else if (std.mem.startsWith(u8, html[i..], open_tag)) {
            depth += 1;
            i += open_tag.len;
        } else {
            i += 1;
        }
    }

    return null;
}

/// Find attribute value
fn findAttr(tag: []const u8, attr: []const u8) ?[]const u8 {
    const eq_pos = std.mem.indexOf(u8, tag, attr ++ "=") orelse return null;
    const value_start = eq_pos + attr.len + 1;

    if (value_start >= tag.len) return null;

    var i = value_start;
    while (i < tag.len and (tag[i] == ' ' or tag[i] == '\t')) i += 1;

    if (i >= tag.len) return null;

    const delimiter = tag[i];
    if (delimiter == '"' or delimiter == '\'') {
        const value_end = findChar(tag, delimiter, i + 1) orelse return null;
        return tag[i + 1 .. value_end];
    } else {
        // Unquoted value
        const value_end = i;
        while (i < tag.len and tag[i] != ' ' and tag[i] != '>' and tag[i] != '\t') i += 1;
        return tag[value_end..i];
    }
}

/// Find content inside tag
fn findTagContent(html: []const u8, tag: []const u8) ?[]const u8 {
    const open = "<" ++ tag;
    const close = "</" ++ tag ++ ">";

    const start = std.mem.indexOf(u8, html, open) orelse return null;
    const content_start = start + open.len;

    const end = std.mem.indexOf(u8, html[content_start..], close) orelse return null;

    return html[content_start .. content_start + end];
}

/// Find character
fn findChar(data: []const u8, char: u8, start: usize) ?usize {
    var i = start;
    while (i < data.len) {
        if (data[i] == char) return i;
        i += 1;
    }
    return null;
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

/// Extract image format from URL
fn extractFormat(url: []const u8) []const u8 {
    const formats = [_][]const u8{ "jpg", "jpeg", "png", "gif", "webp", "svg", "avif", "apng" };

    for (formats) |fmt| {
        if (std.mem.endsWith(u8, url, "." ++ fmt)) {
            return fmt;
        }
        if (std.mem.indexOf(u8, url, "." ++ fmt ++ "?")) |_| {
            return fmt;
        }
    }

    return "unknown";
}

/// Parse dimension (e.g., "100", "100px", "100%")
fn parseDimension(s: []const u8) ?u32 {
    var num_str: []const u8 = s;

    // Strip non-numeric suffix
    var i: usize = 0;
    while (i < num_str.len and (std.ascii.isDigit(num_str[i]) or num_str[i] == '.')) {
        i += 1;
    }
    num_str = num_str[0..i];

    if (num_str.len == 0) return null;

    return std.fmt.parseInt(u32, num_str, 10) catch null;
}
