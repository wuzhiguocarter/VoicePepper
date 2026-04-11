import SwiftUI

// MARK: - Audio Level Waveform View (Task 6.5)
// Animated bar waveform showing current audio level using Canvas API.

struct AudioLevelView: View {
    let level: Float  // 0.0 - 1.0

    private let barCount = 12
    private let barSpacing: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            let barWidth = (size.width - CGFloat(barCount - 1) * barSpacing) / CGFloat(barCount)

            for i in 0..<barCount {
                // Each bar gets a slightly different height based on level + noise
                let normalizedIndex = Float(i) / Float(barCount - 1)
                let barLevel = level * (0.6 + 0.4 * sin(normalizedIndex * .pi))
                let barHeight = max(2, CGFloat(barLevel) * size.height)

                let x = CGFloat(i) * (barWidth + barSpacing)
                let y = (size.height - barHeight) / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                context.fill(
                    path,
                    with: .color(level > 0.01 ? .red.opacity(0.7) : .gray.opacity(0.3))
                )
            }
        }
        .animation(.easeOut(duration: 0.1), value: level)
    }
}

