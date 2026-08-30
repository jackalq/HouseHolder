import 'dart:convert';
import 'dart:io';

/// Small hierarchical JSON document store used by HouseHolder.
class JsonDocumentRepository {
  JsonDocumentRepository(this.rootDirectory);

  final Directory rootDirectory;

  Future<Map<String, Object?>?> readObject(String relativePath) async {
    final text = await readText(relativePath);
    if (text == null) return null;
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object.');
    }
    return decoded;
  }

  Future<List<Map<String, Object?>>> readJsonLines(String relativePath) async {
    final file = _file(relativePath);
    if (!await file.exists()) return const [];
    final result = <Map<String, Object?>>[];
    await for (final line in file.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, Object?>) {
        throw FormatException('Expected JSON object line in $relativePath.');
      }
      result.add(decoded);
    }
    return result;
  }

  Future<String?> readText(String relativePath) async {
    final file = _file(relativePath);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> writeObject(String relativePath, Map<String, Object?> object) =>
      writeText(relativePath, jsonEncode(object));

  Future<void> writeText(String relativePath, String text) async {
    final file = _file(relativePath);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(text, flush: true);
    await temporary.rename(file.path);
  }

  Future<void> appendJsonLine(String relativePath, Map<String, Object?> object) async {
    final file = _file(relativePath);
    await file.parent.create(recursive: true);
    await file.writeAsString('${jsonEncode(object)}\n', mode: FileMode.append, flush: true);
  }

  Future<List<String>> listFiles(String relativeDirectory) async {
    final directory = _directory(relativeDirectory);
    if (!await directory.exists()) return const [];
    final result = <String>[];
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(rootDirectory.path.length + 1).replaceAll('\\', '/');
      result.add(relative);
    }
    result.sort();
    return result;
  }

  File _file(String relativePath) {
    _validate(relativePath);
    return File('${rootDirectory.path}/$relativePath');
  }

  Directory _directory(String relativePath) {
    _validate(relativePath);
    return Directory('${rootDirectory.path}/$relativePath');
  }

  void _validate(String relativePath) {
    if (relativePath.startsWith('/') || relativePath.contains('..')) {
      throw ArgumentError.value(relativePath, 'relativePath', 'Unsafe path');
    }
  }
}
