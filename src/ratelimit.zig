//! Noosphere Rate Limiter
//! 
//! Prevents abuse with configurable rate limits.

const std = @import("std");
const time = std.time;

/// Rate limit configuration
pub const RateLimitConfig = struct {
    max_requests_per_second: u32 = 10,
    max_requests_per_minute: u32 = 100,
    max_requests_per_hour: u32 = 1000,
    burst_size: u32 = 20,
};

/// Rate limiter state
pub const RateLimiter = struct {
    config: RateLimitConfig,
    requests_second: u32 = 0,
    requests_minute: u32 = 0,
    requests_hour: u32 = 0,
    second_start: i64,
    minute_start: i64,
    hour_start: i64,
    burst_used: u32 = 0,
    last_burst: i64 = 0,

    pub fn init(config: RateLimitConfig) RateLimiter {
        const now = time.timestamp();
        return RateLimiter{
            .config = config,
            .second_start = now,
            .minute_start = now,
            .hour_start = now,
        };
    }

    /// Check if request is allowed
    pub fn check(self: *RateLimiter) !void {
        const now = time.timestamp();

        // Reset counters if window passed
        if (now - self.second_start >= 1) {
            self.requests_second = 0;
            self.second_start = now;
        }

        if (now - self.minute_start >= 60) {
            self.requests_minute = 0;
            self.minute_start = now;
        }

        if (now - self.hour_start >= 3600) {
            self.requests_hour = 0;
            self.hour_start = now;
        }

        // Check limits
        if (self.requests_second >= self.config.max_requests_per_second) {
            return error.RateLimitPerSecond;
        }

        if (self.requests_minute >= self.config.max_requests_per_minute) {
            return error.RateLimitPerMinute;
        }

        if (self.requests_hour >= self.config.max_requests_per_hour) {
            return error.RateLimitPerHour;
        }

        // Check burst
        if (now - self.last_burst >= 1) {
            self.burst_used = 0;
            self.last_burst = now;
        }

        if (self.burst_used >= self.config.burst_size) {
            return error.BurstLimitExceeded;
        }

        // Increment counters
        self.requests_second += 1;
        self.requests_minute += 1;
        self.requests_hour += 1;
        self.burst_used += 1;
    }

    /// Get remaining quota
    pub fn remaining(self: *RateLimiter) struct {
        second: u32,
        minute: u32,
        hour: u32,
    } {
        return .{
            .second = self.config.max_requests_per_second - self.requests_second,
            .minute = self.config.max_requests_per_minute - self.requests_minute,
            .hour = self.config.max_requests_per_hour - self.requests_hour,
        };
    }
};
