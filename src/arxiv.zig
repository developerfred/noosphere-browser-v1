//! Noosphere ArXiv Integration
//! 
//! Fetch and parse ArXiv papers for research agents.
//! ArXiv is a major source of research papers for AI agents.

const std = @import("std");
const http = @import("http.zig");
const parser = @import("parser.zig");

/// ArXiv paper metadata
pub const ArxivPaper = struct {
    id: []const u8,
    title: []const u8,
    authors: [][]const u8,
    abstract: []const u8,
    categories: [][]const u8,
    published: []const u8,
    updated: []const u8,
    doi: ?[]const u8,
    pdf_url: []const u8,
    primary_category: []const u8,
};

/// ArXiv API response
pub const ArxivResponse = struct {
    total_results: u32,
    start_index: u32,
    items_per_page: u32,
    papers: []ArxivPaper,
};

/// ArXiv API client
pub const ArxivClient = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,

    pub fn init(allocator: std.mem.Allocator) ArxivClient {
        return ArxivClient{
            .allocator = allocator,
            .base_url = "http://export.arxiv.org/api/query",
        };
    }

    pub fn deinit(self: *ArxivClient) void {
        self.allocator.free(self.base_url);
    }

    /// Search ArXiv by query
    pub fn search(self: *ArxivClient, query: []const u8, max_results: u32) !ArxivResponse {
        // URL encode query
        const encoded_query = try urlEncode(self.allocator, query);
        defer self.allocator.free(encoded_query);

        // Build URL
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}?search_query=all:{s}&start=0&max_results={d}",
            .{ self.base_url, encoded_query, max_results }
        );
        defer self.allocator.free(url);

        // Fetch
        const response = try http.fetch(url);
        defer response.deinit();

        // Parse ATOM feed
        return try parseAtomFeed(self.allocator, response.body);
    }

    /// Get paper by ID
    pub fn getPaper(self: *ArxivClient, paper_id: []const u8) !ArxivPaper {
        const url = try std.fmt.allocPrint(
            self.allocator,
            "{s}?id_list={s}",
            .{ self.base_url, paper_id }
        );
        defer self.allocator.free(url);

        const response = try http.fetch(url);
        defer response.deinit();

        const papers = try parseAtomFeed(self.allocator, response.body);
        if (papers.papers.len == 0) {
            return error.PaperNotFound;
        }
        return papers.papers[0];
    }

    /// Get PDF URL for a paper
    pub fn getPdfUrl(self: *ArxivClient, paper_id: []const u8) ![]const u8 {
        const paper = try self.getPaper(paper_id);
        return paper.pdf_url;
    }
};

/// Parse ArXiv ATOM feed
fn parseAtomFeed(allocator: std.mem.Allocator, xml: []const u8) !ArxivResponse {
    var papers = std.ArrayList(ArxivPaper).init(allocator);
    defer papers.deinit();

    var total_results: u32 = 0;
    var start_index: u32 = 0;
    var items_per_page: u32 = 0;

    // Simple XML parsing
    var in_entry = false;
    var current_paper: ?ArxivPaper = null;
    var current_field: []const u8 = "";

    const lines = std.mem.split(u8, xml, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        // Parse metadata
        if (std.mem.startsWith(u8, trimmed, "<opensearch:totalResults>")) {
            const value = extractXmlValue(trimmed, "opensearch:totalResults");
            total_results = std.fmt.parseInt(u32, value, 10) catch 0;
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, "<entry>")) {
            in_entry = true;
            current_paper = ArxivPaper{
                .id = "",
                .title = "",
                .authors = &.{},
                .abstract = "",
                .categories = &.{},
                .published = "",
                .updated = "",
                .doi = null,
                .pdf_url = "",
                .primary_category = "",
            };
            continue;
        }

        if (std.mem.startsWith(u8, trimmed, "</entry>")) {
            in_entry = false;
            if (current_paper) |paper| {
                try papers.append(paper);
            }
            current_paper = null;
            continue;
        }

        if (!in_entry) continue;

        // Parse fields
        if (std.mem.startsWith(u8, trimmed, "<id>")) {
            current_field = "id";
            current_paper.?.id = extractXmlValue(trimmed, "id");
        } else if (std.mem.startsWith(u8, trimmed, "<title>")) {
            current_field = "title";
            var title = extractXmlValue(trimmed, "title");
            // Clean up whitespace
            while (std.mem.indexOf(u8, title, "\n") != null) {
                title = std.mem.replaceOwned(u8, allocator, title, "\n", " ");
            }
            current_paper.?.title = std.mem.trim(u8, title, " ");
        } else if (std.mem.startsWith(u8, trimmed, "<summary>")) {
            current_field = "abstract";
            var abs = extractXmlValue(trimmed, "summary");
            while (std.mem.indexOf(u8, abs, "\n") != null) {
                abs = std.mem.replaceOwned(u8, allocator, abs, "\n", " ");
            }
            current_paper.?.abstract = std.mem.trim(u8, abs, " ");
        } else if (std.mem.startsWith(u8, trimmed, "<published>")) {
            current_field = "published";
            current_paper.?.published = extractXmlValue(trimmed, "published");
        } else if (std.mem.startsWith(u8, trimmed, "<updated>")) {
            current_field = "updated";
            current_paper.?.updated = extractXmlValue(trimmed, "updated");
        } else if (std.mem.startsWith(u8, trimmed, "<arxiv:doi>")) {
            current_field = "doi";
            current_paper.?.doi = extractXmlValue(trimmed, "arxiv:doi");
        } else if (std.mem.startsWith(u8, trimmed, "<link title=\"pdf\"")) {
            current_field = "pdf_url";
            // Extract href from link tag
            if (std.mem.indexOf(u8, trimmed, "href=\"")) |start| {
                const href_start = start + 6;
                if (std.mem.indexOf(u8, trimmed[href_start..], "\"")) |end| {
                    current_paper.?.pdf_url = trimmed[href_start..href_start + end];
                }
            }
        } else if (std.mem.startsWith(u8, trimmed, "<arxiv:primary_category")) {
            current_field = "primary_category";
            // Extract term attribute
            if (std.mem.indexOf(u8, trimmed, "term=\"")) |start| {
                const term_start = start + 6;
                if (std.mem.indexOf(u8, trimmed[term_start..], "\"")) |end| {
                    current_paper.?.primary_category = trimmed[term_start..term_start + end];
                }
            }
        }
    }

    return ArxivResponse{
        .total_results = total_results,
        .start_index = start_index,
        .items_per_page = items_per_page,
        .papers = try papers.toOwnedSlice(),
    };
}

/// Extract value from XML tag
fn extractXmlValue(line: []const u8, tag: []const u8) []const u8 {
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

/// URL encode a string
fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    for (input) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '-', '_', '.', '~' => {
                try result.append(c);
            },
            else => {
                try result.writer().print("%{X}", .{c});
            },
        }
    }

    return result.toOwnedSlice();
}
