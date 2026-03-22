//! Noosphere Table Extraction
//! 
//! Extract HTML tables and convert to structured formats.
//! For research agents, tables contain key data.

const std = @import("std");

/// Extracted table
pub const Table = struct {
    headers: [][]const u8,
    rows: [][]const u8,
    caption: ?[]const u8,
    source_url: ?[]const u8,
};

/// Table format for export
pub const TableFormat = enum {
    csv,
    json,
    markdown,
    html,
};

/// Table extractor
pub const TableExtractor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TableExtractor {
        return TableExtractor{ .allocator = allocator };
    }

    /// Extract all tables from HTML
    pub fn extractAll(self: *TableExtractor, html: []const u8, source_url: ?[]const u8) ![]Table {
        var tables = std.ArrayList(Table).init(self.allocator);

        // Simple table detection
        var i: usize = 0;
        while (i < html.len) {
            if (std.mem.startsWith(u8, html[i..], "<table")) {
                const end = findMatchingTag(html, i, "table") orelse {
                    i += 1;
                    continue;
                };

                const table_html = html[i..end];
                const table = self.extractTable(table_html, source_url) catch continue;
                try tables.append(table);

                i = end;
            } else {
                i += 1;
            }
        }

        return tables.toOwnedSlice();
    }

    /// Extract single table
    pub fn extractTable(self: *TableExtractor, table_html: []const u8, source_url: ?[]const u8) !Table {
        var headers = std.ArrayList([]const u8).init(self.allocator);
        var rows = std.ArrayList([]const u8).init(self.allocator);
        var caption: ?[]const u8 = null;

        // Extract caption
        if (findTagContent(table_html, "caption")) |cap| {
            caption = try self.allocator.dupe(u8, cap);
        }

        // Extract headers
        if (findTagContent(table_html, "thead")) |thead| {
            var row_it = std.mem.split(u8, thead, "<tr");
            while (row_it.next()) |row| {
                if (row.len == 0) continue;
                const cells = extractCells(row, "th");
                if (cells.len > 0) {
                    for (cells) |cell| {
                        try headers.append(try self.allocator.dupe(u8, cell));
                    }
                    break; // Only first row
                }
            }
        }

        // If no thead, look in first tr of tbody
        if (headers.len == 0) {
            if (findTagContent(table_html, "tbody")) |tbody| {
                var row_it = std.mem.split(u8, tbody, "<tr");
                while (row_it.next()) |row| {
                    if (row.len == 0) continue;
                    const cells = extractCells(row, "th");
                    if (cells.len > 0) {
                        for (cells) |cell| {
                            try headers.append(try self.allocator.dupe(u8, cell));
                        }
                        break;
                    }
                }
            }
        }

        // Extract body rows
        const body_content = findTagContent(table_html, "tbody") orelse table_html;
        var row_it = std.mem.split(u8, body_content, "<tr");
        var is_header_row = headers.len == 0;
        
        while (row_it.next()) |row| {
            if (row.len == 0) continue;
            
            // Skip header row if we already found headers
            if (is_header_row and headers.len > 0) {
                is_header_row = false;
                continue;
            }

            const cells = extractCells(row, "td");
            if (cells.len > 0) {
                // Build row string
                const row_str = try std.mem.join(self.allocator, ",", cells);
                try rows.append(row_str);
            }
        }

        // If still no headers, use first row
        if (headers.len == 0 and rows.len > 0) {
            const first_row = rows.items[0];
            var cell_it = std.mem.split(u8, first_row, ",");
            while (cell_it.next()) |cell| {
                try headers.append(try self.allocator.dupe(u8, std.mem.trim(u8, cell, " \t")));
            }
        }

        return Table{
            .headers = try headers.toOwnedSlice(),
            .rows = try rows.toOwnedSlice(),
            .caption = caption,
            .source_url = if (source_url) |s| try self.allocator.dupe(u8, s) else null,
        };
    }

    /// Export table to format
    pub fn exportTo(self: *TableExtractor, table: *const Table, format: TableFormat) ![]u8 {
        switch (format) {
            .csv => return self.toCSV(table),
            .json => return self.toJSON(table),
            .markdown => return self.toMarkdown(table),
            .html => return self.toHTML(table),
        }
    }

    /// Export to CSV
    fn toCSV(self: *TableExtractor, table: *const Table) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        // Header row
        try writer.writeAll(try std.mem.join(self.allocator, ",", table.headers));
        try writer.writeAll("\n");

        // Data rows
        for (table.rows) |row| {
            try writer.writeAll(row);
            try writer.writeAll("\n");
        }

        return result.toOwnedSlice();
    }

    /// Export to JSON
    fn toJSON(self: *TableExtractor, table: *const Table) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        try writer.writeAll("[\n");

        for (table.rows, 0..) |row, i| {
            const cells = std.mem.split(u8, row, ",");
            try writer.writeAll("  {\n");
            
            var j: usize = 0;
            while (cells.next()) |cell| {
                const trimmed = std.mem.trim(u8, cell, " \t\"");
                try writer.print("    \"{s}\": \"{s}\"", .{ table.headers[j], trimmed });
                if (j < table.headers.len - 1) try writer.writeAll(",");
                try writer.writeAll("\n");
                j += 1;
            }
            
            try writer.writeAll("  }");
            if (i < table.rows.len - 1) try writer.writeAll(",");
            try writer.writeAll("\n");
        }

        try writer.writeAll("]\n");

        return result.toOwnedSlice();
    }

    /// Export to Markdown
    fn toMarkdown(self: *TableExtractor, table: *const Table) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        // Caption
        if (table.caption) |cap| {
            try writer.print("*Caption: {s}*\n\n", .{cap});
        }

        // Header row
        try writer.writeAll("| ");
        try writer.writeAll(try std.mem.join(self.allocator, " | ", table.headers));
        try writer.writeAll(" |\n");

        // Separator
        try writer.writeAll("|");
        for (table.headers) |_| {
            try writer.writeAll(" --- |");
        }
        try writer.writeAll("\n");

        // Data rows
        for (table.rows) |row| {
            try writer.writeAll("| ");
            try writer.writeAll(try std.mem.replaceOwned(u8, self.allocator, row, ",", " | "));
            try writer.writeAll(" |\n");
        }

        return result.toOwnedSlice();
    }

    /// Export to HTML
    fn toHTML(self: *TableExtractor, table: *const Table) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        const writer = result.writer();

        try writer.writeAll("<table>\n");

        if (table.caption) |cap| {
            try writer.print("  <caption>{s}</caption>\n", .{cap});
        }

        // Headers
        try writer.writeAll("  <thead>\n    <tr>\n");
        for (table.headers) |h| {
            try writer.print("      <th>{s}</th>\n", .{h});
        }
        try writer.writeAll("    </tr>\n  </thead>\n");

        // Body
        try writer.writeAll("  <tbody>\n");
        for (table.rows) |row| {
            try writer.writeAll("    <tr>\n");
            var cells = std.mem.split(u8, row, ",");
            while (cells.next()) |cell| {
                try writer.print("      <td>{s}</td>\n", .{std.mem.trim(u8, cell, " \t")});
            }
            try writer.writeAll("    </tr>\n");
        }
        try writer.writeAll("  </tbody>\n");

        try writer.writeAll("</table>\n");

        return result.toOwnedSlice();
    }
};

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

/// Extract content of a tag
fn findTagContent(html: []const u8, tag: []const u8) ?[]const u8 {
    const open = "<" ++ tag;
    const close = "</" ++ tag ++ ">";

    const start = std.mem.indexOf(u8, html, open) orelse return null;
    const content_start = start + open.len;
    
    const end = std.mem.indexOf(u8, html[content_start..], close) orelse return null;
    
    return html[content_start..content_start + end];
}

/// Extract cells from a row
fn extractCells(row: []const u8, cell_tag: []const u8) [][]const u8 {
    var cells = std.ArrayList([]const u8);
    const open = "<" ++ cell_tag;
    const close = "</" ++ cell_tag ++ ">";

    var i: usize = 0;
    while (i < row.len) {
        if (std.mem.startsWith(u8, row[i..], open)) {
            const content_start = i + open.len;
            const end = std.mem.indexOf(u8, row[content_start..], close) orelse break;
            const cell = row[content_start..content_start + end];
            cells.append(stripTags(cell));
            i = content_start + end + close.len;
        } else {
            i += 1;
        }
    }

    return cells.items;
}

/// Strip HTML tags from text
fn stripTags(text: []const u8) []const u8 {
    var result = std.ArrayList(u8);
    var in_tag = false;

    for (text) |c| {
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
