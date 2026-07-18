import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal user identity model for TUNAI Consumer.
/// Compatible with the future AI Orchestrator which will extend this
/// with listening preferences and personalization metadata.
class UserProfile {
  final int userId;
  final String email;
  final String nickname;
  final List<String> savedProfileIds;

  const UserProfile({
    required this.userId,
    required this.email,
    required this.nickname,
    this.savedProfileIds = const [],
  });

  UserProfile copyWith({
    String? nickname,
    List<String>? savedProfileIds,
  }) =>
      UserProfile(
        userId: userId,
        email: email,
        nickname: nickname ?? this.nickname,
        savedProfileIds: savedProfileIds ?? this.savedProfileIds,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'email': email,
        'nickname': nickname,
        'savedProfileIds': savedProfileIds,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        userId: json['userId'] as int,
        email: json['email'] as String,
        nickname: json['nickname'] as String,
        savedProfileIds:
            (json['savedProfileIds'] as List?)?.cast<String>() ?? [],
      );
}

/// A sound profile published to the TUNAI community.
/// Mirrors the server `presets` schema; designed for future AI Orchestrator
/// ranking and personalization hooks.
class CommunitySoundProfile {
  final int id;
  final String title;
  final String? description;
  final String? roomTag;
  final int likes;
  final String authorNickname;
  final DateTime publishedAt;

  const CommunitySoundProfile({
    required this.id,
    required this.title,
    this.description,
    this.roomTag,
    required this.likes,
    required this.authorNickname,
    required this.publishedAt,
  });

  factory CommunitySoundProfile.fromJson(Map<String, dynamic> json) =>
      CommunitySoundProfile(
        id: json['id'] as int,
        title: json['title'] as String,
        description: json['description'] as String?,
        roomTag: json['room_tag'] as String?,
        likes: (json['likes'] ?? 0) as int,
        authorNickname: json['nickname'] as String? ?? '',
        publishedAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}

const _kUserProfileKey = 'tunai_user_profile';

class UserProfileNotifier extends StateNotifier<UserProfile?> {
  UserProfileNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUserProfileKey);
    if (raw != null) {
      try {
        state = UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  Future<void> setProfile(UserProfile profile) async {
    state = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserProfileKey, jsonEncode(profile.toJson()));
  }

  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserProfileKey);
  }

  Future<void> addSavedProfileId(String id) async {
    if (state == null) return;
    final updated = state!.copyWith(
      savedProfileIds: [...state!.savedProfileIds, id],
    );
    await setProfile(updated);
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile?>(
  (_) => UserProfileNotifier(),
);
