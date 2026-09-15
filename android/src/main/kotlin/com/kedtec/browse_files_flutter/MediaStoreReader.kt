package com.kedtec.browse_files_flutter

import android.content.ContentResolver
import android.content.Context
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Size
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream

/**
 * Reads bytes off a content URI.
 *
 * The plugin never sees a `MediaStore` row id any more: the system Photo Picker hands
 * back content URIs and the SAF picker hands back file URIs, and both work the same way
 * here. A camera capture is a `file://` URI into the plugin's own cache, which has no
 * provider behind it — those are read straight off disk. Functions block and must be
 * called off the main thread — they walk cursors and copy streams while the grid scrolls.
 *
 * The maps handed back are exactly the shapes `MediaItem.fromMap` reads on the Dart
 * side.
 */
internal object MediaStoreReader {
    /** Where captures and resolved copies live; created on demand. */
    fun cacheDirectory(context: Context): File =
        File(context.cacheDir, "browse_files").apply { mkdirs() }

    /** The file behind a `file://` id, or null for anything a provider serves. */
    private fun fileOf(uri: Uri): File? =
        if (uri.scheme == "file") uri.path?.let(::File)?.takeIf { it.isFile } else null

    /** A JPEG thumbnail for [uri], or null when the platform cannot make one. */
    fun loadThumbnail(
        context: Context,
        uri: Uri,
        width: Int,
        height: Int,
        quality: Int
    ): ByteArray? {
        val file = fileOf(uri)
        val decoded: Bitmap? =
            when {
                file != null -> fileThumbnail(file, width, height)
                // A provider without thumbnails of its own (a Drive document behind
                // GET_CONTENT, say) throws here; the stream decode below still works for it.
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                    runCatching {
                        context.contentResolver.loadThumbnail(uri, Size(width, height), null)
                    }.getOrNull() ?: streamThumbnail(context, uri, width, height)
                else -> streamThumbnail(context, uri, width, height)
            }
        val thumbnail = decoded ?: return null
        // A hardware bitmap has no pixels this process can read, and compressing one fails
        // without saying so — the caller would get an empty array, which is a blank tile with
        // no error anywhere. Copy it into memory we own first.
        val bitmap =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                thumbnail.config == Bitmap.Config.HARDWARE
            ) {
                thumbnail.copy(Bitmap.Config.ARGB_8888, false).also { thumbnail.recycle() }
            } else {
                thumbnail
            } ?: return null
        val bytes =
            ByteArrayOutputStream().use { out ->
                val encoded = bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
                bitmap.recycle()
                if (encoded) out.toByteArray() else null
            }
        // An empty array crosses the channel as bytes, and Image.memory paints nothing for it.
        return if (bytes == null || bytes.isEmpty()) null else bytes
    }

    /**
     * Copies [uri] into the app cache and returns the path.
     *
     * A content URI is a handle, not a path, and the grant behind it can be revoked; the
     * host app gets a file it owns instead.
     */
    fun copyToCache(
        context: Context,
        uri: Uri
    ): String? {
        // A capture is already a file in the cache: hand it straight back.
        fileOf(uri)?.let { return it.absolutePath }
        val directory = cacheDirectory(context)
        val name =
            displayNameOf(context.contentResolver, uri)
                ?: uri.lastPathSegment
                ?: "file_${System.currentTimeMillis()}"
        val target = uniqueTarget(directory, name)
        val copied =
            try {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(target).use { output -> input.copyTo(output) }
                    true
                } ?: false
            } catch (error: Exception) {
                // Half a file is worse than none: the caller gets ioError, not a truncated path.
                target.delete()
                throw error
            }
        return if (copied) target.absolutePath else null
    }

    /**
     * A file in [directory] called [name] that nothing else is using.
     *
     * Never overwrites: a path handed to the host app stays valid, so a second file with the
     * same name lands beside the first as `name (1).ext` — the same rule as iOS.
     */
    private fun uniqueTarget(
        directory: File,
        name: String
    ): File {
        val safe = safeName(name)
        var candidate = File(directory, safe)
        if (!candidate.exists()) return candidate
        val dot = safe.lastIndexOf('.')
        val stem = if (dot > 0) safe.substring(0, dot) else safe
        val extension = if (dot > 0) safe.substring(dot) else ""
        var counter = 1
        while (candidate.exists()) {
            candidate = File(directory, "$stem ($counter)$extension")
            counter++
        }
        return candidate
    }

    /**
     * The metadata `MediaItem.fromMap` reads on the Dart side.
     *
     * Every column is best effort. The Photo Picker, MediaStore and a DocumentsProvider
     * behind GET_CONTENT each publish a different set, and a provider that is asked for a
     * column it does not have may throw or hand back a cursor without it — an item must not
     * vanish from the pick because its width was unavailable.
     */
    fun describe(
        context: Context,
        uri: Uri
    ): Map<String, Any?> {
        fileOf(uri)?.let { file ->
            return describeFile(file, isVideo = mimeTypeOf(file)?.startsWith("video/") == true)
        }
        val resolver = context.contentResolver
        val mimeType = runCatching { resolver.getType(uri) }.getOrNull()
        val isVideo = mimeType?.startsWith("video/") == true
        val row = rowOf(resolver, uri)
        var width = intOf(row, MediaStore.MediaColumns.WIDTH) ?: 0
        var height = intOf(row, MediaStore.MediaColumns.HEIGHT) ?: 0
        if (!isVideo && (width <= 0 || height <= 0)) {
            val bounds = boundsOf(resolver, uri)
            width = bounds.first
            height = bounds.second
        }
        val orientation = intOf(row, MediaStore.MediaColumns.ORIENTATION) ?: 0
        if (orientation == 90 || orientation == 270) width = height.also { height = width }
        var durationMs = longOf(row, MediaStore.MediaColumns.DURATION, PICKER_DURATION_MILLIS)
        if (isVideo && durationMs == null) durationMs = durationOf(context, uri)
        // MediaStore's DATE_TAKEN and the picker's are milliseconds; DATE_MODIFIED is seconds.
        val createdAtMs =
            longOf(row, MediaStore.MediaColumns.DATE_TAKEN, PICKER_DATE_TAKEN, DOCUMENT_LAST_MODIFIED)
                ?: longOf(row, MediaStore.MediaColumns.DATE_MODIFIED)?.times(1000L)
                ?: 0L
        return mapOf(
            "id" to uri.toString(),
            "type" to if (isVideo) "video" else "image",
            "width" to width,
            "height" to height,
            "createdAtMs" to createdAtMs,
            "durationMs" to durationMs,
            "mimeType" to mimeType,
            "name" to stringOf(row, OpenableColumns.DISPLAY_NAME),
            "sizeBytes" to longOf(row, OpenableColumns.SIZE)
        )
    }

    /**
     * The metadata for a file in the cache — a camera capture — read off the file itself,
     * since no provider knows it.
     *
     * A photo is measured with its EXIF orientation applied, and a video with its rotation,
     * so portrait shots report portrait sizes.
     */
    fun describeFile(
        file: File,
        isVideo: Boolean
    ): Map<String, Any?> {
        var width = 0
        var height = 0
        var durationMs: Long? = null
        if (isVideo) {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(file.absolutePath)
                width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
                height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
                durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                val rotation =
                    retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
                if (rotation == 90 || rotation == 270) width = height.also { height = width }
            } catch (error: Exception) {
                // Dimensions are cosmetic in a square grid; a clip we cannot read still attaches.
            } finally {
                retriever.release()
            }
        } else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.absolutePath, bounds)
            width = bounds.outWidth.coerceAtLeast(0)
            height = bounds.outHeight.coerceAtLeast(0)
            val orientation =
                runCatching {
                    ExifInterface(file.absolutePath)
                        .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
            if (orientation == ExifInterface.ORIENTATION_ROTATE_90 ||
                orientation == ExifInterface.ORIENTATION_ROTATE_270 ||
                orientation == ExifInterface.ORIENTATION_TRANSPOSE ||
                orientation == ExifInterface.ORIENTATION_TRANSVERSE
            ) {
                width = height.also { height = width }
            }
        }
        return mapOf(
            "id" to Uri.fromFile(file).toString(),
            "type" to if (isVideo) "video" else "image",
            "width" to width,
            "height" to height,
            "createdAtMs" to file.lastModified(),
            "durationMs" to durationMs,
            "mimeType" to (mimeTypeOf(file) ?: if (isVideo) "video/mp4" else "image/jpeg"),
            "name" to file.name,
            "sizeBytes" to file.length()
        )
    }

    private fun mimeTypeOf(file: File): String? =
        android.webkit.MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(file.extension.lowercase())

    /**
     * A thumbnail for a file in the cache, which no provider will make for us.
     *
     * API 29+ has `ThumbnailUtils` do it — orientation applied, centre-cropped; below that a
     * photo is decoded with a sample size that lands near the tile and turned upright by its
     * EXIF orientation, and a clip gives up its first frame.
     */
    private fun fileThumbnail(
        file: File,
        width: Int,
        height: Int
    ): Bitmap? {
        val isVideo = mimeTypeOf(file)?.startsWith("video/") == true
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                if (isVideo) {
                    ThumbnailUtils.createVideoThumbnail(file, Size(width, height), null)
                } else {
                    ThumbnailUtils.createImageThumbnail(file, Size(width, height), null)
                }
            } else if (isVideo) {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(file.absolutePath)
                    retriever.frameAtTime?.let { ThumbnailUtils.extractThumbnail(it, width, height, ThumbnailUtils.OPTIONS_RECYCLE_INPUT) }
                } finally {
                    retriever.release()
                }
            } else {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.absolutePath, bounds)
                val options = BitmapFactory.Options().apply { inSampleSize = sampleSizeFor(bounds, width, height) }
                val orientation =
                    runCatching {
                        ExifInterface(file.absolutePath)
                            .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                    }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
                BitmapFactory.decodeFile(file.absolutePath, options)?.let {
                    ThumbnailUtils.extractThumbnail(
                        upright(it, orientation),
                        width,
                        height,
                        ThumbnailUtils.OPTIONS_RECYCLE_INPUT
                    )
                }
            }
        } catch (error: Exception) {
            null
        }
    }

    /** The Photo Picker's own column names (`MediaStore.PickerMediaColumns`, API 33). */
    private const val PICKER_DURATION_MILLIS = "duration_millis"
    private const val PICKER_DATE_TAKEN = "date_taken"

    /** `DocumentsContract.Document.COLUMN_LAST_MODIFIED`, in milliseconds. */
    private const val DOCUMENT_LAST_MODIFIED = "last_modified"

    /**
     * The first row a provider returns for [uri], keyed by lowercase column name; empty when
     * it returns none or refuses the query.
     *
     * One query with no projection rather than one per column: the provider hands back
     * whatever it has, and asking a provider for a column it lacks is what throws.
     */
    private fun rowOf(
        resolver: ContentResolver,
        uri: Uri
    ): Map<String, Any?> =
        runCatching {
            resolver.query(uri, null, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return@use emptyMap<String, Any?>()
                cursor.columnNames.withIndex().associate { (index, name) ->
                    name.lowercase() to
                        when (cursor.getType(index)) {
                            Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(index)
                            Cursor.FIELD_TYPE_FLOAT -> cursor.getDouble(index)
                            Cursor.FIELD_TYPE_STRING -> cursor.getString(index)
                            else -> null
                        }
                }
            }
        }.getOrNull() ?: emptyMap()

    /** The first of [columns] present in [row] as a number; a numeric string counts. */
    private fun longOf(
        row: Map<String, Any?>,
        vararg columns: String
    ): Long? =
        columns.firstNotNullOfOrNull { column ->
            when (val value = row[column.lowercase()]) {
                is Number -> value.toLong()
                is String -> value.toLongOrNull()
                else -> null
            }
        }

    private fun intOf(
        row: Map<String, Any?>,
        vararg columns: String
    ): Int? = longOf(row, *columns)?.toInt()

    private fun stringOf(
        row: Map<String, Any?>,
        column: String
    ): String? = row[column.lowercase()]?.toString()?.takeIf { it.isNotEmpty() }

    /** A clip's length read off the stream, for providers that publish no duration column. */
    private fun durationOf(
        context: Context,
        uri: Uri
    ): Long? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
        } catch (error: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    /** An image's pixel size from its header alone — no bitmap is allocated. */
    private fun boundsOf(
        resolver: ContentResolver,
        uri: Uri
    ): Pair<Int, Int> =
        runCatching {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            bounds.outWidth.coerceAtLeast(0) to bounds.outHeight.coerceAtLeast(0)
        }.getOrDefault(0 to 0)

    /**
     * A thumbnail decoded off the provider's stream, for a URI the platform cannot make one
     * for: every content URI below API 29, and above it a provider with no thumbnails of
     * its own.
     *
     * The header is read first so the decode is sub-sampled to the tile — decoding a 12 MP
     * photo whole to draw a 256 px cell is how a grid runs out of memory. A photo is turned
     * upright by its EXIF orientation, a clip gives up its first frame.
     */
    private fun streamThumbnail(
        context: Context,
        uri: Uri,
        width: Int,
        height: Int
    ): Bitmap? {
        val resolver = context.contentResolver
        return try {
            if (resolver.getType(uri)?.startsWith("video/") == true) {
                val retriever = MediaMetadataRetriever()
                try {
                    retriever.setDataSource(context, uri)
                    retriever.frameAtTime?.let {
                        ThumbnailUtils.extractThumbnail(it, width, height, ThumbnailUtils.OPTIONS_RECYCLE_INPUT)
                    }
                } finally {
                    retriever.release()
                }
            } else {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
                val options = BitmapFactory.Options().apply { inSampleSize = sampleSizeFor(bounds, width, height) }
                val decoded =
                    resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
                        ?: return null
                val orientation =
                    runCatching {
                        resolver.openInputStream(uri)?.use { input ->
                            ExifInterface(input)
                                .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                        }
                    }.getOrNull() ?: ExifInterface.ORIENTATION_NORMAL
                ThumbnailUtils.extractThumbnail(
                    upright(decoded, orientation),
                    width,
                    height,
                    ThumbnailUtils.OPTIONS_RECYCLE_INPUT
                )
            }
        } catch (error: Exception) {
            null
        }
    }

    /** The largest power-of-two sample that still leaves the decode at least [width] x [height]. */
    private fun sampleSizeFor(
        bounds: BitmapFactory.Options,
        width: Int,
        height: Int
    ): Int {
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= width && bounds.outHeight / (sample * 2) >= height) {
            sample *= 2
        }
        return sample
    }

    /** [bitmap] rotated to its EXIF [orientation]; the input is recycled when a copy is made. */
    private fun upright(
        bitmap: Bitmap,
        orientation: Int
    ): Bitmap {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> matrix.postRotate(90f).also { matrix.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_TRANSVERSE -> matrix.postRotate(270f).also { matrix.postScale(-1f, 1f) }
            else -> return bitmap
        }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }

    private fun displayNameOf(
        resolver: ContentResolver,
        uri: Uri
    ): String? =
        resolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }

    /** Keeps a provider-supplied name from escaping the cache directory. */
    private fun safeName(name: String): String =
        name.substringAfterLast('/').replace("..", "_").ifEmpty { "file" }
}
