//! Noosphere Citation Graph
//! 
//! Build citation networks from academic papers.
//! Essential for research agents analyzing paper relationships.

const std = @import("std");

/// Citation entry
pub const Citation = struct {
    text: []const u8,
    authors: [][]const u8,
    title: []const u8,
    year: ?u16,
    venue: ?[]const u8,
    doi: ?[]const u8,
    url: ?[]const u8,
};

/// Paper with citations
pub const PaperWithCitations = struct {
    paper_id: []const u8,
    title: []const u8,
    references: []Citation, // Papers this one cites
    cited_by: [][]const u8,   // Paper IDs that cite this one
};

/// Citation graph
pub const CitationGraph = struct {
    allocator: std.mem.Allocator,
    papers: std.StringArrayHashMap(PaperWithCitations),

    pub fn init(allocator: std.mem.Allocator) CitationGraph {
        return CitationGraph{
            .allocator = allocator,
            .papers = std.StringArrayHashMap(PaperWithCitations).init(allocator),
        };
    }

    pub fn deinit(self: *CitationGraph) void {
        var it = self.papers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*.paper_id);
            self.allocator.free(entry.value_ptr.*.title);
            for (entry.value_ptr.*.references) |ref| {
                self.allocator.free(ref.text);
                for (ref.authors) |a| self.allocator.free(a);
                self.allocator.free(ref.authors);
                if (ref.venue) |v| self.allocator.free(v);
                if (ref.doi) |d| self.allocator.free(d);
                if (ref.url) |u| self.allocator.free(u);
            }
            self.allocator.free(entry.value_ptr.*.references);
            for (entry.value_ptr.*.cited_by) |id| self.allocator.free(id);
            self.allocator.free(entry.value_ptr.*.cited_by);
        }
        self.papers.deinit();
    }

    /// Add a paper to the graph
    pub fn addPaper(self: *CitationGraph, paper: PaperWithCitations) !void {
        const id = try self.allocator.dupe(u8, paper.paper_id);
        try self.papers.put(id, paper);
    }

    /// Add citation relationship
    pub fn addCitation(self: *CitationGraph, citing_id: []const u8, cited_id: []const u8) !void {
        const citing = self.papers.getPtr(citing_id);
        const cited = self.papers.getPtr(cited_id);

        if (citing) |p| {
            try p.*.cited_by.append(try self.allocator.dupe(u8, cited_id));
        }

        if (cited) |p| {
            _ = p; // Could track in another direction
        }
    }

    /// Get citation count
    pub fn getCitationCount(self: *CitationGraph, paper_id: []const u8) usize {
        if (self.papers.get(paper_id)) |paper| {
            return paper.cited_by.len;
        }
        return 0;
    }

    /// Find papers by author
    pub fn findByAuthor(self: *CitationGraph, author_name: []const u8) ![][]const u8 {
        var results = std.ArrayList([]const u8).init(self.allocator);

        var it = self.papers.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.*.references) |ref| {
                for (ref.authors) |author| {
                    if (std.mem.indexOf(u8, author, author_name) != null) {
                        try results.append(try self.allocator.dupe(u8, entry.key_ptr.*));
                        break;
                    }
                }
            }
        }

        return results.toOwnedSlice();
    }

    /// Get most cited papers
    pub fn getMostCited(self: *CitationGraph, limit: usize) ![][]const u8 {
        var sorted = std.ArrayList(struct {
            id: []const u8,
            count: usize,
        }).init(self.allocator);

        var it = self.papers.iterator();
        while (it.next()) |entry| {
            try sorted.append(.{
                .id = entry.key_ptr.*,
                .count = entry.value_ptr.*.cited_by.len,
            });
        }

        // Sort by count descending
        std.sort.sort(struct { id: []const u8, count: usize }, sorted.items, {}, struct {
            fn less(_: void, a: @TypeOf(sorted.items[0]), b: @TypeOf(sorted.items[0])) bool {
                return a.count > b.count;
            }
        }.less);

        var results = std.ArrayList([]const u8).init(self.allocator);
        for (sorted.items[0..@min(sorted.items.len, limit)]) |item| {
            try results.append(item.id);
        }

        return results.toOwnedSlice();
    }
};

/// Parse BibTeX entry
pub fn parseBibtex(allocator: std.mem.Allocator, bibtex: []const u8) !Citation {
    var citation = Citation{
        .text = try allocator.dupe(u8, bibtex),
        .authors = &.{},
        .title = "",
        .year = null,
        .venue = null,
        .doi = null,
        .url = null,
    };

    var authors = std.ArrayList([]const u8).init(allocator);

    // Extract title
    if (extractBibtexField(bibtex, "title")) |title| {
        citation.title = try allocator.dupe(u8, title);
    }

    // Extract author
    if (extractBibtexField(bibtex, "author")) |author_str| {
        // Split by "and"
        var author_list = std.mem.split(u8, author_str, " and ");
        while (author_list.next()) |author| {
            try authors.append(try allocator.dupe(u8, author));
        }
        citation.authors = try authors.toOwnedSlice();
    }

    // Extract year
    if (extractBibtexField(bibtex, "year")) |year_str| {
        citation.year = std.fmt.parseInt(u16, year_str, 10) catch null;
    }

    // Extract venue/journal
    if (extractBibtexField(bibtex, "journal")) |j| {
        citation.venue = try allocator.dupe(u8, j);
    } else if (extractBibtexField(bibtex, "booktitle")) |b| {
        citation.venue = try allocator.dupe(u8, b);
    }

    // Extract DOI
    if (extractBibtexField(bibtex, "doi")) |doi| {
        citation.doi = try allocator.dupe(u8, doi);
    }

    // Extract URL
    if (extractBibtexField(bibtex, "url")) |url| {
        citation.url = try allocator.dupe(u8, url);
    }

    return citation;
}

/// Extract field from BibTeX entry
fn extractBibtexField(entry: []const u8, field: []const u8) ?[]const u8 {
    const pattern = field ++ " = ";
    if (std.mem.indexOf(u8, entry, pattern)) |start| {
        const value_start = start + pattern.len;
        const entry_content = entry[value_start..];

        if (entry_content.len > 0) {
            if (entry_content[0] == '{') {
                // Find matching closing brace
                var depth: usize = 1;
                var i: usize = 1;
                while (i < entry_content.len and depth > 0) {
                    if (entry_content[i] == '{') depth += 1;
                    if (entry_content[i] == '}') depth -= 1;
                    i += 1;
                }
                return entry_content[1..i - 1];
            } else if (entry_content[0] == '"') {
                // Find matching closing quote
                const i = std.mem.indexOf(u8, entry_content[1..], "\"").?;
                return entry_content[1..1 + i];
            }
        }
    }
    return null;
}

/// Export to BibTeX format
pub fn toBibtex(allocator: std.mem.Allocator, citation: *const Citation) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    const writer = result.writer();

    try writer.print("@misc{{key,\n", .{});
    if (citation.title.len > 0) try writer.print("  title = {{{s}}},\n", .{citation.title});

    if (citation.authors.len > 0) {
        try writer.writeAll("  author = {");
        for (citation.authors, 0..) |author, i| {
            if (i > 0) try writer.writeAll(" and ");
            try writer.print("{s}", .{author});
        }
        try writer.writeAll("},\n");
    }

    if (citation.year) |y| try writer.print("  year = {{{d}}},\n", .{y});
    if (citation.venue) |v| try writer.print("  journal = {{{s}}},\n", .{v});
    if (citation.doi) |d| try writer.print("  doi = {{{s}}},\n", .{d});
    if (citation.url) |u| try writer.print("  url = {{{s}}},\n", .{u});

    try writer.writeAll("}\n");

    return result.toOwnedSlice();
}
