package com.navivibe.navivibe

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/**
 * Serves cover art to the car host, which can neither fetch an authenticated
 * server URL nor read app-private files.
 *   content://<authority>/net?u=<https cover-art url>
 *   content://<authority>/file?p=<file under the app's own storage>
 * Only cover-art URLs and files inside the app's own data are served.
 */
class ArtworkProvider : ContentProvider() {
    override fun onCreate() = true

    override fun getType(uri: Uri): String = "image/*"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val ctx = context ?: throw FileNotFoundException()
        val file: File? = when (uri.path) {
            "/net" -> uri.getQueryParameter("u")
                ?.takeIf { it.contains("getCoverArt") }
                ?.let { ArtCache.fetch(ctx, it) }
            "/file" -> uri.getQueryParameter("p")?.let { File(it).canonicalFile }
                ?.takeIf { isOwnArtFile(ctx, it) }
            else -> null
        }
        if (file == null || !file.exists()) throw FileNotFoundException(uri.toString())
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    /** Inside the Flutter documents dir or the cache — never prefs, databases or keys. */
    private fun isOwnArtFile(ctx: android.content.Context, f: File): Boolean {
        val roots = listOf(File(ctx.dataDir, "app_flutter").canonicalFile, ctx.cacheDir.canonicalFile)
        return roots.any { f.path.startsWith(it.path + File.separator) }
    }

    override fun query(u: Uri, p: Array<String>?, s: String?, a: Array<String>?, o: String?): Cursor? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun update(uri: Uri, values: ContentValues?, s: String?, a: Array<String>?) = 0
    override fun delete(uri: Uri, s: String?, a: Array<String>?) = 0
}
