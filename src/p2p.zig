//! Noosphere P2P Network
//! 
//! Distributed knowledge sharing between Noosphere nodes.
//! Uses TCP with a simple gossip protocol.

const std = @import("std");
const net = std.net;
const posix = std.posix;

/// Message types for P2P protocol
pub const MessageType = enum(u8) {
    ping = 1,
    pong = 2,
    announce = 3,
    query = 4,
    response = 5,
    sync_request = 6,
    sync_response = 7,
    share_entity = 8,
    share_page = 9,
};

/// P2P Message
pub const Message = struct {
    msg_type: MessageType,
    node_id: [16]u8,
    payload: []const u8,
    timestamp: i64,
};

/// Peer in the network
pub const Peer = struct {
    address: net.Address,
    node_id: [16]u8,
    last_seen: i64,
    latency_ms: u32,
    connected: bool,
};

/// P2P Node
pub const P2PNode = struct {
    allocator: std.mem.Allocator,
    node_id: [16]u8,
    address: net.Address,
    peers: std.ArrayList(Peer),
    running: bool,
    socket: ?posix.socket_t,
    port: u16,

    pub fn init(allocator: std.mem.Allocator, port: u16) !P2PNode {
        // Generate random node ID
        var node_id: [16]u8 = undefined;
        try std.crypto.random.bytes(&node_id);

        // Create TCP socket
        const sock = try posix.socket(.ip, .tcp, .auto);
        try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEADDR, 1);

        // Bind to port
        const addr = net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
        try posix.bind(sock, &addr);
        try posix.listen(sock, 10);

        return P2PNode{
            .allocator = allocator,
            .node_id = node_id,
            .address = addr,
            .peers = std.ArrayList(Peer).init(allocator),
            .running = true,
            .socket = sock,
            .port = port,
        };
    }

    pub fn deinit(self: *P2PNode) void {
        self.running = false;
        if (self.socket) |sock| {
            posix.close(sock);
        }
        for (self.peers.items) |peer| {
            // Close peer connections
            _ = peer;
        }
        self.peers.deinit();
    }

    /// Connect to a peer
    pub fn connect(self: *P2PNode, peer_address: net.Address) !void {
        const sock = try posix.socket(.ip, .tcp, .auto);
        
        posix.connect(sock, &peer_address) catch {
            posix.close(sock);
            return error.ConnectionFailed;
        };

        var peer = Peer{
            .address = peer_address,
            .node_id = .{0} ** 16,
            .last_seen = std.time.timestamp(),
            .latency_ms = 0,
            .connected = true,
        };

        // Send ping to get peer info
        const ping_msg = try self.createMessage(.ping, "ping");
        defer self.allocator.free(ping_msg);

        // TODO: Send and receive

        try self.peers.append(peer);
    }

    /// Broadcast message to all connected peers
    pub fn broadcast(self: *P2PNode, msg: Message) !void {
        const data = try encodeMessage(self.allocator, msg);
        defer self.allocator.free(data);

        for (self.peers.items) |*peer| {
            if (peer.*.connected) {
                // TODO: Send to peer
                _ = data;
            }
        }
    }

    /// Share an entity with the network
    pub fn shareEntity(self: *P2PNode, entity_type: []const u8, entity_text: []const u8, source_url: []const u8) !void {
        const payload = try std.fmt.allocPrint(
            self.allocator,
            "\\"{s}\",\\"{s}\\",\\"{s}\\"",
            .{ entity_type, entity_text, source_url }
        );
        defer self.allocator.free(payload);

        const msg = Message{
            .msg_type = .share_entity,
            .node_id = self.node_id,
            .payload = payload,
            .timestamp = std.time.timestamp(),
        };

        try self.broadcast(msg);
    }

    /// Share a page with the network
    pub fn sharePage(self: *P2PNode, url: []const u8, title: []const u8) !void {
        const payload = try std.fmt.allocPrint(
            self.allocator,
            "\\"{s}\\",\\"{s}\\"",
            .{ url, title }
        );
        defer self.allocator.free(payload);

        const msg = Message{
            .msg_type = .share_page,
            .node_id = self.node_id,
            .payload = payload,
            .timestamp = std.time.timestamp(),
        };

        try self.broadcast(msg);
    }

    /// Query the network for an entity
    pub fn queryEntity(self: *P2PNode, query: []const u8) !void {
        const msg = Message{
            .msg_type = .query,
            .node_id = self.node_id,
            .payload = query,
            .timestamp = std.time.timestamp(),
        };

        try self.broadcast(msg);
    }

    /// Accept incoming connections
    pub fn accept(self: *P2PNode) !void {
        if (self.socket == null) return;

        const client_sock = try posix.accept(self.socket.?, null, null);
        
        // TODO: Handle client in separate thread or async
        _ = client_sock;
    }

    /// Create a message
    fn createMessage(self: *P2PNode, msg_type: MessageType, payload: []const u8) ![]u8 {
        return try encodeMessage(self.allocator, Message{
            .msg_type = msg_type,
            .node_id = self.node_id,
            .payload = payload,
            .timestamp = std.time.timestamp(),
        });
    }

    /// Get peer count
    pub fn peerCount(self: *P2PNode) usize {
        return self.peers.items.len;
    }

    /// Get peer list
    pub fn getPeers(self: *P2PNode) []Peer {
        return self.peers.items;
    }
};

/// Encode message to bytes
pub fn encodeMessage(allocator: std.mem.Allocator, msg: Message) ![]u8 {
    var data = std.ArrayList(u8).init(allocator);

    // Message type (1 byte)
    try data.append(@intFromEnum(msg.msg_type));

    // Node ID (16 bytes)
    for (msg.node_id) |b| {
        try data.append(b);
    }

    // Timestamp (8 bytes, big endian)
    const ts = @as(u64, @intCast(msg.timestamp));
    try data.append(@as(u8, @truncate(ts >> 56)));
    try data.append(@as(u8, @truncate(ts >> 48)));
    try data.append(@as(u8, @truncate(ts >> 40)));
    try data.append(@as(u8, @truncate(ts >> 32)));
    try data.append(@as(u8, @truncate(ts >> 24)));
    try data.append(@as(u8, @truncate(ts >> 16)));
    try data.append(@as(u8, @truncate(ts >> 8)));
    try data.append(@as(u8, @truncate(ts)));

    // Payload length (4 bytes) + payload
    const payload_len = @as(u32, @intCast(msg.payload.len));
    try data.append(@as(u8, @truncate(payload_len >> 24)));
    try data.append(@as(u8, @truncate(payload_len >> 16)));
    try data.append(@as(u8, @truncate(payload_len >> 8)));
    try data.append(@as(u8, @truncate(payload_len)));
    
    for (msg.payload) |b| {
        try data.append(b);
    }

    return data.toOwnedSlice();
}

/// Decode message from bytes
pub fn decodeMessage(allocator: std.mem.Allocator, data: []const u8) !Message {
    if (data.len < 30) return error.InvalidMessage;

    var offset: usize = 0;

    // Message type
    const msg_type_byte = data[offset];
    offset += 1;
    const msg_type = std.meta.intToEnum(MessageType, msg_type_byte) catch return error.InvalidMessage;

    // Node ID
    var node_id: [16]u8 = undefined;
    std.mem.copy(u8, &node_id, data[offset..offset + 16]);
    offset += 16;

    // Timestamp
    const ts = (@as(i64, @as(u64, data[offset])) << 56 |
              (@as(i64, @as(u64, data[offset + 1])) << 48 |
              (@as(i64, @as(u64, data[offset + 2])) << 40 |
              (@as(i64, @as(u64, data[offset + 3])) << 32 |
              (@as(i64, @as(u64, data[offset + 4])) << 24 |
              (@as(i64, @as(u64, data[offset + 5])) << 16 |
              (@as(i64, @as(u64, data[offset + 6])) << 8 |
              (@as(i64, @as(u64, data[offset + 7])));
    offset += 8;

    // Payload length
    const payload_len = (@as(u32, data[offset]) << 24) |
                       (@as(u32, data[offset + 1]) << 16) |
                       (@as(u32, data[offset + 2]) << 8) |
                       (@as(u32, data[offset + 3]));
    offset += 4;

    // Payload
    if (data.len < offset + payload_len) return error.InvalidMessage;
    const payload = try allocator.dupe(u8, data[offset..offset + payload_len]);

    return Message{
        .msg_type = msg_type,
        .node_id = node_id,
        .payload = payload,
        .timestamp = ts,
    };
}
