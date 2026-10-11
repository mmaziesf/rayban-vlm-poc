// ⚠️ STRUCTURAL / UNVERIFIED: written on Linux against the DAT 1.0.1 .swiftinterface files; never compiled
// (MWDAT* are iOS-only binary xcframeworks). First compile happens on macOS (see ios/README.md / docs/IOS_OPTIONS.md).
import Foundation
import CoreMedia
import CoreVideo
import MWDATCore
import MWDATCamera
import MWDATSpeech
import GlanceCore

/// Mirrors Android GlassesRig: one DeviceSession → camera stream (raw, medium 504x896, 2 fps) into FrameRingBuffer,
/// speech transcription → GlanceController, display → DatHudRenderer.
final class GlassesRig: @unchecked Sendable {
    private let buffer: FrameRingBuffer
    private let clock: Clock
    private var session: DeviceSession?
    private var camera: Camera?
    private var speech: Speech?
    private var tokens: [any AnyListenerToken] = []
    private(set) var hud: DatHudRenderer?
    private let sampleEveryN: Int
    private var frameCount = 0

    /// DAT min stream fps is higher than 2 on some configs → we decimate (keep every Nth) like Android.
    init(buffer: FrameRingBuffer, clock: Clock = SystemClock(), sampleEveryN: Int = 1) {
        self.buffer = buffer; self.clock = clock; self.sampleEveryN = max(1, sampleEveryN)
    }

    func start(selector: any DeviceSelector,
               onTranscript: @escaping @Sendable (String, Bool, Float) -> Void) throws {
        let s = try Wearables.shared.createSession(deviceSelector: selector)
        try s.start()
        session = s

        // Camera: raw frames so we can read the luma plane (no decode needed).
        if let cam = try s.addCamera(config: StreamConfiguration(videoCodec: .raw, resolution: .medium, frameRate: 2)) {
            camera = cam
            tokens.append(cam.stream.videoFramePublisher.listen { [weak self] vf in self?.onVideoFrame(vf.sampleBuffer) })
            cam.stream.start()
        }
        // Speech: partial + final transcriptions.
        if let sp = try s.addSpeech() {
            speech = sp
            tokens.append(sp.transcriptionPublisher.listen { r in onTranscript(r.text, r.isFinal, r.confidence) })
            sp.start()
        }
        // Display (Ray-Ban Display only; other models throw → HUD falls back to phone UI only).
        if let d = try? s.addDisplay() { d.start(); hud = DatHudRenderer(display: d) }
    }

    private func onVideoFrame(_ sb: CMSampleBuffer) {
        frameCount += 1
        guard frameCount % sampleEveryN == 0, let px = CMSampleBufferGetImageBuffer(sb) else { return }
        guard let f = Self.lumaFrame(px, nowMs: clock.nowMs()) else { return }
        buffer.push(f)
    }

    /// Copy plane 0 (Y) of a bi-planar 420 pixel buffer; BGRA fallback is converted to approximate luma.
    static func lumaFrame(_ px: CVPixelBuffer, nowMs: Int64) -> Frame? {
        CVPixelBufferLockBaseAddress(px, .readOnly); defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        let w = CVPixelBufferGetWidth(px), h = CVPixelBufferGetHeight(px)
        var out = [UInt8](repeating: 0, count: w * h)
        if CVPixelBufferIsPlanar(px), let base = CVPixelBufferGetBaseAddressOfPlane(px, 0) {
            let stride = CVPixelBufferGetBytesPerRowOfPlane(px, 0)
            let p = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<h { for x in 0..<w { out[y * w + x] = p[y * stride + x] } }
        } else if let base = CVPixelBufferGetBaseAddress(px) {      // kCVPixelFormatType_32BGRA
            let stride = CVPixelBufferGetBytesPerRow(px); let p = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<h { for x in 0..<w {
                let o = y * stride + x * 4
                out[y * w + x] = UInt8((29 * Int(p[o]) + 150 * Int(p[o + 1]) + 77 * Int(p[o + 2])) >> 8)
            } }
        } else { return nil }
        let sharp = Sharpness.lumaLaplacianVariance(out, width: w, height: h)
        // NOTE: luma-only frame is enough for buffer/sharpness; the VLM adapter needs RGB → keep the CVPixelBuffer
        // or a JPEG too once a real engine lands (TODO M7.3).
        return Frame(bytes: out, width: w, height: h, format: .yuv420, captureTimeMs: nowMs, origin: .streamBuffer, sharpness: sharp)
    }

    /// On-demand fallback (DAT stream.capturePhoto(format: .jpeg) → photoDataPublisher). Async in DAT; core wants sync → semaphore with timeout.
    func makeCapture(timeoutMs: Int = 3000) -> OnDemandCapture {
        ClosureCapture { [weak self] in
            guard let cam = self?.camera else { return nil }
            let sem = DispatchSemaphore(value: 0); var result: Frame?
            let t = cam.stream.photoDataPublisher.listen { pd in
                result = Frame(bytes: [UInt8](pd.data), width: 0, height: 0, format: .jpeg,
                               captureTimeMs: SystemClock().nowMs(), origin: .photoCapture)
                sem.signal()
            }
            _ = cam.stream.capturePhoto(format: .jpeg)
            _ = sem.wait(timeout: .now() + .milliseconds(timeoutMs)); _ = t
            return result
        }
    }

    func stop() { speech?.stop(); camera?.stop(); hud?.stop(); session?.stop(); tokens.removeAll(); session = nil }
}
