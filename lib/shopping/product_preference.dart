class ProductPreference {
  const ProductPreference({
    this.requiredTerms = const [],
    this.excludedTerms = const [],
    this.preferredTerms = const [],
    this.preferredMerchants = const [],
  });

  final List<String> requiredTerms;
  final List<String> excludedTerms;
  final List<String> preferredTerms;
  final List<String> preferredMerchants;

  bool get isEmpty => requiredTerms.isEmpty && excludedTerms.isEmpty && preferredTerms.isEmpty && preferredMerchants.isEmpty;

  factory ProductPreference.fromJson(Map<String, Object?> json) => ProductPreference(
        requiredTerms: _strings(json['requiredTerms']),
        excludedTerms: _strings(json['excludedTerms']),
        preferredTerms: _strings(json['preferredTerms']),
        preferredMerchants: _strings(json['preferredMerchants']),
      );

  Map<String, Object?> toJson() => {
        if (requiredTerms.isNotEmpty) 'requiredTerms': requiredTerms,
        if (excludedTerms.isNotEmpty) 'excludedTerms': excludedTerms,
        if (preferredTerms.isNotEmpty) 'preferredTerms': preferredTerms,
        if (preferredMerchants.isNotEmpty) 'preferredMerchants': preferredMerchants,
      };

  bool accepts(String title) {
    final normalized = title.toLowerCase();
    if (excludedTerms.any((term) => normalized.contains(term.toLowerCase()))) return false;
    return requiredTerms.every((term) => normalized.contains(term.toLowerCase()));
  }

  int score({required String title, required String merchantId, required String merchantName}) {
    final normalized = title.toLowerCase();
    var result = 0;
    for (final term in preferredTerms) {
      if (normalized.contains(term.toLowerCase())) result += 10;
    }
    final merchant = '$merchantId $merchantName'.toLowerCase();
    for (final term in preferredMerchants) {
      if (merchant.contains(term.toLowerCase())) result += 4;
    }
    return result;
  }

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList(growable: false);
  }
}
