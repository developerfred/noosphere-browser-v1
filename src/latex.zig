//! Noosphere LaTeX Processor
//! 
//! Process LaTeX math notation from papers and web.
//! Convert to various output formats.

const std = @import("std");

/// LaTeX element types
pub const LaTeXType = enum {
    text,
    math_inline,
    math_display,
    command,
    environment,
    comment,
};

/// LaTeX element
pub const LaTeXElement = struct {
    latex_type: LaTeXType,
    content: []const u8,
    start: usize,
    end: usize,
};

/// Processed LaTeX document
pub const LaTeXDocument = struct {
    elements: []LaTeXElement,
    text_content: []const u8,
    equations: []Equation,
};

pub const Equation = struct {
    latex: []const u8,
    text: []const u8,
    is_display: bool,
};

/// LaTeX processor
pub const LaTeXProcessor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LaTeXProcessor {
        return LaTeXProcessor{ .allocator = allocator };
    }

    /// Process LaTeX text and extract elements
    pub fn process(self: *LaTeXProcessor, latex: []const u8) !LaTeXDocument {
        var elements = std.ArrayList(LaTeXElement).init(self.allocator);
        var equations = std.ArrayList(Equation).init(self.allocator);
        var text_content = std.ArrayList(u8).init(self.allocator);

        var i: usize = 0;
        while (i < latex.len) {
            if (latex[i] == '%') {
                // Comment - skip to end of line
                const end = findLineEnd(latex, i);
                try elements.append(LaTeXElement{
                    .latex_type = .comment,
                    .content = latex[i..end],
                    .start = i,
                    .end = end,
                });
                i = end;
            } else if (latex[i] == '$' and i + 1 < latex.len and latex[i + 1] != '$') {
                // Inline math
                const end = findMatchingChar(latex, i + 1, '$') orelse latex.len;
                const math = latex[i + 1..end];
                try elements.append(LaTeXElement{
                    .latex_type = .math_inline,
                    .content = latex[i..end + 1],
                    .start = i,
                    .end = end + 1,
                });
                try equations.append(Equation{
                    .latex = math,
                    .text = try self.mathToText(math),
                    .is_display = false,
                });
                try text_content.appendSlice(math);
                try text_content.append(' ');
                i = end + 1;
            } else if (latex[i] == '$' and i + 1 < latex.len and latex[i + 1] == '$') {
                // Display math
                const end = findMatchingDouble(latex, i + 2, "$$") orelse latex.len;
                const math = latex[i + 2..end];
                try elements.append(LaTeXElement{
                    .latex_type = .math_display,
                    .content = latex[i..end + 2],
                    .start = i,
                    .end = end + 2,
                });
                try equations.append(Equation{
                    .latex = math,
                    .text = try self.mathToText(math),
                    .is_display = true,
                });
                try text_content.appendSlice(math);
                try text_content.append(' ');
                i = end + 2;
            } else if (latex[i] == '\\') {
                // Command
                const end = findCommandEnd(latex, i);
                const cmd = latex[i..end];
                try elements.append(LaTeXElement{
                    .latex_type = .command,
                    .content = cmd,
                    .start = i,
                    .end = end,
                });
                i = end;
            } else {
                // Regular text
                try text_content.append(latex[i]);
                i += 1;
            }
        }

        return LaTeXDocument{
            .elements = try elements.toOwnedSlice(),
            .text_content = try text_content.toOwnedSlice(),
            .equations = try equations.toOwnedSlice(),
        };
    }

    /// Convert math LaTeX to readable text
    pub fn mathToText(self: *LaTeXProcessor, math: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);

        var i: usize = 0;
        while (i < math.len) {
            if (math[i] == '\\') {
                // LaTeX command
                const cmd_end = findCommandEnd(math, i);
                const cmd = math[i + 1..cmd_end];

                const text_repr = latexCmdToText(cmd);
                try result.appendSlice(text_repr);

                i = cmd_end;
            } else if (math[i] == '^') {
                try result.append('^');
                i += 1;
            } else if (math[i] == '_') {
                try result.append('_');
                i += 1;
            } else if (math[i] == '{') {
                i += 1;
            } else if (math[i] == '}') {
                i += 1;
            } else {
                try result.append(math[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice();
    }

    /// Replace LaTeX commands with readable text in content
    pub fn renderToText(self: *LaTeXProcessor, latex: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);

        var i: usize = 0;
        while (i < latex.len) {
            if (latex[i] == '\\') {
                const cmd_end = findCommandEnd(latex, i);
                const cmd = latex[i + 1..cmd_end];

                // Get replacement
                const replacement = getLatexReplacement(cmd);
                try result.appendSlice(replacement);

                i = cmd_end;
            } else if (latex[i] == '%') {
                // Skip comments
                const end = findLineEnd(latex, i);
                i = end;
            } else if (latex[i] == '$') {
                // Skip math delimiters
                i += 1;
            } else {
                try result.append(latex[i]);
                i += 1;
            }
        }

        return result.toOwnedSlice();
    }
});

/// Common LaTeX commands to text
fn latexCmdToText(cmd: []const u8) []const u8 {
    // Single character commands
    if (cmd.len == 1) {
        return switch (cmd[0]) {
            'a' => "a",
            'e' => "e",
            'i' => "i",
            'o' => "o",
            'u' => "u",
            else => cmd,
        };
    }

    // Greek letters
    const greek = std.ComptimeStringMap([]const u8, .{
        .{ "alpha", "alpha" },
        .{ "beta", "beta" },
        .{ "gamma", "gamma" },
        .{ "delta", "delta" },
        .{ "epsilon", "epsilon" },
        .{ "lambda", "lambda" },
        .{ "mu", "mu" },
        .{ "pi", "pi" },
        .{ "sigma", "sigma" },
        .{ "phi", "phi" },
        .{ "psi", "psi" },
        .{ "omega", "omega" },
        .{ "Alpha", "Alpha" },
        .{ "Beta", "Beta" },
        .{ "Gamma", "Gamma" },
        .{ "Delta", "Delta" },
    });

    if (greek.get(cmd)) |val| return val;

    // Math symbols
    const symbols = std.ComptimeStringMap([]const u8, .{
        .{ "rightarrow", "->" },
        .{ "leftarrow", "<-" },
        .{ "Rightarrow", "=>" },
        .{ "Leftarrow", "<=" },
        .{ "infty", "inf" },
        .{ "sum", "sum" },
        .{ "prod", "prod" },
        .{ "int", "int" },
        .{ "partial", "d" },
        .{ "nabla", "nabla" },
        .{ "times", "*" },
        .{ "div", "/" },
        .{ "cdot", "." },
        .{ "leq", "<=" },
        .{ "geq", ">=" },
        .{ "neq", "!=" },
        .{ "approx", "~=" },
        .{ "equiv", "==" },
    });

    if (symbols.get(cmd)) |val| return val;

    // Words
    const words = std.ComptimeStringMap([]const u8, .{
        .{ "textbf", "" },  // Skip formatting
        .{ "textit", "" },
        .{ "mathsf", "" },
        .{ "mathrm", "" },
        .{ "mathcal", "" },
        .{ "mathbb", "" },
        .{ "textrm", "" },
        .{ "tilde", "~" },
        .{ "hat", "^" },
        .{ "bar", "-" },
        .{ "vec", "" },
    });

    if (words.get(cmd)) |val| return val;

    return cmd;
}

/// Get full replacement for a command with args
fn getLatexReplacement(cmd: []const u8) []const u8 {
    // Common replacements
    const replacements = std.ComptimeStringMap([]const u8, .{
        .{ "\\frac", "/" },
        .{ "\\sqrt", "sqrt" },
        .{ "\\sum", "sum" },
        .{ "\\prod", "prod" },
        .{ "\\int", "int" },
        .{ "\\infty", "inf" },
        .{ "\\alpha", "alpha" },
        .{ "\\beta", "beta" },
        .{ "\\gamma", "gamma" },
        .{ "\\delta", "delta" },
        .{ "\\theta", "theta" },
        .{ "\\pi", "pi" },
        .{ "\\sigma", "sigma" },
        .{ "\\phi", "phi" },
        .{ "\\omega", "omega" },
        .{ "\\lambda", "lambda" },
    });

    if (replacements.get(cmd)) |val| return val;
    return "";
}

/// Find end of line
fn findLineEnd(data: []const u8, start: usize) usize {
    var i = start;
    while (i < data.len and data[i] != '\n' and data[i] != '\r') {
        i += 1;
    }
    return i;
}

/// Find matching character (single char)
fn findMatchingChar(data: []const u8, start: usize, char: u8) ?usize {
    var i = start;
    while (i < data.len) {
        if (data[i] == char) {
            return i;
        }
        i += 1;
    }
    return null;
}

/// Find matching double-char end
fn findMatchingDouble(data: []const u8, start: usize, end_str: []const u8) ?usize {
    var i = start;
    while (i < data.len - end_str.len) {
        if (std.mem.startsWith(u8, data[i..], end_str)) {
            return i;
        }
        i += 1;
    }
    return null;
}

/// Find end of LaTeX command
fn findCommandEnd(data: []const u8, start: usize) usize {
    var i = start + 1;
    if (i >= data.len) return i;

    // Skip whitespace after \
    while (i < data.len and (data[i] == ' ' or data[i] == '\t' or data[i] == '\n')) {
        i += 1;
    }

    // Command is \name where name is letters
    while (i < data.len and std.ascii.isAlpha(data[i])) {
        i += 1;
    }

    // If followed by {}, skip those too
    if (i < data.len and data[i] == '{') {
        var depth: usize = 1;
        i += 1;
        while (i < data.len and depth > 0) {
            if (data[i] == '{') depth += 1
            else if (data[i] == '}') depth -= 1;
            i += 1;
        }
    }

    return i;
}
