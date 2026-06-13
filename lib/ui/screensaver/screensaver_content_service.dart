import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';

import '../../preference/user_preferences.dart';

class ScreensaverItem {
  const ScreensaverItem({
    required this.name,
    required this.backdropUrl,
    this.logoUrl,
  });

  final String name;
  final String backdropUrl;
  final String? logoUrl;
}

class ScreensaverContentService {
  ScreensaverContentService(this._prefs);

  final UserPreferences _prefs;

  static const _batchSize = 60;

  Future<List<ScreensaverItem>> loadBatch() async {
    if (!GetIt.instance.isRegistered<MediaServerClient>()) {
      return const [];
    }
    final client = GetIt.instance<MediaServerClient>();
    final maxAge = _prefs.get(UserPreferences.screensaverMaxAgeRating);
    final requireRating = _prefs.get(UserPreferences.screensaverRequireRating);
    try {
      final response = await client.itemsApi.getItems(
        includeItemTypes: ['Movie', 'Series'],
        sortBy: 'Random',
        sortOrder: 'Descending',
        recursive: true,
        limit: _batchSize,
        fields: 'ImageTags,BackdropImageTags,OfficialRating',
        enableTotalRecordCount: false,
        enableImageTypes: 'Backdrop,Logo',
        maxOfficialRating: maxAge == 'any' ? null : maxAge,
        hasParentalRating: requireRating ? true : null,
      );
      final rawItems = (response['Items'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final items = <ScreensaverItem>[];
      for (final raw in rawItems) {
        final item = _toItem(client, raw, requireRating: requireRating);
        if (item != null) {
          items.add(item);
        }
      }
      return items;
    } catch (_) {
      return const [];
    }
  }

  ScreensaverItem? _toItem(
    MediaServerClient client,
    Map<String, dynamic> raw, {
    required bool requireRating,
  }) {
    final id = raw['Id'] as String? ?? '';
    if (id.isEmpty) return null;
    if (requireRating &&
        ((raw['OfficialRating'] as String?)?.isEmpty ?? true)) {
      return null;
    }

    String? backdropUrl;
    final backdropTags = raw['BackdropImageTags'] as List?;
    if (backdropTags != null && backdropTags.isNotEmpty) {
      backdropUrl = client.imageApi.getBackdropImageUrl(
        id,
        maxWidth: 1920,
        tag: backdropTags.first as String?,
      );
    } else {
      final parentId = raw['ParentBackdropItemId'] as String?;
      final parentTags = raw['ParentBackdropImageTags'] as List?;
      if (parentId != null && parentTags != null && parentTags.isNotEmpty) {
        backdropUrl = client.imageApi.getBackdropImageUrl(
          parentId,
          maxWidth: 1920,
          tag: parentTags.first as String?,
        );
      }
    }
    if (backdropUrl == null) return null;

    String? logoUrl;
    final logoTag = (raw['ImageTags'] as Map?)?['Logo'] as String?;
    if (logoTag != null && logoTag.isNotEmpty) {
      logoUrl = client.imageApi.getLogoImageUrl(id, maxWidth: 800, tag: logoTag);
    }

    return ScreensaverItem(
      name: raw['Name'] as String? ?? '',
      backdropUrl: backdropUrl,
      logoUrl: logoUrl,
    );
  }
}
