const std = @import("std");

/// Trade entity: Represents a single trade from Binance WebSocket.
/// Adheres to clean code by being a pure data model; logic is separated.
pub const Trade = struct {
    /// Event type (e.g., "trade")
    type: []const u8,
    /// Event timestamp (milliseconds, E)
    event_timestamp: i64,
    /// Trading pair (e.g., "btcusdt", s)
    trade_pair: []const u8,
    /// Trade ID as string (t)
    trade_id: i64,
    /// Price as string (p)
    price: []const u8,
    /// Quantity as string (q)
    quantity: []const u8,
    /// Trade timestamp (milliseconds, T)
    trade_timestamp: i64,
    /// Buy/sell side (derived from m: true = sell)
    side: Side,
    /// Computed value: price * quantity (f64)
    value: f64,
    /// Original message as JSON string
    original_msg: []const u8,

    pub const Side = enum { buy, sell };

    /// Specific errors for parsing failures.
    pub const ParseError = error{
        /// Generic JSON syntax error.
        InvalidJson,
        /// "e" field missing or invalid.
        MissingType,
        /// "E" field missing or invalid.
        MissingEventTimestamp,
        /// "s" field missing or invalid.
        MissingTradePair,
        /// "t" field missing or invalid.
        MissingTradeId,
        /// "p" field missing or invalid.
        MissingPrice,
        /// "q" field missing or invalid.
        MissingQuantity,
        /// "T" field missing or invalid.
        MissingTradeTimestamp,
        /// "m" field missing or invalid.
        MissingSide,
        /// Price/quantity invalid (e.g., negative or unparseable).
        InvalidValue,
    };

    /// Parses a Trade from Binance WebSocket JSON payload.
    /// Returns specific errors for each failure point.
    pub fn parseFromJson(json_text: []const u8) ParseError!Trade {
        // Extract all fields from JSON (manual for zero-alloc)
        const type_str = extractString(json_text, "e") catch return ParseError.MissingType;
        const event_timestamp = extractInt(json_text, "E") catch return ParseError.MissingEventTimestamp;
        const trade_pair = extractString(json_text, "s") catch return ParseError.MissingTradePair;
        const trade_id_str = extractInt(json_text, "t") catch return ParseError.MissingTradeId;
        const price_str = extractString(json_text, "p") catch return ParseError.MissingPrice;
        const quantity_str = extractString(json_text, "q") catch return ParseError.MissingQuantity;
        const trade_timestamp = extractInt(json_text, "T") catch return ParseError.MissingTradeTimestamp;

        // Special: m is boolean, not quoted
        const m_val = extractBool(json_text, "m") catch return ParseError.MissingSide;
        const side: Side = switch (m_val) {
            true => .sell,
            false => .buy,
        };

        // Parse floats and compute value (with validation)
        const price = std.fmt.parseFloat(f64, price_str) catch return ParseError.MissingPrice;
        const quantity = std.fmt.parseFloat(f64, quantity_str) catch return ParseError.MissingQuantity;
        if (price < 0 or quantity < 0) return error.InvalidValue;
        const value = std.math.round((price * quantity) * 100.0) / 100.0;

        return .{
            .type = type_str,
            .event_timestamp = event_timestamp,
            .trade_pair = trade_pair,
            .trade_id = trade_id_str,
            .price = price_str,
            .quantity = quantity_str,
            .trade_timestamp = trade_timestamp,
            .side = side,
            .value = value,
            .original_msg = json_text,
        };
    }

    // Helpers remain unchanged (return error.InvalidJson on failure)
    fn extractString(json_text: []const u8, field: []const u8) ![]const u8 {
        var prefix_buf: [20]u8 = undefined;
        const prefix = try std.fmt.bufPrint(&prefix_buf, "\"{s}\":\"", .{field});
        const start = std.mem.indexOf(u8, json_text, prefix) orelse return error.InvalidJson;
        const val_start = start + prefix.len;
        const end = std.mem.indexOfPos(u8, json_text, val_start, "\"") orelse return error.InvalidJson;
        return json_text[val_start..end];
    }

    fn extractInt(json_text: []const u8, field: []const u8) !i64 {
        var prefix_buf: [20]u8 = undefined;
        const prefix = try std.fmt.bufPrint(&prefix_buf, "\"{s}\":", .{field});
        const start = std.mem.indexOf(u8, json_text, prefix) orelse return error.InvalidJson;
        const val_start = start + prefix.len;
        const end = std.mem.indexOfPos(u8, json_text, val_start, ",") orelse std.mem.indexOfPos(u8, json_text, val_start, "}") orelse return error.InvalidJson;
        const val_str = std.mem.trim(u8, json_text[val_start..end], " ");
        return std.fmt.parseInt(i64, val_str, 10);
    }

    fn extractBool(json_text: []const u8, field: []const u8) !bool {
        var prefix_buf: [20]u8 = undefined;
        const prefix = try std.fmt.bufPrint(&prefix_buf, "\"{s}\":", .{field});
        const start = std.mem.indexOf(u8, json_text, prefix) orelse return error.InvalidJson;
        const val_start = start + prefix.len;
        const val_char = json_text[val_start];
        return switch (val_char) {
            't' => true,
            'f' => false,
            else => return error.InvalidJson,
        };
    }
    /// Serializes the Trade to a JSON string (compact, zero-alloc friendly).
    /// Returns a heap-allocated slice; caller must free with allocator.free().
    pub fn toJson(self: Trade, allocator: std.mem.Allocator) ![]const u8 {
        // Estimate size (adjust if needed; prevents reallocs).
        var list = try std.ArrayList(u8).initCapacity(allocator, 1024);
        defer list.deinit(allocator); // Fix: Pass allocator

        try list.writer(allocator).print(
            \\{{"type":"{s}","event_timestamp":{d},"trade_pair":"{s}","trade_id":"{d}","price":"{s}","quantity":"{s}","trade_timestamp":{d},"side":"{s}","value":{d:.2}}}"
        , .{
            self.type,
            self.event_timestamp,
            self.trade_pair,
            self.trade_id,
            self.price,
            self.quantity,
            self.trade_timestamp,
            @tagName(self.side),
            self.value,
        });

        return list.toOwnedSlice(allocator);
    }
};

// Add this at the end of src/trade.zig, after the closing brace of the Trade struct

test "parseFromJson - valid buy trade" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","t":12345,"p":"50000.50","q":"0.1","T":1234567890,"m":false}
    ;

    const trade = try Trade.parseFromJson(json);

    try std.testing.expectEqualStrings("trade", trade.type);
    try std.testing.expectEqual(@as(i64, 1234567890), trade.event_timestamp);
    try std.testing.expectEqualStrings("btcusdt", trade.trade_pair);
    try std.testing.expectEqual(@as(i64, 12345), trade.trade_id);
    try std.testing.expectEqualStrings("50000.50", trade.price);
    try std.testing.expectEqualStrings("0.1", trade.quantity);
    try std.testing.expectEqual(@as(i64, 1234567890), trade.trade_timestamp);
    try std.testing.expectEqual(Trade.Side.buy, trade.side);
    try std.testing.expectApproxEqAbs(@as(f64, 5000.05), trade.value, 0.01);
}

test "parseFromJson - valid sell trade" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"ethusdt","t":67890,"p":"3000.25","q":"2.5","T":1234567890,"m":true}
    ;

    const trade = try Trade.parseFromJson(json);

    try std.testing.expectEqual(Trade.Side.sell, trade.side);
    try std.testing.expectApproxEqAbs(@as(f64, 7500.63), trade.value, 0.01);
}

test "parseFromJson - value rounding to 2 decimal places" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","t":12345,"p":"100.333","q":"2.777","T":1234567890,"m":false}
    ;

    const trade = try Trade.parseFromJson(json);
    // 100.333 * 2.777 = 278.624441, rounded to 2 decimals = 278.62
    try std.testing.expectApproxEqAbs(@as(f64, 278.62), trade.value, 0.01);
}

test "parseFromJson - missing type field" {
    const json =
        \\{"E":1234567890,"s":"btcusdt","t":12345,"p":"50000.50","q":"0.1","T":1234567890,"m":false}
    ;

    const result = Trade.parseFromJson(json);
    try std.testing.expectError(Trade.ParseError.MissingType, result);
}

test "parseFromJson - missing event timestamp" {
    const json =
        \\{"e":"trade","s":"btcusdt","t":12345,"p":"50000.50","q":"0.1","T":1234567890,"m":false}
    ;

    const result = Trade.parseFromJson(json);
    try std.testing.expectError(Trade.ParseError.MissingEventTimestamp, result);
}

test "parseFromJson - missing trade pair" {
    const json =
        \\{"e":"trade","E":1234567890,"t":12345,"p":"50000.50","q":"0.1","T":1234567890,"m":false}
    ;

    const result = Trade.parseFromJson(json);
    try std.testing.expectError(Trade.ParseError.MissingTradePair, result);
}

test "parseFromJson - missing trade id" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","p":"50000.50","q":"0.1","T":1234567890,"m":false}
    ;

    const result = Trade.parseFromJson(json);
    try std.testing.expectError(Trade.ParseError.MissingTradeId, result);
}

test "parseFromJson - missing price" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","t":12345,"q":"0.1","T":1234567890,"m":false}
    ;

    const result = Trade.parseFromJson(json);
    try std.testing.expectError(Trade.ParseError.MissingPrice, result);
}

test "parseFromJson - missing quantity" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","t":12345,"p":"50000.50","T":1234567890,"m":false}
    ;

    const result = Trade.parseFromJson(json);
    try std.testing.expectError(Trade.ParseError.MissingQuantity, result);
}

test "parseFromJson - missing trade timestamp" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","t":12345,"p":"50000.50","q":"0.1","m":false}
    ;

    const result = Trade.parseFromJson(json);
    try std.testing.expectError(Trade.ParseError.MissingTradeTimestamp, result);
}

test "parseFromJson - missing side" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","t":12345,"p":"50000.50","q":"0.1","T":1234567890}
    ;

    const result = Trade.parseFromJson(json);
    try std.testing.expectError(Trade.ParseError.MissingSide, result);
}

test "parseFromJson - negative price" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","t":12345,"p":"-50000.50","q":"0.1","T":1234567890,"m":false}
    ;

    const result = Trade.parseFromJson(json);
    try std.testing.expectError(Trade.ParseError.InvalidValue, result);
}

test "parseFromJson - negative quantity" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","t":12345,"p":"50000.50","q":"-0.1","T":1234567890,"m":false}
    ;

    const result = Trade.parseFromJson(json);
    try std.testing.expectError(Trade.ParseError.InvalidValue, result);
}

test "parseFromJson - invalid price format" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","t":12345,"p":"invalid","q":"0.1","T":1234567890,"m":false}
    ;

    const result = Trade.parseFromJson(json);
    try std.testing.expectError(Trade.ParseError.MissingPrice, result);
}

test "parseFromJson - invalid quantity format" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","t":12345,"p":"50000.50","q":"invalid","T":1234567890,"m":false}
    ;

    const result = Trade.parseFromJson(json);
    try std.testing.expectError(Trade.ParseError.MissingQuantity, result);
}

test "parseFromJson - zero value" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","t":12345,"p":"0.0","q":"0.0","T":1234567890,"m":false}
    ;

    const trade = try Trade.parseFromJson(json);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), trade.value, 0.01);
}

test "toJson - serialization" {
    const json_input =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","t":12345,"p":"50000.50","q":"0.1","T":1234567890,"m":false}
    ;

    const trade = try Trade.parseFromJson(json_input);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json_output = try trade.toJson(allocator);
    defer allocator.free(json_output);

    // Verify the output contains expected fields
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"type\":\"trade\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"trade_pair\":\"btcusdt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"side\":\"buy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"value\":") != null);

    // Verify value is formatted with 2 decimal places
    const value_start = std.mem.indexOf(u8, json_output, "\"value\":") orelse return error.NotFound;
    const value_end = std.mem.indexOfPos(u8, json_output, value_start, "}") orelse return error.NotFound;
    const value_str = json_output[value_start + 8 .. value_end];

    // Check that value has at most 2 decimal places (e.g., "5000.05" or "5000.00")
    const dot_pos = std.mem.indexOf(u8, value_str, ".") orelse return;
    if (dot_pos < value_str.len - 1) {
        const decimal_part = value_str[dot_pos + 1 ..];
        try std.testing.expect(decimal_part.len <= 2);
    }
}

test "parseFromJson - preserves original message" {
    const json =
        \\{"e":"trade","E":1234567890,"s":"btcusdt","t":12345,"p":"50000.50","q":"0.1","T":1234567890,"m":false}
    ;

    const trade = try Trade.parseFromJson(json);
    try std.testing.expectEqualStrings(json, trade.original_msg);
}
