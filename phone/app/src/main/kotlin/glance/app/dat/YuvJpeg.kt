package glance.app.dat

import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import java.io.ByteArrayOutputStream

/**
 * Converts a buffered YUV420 frame to JPEG only when the VLM needs it (not per frame).
 * VERIFY: DAT says VideoFrame.buffer is "decoded YUV" but does not document the plane layout.
 * Log the buffer size and inspect one frame: I420 (Y,U,V planar) vs NV12/NV21 (Y + interleaved UV).
 * This assumes I420 and repacks to NV21 for YuvImage.
 */
object YuvJpeg {
    fun i420ToJpeg(i420: ByteArray, w: Int, h: Int, quality: Int = 85, maxSide: Int = 896): ByteArray {
        val ySize = w * h; val q = ySize / 4
        val nv21 = ByteArray(ySize + 2 * q)
        System.arraycopy(i420, 0, nv21, 0, ySize)
        var o = ySize
        for (i in 0 until q) { nv21[o++] = i420[ySize + q + i]; nv21[o++] = i420[ySize + i] } // V,U interleave
        val out = ByteArrayOutputStream(ySize / 8)
        YuvImage(nv21, ImageFormat.NV21, w, h, null).compressToJpeg(Rect(0, 0, w, h), quality, out)
        return out.toByteArray() // maxSide: resizing is left to the VLM visual-token budget for now.
    }
}
