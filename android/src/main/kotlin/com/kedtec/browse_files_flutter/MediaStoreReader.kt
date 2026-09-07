package com.kedtec.browse_files_flutter

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Size
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap

/**
 * Everything that reads MediaStore, kept apart from the channel plumbing.
 *
 * Every function here blocks and must be called off the main thread: these are cursor walks and
 * file copies, and the grid scrolls while they run. The maps handed back are exactly the shapes
 * `MediaItem.fromMap`, `MediaAlbum.fromMap` and `MediaPage.fromMap` read on the Dart side.
 */
internal object MediaStoreReader {
    /** The synthetic album that means "the whole library". */
    const val ALL_ALBUM_ID = "all"

    /** The MIME pattern that means "no filter at all". */
    private const val ANY_MIME_TYPE = "*/*"

    private val COLLECTION: Uri = MediaStore.Files.getContentUri("external")

    /**
     * The last row count worked out for a selection, keyed by it.
     *
     * Only reached when the provider does not volunteer EXTRA_TOTAL_COUNT — below Android R
     * that is every query, and counting there means running the selection again with no LIMIT.
     * Doing that per page turns one scroll through a large library into a scan per page. A
     * browse always starts at offset 0, so that is where the count is taken again; the pages
     * that follow reuse it. Concurrent because library reads run on a pool.
     */
    private val totals = ConcurrentHashMap<String, Int>()

    private val PROJECTION =
        arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
            MediaStore.MediaColumns.WIDTH,
            MediaStore.MediaColumns.HEIGHT,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.DURATION,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE
        )

    private val DOCUMENT_PROJECTION =
        arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DATE_MODIFIED
        )

    private const val SORT = "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"

    /** One page of an album, newest first, as `MediaPage.fromMap` expects it. */
    fun fetchMedia(
        context: Context,
        types: Set<String>,
        albumId: String?,
        offset: Int,
        limit: Int
    ): Map<String, Any?> {
        val (selection, args) = selectionFor(types, albumId)
        val items = mutableListOf<Map<String, Any?>>()
        var total = -1
        query(context.contentResolver, PROJECTION, selection, args, limit, offset)?.use { cursor ->
            total = reportedTotal(cursor)
            while (cursor.moveToNext()) {
                items.add(itemFrom(cursor))
            }
        }
        if (total < 0) {
            total = totalFor(context.contentResolver, selection, args, offset)
        }
        return mapOf("items" to items, "offset" to offset, "total" to total)
    }

    /**
     * The albums holding at least one matching asset, "all media" first.
     *
     * MediaStore has no GROUP BY, so this walks the ids and buckets — three small columns —
     * and counts them here. The rows are already newest-first, so the first id seen for a
     * bucket is its cover.
     */
    fun fetchAlbums(
        context: Context,
        types: Set<String>
    ): List<Map<String, Any?>> {
        val (selection, args) = selectionFor(types, null)
        val projection =
            arrayOf(
                MediaStore.Files.FileColumns._ID,
                MediaStore.Files.FileColumns.BUCKET_ID,
                MediaStore.Files.FileColumns.BUCKET_DISPLAY_NAME
            )
        val albums = LinkedHashMap<String, MutableMap<String, Any?>>()
        var total = 0
        var newestId: String? = null
        context.contentResolver
            .query(COLLECTION, projection, selection, args, SORT)
            ?.use { cursor ->
                while (cursor.moveToNext()) {
                    total++
                    val id = cursor.getLong(0).toString()
                    if (newestId == null) newestId = id
                    val bucketId = cursor.getString(1) ?: continue
                    val album =
                        albums.getOrPut(bucketId) {
                            mutableMapOf(
                                "id" to bucketId,
                                "name" to (cursor.getString(2) ?: ""),
                                "count" to 0,
                                "coverId" to id,
                                "isAll" to false
                            )
                        }
                    album["count"] = (album["count"] as Int) + 1
                }
            }
        val all =
            mapOf(
                "id" to ALL_ALBUM_ID,
                "name" to "All media",
                "count" to total,
                "coverId" to newestId,
                "isAll" to true
            )
        return listOf(all) + albums.values
    }

    /**
     * One page of the files that are not photos or videos.
     *
     * Scoped storage is the whole story here: from Android 11 (API 30) MediaStore only hands
     * back non-visual rows this app itself created, so the answer carries `enumerable` to say
     * whether a device-wide listing was even possible. Everything else is behind the system
     * picker, by design of the OS.
     */
    fun fetchDocuments(
        context: Context,
        mimeTypes: List<String>,
        offset: Int,
        limit: Int
    ): Map<String, Any?> {
        val selection =
            StringBuilder(
                "${MediaStore.Files.FileColumns.MEDIA_TYPE} NOT IN (?, ?)" +
                    " AND ${MediaStore.MediaColumns.SIZE} > 0" +
                    " AND ${MediaStore.MediaColumns.DISPLAY_NAME} IS NOT NULL"
            )
        val args =
            mutableListOf(
                MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(),
                MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString()
            )
        // "image/*" is a pattern, not a value: SQL IN cannot match it, so wildcards
        // become LIKE clauses and "*/*" drops the filter altogether.
        if (mimeTypes.isNotEmpty() && !mimeTypes.contains(ANY_MIME_TYPE)) {
            val exact = mimeTypes.filterNot { it.endsWith("/*") }
            val patterns = mimeTypes.filter { it.endsWith("/*") }
            val clauses = mutableListOf<String>()
            if (exact.isNotEmpty()) {
                val placeholders = exact.joinToString(",") { "?" }
                clauses.add("${MediaStore.MediaColumns.MIME_TYPE} IN ($placeholders)")
                args.addAll(exact)
            }
            for (pattern in patterns) {
                clauses.add("${MediaStore.MediaColumns.MIME_TYPE} LIKE ?")
                args.add(pattern.dropLast(1) + "%")
            }
            if (clauses.isNotEmpty()) {
                selection.append(" AND (${clauses.joinToString(" OR ")})")
            }
        }
        val selectionText = selection.toString()
        val selectionArgs = args.toTypedArray()

        val items = mutableListOf<Map<String, Any?>>()
        var total = -1
        query(
            context.contentResolver,
            DOCUMENT_PROJECTION,
            selectionText,
            selectionArgs,
            limit,
            offset
        )?.use { cursor ->
            total = reportedTotal(cursor)
            while (cursor.moveToNext()) {
                items.add(documentFrom(cursor))
            }
        }
        if (total < 0) {
            total = totalFor(context.contentResolver, selectionText, selectionArgs, offset)
        }
        return mapOf(
            "items" to items,
            "offset" to offset,
            "total" to total,
            "enumerable" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.R)
        )
    }

    /** A JPEG thumbnail for one asset, or null when the platform cannot make one. */
    fun loadThumbnail(
        context: Context,
        id: String,
        width: Int,
        height: Int,
        quality: Int
    ): ByteArray? {
        val assetId = id.toLongOrNull() ?: return null
        val thumbnail =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                context.contentResolver.loadThumbnail(uriOf(assetId), Size(width, height), null)
            } else {
                legacyThumbnail(context.contentResolver, assetId, width, height)
            } ?: return null
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

    /** Copies a library asset into the app cache and returns the path. */
    fun resolveFile(
        context: Context,
        id: String
    ): String? {
        val assetId = id.toLongOrNull() ?: return null
        return copyToCache(context, uriOf(assetId))
    }

    /**
     * Copies a content URI into the app cache.
     *
     * A SAF URI and a MediaStore URI are both handles, not paths, and the grant behind them can
     * be revoked; the host app gets a file it owns instead.
     */
    fun copyToCache(
        context: Context,
        uri: Uri
    ): String? {
        val directory = File(context.cacheDir, "browse_files").apply { mkdirs() }
        val name = displayNameOf(context.contentResolver, uri) ?: "file_${System.currentTimeMillis()}"
        val target = File(directory, safeName(name))
        val copied =
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(target).use { output -> input.copyTo(output) }
                true
            } ?: false
        return if (copied) target.absolutePath else null
    }

    private fun uriOf(assetId: Long): Uri = ContentUris.withAppendedId(COLLECTION, assetId)

    private fun selectionFor(
        types: Set<String>,
        albumId: String?
    ): Pair<String, Array<String>> {
        val mediaTypes =
            buildList {
                if (types.contains("image")) add(MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE)
                if (types.contains("video")) add(MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO)
            }
        val placeholders = mediaTypes.joinToString(",") { "?" }
        val selection = StringBuilder("${MediaStore.Files.FileColumns.MEDIA_TYPE} IN ($placeholders)")
        val args = mediaTypes.mapTo(mutableListOf()) { it.toString() }
        if (albumId != null && albumId != ALL_ALBUM_ID) {
            selection.append(" AND ${MediaStore.Files.FileColumns.BUCKET_ID} = ?")
            args.add(albumId)
        }
        return selection.toString() to args.toTypedArray()
    }

    private fun query(
        resolver: ContentResolver,
        projection: Array<String>,
        selection: String,
        args: Array<String>,
        limit: Int,
        offset: Int
    ): Cursor? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bundle =
                Bundle().apply {
                    putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                    putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, args)
                    putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, SORT)
                    putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
                    putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
                }
            resolver.query(COLLECTION, projection, bundle, null)
        } else {
            // The provider is SQLite-backed, so paging rides on the sort order below R.
            resolver.query(COLLECTION, projection, selection, args, "$SORT LIMIT $limit OFFSET $offset")
        }

    /** The row count the provider volunteered, or -1 when it did not. */
    private fun reportedTotal(cursor: Cursor): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            cursor.extras?.getInt(ContentResolver.EXTRA_TOTAL_COUNT, -1) ?: -1
        } else {
            -1
        }

    /**
     * The row count for a selection: measured at the start of a browse, remembered for the
     * pages after it.
     */
    private fun totalFor(
        resolver: ContentResolver,
        selection: String,
        args: Array<String>,
        offset: Int
    ): Int {
        val key = args.joinToString(separator = "\u0000", prefix = "$selection\u0000")
        if (offset > 0) {
            totals[key]?.let { return it }
        }
        val total = count(resolver, selection, args)
        totals[key] = total
        return total
    }

    private fun count(
        resolver: ContentResolver,
        selection: String,
        args: Array<String>
    ): Int =
        resolver
            .query(COLLECTION, arrayOf(MediaStore.Files.FileColumns._ID), selection, args, null)
            ?.use { it.count } ?: 0

    private fun documentFrom(cursor: Cursor): Map<String, Any?> =
        mapOf(
            "id" to cursor.getLong(0).toString(),
            "name" to cursor.getString(1),
            "sizeBytes" to cursor.getLong(2),
            "mimeType" to cursor.getString(3),
            // DATE_MODIFIED is in seconds; the Dart model reads milliseconds.
            "modifiedAtMs" to cursor.getLong(4) * 1000L,
            // A MediaStore row is a handle, not a path: resolveFile copies it out.
            "path" to null
        )

    private fun itemFrom(cursor: Cursor): Map<String, Any?> {
        val isVideo =
            cursor.getInt(1) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
        val duration = if (cursor.isNull(5)) null else cursor.getLong(5)
        return mapOf(
            "id" to cursor.getLong(0).toString(),
            "type" to if (isVideo) "video" else "image",
            "width" to cursor.getInt(2),
            "height" to cursor.getInt(3),
            // DATE_MODIFIED is in seconds; the Dart model reads milliseconds.
            "createdAtMs" to cursor.getLong(4) * 1000L,
            "durationMs" to if (isVideo) duration else null,
            "mimeType" to cursor.getString(6),
            "name" to cursor.getString(7),
            "sizeBytes" to cursor.getLong(8)
        )
    }

    @Suppress("DEPRECATION")
    private fun legacyThumbnail(
        resolver: ContentResolver,
        assetId: Long,
        width: Int,
        height: Int
    ): Bitmap? {
        val kind =
            if (width <= 96 && height <= 96) {
                MediaStore.Images.Thumbnails.MICRO_KIND
            } else {
                MediaStore.Images.Thumbnails.MINI_KIND
            }
        val isVideo =
            resolver
                .query(
                    COLLECTION,
                    arrayOf(MediaStore.Files.FileColumns.MEDIA_TYPE),
                    "${MediaStore.Files.FileColumns._ID} = ?",
                    arrayOf(assetId.toString()),
                    null
                )?.use { cursor ->
                    cursor.moveToFirst() &&
                        cursor.getInt(0) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
                } ?: false
        return if (isVideo) {
            MediaStore.Video.Thumbnails.getThumbnail(resolver, assetId, kind, null)
        } else {
            MediaStore.Images.Thumbnails.getThumbnail(resolver, assetId, kind, null)
        }
    }

    private fun displayNameOf(
        resolver: ContentResolver,
        uri: Uri
    ): String? =
        resolver
            .query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }

    /** Keeps a provider-supplied name from escaping the cache directory. */
    private fun safeName(name: String): String =
        name.substringAfterLast('/').replace("..", "_").ifEmpty { "file" }
}
