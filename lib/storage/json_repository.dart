import 'dart:convert';
import 'dart:io';

/// Small hierarchical JSON document store used by the Android MVP.
///
/// The root directory is injected by platform bootstrap code. This keeps the
/// storage format independent from Android/iOS path APIs and makes the format
/// easy to synchronize later.
class JsonDocumentRepository {
  JsonDocumentRepository(this.rootDirectory);

  final Directory rootDirectory;

  Future<Map<String, Object?>?> readObject(String relativePath) async {
    final file = _file(relativePath);
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected a JSON object.');
    }
    return decoded;
  }

  Future<List<Map<String, Object?>>> readJsonLines(String relativePath) async {
    final file = _file(relativePath);
    if (!await file.exists()) return const [];

    final result = <Map<String, Object?>>[];
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, Object?>) {
        throw FormatException('Expected JSON object line in $relativePath.');
      }
      result.add(decoded);
    }
    return result;
  }

  Future<void> writeObject(
    String relativePath,
    Map<String, Object?> object,
  ) async {
    final file = _file(relativePath);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(object), flush: true);
    await temporary.rename(file.path);
  }

  Future<void> appendJsonLine(
    String relativePath,
    Map<String, Object?> object,
  ) async {
    final file = _file(relativePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(object)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  File _file(String relativePath) {
    if (relativePath.startsWith('/') || relativePath.contains('..')) {
      throw ArgumentError.value(relativePath, 'relativePath', 'Unsafe path');
    }
    return File('${rootDirectory.path}/$relativePath');
  }
}
