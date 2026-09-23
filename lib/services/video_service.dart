import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:onlystream/models/video_model.dart';
import 'package:onlystream/utils/constants.dart';

// [Video_Service]
class VideoService {
  /// Fetches next episode metadata from endpoint:
  /// http://localhost:5555/tv/{id}/{season}/{episode}/?nextepisode=true
  static Future<Video?> fetchNextEpisode({
    required int tvId,
    required int season,
    required int episode,
    String language = 'it',
  }) async {
    final urlString =
        '${AppConstants.baseUrl}/tv/$tvId/$season/$episode/?nextepisode=true&lang=$language';
    debugPrint('[VideoService] Fetching next episode from API: $urlString');

    try {
      final response = await http
          .get(Uri.parse(urlString))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        debugPrint(
          '[VideoService] API returned next episode data successfully',
        );
        return Video.fromJson(data);
      } else {
        debugPrint(
          '[VideoService] API request failed with status code: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[VideoService] Failed to fetch next episode via API: $e');
    }
    return null;
  }

  static Future<Video?> fetchCurrentEpisode({
    required int tvId,
    required int season,
    required int episode,
    String language = 'it',
  }) async {
    final urlString =
        '${AppConstants.baseUrl}/tv/$tvId/$season/$episode/?currentInfo=true&lang=$language';
    debugPrint('[VideoService] Fetching next episode from API: $urlString');

    try {
      final response = await http
          .get(Uri.parse(urlString))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        debugPrint(
          '[VideoService] API returned next episode data successfully',
        );
        return Video.fromJson(data);
      } else {
        debugPrint(
          '[VideoService] API request failed with status code: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[VideoService] Failed to fetch next episode via API: $e');
    }
    return null;
  }
}
