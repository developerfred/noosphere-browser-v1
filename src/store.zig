//! Simple JSON Store for Noosphere
//! 
//! Stores semantic data in JSON files.
//! No external dependencies - works on Raspberry Pi out of the box.

const std = @import("std");
const Semantic = @import("parser.zig").Semantic;

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

/// Store wraps file-based JSON storage
pub const Store = struct {
    file_path: []const u8,
    allocator: std.mem.Allocator,
    pages: std.StringArrayHashMap(PageData),
    
    const PageData = struct {
        title: []const u8,
        content: []const u8,
        word_count: usize,
        entities: []EntityData,
        relations: []RelationData,
        saved_at: []const u8,
    };
    
    const EntityData = struct {
        type: []const u8,
        text: []const u8,
        count: usize,
    };
    
    const RelationData = struct {
        type: []const u8,
        from: []const u8,
        to: []const u8,
        confidence: f32,
    };
    
    pub fn init(path: []const u8) !Store {
        var store = Store{
            .file_path = try std.heap.page_allocator.dupe(u8, path),
            .allocator = std.heap.page_allocator,
            .pages = std.StringArrayHashMap(PageData).init(std.heap.page_allocator),
        };
        
        // Try to load existing data
        if (std.fs.path.exists(path)) {
            const file = try std.fs.openFileAbsolute(path, .{});
            defer file.close();
            
            const content = try file.readToEndAlloc(store.allocator, 1_000_000);
            defer store.allocator.free(content);
            
            // Parse JSON (simplified - just look for URLs)
            // In production, use std.json
            _ = content;
        }
        
        return store;
    }
    
    pub fn deinit(self: *Store) void {
        self.save() catch {};
        self.allocator.free(self.file_path);
        
        var it = self.pages.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*.title);
            self.allocator.free(entry.value_ptr.*.content);
            for (entry.value_ptr.*.entities) |e| {
                self.allocator.free(e.type);
                self.allocator.free(e.text);
            }
            self.allocator.free(entry.value_ptr.*.entities);
            for (entry.value_ptr.*.relations) |r| {
                self.allocator.free(r.type);
                self.allocator.free(r.from);
                self.allocator.free(r.to);
            }
            self.allocator.free(entry.value_ptr.*.relations);
            self.allocator.free(entry.value_ptr.*.saved_at);
        }
        self.pages.deinit();
    }
    
    pub fn addPage(self: *Store, url: []const u8, semantic: *const Semantic) !void {
        const allocator = self.allocator;
        
        // Convert entities
        var entities = try allocator.alloc(EntityData, semantic.entities.len);
        for (semantic.entities, 0..) |entity, idx| {
            entities[idx] = EntityData{
                .type = try allocator.dupe(u8, @tagName(entity.type)),
                .text = try allocator.dupe(u8, entity.text),
                .count = entity.count,
            };
        }
        
        // Convert relations
        var relations = try allocator.alloc(RelationData, semantic.relations.len);
        for (semantic.relations, 0..) |relation, idx| {
            relations[idx] = RelationData{
                .type = try allocator.dupe(u8, @tagName(relation.type)),
                .from = try allocator.dupe(u8, relation.from),
                .to = try allocator.dupe(u8, relation.to),
                .confidence = relation.confidence,
            };
        }
        
        // Create timestamp
        const now = std.time.Timestamp.now();
        const time_str = try std.fmt.allocPrint(allocator, "{}", .{now});
        
        const page_data = PageData{
            .title = try allocator.dupe(u8, semantic.title),
            .content = try allocator.dupe(u8, semantic.content),
            .word_count = semantic.word_count,
            .entities = entities,
            .relations = relations,
            .saved_at = time_str,
        };
        
        try self.pages.put(try allocator.dupe(u8, url), page_data);
        try self.save();
    }
    
    pub fn getAllPages(self: *Store) ![]Page {
        var pages = std.ArrayList(Page).init(self.allocator);
        defer pages.deinit();
        
        var it = self.pages.iterator();
        while (it.next()) |entry| {
            const data = entry.value_ptr.*;
            try pages.append(Page{
                .url = entry.key_ptr.*,
                .title = data.title,
                .content = data.content,
                .word_count = data.word_count,
                .entity_count = data.entities.len,
                .relation_count = data.relations.len,
                .saved_at = data.saved_at,
            });
        }
        
        return pages.toOwnedSlice();
    }
    
    pub fn freePages(self: *Store, pages: []Page) void {
        // No-op since we don't own the data
        _ = self;
        _ = pages;
    }
    
    pub fn search(self: *Store, query: []const u8) ![]Page {
        var results = std.ArrayList(Page).init(self.allocator);
        defer results.deinit();
        
        const query_lower = std.ascii.lowerString(self.allocator, query);
        defer self.allocator.free(query_lower);
        
        var it = self.pages.iterator();
        while (it.next()) |entry| {
            const data = entry.value_ptr.*;
            
            // Simple search: check title, content, and entities
            const title_lower = std.ascii.lowerString(self.allocator, data.title);
            defer self.allocator.free(title_lower);
            
            if (std.mem.containsAtLeast(u8, title_lower, 1, query_lower)) {
                try results.append(Page{
                    .url = entry.key_ptr.*,
                    .title = data.title,
                    .content = data.content,
                    .word_count = data.word_count,
                    .entity_count = data.entities.len,
                    .relation_count = data.relations.len,
                    .saved_at = data.saved_at,
                });
                continue;
            }
            
            // Check entities
            for (data.entities) |entity| {
                const entity_lower = std.ascii.lowerString(self.allocator, entity.text);
                defer self.allocator.free(entity_lower);
                
                if (std.mem.containsAtLeast(u8, entity_lower, 1, query_lower)) {
                    try results.append(Page{
                        .url = entry.key_ptr.*,
                        .title = data.title,
                        .content = data.content,
                        .word_count = data.word_count,
                        .entity_count = data.entities.len,
                        .relation_count = data.relations.len,
                        .saved_at = data.saved_at,
                    });
                    break;
                }
            }
        }
        
        return results.toOwnedSlice();
    }
    
    fn save(self: *Store) !void {
        // Simple JSON-like format
        var content = std.ArrayList(u8).init(self.allocator);
        defer content.deinit();
        
        try content.appendSlice("{\n");
        try content.appendSlice("  \"pages\": [\n");
        
        var it = self.pages.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) try content.appendSlice(",\n");
            first = false;
            
            const data = entry.value_ptr.*;
            try content.appendSlice("    {\n");
            try content.appendSlice("      \"url\": \"");
            try escapeJson(content, entry.key_ptr.*);
            try content.appendSlice("\",\n");
            try content.appendSlice("      \"title\": \"");
            try escapeJson(content, data.title);
            try content.appendSlice("\",\n");
            try content.appendSlice("      \"word_count\": ");
            try content.appendSlice(try std.fmt.allocPrint(self.allocator, "{}", .{data.word_count}));
            try content.appendSlice(",\n");
            try content.appendSlice("      \"entities\": ");
            try content.appendSlice("[");
            for (data.entities, 0..) |entity, idx| {
                if (idx > 0) try content.appendSlice(",");
                try content.appendSlice("{\"type\":\"");
                try content.appendSlice(entity.type);
                try content.appendSlice("\",\"text\":\"");
                try escapeJson(content, entity.text);
                try content.appendSlice("\"}");
            }
            try content.appendSlice("],\n");
            try content.appendSlice("      \"saved_at\": \"");
            try content.appendSlice(data.saved_at);
            try content.appendSlice("\"\n");
            try content.appendSlice("    }");
        }
        
        try content.appendSlice("\n  ]\n");
        try content.appendSlice("}\n");
        
        // Write to file
        try std.fs.writeFileAbsolute(self.file_path, content.items);
    }
    
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
};
