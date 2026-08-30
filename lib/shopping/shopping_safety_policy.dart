class ShoppingSafetyPolicy {
  const ShoppingSafetyPolicy();

  static const _blockedTerms = <String>[
    '電子煙',
    '香菸',
    '煙彈',
    'vape',
    'nicotine',
    '尼古丁',
    '啤酒',
    '威士忌',
    '伏特加',
    'wine',
    'beer',
    '大麻',
    'thc',
    'cbd',
    '迷幻蘑菇',
    '手槍',
    '步槍',
    '子彈',
    '彈藥',
    'taser',
    '電擊棒',
    '戰術刀',
    '彈簧刀',
    'switchblade',
    '賭博',
    '投注',
    'casino',
    'sportsbook',
  ];

  void ensureAllowed(String query) {
    final normalized = query.toLowerCase();
    for (final term in _blockedTerms) {
      if (normalized.contains(term.toLowerCase())) {
        throw UnsupportedError('此類商品不提供採購搜尋。');
      }
    }
  }
}
