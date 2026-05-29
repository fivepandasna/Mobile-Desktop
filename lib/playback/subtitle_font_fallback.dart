const List<String> kSubtitleFontFamilyFallback = <String>[
  'NotoSansCJK',
  'NotoSansSymbols2',
  'Noto Sans CJK JP',
  'Noto Sans CJK SC',
  'Noto Sans CJK KR',
  'Source Han Sans',
  'Noto Sans',
  'Roboto',
  'Arial Unicode MS',
  'Segoe UI Symbol',
  'Apple Color Emoji',
  'Noto Color Emoji',
  'Arial',
];

const String kWebSubtitleCjkFontFamily = 'MoonfinSubtitlesCJK';
const String kWebSubtitleSymbolsFontFamily = 'MoonfinSubtitlesSymbols';

String subtitleFontFamilyCssStack() {
  final families = <String>[
    kWebSubtitleCjkFontFamily,
    kWebSubtitleSymbolsFontFamily,
    ...kSubtitleFontFamilyFallback,
  ].map((family) => family.contains(' ') ? "'$family'" : family).join(', ');
  return '$families, sans-serif';
}
