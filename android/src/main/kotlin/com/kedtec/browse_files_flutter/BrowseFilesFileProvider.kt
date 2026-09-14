package com.kedtec.browse_files_flutter

import androidx.core.content.FileProvider

/**
 * The provider the camera app writes captures through.
 *
 * A subclass rather than `FileProvider` itself: two manifests declaring the same provider class
 * with different authorities fail to merge, and host apps often already have one.
 */
class BrowseFilesFileProvider : FileProvider()
