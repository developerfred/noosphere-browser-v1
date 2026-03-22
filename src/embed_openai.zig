//! Noosphere Embeddings - OpenAI and Local Models
//! 
//! Generate vector embeddings using OpenAI API or local models.
//! Support for sentence-transformers and ONNX runtime.

const std = @import("std");
const http = @import("http.zig");

/// Embedding model configuration
pub const EmbeddingModel = enum {
    openai_ada002,
    openai_text_embedding_3_small,
    openai_text_embedding_3_large,
    local_mini_lm,     // 6-layer MiniLM
    local_all_mini_lm, // 12-layer MiniLM
};

/// Embedding result
pub const EmbeddingResult = struct {
    embedding: []f32,
    model: []const u8,
    tokens_used: u32,
    provider: []const u8,
};

/// Local embedding model
pub const LocalEmbedder = struct {
    allocator: std.mem.Allocator,
    model_path: []const u8,
    dimensions: u32,
    model_type: []const u8,

    pub fn init(allocator: std.mem.Allocator) LocalEmbedder {
        return LocalEmbedder{
            .allocator = allocator,
            .model_path = "",
            .dimensions = 384,
            .model_type = "MiniLM-L6",
        };
    }

    /// Check if sentence-transformers is available
    pub fn hasSentenceTransformers(self: *LocalEmbedder) bool {
        const result = std.ChildProcess.exec(.{
            .argv = &.{ "python3", "-c", "from sentence_transformers import SentenceTransformer; print('ok')" },
        }) catch return false;

        return std.mem.containsAtLeast(u8, result.stdout, 2);
    }

    /// Check if ONNX runtime is available
    pub fn hasONNXRuntime(self: *LocalEmbedder) bool {
        const result = std.ChildProcess.exec(.{
            .argv = &.{ "python3", "-c", "import onnxruntime; print('ok')" },
        }) catch return false;

        return std.mem.containsAtLeast(u8, result.stdout, 2);
    }

    /// Generate embedding using Python sentence-transformers
    pub fn embedPython(self: *LocalEmbedder, text: []const u8) !EmbeddingResult {
        // Python script for embeddings
        const python_script = try std.fmt.allocPrint(
            self.allocator,
            \\from sentence_transformers import SentenceTransformer
            \\import sys, json
            \\
            \\model = SentenceTransformer('all-MiniLM-L6-v2')
            \\text = sys.argv[1]
            \\embedding = model.encode(text).tolist()
            \\result = {{"embedding": embedding, "dimensions": len(embedding)}}
            \\print(json.dumps(result))
        , .{});
        defer self.allocator.free(python_script);

        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &.{ "python3", "-c", python_script, text },
        });

        if (result.term.Exited != 0) {
            return error.EmbeddingFailed;
        }

        // Parse JSON result
        const parsed = std.json.parseFromSlice(
            struct { embedding: []f32, dimensions: u32 },
            self.allocator,
            result.stdout,
        ) catch return error.ParseFailed;

        return EmbeddingResult{
            .embedding = parsed.value.embedding,
            .model = "all-MiniLM-L6-v2",
            .tokens_used = 0,
            .provider = "local",
        };
    }

    /// Batch embed multiple texts
    pub fn embedBatchPython(self: *LocalEmbedder, texts: [][]const u8) ![]EmbeddingResult {
        var results = std.ArrayList(EmbeddingResult).init(self.allocator);

        // Python script for batch
        const python_script = try std.fmt.allocPrint(
            self.allocator,
            \\from sentence_transformers import SentenceTransformer
            \\import sys, json
            \\import ast
            \\
            \\model = SentenceTransformer('all-MiniLM-L6-v2')
            \\texts = ast.literal_eval(sys.argv[1])
            \\embeddings = model.encode(texts).tolist()
            \\result = {{"embeddings": embeddings, "count": len(embeddings), "dimensions": len(embeddings[0])}}
            \\print(json.dumps(result))
        , .{});
        defer self.allocator.free(python_script);

        const texts_json = try std.json.stringifyAlloc(self.allocator, texts);
        defer self.allocator.free(texts_json);

        const result = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &.{ "python3", "-c", python_script, texts_json },
        });

        if (result.term.Exited != 0) {
            return error.BatchEmbeddingFailed;
        }

        // Parse results
        const parsed = try std.json.parseFromSlice(
            struct { embeddings: [][]f32, count: u32, dimensions: u32 },
            self.allocator,
            result.stdout,
        );

        for (parsed.value.embeddings) |emb| {
            try results.append(EmbeddingResult{
                .embedding = emb,
                .model = "all-MiniLM-L6-v2",
                .tokens_used = 0,
                .provider = "local",
            });
        }

        return results.toOwnedSlice();
    }
});

/// OpenAI embedding client
pub const OpenAIEmbedder = struct {
    allocator: std.mem.Allocator,
    api_key: []const u8,
    api_base: []const u8,
    model: EmbeddingModel,

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8) OpenAIEmbedder {
        return OpenAIEmbedder{
            .allocator = allocator,
            .api_key = api_key,
            .api_base = "https://api.openai.com/v1",
            .model = .openai_text_embedding_3_small,
        };
    }

    /// Get model name for API
    fn modelName(self: *const OpenAIEmbedder) []const u8 {
        return switch (self.model) {
            .openai_ada002 => "text-embedding-ada-002",
            .openai_text_embedding_3_small => "text-embedding-3-small",
            .openai_text_embedding_3_large => "text-embedding-3-large",
            else => "text-embedding-3-small",
        };
    }

    /// Generate embedding using OpenAI API
    pub fn embed(self: *OpenAIEmbedder, text: []const u8) !EmbeddingResult {
        const request_body = try std.fmt.allocPrint(
            self.allocator,
            \\{{"input": "{s}","model":"{s}"}}
        , .{ text, self.modelName() });
        defer self.allocator.free(request_body);

        // Make HTTP request
        const response = try http.postJSON(
            self.allocator,
            self.api_base ++ "/embeddings",
            request_body,
            &.{
                .{ .name = "Authorization", .value = "Bearer " ++ self.api_key },
                .{ .name = "Content-Type", .value = "application/json" },
            },
        );
        defer response.deinit();

        if (response.status_code != 200) {
            return error.APIError;
        }

        // Parse response
        const parsed = try std.json.parseFromSlice(
            struct {
                data: []struct { embedding: []f32 },
                usage: struct { prompt_tokens: u32 },
            },
            self.allocator,
            response.body,
        );

        const embedding = try self.allocator.dupe(f32, parsed.value.data[0].embedding);

        return EmbeddingResult{
            .embedding = embedding,
            .model = self.modelName(),
            .tokens_used = parsed.value.usage.prompt_tokens,
            .provider = "openai",
        };
    }

    /// Batch embed (OpenAI supports up to 2048 inputs)
    pub fn embedBatch(self: *OpenAIEmbedder, texts: [][]const u8) ![]EmbeddingResult {
        // Build request
        var input_json = std.ArrayList(u8).init(self.allocator);
        try input_json.append('[');
        for (texts, 0..) |text, i| {
            try input_json.append('"');
            // Escape quotes
            for (text) |c| {
                if (c == '"') try input_json.append('\\');
                try input_json.append(c);
            }
            try input_json.append('"');
            if (i < texts.len - 1) try input_json.append(',');
        }
        try input_json.append(']');

        const request_body = try std.fmt.allocPrint(
            self.allocator,
            \\{{"input": {s},"model":"{s}"}}
        , .{ input_json.items, self.modelName() });
        defer self.allocator.free(request_body);

        // Make request
        const response = try http.postJSON(
            self.allocator,
            self.api_base ++ "/embeddings",
            request_body,
            &.{
                .{ .name = "Authorization", .value = "Bearer " ++ self.api_key },
                .{ .name = "Content-Type", .value = "application/json" },
            },
        );
        defer response.deinit();

        if (response.status_code != 200) {
            return error.APIError;
        }

        // Parse response
        const parsed = try std.json.parseFromSlice(
            struct {
                data: []struct { embedding: []f32 },
                usage: struct { prompt_tokens: u32 },
            },
            self.allocator,
            response.body,
        );

        var results = std.ArrayList(EmbeddingResult).init(self.allocator);
        for (parsed.value.data) |item| {
            const emb = try self.allocator.dupe(f32, item.embedding);
            try results.append(EmbeddingResult{
                .embedding = emb,
                .model = self.modelName(),
                .tokens_used = parsed.value.usage.prompt_tokens,
                .provider = "openai",
            });
        }

        return results.toOwnedSlice();
    }
});

/// Unified embedding interface
pub const EmbeddingService = struct {
    allocator: std.mem.Allocator,
    openai: ?OpenAIEmbedder,
    local: LocalEmbedder,
    use_local: bool,

    pub fn init(allocator: std.mem.Allocator, openai_key: ?[]const u8) EmbeddingService {
        var service = EmbeddingService{
            .allocator = allocator,
            .openai = null,
            .local = LocalEmbedder.init(allocator),
            .use_local = false,
        };

        if (openai_key) |key| {
            service.openai = OpenAIEmbedder.init(allocator, key);
        } else {
            service.use_local = true;
        }

        return service;
    }

    pub fn deinit(self: *EmbeddingService) void {
        if (self.openai) |_| {
            // OpenAI has no cleanup
        }
    }

    /// Generate embedding
    pub fn embed(self: *EmbeddingService, text: []const u8) !EmbeddingResult {
        if (self.use_local) {
            return self.local.embedPython(text);
        } else if (self.openai) |openai| {
            return openai.embed(text);
        }
        return error.NoEmbedderAvailable;
    }

    /// Batch embed
    pub fn embedBatch(self: *EmbeddingService, texts: [][]const u8) ![]EmbeddingResult {
        if (self.use_local) {
            return self.local.embedBatchPython(texts);
        } else if (self.openai) |openai| {
            return openai.embedBatch(texts);
        }
        return error.NoEmbedderAvailable;
    }

    /// Check available embedders
    pub fn checkAvailability(self: *EmbeddingService) EmbedderAvailability {
        return EmbedderAvailability{
            .openai = self.openai != null,
            .local_python = self.local.hasSentenceTransformers(),
            .local_onnx = self.local.hasONNXRuntime(),
        };
    }
};

pub const EmbedderAvailability = struct {
    openai: bool,
    local_python: bool,
    local_onnx: bool,
};

/// HTTP POST helper for JSON
fn postJSON(allocator: std.mem.Allocator, url: []const u8, body: []const u8, headers: []struct { name: []const u8, value: []const u8 }) !HTTPResponse {
    // Simplified - would use actual HTTP client
    _ = .{ allocator = allocator, url = url, body = body, headers = headers };
    return HTTPResponse{ .status_code = 200, .body = "" };
}

const HTTPResponse = struct {
    status_code: u16,
    body: []const u8,
};
