const std = @import("std");

pub const c = @cImport({
    @cInclude("prism.h");
});

pub const prism = c;

pub const NodeType = prism.pm_node_type_t;
