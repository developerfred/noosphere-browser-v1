//! Noosphere PDF Full Parser
//! 
//! Full PDF parsing using C library (poppler/mupdf).
//! For ArXiv papers and complex documents.

const std = @import("std");
const fs = std.fs;

pub const PDFFullDocument = struct {
    pages: []PDFPageFull,
    metadata: PDFMetadataFull,
    toc: []TOCEntry,
    text_content: []const u8,
};

pub const PDFPageFull = struct {
    page_num: u32,
    width: f32,
    height: f32,
    text: []const u8,
    images: []PDFImage,
    fonts: []PDFFont,
};

pub const PDFImage = struct {
    xobj_id: []const u8,
    width: u32,
    height: u32,
    bpc: u32,
    colorspace: []const u8,
    filter: []const u8,
    data_offset: usize,
    data_length: usize,
};

pub const PDFFont = struct {
    name: []const u8,
    type: []const u8,
    encoding: []const u8,
    embedded: bool,
};

pub const PDFMetadataFull = struct {
    title: []const u8,
    author: []const u8,
    subject: []const u8,
    keywords: []const u8,
    creator: []const u8,
    producer: []const u8,
    creation_date: []const u8,
    mod_date: []const u8,
    pdf_version: []const u8,
    page_count: u32,
    encrypted: bool,
    linearized: bool,
};

pub const TOCTreeEntry = struct {
    title: []const u8,
    level: u32,
    page: u32,
    kids: []TOCTreeEntry,
};

/// Full PDF parser with C library integration
pub const PDFParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PDFParser {
        return PDFParser{ .allocator = allocator };
    }

    /// Check if poppler is available
    pub fn hasPoppler(self: *PDFParser) bool {
        // Check if pdftotext command exists
        const result = std.ChildProcess.exec(.{
            .argv = &.{ "which", "pdftotext" },
        }) catch return false;

        return result.term.Exited == 0;
    }

    /// Check if mutool is available
    pub fn hasMutool(self: *PDFParser) bool {
        const result = std.ChildProcess.exec(.{
            .argv = &.{ "which", "mutool" },
        }) catch return false;

        return result.term.Exited == 0;
    }

    /// Extract text using pdftotext (poppler)
    pub fn extractTextPdftotext(self: *PDFParser, filepath: []const u8) ![]const u8 {
        const result = try std.ChildProcess.exec(.{
            .argv = &.{ "pdftotext", "-layout", filepath, "-" },
        });

        if (result.term.Exited != 0) {
            return error.ExtractionFailed;
        }

        return try self.allocator.dupe(u8, result.stdout);
    }

    /// Extract text using mutool (mupdf)
    pub fn extractTextMutool(self: *PDFParser, filepath: []const u8) ![]const u8 {
        const result = try std.ChildProcess.exec(.{
            .argv = &.{ "mutool", "draw", "-F", "txt", "-o", "-", filepath },
        });

        if (result.term.Exited != 0) {
            return error.ExtractionFailed;
        }

        return try self.allocator.dupe(u8, result.stdout);
    }

    /// Extract metadata using pdfinfo
    pub fn extractMetadataPdfinfo(self: *PDFParser, filepath: []const u8) !PDFMetadataFull {
        const result = try std.ChildProcess.exec(.{
            .argv = &.{ "pdfinfo", "-meta", filepath },
        });

        if (result.term.Exited != 0) {
            return error.MetadataExtractionFailed;
        }

        return parsePdfinfoOutput(self.allocator, result.stdout);
    }

    /// Extract TOC using pdftotext with TOC page
    pub fn extractTOC(self: *PDFParser, filepath: []const u8) ![]TOCTreeEntry {
        // Try to extract outline using mutool
        const result = try std.ChildProcess.exec(.{
            .argv = &.{ "mutool", "show", filepath, "outline" },
        });

        if (result.term.Exited != 0) {
            return &.{};
        }

        return parseOutline(self.allocator, result.stdout);
    }

    /// Extract images from PDF
    pub fn extractImages(self: *PDFParser, filepath: []const u8, output_dir: []const u8) ![]PDFImage {
        // Use mutool to extract images
        try std.ChildProcess.exec(.{
            .argv &.{ "mutool", "convert", "-F", "png", "-o", output_dir, filepath },
        });

        // Parse output to get image list
        return &.{};
    }

    /// Full extraction using best available tool
    pub fn extractFull(self: *PDFParser, filepath: []const u8) !PDFFullDocument {
        var doc = PDFFullDocument{
            .pages = try self.allocator.alloc(PDFPageFull, 0),
            .metadata = PDFMetadataFull{
                .title = "",
                .author = "",
                .subject = "",
                .keywords = "",
                .creator = "",
                .producer = "",
                .creation_date = "",
                .mod_date = "",
                .pdf_version = "",
                .page_count = 0,
                .encrypted = false,
                .linearized = false,
            },
            .toc = &.{},
            .text_content = "",
        };

        // Try mutool first (better for complex PDFs)
        if (self.hasMutool()) {
            doc.text_content = try self.extractTextMutool(filepath);
            doc.metadata = try self.extractMetadataPdfinfo(filepath) catch doc.metadata;
            doc.toc = try self.extractTOC(filepath);
        } else if (self.hasPoppler()) {
            doc.text_content = try self.extractTextPdftotext(filepath);
            doc.metadata = try self.extractMetadataPdfinfo(filepath) catch doc.metadata;
        } else {
            return error.NoPDFToolAvailable;
        }

        return doc;
    }

    /// Install dependencies (for reference)
    pub fn installDeps(self: *PDFParser) !void {
        // These would be run as shell commands
        // apt-get install poppler-utils mupdf-tools
        _ = self;
    }
});

/// Parse pdfinfo output
fn parsePdfinfoOutput(allocator: std.mem.Allocator, output: []const u8) PDFMetadataFull {
    var metadata = PDFMetadataFull{
        .title = "",
        .author = "",
        .subject = "",
        .keywords = "",
        .creator = "",
        .producer = "",
        .creation_date = "",
        .mod_date = "",
        .pdf_version = "",
        .page_count = 0,
        .encrypted = false,
        .linearized = false,
    };

    var lines = std.mem.split(u8, output, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "Title:")) {
            metadata.title = std.mem.trim(u8, line[6..], " \t");
        } else if (std.mem.startsWith(u8, line, "Author:")) {
            metadata.author = std.mem.trim(u8, line[6..], " \t");
        } else if (std.mem.startsWith(u8, line, "Subject:")) {
            metadata.subject = std.mem.trim(u8, line[8..], " \t");
        } else if (std.mem.startsWith(u8, line, "Keywords:")) {
            metadata.keywords = std.mem.trim(u8, line[10..], " \t");
        } else if (std.mem.startsWith(u8, line, "Creator:")) {
            metadata.creator = std.mem.trim(u8, line[8..], " \t");
        } else if (std.mem.startsWith(u8, line, "Producer:")) {
            metadata.producer = std.mem.trim(u8, line[9..], " \t");
        } else if (std.mem.startsWith(u8, line, "CreationDate:")) {
            metadata.creation_date = std.mem.trim(u8, line[13..], " \t");
        } else if (std.mem.startsWith(u8, line, "ModDate:")) {
            metadata.mod_date = std.mem.trim(u8, line[8..], " \t");
        } else if (std.mem.startsWith(u8, line, "PDF version:")) {
            metadata.pdf_version = std.mem.trim(u8, line[12..], " \t");
        } else if (std.mem.startsWith(u8, line, "Pages:")) {
            const count_str = std.mem.trim(u8, line[6..], " \t");
            metadata.page_count = std.fmt.parseInt(u32, count_str, 10) catch 0;
        } else if (std.mem.startsWith(u8, line, "Encrypted:")) {
            metadata.encrypted = std.mem.indexOf(u8, line, "Yes") != null;
        } else if (std.mem.startsWith(u8, line, "Linearized:")) {
            metadata.linearized = std.mem.indexOf(u8, line, "Yes") != null;
        }
    }

    _ = allocator;
    return metadata;
}

/// Parse mutool outline output
fn parseOutline(allocator: std.mem.Allocator, output: []const u8) []TOCTreeEntry {
    var entries = std.ArrayList(TOCTreeEntry).init(allocator);
    var lines = std.mem.split(u8, output, "\n");

    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // Count indentation (depth level)
        var level: u32 = 0;
        for (line) |c| {
            if (c == ' ') {
                level += 1;
            } else if (c != ' ' and c != '\t') {
                break;
            }
        }

        // Skip if just whitespace
        const title = std.mem.trim(u8, line, " \t");
        if (title.len == 0) continue;

        // Parse page number from parentheses if present
        // Format: "    Title (page 123)"
        var page: u32 = 0;
        const page_start = std.mem.lastIndexOf(u8, title, "(page ") orelse {
            try entries.append(TOCTreeEntry{
                .title = try allocator.dupe(u8, title),
                .level = level,
                .page = 0,
                .kids = &.{},
            });
            continue;
        };

        const page_str = title[page_start + 6 .. title.len - 1];
        page = std.fmt.parseInt(u32, page_str, 10) catch 0;

        const entry_title = std.mem.trim(u8, title[0..page_start], " \t");

        try entries.append(TOCTreeEntry{
            .title = try allocator.dupe(u8, entry_title),
            .level = level,
            .page = page,
            .kids = &.{},
        });
    }

    return entries.toOwnedSlice();
}
