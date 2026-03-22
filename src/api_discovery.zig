//! Noosphere API Discovery
//! 
//! Detect and extract from hidden APIs.
//! Many modern sites use APIs instead of HTML.

const std = @import("std");
const http = @import("http.zig");

/// Discovered API endpoint
pub const ApiEndpoint = struct {
    url: []const u8,
    method: []const u8,
    content_type: []const u8,
    description: ?[]const u8,
};

/// API discovery result
pub const ApiDiscovery = struct {
    base_url: []const u8,
    endpoints: []ApiEndpoint,
    uses_graphql: bool,
    uses_rest: bool,
};

/// API discovery
pub const ApiDiscoverer = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ApiDiscoverer {
        return ApiDiscoverer{ .allocator = allocator };
    }

    /// Discover APIs on a website
    pub fn discover(self: *ApiDiscoverer, domain: []const u8) !ApiDiscovery {
        var endpoints = std.ArrayList(ApiEndpoint).init(self.allocator);

        // Common API paths
        const api_paths = [_][]const u8{
            "/api",
            "/api/v1",
            "/api/v2",
            "/api/v3",
            "/graphql",
            "/api/graphql",
            "/rest",
            "/api/rest",
            "/json",
            "/api/json",
        };

        for (api_paths) |api_path| {
            const url = try std.fmt.allocPrint(self.allocator, "https://{s}{s}", .{ domain, api_path });
            defer self.allocator.free(url);

            // Try to fetch
            const response = http.fetch(url) catch continue;

            if (response.status == 200) {
                const ct = response.headers.get("content-type") orelse "";
                
                // Check if it's an API response
                if (self.looksLikeApi(response.body, ct)) {
                    try endpoints.append(ApiEndpoint{
                        .url = try self.allocator.dupe(u8, url),
                        .method = "GET",
                        .content_type = try self.allocator.dupe(u8, ct),
                        .description = null,
                    });
                }
            }
        }

        return ApiDiscovery{
            .base_url = try self.allocator.dupe(u8, domain),
            .endpoints = try endpoints.toOwnedSlice(),
            .uses_graphql = false, // TODO: detect
            .uses_rest = endpoints.items.len > 0,
        };
    }

    /// Check if response looks like API
    fn looksLikeApi(self: *ApiDiscoverer, body: []const u8, content_type: []const u8) bool {
        _ = self;

        // JSON content type
        if (std.mem.indexOf(u8, content_type, "json")) |_| {
            return true;
        }

        // Try to parse as JSON
        if (body.len > 0 and body[0] == '{') {
            // Starts with {, likely JSON
            if (std.mem.indexOf(u8, body, "\"data\"") != null or
                std.mem.indexOf(u8, body, "\"results\"") != null or
                std.mem.indexOf(u8, body, "\"items\"") != null or
                std.mem.indexOf(u8, body, "\"id\"") != null) {
                return true;
            }
        }

        // Array response
        if (body.len > 0 and body[0] == '[') {
            return true;
        }

        return false;
    }

    /// Parse GraphQL schema from introspection
    pub fn parseGraphQLSchema(self: *ApiDiscoverer, schema_url: []const u8) !void {
        // GraphQL introspection query
        const introspection_query = 
            \\{"query":"{ __schema { types { name fields { name type { name kind } } } } }"}
        ;

        // TODO: POST to schema_url with introspection query
        _ = introspection_query;
        _ = schema_url;
    }

    /// Extract REST endpoints from OpenAPI spec
    pub fn parseOpenApiSpec(self: *ApiDiscoverer, spec_url: []const u8) ![]ApiEndpoint {
        var endpoints = std.ArrayList(ApiEndpoint).init(self.allocator);

        const response = http.fetch(spec_url) catch return endpoints.toOwnedSlice();
        
        // Try to parse as JSON
        if (std.mem.startsWith(u8, response.body, "{")) {
            // Simple OpenAPI detection - look for paths
            var i: usize = 0;
            while (i < response.body.len - 10) {
                if (std.mem.startsWith(u8, response.body[i..], "\"paths\":")) {
                    // Found paths object
                    // TODO: Parse properly
                    _ = i;
                }
                i += 1;
            }
        }

        return endpoints.toOwnedSlice();
    }
};
