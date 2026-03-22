//! Noosphere Metrics
//! 
//! Performance monitoring and resource tracking.
//! For ensuring <2MB binary and <128MB RAM targets.

const std = @import("std");

/// Memory usage stats
pub const MemoryStats = struct {
    rss_bytes: u64,         // Resident set size
    heap_bytes: u64,        // Heap allocation
    total_alloc: u64,       // Total allocated ever
    total_free: u64,        // Total freed
    active_allocs: u64,     // Current active allocations
    allocation_count: u64,  // Total allocations
};

/// Performance metrics
pub const Metrics = struct {
    requests_total: u64,
    requests_success: u64,
    requests_failed: u64,
    bytes_fetched: u64,
    parse_time_ms: u64,
    memory_stats: MemoryStats,
    start_time: i64,
};

/// Counter for tracking
pub const Counter = struct {
    value: u64,
    lock: std.Mutex,

    pub fn init() Counter {
        return Counter{ .value = 0, .lock = std.Mutex{} };
    }

    pub fn inc(self: *Counter) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.value += 1;
    }

    pub fn add(self: *Counter, n: u64) void {
        self.lock.lock();
        defer self.lock.unlock();
        self.value += n;
    }

    pub fn get(self: *Counter) u64 {
        self.lock.lock();
        defer self.lock.unlock();
        return self.value;
    }
};

/// Histogram for latency tracking
pub const Histogram = struct {
    counts: [6]u64, // Buckets: <10ms, <50ms, <100ms, <500ms, <1s, >1s
    total_ns: u64,
    count: u64,
    lock: std.Mutex,

    pub fn init() Histogram {
        return Histogram{
            .counts = [_]u64{0} ** 6,
            .total_ns = 0,
            .count = 0,
            .lock = std.Mutex{},
        };
    }

    pub fn record(self: *Histogram, duration_ns: u64) void {
        self.lock.lock();
        defer self.lock.unlock();

        self.total_ns += duration_ns;
        self.count += 1;

        const ms = duration_ns / std.time.ns_per_ms;
        
        if (ms < 10) self.counts[0] += 1
        else if (ms < 50) self.counts[1] += 1
        else if (ms < 100) self.counts[2] += 1
        else if (ms < 500) self.counts[3] += 1
        else if (ms < 1000) self.counts[4] += 1
        else self.counts[5] += 1;
    }

    pub fn mean(self: *Histogram) f64 {
        self.lock.lock();
        defer self.lock.unlock();

        if (self.count == 0) return 0;
        return @as(f64, @floatFromInt(self.total_ns)) / @as(f64, @floatFromInt(self.count)) / std.time.ns_per_ms;
    }

    pub fn p50(self: *Histogram) f64 {
        // Approximate median from histogram
        return self.percentile(50);
    }

    pub fn p95(self: *Histogram) f64 {
        return self.percentile(95);
    }

    fn percentile(self: *Histogram, p: u32) f64 {
        self.lock.lock();
        defer self.lock.unlock();

        if (self.count == 0) return 0;

        const target = @as(u64, @intCast(@as(f64, @floatFromInt(self.count)) * @as(f64, @intCast(p)) / 100.0));
        
        var cumulative: u64 = 0;
        for (self.counts, 0..) |bucket_count, i| {
            cumulative += bucket_count;
            if (cumulative >= target) {
                // Return bucket midpoint in ms
                return switch (i) {
                    0 => 5.0,
                    1 => 30.0,
                    2 => 75.0,
                    3 => 300.0,
                    4 => 750.0,
                    else => 1500.0,
                };
            }
        }

        return self.mean();
    }
};

/// Metrics collector
pub const MetricsCollector = struct {
    allocator: std.mem.Allocator,
    requests: Counter,
    successes: Counter,
    failures: Counter,
    bytes_fetched: Counter,
    parse_time: Histogram,
    fetch_time: Histogram,
    memory_stats: MemoryStats,

    pub fn init(allocator: std.mem.Allocator) MetricsCollector {
        return MetricsCollector{
            .allocator = allocator,
            .requests = Counter.init(),
            .successes = Counter.init(),
            .failures = Counter.init(),
            .bytes_fetched = Counter.init(),
            .parse_time = Histogram.init(),
            .fetch_time = Histogram.init(),
            .memory_stats = MemoryStats{
                .rss_bytes = 0,
                .heap_bytes = 0,
                .total_alloc = 0,
                .total_free = 0,
                .active_allocs = 0,
                .allocation_count = 0,
            },
        };
    }

    pub fn recordRequest(self: *MetricsCollector) void {
        self.requests.inc();
    }

    pub fn recordSuccess(self: *MetricsCollector, bytes: u64, parse_ns: u64, fetch_ns: u64) void {
        self.successes.inc();
        self.bytes_fetched.add(bytes);
        self.parse_time.record(parse_ns);
        self.fetch_time.record(fetch_ns);
    }

    pub fn recordFailure(self: *MetricsCollector) void {
        self.failures.inc();
    }

    pub fn getMemoryStats(self: *MetricsCollector) void {
        // On Linux, read /proc/self/statm
        // TODO: Platform-specific memory stats
    }

    pub fn getReport(self: *MetricsCollector) []const u8 {
        const total = self.requests.get();
        const success = self.successes.get();
        const fail = self.failures.get();

        if (total == 0) return "No requests yet";

        const success_rate = @as(f64, @floatFromInt(success)) / @as(f64, @floatFromInt(total)) * 100;

        return std.fmt.allocPrint(self.allocator,
            \\Requests: {d} (Success: {d}, Failed: {d}, Rate: {d:.1f}%)
            \\Bytes: {d}
            \\Parse Time: mean={d:.1f}ms, p50={d:.1f}ms, p95={d:.1f}ms
        , .{
            total, success, fail, success_rate,
            self.bytes_fetched.get(),
            self.parse_time.mean(),
            self.parse_time.p50(),
            self.parse_time.p95(),
        }) catch return "Error generating report";
    }

    pub fn reset(self: *MetricsCollector) void {
        // Reset counters but keep configuration
        self.requests = Counter.init();
        self.successes = Counter.init();
        self.failures = Counter.init();
        self.bytes_fetched = Counter.init();
        self.parse_time = Histogram.init();
        self.fetch_time = Histogram.init();
    }
};

/// Performance budget
pub const PerformanceBudget = struct {
    max_binary_bytes: u64 = 5 * 1024 * 1024,    // 5MB default
    max_memory_bytes: u64 = 512 * 1024 * 1024,   // 512MB default (goal: 128MB)
    max_latency_ms: u32 = 5000,                    // 5s timeout

    pub fn checkBinarySize(self: *const PerformanceBudget, size_bytes: u64) bool {
        return size_bytes <= self.max_binary_bytes;
    }

    pub fn checkMemory(self: *const PerformanceBudget, rss_bytes: u64) bool {
        return rss_bytes <= self.max_memory_bytes;
    }
};
