import SwiftUI

struct DockItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let page: AppModel.Page?
    let action: () -> Void
}

/// The control centre: a liquid dial. The Sinnfaden mark sits at the bottom centre;
/// a click pours the areas out as drops that stay joined while they travel, then part.
/// Drops lean toward the cursor, swell under it and merge with a small cursor drop.
struct NavigationDock: View {
    @Binding var open: Bool
    let current: AppModel.Page
    let items: [DockItem]
    var showHint = false
    @State private var changedAt = Date.distantPast
    @State private var hover: CGPoint?
    @State private var buttonHovered = false
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let radius: CGFloat = 215
    private let dropRadius: CGFloat = 28
    private var width: CGFloat { radius * 2 + 180 }
    private var height: CGFloat { radius + 200 }
    private var center: CGPoint { CGPoint(x: width / 2, y: height - 52) }

    var body: some View {
        ZStack(alignment: .bottom) {
            // The milk wave spreads from the mark over the whole window; the dial stays sharp above it.
            if animating || open {
                TimelineView(.animation(minimumInterval: nil, paused: !animating)) { timeline in
                    MilkWave(progress: waveProgress(now: animating ? timeline.date : settledDate), bottomInset: 12 + (height - center.y))
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { open = false }
                .allowsHitTesting(open)
                .accessibilityHidden(true)
            }
            Group {
                // Between motions the dial is drawn once at its settled state. A paused timeline
                // could freeze a half-finished close (sheet or page change) and leave drops behind.
                if animating || hover != nil {
                    TimelineView(.animation(minimumInterval: nil, paused: false)) { timeline in
                        dial(now: timeline.date)
                    }
                } else {
                    dial(now: settledDate)
                }
            }
            .frame(width: width, height: height)
            .padding(.bottom, 12)
            if showHint && !open {
                Text("Hier findest du alle Bereiche")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.sinnAnnotation, in: Capsule())
                    .shadow(color: Color.sinnAnnotation.opacity(0.35), radius: 12, y: 6)
                    .padding(.bottom, 132)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.3), value: showHint)
        .background {
            Button("") { open = false }.keyboardShortcut(.cancelAction).opacity(0).disabled(!open)
        }
        .onChange(of: open) { _, isOpen in
            AnnotationPresentation.setHoverSuspended(isOpen)
            if !isOpen { hover = nil }
            let started = Date()
            changedAt = started
            animating = true
            // Stop ticking once this motion is over, whichever way it went.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { if changedAt == started { animating = false } }
        }
    }

    /// Far enough in the future that every spring has come to rest.
    private var settledDate: Date { changedAt.addingTimeInterval(30) }

    private func waveProgress(now: Date) -> CGFloat {
        if reduceMotion { return open ? 1 : 0 }
        let elapsed = now.timeIntervalSince(changedAt)
        return open ? min(1, spring(elapsed, response: 0.85, damping: 1)) : max(0, 1 - spring(elapsed, response: 0.5, damping: 1))
    }

    // MARK: - Layout over time

    /// `anchor` is where the item is clicked; `point` is where it is drawn (pulled toward the cursor).
    private struct Drop { var anchor: CGPoint; var point: CGPoint; var progress: CGFloat; var magnet: CGFloat; var angle: Double }

    /// Damped spring from 0 to 1; `t` in seconds.
    private func spring(_ t: Double, response: Double, damping: Double) -> CGFloat {
        guard t > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        if damping >= 1 { return CGFloat(1 - exp(-omega * t) * (1 + omega * t)) }
        let decay = exp(-damping * omega * t)
        let frequency = omega * sqrt(1 - damping * damping)
        return CGFloat(1 - decay * (cos(frequency * t) + damping * omega / frequency * sin(frequency * t)))
    }

    private func drops(now: Date) -> [Drop] {
        let elapsed = now.timeIntervalSince(changedAt)
        let count = max(1, items.count - 1)
        return items.indices.map { index in
            // Upper arc only: the ends stay clear of the logo and of each other.
            let angle = Double.pi * (0.9 - 0.8 * Double(index) / Double(count))
            let target = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y - CGFloat(sin(angle)) * radius * 0.92)
            let progress: CGFloat
            if reduceMotion { progress = open ? 1 : 0 }
            else if open { progress = spring(elapsed - Double(index) * 0.035, response: 0.62, damping: 0.62) }
            else { progress = max(0, 1 - spring(elapsed - Double(items.count - 1 - index) * 0.018, response: 0.42, damping: 1)) }
            let anchor = CGPoint(x: center.x + (target.x - center.x) * progress, y: center.y + (target.y - center.y) * progress)
            var point = anchor
            var magnet: CGFloat = 0
            if let hover, open, !reduceMotion {
                let dx = hover.x - anchor.x, dy = hover.y - anchor.y
                magnet = CGFloat(exp(-Double(dx * dx + dy * dy) / (70 * 70)))
                point.x += dx * 0.16 * magnet; point.y += dy * 0.16 * magnet
            }
            return Drop(anchor: anchor, point: point, progress: progress, magnet: magnet, angle: angle)
        }
    }

    // MARK: - Drawing

    private func dial(now: Date) -> some View {
        let layout = drops(now: now)
        var blobs = [LiquidBlob(center: center, radius: 34 + (buttonHovered ? 3 : 0))]
        for drop in layout where drop.progress > 0.02 {
            blobs.append(LiquidBlob(center: drop.point, radius: dropRadius * (0.55 + 0.45 * min(1, drop.progress)) * (1 + 0.22 * drop.magnet)))
        }
        if let hover, open, !reduceMotion {
            blobs.append(LiquidBlob(center: hover, radius: 13))
        }
        let liquid = GooeyBlobs(blobs: blobs, softness: 11)
        return ZStack {
            // Liquid glass is decoration only: it must never take a click from the page beneath.
            // One liquid render per frame (gradients are composed first, then masked once).
            ZStack {
                LinearGradient(colors: [Color.white, Color(red: 0.9, green: 0.94, blue: 1)], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [Color.sinnAnnotation.opacity(0.18), .clear], startPoint: .bottom, endPoint: .center)
            }
            .mask(liquid)
            .drawingGroup()
            .shadow(color: Color.black.opacity(0.16), radius: 12, y: 7)
            .allowsHitTesting(false)
            if open {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { open = false }
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                itemView(item, drop: layout[index])
            }
            centerButton.position(center)
        }
        .frame(width: width, height: height)
        // Tracking sits on the whole dial, so it keeps reporting while the cursor is over a
        // drop. Only while open: a hover region is also a click target, and a closed dial
        // must never take clicks from the page beneath it.
        .modifier(DialHover(enabled: open && !reduceMotion) { phase in
            if case .active(let point) = phase { hover = point } else { hover = nil }
        })
    }

    private var centerButton: some View {
        Button { open.toggle() } label: {
            ZStack {
                Circle().fill(open ? Color.sinnInk : Color.clear).frame(width: 60, height: 60)
                SinnfadenMark(color: open ? .white : .sinnInk, weight: 1.15)
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(open && !reduceMotion ? 180 : 0))
                    .animation(.spring(response: 0.5, dampingFraction: 0.65), value: open)
            }
            .frame(width: 68, height: 68)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { buttonHovered = inside } }
        .keyboardShortcut("k", modifiers: .command)
        .help("Bereiche öffnen · ⌘K")
        .accessibilityLabel(open ? "Bereiche schließen" : "Bereiche öffnen")
    }

    private func itemView(_ item: DockItem, drop: Drop) -> some View {
        let selected = item.page == current
        let visible = drop.progress > 0.55
        // Labels sit outward: side items start at the icon edge, top items sit above it.
        let side = cos(drop.angle)
        let alignment: Alignment = side > 0.35 ? .leading : side < -0.35 ? .trailing : .center
        let outward = CGSize(width: side > 0.35 ? 34 : side < -0.35 ? -34 : 0,
                             height: abs(side) > 0.35 ? -CGFloat(sin(drop.angle)) * 12 : -42)
        let pull = CGSize(width: drop.point.x - drop.anchor.x, height: drop.point.y - drop.anchor.y)
        return Button {
            open = false
            item.action()
        } label: {
            ZStack {
                if selected { Circle().fill(Color.sinnInk).frame(width: 46, height: 46) }
                Image(systemName: item.symbol).font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : drop.magnet > 0.5 ? Color.sinnAnnotation : Color.sinnInk)
            }
            .frame(width: 56, height: 56)
            .overlay {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sinnInk)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .fixedSize()
                    .frame(width: 0, alignment: alignment)
                    .offset(outward)
                    .opacity(Double(min(1, max(0, (drop.progress - 0.7) / 0.3))))
                    .allowsHitTesting(false)
            }
            .scaleEffect(1 + 0.16 * drop.magnet)
            .offset(pull)
            // The click target never moves: it stays at the resting place of the drop.
            .frame(width: 64, height: 64)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .position(drop.anchor)
        .opacity(visible ? Double(min(1, (drop.progress - 0.55) / 0.3)) : 0)
        .allowsHitTesting(open && visible)
        .accessibilityHidden(!open)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Milk that rolls out from the Sinnfaden mark: a soft-edged disc grows over the window,
/// led by a bright crest, and draws back into the mark when the dial closes.
private struct MilkWave: View {
    let progress: CGFloat
    /// Distance from the window's bottom edge to the mark's centre.
    let bottomInset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let origin = CGPoint(x: geometry.size.width / 2, y: geometry.size.height - bottomInset)
            let reach = hypot(max(origin.x, geometry.size.width - origin.x), origin.y) * 1.12
            let radius = max(1, reach * progress)
            let crest = sin(.pi * min(1, progress)) // strongest while travelling, gone at rest
            ZStack {
                Color.white.opacity(0.74)
                    .mask {
                        RadialGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.82), .init(color: .clear, location: 1)],
                                       center: UnitPoint(x: origin.x / max(1, geometry.size.width), y: origin.y / max(1, geometry.size.height)),
                                       startRadius: 0, endRadius: radius)
                    }
                Circle()
                    .strokeBorder(Color.white, lineWidth: 26 + 30 * crest)
                    .frame(width: radius * 1.9, height: radius * 1.9)
                    .position(origin)
                    .blur(radius: 18)
                    .opacity(Double(0.85 * crest))
                Circle()
                    .strokeBorder(Color.sinnAnnotation.opacity(0.22), lineWidth: 2)
                    .frame(width: radius * 1.86, height: radius * 1.86)
                    .position(origin)
                    .blur(radius: 3)
                    .opacity(Double(crest))
            }
            .compositingGroup()
        }
    }
}

private struct DialHover: ViewModifier {
    let enabled: Bool
    let track: (HoverPhase) -> Void
    func body(content: Content) -> some View {
        if enabled { content.onContinuousHover(perform: track) } else { content }
    }
}
