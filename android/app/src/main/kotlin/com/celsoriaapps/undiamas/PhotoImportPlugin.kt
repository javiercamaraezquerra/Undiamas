package com.celsoriaapps.undiamas

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorSpace
import android.graphics.Matrix
import android.graphics.Paint
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileDescriptor
import java.io.IOException
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/**
 * Converts an app-private picker file into a small metadata-free JPEG in memory.
 * It never writes, replaces, or deletes the selected file. Dart owns cache cleanup.
 */
class PhotoImportPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var generation = 0
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var executor: ThreadPoolExecutor? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        generation++
        context = binding.applicationContext
        executor = ThreadPoolExecutor(
            1, 1, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue<Runnable>(1),
            { runnable -> Thread(runnable, "UnDiaMasPhotoImport").apply { isDaemon = true } },
            ThreadPoolExecutor.AbortPolicy(),
        )
        channel = MethodChannel(binding.binaryMessenger, "undiamas/photos").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "prepare") {
            result.notImplemented()
            return
        }
        val arguments = call.arguments as? Map<*, *>
        val path = arguments?.get("path") as? String
        val appContext = context
        val worker = executor
        if (path.isNullOrBlank() || path.length > 4096 || path.indexOf('\u0000') >= 0 ||
            appContext == null || worker == null
        ) {
            reportError(result, "photo_unreadable")
            return
        }
        val requestGeneration = generation
        try {
            worker.execute {
                var jpeg: ByteArray? = null
                var code: String? = null
                try {
                    ensureCurrent(requestGeneration)
                    jpeg = prepare(appContext, path, requestGeneration)
                } catch (_: PhotoPreparationCancelled) {
                    // A detached engine has no receiver. Buffers/FDs are released
                    // by prepare's finally blocks, and no stale result is sent.
                    return@execute
                } catch (failure: PhotoImportFailure) {
                    code = failure.code
                } catch (_: OutOfMemoryError) {
                    code = "photo_too_large"
                } catch (_: SecurityException) {
                    code = "photo_unreadable"
                } catch (_: IOException) {
                    code = "photo_unreadable"
                } catch (failure: ErrnoException) {
                    code = if (failure.errno == OsConstants.ENOSPC) "photo_storage" else "photo_unreadable"
                } catch (_: RuntimeException) {
                    code = "photo_prepare_failed"
                }
                val preparedBytes = jpeg
                val failureCode = code
                mainHandler.post {
                    if (generation != requestGeneration || channel == null) return@post
                    if (failureCode != null) {
                        reportError(result, failureCode)
                    } else if (preparedBytes != null) {
                        result.success(preparedBytes)
                    } else {
                        reportError(result, "photo_prepare_failed")
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            // Never accumulate unbounded queued jobs/MethodChannel results.
            reportError(result, "photo_prepare_failed")
        }
    }

    private fun prepare(appContext: Context, path: String, token: Int): ByteArray {
        val cache = appContext.cacheDir.canonicalFile
        val selected = File(path)
        if (!selected.isAbsolute) throw PhotoImportFailure("photo_unreadable")
        val canonical = selected.canonicalFile
        if (!inside(cache, canonical)) throw PhotoImportFailure("photo_unreadable")

        // O_NOFOLLOW rejects a last-component symlink swapped after canonicalizing.
        // fstat/stat identity below also detects a changed intermediate directory.
        val descriptor = Os.open(
            canonical.path,
            OsConstants.O_RDONLY or OsConstants.O_CLOEXEC or OsConstants.O_NOFOLLOW or OsConstants.O_NONBLOCK,
            0,
        )
        try {
            val opened = Os.fstat(descriptor)
            if (!OsConstants.S_ISREG(opened.st_mode)) throw PhotoImportFailure("photo_unreadable")
            val current = selected.canonicalFile
            if (!inside(cache, current)) throw PhotoImportFailure("photo_unreadable")
            val named = Os.stat(current.path)
            if (opened.st_dev != named.st_dev || opened.st_ino != named.st_ino) {
                throw PhotoImportFailure("photo_unreadable")
            }
            PhotoImportPolicy.validateBytes(opened.st_size)
            ensureCurrent(token)

            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFileDescriptor(descriptor, null, bounds)
            PhotoImportPolicy.validateDimensions(bounds.outWidth, bounds.outHeight)
            val sample = PhotoImportPolicy.sampleSize(bounds.outWidth, bounds.outHeight)
            ensureCurrent(token)
            val orientation = readOrientation(descriptor)
            ensureCurrent(token)
            Os.lseek(descriptor, 0L, OsConstants.SEEK_SET)
            PhotoImportPolicy.validateBytes(Os.fstat(descriptor).st_size)

            val options = BitmapFactory.Options().apply {
                inSampleSize = sample
                inScaled = false
                inPreferredConfig = Bitmap.Config.ARGB_8888
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    inPreferredColorSpace = ColorSpace.get(ColorSpace.Named.SRGB)
                }
            }
            val decoded = BitmapFactory.decodeFileDescriptor(descriptor, null, options)
                ?: throw PhotoImportFailure("photo_unreadable")
            try {
                ensureCurrent(token)
                PhotoImportPolicy.validateDecoded(
                    decoded.width, decoded.height, decoded.allocationByteCount.toLong(),
                )
                val geometry = PhotoImportPolicy.outputTransform(decoded.width, decoded.height, orientation)
                val output = Bitmap.createBitmap(geometry.width, geometry.height, Bitmap.Config.ARGB_8888)
                try {
                    output.setHasAlpha(false)
                    val canvas = Canvas(output)
                    canvas.drawColor(Color.WHITE)
                    val matrix = Matrix().apply { setValues(geometry.matrixValues) }
                    val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG)
                    canvas.drawBitmap(decoded, matrix, paint)
                    ensureCurrent(token)
                    return encode(output, token)
                } finally {
                    output.recycle()
                }
            } finally {
                decoded.recycle()
            }
        } finally {
            Os.close(descriptor)
        }
    }

    private fun readOrientation(descriptor: FileDescriptor): Int {
        Os.lseek(descriptor, 0L, OsConstants.SEEK_SET)
        return try {
            ExifInterface(descriptor).getAttributeInt(
                ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL,
            ).let { if (it in 1..8) it else ExifInterface.ORIENTATION_NORMAL }
        } catch (_: IOException) {
            // Some OS-supported formats have no readable EXIF. Their decoded
            // pixels are still usable; malformed optional metadata is discarded.
            ExifInterface.ORIENTATION_NORMAL
        } catch (_: RuntimeException) {
            ExifInterface.ORIENTATION_NORMAL
        }
    }

    private fun encode(bitmap: Bitmap, token: Int): ByteArray {
        for (quality in PhotoImportPolicy.JPEG_QUALITIES) {
            ensureCurrent(token)
            val encoded = ByteArrayOutputStream().use { output ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, quality, output)) {
                    throw PhotoImportFailure("photo_prepare_failed")
                }
                output.toByteArray()
            }
            ensureCurrent(token)
            val clean = PhotoImportPolicy.stripOutputMetadata(encoded)
            if (clean.size <= PhotoImportPolicy.TARGET_OUTPUT_BYTES ||
                (quality == PhotoImportPolicy.JPEG_QUALITIES.last() &&
                    clean.size <= PhotoImportPolicy.MAX_OUTPUT_BYTES)
            ) {
                return clean
            }
        }
        throw PhotoImportFailure("photo_too_large")
    }

    private fun ensureCurrent(token: Int) {
        if (generation != token || Thread.currentThread().isInterrupted) {
            throw PhotoPreparationCancelled()
        }
    }

    private fun inside(root: File, candidate: File) =
        candidate.path.startsWith(root.path + File.separator)

    private fun reportError(result: MethodChannel.Result, code: String) {
        val message = when (code) {
            "photo_unreadable" -> "No se puede leer esta foto. Elígela de nuevo desde la galería."
            "photo_unsupported" -> "Android no puede abrir este formato de imagen. Prueba con otra foto."
            "photo_too_large" -> "Esta foto supera el tamaño que podemos preparar con seguridad. Elige una versión más pequeña."
            "photo_storage" -> "No se ha podido acceder a la foto seleccionada. Comprueba el almacenamiento y vuelve a intentarlo."
            else -> "No se ha podido preparar esta foto. Tu mensaje se conserva."
        }
        result.error(code, message, null)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        generation++
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
        executor?.shutdownNow()
        executor = null
    }
}

private class PhotoPreparationCancelled : RuntimeException()
