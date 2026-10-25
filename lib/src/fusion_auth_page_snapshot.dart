import 'dart:typed_data';
import 'dart:ui';

/// An in-memory image of a retained iOS page, in Flutter logical coordinates.
/// Paint it inside the outgoing route before canceling native authentication.
/// Dispose decoded images on failure or route disposal; never persist the PNG.
class FusionAuthPageSnapshot {
  final Uint8List png;
  final Rect frame;

  const FusionAuthPageSnapshot({required this.png, required this.frame});
}
