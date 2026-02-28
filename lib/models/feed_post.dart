// models/feed_post.dart
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math';

class FeedPost {
  final String id;
  final String authorName;
  final String authorEmail;
  final String? authorDesignation;
  final String content;
  final String? imageUrl;
  final String? videoUrl;
  final Poll? poll;
  final List<String> mentions;
  final List<String> bulkMentions;
  final List<String> tags;
  final DateTime createdAt;
  final int likes;
  final int comments;
  final bool isLiked;
  final bool isPinned;
  final bool isActive;

  FeedPost({
    required this.id,
    required this.authorName,
    required this.authorEmail,
    this.authorDesignation,
    required this.content,
    this.imageUrl,
    this.videoUrl,
    this.poll,
    this.mentions = const [],
    this.bulkMentions = const [],
    this.tags = const [],
    required this.createdAt,
    this.likes = 0,
    this.comments = 0,
    this.isLiked = false,
    this.isPinned = false,
    this.isActive = true,
  });

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    // Extract image URL from attachments
    String? imageUrl = json['imageUrl'];
    
    if (imageUrl == null && json['attachments'] != null) {
      try {
        final attachments = json['attachments'] as List? ?? [];
        final imageAttachment = attachments.firstWhere(
          (a) => a is Map && a['type'] == 'image',
          orElse: () => null,
        );
        if (imageAttachment != null) {
          imageUrl = imageAttachment['data'] != null 
              ? 'data:image/jpeg;base64,${imageAttachment['data']}'
              : imageAttachment['url'];
        }
      } catch (e) {
        debugPrint('❌ Error parsing attachments: $e');
      }
    }

    // Parse poll if exists
    Poll? poll;
    if (json['poll'] != null) {
      try {
        poll = Poll.fromJson(json['poll']);
      } catch (e) {
        debugPrint('❌ Error parsing poll: $e');
      }
    }

    return FeedPost(
      id: json['id']?.toString() ?? '',
      authorName: json['authorName'] ?? 'Unknown',
      authorEmail: json['authorEmail'] ?? '',
      authorDesignation: json['authorDesignation'],
      content: json['content'] ?? '',
      imageUrl: imageUrl,
      videoUrl: json['videoUrl'],
      poll: poll,
      mentions: _parseStringList(json['mentions']),
      bulkMentions: _parseStringList(json['bulkMentions']), // 🔴 FIXED: Now properly parsed
      tags: _parseStringList(json['tags']),
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
      likes: json['likes'] ?? 0,
      comments: json['comments'] ?? 0,
      isLiked: _parseBool(json['likedByUser'] ?? json['liked_by_user'] ?? json['isLiked']),
      isPinned: _parseBool(json['isPinned']),
      isActive: _parseBool(json['isActive']),
    );
  }

  static List<String> _parseStringList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String) {
      // Handle comma-separated string
      if (value.contains(',')) {
        return value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      // Handle JSON array string
      try {
        final parsed = jsonDecode(value);
        if (parsed is List) {
          return parsed.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return [];
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value).toLocal();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      final lower = value.toLowerCase();
      return lower == 'true' || lower == '1' || lower == 'yes';
    }
    return false;
  }

  FeedPost copyWith({
    String? id,
    String? authorName,
    String? authorEmail,
    String? authorDesignation,
    String? content,
    String? imageUrl,
    String? videoUrl,
    Poll? poll,
    List<String>? mentions,
    List<String>? bulkMentions,
    List<String>? tags,
    DateTime? createdAt,
    int? likes,
    int? comments,
    bool? isLiked,
    bool? isPinned,
    bool? isActive,
  }) {
    return FeedPost(
      id: id ?? this.id,
      authorName: authorName ?? this.authorName,
      authorEmail: authorEmail ?? this.authorEmail,
      authorDesignation: authorDesignation ?? this.authorDesignation,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      poll: poll ?? this.poll,
      mentions: mentions ?? this.mentions,
      bulkMentions: bulkMentions ?? this.bulkMentions,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      isLiked: isLiked ?? this.isLiked,
      isPinned: isPinned ?? this.isPinned,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  String toString() {
    final contentPreview = content.length > 20 
        ? '${content.substring(0, 20)}...' 
        : content;
    return 'FeedPost(id: $id, author: $authorName, content: $contentPreview, bulkMentions: $bulkMentions)';
  }
}

class Poll {
  final String id;
  final String question;
  final List<PollOption> options;
  final bool isMultipleChoice;
  final DateTime endsAt;
  final bool hasVoted;

  Poll({
    required this.id,
    required this.question,
    required this.options,
    this.isMultipleChoice = false,
    required this.endsAt,
    this.hasVoted = false,
  });

  factory Poll.fromJson(Map<String, dynamic> json) {
    return Poll(
      id: json['id']?.toString() ?? '',
      question: json['question'] ?? '',
      options: (json['options'] as List?)
          ?.map((opt) => PollOption.fromJson(opt))
          .toList() ?? [],
      isMultipleChoice: _parseBool(json['multipleChoice']),
      endsAt: _parseDate(json['endsAt']) ?? DateTime.now().add(const Duration(days: 7)),
      hasVoted: _parseBool(json['hasVoted']),
    );
  }

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      final lower = value.toLowerCase();
      return lower == 'true' || lower == '1' || lower == 'yes';
    }
    return false;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value).toLocal();
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

class PollOption {
  final String id;
  final String text;
  final int votes;
  final double percentage;
  final bool isSelected;

  PollOption({
    required this.id,
    required this.text,
    required this.votes,
    this.percentage = 0.0,
    this.isSelected = false,
  });

  factory PollOption.fromJson(Map<String, dynamic> json) {
    return PollOption(
      id: json['id']?.toString() ?? '',
      text: json['text'] ?? json['optionText'] ?? '',
      votes: json['votes'] ?? 0,
      percentage: json['percentage']?.toDouble() ?? 0.0,
      isSelected: _parseBool(json['isSelected']),
    );
  }

  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      final lower = value.toLowerCase();
      return lower == 'true' || lower == '1' || lower == 'yes';
    }
    return false;
  }
}