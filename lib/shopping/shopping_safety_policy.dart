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
    '酒精飲料',
    '烈酒',
    '大麻',
    'thc',
    'cbd',
    '迷幻蘑菇',
    '毒品',
    '手槍',
    '步槍',
    '子彈',
    '彈藥',
    '槍械',
    'taser',
    '電擊棒',
    '胡椒噴霧',
    'pepper spray',
    '戰術刀',
    '彈簧刀',
    'switchblade',
    '蝴蝶刀',
    '開山刀',
    '賭博',
    '投注',
    'casino',
    'sportsbook',
    '運彩',
    '博弈',
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
