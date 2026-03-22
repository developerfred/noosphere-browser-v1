//! Noosphere Error Recovery
//! 
//! Retry logic, circuit breaker, and error handling.
//! For production-grade reliability.

const std = @import("std");

/// Error recovery config
pub const RetryConfig = struct {
    max_attempts: u32 = 3,
    initial_delay_ms: u32 = 100,
    max_delay_ms: u32 = 5000,
    backoff_multiplier: f32 = 2.0,
    jitter: bool = true,
};

/// Circuit breaker state
pub const CircuitState = enum {
    closed,   // Normal operation
    open,     // Failing, reject requests
    half_open, // Testing recovery
};

/// Circuit breaker
pub const CircuitBreaker = struct {
    state: CircuitState,
    failure_count: u32,
    success_count: u32,
    threshold: u32,
    timeout_ms: u32,
    last_failure: i64,

    pub fn init(threshold: u32, timeout_ms: u32) CircuitBreaker {
        return CircuitBreaker{
            .state = .closed,
            .failure_count = 0,
            .success_count = 0,
            .threshold = threshold,
            .timeout_ms = timeout_ms,
            .last_failure = 0,
        };
    }

    /// Record success
    pub fn success(self: *CircuitBreaker) void {
        self.failure_count = 0;
        self.success_count += 1;
        
        if (self.state == .half_open and self.success_count >= 3) {
            self.state = .closed;
            self.success_count = 0;
        }
    }

    /// Record failure
    pub fn failure(self: *CircuitBreaker) void {
        self.failure_count += 1;
        self.last_failure = std.time.timestamp();

        if (self.failure_count >= self.threshold) {
            self.state = .open;
        }
    }

    /// Check if request should proceed
    pub fn canProceed(self: *CircuitBreaker) bool {
        switch (self.state) {
            .closed => return true,
            .open => {
                // Check timeout
                const elapsed = @as(u32, @intCast(std.time.timestamp() - self.last_failure));
                if (elapsed > self.timeout_ms / 1000) {
                    self.state = .half_open;
                    self.success_count = 0;
                    return true;
                }
                return false;
            },
            .half_open => return true,
        }
    }

    /// Get current state as string
    pub fn stateString(self: *CircuitBreaker) []const u8 {
        switch (self.state) {
            .closed => return "closed",
            .open => return "open",
            .half_open => return "half-open",
        }
    }
};

/// Retry with exponential backoff
pub fn retryWithBackoff(
    max_attempts: u32,
    initial_delay_ms: u32,
    max_delay_ms: u32,
    backoff: f32,
    jitter: bool,
    operation: *const fn () anyerror!void,
) !void {
    var attempt: u32 = 0;
    var delay_ms: u32 = initial_delay_ms;

    while (attempt < max_attempts) {
        const result = operation();

        if (result) {
            return;
        } else |err| {
            attempt += 1;
            
            if (attempt >= max_attempts) {
                return err;
            }

            // Calculate delay with backoff
            delay_ms = @min(@as(u32, @intCast(@as(f32, @floatFromInt(delay_ms)) * backoff)), max_delay_ms);

            // Add jitter
            if (jitter) {
                const jitter_amount = std.crypto.random.intRangeAtMost(u32, 0, delay_ms / 4);
                delay_ms += jitter_amount;
            }

            std.time.sleep(delay_ms * std.time.ns_per_ms);
        }
    }
}

/// Generic retry wrapper
pub const RetryOperation = struct {
    config: RetryConfig,

    pub fn init(config: RetryConfig) RetryOperation {
        return RetryOperation{ .config = config };
    }

    pub fn execute(self: *RetryOperation, operation: *const fn () anyerror!void) !void {
        try retryWithBackoff(
            self.config.max_attempts,
            self.config.initial_delay_ms,
            self.config.max_delay_ms,
            self.config.backoff_multiplier,
            self.config.jitter,
            operation,
        );
    }
};

/// Error category
pub const ErrorCategory = enum {
    network,
    parse,
    storage,
    access,
    unknown,
};

/// Categorized error
pub const CategorizedError = struct {
    category: ErrorCategory,
    message: []const u8,
    retryable: bool,
};

/// Categorize error for retry decision
pub fn categorizeError(err: anyerror) CategorizedError {
    const err_name = @errorName(err);
    
    // Network errors are retryable
    if (std.mem.containsAtLeast(u8, err_name, 6) and 
        (std.mem.indexOf(u8, err_name, "Network") != null or
         std.mem.indexOf(u8, err_name, "Connection") != null or
         std.mem.indexOf(u8, err_name, "Timeout") != null or
         std.mem.indexOf(u8, err_name, "Host") != null)) {
        return CategorizedError{
            .category = .network,
            .message = err_name,
            .retryable = true,
        };
    }

    // Parse errors are not retryable
    if (std.mem.indexOf(u8, err_name, "Parse") != null or
        std.mem.indexOf(u8, err_name, "Invalid") != null or
        std.mem.indexOf(u8, err_name, "Format") != null) {
        return CategorizedError{
            .category = .parse,
            .message = err_name,
            .retryable = false,
        };
    }

    // Storage errors might be retryable
    if (std.mem.indexOf(u8, err_name, "Disk") != null or
        std.mem.indexOf(u8, err_name, "IO") != null or
        std.mem.indexOf(u8, err_name, "File") != null) {
        return CategorizedError{
            .category = .storage,
            .message = err_name,
            .retryable = true,
        };
    }

    return CategorizedError{
        .category = .unknown,
        .message = err_name,
        .retryable = false,
    };
}

/// Health check result
pub const HealthStatus = struct {
    healthy: bool,
    latency_ms: u32,
    checks_passed: u32,
    checks_failed: u32,
    details: []const u8,
};

/// Health checker
pub const HealthChecker = struct {
    allocator: std.mem.Allocator,
    checks: std.ArrayList(HealthCheck),
    circuit_breakers: std.StringHashMap(CircuitBreaker),

    pub const HealthCheck = struct {
        name: []const u8,
        check_fn: *const fn () anyerror!bool,
    },

    pub fn init(allocator: std.mem.Allocator) HealthChecker {
        return HealthChecker{
            .allocator = allocator,
            .checks = std.ArrayList(HealthCheck).init(allocator),
            .circuit_breakers = std.StringHashMap(CircuitBreaker).init(allocator),
        };
    }

    pub fn deinit(self: *HealthChecker) void {
        self.checks.deinit();
        var it = self.circuit_breakers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.circuit_breakers.deinit();
    }

    pub fn addCheck(self: *HealthChecker, name: []const u8, check_fn: *const fn () anyerror!bool) !void {
        try self.checks.append(HealthCheck{
            .name = try self.allocator.dupe(u8, name),
            .check_fn = check_fn,
        });
    }

    pub fn checkAll(self: *HealthChecker) !HealthStatus {
        var passed: u32 = 0;
        var failed: u32 = 0;
        var start = std.time.milliTimestamp();

        for (self.checks.items) |check| {
            const result = check.check_fn();
            
            if (result) |ok| {
                if (ok) passed += 1 else failed += 1;
            } else |_| {
                failed += 1;
            }
        }

        const latency = @as(u32, @intCast(std.time.milliTimestamp() - start));

        return HealthStatus{
            .healthy = failed == 0,
            .latency_ms = latency,
            .checks_passed = passed,
            .checks_failed = failed,
            .details = if (failed > 0) "Some checks failed" else "All checks passed",
        };
    }
};
