//! Noosphere Vector Embeddings
//! 
//! Generate and store vector embeddings for RAG.
//! Simple local embeddings without external APIs.

const std = @import("std");
const chunk = @import("chunk.zig");

/// Embedding vector
pub const Embedding = struct {
    text: []const u8,
    vector: []f32,
    model: []const u8,
};

/// Embedding result
pub const EmbedResult = struct {
    embeddings: []Embedding,
    dimensions: u32,
    model: []const u8,
};

/// Simple hash-based embedding generator
/// Note: For production, use proper embedding models (OpenAI, local transformers, etc.)
pub const Embedder = struct {
    allocator: std.mem.Allocator,
    dimensions: u32,

    pub fn init(allocator: std.mem.Allocator, dimensions: u32) Embedder {
        return Embedder{
            .allocator = allocator,
            .dimensions = dimensions,
        };
    }

    /// Generate embedding for text
    /// Uses a simple word frequency hash for demonstration
    /// In production, use proper embedding models
    pub fn embed(self: *Embedder, text: []const u8, model: []const u8) !Embedding {
        var vector = try self.allocator.alloc(f32, self.dimensions);

        // Simple hashing based on word frequencies
        const words = splitWords(text);
        var hash: u64 = 0;

        for (words) |word| {
            const word_hash = hashWord(word);
            hash ^= word_hash;

            // Spread hash across vector dimensions
            var i: usize = 0;
            while (i < self.dimensions) {
                const idx = (word_hash >> @truncate(u6, i)) % @as(u32, self.dimensions);
                const val = @as(f32, @floatFromInt(word_hash >> @truncate(u8, idx % 64))) / std.math.floatMax(f32);
                vector[idx] += val;
                i += 1;
            }
        }

        // Normalize
        normalize(vector);

        return Embedding{
            .text = try self.allocator.dupe(u8, text),
            .vector = vector,
            .model = try self.allocator.dupe(u8, model),
        };
    }

    /// Generate embeddings for chunks
    pub fn embedChunks(self: *Embedder, chunks: []chunk.Chunk, model: []const u8) !EmbedResult {
        var embeddings = std.ArrayList(Embedding).init(self.allocator);

        for (chunks) |chunk_item| {
            const emb = try self.embed(chunk_item.text, model);
            try embeddings.append(emb);
        }

        return EmbedResult{
            .embeddings = try embeddings.toOwnedSlice(),
            .dimensions = self.dimensions,
            .model = try self.allocator.dupe(u8, model),
        };
    }

    /// Calculate cosine similarity between two vectors
    pub fn cosineSimilarity(self: *Embedder, a: []f32, b: []f32) f32 {
        _ = self;

        if (a.len != b.len) return 0;

        var dot: f32 = 0;
        var norm_a: f32 = 0;
        var norm_b: f32 = 0;

        var i: usize = 0;
        while (i < a.len) {
            dot += a[i] * b[i];
            norm_a += a[i] * a[i];
            norm_b += b[i] * b[i];
            i += 1;
        }

        const mag = std.math.sqrt(norm_a) * std.math.sqrt(norm_b);
        if (mag < 0.0001) return 0;

        return dot / mag;
    }

    /// Find most similar embedding
    pub fn findMostSimilar(self: *Embedder, query: []const u8, embeddings: []Embedding, model: []const u8) !?struct { embedding: *const Embedding, similarity: f32 } {
        const query_emb = try self.embed(query, model);

        var best: ?*const Embedding = null;
        var best_sim: f32 = 0;

        for (embeddings) |*emb| {
            const sim = self.cosineSimilarity(query_emb.vector, emb.vector);
            if (sim > best_sim) {
                best_sim = sim;
                best = emb;
            }
        }

        if (best) |b| {
            return .{ .embedding = b, .similarity = best_sim };
        }

        return null;
    }
});

/// Split text into words
fn splitWords(text: []const u8) [][]const u8 {
    var words = std.ArrayList([]const u8);

    var word_start: ?usize = null;
    for (text, 0..) |c, i| {
        if (std.ascii.isAlphanumeric(c)) {
            if (word_start == null) word_start = i;
        } else {
            if (word_start) |start| {
                try words.append(text[start..i]);
                word_start = null;
            }
        }
    }

    if (word_start) |start| {
        try words.append(text[start..text.len]);
    }

    return words.items;
}

/// Hash a word to u64
fn hashWord(word: []const u8) u64 {
    var h: u64 = 0;
    for (word) |c| {
        h = h *% 31 +% @as(u64, c);
    }
    return h;
}

/// Normalize vector to unit length
fn normalize(vec: []f32) void {
    var norm: f32 = 0;
    for (vec) |v| {
        norm += v * v;
    }
    norm = std.math.sqrt(norm);

    if (norm > 0.0001) {
        for (vec) |*v| {
            v.* /= norm;
        }
    }
}

/// Embedding store for persistence
pub const EmbeddingStore = struct {
    allocator: std.mem.Allocator,
    embeddings: std.ArrayList(Embedding),
    dimensions: u32,

    pub fn init(allocator: std.mem.Allocator) EmbeddingStore {
        return EmbeddingStore{
            .allocator = allocator,
            .embeddings = std.ArrayList(Embedding).init(allocator),
            .dimensions = 384,
        };
    }

    pub fn deinit(self: *EmbeddingStore) void {
        for (self.embeddings.items) |emb| {
            self.allocator.free(emb.text);
            self.allocator.free(emb.vector);
            self.allocator.free(emb.model);
        }
        self.embeddings.deinit();
    }

    /// Add embedding
    pub fn add(self: *EmbeddingStore, emb: Embedding) !void {
        try self.embeddings.append(emb);
    }

    /// Search for similar
    pub fn search(self: *EmbeddingStore, query: []const u8, model: []const u8, top_k: u32) ![]struct { embedding: *const Embedding, similarity: f32 } {
        var embedder = Embedder.init(self.allocator, self.dimensions);
        const query_emb = try embedder.embed(query, model);

        // Calculate similarities
        var results = std.ArrayList(struct { embedding: *const Embedding, similarity: f32 }).init(self.allocator);

        for (self.embeddings.items) |*emb| {
            const sim = embedder.cosineSimilarity(query_emb.vector, emb.vector);
            try results.append(.{ .embedding = emb, .similarity = sim });
        }

        // Sort by similarity
        std.mem.sort(struct { embedding: *const Embedding, similarity: f32 }, results.items, {}, struct {
            fn less(_: void, a: struct { embedding: *const Embedding, similarity: f32 }, b: struct { embedding: *const Embedding, similarity: f32 }) bool {
                return a.similarity > b.similarity;
            }
        }.less);

        // Return top k
        const count = @min(top_k, @as(u32, @intCast(results.items.len)));
        return results.items[0..count];
    }

    /// Save to JSON
    pub fn save(self: *EmbeddingStore, writer: anytype) !void {
        try writer.writeAll("{\"embeddings\":[\n");

        for (self.embeddings.items, 0..) |emb, i| {
            try writer.writeAll("{\"text\":\"");
            try writer.writeAll(emb.text);
            try writer.writeAll("\",\"vector\":[");
            
            for (emb.vector, 0..) |v, j| {
                try std.fmt.format(writer, "{d}", .{v});
                if (j < emb.vector.len - 1) try writer.writeAll(",");
            }
            
            try writer.writeAll("],\"model\":\"");
            try writer.writeAll(emb.model);
            try writer.writeAll("\"}");
            
            if (i < self.embeddings.items.len - 1) try writer.writeAll(",");
            try writer.writeAll("\n");
        }

        try writer.writeAll("],\"dimensions\":");
        try std.fmt.formatInt(self.dimensions, 10, .lower, .{}, writer);
        try writer.writeAll("}\n");
    }
};
