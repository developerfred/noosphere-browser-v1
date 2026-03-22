//! Noosphere RAG Chunking
//! 
//! Text chunking strategies for RAG systems.
//! Splits content into optimal chunks for LLM context windows.

const std = @import("std");

/// Chunk configuration
pub const ChunkConfig = struct {
    max_tokens: usize = 512,
    overlap_tokens: usize = 64,
    split_by: SplitStrategy = .semantic,
};

pub const SplitStrategy = enum {
    semantic,  // Split by paragraphs/sections
    fixed,      // Fixed token count
    sentences,  // Split by sentences
};

/// Text chunk for RAG
pub const Chunk = struct {
    text: []const u8,
    tokens: usize,
    chunk_index: usize,
    total_chunks: usize,
    metadata: ChunkMetadata,
};

pub const ChunkMetadata = struct {
    source_url: []const u8,
    source_title: []const u8,
    start_char: usize,
    end_char: usize,
};

/// Text chunker
pub const TextChunker = struct {
    allocator: std.mem.Allocator,
    config: ChunkConfig,

    pub fn init(allocator: std.mem.Allocator, config: ChunkConfig) TextChunker {
        return TextChunker{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Chunk text by words (approximate tokens)
    pub fn chunk(self: *TextChunker, text: []const u8, metadata: ChunkMetadata) ![]Chunk {
        switch (self.config.split_by) {
            .semantic => return self.chunkSemantic(text, metadata),
            .fixed => return self.chunkFixed(text, metadata),
            .sentences => return self.chunkBySentences(text, metadata),
        }
    }

    /// Semantic chunking - split by natural boundaries
    fn chunkSemantic(self: *TextChunker, text: []const u8, metadata: ChunkMetadata) ![]Chunk {
        var chunks = std.ArrayList(Chunk).init(self.allocator);

        // Split by double newlines (paragraphs)
        var paragraphs = std.mem.split(u8, text, "\n\n");
        
        var current_chunk = std.ArrayList(u8).init(self.allocator);
        var current_tokens: usize = 0;
        var chunk_index: usize = 0;
        var start_char: usize = 0;

        while (paragraphs.next()) |para| {
            const para_tokens = estimateTokens(para);

            // If single paragraph exceeds limit, split it
            if (para_tokens > self.config.max_tokens) {
                // Save current chunk
                if (current_chunk.items.len > 0) {
                    try chunks.append(Chunk{
                        .text = try self.allocator.dupe(u8, current_chunk.items),
                        .tokens = current_tokens,
                        .chunk_index = chunk_index,
                        .total_chunks = 0, // Will update later
                        .metadata = .{
                            .source_url = try self.allocator.dupe(u8, metadata.source_url),
                            .source_title = try self.allocator.dupe(u8, metadata.source_title),
                            .start_char = start_char,
                            .end_char = start_char + current_chunk.items.len,
                        },
                    });
                    chunk_index += 1;
                    current_chunk.deinit();
                    current_chunk = std.ArrayList(u8).init(self.allocator);
                    current_tokens = 0;
                }

                // Split long paragraph
                const sub_chunks = try self.splitLongParagraph(para, metadata);
                for (sub_chunks) |sub| {
                    try chunks.append(sub);
                }
                start_char += para.len + 2;
                continue;
            }

            // Check if adding this paragraph exceeds limit
            if (current_tokens + para_tokens > self.config.max_tokens and current_chunk.items.len > 0) {
                // Save current chunk
                try chunks.append(Chunk{
                    .text = try self.allocator.dupe(u8, current_chunk.items),
                    .tokens = current_tokens,
                    .chunk_index = chunk_index,
                    .total_chunks = 0,
                    .metadata = .{
                        .source_url = try self.allocator.dupe(u8, metadata.source_url),
                        .source_title = try self.allocator.dupe(u8, metadata.source_title),
                        .start_char = start_char,
                        .end_char = start_char + current_chunk.items.len,
                    },
                });
                chunk_index += 1;

                // Start new chunk with overlap
                const overlap_text = try self.getOverlapText(current_chunk.items);
                current_chunk.deinit();
                current_chunk = std.ArrayList(u8).init(self.allocator);
                if (overlap_text.len > 0) {
                    try current_chunk.appendSlice(overlap_text);
                    current_tokens = estimateTokens(overlap_text);
                } else {
                    current_tokens = 0;
                }
                start_char = start_char + current_chunk.items.len;
            }

            // Add paragraph
            if (current_chunk.items.len > 0) {
                try current_chunk.appendSlice("\n\n");
                current_tokens += 2; // for the newlines
            }
            try current_chunk.appendSlice(para);
            current_tokens += para_tokens;
        }

        // Don't forget last chunk
        if (current_chunk.items.len > 0) {
            try chunks.append(Chunk{
                .text = try self.allocator.dupe(u8, current_chunk.items),
                .tokens = current_tokens,
                .chunk_index = chunk_index,
                .total_chunks = chunks.len + 1,
                .metadata = .{
                    .source_url = try self.allocator.dupe(u8, metadata.source_url),
                    .source_title = try self.allocator.dupe(u8, metadata.source_title),
                    .start_char = start_char,
                    .end_char = start_char + current_chunk.items.len,
                },
            });
        }

        return chunks.toOwnedSlice();
    }

    /// Fixed-size chunking
    fn chunkFixed(self: *TextChunker, text: []const u8, metadata: ChunkMetadata) ![]Chunk {
        var chunks = std.ArrayList(Chunk).init(self.allocator);
        
        const words = std.mem.split(u8, text, " ");
        var current = std.ArrayList([]const u8).init(self.allocator);
        var current_tokens: usize = 0;
        var chunk_index: usize = 0;
        var char_pos: usize = 0;

        for (words) |word| {
            const word_tokens = estimateTokens(word);

            if (current_tokens + word_tokens > self.config.max_tokens and current.items.len > 0) {
                const chunk_text = try std.mem.join(self.allocator, " ", current.items);
                
                try chunks.append(Chunk{
                    .text = chunk_text,
                    .tokens = current_tokens,
                    .chunk_index = chunk_index,
                    .total_chunks = 0,
                    .metadata = .{
                        .source_url = try self.allocator.dupe(u8, metadata.source_url),
                        .source_title = try self.allocator.dupe(u8, metadata.source_title),
                        .start_char = char_pos,
                        .end_char = char_pos + chunk_text.len,
                    },
                });

                chunk_index += 1;

                // Overlap
                const overlap = try self.getOverlapWords(current.items);
                current.deinit();
                current = std.ArrayList([]const u8).init(self.allocator);
                
                for (overlap) |ow| {
                    try current.append(ow);
                    current_tokens = estimateTokens(try std.mem.join(self.allocator, " ", current.items));
                }
                char_pos += chunk_text.len - (overlap_tokens * 5); // Approximate
            }

            try current.append(word);
            current_tokens += word_tokens;
        }

        // Last chunk
        if (current.items.len > 0) {
            const chunk_text = try std.mem.join(self.allocator, " ", current.items);
            try chunks.append(Chunk{
                .text = chunk_text,
                .tokens = current_tokens,
                .chunk_index = chunk_index,
                .total_chunks = chunks.len + 1,
                .metadata = .{
                    .source_url = try self.allocator.dupe(u8, metadata.source_url),
                    .source_title = try self.allocator.dupe(u8, metadata.source_title),
                    .start_char = char_pos,
                    .end_char = char_pos + chunk_text.len,
                },
            });
        }

        return chunks.toOwnedSlice();
    }

    /// Chunk by sentences
    fn chunkBySentences(self: *TextChunker, text: []const u8, metadata: ChunkMetadata) ![]Chunk {
        var chunks = std.ArrayList(Chunk).init(self.allocator);
        
        // Sentence endings: . ! ? followed by space or end
        var sentences = std.mem.split(u8, text, ". ");
        
        var current = std.ArrayList(u8).init(self.allocator);
        var current_tokens: usize = 0;
        var chunk_index: usize = 0;
        var start_char: usize = 0;

        while (sentences.next()) |sentence| {
            // Add period back
            var full_sentence = try std.fmt.allocPrint(self.allocator, "{s}.", .{sentence});
            defer self.allocator.free(full_sentence);
            
            const sentence_tokens = estimateTokens(full_sentence);

            if (current_tokens + sentence_tokens > self.config.max_tokens and current.items.len > 0) {
                try chunks.append(Chunk{
                    .text = try self.allocator.dupe(u8, current.items),
                    .tokens = current_tokens,
                    .chunk_index = chunk_index,
                    .total_chunks = 0,
                    .metadata = .{
                        .source_url = try self.allocator.dupe(u8, metadata.source_url),
                        .source_title = try self.allocator.dupe(u8, metadata.source_title),
                        .start_char = start_char,
                        .end_char = start_char + current.items.len,
                    },
                });

                chunk_index += 1;
                current.deinit();
                current = std.ArrayList(u8).init(self.allocator);
                current_tokens = 0;
                start_char += current.items.len;
            }

            if (current.items.len > 0) {
                try current.appendSlice(" ");
                current_tokens += 1;
            }
            try current.appendSlice(full_sentence);
            current_tokens += sentence_tokens;
        }

        if (current.items.len > 0) {
            try chunks.append(Chunk{
                .text = try self.allocator.dupe(u8, current.items),
                .tokens = current_tokens,
                .chunk_index = chunk_index,
                .total_chunks = chunks.len + 1,
                .metadata = .{
                    .source_url = try self.allocator.dupe(u8, metadata.source_url),
                    .source_title = try self.allocator.dupe(u8, metadata.source_title),
                    .start_char = start_char,
                    .end_char = start_char + current.items.len,
                },
            });
        }

        return chunks.toOwnedSlice();
    }

    /// Split long paragraph
    fn splitLongParagraph(self: *TextChunker, para: []const u8, metadata: ChunkMetadata) ![]Chunk {
        // Split by sentence for long paragraphs
        return self.chunkBySentences(para, metadata);
    }

    /// Get overlap text from previous chunk (semantic)
    fn getOverlapText(self: *TextChunker, text: []const u8) ![]u8 {
        const lines = std.mem.split(u8, text, "\n");
        var overlap_lines = std.ArrayList([]const u8).init(self.allocator);
        var overlap_tokens: usize = 0;

        while (lines.next()) |line| {
            const line_tokens = estimateTokens(line);
            if (overlap_tokens + line_tokens > self.config.overlap_tokens) break;
            try overlap_lines.append(line);
            overlap_tokens += line_tokens;
        }

        if (overlap_lines.items.len == 0) return &.{};
        return std.mem.join(self.allocator, "\n", overlap_lines.items);
    }

    /// Get overlap words from previous chunk (fixed)
    fn getOverlapWords(self: *TextChunker, words: [][]const u8) ![][]const u8 {
        var overlap_words = std.ArrayList([]const u8).init(self.allocator);
        var overlap_tokens: usize = 0;

        // Take from end of previous
        var i = words.len - 1;
        while (i >= 0) {
            const word_tokens = estimateTokens(words[i]);
            if (overlap_tokens + word_tokens > self.config.overlap_tokens) break;
            try overlap_words.insert(0, words[i]);
            overlap_tokens += word_tokens;
            i -= 1;
        }

        return overlap_words.toOwnedSlice();
    }
};

/// Estimate token count (rough: 1 token ≈ 4 chars)
pub fn estimateTokens(text: []const u8) usize {
    return (text.len + 3) / 4;
}
