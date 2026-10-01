package com.mylanglean.app

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File

/**
 * Minimal read-only [ContentProvider] that exposes the downloaded update APK
 * to the system package installer.
 *
 * Implemented by hand instead of relying on androidx FileProvider so the app
 * keeps zero extra Gradle dependencies (the same constraint as the other
 * self-written plugins). The served file is the single fixed cache file used
 * by [MlUpdaterPlugin]; the URI path is intentionally ignored.
 *
 * Authority: `<applicationId>.updatefile`, URI: `content://.../apk`.
 */
class MlUpdateFileProvider : ContentProvider() {

    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = APK_MIME

    private fun apkFile(): File? {
        val ctx = context ?: return null
        return File(ctx.cacheDir, MlUpdaterPlugin.APK_NAME)
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        val file = apkFile() ?: return null
        if (!file.exists()) return null
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = apkFile()
        val columns = arrayOf(
            OpenableColumns.DISPLAY_NAME,
            OpenableColumns.SIZE,
        )
        val cursor = MatrixCursor(columns)
        cursor.addRow(
            arrayOf<Any?>(
                file?.name ?: MlUpdaterPlugin.APK_NAME,
                if (file?.exists() == true) file.length() else 0L,
            )
        )
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    companion object {
        const val APK_MIME = "application/vnd.android.package-archive"
    }
}
