package com.kedtec.browse_files_flutter

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Android side of `browse_files_flutter`.
 *
 * Media access is not binary here: on API 34+ the user can grant
 * READ_MEDIA_VISUAL_USER_SELECTED alone, which is reported as "limited" and re-opens the system
 * photo picker rather than counting as a refusal.
 *
 * Every library read runs on [worker] and replies on the main thread — cursor walks and file
 * copies must not block the platform thread while the grid is scrolling. The queries themselves
 * live in [MediaStoreReader].
 *
 * The host app must declare the permissions it wants in its own manifest; an undeclared
 * permission is denied without ever showing a dialog. See `example/android`.
 *
 * Errors come back as `result.error(code, message, details)` with a code from
 * BrowseFilesErrorCode: permissionDenied, userCanceled, notFound, ioError, unsupported.
 */
class BrowseFilesFlutterPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodCallHandler,
    RequestPermissionsResultListener,
    ActivityResultListener {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    /** The reply waiting on the system permission dialog, with the types it asked about. */
    private var pendingResult: Result? = null
    private var pendingTypes: Set<String> = emptySet()

    /** The reply waiting on the system document picker. */
    private var pendingDocuments: Result? = null

    /**
     * Created on first use, not on construction: touching Looper in a constructor makes the
     * plugin impossible to instantiate in a plain JVM unit test.
     *
     * A pool rather than a single thread: the grid asks for one thumbnail per visible tile at
     * once, and on one thread each tile waits for every tile before it to be decoded and
     * re-encoded — and for any resolveFile copy that happens to be queued ahead of them.
     */
    private val worker: ExecutorService by lazy {
        Executors.newFixedThreadPool(
            Runtime.getRuntime().availableProcessors().coerceIn(2, 6)
        )
    }
    private val main: Handler by lazy { Handler(Looper.getMainLooper()) }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel =
            MethodChannel(
                flutterPluginBinding.binaryMessenger,
                CHANNEL
            )
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        worker.shutdown()
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "permissionStatus" -> result.success(statusOf(typesOf(call)))
            "requestPermission" -> requestPermission(typesOf(call), result)
            "presentLimitedPicker" -> presentLimitedPicker(result)
            "openSettings" -> openSettings(result)
            "fetchAlbums" -> fetchAlbums(call, result)
            "fetchMedia" -> fetchMedia(call, result)
            "loadThumbnail" -> loadThumbnail(call, result)
            "resolveFile" -> resolveFile(call, result)
            "fetchDocuments" -> fetchDocuments(call, result)
            "pickDocuments" -> pickDocuments(call, result)
            else -> result.notImplemented()
        }
    }

    /** Asks for whatever [types] needs, answering with the access level the user settled on. */
    private fun requestPermission(
        types: Set<String>,
        result: Result
    ) {
        val activity = activity
        if (activity == null) {
            result.error(
                UNSUPPORTED,
                "Asking for media access needs a foreground activity.",
                null
            )
            return
        }
        if (pendingResult != null) {
            result.error(UNKNOWN, "A permission request is already in flight.", null)
            return
        }
        val requested = requestedPermissions(types)
        if (requested.isEmpty()) {
            result.error(UNSUPPORTED, "No media type was asked for.", null)
            return
        }
        // Already fully granted: the system would return immediately anyway.
        if (statusOf(types) == GRANTED) {
            result.success(GRANTED)
            return
        }
        pendingResult = result
        pendingTypes = types
        markAsked()
        activity.requestPermissions(requested.toTypedArray(), PERMISSION_REQUEST_CODE)
    }

    /**
     * Re-opens the system photo picker so a limited grant can be widened.
     *
     * On API 34+ re-requesting READ_MEDIA_VISUAL_USER_SELECTED while partially granted is what
     * shows the "select more photos" sheet; there is no such thing below that.
     */
    private fun presentLimitedPicker(result: Result) {
        if (!partialGrantSupported) {
            result.error(
                UNSUPPORTED,
                "Partial media access needs Android 14 (API 34) or newer.",
                null
            )
            return
        }
        if (statusOf(ALL_TYPES) != LIMITED) {
            result.error(
                UNSUPPORTED,
                "The photo picker only re-opens while access is limited.",
                null
            )
            return
        }
        requestPermission(ALL_TYPES, result)
    }

    private fun openSettings(result: Result) {
        val context = context
        if (context == null) {
            result.error(UNSUPPORTED, "The plugin is not attached to an engine.", null)
            return
        }
        val intent =
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", context.packageName, null)
            )
        val host: Context = activity ?: context.also { intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
        try {
            host.startActivity(intent)
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            result.success(false)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val result = pendingResult ?: return false
        val types = pendingTypes
        pendingResult = null
        pendingTypes = emptySet()
        // Read the grants back rather than trusting grantResults: a partial grant denies
        // READ_MEDIA_IMAGES and grants READ_MEDIA_VISUAL_USER_SELECTED instead.
        result.success(statusOf(types))
        return true
    }

    /** The access level right now, without prompting. */
    private fun statusOf(types: Set<String>): String {
        val context = context ?: return DENIED
        val required = requiredPermissions(types)
        if (required.isEmpty()) return DENIED
        if (required.all { context.isGranted(it) }) return GRANTED
        if (partialGrantSupported &&
            context.isGranted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
        ) {
            return LIMITED
        }
        if (!hasAsked()) return NOT_DETERMINED
        // Without an activity there is no rationale to read, so report the safer answer.
        val activity = activity ?: return DENIED
        val canAskAgain = required.any { activity.shouldShowRequestPermissionRationale(it) }
        return if (canAskAgain) DENIED else PERMANENTLY_DENIED
    }

    /** The permissions that must be held to read [types] in full. */
    private fun requiredPermissions(types: Set<String>): List<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            buildList {
                if (IMAGE in types) add(Manifest.permission.READ_MEDIA_IMAGES)
                if (VIDEO in types) add(Manifest.permission.READ_MEDIA_VIDEO)
            }
        } else if (types.isEmpty()) {
            emptyList()
        } else {
            listOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

    /**
     * What to hand [Activity.requestPermissions].
     *
     * READ_MEDIA_VISUAL_USER_SELECTED has to travel with the full-access permissions, otherwise
     * API 34+ never offers the "select photos" choice.
     */
    private fun requestedPermissions(types: Set<String>): List<String> {
        val required = requiredPermissions(types)
        if (required.isEmpty() || !partialGrantSupported) return required
        return required + Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
    }

    private val partialGrantSupported: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE

    private fun Context.isGranted(permission: String): Boolean =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun typesOf(call: MethodCall): Set<String> =
        call.argument<List<String>>("types")?.toSet() ?: ALL_TYPES

    /**
     * Whether the dialog has ever been shown.
     *
     * Android cannot tell "never asked" from "asked and refused for good" — both read as denied
     * with no rationale — so the first ask is recorded here.
     */
    private fun hasAsked(): Boolean = prefs()?.getBoolean(KEY_ASKED, false) ?: false

    private fun markAsked() {
        prefs()?.edit()?.putBoolean(KEY_ASKED, true)?.apply()
    }

    private fun prefs(): SharedPreferences? = context?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun fetchAlbums(
        call: MethodCall,
        result: Result
    ) {
        val types = typesOf(call)
        onLibrary(result) { context -> MediaStoreReader.fetchAlbums(context, types) }
    }

    private fun fetchMedia(
        call: MethodCall,
        result: Result
    ) {
        val types = typesOf(call)
        val albumId = call.argument<String>("albumId")
        val offset = call.argument<Int>("offset") ?: 0
        val limit = call.argument<Int>("limit") ?: 50
        onLibrary(result) { context ->
            MediaStoreReader.fetchMedia(context, types, albumId, offset, limit)
        }
    }

    private fun loadThumbnail(
        call: MethodCall,
        result: Result
    ) {
        val id = call.argument<String>("id")
        if (id == null) {
            result.error(NOT_FOUND, "loadThumbnail needs an asset id.", null)
            return
        }
        val width = call.argument<Int>("width") ?: 256
        val height = call.argument<Int>("height") ?: 256
        val quality = call.argument<Int>("quality") ?: 80
        onLibrary(result) { context ->
            MediaStoreReader.loadThumbnail(context, id, width, height, quality)
        }
    }

    private fun resolveFile(
        call: MethodCall,
        result: Result
    ) {
        val id = call.argument<String>("id")
        if (id == null) {
            result.error(NOT_FOUND, "resolveFile needs an asset id.", null)
            return
        }
        // A null path crosses the channel as notFound, which is what a missing asset is.
        onLibrary(result) { context -> MediaStoreReader.resolveFile(context, id) }
    }

    private fun fetchDocuments(
        call: MethodCall,
        result: Result
    ) {
        val mimeTypes = call.argument<List<String>>("mimeTypes") ?: emptyList()
        val offset = call.argument<Int>("offset") ?: 0
        val limit = call.argument<Int>("limit") ?: 50
        onLibrary(result) { context ->
            MediaStoreReader.fetchDocuments(context, mimeTypes, offset, limit)
        }
    }

    /**
     * Opens the Storage Access Framework picker.
     *
     * Browsing storage ourselves would mean re-implementing the file manager, and the picked
     * URIs are copied into the cache because a SAF grant is not a path.
     */
    private fun pickDocuments(
        call: MethodCall,
        result: Result
    ) {
        val activity = activity
        if (activity == null) {
            result.error(UNSUPPORTED, "Picking documents needs a foreground activity.", null)
            return
        }
        if (pendingDocuments != null) {
            result.error(UNKNOWN, "A document picker is already open.", null)
            return
        }
        val mimeTypes = call.argument<List<String>>("mimeTypes") ?: emptyList()
        val allowMultiple = call.argument<Boolean>("allowMultiple") ?: true
        val intent =
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = if (mimeTypes.size == 1) mimeTypes.first() else "*/*"
                if (mimeTypes.size > 1) {
                    putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
                }
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, allowMultiple)
            }
        pendingDocuments = result
        try {
            activity.startActivityForResult(intent, DOCUMENT_REQUEST_CODE)
        } catch (error: ActivityNotFoundException) {
            pendingDocuments = null
            result.error(UNSUPPORTED, "This device has no document picker.", null)
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ): Boolean {
        if (requestCode != DOCUMENT_REQUEST_CODE) return false
        val result = pendingDocuments ?: return false
        pendingDocuments = null
        val context = context
        if (resultCode != Activity.RESULT_OK || data == null || context == null) {
            // Backing out of the picker is a normal outcome, not a failure.
            result.success(emptyList<String>())
            return true
        }
        val uris = mutableListOf<Uri>()
        data.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                uris.add(clip.getItemAt(index).uri)
            }
        }
        data.data?.let { uris.add(it) }
        worker.execute {
            val paths = uris.mapNotNull { uri -> runCatching { MediaStoreReader.copyToCache(context, uri) }.getOrNull() }
            main.post { result.success(paths) }
        }
        return true
    }

    /**
     * Runs a library read off the platform thread and replies on it.
     *
     * A SecurityException here means the grant was revoked while the sheet was open, which is a
     * permission problem rather than an I/O one.
     */
    private fun onLibrary(
        result: Result,
        work: (Context) -> Any?
    ) {
        val context = context
        if (context == null) {
            result.error(UNSUPPORTED, "The plugin is not attached to an engine.", null)
            return
        }
        worker.execute {
            try {
                val value = work(context)
                main.post { result.success(value) }
            } catch (error: SecurityException) {
                main.post {
                    result.error(
                        PERMISSION_DENIED,
                        error.message ?: "The media library is not readable.",
                        null
                    )
                }
            } catch (error: Exception) {
                main.post {
                    result.error(
                        IO_ERROR,
                        error.message ?: "The media library could not be read.",
                        null
                    )
                }
            }
        }
    }

    private companion object {
        const val CHANNEL = "com.kedtec.browse_files_flutter/methods"
        const val PERMISSION_REQUEST_CODE = 0xBF17
        const val DOCUMENT_REQUEST_CODE = 0xBF18

        const val PREFS = "com.kedtec.browse_files_flutter"
        const val KEY_ASKED = "hasAskedForMediaAccess"

        const val IMAGE = "image"
        const val VIDEO = "video"
        val ALL_TYPES = setOf(IMAGE, VIDEO)

        // MediaPermissionStatus on the Dart side.
        const val GRANTED = "granted"
        const val LIMITED = "limited"
        const val DENIED = "denied"
        const val PERMANENTLY_DENIED = "permanentlyDenied"
        const val NOT_DETERMINED = "notDetermined"

        // BrowseFilesErrorCode on the Dart side.
        const val PERMISSION_DENIED = "permissionDenied"
        const val NOT_FOUND = "notFound"
        const val IO_ERROR = "ioError"
        const val UNSUPPORTED = "unsupported"
        const val UNKNOWN = "unknown"
    }
}
