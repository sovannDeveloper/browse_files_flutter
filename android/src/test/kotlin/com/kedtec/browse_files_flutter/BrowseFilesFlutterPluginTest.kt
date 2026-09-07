package com.kedtec.browse_files_flutter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

/*
 * Run these from `example/android/` with `./gradlew testDebugUnitTest`, or from an IDE
 * that supports JUnit.
 */
internal class BrowseFilesFlutterPluginTest {
    @Test
    fun onMethodCall_unknownMethod_reportsNotImplemented() {
        val plugin = BrowseFilesFlutterPlugin()

        val call = MethodCall("nothingLikeThis", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).notImplemented()
    }
}
