//! HTTP Client for Noosphere
//! 
//! Minimal HTTP/1.1 client written in pure Zig.
//! Designed to work on Raspberry Pi with minimal dependencies.

const std = @import("std");

/// HTTP Response structure
pub const Response = struct {
    status: u16,
    headers: std.StringArrayHashMap([]const u8),
    body: []u8,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }
};

/// Security: blocked schemes
const BLOCKED_SCHEMES = &.{ "javascript", "data", "file", "ftp" };

/// Fetch a URL and return the response
pub fn fetch(url_str: []const u8) !Response {
    const allocator = std.heap.page_allocator;
    
    // SECURITY: Validate URL scheme
    for (BLOCKED_SCHEMES) |blocked| {
        if (std.mem.startsWith(u8, url_str, blocked ++ ":")) {
            return error.BlockedScheme;
        }
    }
    
    // Parse URL
    const parsed = try parseUrl(url_str);
    defer {
        allocator.free(parsed.host);
        if (parsed.path.len > 0) allocator.free(parsed.path);
    }
    
    // SECURITY: Warn on HTTP for non-localhost
    const is_localhost = std.mem.startsWith(u8, parsed.host, "localhost") or
        std.mem.startsWith(u8, parsed.host, "127.") or
        std.mem.startsWith(u8, parsed.host, "192.168.") or
        std.mem.startsWith(u8, parsed.host, "10.") or
        std.mem.startsWith(u8, parsed.host, "172.16.") or
        std.mem.startsWith(u8, parsed.host, "0.");
    
    if (!is_localhost and std.mem.eql(u8, parsed.scheme, "http")) {
        std.log.warn("Insecure HTTP connection to {s} - consider using HTTPS", .{parsed.host});
    }
    
    // SECURITY: Limit host length
    if (parsed.host.len > 253) {
        return error.InvalidHost;
    }
    
    // SECURITY: Limit path length
    if (parsed.path.len > 2048) {
        return error.InvalidPath;
    }
    
    // Connect to server
    const address = try resolveHost(parsed.host, parsed.port);
    
    var stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();
    
    // Send HTTP request
    const request = try std.fmt.allocPrint(allocator,
        "GET {s} HTTP/1.1\r\n" ++
        "Host: {s}\r\n" ++
        "User-Agent: Noosphere/0.1\r\n" ++
        "Accept: text/html,application/xhtml+xml,*/*\r\n" ++
        "Connection: close\r\n" ++
        "\r\n",
        .{ parsed.path, parsed.host }
    );
    defer allocator.free(request);
    
    try stream.writeAll(request);
    
    // Read response
    var response_data = std.ArrayList(u8).init(allocator);
    defer response_data.deinit();
    
    {
        var buf: [4096]u8 = undefined;
        while (true {
            const n = try stream.read(&buf);
            if (n == 0) break;
            try response_data.appendSlice(buf[0..n]);
        }
    }
    
    // Parse HTTP response
    return try parseHttpResponse(allocator, response_data.items);
}

const ParsedUrl = struct {
    scheme: []const u8,
    host: []const u8,
    port: u16,
    path: []const u8,
};

fn parseUrl(url_str: []const u8) !ParsedUrl {
    const allocator = std.heap.page_allocator;
    
    // Simple URL parser (no dependencies)
    var url = url_str;
    
    // Parse scheme
    var scheme: []const u8 = "https";
    if (std.mem.startsWith(u8, url, "http://")) {
        scheme = "http";
        url = url[7..];
    } else if (std.mem.startsWith(u8, url, "https://")) {
        url = url[8..];
    }
    
    // Parse host and path
    var host: []const u8 = url;
    var path: []const u8 = "/";
    
    if (std.mem.indexOfScalar(u8, url, '/')) |idx| {
        host = try allocator.dupe(u8, url[0..idx]);
        path = try allocator.dupe(u8, url[idx..]);
    } else {
        host = try allocator.dupe(u8, url);
    }
    
    // Parse port
    var port: u16 = 80;
    if (std.mem.indexOfScalar(u8, host, ':')) |idx| {
        const port_str = host[idx + 1..];
        port = try std.fmt.parseInt(u16, port_str, 10);
        host = try allocator.dupe(u8, host[0..idx]);
    } else if (std.mem.eql(u8, scheme, "https")) {
        port = 443;
    }
    
    return ParsedUrl{
        .scheme = scheme,
        .host = host,
        .port = port,
        .path = path,
    };
}

fn resolveHost(host: []const u8, port: u16) !std.net.Address {
    const allocator = std.heap.page_allocator;
    
    // Simple hosts file lookup first
    const addrs = try std.net.getAddressFromHostPort(.{ .host = host, .port = port }, .{});
    
    return addrs[0];
}

fn parseHttpResponse(allocator: std.mem.Allocator, data: []u8) !Response {
    // Find headers end (\r\n\r\n)
    const header_end = std.mem.indexOf(u8, data, "\r\n\r\n");
    if (header_end == null) {
        return error.InvalidResponse;
    }
    
    // Parse status line
    const header_str = data[0..header_end.?];
    var header_lines = std.mem.split(u8, header_str, "\r\n");
    
    const status_line = header_lines.next() orelse return error.InvalidResponse;
    
    // Parse HTTP/1.1 status
    var status: u16 = 200;
    if (std.mem.startsWith(u8, status_line, "HTTP/1.1 ")) {
        const status_str = status_line[9..];
        status = try std.fmt.parseInt(u16, status_str[0..3], 10);
    } else if (std.mem.startsWith(u8, status_line, "HTTP/1.0 ")) {
        const status_str = status_line[9..];
        status = try std.fmt.parseInt(u16, status_str[0..3], 10);
    }
    
    // Parse headers
    var headers = std.StringArrayHashMap([]const u8).init(allocator);
    errdefer headers.deinit();
    
    while (header_lines.next()) |line| {
        if (line.len == 0) break;
        if (std.mem.indexOfScalar(u8, line, ':')) |idx| {
            const key = try allocator.dupe(u8, std.mem.trim(u8, line[0..idx], " "));
            const value = try allocator.dupe(u8, std.mem.trim(u8, line[idx + 1..], " "));
            try headers.put(key, value);
        }
    }
    
    // Get body
    const body_start = header_end.? + 4;
    const body = try allocator.dupe(u8, data[body_start..]);
    
    return Response{
        .status = status,
        .headers = headers,
        .body = body,
        .allocator = allocator,
    };
}
