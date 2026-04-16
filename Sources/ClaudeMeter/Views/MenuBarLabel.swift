import SwiftUI
import AppKit

/// Menu bar label rendered as a custom NSImage (isTemplate=false) so colors show.
struct MenuBarLabel: View {
    let snapshot: UsageSnapshot

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

        let sText = formatPercent(snapshot.sessionPercent)
        let wText = formatPercent(snapshot.weeklyPercent)
        let sLabel = "5h"
        let wLabel = "7d"

        let sLabelWidth = (sLabel as NSString).size(withAttributes: [.font: labelFont]).width
        let wLabelWidth = (wLabel as NSString).size(withAttributes: [.font: labelFont]).width
        let sTextWidth = (sText as NSString).size(withAttributes: [.font: textFont]).width
        let wTextWidth = (wText as NSString).size(withAttributes: [.font: textFont]).width

        let sBlockWidth = sLabelWidth + spacing + barWidth + spacing + sTextWidth
        let wBlockWidth = wLabelWidth + spacing + barWidth + spacing + wTextWidth
        let gapBetween: CGFloat = 8
        let totalWidth = sBlockWidth + gapBetween + wBlockWidth
        let height: CGFloat = 18

        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: true) { rect in
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let textColor = isDark ? NSColor.white : NSColor.black
            let bgColor = isDark ? NSColor.white.withAlphaComponent(0.2) : NSColor.black.withAlphaComponent(0.15)

            let centerY = rect.height / 2
            let barY = centerY - barHeight / 2

            // Session block
            var x: CGFloat = 0
            (sLabel as NSString).draw(at: NSPoint(x: x, y: centerY - labelFont.pointSize / 2 - 1),
                                       withAttributes: [.font: labelFont, .foregroundColor: textColor.withAlphaComponent(0.6)])
            x += sLabelWidth + spacing

            drawBar(at: NSPoint(x: x, y: barY), width: barWidth, height: barHeight, radius: barRadius,
                    fill: snapshot.sessionPercent, bgColor: bgColor, fillColor: colorFor(snapshot.sessionPercent))
            x += barWidth + spacing

            (sText as NSString).draw(at: NSPoint(x: x, y: centerY - textFont.pointSize / 2 - 1),
                                      withAttributes: [.font: textFont, .foregroundColor: textColor])
            x += sTextWidth + gapBetween

            // Weekly block
            (wLabel as NSString).draw(at: NSPoint(x: x, y: centerY - labelFont.pointSize / 2 - 1),
                                       withAttributes: [.font: labelFont, .foregroundColor: textColor.withAlphaComponent(0.6)])
            x += wLabelWidth + spacing

            drawBar(at: NSPoint(x: x, y: barY), width: barWidth, height: barHeight, radius: barRadius,
                    fill: snapshot.weeklyPercent, bgColor: bgColor, fillColor: colorFor(snapshot.weeklyPercent))
            x += barWidth + spacing

            (wText as NSString).draw(at: NSPoint(x: x, y: centerY - textFont.pointSize / 2 - 1),
                                      withAttributes: [.font: textFont, .foregroundColor: textColor])
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
