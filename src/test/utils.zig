const types = @import("../parser/types.zig");

const AstNode = types.AstNode;
const NodeKind = types.NodeKind;

/// Returns a direct child with the requested kind or null when absent.
pub fn findChild(node: *const AstNode, kind: NodeKind) ?*const AstNode {
    for (node.children, 0..) |child, index| {
        if (child.kind == kind) {
            return &node.children[index];
        }
    }
    return null;
}

/// Performs a depth-first search to check whether any node matches the kind.
pub fn hasNode(node: *const AstNode, kind: NodeKind) bool {
    if (node.kind == kind) return true;
    for (node.children) |child| {
        if (hasNode(&child, kind)) return true;
    }
    return false;
}
