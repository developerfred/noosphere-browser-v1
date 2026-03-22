//! Noosphere Access Control
//! 
//! Simple permission system for the knowledge graph store.

const std = @import("std");

/// Access level
pub const AccessLevel = enum {
    read,
    write,
    admin,
};

/// Access control entry
pub const ACE = struct {
    principal: []const u8,
    level: AccessLevel,
};

/// Access control list
pub const ACL = struct {
    entries: std.ArrayList(ACE),
    default_level: AccessLevel,

    pub fn init(allocator: std.mem.Allocator, default_level: AccessLevel) ACL {
        return ACL{
            .entries = std.ArrayList(ACE).init(allocator),
            .default_level = default_level,
        };
    }

    pub fn deinit(self: *ACL) void {
        for (self.entries.items) |entry| {
            self.entries.allocator.free(entry.principal);
        }
        self.entries.deinit();
    }

    /// Add an entry to ACL
    pub fn add(self: *ACL, principal: []const u8, level: AccessLevel) !void {
        try self.entries.append(.{
            .principal = try self.entries.allocator.dupe(u8, principal),
            .level = level,
        });
    }

    /// Check if principal has required access
    pub fn check(self: *ACL, principal: []const u8, required: AccessLevel) bool {
        // Admin has all access
        if (self.hasLevel(principal, .admin)) return true;

        // Check required level
        return self.hasLevel(principal, required);
    }

    /// Check if principal has specific level
    fn hasLevel(self: *ACL, principal: []const u8, level: AccessLevel) bool {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.principal, principal) and
                @intFromEnum(entry.level) >= @intFromEnum(level)) {
                return true;
            }
        }
        return false;
    }
};

/// Security context
pub const SecurityContext = struct {
    principal: []const u8,
    level: AccessLevel,
    ip_address: ?[]const u8,

    pub fn isLocalhost(self: *SecurityContext) bool {
        if (self.ip_address) |ip| {
            return std.mem.startsWith(u8, ip, "127.") or
                std.mem.startsWith(u8, ip, "localhost");
        }
        return false;
    }
};

/// Create default ACL for local-only access
pub fn createLocalACL(allocator: std.mem.Allocator) !ACL {
    var acl = ACL.init(allocator, .read);
    
    // Localhost has full access
    try acl.add("127.0.0.1", .admin);
    try acl.add("::1", .admin);
    
    return acl;
}

/// Create permissive ACL (for testing)
pub fn createPermissiveACL(allocator: std.mem.Allocator) !ACL {
    var acl = ACL.init(allocator, .admin);
    
    // Everyone has admin access
    try acl.add("*", .admin);
    
    return acl;
}
