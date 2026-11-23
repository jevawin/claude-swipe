// Linked chats in the Indent layout: each chat sits under the chat it was started from.
// AppKit-free, so tests/run.sh can check it.

// Where a row sits. depth 0 is a top-level row. guides[k] is true when the line at
// level k carries on past this row to a later sibling.
struct TreeSpot: Equatable {
    var depth = 0
    var guides: [Bool] = []
    var last = true      // the last child of its parent
    var hasKids = false  // a child is listed right below it
}

// Each item whose parent is in the same list goes under that parent. A branch sits
// where its earliest item sits (lists come newest first), so a busy side session pulls
// its parent up with it. Items whose parent isn't listed stay top level. A loop of
// parents should never come from the app; if one did, every item still shows once.
func treeOrder<T>(_ items: [T], id: (T) -> String, node: (T) -> String?, parent: (T) -> String?)
    -> [(item: T, spot: TreeSpot)] {
    let nodes = Set(items.compactMap(node))
    var kids: [String: [Int]] = [:], roots: [Int] = []
    for (i, t) in items.enumerated() {
        if let p = parent(t), p != node(t), nodes.contains(p) { kids[p, default: []].append(i) } else { roots.append(i) }
    }
    var rankMemo: [Int: Int] = [:]
    func rank(_ i: Int, _ seen: Set<Int> = []) -> Int {
        if let r = rankMemo[i] { return r }
        var r = i
        for k in kids[node(items[i]) ?? ""] ?? [] where !seen.contains(k) { r = min(r, rank(k, seen.union([i]))) }
        rankMemo[i] = r
        return r
    }
    var out: [(item: T, spot: TreeSpot)] = [], placed = Set<String>()
    func walk(_ i: Int, _ spot: TreeSpot) {
        guard placed.insert(id(items[i])).inserted else { return }
        let children = (kids[node(items[i]) ?? ""] ?? []).filter { !placed.contains(id(items[$0])) }.sorted { rank($0) < rank($1) }
        var me = spot
        me.hasKids = !children.isEmpty
        out.append((items[i], me))
        let guides = spot.depth == 0 ? [] : spot.guides + [!spot.last]
        for (n, k) in children.enumerated() {
            walk(k, TreeSpot(depth: spot.depth + 1, guides: guides, last: n == children.count - 1))
        }
    }
    for r in roots.sorted(by: { rank($0) < rank($1) }) { walk(r, TreeSpot()) }
    for i in items.indices where !placed.contains(id(items[i])) { walk(i, TreeSpot()) }
    return out
}
