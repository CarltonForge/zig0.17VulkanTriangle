pub const packages = struct {
    pub const @"aro-0.0.0-JSD1QtdkOQAWPwBQDx-LugmB9nY29cc5so3BPZvsinDe" = struct {
        pub const build_root = "zig-pkg/aro-0.0.0-JSD1QtdkOQAWPwBQDx-LugmB9nY29cc5so3BPZvsinDe";
        pub const build_zig = @import("aro-0.0.0-JSD1QtdkOQAWPwBQDx-LugmB9nY29cc5so3BPZvsinDe");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"translate_c-0.0.0-Q_BUWrNjBwCHg3y4GIuz1euFBi2u5G9C5JP4wHCNJ6BZ" = struct {
        pub const build_root = "zig-pkg/translate_c-0.0.0-Q_BUWrNjBwCHg3y4GIuz1euFBi2u5G9C5JP4wHCNJ6BZ";
        pub const build_zig = @import("translate_c-0.0.0-Q_BUWrNjBwCHg3y4GIuz1euFBi2u5G9C5JP4wHCNJ6BZ");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "aro", "aro-0.0.0-JSD1QtdkOQAWPwBQDx-LugmB9nY29cc5so3BPZvsinDe" },
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "translate_c", "translate_c-0.0.0-Q_BUWrNjBwCHg3y4GIuz1euFBi2u5G9C5JP4wHCNJ6BZ" },
};
