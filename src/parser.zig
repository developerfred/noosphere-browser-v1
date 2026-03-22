//! HTML Parser for Noosphere
//! 
//! Transforms HTML into semantic data: Markdown + entities + relations.
//! Minimal dependencies, works on Raspberry Pi.

const std = @import("std");

/// Semantic data extracted from a page
pub const Semantic = struct {
    title: []const u8,
    content: []const u8,
    word_count: usize,
    entities: []Entity,
    relations: []Relation,
};

/// A named entity extracted from text
pub const Entity = struct {
    type: EntityType,
    text: []const u8,
    count: usize,
};

pub const EntityType = enum {
    person,
    organization,
    location,
    date,
    number,
    url,
    other,
};

/// A relation between entities
pub const Relation = struct {
    type: RelationType,
    from: []const u8,
    to: []const u8,
    confidence: f32,
};

pub const RelationType = enum {
    co_occurs,
    cites,
    references,
    located_in,
    works_for,
    born_in,
    related_to,
};

/// Parse HTML content and extract semantic data
pub fn parse(html: []const u8) !Semantic {
    // For MVP, we'll use a simple regex-based approach
    // In production, this would use a proper HTML parser
    
    const allocator = std.heap.page_allocator;
    
    // Extract title
    const title = extractTitle(html);
    
    // Extract text content (simplified)
    const text = extractText(html);
    const word_count = countWords(text);
    
    // Extract entities
    var entities = std.ArrayList(Entity).init(allocator);
    try extractEntities(text, &entities);
    
    // Extract relations
    var relations = std.ArrayList(Relation).init(allocator);
    try extractRelations(entities.items, text, &relations);
    
    // Convert to Markdown
    const content = htmlToMarkdown(html);
    
    return Semantic{
        .title = title,
        .content = content,
        .word_count = word_count,
        .entities = try entities.toOwnedSlice(),
        .relations = try relations.toOwnedSlice(),
    };
}

fn extractTitle(html: []const u8) []const u8 {
    // Simple title extraction
    if (std.mem.indexOf(u8, html, "<title>")) |start| {
        const begin = start + 7;
        if (std.mem.indexOf(u8, html[begin..], "</title>")) |end| {
            return std.mem.trim(u8, html[begin..begin + end], " \t\r\n");
        }
    }
    
    // Fallback to og:title
    if (std.mem.indexOf(u8, html, "property=\"og:title\"")) |start| {
        if (std.mem.indexOf(u8, html[start..], "content=\"")) |content_start| {
            const begin = start + content_start + 10;
            if (std.mem.indexOf(u8, html[begin..], "\"")) |content_end| {
                return std.mem.trim(u8, html[begin..begin + content_end], " \t\r\n");
            }
        }
    }
    
    return "Untitled";
}

fn extractText(html: []const u8) []const u8 {
    // Very simplified HTML tag removal
    var text = std.ArrayList(u8).init(std.heap.page_allocator);
    
    var i: usize = 0;
    var in_tag = false;
    var last_was_space = false;
    
    while (i < html.len) {
        const c = html[i];
        
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
            if (!last_was_space) {
                text.append(' ') catch {};
                last_was_space = true;
            }
        } else if (!in_tag) {
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                if (!last_was_space) {
                    text.append(' ') catch {};
                    last_was_space = true;
                }
            } else {
                text.append(c) catch {};
                last_was_space = false;
            }
        }
        
        i += 1;
    }
    
    // Trim and collapse whitespace
    const result = std.mem.trim(u8, text.items, " \t\r\n");
    return result;
}

fn countWords(text: []const u8) usize {
    var count: usize = 0;
    var in_word = false;
    
    for (text) |c| {
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            in_word = false;
        } else if (!in_word) {
            in_word = true;
            count += 1;
        }
    }
    
    return count;
}

fn extractEntities(text: []const u8, entities: *std.ArrayList(Entity)) !void {
    const allocator = std.heap.page_allocator;
    
    // Capitalized phrases (proper nouns)
    var i: usize = 0;
    while (i < text.len) {
        // Match capitalized word sequences
        if (i < text.len and std.ascii.isUpper(text[i])) {
            var j = i + 1;
            while (j < text.len and std.ascii.isLower(text[j])) j += 1;
            
            // Check if next word is also capitalized (multi-word entity)
            var next_capitalized = false;
            var k = j;
            while (k < text.len and text[k] == ' ') k += 1;
            if (k < text.len and std.ascii.isUpper(text[k])) {
                next_capitalized = true;
            }
            
            if (next_capitalized) {
                // Find full phrase
                while (j < text.len and (std.ascii.isLower(text[j]) or text[j] == ' ')) {
                    if (text[j] == ' ') {
                        j += 1;
                        while (j < text.len and text[j] == ' ') j += 1;
                        if (j < text.len and std.ascii.isUpper(text[j])) {
                            while (j < text.len and (std.ascii.isLower(text[j]) or text[j] == ' ')) {
                                if (text[j] == ' ') j += 1;
                                if (j < text.len and std.ascii.isLower(text[j])) {
                                    while (j < text.len and std.ascii.isLower(text[j])) j += 1;
                                } else break;
                            }
                            break;
                        } else break;
                    }
                    if (j < text.len and std.ascii.isLower(text[j])) {
                        while (j < text.len and std.ascii.isLower(text[j])) j += 1;
                    } else break;
                }
                
                const phrase = std.mem.trim(u8, text[i..j], " ");
                if (phrase.len > 2 and phrase.len < 100) {
                    const count = countOccurrences(text, phrase);
                    if (count > 0) {
                        try entities.append(Entity{
                            .type = .organization, // Simplified - could be person too
                            .text = try allocator.dupe(u8, phrase),
                            .count = count,
                        });
                    }
                }
            }
            
            i = j;
        } else {
            i += 1;
        }
    }
    
    // URLs
    var url_i: usize = 0;
    while (url_i < text.len) {
        if (std.mem.startsWith(u8, text[url_i..], "http://") or
            std.mem.startsWith(u8, text[url_i..], "https://")) {
            var url_end = url_i;
            while (url_end < text.len and !std.ascii.isWhitespace(text[url_end])) {
                url_end += 1;
            }
            const url = text[url_i..url_end];
            try entities.append(Entity{
                .type = .url,
                .text = try allocator.dupe(u8, url),
                .count = 1,
            });
            url_i = url_end;
        } else {
            url_i += 1;
        }
    }
}

fn countOccurrences(text: []const u8, pattern: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    
    while (i <= text.len - pattern.len) {
        if (std.mem.eql(u8, text[i..i + pattern.len], pattern)) {
            count += 1;
            i += pattern.len;
        } else {
            i += 1;
        }
    }
    
    return count;
}

fn extractRelations(entities: []Entity, text: []const u8, relations: *std.ArrayList(Relation)) !void {
    const allocator = std.heap.page_allocator;
    
    // Simple co-occurrence based relations
    for (entities) |entity| {
        const context_count = countOccurrences(text, entity.text);
        if (context_count > 1) {
            try relations.append(Relation{
                .type = .co_occurs,
                .from = entity.text,
                .to = "multiple_sources",
                .confidence = @min(@as(f32, @floatFromInt(context_count)) / 5.0, 1.0),
            });
        }
    }
}

fn htmlToMarkdown(html: []const u8) []const u8 {
    // Very simplified HTML to Markdown conversion
    // In production, use a proper parser
    
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    
    var i: usize = 0;
    var in_tag = false;
    var in_pre = false;
    
    while (i < html.len) {
        const remaining = html[i..];
        
        if (std.mem.startsWith(u8, remaining, "<h1")) {
            try result.appendSlice("\n# ");
            i += 4;
            continue;
        }
        if (std.mem.startsWith(u8, remaining, "<h2")) {
            try result.appendSlice("\n## ");
            i += 4;
            continue;
        }
        if (std.mem.startsWith(u8, remaining, "<h3")) {
            try result.appendSlice("\n### ");
            i += 4;
            continue;
        }
        if (std.mem.startsWith(u8, remaining, "<p>") or std.mem.startsWith(u8, remaining, "<p ")) {
            try result.appendSlice("\n\n");
            i += 3;
            continue;
        }
        if (std.mem.startsWith(u8, remaining, "<pre")) {
            in_pre = true;
            try result.appendSlice("\n```\n");
            i += 5;
            continue;
        }
        if (std.mem.startsWith(u8, remaining, "</pre>")) {
            in_pre = false;
            try result.appendSlice("\n```\n");
            i += 6;
            continue;
        }
        if (std.mem.startsWith(u8, remaining, "<li")) {
            try result.appendSlice("\n- ");
            i += 4;
            continue;
        }
        if (std.mem.startsWith(u8, remaining, "<a href=\"")) {
            // Extract link
            const end = std.mem.indexOf(u8, remaining[9..], "\"");
            if (end) |e| {
                try result.appendSlice("[LINK:");
                try result.appendSlice(remaining[9..9+e]);
                try result.appendSlice("] ");
            }
            i += 9;
            continue;
        }
        if (std.mem.startsWith(u8, remaining, "<title>")) {
            // Skip title tags
            i += 7;
            continue;
        }
        if (std.mem.startsWith(u8, remaining, "</title>")) {
            i += 8;
            continue;
        }
        
        const c = html[i];
        
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            if (in_pre) {
                try result.append(c);
            } else if (c == '&') {
                // HTML entities
                if (std.mem.startsWith(u8, remaining, "&amp;")) {
                    try result.append('&');
                    i += 4;
                    continue;
                }
                if (std.mem.startsWith(u8, remaining, "&lt;")) {
                    try result.append('<');
                    i += 4;
                    continue;
                }
                if (std.mem.startsWith(u8, remaining, "&gt;")) {
                    try result.append('>');
                    i += 4;
                    continue;
                }
                if (std.mem.startsWith(u8, remaining, "&quot;")) {
                    try result.append('"');
                    i += 5;
                    continue;
                }
                try result.append('&');
            } else {
                try result.append(c);
            }
        }
        
        i += 1;
    }
    
    // Trim
    const trimmed = std.mem.trim(u8, result.items, "\n ");
    return trimmed;
}
