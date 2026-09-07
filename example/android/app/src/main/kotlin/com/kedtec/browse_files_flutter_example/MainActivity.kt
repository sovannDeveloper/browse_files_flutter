package com.kedtec.browse_files_flutter_example

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The host app's half of the attachment sheet's camera cell.
 *
 * browse_files_flutter carries no camera, so this shells out to whatever camera app is
 * installed. The shot is written into a MediaStore row this app creates up front, which means
 * the id handed back to Dart is an ordinary library id the plugin can resolve — and the photo
 * shows up in the sheet's grid like any other.
 *
 * No CAMERA permission is declared: ACTION_IMAGE_CAPTURE needs none, and declaring it would
 * turn it into something the user has to grant first.
 */
class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingUri: Uri? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capture" -> capture(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun capture(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "The camera is already open.", null)
            return
        }
        val values =
            ContentValues().apply {
                put(
                    MediaStore.Images.Media.DISPLAY_NAME,
                    "capture_${System.currentTimeMillis()}.jpg"
                )
                put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            }
        val uri =
            contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
        if (uri == null) {
            result.error("ioError", "Could not make room for the photo.", null)
            return
        }
        val intent =
            Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                .putExtra(MediaStore.EXTRA_OUTPUT, uri)
                .addFlags(
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
        pendingResult = result
        pendingUri = uri
        try {
            startActivityForResult(intent, CAPTURE_REQUEST)
        } catch (error: ActivityNotFoundException) {
            clearPending()
            contentResolver.delete(uri, null, null)
            result.error("unsupported", "This device has no camera app.", null)
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CAPTURE_REQUEST) return
        val result = pendingResult ?: return
        val uri = pendingUri
        clearPending()
        if (resultCode != Activity.RESULT_OK || uri == null) {
            // Backing out would otherwise leave an empty row in the library.
            uri?.let { contentResolver.delete(it, null, null) }
            result.success(null)
            return
        }
        result.success(uri.lastPathSegment)
    }

    private fun clearPending() {
        pendingResult = null
        pendingUri = null
    }

    private companion object {
        const val CHANNEL = "com.kedtec.browse_files_flutter_example/camera"
        const val CAPTURE_REQUEST = 0xCA
    }
}
