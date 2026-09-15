package com.kedtec.browse_files_flutter

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import android.os.Handler
import android.os.Looper

/**
 * Android side of `browse_files_flutter`.
 *
 * Media access on Android 13+ goes through the system Photo Picker
 * (`MediaStore.ACTION_PICK_IMAGES`), which deliberately does not require any
 * `READ_MEDIA_*` permission — that is the whole reason the picker exists, and
 * why apps that just want to attach a photo can ship without those
 * permissions on Google Play.
 *
 * Below API 33 the picker falls back to `ACTION_GET_CONTENT` with the
 * appropriate MIME types, which has worked without permissions since Android
 * 1.0.
 *
 * Documents still go through the Storage Access Framework
 * (`ACTION_OPEN_DOCUMENT`). SAF never required a media permission either.
 *
 * The camera is the system camera app (`ACTION_IMAGE_CAPTURE` / `ACTION_VIDEO_CAPTURE`)
 * writing into this app's cache through [BrowseFilesFileProvider], so a capture needs no
 * CAMERA or storage permission and comes back as a `file://` id that is already resolved.
 * The one exception: a host app that declares `CAMERA` itself makes the intent require it,
 * so `requestCameraPermission` (and `captureMedia` before it opens the camera) prompts for
 * it in that case only.
 *
 * Errors come back as `result.error(code, message, details)` with a code from
 * `BrowseFilesErrorCode`: `permissionDenied`, `userCanceled`, `notFound`,
 * `ioError`, `unsupported`.
 */
class BrowseFilesFlutterPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodCallHandler,
    ActivityResultListener,
    RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    /** The reply waiting on the system media picker. */
    private var pendingMedia: Result? = null

    /** The reply waiting on the system document picker. */
    private var pendingDocuments: Result? = null

    /** The reply waiting on the camera, and the file the camera was told to write. */
    private var pendingCapture: Result? = null
    private var captureTarget: File? = null
    private var captureIsVideo: Boolean = false

    /** What to do with the answer to the CAMERA prompt, once the user gives one. */
    private var pendingPermission: ((String) -> Unit)? = null

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
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
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
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "pickMedia" -> pickMedia(typesOf(call), allowMultipleOf(call), result)
            "loadThumbnail" -> loadThumbnail(call, result)
            "resolveFile" -> resolveFile(call, result)
            "pickDocuments" -> pickDocuments(call, result)
            "captureMedia" -> captureMedia(call, result)
            "requestCameraPermission" -> requestCameraPermission(result)
            else -> result.notImplemented()
        }
    }

    /**
     * Opens the system media picker and returns what the user chose.
     *
     * On API 33+ this is the dedicated Photo Picker activity; below that we fall
     * back to `ACTION_GET_CONTENT`, which has never required a permission.
     */
    private fun pickMedia(
        types: Set<String>,
        allowMultiple: Boolean,
        result: Result
    ) {
        val activity = activity
        if (activity == null) {
            result.error(
                UNSUPPORTED,
                "Picking media needs a foreground activity.",
                null
            )
            return
        }
        if (pendingMedia != null) {
            result.error(UNKNOWN, "A media picker is already open.", null)
            return
        }
        pendingMedia = result
        try {
            activity.startActivityForResult(pickerIntent(types, allowMultiple), MEDIA_REQUEST_CODE)
        } catch (error: ActivityNotFoundException) {
            pendingMedia = null
            result.error(UNSUPPORTED, "This device has no media picker.", null)
        }
    }

    private fun pickerIntent(types: Set<String>, allowMultiple: Boolean): Intent {
        val mimeTypes = mimeTypesOf(types)
        val intent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                    // The Photo Picker filters on `type`, one family at a time; it only learnt
                    // EXTRA_MIME_TYPES with Android 14. Left unset it shows photos and videos.
                    if (mimeTypes.size == 1 && mimeTypes.first() != "*/*") {
                        type = mimeTypes.first()
                    }
                    // Multi-select is a count, not a flag: without EXTRA_PICK_IMAGES_MAX the
                    // picker allows exactly one item.
                    if (allowMultiple) {
                        putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, MediaStore.getPickImagesMaxLimit())
                    }
                }
            } else {
                Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = if (mimeTypes.size == 1) mimeTypes.first() else "*/*"
                    if (mimeTypes.size > 1) {
                        putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes)
                    }
                    if (allowMultiple) {
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    }
                    addCategory(Intent.CATEGORY_OPENABLE)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            }
        return intent
    }

    private fun mimeTypesOf(types: Set<String>): Array<String> {
        val list = mutableListOf<String>()
        if (IMAGE in types) list.add("image/*")
        if (VIDEO in types) list.add("video/*")
        if (list.isEmpty()) list.add("*/*")
        return list.toTypedArray()
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
        onWorker(result) { context ->
            MediaStoreReader.loadThumbnail(context, Uri.parse(id), width, height, quality)
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
        onWorker(result) { context -> MediaStoreReader.copyToCache(context, Uri.parse(id)) }
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

    /**
     * Opens the system camera for a photo or a video.
     *
     * The capture goes into the plugin's cache directory through the FileProvider rather
     * than into the user's library: no storage permission, nothing left behind in the
     * gallery, and the id handed back is already a file the host app owns.
     */
    private fun captureMedia(
        call: MethodCall,
        result: Result
    ) {
        val activity = activity
        val context = context
        if (activity == null || context == null) {
            result.error(UNSUPPORTED, "Opening the camera needs a foreground activity.", null)
            return
        }
        if (pendingCapture != null) {
            result.error(UNKNOWN, "The camera is already open.", null)
            return
        }
        if (pendingPermission != null) {
            result.error(UNKNOWN, "The camera permission prompt is already open.", null)
            return
        }
        val isVideo = call.argument<String>("type") == VIDEO
        // Ask first when the host manifest makes the intent require CAMERA, so a direct
        // caller gets the prompt rather than the SecurityException below.
        ensureCameraPermission(activity) { status ->
            if (status != GRANTED) {
                result.error(
                    PERMISSION_DENIED,
                    "Camera access was refused; it can be turned on in Settings.",
                    status
                )
                return@ensureCameraPermission
            }
            startCapture(activity, context, isVideo, result)
        }
    }

    private fun startCapture(
        activity: Activity,
        context: Context,
        isVideo: Boolean,
        result: Result
    ) {
        val target =
            File(MediaStoreReader.cacheDirectory(context), captureName(isVideo))
        val uri =
            FileProvider.getUriForFile(context, "${context.packageName}$PROVIDER_SUFFIX", target)
        val intent =
            Intent(if (isVideo) MediaStore.ACTION_VIDEO_CAPTURE else MediaStore.ACTION_IMAGE_CAPTURE)
                .putExtra(MediaStore.EXTRA_OUTPUT, uri)
                .addFlags(
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
        pendingCapture = result
        captureTarget = target
        captureIsVideo = isVideo
        try {
            activity.startActivityForResult(intent, CAPTURE_REQUEST_CODE)
        } catch (error: ActivityNotFoundException) {
            clearCapture()
            result.error(UNSUPPORTED, "This device has no camera app.", null)
        } catch (error: SecurityException) {
            // A host app that declares CAMERA but has not been granted it lands here: once
            // the permission is declared, the camera intent starts requiring it.
            clearCapture()
            result.error(PERMISSION_DENIED, error.message ?: "The camera may not be opened.", null)
        }
    }

    /**
     * Reports whether the camera may be opened, prompting for CAMERA first if the host app
     * declares it and the user has not answered yet.
     *
     * The plugin itself declares no CAMERA permission — the capture intent needs none — but
     * once the host manifest declares it, the intent refuses to start until it is granted.
     * Without the declaration there is nothing to ask for and the answer is `granted`.
     */
    private fun requestCameraPermission(result: Result) {
        val activity = activity
        if (activity == null) {
            result.error(UNSUPPORTED, "Asking for the camera needs a foreground activity.", null)
            return
        }
        if (pendingPermission != null) {
            result.error(UNKNOWN, "The camera permission prompt is already open.", null)
            return
        }
        ensureCameraPermission(activity) { status -> result.success(status) }
    }

    private fun ensureCameraPermission(activity: Activity, onStatus: (String) -> Unit) {
        if (!declaresCameraPermission(activity)) {
            onStatus(GRANTED)
            return
        }
        if (
            ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            onStatus(GRANTED)
            return
        }
        pendingPermission = onStatus
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.CAMERA),
            PERMISSION_REQUEST_CODE
        )
    }

    /** Whether the host app's merged manifest lists `CAMERA` at all. */
    private fun declaresCameraPermission(context: Context): Boolean {
        val declared =
            try {
                context.packageManager
                    .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
                    .requestedPermissions
            } catch (error: PackageManager.NameNotFoundException) {
                null
            }
        return declared?.contains(Manifest.permission.CAMERA) == true
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val onStatus = pendingPermission ?: return true
        pendingPermission = null
        val granted =
            grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        val status =
            when {
                granted -> GRANTED
                // No rationale to show after a refusal means "don't ask again" (or a
                // policy): only Settings can turn it back on.
                activity?.let {
                    ActivityCompat.shouldShowRequestPermissionRationale(
                        it,
                        Manifest.permission.CAMERA
                    )
                } == true -> DENIED
                else -> PERMANENTLY_DENIED
            }
        onStatus(status)
        return true
    }

    private fun captureName(isVideo: Boolean): String =
        "capture_${System.currentTimeMillis()}.${if (isVideo) "mp4" else "jpg"}"

    private fun clearCapture() {
        pendingCapture = null
        captureTarget = null
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ): Boolean = when (requestCode) {
        MEDIA_REQUEST_CODE -> handleMediaResult(resultCode, data)
        DOCUMENT_REQUEST_CODE -> handleDocumentResult(resultCode, data)
        CAPTURE_REQUEST_CODE -> handleCaptureResult(resultCode, data)
        else -> false
    }

    /**
     * Describes the capture, or answers null when the user backed out.
     *
     * Some camera apps ignore `EXTRA_OUTPUT` for video and hand the clip back as `data.data`
     * instead; that copy is pulled into the target file so the reply is the same either way.
     */
    private fun handleCaptureResult(resultCode: Int, data: Intent?): Boolean {
        val result = pendingCapture ?: return false
        val target = captureTarget
        val isVideo = captureIsVideo
        clearCapture()
        val context = context
        if (resultCode != Activity.RESULT_OK || target == null || context == null) {
            target?.delete()
            result.success(null)
            return true
        }
        val fallback = data?.data
        worker.execute {
            val described =
                runCatching {
                    if (target.length() == 0L && fallback != null) {
                        context.contentResolver.openInputStream(fallback)?.use { input ->
                            target.outputStream().use { output -> input.copyTo(output) }
                        }
                    }
                    if (target.length() == 0L) null else MediaStoreReader.describeFile(target, isVideo)
                }.getOrNull()
            if (described == null) target.delete()
            main.post { result.success(described) }
        }
        return true
    }

    /**
     * Pulls the URIs out of the picker, describes each one on a worker, and answers
     * with the list — or an empty list when the user backed out.
     */
    private fun handleMediaResult(resultCode: Int, data: Intent?): Boolean {
        val result = pendingMedia ?: return false
        pendingMedia = null
        val context = context
        if (context == null) {
            result.error(UNSUPPORTED, "The plugin is not attached to an engine.", null)
            return true
        }
        if (resultCode != Activity.RESULT_OK || data == null) {
            // Backing out of the picker is a normal outcome, not a failure.
            result.success(emptyList<Map<String, Any?>>())
            return true
        }
        val uris = collectUris(data)
        worker.execute {
            val described =
                uris.mapNotNull { uri ->
                    runCatching { MediaStoreReader.describe(context, uri) }.getOrNull()
                }
            main.post { result.success(described) }
        }
        return true
    }

    private fun handleDocumentResult(resultCode: Int, data: Intent?): Boolean {
        val result = pendingDocuments ?: return false
        pendingDocuments = null
        val context = context
        if (resultCode != Activity.RESULT_OK || data == null || context == null) {
            // Backing out of the picker is a normal outcome, not a failure.
            result.success(emptyList<String>())
            return true
        }
        val uris = collectUris(data)
        worker.execute {
            val paths =
                uris.mapNotNull { uri ->
                    runCatching { MediaStoreReader.copyToCache(context, uri) }.getOrNull()
                }
            main.post { result.success(paths) }
        }
        return true
    }

    /**
     * Extracts every URI from a picker result.
     *
     * The single-selection case lives in `data.data`; multi-selection puts each
     * URI on a separate `ClipData.Item`. The Photo Picker can also leave the
     * URI on `Intent.EXTRA_STREAM` for some flows, and Android 14+ may report
     * `ClipData` even for a single pick — every plausible source is checked.
     */
    private fun collectUris(data: Intent): List<Uri> {
        val uris = LinkedHashSet<Uri>()
        data.clipData?.let { clip ->
            // Not `getItemAt(0)` unguarded: an empty ClipData throws on it.
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let { uris.add(it) }
            }
        }
        data.data?.let { uris.add(it) }
        val stream = data.extras?.get(Intent.EXTRA_STREAM) as? Uri
        if (stream != null) uris.add(stream)
        val streams = data.extras?.getParcelableArrayList<Uri>(Intent.EXTRA_STREAM)
        streams?.forEach { uris.add(it) }
        return uris.toList()
    }

    /**
     * Runs a worker task and replies on the main thread.
     *
     * A SecurityException here means the picker grant was lost while the worker
     * was using it; that is an I/O problem from the caller's point of view.
     */
    private fun onWorker(
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
                        IO_ERROR,
                        error.message ?: "The asset is no longer readable.",
                        null
                    )
                }
            } catch (error: Exception) {
                main.post {
                    result.error(
                        IO_ERROR,
                        error.message ?: "The asset could not be read.",
                        null
                    )
                }
            }
        }
    }

    private fun typesOf(call: MethodCall): Set<String> =
        call.argument<List<String>>("types")?.toSet() ?: ALL_TYPES

    private fun allowMultipleOf(call: MethodCall): Boolean =
        call.argument<Boolean>("allowMultiple") ?: true

    private companion object {
        const val CHANNEL = "com.kedtec.browse_files_flutter/methods"
        const val MEDIA_REQUEST_CODE = 0xBF19
        const val DOCUMENT_REQUEST_CODE = 0xBF18
        const val CAPTURE_REQUEST_CODE = 0xBF17
        const val PERMISSION_REQUEST_CODE = 0xBF16

        // OCCameraPermission on the Dart side.
        const val GRANTED = "granted"
        const val DENIED = "denied"
        const val PERMANENTLY_DENIED = "permanentlyDenied"

        /** Matches the authority declared in the plugin manifest. */
        const val PROVIDER_SUFFIX = ".browse_files_flutter.provider"

        const val IMAGE = "image"
        const val VIDEO = "video"
        val ALL_TYPES = setOf(IMAGE, VIDEO)

        // BrowseFilesErrorCode on the Dart side.
        const val PERMISSION_DENIED = "permissionDenied"
        const val NOT_FOUND = "notFound"
        const val IO_ERROR = "ioError"
        const val UNSUPPORTED = "unsupported"
        const val UNKNOWN = "unknown"
    }
}
