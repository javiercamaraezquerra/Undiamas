package com.celsoriaapps.undiamas

import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Pure policy/geometry shared by Android preparation and host JVM checks. */
internal object PhotoImportPolicy {
    const val MAX_SOURCE_BYTES = 128L * 1024L * 1024L
    const val MAX_SOURCE_PIXELS = 128_000_000L
    const val MAX_SOURCE_SIDE = 20_000
    const val MAX_DECODE_SIDE = 3_200
    const val MAX_DECODE_PIXELS = MAX_DECODE_SIDE.toLong() * MAX_DECODE_SIDE
    const val MAX_OUTPUT_SIDE = 1_600
    const val TARGET_OUTPUT_BYTES = 700 * 1024
    const val MAX_OUTPUT_BYTES = 2 * 1024 * 1024
    val JPEG_QUALITIES = intArrayOf(85, 75, 65, 55)

    fun validateBytes(byteCount: Long) {
        if (byteCount <= 0) throw PhotoImportFailure("photo_unreadable")
        if (byteCount > MAX_SOURCE_BYTES) throw PhotoImportFailure("photo_too_large")
    }

    fun validateDimensions(width: Int, height: Int) {
        if (width <= 0 || height <= 0) throw PhotoImportFailure("photo_unsupported")
        if (width > MAX_SOURCE_SIDE || height > MAX_SOURCE_SIDE ||
            width.toLong() * height.toLong() > MAX_SOURCE_PIXELS
        ) {
            throw PhotoImportFailure("photo_too_large")
        }
    }

    /** Power-of-two sampling bounds both bitmap dimensions before allocation. */
    fun sampleSize(width: Int, height: Int): Int {
        validateDimensions(width, height)
        var sample = 1
        while (ceilDivide(width, sample) > MAX_DECODE_SIDE ||
            ceilDivide(height, sample) > MAX_DECODE_SIDE
        ) {
            sample *= 2
        }
        return sample
    }

    fun validateDecoded(width: Int, height: Int, byteCount: Long) {
        if (width <= 0 || height <= 0) throw PhotoImportFailure("photo_unreadable")
        if (width > MAX_DECODE_SIDE || height > MAX_DECODE_SIDE ||
            width.toLong() * height.toLong() > MAX_DECODE_PIXELS ||
            byteCount > MAX_DECODE_PIXELS * 4L
        ) {
            throw PhotoImportFailure("photo_too_large")
        }
    }

    /**
     * Source-pixel edges -> oriented, scaled destination-pixel edges.
     * A single Canvas draw avoids a second full-size rotated bitmap.
     * EXIF orientation values are the standard 1..8 values, independent of Android.
     */
    fun outputTransform(width: Int, height: Int, orientation: Int): PhotoOutputTransform {
        validateDecoded(width, height, width.toLong() * height.toLong() * 4L)
        val w = width.toFloat()
        val h = height.toFloat()
        val coefficients = when (orientation) {
            2 -> floatArrayOf(-1f, 0f, w, 0f, 1f, 0f)
            3 -> floatArrayOf(-1f, 0f, w, 0f, -1f, h)
            4 -> floatArrayOf(1f, 0f, 0f, 0f, -1f, h)
            5 -> floatArrayOf(0f, 1f, 0f, 1f, 0f, 0f)
            6 -> floatArrayOf(0f, -1f, h, 1f, 0f, 0f)
            7 -> floatArrayOf(0f, -1f, h, -1f, 0f, w)
            8 -> floatArrayOf(0f, 1f, 0f, -1f, 0f, w)
            else -> floatArrayOf(1f, 0f, 0f, 0f, 1f, 0f)
        }
        val swap = orientation in 5..8
        val orientedWidth = if (swap) height else width
        val orientedHeight = if (swap) width else height
        val ratio = min(1.0, MAX_OUTPUT_SIDE.toDouble() / max(orientedWidth, orientedHeight))
        val outputWidth = max(1, (orientedWidth * ratio).roundToInt())
        val outputHeight = max(1, (orientedHeight * ratio).roundToInt())
        val scaleX = outputWidth.toFloat() / orientedWidth
        val scaleY = outputHeight.toFloat() / orientedHeight
        return PhotoOutputTransform(
            outputWidth,
            outputHeight,
            floatArrayOf(
                coefficients[0] * scaleX, coefficients[1] * scaleX, coefficients[2] * scaleX,
                coefficients[3] * scaleY, coefficients[4] * scaleY, coefficients[5] * scaleY,
                0f, 0f, 1f,
            ),
        )
    }

    /**
     * A fresh sRGB Bitmap normally emits no EXIF. Remove optional APP/COM
     * segments too, so a platform encoder cannot carry a profile/comment into
     * the normalized format accepted by the encrypted photo store.
     * This only parses JPEG bytes produced by Bitmap.compress, never source files.
     */
    fun stripOutputMetadata(jpeg: ByteArray): ByteArray {
        if (jpeg.size < 4 || unsigned(jpeg[0]) != 0xff || unsigned(jpeg[1]) != 0xd8 ||
            unsigned(jpeg[jpeg.lastIndex - 1]) != 0xff || unsigned(jpeg.last()) != 0xd9
        ) {
            throw PhotoImportFailure("photo_prepare_failed")
        }
        val output = ByteArrayOutputStream(jpeg.size)
        output.write(jpeg, 0, 2)
        var position = 2
        while (position + 3 < jpeg.size) {
            val markerStart = position
            if (unsigned(jpeg[position++]) != 0xff) throw PhotoImportFailure("photo_prepare_failed")
            while (position < jpeg.size && unsigned(jpeg[position]) == 0xff) position++
            if (position >= jpeg.size) throw PhotoImportFailure("photo_prepare_failed")
            val marker = unsigned(jpeg[position++])
            if (marker == 0xda) {
                output.write(jpeg, markerStart, jpeg.size - markerStart)
                return output.toByteArray()
            }
            if (marker == 0xd9 || marker == 0x00 || marker == 0xd8 ||
                marker == 0x01 || marker in 0xd0..0xd7 || position + 2 > jpeg.size
            ) {
                throw PhotoImportFailure("photo_prepare_failed")
            }
            val length = unsigned(jpeg[position]) * 256 + unsigned(jpeg[position + 1])
            if (length < 2 || length > jpeg.size - position) {
                throw PhotoImportFailure("photo_prepare_failed")
            }
            if (marker !in 0xe1..0xef && marker != 0xfe) {
                output.write(jpeg, markerStart, position + length - markerStart)
            }
            position += length
        }
        throw PhotoImportFailure("photo_prepare_failed")
    }

    private fun ceilDivide(value: Int, divisor: Int) = (value + divisor - 1) / divisor
    private fun unsigned(value: Byte) = value.toInt() and 0xff
}

internal data class PhotoOutputTransform(
    val width: Int,
    val height: Int,
    val matrixValues: FloatArray,
)

internal class PhotoImportFailure(val code: String) : Exception(code)
