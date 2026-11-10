// Card sizes for Settings › Cards › Card size. The panel stays the same width;
// smaller cards just fit more chats on screen.
//   default: the original card.
//   cozy:    everything a little smaller, same information.
//   compact: cozy sizes, and the summary drops to one line.

import CoreGraphics

struct CardMetrics {
    let tile: CGFloat           // icon tile, square
    let tileCorner: CGFloat
    let tileEmoji: CGFloat      // emoji on the tile (emoji first)
    let tileSymbol: CGFloat     // status symbol on the tile (status first)
    let badge: CGFloat          // status badge (emoji first)
    let badgeSymbol: CGFloat
    let emojiBadge: CGFloat     // emoji badge (status first)
    let emojiBadgeFont: CGFloat
    let badgeOffset: CGFloat
    let title: CGFloat
    let age: CGFloat
    let folder: CGFloat
    let summary: CGFloat
    let summaryLines: Int
    let folderGap: CGFloat      // above the folder label
    let summaryGap: CGFloat     // above the summary
    let padding: CGFloat        // inside the card
    let spacing: CGFloat        // tile to text
    let corner: CGFloat
    let gap: CGFloat            // between cards in the panel

    static let normal = CardMetrics(
        tile: 34, tileCorner: 9, tileEmoji: 19, tileSymbol: 15,
        badge: 18, badgeSymbol: 9, emojiBadge: 20, emojiBadgeFont: 11, badgeOffset: 6,
        title: 15, age: 13, folder: 12, summary: 13, summaryLines: 2,
        folderGap: 4, summaryGap: 7, padding: 10, spacing: 10, corner: 14, gap: 8)

    static let cozy = CardMetrics(
        tile: 28, tileCorner: 8, tileEmoji: 16, tileSymbol: 12.5,
        badge: 15, badgeSymbol: 7.5, emojiBadge: 17, emojiBadgeFont: 9.5, badgeOffset: 5,
        title: 13.5, age: 12, folder: 11, summary: 12, summaryLines: 2,
        folderGap: 3, summaryGap: 5, padding: 8, spacing: 9, corner: 12, gap: 6)

    static let compact = CardMetrics(
        tile: cozy.tile, tileCorner: cozy.tileCorner, tileEmoji: cozy.tileEmoji, tileSymbol: cozy.tileSymbol,
        badge: cozy.badge, badgeSymbol: cozy.badgeSymbol, emojiBadge: cozy.emojiBadge,
        emojiBadgeFont: cozy.emojiBadgeFont, badgeOffset: cozy.badgeOffset,
        title: cozy.title, age: cozy.age, folder: cozy.folder, summary: cozy.summary, summaryLines: 1,
        folderGap: cozy.folderGap, summaryGap: 4, padding: 7, spacing: cozy.spacing, corner: cozy.corner, gap: 5)

    static func of(_ size: String) -> CardMetrics {
        size == "compact" ? compact : size == "cozy" ? cozy : normal
    }
}
