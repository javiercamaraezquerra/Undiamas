package com.celsoriaapps.undiamas

import kotlin.math.abs
import kotlin.math.max

/** Host-JVM tests: limits, sampling, transforms and JPEG metadata only. */
fun main() {
    var passed = 0
    fun test(name: String, run: () -> Unit) {
        run()
        passed++
        println("PASS $name")
    }

    test("byte limits reject empty/oversized input without integer overflow") {
        PhotoImportPolicy.validateBytes(1)
        PhotoImportPolicy.validateBytes(PhotoImportPolicy.MAX_SOURCE_BYTES)
        expectCode("photo_unreadable") { PhotoImportPolicy.validateBytes(0) }
        expectCode("photo_unreadable") { PhotoImportPolicy.validateBytes(-1) }
        expectCode("photo_too_large") { PhotoImportPolicy.validateBytes(PhotoImportPolicy.MAX_SOURCE_BYTES + 1) }
        expectCode("photo_too_large") { PhotoImportPolicy.validateBytes(Long.MAX_VALUE) }
    }
    test("dimensions support normal 48MP/108MP and cap 128MP/20000px") {
        PhotoImportPolicy.validateDimensions(8000, 6000)
        PhotoImportPolicy.validateDimensions(12000, 9000)
        PhotoImportPolicy.validateDimensions(16000, 8000)
        PhotoImportPolicy.validateDimensions(20000, 6400)
        expectCode("photo_too_large") { PhotoImportPolicy.validateDimensions(16000, 8001) }
        expectCode("photo_too_large") { PhotoImportPolicy.validateDimensions(20001, 1) }
        expectCode("photo_too_large") { PhotoImportPolicy.validateDimensions(Int.MAX_VALUE, Int.MAX_VALUE) }
        expectCode("photo_unsupported") { PhotoImportPolicy.validateDimensions(-1, 1000) }
    }
    test("sample size is a power of two and bounds both decoded sides") {
        check(PhotoImportPolicy.sampleSize(4000, 3000) == 2)
        check(PhotoImportPolicy.sampleSize(8000, 6000) == 4)
        check(PhotoImportPolicy.sampleSize(12000, 9000) == 4)
        check(PhotoImportPolicy.sampleSize(16000, 8000) == 8)
        check(PhotoImportPolicy.sampleSize(3200, 3200) == 1)
        check(PhotoImportPolicy.sampleSize(3201, 1) == 2)
        for (width in 1..20000 step 137) {
            for (height in 1..20000 step 193) {
                if (width.toLong() * height > PhotoImportPolicy.MAX_SOURCE_PIXELS) continue
                val sample = PhotoImportPolicy.sampleSize(width, height)
                check(sample > 0 && sample and (sample - 1) == 0)
                check((width + sample - 1) / sample <= PhotoImportPolicy.MAX_DECODE_SIDE)
                check((height + sample - 1) / sample <= PhotoImportPolicy.MAX_DECODE_SIDE)
            }
        }
    }
    test("unexpected decoder dimensions/allocation fail before output bitmap") {
        PhotoImportPolicy.validateDecoded(3200, 3200, 3200L * 3200 * 4)
        expectCode("photo_too_large") { PhotoImportPolicy.validateDecoded(3201, 10, 3201L * 10 * 4) }
        expectCode("photo_too_large") { PhotoImportPolicy.validateDecoded(3200, 3200, 3200L * 3200 * 8) }
        expectCode("photo_unreadable") { PhotoImportPolicy.validateDecoded(0, 1, 0) }
    }
    test("all eight EXIF transforms map asymmetric corners correctly") {
        // Source corners: top-left, top-right, bottom-left, bottom-right.
        val source = arrayOf(0f to 0f, 4f to 0f, 0f to 2f, 4f to 2f)
        val expected = arrayOf(
            arrayOf(0f to 0f, 4f to 0f, 0f to 2f, 4f to 2f),
            arrayOf(4f to 0f, 0f to 0f, 4f to 2f, 0f to 2f),
            arrayOf(4f to 2f, 0f to 2f, 4f to 0f, 0f to 0f),
            arrayOf(0f to 2f, 4f to 2f, 0f to 0f, 4f to 0f),
            arrayOf(0f to 0f, 0f to 4f, 2f to 0f, 2f to 4f),
            arrayOf(2f to 0f, 2f to 4f, 0f to 0f, 0f to 4f),
            arrayOf(2f to 4f, 2f to 0f, 0f to 4f, 0f to 0f),
            arrayOf(0f to 4f, 0f to 0f, 2f to 4f, 2f to 0f),
        )
        for (orientation in 1..8) {
            val geometry = PhotoImportPolicy.outputTransform(4, 2, orientation)
            check(geometry.width == if (orientation >= 5) 2 else 4)
            check(geometry.height == if (orientation >= 5) 4 else 2)
            for (index in source.indices) {
                val actual = map(geometry.matrixValues, source[index])
                close(actual.first, expected[orientation - 1][index].first)
                close(actual.second, expected[orientation - 1][index].second)
            }
        }
    }
    test("orientation and resize share one bounded matrix without upscaling") {
        val landscape = PhotoImportPolicy.outputTransform(3200, 1600, 1)
        check(landscape.width == 1600 && landscape.height == 800)
        val portrait = PhotoImportPolicy.outputTransform(3200, 1600, 6)
        check(portrait.width == 800 && portrait.height == 1600)
        val corner = map(portrait.matrixValues, 3200f to 1600f)
        close(corner.first, 0f)
        close(corner.second, 1600f)
        val small = PhotoImportPolicy.outputTransform(12, 7, 99)
        check(small.width == 12 && small.height == 7)
        for (orientation in 1..8) {
            val geometry = PhotoImportPolicy.outputTransform(1, 3200, orientation)
            check(geometry.width >= 1 && geometry.height >= 1)
            check(max(geometry.width, geometry.height) <= 1600)
        }
    }
    test("JPEG output filtering removes EXIF/ICC/comments and preserves pixels") {
        val scan = bytes(0xff, 0xda, 0x00, 0x02, 11, 22, 33, 0xff, 0x00, 44, 0xff, 0xd9)
        val app0 = segment(0xe0, "JFIF".toByteArray())
        val table = segment(0xdb, bytes(1, 2, 3, 4))
        val original = bytes(0xff, 0xd8) + app0 +
            segment(0xe1, "Exif GPS location".toByteArray()) +
            segment(0xe2, "ICC_PROFILE".toByteArray()) +
            segment(0xfe, "private comment".toByteArray()) + table + scan
        val expected = bytes(0xff, 0xd8) + app0 + table + scan
        val saved = original.copyOf()
        check(PhotoImportPolicy.stripOutputMetadata(original).contentEquals(expected))
        check(original.contentEquals(saved))
        check(PhotoImportPolicy.stripOutputMetadata(expected).contentEquals(expected))
    }
    test("invalid JPEG encoder output fails instead of emitting partial bytes") {
        for (value in arrayOf(ByteArray(0), bytes(0xff, 0xd8, 0xff, 0xd9),
            bytes(0xff, 0xd8, 0xff, 0xe1, 0xff, 0xff, 0xff, 0xd9),
            bytes(0xff, 0xd8, 0xff, 0xda, 0, 2, 1, 2))) {
            expectCode("photo_prepare_failed") { PhotoImportPolicy.stripOutputMetadata(value) }
        }
    }
    println("$passed JVM policy tests passed. Android Bitmap runtime was not exercised.")
}

private fun expectCode(code: String, action: () -> Unit) {
    try {
        action()
        error("Expected $code")
    } catch (failure: PhotoImportFailure) {
        check(failure.code == code) { "Expected $code, received ${failure.code}" }
    }
}

private fun map(matrix: FloatArray, point: Pair<Float, Float>) =
    (matrix[0] * point.first + matrix[1] * point.second + matrix[2]) to
        (matrix[3] * point.first + matrix[4] * point.second + matrix[5])

private fun close(actual: Float, expected: Float) {
    check(abs(actual - expected) < 0.001f) { "$actual != $expected" }
}

private fun bytes(vararg values: Int) = ByteArray(values.size) { values[it].toByte() }

private fun segment(marker: Int, payload: ByteArray): ByteArray {
    val length = payload.size + 2
    return bytes(0xff, marker, length shr 8, length and 0xff) + payload
}
