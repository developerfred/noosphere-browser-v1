//! Noosphere RAG Export
//! 
//! Export extracted content for RAG systems.
//! Supports LangChain, LlamaIndex, and standard formats.

const std = @import("std");
const chunk = @import("chunk.zig");
const embed = @import("embed.zig");

/// Export format
pub const ExportFormat = enum {
    langchain_json,
    llamaindex_json,
    oai_jsonl,
    chunk_json,
    markdown,
    html,
};

/// Export configuration
pub const ExportConfig = struct {
    format: ExportFormat,
    include_embeddings: bool,
    include_metadata: bool,
    include_source: bool,
};

/// Default config
pub fn defaultConfig() ExportConfig {
    return ExportConfig{
        .format = .chunk_json,
        .include_embeddings = false,
        .include_metadata = true,
        .include_source = true,
    };
}

/// RAG Exporter
pub const RAGExporter = struct {
    allocator: std.mem.Allocator,
    config: ExportConfig,

    pub fn init(allocator: std.mem.Allocator, config: ExportConfig) RAGExporter {
        return RAGExporter{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Export chunks to format
    pub fn export(self: *RAGExporter, chunks: []chunk.Chunk, doc_id: []const u8) ![]u8 {
        switch (self.config.format) {
            .langchain_json => return self.exportLangChain(chunks, doc_id),
            .llamaindex_json => return self.exportLlamaIndex(chunks, doc_id),
            .oai_jsonl => return self.exportOAIJsonl(chunks, doc_id),
            .chunk_json => return self.exportChunkJson(chunks, doc_id),
            .markdown => return self.exportMarkdown(chunks, doc_id),
            .html => return self.exportHtml(chunks, doc_id),
        }
    }

    /// Export to LangChain JSON format
    /// LangChain expects: {page_content, metadata}
    fn exportLangChain(self: *RAGExporter, chunks: []chunk.Chunk, doc_id: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);

        try result.appendSlice("[\n");

        for (chunks, 0..) |ch, i| {
            try result.appendSlice("  {\n");
            try result.appendSlice("    \"page_content\": ");
            try writeJSONString(result, ch.text);

            try result.appendSlice(",\n    \"metadata\": {\n");
            try std.fmt.format("      \"source\": \"{s}\",\n", .{ch.metadata.source_url}, result.writer());
            try std.fmt.format("      \"doc_id\": \"{s}\",\n", .{doc_id}, result.writer());
            try std.fmt.format("      \"chunk_id\": {},\n", .{i}, result.writer());
            try std.fmt.format("      \"chunk_index\": {},\n", .{ch.chunk_index}, result.writer());
            try std.fmt.format("      \"total_chunks\": {},\n", .{ch.total_chunks}, result.writer());
            try std.fmt.format("      \"tokens\": {}", .{ch.tokens}, result.writer());
            try result.appendSlice("\n    }\n");
            try result.appendSlice("  }");
            if (i < chunks.len - 1) try result.append(',');
            try result.append('\n');
        }

        try result.appendSlice("]\n");

        return result.toOwnedSlice();
    }

    /// Export to LlamaIndex JSON format
    /// LlamaIndex expects: {id, text, metadata, embedding?}
    fn exportLlamaIndex(self: *RAGExporter, chunks: []chunk.Chunk, doc_id: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);

        try result.appendSlice("[\n");

        for (chunks, 0..) |ch, i| {
            try result.appendSlice("  {\n");
            try std.fmt.format("    \"id\": \"{s}_chunk_{d}\",\n", .{ doc_id, i }, result.writer());
            try result.appendSlice("    \"text\": ");
            try writeJSONString(result, ch.text);

            try result.appendSlice(",\n    \"metadata\": {\n");
            try std.fmt.format("      \"source\": \"{s}\",\n", .{ch.metadata.source_url}, result.writer());
            try std.fmt.format("      \"title\": \"{s}\",\n", .{ch.metadata.source_title}, result.writer());
            try std.fmt.format("      \"start_char\": {},\n", .{ch.metadata.start_char}, result.writer());
            try std.fmt.format("      \"end_char\": {}\n", .{ch.metadata.end_char}, result.writer());
            try result.appendSlice("    }\n");
            try result.appendSlice("  }");
            if (i < chunks.len - 1) try result.append(',');
            try result.append('\n');
        }

        try result.appendSlice("]\n");

        return result.toOwnedSlice();
    }

    /// Export to OpenAI JSONL format
    fn exportOAIJsonl(self: *RAGExporter, chunks: []chunk.Chunk, doc_id: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);

        for (chunks, 0..) |ch, i| {
            try result.appendSlice("{");
            try result.appendSlice("\"text\": ");
            try writeJSONString(result, ch.text);
            try result.appendSlice(",\"source\":\"");
            try result.appendSlice(ch.metadata.source_url);
            try result.appendSlice("\",\"doc_id\":\"");
            try result.appendSlice(doc_id);
            try result.appendSlice("\",\"chunk_id\":");
            try std.fmt.formatInt(i, 10, .lower, .{}, result.writer());
            try result.appendSlice("}\n");
        }

        return result.toOwnedSlice();
    }

    /// Export to simple chunk JSON
    fn exportChunkJson(self: *RAGExporter, chunks: []chunk.Chunk, doc_id: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);

        try result.appendSlice("{\n");
        try std.fmt.format("  \"doc_id\": \"{s}\",\n", .{doc_id}, result.writer());
        try std.fmt.format("  \"chunk_count\": {},\n", .{chunks.len}, result.writer());
        try result.appendSlice("  \"chunks\": [\n");

        for (chunks, 0..) |ch, i| {
            try result.appendSlice("    {\n");
            try std.fmt.format("      \"index\": {},\n", .{i}, result.writer());
            try result.appendSlice("      \"text\": ");
            try writeJSONString(result, ch.text);
            try result.appendSlice(",\n");
            try std.fmt.format("      \"tokens\": {},\n", .{ch.tokens}, result.writer());
            try std.fmt.format("      \"source\": \"{s}\",\n", .{ch.metadata.source_url}, result.writer());
            try std.fmt.format("      \"start_char\": {},\n", .{ch.metadata.start_char}, result.writer());
            try std.fmt.format("      \"end_char\": {}\n", .{ch.metadata.end_char}, result.writer());
            try result.appendSlice("    }");
            if (i < chunks.len - 1) try result.append(',');
            try result.append('\n');
        }

        try result.appendSlice("  ]\n");
        try result.appendSlice("}\n");

        return result.toOwnedSlice();
    }

    /// Export to Markdown (for human readability)
    fn exportMarkdown(self: *RAGExporter, chunks: []chunk.Chunk, doc_id: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);

        try std.fmt.format("# Document: {s}\n\n", .{doc_id}, result.writer());
        try std.fmt.format("**Source:** {s}\n\n", .{chunks[0].metadata.source_url}, result.writer());
        try std.fmt.format("**Total chunks:** {}\n\n", .{chunks.len}, result.writer());

        for (chunks, 0..) |ch, i| {
            try std.fmt.format("## Chunk {d}\n\n", .{i}, result.writer());
            try std.fmt.format("**Tokens:** {} | **Chars:** {}-{}\n\n", .{
                ch.tokens, ch.metadata.start_char, ch.metadata.end_char
            }, result.writer());
            try result.appendSlice(ch.text);
            try result.appendSlice("\n\n---\n\n");
        }

        return result.toOwnedSlice();
    }

    /// Export to HTML
    fn exportHtml(self: *RAGExporter, chunks: []chunk.Chunk, doc_id: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);

        try result.appendSlice("<!DOCTYPE html>\n<html>\n<head>\n");
        try std.fmt.format("<title>Document: {s}</title>\n", .{doc_id}, result.writer());
        try result.appendSlice("<style>\n");
        try result.appendSlice("body { font-family: system-ui; max-width: 800px; margin: 0 auto; padding: 2rem; }\n");
        try result.appendSlice(".chunk { border: 1px solid #ddd; padding: 1rem; margin: 1rem 0; border-radius: 8px; }\n");
        try result.appendSlice(".meta { color: #666; font-size: 0.9rem; }\n");
        try result.appendSlice("</style>\n</head>\n<body>\n");

        try std.fmt.format("<h1>Document: {s}</h1>\n", .{doc_id}, result.writer());
        try std.fmt.format("<p class=\"meta\">Source: <a href=\"{s}\">{s}</a></p>\n", .{
            chunks[0].metadata.source_url, chunks[0].metadata.source_url
        }, result.writer());

        for (chunks, 0..) |ch, i| {
            try result.appendSlice("<div class=\"chunk\">\n");
            try std.fmt.format("<h2>Chunk {d}</h2>\n", .{i}, result.writer());
            try std.fmt.format("<p class=\"meta\">Tokens: {} | Chars: {}-{}</p>\n", .{
                ch.tokens, ch.metadata.start_char, ch.metadata.end_char
            }, result.writer());
            try result.appendSlice("<pre>");
            try writeHTMLString(result, ch.text);
            try result.appendSlice("</pre>\n");
            try result.appendSlice("</div>\n");
        }

        try result.appendSlice("</body>\n</html>\n");

        return result.toOwnedSlice();
    }
});

/// Write string with JSON escaping
fn writeJSONString(writer: anytype, str: []const u8) !void {
    try writer.writeAll("\"");

    for (str) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }

    try writer.writeAll("\"");
}

/// Write string with HTML escaping
fn writeHTMLString(writer: anytype, str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '&' => try writer.writeAll("&amp;"),
            '"' => try writer.writeAll("&quot;"),
            else => try writer.writeByte(c),
        }
    }
}
