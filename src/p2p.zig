//! Noosphere P2P Module
//! 
//! Gossip protocol for Pi-to-Pi communication.
//! Uses TCP with a simple JSON-based message protocol.

const std = @import("std");
const net = std.net;
const posix = std.posix;

/// P2P Message types
pub const MessageType = enum {
    ping,
    pong,
    announce,
    query,
    response,
    sync_request,
    sync_response,
};

/// P2P Message structure
pub const Message = struct {
    msg_type: MessageType,
    node_id: []const u8,
    payload: ?[]const u8,
    timestamp: i64,
};

/// Peer info
pub const Peer = struct {
    address: net.Address,
    node_id: []const u8,
    last_seen: i64,
    connected: bool,
};

/// P2P Node
pub const Node = struct {
    allocator: std.mem.Allocator,
    node_id: [16]u8,
    address: net.Address,
    peers: std.ArrayList(Peer),
    running: bool,
    socket: ?posix.socket_t,

    pub fn init(allocator: std.mem.Allocator, port: u16) !Node {
        // Generate random node ID
        var node_id: [16]u8 = undefined;
        std.crypto.random.bytes(&node_id);

        // Create TCP socket
        const socket = try posix.socket(.ip, .tcp, .auto);
        
        // Bind to port
        const address = net.Address.initIp4([127, 0, 0, 1], port);
        try posix.bind(socket, &address.any);
        try posix.listen(socket, 10);

        return Node{
            .allocator = allocator,
            .node_id = node_id,
            .address = address,
            .peers = std.ArrayList(Peer).init(allocator),
            .running = true,
            .socket = socket,
        };
    }

    pub fn deinit(self: *Node) void {
        self.running = false;
        if (self.socket) |sock| {
            posix.close(sock);
        }
        self.peers.deinit();
    }

    /// Connect to a peer
    pub fn connect(self: *Node, peer_address: net.Address) !void {
        const socket = try posix.socket(.ip, .tcp, .auto);
        try posix.connect(socket, &peer_address);
        
        try self.peers.append(Peer{
            .address = peer_address,
            .node_id = "",
            .last_seen = std.time.timestamp(),
            .connected = true,
        });
    }

    /// Broadcast a message to all peers
    pub fn broadcast(self: *Node, msg: Message) !void {
        const json = try msgToJson(self.allocator, msg);
        defer self.allocator.free(json);

        for (self.peers.items) |peer| {
            if (peer.connected) {
                // TODO: Send to peer
                _ = json;
            }
        }
    }

    /// Announce this node to the network
    pub fn announce(self: *Node) !void {
        const msg = Message{
            .msg_type = .announce,
            .node_id = try std.fmt.allocPrint(self.allocator, "{s}", .{std.fmt.fmtSliceHexLower(&self.node_id)}),
            .payload = null,
            .timestamp = std.time.timestamp(),
        };
        defer self.allocator.free(msg.node_id);

        try self.broadcast(msg);
    }
};

/// Encode message to JSON
fn msgToJson(allocator: std.mem.Allocator, msg: Message) ![]u8 {
    const node_id = try allocator.dupe(u8, msg.node_id);
    defer allocator.free(node_id);

    return try std.fmt.allocPrint(allocator,
        \\{{"type":"{s}","node_id":"{s}","payload":{s},"timestamp":{}}}
    , .{
        @tagName(msg.msg_type),
        node_id,
        if (msg.payload) |p| try std.fmt.allocPrint(allocator, "\"{s}\"", .{p}) else "null",
        msg.timestamp,
    });
}

/// Decode message from JSON
pub fn jsonToMsg(allocator: std.mem.Allocator, json: []const u8) !Message {
    // Simple JSON parsing without external dependencies
    // In production, use std.json
    
    const type_start = std.mem.indexOf(u8, json, "\"type\":\"") orelse return error.InvalidJson;
    const type_begin = type_start + 8;
    const type_end = std.mem.indexOf(u8, json[type_begin..], "\"") orelse return error.InvalidJson;
    const type_str = json[type_begin..type_begin + type_end];
    
    const msg_type = std.meta.stringToEnum(MessageType, type_str) orelse .ping;

    return Message{
        .msg_type = msg_type,
        .node_id = "unknown",
        .payload = null,
        .timestamp = 0,
    };
}
