// DEBUG-only fallback for CI when the DAT mock link can't connect on the Simulator (docs/IOS_OPTIONS.md).
// No DAT session: pushes synthetic 504x896 luma frames at 2 fps into the real FrameRingBuffer, so the real
// GlanceController / IntentRouter / BufferedFrameSource / HUD run end to end. Launch arg: --fake-glasses.
#if DEBUG
import Foundation
import GlanceCore

final class FakeRig: @unchecked Sendable {
    private var timer: DispatchSourceTimer?
    private var n = 0
    let width = 504, height = 896

    func start(buffer: FrameRingBuffer, fps: Int = 2) {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "glance.fakerig"))
        t.schedule(deadline: .now(), repeating: .milliseconds(1000 / max(fps, 1)))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            n += 1
            var luma = [UInt8](repeating: 0, count: width * height)
            // Moving checkerboard → non-zero sharpness, changes every frame.
            for y in 0..<height { for x in 0..<width { luma[y * width + x] = ((x / 24 + y / 24 + n) % 2 == 0) ? 40 : 210 } }
            let sharp = Sharpness.lumaLaplacianVariance(luma, width: width, height: height)
            buffer.push(Frame(bytes: luma, width: width, height: height, format: .yuv420,
                              captureTimeMs: SystemClock().nowMs(), origin: .testAsset, sharpness: sharp))
        }
        t.resume(); timer = t
    }
    func stop() { timer?.cancel(); timer = nil }
}
#endif
