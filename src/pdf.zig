//! Noosphere PDF Parser
//! 
//! Parse PDF documents, especially ArXiv papers.
//! Extract text, metadata, and structure.

const std = @import("std");

/// PDF document
pub const PDFDocument = struct {
    pages: []PDFPage,
    metadata: PDFMetadata,
    outlines: []Outline,
};

pub const PDFPage = struct {
    page_num: u32,
    text: []const u8,
    width: f32,
    height: f32,
};

pub const PDFMetadata = struct {
    title: ?[]const u8,
    author: ?[]const u8,
    subject: ?[]const u8,
    keywords: ?[]const u8,
    creator: ?[]const u8,
    producer: ?[]const u8,
    creation_date: ?[]const u8,
    mod_date: ?[]const u8,
};

pub const Outline = struct {
    title: []const u8,
    level: u32,
    page_num: u32,
};

/// PDF extractor
pub const PDFExtractor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PDFExtractor {
        return PDFExtractor{ .allocator = allocator };
    }

    /// Extract text from PDF binary
    pub fn extractText(self: *PDFExtractor, pdf_data: []const u8) ![]const u8 {
        // Simple PDF text extraction - look for text streams
        var text = std.ArrayList(u8).init(self.allocator);

        var i: usize = 0;
        while (i < pdf_data.len - 10) {
            // Look for BT (Begin Text) markers
            if (pdf_data[i] == 'B' and pdf_data[i + 1] == 'T') {
                const end = findMatchingET(pdf_data, i + 2) orelse {
                    i += 1;
                    continue;
                };

                // Extract text from this block
                const block = pdf_data[i..end];
                const extracted = extractTextFromBT(block);
                try text.appendSlice(extracted);
                try text.append(' ');

                i = end;
            } else {
                i += 1;
            }
        }

        return text.toOwnedSlice();
    }

    /// Extract metadata from PDF
    pub fn extractMetadata(self: *PDFExtractor, pdf_data: []const u8) !PDFMetadata {
        return PDFMetadata{
            .title = extractInfoField(pdf_data, "Title"),
            .author = extractInfoField(pdf_data, "Author"),
            .subject = extractInfoField(pdf_data, "Subject"),
            .keywords = extractInfoField(pdf_data, "Keywords"),
            .creator = extractInfoField(pdf_data, "Creator"),
            .producer = extractInfoField(pdf_data, "Producer"),
            .creation_date = extractInfoField(pdf_data, "CreationDate"),
            .mod_date = extractInfoField(pdf_data, "ModDate"),
        };
    }

    /// Count pages
    pub fn countPages(self: *PDFExtractor, pdf_data: []const u8) u32 {
        var count: u32 = 0;
        var i: usize = 0;

        while (i < pdf_data.len - 5) {
            if (std.mem.startsWith(u8, pdf_data[i..], "/Type /Page")) {
                count += 1;
            }
            i += 1;
        }

        return count;
    }

    /// Check if PDF is valid
    pub fn isValid(self: *PDFExtractor, pdf_data: []const u8) bool {
        if (pdf_data.len < 8) return false;
        return std.mem.startsWith(u8, pdf_data[0..8], "%PDF-");
    }

    /// Extract full document structure
    pub fn extractDocument(self: *PDFExtractor, pdf_data: []const u8) !PDFDocument {
        const text = try self.extractText(pdf_data);
        const metadata = try self.extractMetadata(pdf_data);
        const page_count = self.countPages(pdf_data);

        // Create single page with all text
        const page = PDFPage{
            .page_num = 1,
            .text = text,
            .width = 612.0, // Letter size default
            .height = 792.0,
        };

        return PDFDocument{
            .pages = try self.allocator.alloc(PDFPage, 1),
            .metadata = metadata,
            .outlines = try self.allocator.alloc(Outline, 0),
        };
    }
});

/// Find matching ET (End Text)
fn findMatchingET(data: []const u8, start: usize) ?usize {
    var i = start;
    while (i < data.len - 2) {
        if (data[i] == 'E' and data[i + 1] == 'T') {
            return i + 2;
        }
        i += 1;
    }
    return null;
}

/// Extract text from BT...ET block
fn extractTextFromBT(block: []const u8) []const u8 {
    var result = std.ArrayList(u8);
    var i: usize = 0;

    while (i < block.len - 3) {
        // Look for Tj or TJ operators
        if (block[i] == 'T' and (block[i + 1] == 'j' or block[i + 1] == 'J')) {
            // Extract string before Tj
            const start = findStringStart(block, i) orelse {
                i += 1;
                continue;
            };
            const end = i;
            if (end > start) {
                try result.appendSlice(block[start..end]);
            }
            i += 2;
        } else if (block[i] == 'T' and block[i + 1] == 'J') {
            // TJ operator - array of strings
            const array_end = findArrayEnd(block, i + 2) orelse {
                i += 1;
                continue;
            };
            // Extract strings from array
            var j = i + 2;
            while (j < array_end) {
                if (block[j] == '(') {
                    const str_end = findStringEnd(block, j) orelse break;
                    try result.appendSlice(block[j + 1 .. str_end]);
                    j = str_end + 1;
                } else {
                    j += 1;
                }
            }
            i = array_end;
        } else {
            i += 1;
        }
    }

    return result.items;
}

/// Find start of string (after last ')' before Tj)
fn findStringStart(data: []const u8, before: usize) ?usize {
    var i: usize = before - 1;
    var paren_depth: usize = 0;

    while (i > 0) {
        if (data[i] == ')' and (i == 0 or data[i - 1] != '\\')) {
            paren_depth += 1;
        } else if (data[i] == '(' and (i == 0 or data[i - 1] != '\\')) {
            if (paren_depth == 0) {
                return i + 1;
            }
            paren_depth -= 1;
        }
        i -= 1;
    }
    return null;
}

/// Find end of string (matching ')' for Tj)
fn findStringEnd(data: []const u8, start: usize) ?usize {
    if (data[start] != '(') return null;
    var i = start + 1;
    var paren_depth: usize = 1;

    while (i < data.len and paren_depth > 0) {
        if (data[i] == '\\') {
            i += 2; // Skip escaped char
        } else if (data[i] == '(') {
            paren_depth += 1;
            i += 1;
        } else if (data[i] == ')') {
            paren_depth -= 1;
            if (paren_depth == 0) {
                return i;
            }
            i += 1;
        } else {
            i += 1;
        }
    }
    return null;
}

/// Find array end (matching ']')
fn findArrayEnd(data: []const u8, start: usize) ?usize {
    var i = start;
    var depth: usize = 1;

    while (i < data.len and depth > 0) {
        if (data[i] == '[') {
            depth += 1;
        } else if (data[i] == ']') {
            depth -= 1;
            if (depth == 0) return i + 1;
        }
        i += 1;
    }
    return null;
}

/// Extract Info field from PDF
fn extractInfoField(pdf_data: []const u8, field: []const u8) ?[]const u8 {
    const search = try std.fmt.allocPrint(std.heap.page_allocator, "/{s} ", .{field});
    defer std.heap.page_allocator.free(search);

    const pos = std.mem.indexOf(u8, pdf_data, search) orelse return null;
    const start = pos + search.len;

    if (start >= pdf_data.len) return null;

    if (pdf_data[start] == '(') {
        return findStringEnd(pdf_data, start);
    } else if (pdf_data[start] == '<') {
        // Hex string
        const end = std.mem.indexOf(u8, pdf_data[start..], ">") orelse return null;
        return pdf_data[start + 1 .. start + end];
    }

    return null;
}
