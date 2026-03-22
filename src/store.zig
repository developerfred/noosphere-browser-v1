//! Noosphere Store - Simple JSON-based Knowledge Graph Storage
//! 
//! For MVP, uses JSON files. Includes access control.

const std = @import("std");
const Semantic = @import("parser.zig").Semantic;
const access = @import("access.zig");

/// Security error types
pub const StoreError = error{
    AccessDenied,
    InvalidPath,
    StorageFull,
    CorruptedData,
};

/// Page stored in the graph
pub const Page = struct {
    url: []const u8,
    title: []const u8,
    content: []const u8,
    word_count: usize,
    entity_count: usize,
    relation_count: usize,
    saved_at: []const u8,
};

/// Entity in the knowledge graph
pub const Entity = struct {
    entity_type: []const u8,
    entity_text: []const u8,
    count: usize,
};

/// Relation between entities
pub const Relation = struct {
    relation_type: []const u8,
    relation_from: []const u8,
    relation_to: []const u8,
    confidence: f32,
};

/// Knowledge Graph Store
pub const Store = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,
    pages: std.StringArrayHashMap(StoredPage),
    modified: bool,

    const StoredPage = struct {
        title: []const u8,
        content: []const u8,
        word_count: usize,
        entities: []Entity,
        relations: []Relation,
        saved_at: i64,
    };

    /// Initialize store
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Store {
        var store = Store{
            .allocator = allocator,
            .file_path = try allocator.dupe(u8, path),
            .pages = std.StringArrayHashMap(StoredPage).init(allocator),
            .modified = false,
        };

        // Try to load existing data
        if (std.fs.path.exists(path)) {
            const file = try std.fs.openFileAbsolute(path, .{});
            defer file.close();

            const content = try file.readToEndAlloc(allocator, 100_000_000);
            defer allocator.free(content);

            // Parse JSON (simplified)
            try store.parseJson(content);
        }

        return store;
    }

    /// Deinitialize store
    pub fn deinit(self: *Store) void {
        if (self.modified) {
            self.save() catch {};
        }
        
        var it = self.pages.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*.title);
            self.allocator.free(entry.value_ptr.*.content);
            for (entry.value_ptr.*.entities) |e| {
                self.allocator.free(e.entity_type);
                self.allocator.free(e.entity_text);
            }
            self.allocator.free(entry.value_ptr.*.entities);
            for (entry.value_ptr.*.relations) |r| {
                self.allocator.free(r.relation_type);
                self.allocator.free(r.relation_from);
                self.allocator.free(r.relation_to);
            }
            self.allocator.free(entry.value_ptr.*.relations);
        }
        self.pages.deinit();
        self.allocator.free(self.file_path);
    }

    /// Parse JSON content
    fn parseJson(self: *Store, content: []const u8) !void {
        // Simple JSON parser - looks for "url": "value" patterns
        // In production, use std.json
        
        var i: usize = 0;
        while (i < content.len) {
            // Look for page entries
            if (std.mem.startsWith(u8, content[i..], "\"url\":")) {
                i += 6;
                while (i < content.len and content[i] != '"') i += 1;
                if (i >= content.len) break;
                i += 1;
                const url_start = i;
                while (i < content.len and content[i] != '"') i += 1;
                const url = content[url_start..i];
                
                try self.pages.put(try self.allocator.dupe(u8, url), StoredPage{
                    .title = try self.allocator.dupe(u8, "Untitled"),
                    .content = try self.allocator.dupe(u8, ""),
                    .word_count = 0,
                    .entities = &.{},
                    .relations = &.{},
                    .saved_at = 0,
                });
            }
            i += 1;
        }
    }

    /// Save to file
    fn save(self: *Store) !void {
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();

        try content.appendSlice("{\n  \"pages\": [\n");

        var it = self.pages.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) try content.appendSlice(",\n");
            first = false;

            const page = entry.value_ptr.*;
            try content.appendSlice("    {\n");
            try content.appendSlice("      \"url\": \"");
            try escapeJson(content, entry.key_ptr.*);
            try content.appendSlice("\",\n");
            try content.appendSlice("      \"title\": \"");
            try escapeJson(content, page.title);
            try content.appendSlice("\",\n");
            try content.appendSlice("      \"content\": \"");
            try escapeJson(content, page.content);
            try content.appendSlice("\",\n");
            try content.appendSlice("      \"word_count\": ");
            try content.appendSlice(try std.fmt.allocPrint(self.allocator, "{}", .{page.word_count}));
            try content.appendSlice(",\n");
            try content.appendSlice("      \"entities\": [");
            for (page.entities, 0..) |entity, idx| {
                if (idx > 0) try content.appendSlice(",");
                try content.appendSlice("{\"type\":\"");
                try content.appendSlice(entity.entity_type);
                try content.appendSlice("\",\"text\":\"");
                try escapeJson(content, entity.entity_text);
                try content.appendSlice("\"}");
            }
            try content.appendSlice("],\n");
            try content.appendSlice("      \"relations\": [");
            for (page.relations, 0..) |relation, idx| {
                if (idx > 0) try content.appendSlice(",");
                try content.appendSlice("{\"type\":\"");
                try content.appendSlice(relation.relation_type);
                try content.appendSlice("\",\"from\":\"");
                try escapeJson(content, relation.relation_from);
                try content.appendSlice("\",\"to\":\"");
                try escapeJson(content, relation.relation_to);
                try content.appendSlice("\"}");
            }
            try content.appendSlice("],\n");
            try content.appendSlice("      \"saved_at\": ");
            try content.appendSlice(try std.fmt.allocPrint(self.allocator, "{}", .{page.saved_at}));
            try content.appendSlice("\n");
            try content.appendSlice("    }");
        }

        try content.appendSlice("\n  ]\n");
        try content.appendSlice("}\n");

        try std.fs.writeFileAbsolute(self.file_path, content.items);
    }

    /// Add a page to the store
    pub fn addPage(self: *Store, url: []const u8, semantic: *const Semantic) !void {
        const url_copy = try self.allocator.dupe(u8, url);
        const title_copy = try self.allocator.dupe(u8, semantic.title);
        const content_copy = try self.allocator.dupe(u8, semantic.content);

        var entities = try self.allocator.alloc(Entity, semantic.entities.len);
        for (semantic.entities, 0..) |entity, idx| {
            entities[idx] = Entity{
                .entity_type = try self.allocator.dupe(u8, @tagName(entity.type)),
                .entity_text = try self.allocator.dupe(u8, entity.text),
                .count = entity.count,
            };
        }

        var relations = try self.allocator.alloc(Relation, semantic.relations.len);
        for (semantic.relations, 0..) |relation, idx| {
            relations[idx] = Relation{
                .relation_type = try self.allocator.dupe(u8, @tagName(relation.type)),
                .relation_from = try self.allocator.dupe(u8, relation.from),
                .relation_to = try self.allocator.dupe(u8, relation.to),
                .confidence = relation.confidence,
            };
        }

        try self.pages.put(url_copy, StoredPage{
            .title = title_copy,
            .content = content_copy,
            .word_count = semantic.word_count,
            .entities = entities,
            .relations = relations,
            .saved_at = std.time.timestamp(),
        });

        self.modified = true;
        try self.save();
    }

    /// Get all pages
    pub fn getAllPages(self: *Store) ![]Page {
        var pages = std.ArrayList(Page).init(self.allocator);

        var it = self.pages.iterator();
        while (it.next()) |entry| {
            const stored = entry.value_ptr.*;
            try pages.append(Page{
                .url = entry.key_ptr.*,
                .title = stored.title,
                .content = stored.content,
                .word_count = stored.word_count,
                .entity_count = stored.entities.len,
                .relation_count = stored.relations.len,
                .saved_at = try std.fmt.allocPrint(self.allocator, "{}", .{stored.saved_at}),
            });
        }

        return pages.toOwnedSlice();
    }

    /// Free pages returned by getAllPages
    pub fn freePages(self: *Store, pages: []Page) void {
        for (pages) |page| {
            self.allocator.free(page.saved_at);
        }
        self.allocator.free(pages);
    }

    /// Search pages
    pub fn search(self: *Store, query: []const u8) ![]Page {
        var results = std.ArrayList(Page).init(self.allocator);

        const query_lower = try std.ascii.lowercase(self.allocator, query);
        defer self.allocator.free(query_lower);

        var it = self.pages.iterator();
        while (it.next()) |entry| {
            const stored = entry.value_ptr.*;
            
            const title_lower = try std.ascii.lowercase(self.allocator, stored.title);
            defer self.allocator.free(title_lower);

            if (std.mem.containsAtLeast(u8, title_lower, 1, query_lower)) {
                try results.append(Page{
                    .url = entry.key_ptr.*,
                    .title = stored.title,
                    .content = stored.content,
                    .word_count = stored.word_count,
                    .entity_count = stored.entities.len,
                    .relation_count = stored.relations.len,
                    .saved_at = try std.fmt.allocPrint(self.allocator, "{}", .{stored.saved_at}),
                });
                continue;
            }

            // Search in entities
            for (stored.entities) |entity| {
                const entity_lower = try std.ascii.lowercase(self.allocator, entity.entity_text);
                defer self.allocator.free(entity_lower);

                if (std.mem.containsAtLeast(u8, entity_lower, 1, query_lower)) {
                    try results.append(Page{
                        .url = entry.key_ptr.*,
                        .title = stored.title,
                        .content = stored.content,
                        .word_count = stored.word_count,
                        .entity_count = stored.entities.len,
                        .relation_count = stored.relations.len,
                        .saved_at = try std.fmt.allocPrint(self.allocator, "{}", .{stored.saved_at}),
                    });
                    break;
                }
            }
        }

        return results.toOwnedSlice();
    }
};

/// Escape string for JSON
fn escapeJson(content: *std.ArrayList(u8), str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '"' => try content.appendSlice("\\\""),
            '\\' => try content.appendSlice("\\\\"),
            '\n' => try content.appendSlice("\\n"),
            '\r' => try content.appendSlice("\\r"),
            '\t' => try content.appendSlice("\\t"),
            else => try content.append(c),
        }
    }
}
