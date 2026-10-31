pub const packages = struct {
    pub const @"aro-0.0.0-JSD1Qi2TNgAqcz8WhBqh5B4FcjLw2WZCvRMqPfT8Q9gY" = struct {
        pub const build_root = "zig-pkg/aro-0.0.0-JSD1Qi2TNgAqcz8WhBqh5B4FcjLw2WZCvRMqPfT8Q9gY";
        pub const build_zig = @import("aro-0.0.0-JSD1Qi2TNgAqcz8WhBqh5B4FcjLw2WZCvRMqPfT8Q9gY");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"translate_c-0.0.0-Q_BUWsauBgDTOOw7VrbuT5gkfPrXhh8WCZng6qfoETNC" = struct {
        pub const build_root = "zig-pkg/translate_c-0.0.0-Q_BUWsauBgDTOOw7VrbuT5gkfPrXhh8WCZng6qfoETNC";
        pub const build_zig = @import("translate_c-0.0.0-Q_BUWsauBgDTOOw7VrbuT5gkfPrXhh8WCZng6qfoETNC");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "aro", "aro-0.0.0-JSD1Qi2TNgAqcz8WhBqh5B4FcjLw2WZCvRMqPfT8Q9gY" },
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "translate_c", "translate_c-0.0.0-Q_BUWsauBgDTOOw7VrbuT5gkfPrXhh8WCZng6qfoETNC" },
};
