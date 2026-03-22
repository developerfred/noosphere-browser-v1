//! Noosphere Secure Store
//! 
//! Access-controlled wrapper around the knowledge graph store.

const std = @import("std");
const store = @import("store.zig");
const access = @import("access.zig");

/// Secure store with access control
pub const SecureStore = struct {
    inner: store.Store,
    acl: access.ACL,
    allocator: std.mem.Allocator,

    /// Initialize secure store
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !SecureStore {
        const inner = try store.Store.init(allocator, path);
        const acl = try access.createLocalACL(allocator);

        return SecureStore{
            .inner = inner,
            .acl = acl,
            .allocator = allocator,
        };
    }

    /// Deinitialize secure store
    pub fn deinit(self: *SecureStore) void {
        self.inner.deinit();
        self.acl.deinit();
    }

    /// Add page with access check
    pub fn addPage(self: *SecureStore, ctx: *access.SecurityContext, url: []const u8, semantic: anytype) !void {
        // SECURITY: Require write access
        if (!self.acl.check(ctx.principal, .write)) {
            return store.StoreError.AccessDenied;
        }

        // SECURITY: Validate URL
        if (url.len > 2048) {
            return store.StoreError.InvalidPath;
        }

        return self.inner.addPage(url, semantic);
    }

    /// Get all pages with access check
    pub fn getAllPages(self: *SecureStore, ctx: *access.SecurityContext) ![]store.Page {
        // SECURITY: Require read access
        if (!self.acl.check(ctx.principal, .read)) {
            return store.StoreError.AccessDenied;
        }

        return self.inner.getAllPages();
    }

    /// Search pages with access check
    pub fn search(self: *SecureStore, ctx: *access.SecurityContext, query: []const u8) ![]store.Page {
        // SECURITY: Require read access
        if (!self.acl.check(ctx.principal, .read)) {
            return store.StoreError.AccessDenied;
        }

        // SECURITY: Limit query length
        if (query.len > 256) {
            return store.StoreError.InvalidPath;
        }

        return self.inner.search(query);
    }
};
