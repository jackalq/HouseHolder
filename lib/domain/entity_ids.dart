import 'dart:math';

class EntityIds {
  EntityIds._();

  static final Random _random = Random.secure();

  static String generate(String prefix) {
    final safePrefix = prefix.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final time = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final randomA = _random.nextInt(0x7fffffff).toRadixString(36).padLeft(6, '0');
    final randomB = _random.nextInt(0x7fffffff).toRadixString(36).padLeft(6, '0');
    return '$safePrefix-$time-$randomA$randomB';
  }
}
