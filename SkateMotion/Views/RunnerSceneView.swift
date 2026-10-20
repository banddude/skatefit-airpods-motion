import SwiftUI

/// Original vector artwork rendered on-device. No third-party art, fonts,
/// models, images, or music are needed for the game's playfield.
struct RunnerSceneView: View {
    let engine: RunnerEngine
    let deckColor: Color
    let reduceMotion: Bool
    let highContrast: Bool
    /// Only populated by live calibrated AirPod motion. Mirrors the real
    /// nose/tail tilt on the game's own board, not just the diagnostics view.
    var livePitchDegrees: Double? = nil

    private var theme: (Color, Color, Color) {
        switch engine.course.worldNumber {
        case 2: return (Color(red: 0.14, green: 0.12, blue: 0.27),
                        Color(red: 0.37, green: 0.19, blue: 0.39), .orange)
        case 3: return (Color(red: 0.04, green: 0.06, blue: 0.24),
                        Color(red: 0.23, green: 0.09, blue: 0.42), .cyan)
        case 4: return (Color(red: 0.03, green: 0.18, blue: 0.31),
                        Color(red: 0.13, green: 0.32, blue: 0.44), .mint)
        case 5: return (Color(red: 0.13, green: 0.02, blue: 0.22),
                        Color(red: 0.32, green: 0.06, blue: 0.33), .pink)
        default: return (Color(red: 0.06, green: 0.09, blue: 0.24),
                         Color(red: 0.22, green: 0.17, blue: 0.38), .mint)
        }
    }

    var body: some View {
        Canvas(opaque: true) { context, size in
            draw(&context, size: size)
        }
        .aspectRatio(1.20, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.2)))
        .accessibilityLabel(
            "Runner stage. \(Int(engine.progress * 100)) percent finished. " +
            "\(engine.lives) lives. \(engine.pickups) collectibles. \(engine.message)"
        )
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        guard w > 0 && h > 0 else { return }
        let ground = h * 0.76
        let (top, bottom, highlight) = theme
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: highContrast ? .color(.black) :
                     .linearGradient(Gradient(colors: [top, bottom]),
                                     startPoint: .zero,
                                     endPoint: CGPoint(x: 0, y: h)))

        // Moon and a fixed constellation use only deterministic geometry.
        circle(&context, x: w * 0.79, y: h * 0.19, radius: h * 0.105,
               color: highlight.opacity(0.10))
        circle(&context, x: w * 0.79, y: h * 0.19, radius: h * 0.054,
               color: .white.opacity(0.92))
        for star in 0..<38 {
            let x = CGFloat((star * 97 + 23) % 401) / 401 * w
            let y = CGFloat((star * 41 + 7) % 89) / 130 * h
            circle(&context, x: x, y: y, radius: star.isMultiple(of: 6) ? 1.7 : 0.8,
                   color: .white.opacity(star.isMultiple(of: 4) ? 0.8 : 0.28))
        }

        // Three parallax layers. Reduce Motion disables background scrolling.
        for layer in 0..<3 {
            let width: CGFloat = layer == 0 ? 52 : layer == 1 ? 39 : 31
            let fraction: Double = layer == 0 ? 0.10 : layer == 1 ? 0.20 : 0.36
            let offset = CGFloat((reduceMotion ? 0 : engine.distance * fraction * 7)
                .truncatingRemainder(dividingBy: Double(width)))
            let color = Color(red: 0.05 + Double(layer) * 0.017,
                              green: 0.07 + Double(layer) * 0.017,
                              blue: 0.17 + Double(layer) * 0.016)
            for index in -1..<Int(w / width) + 3 {
                let x = CGFloat(index) * width - offset
                let buildingHeight = h * (0.20 + CGFloat((index * 17 + layer * 13 + 900)
                    % 11) * 0.018)
                rectangle(&context,
                          CGRect(x: x, y: ground - buildingHeight,
                                 width: width - 3, height: buildingHeight),
                          color: color)
                if layer == 2 {
                    for row in 0..<3 {
                        for column in 0..<3 where (row + column + index + 100) % 3 != 0 {
                            rectangle(&context, CGRect(x: x + 7 + CGFloat(column) * 9,
                                y: ground - buildingHeight + 10 + CGFloat(row) * 17,
                                width: 3, height: 6), color: highlight.opacity(0.40))
                        }
                    }
                }
            }
        }

        // Skateable surface, street lights, and motion streaks.
        rectangle(&context, CGRect(x: 0, y: ground, width: w,
                                   height: h - ground), color: highContrast ? .black : Color(red: 0.065,
                                    green: 0.083, blue: 0.14))
        rectangle(&context, CGRect(x: 0, y: ground, width: w, height: 4),
                  color: highContrast ? .white : highlight.opacity(0.8))
        let laneOffset = CGFloat((engine.distance * 10).truncatingRemainder(dividingBy: 70))
        for index in -1..<Int(w / 70) + 2 {
            rectangle(&context, CGRect(x: CGFloat(index) * 70 - laneOffset,
                y: ground + h * 0.18, width: 25, height: 3),
                color: .white.opacity(0.25))
        }
        let scale = w / 16.0
        let playerX = w * 0.235
        for feature in engine.features {
            let x = playerX + CGFloat(feature.at - engine.distance) * scale
            let itemWidth = max(6, CGFloat(feature.length) * scale)
            if x > w + 50 || x + itemWidth < -50 { continue }
            switch feature.kind {
            case .gap, .longGap:
                rectangle(&context, CGRect(x: x, y: ground - 2,
                    width: itemWidth, height: h - ground + 3), color: .black)
                if feature.kind == .longGap {
                    rectangle(&context, CGRect(x: x, y: ground + 7,
                        width: itemWidth, height: 3), color: .pink.opacity(0.60))
                }
                rectangle(&context, CGRect(x: x - 2, y: ground - 12,
                    width: 3, height: 12), color: .orange)
                rectangle(&context, CGRect(x: x + itemWidth - 1, y: ground - 12,
                    width: 3, height: 12), color: .orange)
            case .barrier:
                let rect = CGRect(x: x, y: ground - 34, width: itemWidth, height: 34)
                rectangle(&context, rect, color: highContrast ? .yellow : Color(red: 0.96, green: 0.34, blue: 0.29))
                for stripe in 0..<3 {
                    rectangle(&context, CGRect(x: x + 3, y: ground - 29 + CGFloat(stripe) * 10,
                        width: max(1, itemWidth - 6), height: 3), color: .white.opacity(0.55))
                }
            case .overhead, .pulseGate:
                let active = feature.kind == .overhead || engine.pulseGateActive(feature)
                let gateColor: Color = active ? (highContrast ? .white : .purple) :
                    .cyan.opacity(0.32)
                rectangle(&context, CGRect(x: x, y: ground - 67,
                    width: itemWidth, height: 13), color: gateColor)
                rectangle(&context, CGRect(x: x, y: ground - 67,
                    width: itemWidth, height: 3), color: active ? .pink : .mint)
                rectangle(&context, CGRect(x: x + itemWidth - 4, y: ground - 55,
                    width: 4, height: 55), color: gateColor.opacity(0.7))
                if feature.kind == .pulseGate {
                    circle(&context, x: x + itemWidth / 2, y: ground - 80,
                           radius: 6, color: active ? .red : .green)
                }
            case .springPad:
                rectangle(&context, CGRect(x: x, y: ground - 7,
                    width: itemWidth, height: 8), color: highContrast ? .white : .green)
                for chevron in 0..<3 {
                    let centerX = x + CGFloat(chevron) * itemWidth / 3
                    let path = Path { path in
                        path.move(to: CGPoint(x: centerX + 3, y: ground - 20))
                        path.addLine(to: CGPoint(x: centerX + 11, y: ground - 29))
                        path.addLine(to: CGPoint(x: centerX + 18, y: ground - 20))
                    }
                    context.stroke(path, with: .color(.white),
                                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            case .manualLine, .noseLine:
                let lineColor: Color = feature.kind == .manualLine ? .yellow : .cyan
                rectangle(&context, CGRect(x: x, y: ground - 5,
                    width: itemWidth, height: 6), color: lineColor.opacity(0.85))
                for dash in 0..<Int(itemWidth / 15) {
                    rectangle(&context, CGRect(x: x + CGFloat(dash) * 15,
                        y: ground - 12, width: 7, height: 3), color: lineColor)
                }
            case .pickup:
                if !feature.resolved {
                    let float: CGFloat = reduceMotion ? 0 :
                        CGFloat(sin(engine.elapsed * 4 + feature.at)) * 5
                    let cy = ground - 43 + float
                    let diamond = Path { path in
                        path.move(to: CGPoint(x: x + 7, y: cy - 10))
                        path.addLine(to: CGPoint(x: x + 16, y: cy))
                        path.addLine(to: CGPoint(x: x + 7, y: cy + 10))
                        path.addLine(to: CGPoint(x: x - 2, y: cy))
                        path.closeSubpath()
                    }
                    context.fill(diamond, with: .color(.yellow))
                    context.stroke(diamond, with: .color(.white.opacity(0.9)),
                                   lineWidth: 1.5)
                }
            case .checkpoint:
                rectangle(&context, CGRect(x: x, y: ground - 126,
                    width: 3, height: 126), color: .white.opacity(0.8))
                rectangle(&context, CGRect(x: x + 3, y: ground - 126,
                    width: 35, height: 18), color: highlight)
            }
        }

        // Longboard-like hero with an animated rider silhouette.
        let heroY = ground - 10 - CGFloat(min(engine.height, 2.8)) * 41
        if engine.invulnerabilityTime == 0 ||
           Int(engine.elapsed * 12).isMultiple(of: 2) {
            let deckY = heroY + (engine.crouching ? 6 : 0)
            let tilt: CGFloat = {
                if let pitch = livePitchDegrees, pitch.isFinite {
                    return -CGFloat(max(-32, min(32, pitch))) * 0.65
                }
                return engine.manualing ? -7 : engine.crouching ? 5 : 0
            }()
            let deckPath = Path { path in
                path.move(to: CGPoint(x: playerX - 21, y: deckY + 6))
                path.addLine(to: CGPoint(x: playerX + 30, y: deckY + 6 + tilt))
                path.addLine(to: CGPoint(x: playerX + 30, y: deckY + tilt))
                path.addLine(to: CGPoint(x: playerX - 21, y: deckY))
                path.closeSubpath()
            }
            context.fill(deckPath, with: .color(deckColor))
            context.stroke(deckPath, with: .color(.white.opacity(0.5)), lineWidth: 1)
            circle(&context, x: playerX - 11, y: deckY + 9,
                   radius: 5.2, color: .white)
            circle(&context, x: playerX + 19, y: deckY + 9,
                   radius: 5.2, color: .white)
            circle(&context, x: playerX - 11, y: deckY + 9,
                   radius: 2, color: .black)
            circle(&context, x: playerX + 19, y: deckY + 9,
                   radius: 2, color: .black)
            let bodyTop = deckY - (engine.crouching ? 23 : 47)
            circle(&context, x: playerX + 2, y: bodyTop - 8,
                   radius: 9, color: .white)
            rectangle(&context, CGRect(x: playerX - 6, y: bodyTop,
                width: 17, height: engine.crouching ? 12 : 24), color: highlight)
            // Express the crouch through bent knees, rather than flipping the deck.
            let legY = bodyTop + (engine.crouching ? 12 : 24)
            let knees = Path { path in
                path.move(to: CGPoint(x: playerX - 2, y: legY))
                path.addLine(to: CGPoint(x: playerX - 9, y: deckY - 7))
                path.move(to: CGPoint(x: playerX + 9, y: legY))
                path.addLine(to: CGPoint(x: playerX + 17, y: deckY - 7))
            }
            context.stroke(knees, with: .color(.white), style: StrokeStyle(
                lineWidth: 4, lineCap: .round))
            if engine.flowMultiplier > 1 && !reduceMotion {
                for spark in 0..<5 {
                    circle(&context, x: playerX - 28 - CGFloat(spark) * 12,
                           y: heroY + CGFloat(spark % 3) * 7,
                           radius: 2, color: .yellow.opacity(0.8 - Double(spark) * 0.1))
                }
            }
            if engine.height > 0.1 {
                for spark in 0..<3 {
                    circle(&context, x: playerX - 26 - CGFloat(spark) * 10,
                           y: heroY + CGFloat(spark) * 5,
                           radius: CGFloat(3 - spark) / 1.8,
                           color: highlight.opacity(0.6))
                }
            }
        }

        // Stage progress always reads from the authoritative simulation.
        rectangle(&context, CGRect(x: 12, y: 13, width: w - 24,
                                   height: 4), color: .white.opacity(0.22))
        rectangle(&context, CGRect(x: 12, y: 13, width: (w - 24) *
                                   CGFloat(engine.progress), height: 4),
                  color: highlight)
    }

    private func rectangle(_ context: inout GraphicsContext, _ rect: CGRect,
                           color: Color) {
        context.fill(Path(rect), with: .color(color))
    }

    private func circle(_ context: inout GraphicsContext, x: CGFloat, y: CGFloat,
                        radius: CGFloat, color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                           width: radius * 2, height: radius * 2)),
                     with: .color(color))
    }
}
