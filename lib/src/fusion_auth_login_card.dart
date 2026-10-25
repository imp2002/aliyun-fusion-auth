import 'dart:ui';

/// Optional iOS SDK authorization card, positioned in Flutter logical pixels.
///
/// This styles the vendor's authorization UI; it does not expose the masked
/// number or bypass the carrier's authorization button and agreements.
class FusionAuthLoginCard {
  final Rect frame;
  final Color backgroundColor;
  final Color primaryColor;
  final Color textColor;
  final Color secondaryTextColor;
  final double textScale;

  /// Text shown inside the one-click authorization button.
  final String title;

  const FusionAuthLoginCard({
    required this.frame,
    required this.backgroundColor,
    required this.primaryColor,
    required this.textColor,
    required this.secondaryTextColor,
    this.textScale = 1,
    this.title = '本机号码一键登录',
  });

  bool get isValid =>
      [frame.left, frame.top, frame.width, frame.height, textScale]
          .every((value) => value.isFinite) &&
      frame.left >= 0 &&
      frame.top >= 0 &&
      frame.width >= 240 &&
      frame.height >= 400 &&
      textScale >= 1 &&
      textScale <= 1.5 &&
      title.trim().isNotEmpty;

  Map<String, Object> toMap() => {
        'x': frame.left,
        'y': frame.top,
        'width': frame.width,
        'height': frame.height,
        'backgroundColor': _argb(backgroundColor),
        'primaryColor': _argb(primaryColor),
        'textColor': _argb(textColor),
        'secondaryTextColor': _argb(secondaryTextColor),
        'textScale': textScale,
        'title': title,
      };

  // Keep compatibility with the package's Flutter 3.19 minimum.
  static int _argb(Color color) => color.value; // ignore: deprecated_member_use
}
