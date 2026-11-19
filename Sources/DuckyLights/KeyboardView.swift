import DuckyKit
import SwiftUI

/// Draws the TKL layout with the live preview colors. Click (or drag) to paint keys.
struct KeyboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width / model.layout.width, geo.size.height / model.layout.height)
            ZStack(alignment: .topLeading) {
                ForEach(model.layout.keys) { key in
                    let c = model.preview[key.ledIndex] ?? .black
                    KeyCap(label: key.label, color: c)
                        .frame(width: key.width * unit - 4, height: unit - 4)
                        .offset(x: key.x * unit + 2, y: key.y * unit + 2)
                        .onTapGesture { model.paint(key) }
                }
            }
            .frame(width: model.layout.width * unit, height: model.layout.height * unit, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4).onChanged { v in
                if let key = keyAt(v.location, unit: unit) { model.paint(key) }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(model.layout.width / model.layout.height, contentMode: .fit)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.08)))
    }

    private func keyAt(_ p: CGPoint, unit: Double) -> KeyInfo? {
        model.layout.keys.first { k in
            p.x >= k.x * unit && p.x < (k.x + k.width) * unit && p.y >= k.y * unit && p.y < (k.y + 1) * unit
        }
    }
}

private struct KeyCap: View {
    let label: String
    let color: RGB

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.16))
            RoundedRectangle(cornerRadius: 6).fill(color.color.opacity(0.85))
                .blur(radius: 2)
                .padding(2)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(radius: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 2)
        }
    }
}
