import 'dart:convert';

/// Produces a stable JSON representation by recursively sorting object keys.
///
/// Hashing is deliberately separated from this class so the storage layer can
/// use a platform/crypto implementation of SHA-256 without coupling the data
/// model to one package.
class CanonicalJson {
  const CanonicalJson._();

  static String encode(Object? value) => jsonEncode(_normalize(value));

  static Object? _normalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _normalize(value[key]),
      };
    }
    if (value is List) {
      return value.map(_normalize).toList(growable: false);
    }
    return value;
  }
}
