import 'package:flutter_test/flutter_test.dart';
import 'package:family_butler/storage/hash_service.dart';

void main() {
  const hashes = HashService();

  test('same semantic object hashes identically despite key order', () {
    final first = <String, Object?>{
      'subject': '國語',
      'dayOfWeek': 1,
      'meta': {'teacher': '王老師', 'room': '201'},
    };
    final second = <String, Object?>{
      'meta': {'room': '201', 'teacher': '王老師'},
      'dayOfWeek': 1,
      'subject': '國語',
    };

    expect(hashes.contentHash(first), hashes.contentHash(second));
  });

  test('changed business value changes hash', () {
    final first = <String, Object?>{'quantity': 1};
    final second = <String, Object?>{'quantity': 2};

    expect(hashes.contentHash(first), isNot(hashes.contentHash(second)));
  });
}
