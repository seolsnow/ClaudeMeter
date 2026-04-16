import SwiftUI
import AppKit

/// Menu bar label rendered as a custom NSImage (isTemplate=false) so colors show.
struct MenuBarLabel: View {
    let snapshot: UsageSnapshot
    let showSession: Bool
    let showWeekly: Bool

    var body: some View {
        Image(nsImage: renderImage())
    }

    private func renderImage() -> NSImage {
        let barWidth: CGFloat = 36
        let barHeight: CGFloat = 5
        let barRadius: CGFloat = 2
        let spacing: CGFloat = 3
        let textFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let labelFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
        let gapBetween: CGFloat = 8
        let height: CGFloat = 18

        struct Block {
            let label: String
            let percent: Double
            let labelWidth: CGFloat
            let textWidth: CGFloat
            let totalWidth: CGFloat
        }

        var blocks: [Block] = []

        if showSession {
            let label = "5h"
            let text = formatPercent(snapshot.sessionPercent)
            let lw = (label as NSString).size(withAttributes: [.font: labelFont]).width
            let tw = (text as NSString).size(withAttributes: [.font: textFont]).width
            blocks.append(Block(label: label, percent: snapshot.sessionPercent, labelWidth: lw, textWidth: tw, totalWidth: lw + spacing + barWidth + spacing + tw))
        }

        if showWeekly {
            let label = "7d"
            let text = formatPercent(snapshot.weeklyPercent)
            let lw = (label as NSString).size(withAttributes: [.font: labelFont]).width
            let tw = (text as NSString).size(withAttributes: [.font: textFont]).width
            blocks.append(Block(label: label, percent: snapshot.weeklyPercent, labelWidth: lw, textWidth: tw, totalWidth: lw + spacing + barWidth + spacing + tw))
        }

        if blocks.isEmpty {
            let fallback = NSImage(size: NSSize(width: 1, height: height), flipped: true) { _ in true }
            fallback.isTemplate = false
            return fallback
        }

        let totalWidth = blocks.map(\.totalWidth).reduce(0, +) + gapBetween * CGFloat(blocks.count - 1)

        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: true) { rect in
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let textColor = isDark ? NSColor.white : NSColor.black
            let bgColor = isDark ? NSColor.white.withAlphaComponent(0.2) : NSColor.black.withAlphaComponent(0.15)

            let centerY = rect.height / 2
            let barY = centerY - barHeight / 2

            var x: CGFloat = 0
            for (i, block) in blocks.enumerated() {
                if i > 0 { x += gapBetween }

                (block.label as NSString).draw(at: NSPoint(x: x, y: centerY - labelFont.pointSize / 2 - 1),
                                               withAttributes: [.font: labelFont, .foregroundColor: textColor.withAlphaComponent(0.6)])
                x += block.labelWidth + spacing

                self.drawBar(at: NSPoint(x: x, y: barY), width: barWidth, height: barHeight, radius: barRadius,
                        fill: block.percent, bgColor: bgColor, fillColor: self.colorFor(block.percent))
                x += barWidth + spacing

                let text = self.formatPercent(block.percent)
                (text as NSString).draw(at: NSPoint(x: x, y: centerY - textFont.pointSize / 2 - 1),
                                        withAttributes: [.font: textFont, .foregroundColor: textColor])
                x += block.textWidth
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private func drawBar(at origin: NSPoint, width: CGFloat, height: CGFloat, radius: CGFloat,
                          fill: Double, bgColor: NSColor, fillColor: NSColor) {
        let bgRect = NSRect(origin: origin, size: NSSize(width: width, height: height))
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
        bgColor.setFill()
        bgPath.fill()

        let fillWidth = max(0, width * CGFloat(min(1.0, fill)))
        if fillWidth > 0 {
            let fillRect = NSRect(origin: origin, size: NSSize(width: fillWidth, height: height))
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius)
            fillColor.setFill()
            fillPath.fill()
        }
    }

    private func colorFor(_ percent: Double) -> NSColor {
        switch percent {
        case ..<0.75: return NSColor.systemGreen
        case 0.75..<0.90: return NSColor.systemYellow
        default: return NSColor.systemRed
        }
    }

    private func formatPercent(_ p: Double) -> String {
        "\(Int((p * 100).rounded()))%"
    }
}
