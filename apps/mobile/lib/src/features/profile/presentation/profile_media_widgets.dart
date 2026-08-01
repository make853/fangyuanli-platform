import 'package:flutter/material.dart';

import '../../media/domain/media_upload_models.dart';

class ProfileAvatarImage extends StatelessWidget {
  const ProfileAvatarImage({
    required this.media,
    required this.initial,
    required this.size,
    required this.borderRadius,
    super.key,
  });

  final MediaAsset? media;
  final String initial;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final url = media?.thumbnailUrl ?? media?.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.square(
        dimension: size,
        child: url == null
            ? _fallback()
            : Image.network(
                url.toString(),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallback(),
              ),
      ),
    );
  }

  Widget _fallback() => ColoredBox(
    color: const Color(0xFFDDEEE7),
    child: Center(
      child: Text(
        initial,
        style: TextStyle(
          color: const Color(0xFF167A5B),
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class ProfileBackgroundImage extends StatelessWidget {
  const ProfileBackgroundImage({
    required this.media,
    this.fit = BoxFit.cover,
    super.key,
  });

  final MediaAsset? media;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final url = media?.url ?? media?.thumbnailUrl;
    if (url == null) return _fallback();
    return Image.network(
      url.toString(),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => _fallback(),
    );
  }

  Widget _fallback() => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFBFDACD), Color(0xFFE9F1ED), Color(0xFFCFE2D9)],
      ),
    ),
  );
}
