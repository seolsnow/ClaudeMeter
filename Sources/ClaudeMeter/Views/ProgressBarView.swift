import SwiftUI

struct ProgressBarView: View {
    let percent: Double  // 0.0 – 1.0
    var width: CGFloat = 40
    var height: CGFloat = 10

    private var fillColor: Color {
        switch percent {
        case ..<0.75: return .green
        case 0.75..<0.90: return .yellow
        default: return .red
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.25))
                .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 2)
                .fill(fillColor)
                .frame(width: max(0, width * CGFloat(min(1.0, percent))), height: height)
        }
        .frame(width: width, height: height)
    }
}
