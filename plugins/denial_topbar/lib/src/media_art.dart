import 'dart:io';

import 'package:flutter/widgets.dart';

/// Cover art for the current track.
///
/// MPRIS hands the artwork over as `mpris:artUrl`, which the SDK has already
/// filtered to `file`, `http` or `https`. Players on this desktop publish a
/// local file far more often than a URL, and `Image.network` cannot read
/// `file://`, so the scheme picks the provider. Anything else, and any load
/// failure, falls back to the caller's placeholder.
class MediaArtwork extends StatelessWidget {
  const MediaArtwork({
    required this.url,
    required this.size,
    required this.radius,
    required this.fallback,
    super.key,
  });

  final String url;
  final double size;
  final double radius;
  final Widget fallback;

  ImageProvider? get _provider {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    if (uri.scheme == 'file') {
      final path = uri.toFilePath();
      if (path.isEmpty) return null;
      return FileImage(File(path));
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return NetworkImage(uri.toString());
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: provider == null
            ? fallback
            : Image(
                image: provider,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, _, _) => fallback,
              ),
      ),
    );
  }
}
