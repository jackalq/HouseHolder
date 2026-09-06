package com.householder.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodChannel

/**
 * Narrow, user-selected sync-folder access through Android Storage Access Framework.
 *
 * The user can pick a Google Drive, local, or another DocumentsProvider folder.
 * HouseHolder only receives persisted read/write access to that selected tree.
 */
class SafSyncTree(private val activity: Activity) {
    companion object {
        const val PICK_TREE_REQUEST = 7301
        private const val PREFS = "householder_sync"
        private const val TREE_URI = "tree_uri"
    }

    private data class Child(val uri: Uri, val mimeType: String)

    private val resolver get() = activity.contentResolver
    private val preferences = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private var pendingPickResult: MethodChannel.Result? = null

    fun pickTree(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("SYNC_PICK_BUSY", "A sync folder picker is already open", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
        }
        activity.startActivityForResult(intent, PICK_TREE_REQUEST)
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_TREE_REQUEST) return false
        val callback = pendingPickResult
        pendingPickResult = null
        if (callback == null) return true
        if (resultCode != Activity.RESULT_OK) {
            callback.success(false)
            return true
        }

        val uri = data?.data
        if (uri == null) {
            callback.error("SYNC_TREE_MISSING", "No directory URI was returned", null)
            return true
        }

        val takeFlags = (data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
        try {
            resolver.takePersistableUriPermission(uri, takeFlags)
            preferences.edit().putString(TREE_URI, uri.toString()).apply()
            callback.success(true)
        } catch (error: Throwable) {
            callback.error(
                "SYNC_TREE_PERMISSION_FAILED",
                error.message ?: error.javaClass.simpleName,
                null,
            )
        }
        return true
    }

    fun status(): Map<String, Any?> {
        val tree = storedTreeUri() ?: return mapOf("configured" to false)
        val permission = resolver.persistedUriPermissions.firstOrNull { it.uri == tree }
        val configured = permission?.isReadPermission == true && permission.isWritePermission
        return mapOf(
            "configured" to configured,
            "uri" to tree.toString(),
            "displayName" to displayName(rootDocumentUri(tree)),
        )
    }

    fun clear(): Boolean {
        val tree = storedTreeUri() ?: return false
        val permission = resolver.persistedUriPermissions.firstOrNull { it.uri == tree }
        if (permission != null) {
            var flags = 0
            if (permission.isReadPermission) flags = flags or Intent.FLAG_GRANT_READ_URI_PERMISSION
            if (permission.isWritePermission) flags = flags or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            try {
                resolver.releasePersistableUriPermission(tree, flags)
            } catch (_: SecurityException) {
                // The provider may already have revoked the permission.
            }
        }
        preferences.edit().remove(TREE_URI).apply()
        return true
    }

    fun list(prefix: String): List<Map<String, Any?>> {
        validateRelativePath(prefix, allowEmpty = true)
        val tree = requireTree()
        val output = mutableListOf<Map<String, Any?>>()
        walk(tree, rootDocumentUri(tree), "", prefix, output)
        return output
    }

    fun readText(path: String): String {
        validateRelativePath(path)
        val tree = requireTree()
        val file = findPath(tree, path, create = false)
            ?: throw IllegalStateException("Sync object does not exist: $path")
        resolver.openInputStream(file).use { input ->
            requireNotNull(input) { "Unable to open sync object: $path" }
            return input.bufferedReader(Charsets.UTF_8).readText()
        }
    }

    fun writeText(path: String, content: String) {
        validateRelativePath(path)
        val tree = requireTree()
        val file = findPath(tree, path, create = true)
            ?: throw IllegalStateException("Unable to create sync object: $path")
        resolver.openOutputStream(file, "wt").use { output ->
            requireNotNull(output) { "Unable to write sync object: $path" }
            output.bufferedWriter(Charsets.UTF_8).use { writer ->
                writer.write(content)
                writer.flush()
            }
        }
    }

    private fun walk(
        tree: Uri,
        parent: Uri,
        parentPath: String,
        prefix: String,
        output: MutableList<Map<String, Any?>>,
    ) {
        val parentId = DocumentsContract.getDocumentId(parent)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        resolver.query(children, columns, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val modifiedIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (cursor.moveToNext()) {
                val id = cursor.getString(idIndex)
                val name = cursor.getString(nameIndex)
                val mime = cursor.getString(mimeIndex)
                val childUri = DocumentsContract.buildDocumentUriUsingTree(tree, id)
                val path = if (parentPath.isEmpty()) name else "$parentPath/$name"
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    walk(tree, childUri, path, prefix, output)
                } else if (path.startsWith(prefix)) {
                    val modified = if (modifiedIndex >= 0 && !cursor.isNull(modifiedIndex)) {
                        cursor.getLong(modifiedIndex)
                    } else null
                    output.add(
                        mapOf(
                            "path" to path,
                            "remoteId" to id,
                            "modifiedAtMillis" to modified,
                        )
                    )
                }
            }
        }
    }

    private fun findPath(tree: Uri, path: String, create: Boolean): Uri? {
        val parts = path.split('/').filter { it.isNotEmpty() }
        var parent = rootDocumentUri(tree)
        parts.forEachIndexed { index, part ->
            val last = index == parts.lastIndex
            val existing = findChild(tree, parent, part)
            if (existing != null) {
                if (!last && existing.mimeType != DocumentsContract.Document.MIME_TYPE_DIR) {
                    throw IllegalStateException("Path segment is not a directory: $part")
                }
                parent = existing.uri
                return@forEachIndexed
            }
            if (!create) return null
            parent = if (last) {
                DocumentsContract.createDocument(resolver, parent, "text/plain", part)
            } else {
                DocumentsContract.createDocument(
                    resolver,
                    parent,
                    DocumentsContract.Document.MIME_TYPE_DIR,
                    part,
                )
            } ?: throw IllegalStateException("Provider refused to create: $part")
        }
        return parent
    }

    private fun findChild(tree: Uri, parent: Uri, name: String): Child? {
        val parentId = DocumentsContract.getDocumentId(parent)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        resolver.query(children, columns, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (cursor.moveToNext()) {
                if (cursor.getString(nameIndex) != name) continue
                val id = cursor.getString(idIndex)
                return Child(
                    uri = DocumentsContract.buildDocumentUriUsingTree(tree, id),
                    mimeType = cursor.getString(mimeIndex),
                )
            }
        }
        return null
    }

    private fun displayName(uri: Uri): String? {
        val columns = arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
        resolver.query(uri, columns, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return null
    }

    private fun requireTree(): Uri {
        val tree = storedTreeUri() ?: throw IllegalStateException("No shared sync folder selected.")
        val permission = resolver.persistedUriPermissions.firstOrNull { it.uri == tree }
        if (permission?.isReadPermission != true || !permission.isWritePermission) {
            throw SecurityException("The shared sync folder permission is no longer valid.")
        }
        return tree
    }

    private fun storedTreeUri(): Uri? = preferences.getString(TREE_URI, null)?.let(Uri::parse)

    private fun rootDocumentUri(tree: Uri): Uri = DocumentsContract.buildDocumentUriUsingTree(
        tree,
        DocumentsContract.getTreeDocumentId(tree),
    )

    private fun validateRelativePath(path: String, allowEmpty: Boolean = false) {
        if (allowEmpty && path.isEmpty()) return
        require(path.isNotEmpty() && !path.startsWith('/') && !path.contains("..")) {
            "Unsafe sync path: $path"
        }
        require(path.split('/').none { it.isBlank() || it == "." || it == ".." }) {
            "Unsafe sync path: $path"
        }
    }
}
