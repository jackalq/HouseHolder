import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'canonical_json.dart';

class HashService {
  const HashService();

  String contentHash(Map<String, Object?> data) {
    final canonical = CanonicalJson.encode(data);
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}
