import 'package:cached_network_image/cached_network_image.dart';
import 'package:fangyuanli_mobile/src/features/media/domain/media_upload_models.dart';
import 'package:fangyuanli_mobile/src/features/profile/presentation/profile_media_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('头像以媒体ID稳定缓存并在签名地址变化时保留旧图', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileAvatarImage(
            media: MediaAsset(
              mediaId: 'avatar-media-v7',
              status: 'ready',
              mediaType: 'image',
              thumbnailUrl: Uri(
                scheme: 'https',
                host: 'media.example',
                path: '/avatar-thumb.webp',
                query: 'signature=short-lived',
              ),
            ),
            initial: '桃',
            size: 44,
            borderRadius: 22,
          ),
        ),
      ),
    );

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.cacheKey, 'avatar-media-v7');
    expect(image.useOldImageOnUrlChange, isTrue);
  });
}
