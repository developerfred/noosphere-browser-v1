//! Noosphere Browser - Semantic-native browser for agents
//! 
//! For Raspberry Pi and edge devices. Pure Zig, no dependencies.
//! Security: URL validation, rate limiting, access control

const std = @import("std");
const http = @import("http.zig");
const parser = @import("parser.zig");
const store = @import("store.zig");
const ratelimit = @import("ratelimit.zig");
const access = @import("access.zig");

pub fn main() !void {
    std.log.info("🌐 Noosphere Browser v0.1.0", .{});
    std.log.info("Semantic-native browser for agents", .{});
    std.log.info("Target: Raspberry Pi (ARM)", .{});
    
    // Parse command line arguments
    const args = std.process.args();
    
    var mode: []const u8 = "interactive";
    var url: ?[]const u8 = null;
    
    var i: usize = 0;
    while (args.next()) |arg| {
        if (i == 1) {
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                try printHelp();
                return;
            }
            if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
                std.log.info("Noosphere v0.1.0", .{});
                return;
            }
            if (std.mem.eql(u8, arg, "--fetch") or std.mem.eql(u8, arg, "-f")) {
                mode = "fetch";
                continue;
            }
            if (std.mem.eql(u8, arg, "--server") or std.mem.eql(u8, arg, "-s")) {
                mode = "server";
                continue;
            }
            if (std.mem.eql(u8, arg, "--graph") or std.mem.eql(u8, arg, "-g")) {
                mode = "graph";
                continue;
            }
            if (std.mem.eql(u8, arg, "--query") or std.mem.eql(u8, arg, "-q")) {
                mode = "query";
                continue;
            }
            if (std.mem.startsWith(u8, arg, "--")) {
                continue;
            }
            url = arg;
        }
        i += 1;
    }
    
    // Initialize storage
    var db = try store.init("noosphere.db");
    defer db.deinit();
    
    // Execute mode
    if (std.mem.eql(u8, mode, "fetch") and url != null) {
        try fetchAndStore(url.?, &db);
    } else if (std.mem.eql(u8, mode, "server")) {
        try startServer(&db);
    } else if (std.mem.eql(u8, mode, "graph")) {
        try dumpGraph(&db);
    } else if (std.mem.eql(u8, mode, "query")) {
        if (url) |query| {
            try queryGraph(query, &db);
        } else {
            std.log.err("Query string required with --query", .{});
        }
    } else {
        try interactiveMode(&db);
    }
}

fn printHelp() !void {
    try std.io.getStdOut().writeAll(
        \\Noosphere Browser - Semantic-native browser
        \\
        \\Usage:
        \\  noosphere [options] [url]
        \\
        \\Options:
        \\  -f, --fetch <url>   Fetch and store a page
        \\  -s, --server        Start HTTP server
        \\  -g, --graph         Dump knowledge graph
        \\  -q, --query <str>   Query the graph
        \\  -h, --help          Show this help
        \\  -v, --version       Show version
        \\
        \\Examples:
        \\  noosphere --fetch https://example.com
        \\  noosphere --server
        \\  noosphere --query "AI"
        \\
    );
}

fn fetchAndStore(url_str: []const u8, db: *store.Store) !void {
    std.log.info("Fetching: {s}", .{url_str});
    
    const response = try http.fetch(url_str);
    defer response.deinit();
    
    std.log.info("Received {d} bytes", .{response.body.len});
    
    const semantic = try parser.parse(response.body);
    
    std.log.info("Extracted:", .{});
    std.log.info("  Title: {s}", .{semantic.title});
    std.log.info("  Words: {d}", .{semantic.word_count});
    std.log.info("  Entities: {d}", .{semantic.entities.len});
    std.log.info("  Relations: {d}", .{semantic.relations.len});
    
    try db.addPage(url_str, &semantic);
    
    std.log.info("✅ Stored in knowledge graph!", .{});
}

fn startServer(db: *store.Store) !void {
    std.log.info("Starting Noosphere server on :8080", .{});
    std.log.warn("Server not yet implemented - use --fetch instead", .{});
    _ = db;
}

fn dumpGraph(db: *store.Store) !void {
    std.log.info("Knowledge Graph:", .{});
    std.log.info("===============", .{});
    
    const pages = try db.getAllPages();
    defer db.freePages(pages);
    
    if (pages.len == 0) {
        std.log.info("(empty)", .{});
        return;
    }
    
    for (pages) |page| {
        std.log.info("- {s}", .{page.url});
        std.log.info("  Title: {s}", .{page.title});
        std.log.info("  Entities: {d}", .{page.entity_count});
    }
}

fn queryGraph(query: []const u8, db: *store.Store) !void {
    std.log.info("Searching for: {s}", .{query});
    
    const results = try db.search(query);
    defer db.freePages(results);
    
    std.log.info("Found {d} results:", .{results.len});
    for (results) |page| {
        std.log.info("- {s}", .{page.url});
    }
}

fn interactiveMode(db: *store.Store) !void {
    std.log.info("", .{});
    std.log.info("Interactive Mode", .{});
    std.log.info("=================", .{});
    std.log.info("Commands:", .{});
    std.log.info("  fetch <url>  - Fetch and store a page", .{});
    std.log.info("  graph        - Show knowledge graph", .{});
    std.log.info("  query <str>  - Search the graph", .{});
    std.log.info("  help         - Show this help", .{});
    std.log.info("  quit         - Exit", .{});
    std.log.info("", .{});
    
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    
    var buf: [256]u8 = undefined;
    
    while (true) {
        try stdout.writeAll("noosphere> ");
        if (try stdin.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;
            
            if (std.mem.eql(u8, trimmed, "quit") or std.mem.eql(u8, trimmed, "exit") or std.mem.eql(u8, trimmed, "q")) {
                break;
            }
            
            if (std.mem.eql(u8, trimmed, "help")) {
                try printHelp();
                continue;
            }
            
            if (std.mem.eql(u8, trimmed, "graph")) {
                try dumpGraph(db);
                continue;
            }
            
            var it = std.mem.split(u8, trimmed, " ");
            const cmd = it.next() orelse continue;
            
            if (std.mem.eql(u8, cmd, "fetch") or std.mem.eql(u8, cmd, "f")) {
                const url = it.next();
                if (url) |u| {
                    try fetchAndStore(u, db);
                } else {
                    std.log.err("Usage: fetch <url>", .{});
                }
                continue;
            }
            
            if (std.mem.eql(u8, cmd, "query") or std.mem.eql(u8, cmd, "q")) {
                const q = it.rest();
                if (q.len > 0) {
                    try queryGraph(q, db);
                } else {
                    std.log.err("Usage: query <search-term>", .{});
                }
                continue;
            }
            
            std.log.err("Unknown command: {s}", .{cmd});
        }
    }
}
