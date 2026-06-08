import SwiftUI

enum ToastState {
    case processing
    case success(text: String, wordCount: Int)
    case error(String)
}

private let kTipHeight: CGFloat = 12
private let kTipWidth:  CGFloat = 20
private let kCorner:    CGFloat = 14

// Speech-bubble shape: rounded rect body with a upward-pointing triangle at the top.
// tipX is the horizontal position of the tip apex within the shape's coordinate space.
struct SpeechBubbleShape: Shape {
    var tipX: CGFloat

    func path(in rect: CGRect) -> Path {
        let bodyTop = rect.minY + kTipHeight
        let r       = kCorner

        // Clamp so the triangle base never overlaps a corner arc
        let cx = max(rect.minX + r + kTipWidth / 2,
                     min(tipX, rect.maxX - r - kTipWidth / 2))

        let apex  = CGPoint(x: cx,                    y: rect.minY)
        let baseL = CGPoint(x: cx - kTipWidth / 2,    y: bodyTop)
        let baseR = CGPoint(x: cx + kTipWidth / 2,    y: bodyTop)

        var p = Path()
        // Start at the exit of the top-left arc, proceed clockwise
        p.move(to: CGPoint(x: rect.minX + r, y: bodyTop))
        p.addLine(to: baseL)
        p.addLine(to: apex)
        p.addLine(to: baseR)
        p.addLine(to: CGPoint(x: rect.maxX - r, y: bodyTop))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: bodyTop + r),
                 radius: r, startAngle: .degrees(270), endAngle: .degrees(0),   clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(0),   endAngle: .degrees(90),  clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(90),  endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: bodyTop + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: bodyTop + r),
                 radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct ToastView: View {
    let state: ToastState
    var tipX: CGFloat = 150   // default: center of 300-wide view

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leadingIcon
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(headline)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    if case .success(_, let wc) = state {
                        Text("\(wc) \(wc == 1 ? "word" : "words")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }

                if case .success(let text, _) = state, !text.isEmpty {
                    Text(text.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .padding(.top, 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13 + kTipHeight)  // reserve space above for the caret
        .padding(.bottom, 13)
        .frame(width: 300, alignment: .leading)
        .background {
            SpeechBubbleShape(tipX: tipX)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.20), radius: 20, x: 0, y: 8)
                .shadow(color: .black.opacity(0.08), radius: 4,  x: 0, y: 2)
        }
        .overlay {
            SpeechBubbleShape(tipX: tipX)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch state {
        case .processing:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.secondary)

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)

        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
        }
    }

    private var headline: String {
        switch state {
        case .processing:       return "Scanning…"
        case .success:          return "Copied."
        case .error(let msg):   return msg
        }
    }
}
