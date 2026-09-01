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
}
