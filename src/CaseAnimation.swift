import AppKit
import SwiftUI

/// Plays 31 pre-rendered hinge angles for each earbud count.
/// Bluetooth state drives the target pose; intermediate frames can play either way.
struct CaseAnimation: View {
    let isOpen: Bool
    let earbuds: Int
    let active: Bool

    var body: some View {
        ZStack {
            Ellipse()
                .fill(active ? Color.accentColor.opacity(0.16) : Color.black.opacity(0.07))
                .frame(width: 145, height: 13)
                .blur(radius: 9)
                .offset(y: 62)
            CaseRenderView(isOpen: isOpen, earbuds: earbuds)
                .frame(width: 220, height: 176)
            if active {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .offset(x: 111, y: 16)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CaseRenderView: NSViewRepresentable {
    let isOpen: Bool
    let earbuds: Int

    func makeNSView(context: Context) -> CaseFrameView { CaseFrameView() }

    func updateNSView(_ view: CaseFrameView, context: Context) {
        view.set(open: isOpen, earbuds: earbuds)
    }
}

private final class CaseFrameView: NSView {
    private static let frameCount = 31
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        cache.countLimit = 40
        return cache
    }()
    private static let resourceBundle: Bundle = {
        // A packaged app keeps the SwiftPM bundle under Contents/Resources.
        if let url = Bundle.main.url(forResource: "AirSkip_MenuBarApp", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()

    private var progress: Double = 0
    private var target: Double = 0
    private var startProgress: Double = 0
    private var startTime: TimeInterval = 0
    private var duration: TimeInterval = 0.45
    private var earbuds = 2
    private var timer: Timer?

    override var isOpaque: Bool { false }

    deinit { timer?.invalidate() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            timer?.invalidate()
            timer = nil
            progress = target
        } else if progress != target {
            startTimer()
        }
    }

    func set(open: Bool, earbuds: Int) {
        let count = min(2, max(0, earbuds))
        if self.earbuds != count {
            self.earbuds = count
            needsDisplay = true
        }
        let next: Double = open ? 1 : 0
        guard next != target else { return }
        // Sample the current pose before reversing, avoiding a jump to an endpoint.
        advance()
        target = next
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || window == nil {
            progress = target
            timer?.invalidate()
            timer = nil
            needsDisplay = true
            return
        }
        startProgress = progress
        startTime = ProcessInfo.processInfo.systemUptime
        duration = max(0.16, 0.45 * abs(target - progress))
        startTimer()
    }

    private func startTimer() {
        guard timer == nil else { return }
        let next = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.advance() }
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    private func advance() {
        guard timer != nil else { return }
        let t = min(1, max(0, (ProcessInfo.processInfo.systemUptime - startTime) / duration))
        let eased = t * t * (3 - 2 * t)
        progress = startProgress + (target - startProgress) * eased
        needsDisplay = true
        if t >= 1 {
            progress = target
            timer?.invalidate()
            timer = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let frame = min(Self.frameCount - 1, max(0, Int((progress * Double(Self.frameCount - 1)).rounded())))
        let name = String(format: "case-%d-%02d", earbuds, frame)
        let key = name as NSString
        let image: NSImage
        if let cached = Self.cache.object(forKey: key) {
            image = cached
        } else if let url = Self.resourceBundle.url(forResource: name, withExtension: "png", subdirectory: "animation"),
                  let loaded = NSImage(contentsOf: url) {
            Self.cache.setObject(loaded, forKey: key, cost: 640 * 512 * 4)
            image = loaded
        } else {
            return
        }
        NSGraphicsContext.current?.imageInterpolation = .high
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                          width: size.width, height: size.height)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true, hints: nil)
    }
}
