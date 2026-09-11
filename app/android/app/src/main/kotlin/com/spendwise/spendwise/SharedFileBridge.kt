package com.spendwise.spendwise

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns

/**
 * Turns a statement handed to the app by another app into ordinary files the
 * Dart side can read.
 *
 * Android delivers a shared document as a `content://` URI, not a path. The
 * URI is readable only while the granting intent is alive, and only by this
 * process — so each one is copied into the app's own cache directory up front
 * rather than held as a reference that expires halfway through an import.
 *
 * Nothing here parses or inspects the file. It is copied, named, and handed
 * over; deciding whether it is a statement at all is the reader's job.
 */
object SharedFileBridge {

    /** Paths waiting to be picked up by the Dart side. */
    private val pending = mutableListOf<String>()

    private val allowedExtensions = setOf("pdf", "csv", "txt")

    /**
     * Records whatever [intent] is offering, if anything.
     *
     * Safe to call for every intent the activity sees: an ordinary launch
     * carries no document and adds nothing.
     */
    fun accept(context: Context, intent: Intent?) {
        if (intent == null) return

        val uris: List<Uri> = when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> listOfNotNull(
                intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri,
            )
            Intent.ACTION_SEND_MULTIPLE ->
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    ?.filterNotNull()
                    ?: emptyList()
            else -> emptyList()
        }

        for (uri in uris) {
            val path = copyToCache(context, uri)
            // Re-sharing the same file twice should not queue it twice.
            if (path != null && !pending.contains(path)) pending.add(path)
        }
    }

    /** Whether anything is waiting, without taking it. */
    fun hasPending(): Boolean = pending.isNotEmpty()

    /** Hands over everything waiting and clears the queue. */
    fun drain(): List<String> {
        val taken = pending.toList()
        pending.clear()
        return taken
    }

    /**
     * Copies [uri] into cache, keeping the original file name where the
     * provider offers one.
     *
     * The name matters: the importer decides how to read a file from its
     * extension, and a document copied to a name with no extension would be
     * read as a CSV and rejected.
     */
    private fun copyToCache(context: Context, uri: Uri): String? {
        val name = displayName(context, uri) ?: "statement"
        val extension = name.substringAfterLast('.', "").lowercase()
        val safeName = if (extension in allowedExtensions) {
            name
        } else {
            // Fall back to the MIME type rather than refusing outright: some
            // providers hand over a name with no extension at all.
            val guessed = when (context.contentResolver.getType(uri)) {
                "application/pdf" -> "pdf"
                "text/csv", "text/comma-separated-values" -> "csv"
                "text/plain" -> "txt"
                else -> return null
            }
            "${name.substringBeforeLast('.', name)}.$guessed"
        }

        val directory = java.io.File(context.cacheDir, "shared_statements")
        directory.mkdirs()
        val target = java.io.File(directory, sanitise(safeName))

        return try {
            context.contentResolver.openInputStream(uri).use { input ->
                if (input == null) return null
                target.outputStream().use { output -> input.copyTo(output) }
            }
            target.absolutePath
        } catch (_: java.io.IOException) {
            null
        } catch (_: SecurityException) {
            // The grant expired, or was never ours to read.
            null
        }
    }

    private fun displayName(context: Context, uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        return try {
            context.contentResolver.query(uri, null, null, null, null)
                ?.use { cursor ->
                    val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (column >= 0 && cursor.moveToFirst()) {
                        cursor.getString(column)
                    } else {
                        null
                    }
                }
        } catch (_: Exception) {
            null
        }
    }

    /** Keeps a provider-supplied name from escaping the cache directory. */
    private fun sanitise(name: String): String =
        name.replace(Regex("""[\\/:*?"<>|]"""), "_").takeLast(120)
}
