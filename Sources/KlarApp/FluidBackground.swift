import AppKit
import MetalKit
import SwiftUI

/// Milky, slowly flowing light behind every screen. It leans toward the cursor and
/// brightens where you point. Reduced motion renders one still frame; reduced
/// transparency shows plain white.
struct FluidBackground: View {
    var energy: Double = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            Color.white
        } else {
            FluidMetalRepresentable(energy: energy).background(Color.white)
        }
    }
}

private struct FluidMetalRepresentable: NSViewRepresentable {
    let energy: Double
    func makeNSView(context: Context) -> FluidMetalView { FluidMetalView() }
    func updateNSView(_ view: FluidMetalView, context: Context) { view.targetEnergy = Float(energy) }
}

final class FluidMetalView: MTKView, MTKViewDelegate {
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private let start = CACurrentMediaTime()
    private var lastTime = CACurrentMediaTime()
    private var mouse = SIMD2<Float>(0.62, 0.4)
    private var mouseTarget = SIMD2<Float>(0.62, 0.4)
    private var mouseVelocity = SIMD2<Float>(0, 0)
    private var mouseEnergy: Float = 0
    private var energy: Float = 0
    var targetEnergy: Float = 0
    private var monitor: Any?

    private struct Uniforms {
        var resolution: SIMD2<Float>
        var mouse: SIMD2<Float>
        var velocity: SIMD2<Float>
        var time: Float
        var hover: Float
        var energy: Float
        var padding: Float = 0
    }

    init() {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        framebufferOnly = true
        preferredFramesPerSecond = 60
        autoResizeDrawable = false
        delegate = self
        setAccessibilityElement(false)
        if let device {
            queue = device.makeCommandQueue()
            pipeline = Self.makePipeline(device: device, format: colorPixelFormat)
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            isPaused = true
            enableSetNeedsDisplay = true
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.track(event)
            return event
        }
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Rendered at reduced resolution: the image is soft by design, the GPU stays cool.
    override func layout() {
        super.layout()
        drawableSize = CGSize(width: max(1, bounds.width * 0.6), height: max(1, bounds.height * 0.6))
        if isPaused { needsDisplay = true }
    }

    private func track(_ event: NSEvent) {
        guard event.window === window, bounds.width > 0, bounds.height > 0 else { return }
        let local = convert(event.locationInWindow, from: nil)
        mouseTarget = SIMD2(Float(local.x / bounds.width), Float(local.y / bounds.height))
        mouseEnergy = min(1, mouseEnergy + Float(hypot(event.deltaX, event.deltaY)) / 140)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline, let queue, let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let now = CACurrentMediaTime()
        let dt = Float(min(0.05, now - lastTime))
        lastTime = now
        // The light trails the cursor a little, like something liquid.
        let previous = mouse
        mouse += (mouseTarget - mouse) * min(1, dt * 5.5)
        mouseVelocity = (mouse - previous) / max(dt, 0.001)
        mouseEnergy *= exp(-dt * 1.6)
        energy += (targetEnergy - energy) * min(1, dt * 2.5)
        var uniforms = Uniforms(resolution: SIMD2(Float(drawableSize.width), Float(drawableSize.height)),
                                mouse: mouse, velocity: mouseVelocity, time: Float(now - start),
                                hover: mouseEnergy, energy: energy)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    private static func makePipeline(device: MTLDevice, format: MTLPixelFormat) -> MTLRenderPipelineState? {
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "fluidVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "fluidFragment")
        descriptor.colorAttachments[0].pixelFormat = format
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct Uniforms { float2 resolution; float2 mouse; float2 velocity; float time; float hover; float energy; float pad; };
    struct VOut { float4 position [[position]]; float2 uv; };

    vertex VOut fluidVertex(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        VOut o; o.position = float4(p * 2.0 - 1.0, 0.0, 1.0); o.uv = p; return o;
    }

    float hash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
    float noise(float2 p) {
        float2 i = floor(p), f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + float2(1, 0)), u.x), mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
    }
    float fbm(float2 p) {
        float v = 0.0, a = 0.5;
        for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + float2(17.0, 9.0); a *= 0.5; }
        return v;
    }

    fragment float4 fluidFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float aspect = u.resolution.x / max(u.resolution.y, 1.0);
        float2 uv = in.uv;
        float2 p = float2(uv.x * aspect, uv.y);
        float2 m = float2(u.mouse.x * aspect, u.mouse.y);
        float t = u.time;
        // The field is pulled toward the cursor and dragged along its motion.
        float d = length(p - m);
        float pull = exp(-d * d * 3.5);
        p += (m - p) * 0.12 * pull;
        p -= float2(u.velocity.x * aspect, u.velocity.y) * 0.035 * pull;
        float2 q = float2(fbm(p * 1.4 + float2(0.0, t * 0.035)), fbm(p * 1.4 + float2(5.2, -t * 0.03)));
        float n = fbm(p * 1.7 + q * 1.8 + float2(t * 0.02, t * 0.015));
        float n2 = fbm(p * 2.6 - q * 1.2 - float2(t * 0.025, 0.0));
        float3 milk = float3(0.982, 0.986, 0.996);
        float3 ice = float3(0.86, 0.915, 1.0);
        float3 blue = float3(0.70, 0.80, 0.98);
        float3 cyan = float3(0.80, 0.95, 1.0);
        float3 col = mix(milk, ice, smoothstep(0.35, 0.85, n) * 0.85);
        col = mix(col, blue, smoothstep(0.62, 0.95, n2) * (0.28 + 0.25 * u.energy));
        col = mix(col, cyan, smoothstep(0.55, 0.9, q.x * n) * 0.22);
        // Light gathers where you point and blooms a little more while you move.
        float glow = exp(-d * d * (5.5 - 2.0 * u.hover));
        col = mix(col, float3(0.94, 0.97, 1.0), glow * (0.35 + 0.35 * u.hover));
        col += float3(0.02, 0.035, 0.07) * glow * u.hover;
        // A calmer centre keeps text readable.
        float2 c = uv - 0.5;
        col = mix(col, milk, smoothstep(0.75, 0.15, length(c)) * 0.35);
        col += (hash(uv * u.resolution + t) - 0.5) / 255.0;
        return float4(col, 1.0);
    }
    """
}
