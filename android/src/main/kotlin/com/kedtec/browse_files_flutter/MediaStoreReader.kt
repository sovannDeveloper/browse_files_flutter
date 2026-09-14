package com.kedtec.browse_files_flutter

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Build
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
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                    context.contentResolver.loadThumbnail(uri, Size(width, height), null)
                else -> legacyThumbnail(context.contentResolver, uri, width, height)
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
        val target = File(directory, safeName(name))
        val copied =
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(target).use { output -> input.copyTo(output) }
                true
            } ?: false
        return if (copied) target.absolutePath else null
    }

    /** The metadata `MediaItem.fromMap` reads on the Dart side. */
    fun describe(
        context: Context,
        uri: Uri
    ): Map<String, Any?> {
        fileOf(uri)?.let { file ->
            return describeFile(file, isVideo = mimeTypeOf(file)?.startsWith("video/") == true)
        }
        val (width, height) = dimensionsOf(context.contentResolver, uri)
        val (sizeBytes, displayName) = statOf(context.contentResolver, uri)
        val mimeType = context.contentResolver.getType(uri)
        return mapOf(
            "id" to uri.toString(),
            "type" to mimeTypeVideo(mimeType),
            "width" to width,
            "height" to height,
            "createdAtMs" to lastModifiedOf(context.contentResolver, uri),
            "durationMs" to null,
            "mimeType" to mimeType,
            "name" to displayName,
            "sizeBytes" to sizeBytes
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
     * photo is decoded with a sample size that lands near the tile and a clip gives up its
     * first frame.
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
                var sample = 1
                while (bounds.outWidth / (sample * 2) >= width && bounds.outHeight / (sample * 2) >= height) {
                    sample *= 2
                }
                val options = BitmapFactory.Options().apply { inSampleSize = sample }
                BitmapFactory.decodeFile(file.absolutePath, options)?.let {
                    ThumbnailUtils.extractThumbnail(it, width, height, ThumbnailUtils.OPTIONS_RECYCLE_INPUT)
                }
            }
        } catch (error: Exception) {
            null
        }
    }

    private fun mimeTypeVideo(mimeType: String?): String =
        if (mimeType != null && mimeType.startsWith("video/")) "video" else "image"

    private val DIMENSIONS_PROJECTION =
        arrayOf(android.provider.MediaStore.MediaColumns.WIDTH, android.provider.MediaStore.MediaColumns.HEIGHT)

    private fun dimensionsOf(resolver: ContentResolver, uri: Uri): Pair<Int, Int> =
        resolver.query(uri, DIMENSIONS_PROJECTION, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getInt(0) to cursor.getInt(1) else 0 to 0
        } ?: (0 to 0)

    private val STAT_PROJECTION =
        arrayOf(OpenableColumns.SIZE, OpenableColumns.DISPLAY_NAME)

    private fun statOf(resolver: ContentResolver, uri: Uri): Pair<Long?, String?> =
        resolver.query(uri, STAT_PROJECTION, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val size = if (cursor.isNull(0)) null else cursor.getLong(0)
                val name = if (cursor.isNull(1)) null else cursor.getString(1)
                size to name
            } else {
                null to null
            }
        } ?: (null to null)

    private val DATE_PROJECTION =
        arrayOf(android.provider.MediaStore.MediaColumns.DATE_MODIFIED)

    private fun lastModifiedOf(resolver: ContentResolver, uri: Uri): Long =
        resolver.query(uri, DATE_PROJECTION, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) * 1000L else 0L
        } ?: 0L

    /**
     * Best-effort fallback for `loadThumbnail` below API 29, where
     * [ContentResolver.loadThumbnail] does not exist.
     *
     * Decodes the URI to a bitmap directly. Returns null on any failure rather than
     * surfacing it — the tile then shows the "no thumbnail" glyph and the caller can
     * still resolve the file.
     */
    @Suppress("DEPRECATION")
    private fun legacyThumbnail(
        resolver: ContentResolver,
        uri: Uri,
        width: Int,
        height: Int
    ): Bitmap? =
        try {
            resolver.openInputStream(uri)?.use { input ->
                android.graphics.BitmapFactory.decodeStream(input, null, null)
            }
        } catch (error: Exception) {
            null
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
