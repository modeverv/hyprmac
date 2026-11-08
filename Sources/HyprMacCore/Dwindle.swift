import CoreGraphics

/// A node of Hyprland's "dwindle" binary layout tree.
/// Leaves hold a window; inner nodes split their rectangle in two.
public final class DwindleNode {
    public fileprivate(set) var window: UInt32?
    public fileprivate(set) var children: [DwindleNode] = []
    /// true: children are side by side (left | right). false: stacked (top / bottom).
    public fileprivate(set) var splitHorizontally = true
    /// Share of the first child (0.1 ... 0.9).
    public fileprivate(set) var ratio: CGFloat = 0.5
    fileprivate weak var parent: DwindleNode?

    init(window: UInt32?) { self.window = window }
}

/// Dwindle layout: every new window splits the focused (or last) window,
/// along its longer side. All coordinates use the Accessibility convention
/// (origin top-left, y grows downward).
public final class DwindleTree {
    public private(set) var root: DwindleNode?

    public init() {}

    public var isEmpty: Bool { root == nil }

    /// Windows in tree order (left/top first).
    public var windows: [UInt32] {
        var out: [UInt32] = []
        func collect(_ n: DwindleNode?) {
            guard let n else { return }
            if let w = n.window { out.append(w) }
            n.children.forEach(collect)
        }
        collect(root)
        return out
    }

    public func contains(_ id: UInt32) -> Bool { leaf(for: id) != nil }

    /// Inserts `id` by splitting the leaf of `target` (or the last leaf).
    /// The split axis follows the target's current shape, like Hyprland.
    public func insert(_ id: UInt32, splitting target: UInt32?, bounds: CGRect) {
        guard !contains(id) else { return }
        let newLeaf = DwindleNode(window: id)
        guard let root else {
            self.root = newLeaf
            return
        }
        let targetLeaf = target.flatMap { leaf(for: $0) } ?? lastLeaf(root)
        var rect = bounds
        walk(root, bounds) { node, r in if node === targetLeaf { rect = r } }

        let split = DwindleNode(window: nil)
        split.splitHorizontally = rect.width >= rect.height
        replace(targetLeaf, with: split)
        split.children = [targetLeaf, newLeaf]
        targetLeaf.parent = split
        newLeaf.parent = split
    }

    public func remove(_ id: UInt32) {
        guard let leaf = leaf(for: id) else { return }
        guard let parent = leaf.parent else {
            root = nil
            return
        }
        let sibling = parent.children.first { $0 !== leaf }!
        replace(parent, with: sibling)
    }

    public func swap(_ a: UInt32, _ b: UInt32) {
        guard let la = leaf(for: a), let lb = leaf(for: b) else { return }
        la.window = b
        lb.window = a
    }

    /// Flips the split direction of the window's parent (Hyprland `togglesplit`).
    public func toggleSplit(_ id: UInt32) {
        leaf(for: id)?.parent?.splitHorizontally.toggle()
    }

    /// Grows (positive delta) or shrinks the window's share of its parent split.
    public func adjustRatio(_ id: UInt32, by delta: CGFloat) {
        guard let leaf = leaf(for: id), let parent = leaf.parent else { return }
        let signed = parent.children.first === leaf ? delta : -delta
        parent.ratio = min(0.9, max(0.1, parent.ratio + signed))
    }

    /// Computes window frames. `gapsOut` is the margin to the monitor edge,
    /// `gapsIn` is applied around each window (so 2×gapsIn between windows).
    public func layout(in bounds: CGRect, gapsIn: CGFloat = 0, gapsOut: CGFloat = 0) -> [UInt32: CGRect] {
        guard let root else { return [:] }
        let outer = bounds.insetBy(dx: gapsOut - gapsIn, dy: gapsOut - gapsIn)
        var result: [UInt32: CGRect] = [:]
        walk(root, outer) { node, rect in
            guard let w = node.window else { return }
            let r = rect.insetBy(dx: gapsIn, dy: gapsIn)
            result[w] = CGRect(x: r.minX.rounded(), y: r.minY.rounded(),
                               width: max(1, r.width.rounded()), height: max(1, r.height.rounded()))
        }
        return result
    }

    // MARK: - Internals

    private func leaf(for id: UInt32) -> DwindleNode? {
        func find(_ n: DwindleNode?) -> DwindleNode? {
            guard let n else { return nil }
            if n.window == id { return n }
            for c in n.children { if let f = find(c) { return f } }
            return nil
        }
        return find(root)
    }

    private func lastLeaf(_ n: DwindleNode) -> DwindleNode {
        var cur = n
        while let last = cur.children.last { cur = last }
        return cur
    }

    private func replace(_ old: DwindleNode, with new: DwindleNode) {
        if let p = old.parent, let i = p.children.firstIndex(where: { $0 === old }) {
            p.children[i] = new
            new.parent = p
        } else {
            root = new
            new.parent = nil
        }
    }

    private func walk(_ node: DwindleNode, _ rect: CGRect, _ visit: (DwindleNode, CGRect) -> Void) {
        visit(node, rect)
        guard node.children.count == 2 else { return }
        let a: CGRect, b: CGRect
        if node.splitHorizontally {
            let w = (rect.width * node.ratio).rounded()
            a = CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height)
            b = CGRect(x: rect.minX + w, y: rect.minY, width: rect.width - w, height: rect.height)
        } else {
            let h = (rect.height * node.ratio).rounded()
            a = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h)
            b = CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h)
        }
        walk(node.children[0], a, visit)
        walk(node.children[1], b, visit)
    }
}
