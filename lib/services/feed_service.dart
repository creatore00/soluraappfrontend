// services/feed_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/feed_post.dart';
import '../services/auth_service.dart';

class FeedService {
  static final FeedService _instance = FeedService._internal();
  factory FeedService() => _instance;
  FeedService._internal();

  String get baseUrl => "${AuthService.baseUrl}/feed";

  static const Duration _timeout = Duration(seconds: 12);

  // ---------------------------
  // Internal helpers
  // ---------------------------
  Map<String, dynamic>? _tryJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ===========================================
  // GET FEED POSTS
  // ===========================================
  Future<List<FeedPost>> fetchFeedPosts({
    required String db,
    required String userEmail,
    int page = 1,
    int limit = 20,
    String? filter,
  }) async {
    final url = Uri.parse(
      "${AuthService.baseUrl}/feed/posts"
      "?db=$db&userEmail=$userEmail&page=$page&limit=$limit"
      "${filter != null ? '&filter=$filter' : ''}",
    );

    try {
      final response = await http.get(url).timeout(_timeout);

      final data = _tryJson(response.body);
      if (response.statusCode != 200 || data == null) {
        print("❌ fetchFeedPosts HTTP ${response.statusCode}: ${response.body}");
        return [];
      }

      if (data['success'] != true) {
        print("❌ fetchFeedPosts success=false: ${data['message']}");
        return [];
      }

      final List postsJson = (data['posts'] as List?) ?? [];
      return postsJson
          .map((p) {
            try {
              return FeedPost.fromJson(Map<String, dynamic>.from(p as Map));
            } catch (e) {
              print("❌ FeedPost parse error: $e");
              print("❌ Post payload: $p");
              return null;
            }
          })
          .whereType<FeedPost>()
          .toList();
    } catch (e) {
      print("❌ fetchFeedPosts error: $e");
      return [];
    }
  }

  // ===========================================
  // CREATE POST
  // ===========================================
  Future<FeedPost?> createPost({
    required String db,
    required String content,
    required String authorEmail,
    required String authorName,
    List<Map<String, dynamic>> attachments = const [],
    String visibility = 'all',
    List<String> mentions = const [],
    List<String> bulkMentions = const [],
    Map<String, dynamic>? poll,
  }) async {
    final url = Uri.parse("${AuthService.baseUrl}/feed/create");

    try {
      final requestBody = {
        'db': db,
        'authorEmail': authorEmail,
        'content': content,
        'attachments': attachments,
        'visibility': visibility,
        'mentions': mentions,
        'bulkMentions': bulkMentions,
        if (poll != null) 'poll': poll,
      };

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(_timeout);

      final data = _tryJson(response.body);
      if (response.statusCode != 200 || data == null) {
        print("❌ createPost HTTP ${response.statusCode}: ${response.body}");
        return null;
      }

      if (data['success'] == true && data['post'] != null) {
        return FeedPost.fromJson(Map<String, dynamic>.from(data['post']));
      }

      print("❌ createPost failed: ${data['message']}");
      return null;
    } catch (e) {
      print("❌ createPost error: $e");
      return null;
    }
  }

  // ===========================================
  // LIKE/UNLIKE POST (TOGGLE)
  // ===========================================
  Future<bool> likePost({
    required String db,
    required String postId,
    required String userEmail,
  }) async {
    final url = Uri.parse("${AuthService.baseUrl}/feed/like");

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'db': db,
              'postId': postId,
              'userEmail': userEmail,
            }),
          )
          .timeout(_timeout);

      final data = _tryJson(response.body);
      if (response.statusCode != 200 || data == null) {
        print("❌ likePost HTTP ${response.statusCode}: ${response.body}");
        return false;
      }

      return data['success'] == true;
    } catch (e) {
      print("❌ likePost error: $e");
      return false;
    }
  }

  // ===========================================
  // ADD COMMENT (supports replies)
  // ===========================================
  Future<Map<String, dynamic>?> addComment({
    required String db,
    required String postId,
    required String userEmail,
    required String content,
    String? parentCommentId,
  }) async {
    final url = Uri.parse("${AuthService.baseUrl}/feed/comment");

    try {
      final body = {
        'db': db,
        'postId': postId,
        'userEmail': userEmail,
        'content': content,
        if (parentCommentId != null && parentCommentId.trim().isNotEmpty)
          'parentCommentId': parentCommentId,
      };

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      final data = _tryJson(response.body);

      if (response.statusCode != 200 || data == null) {
        print("❌ addComment HTTP ${response.statusCode}: ${response.body}");
        return null;
      }

      if (data['success'] == true) {
        return (data['comment'] as Map?)?.cast<String, dynamic>();
      }

      print("❌ addComment failed: ${data['message']}");
      return null;
    } catch (e) {
      print("❌ addComment error: $e");
      return null;
    }
  }

  // ===========================================
  // GET COMMENTS (nested replies + reactions)
  // ===========================================
  Future<List<dynamic>> getComments({
    required String db,
    required String postId,
  }) async {
    final url = Uri.parse("${AuthService.baseUrl}/feed/comments?db=$db&postId=$postId");

    try {
      final response = await http.get(url).timeout(_timeout);

      final data = _tryJson(response.body);
      if (response.statusCode != 200 || data == null) {
        print("❌ getComments HTTP ${response.statusCode}: ${response.body}");
        return [];
      }

      if (data['success'] == true) {
        return (data['comments'] as List?) ?? [];
      }

      print("❌ getComments failed: ${data['message']}");
      return [];
    } catch (e) {
      print("❌ getComments error: $e");
      return [];
    }
  }

  // ===========================================
  // TOGGLE REACTION ON COMMENT
  // ===========================================
  Future<bool> toggleReaction({
    required String db,
    required String commentId,
    required String userEmail,
    required String emoji,
  }) async {
    final url = Uri.parse("${AuthService.baseUrl}/feed/comment/reaction");

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'db': db,
              'commentId': commentId,
              'userEmail': userEmail,
              'emoji': emoji,
            }),
          )
          .timeout(_timeout);

      final data = _tryJson(response.body);
      if (response.statusCode != 200 || data == null) {
        print("❌ toggleReaction HTTP ${response.statusCode}: ${response.body}");
        return false;
      }

      return data['success'] == true;
    } catch (e) {
      print("❌ toggleReaction error: $e");
      return false;
    }
  }

  // ===========================================
  // GET LIKES FOR A POST
  // ===========================================
  Future<List<Map<String, dynamic>>> getLikes({
    required String db,
    required String postId,
  }) async {
    final url = Uri.parse("${AuthService.baseUrl}/feed/likes?db=$db&postId=$postId");

    try {
      final response = await http.get(url).timeout(_timeout);

      final data = _tryJson(response.body);
      if (response.statusCode != 200 || data == null) {
        print("❌ getLikes HTTP ${response.statusCode}: ${response.body}");
        return [];
      }

      if (data['success'] == true) {
        return List<Map<String, dynamic>>.from(data['likes'] ?? const []);
      }

      return [];
    } catch (e) {
      print("❌ getLikes error: $e");
      return [];
    }
  }

  // ===========================================
  // PIN/UNPIN POST
  // ===========================================
  Future<bool> pinPost({
  required String db,
  required String postId,
  required String userEmail,
  required bool pin,
}) async {
  final url = Uri.parse("${AuthService.baseUrl}/feed/pin");

  try {
    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'db': db,
            'postId': postId,
            'userEmail': userEmail,
            'pin': pin,
          }),
        )
        .timeout(_timeout);

    final data = _tryJson(response.body);
    if (response.statusCode != 200 || data == null) {
      print("❌ pinPost HTTP ${response.statusCode}: ${response.body}");
      return false;
    }

    if (data['success'] != true) {
      print("❌ pinPost failed: ${data['message']}");
    }

    return data['success'] == true;
  } catch (e) {
    print("❌ pinPost error: $e");
    return false;
  }
}

  // ===========================================
  // DELETE POST
  // ===========================================
  Future<bool> deletePost({
    required String db,
    required String postId,
    required String userEmail,
  }) async {
    final url = Uri.parse("${AuthService.baseUrl}/feed/post/$postId?db=$db&userEmail=$userEmail");

    try {
      final response = await http.delete(url).timeout(_timeout);

      final data = _tryJson(response.body);
      if (response.statusCode != 200 || data == null) {
        print("❌ deletePost HTTP ${response.statusCode}: ${response.body}");
        return false;
      }

      return data['success'] == true;
    } catch (e) {
      print("❌ deletePost error: $e");
      return false;
    }
  }

  // ===========================================
  // GET POLL VOTES
  // ===========================================
  Future<List<Map<String, dynamic>>> getPollVotes({
    required String db,
    required String pollId,
  }) async {
    final url = Uri.parse("${AuthService.baseUrl}/feed/poll/votes?db=$db&pollId=$pollId");

    try {
      final response = await http.get(url).timeout(_timeout);

      final data = _tryJson(response.body);
      if (response.statusCode != 200 || data == null) {
        print("❌ getPollVotes HTTP ${response.statusCode}: ${response.body}");
        return [];
      }

      if (data['success'] == true) {
        return List<Map<String, dynamic>>.from(data['votes'] ?? const []);
      }

      return [];
    } catch (e) {
      print("❌ getPollVotes error: $e");
      return [];
    }
  }

  // ===========================================
  // VOTE IN POLL
  // ===========================================
  Future<bool> voteInPoll({
    required String db,
    required String pollId,
    required String optionId,
    required String userEmail,
  }) async {
    final url = Uri.parse("${AuthService.baseUrl}/feed/poll/vote");

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'db': db,
              'pollId': pollId,
              'optionId': optionId,
              'userEmail': userEmail,
            }),
          )
          .timeout(_timeout);

      final data = _tryJson(response.body);
      if (data == null) {
        print("❌ voteInPoll invalid JSON: ${response.body}");
        return false;
      }

      // backend may return 400 with message (already voted / ended)
      if (response.statusCode == 200) return data['success'] == true;

      print("❌ voteInPoll HTTP ${response.statusCode}: ${data['message']}");
      return false;
    } catch (e) {
      print("❌ voteInPoll error: $e");
      return false;
    }
  }

  // ===========================================
  // CHANGE VOTE IN POLL
  // ===========================================
  Future<bool> changeVoteInPoll({
    required String db,
    required String pollId,
    required String? oldOptionId,
    required String newOptionId,
    required String userEmail,
  }) async {
    final url = Uri.parse("${AuthService.baseUrl}/feed/poll/change-vote");

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'db': db,
              'pollId': pollId,
              'oldOptionId': oldOptionId,
              'newOptionId': newOptionId,
              'userEmail': userEmail,
            }),
          )
          .timeout(_timeout);

      final data = _tryJson(response.body);
      if (data == null) {
        print("❌ changeVoteInPoll invalid JSON: ${response.body}");
        return false;
      }

      if (response.statusCode == 200) return data['success'] == true;

      print("❌ changeVoteInPoll HTTP ${response.statusCode}: ${data['message']}");
      return false;
    } catch (e) {
      print("❌ changeVoteInPoll error: $e");
      return false;
    }
  }

  // ===========================================
  // DELETE COMMENT
  // ===========================================
  Future<bool> deleteComment({
    required String db,
    required String commentId,
    required String userEmail,
  }) async {
    final url = Uri.parse("${AuthService.baseUrl}/feed/comment/$commentId?db=$db&userEmail=$userEmail");

    try {
      final response = await http.delete(url).timeout(_timeout);

      final data = _tryJson(response.body);
      if (response.statusCode != 200 || data == null) {
        print("❌ deleteComment HTTP ${response.statusCode}: ${response.body}");
        return false;
      }

      return data['success'] == true;
    } catch (e) {
      print("❌ deleteComment error: $e");
      return false;
    }
  }

  // Optional: you can remove getReactions() because your comments endpoint already returns reactions
  Future<Map<String, dynamic>> getReactions({
    required String db,
    required String commentId,
  }) async {
    final url = Uri.parse("${AuthService.baseUrl}/feed/comment/reactions?db=$db&commentId=$commentId");

    try {
      final response = await http.get(url).timeout(_timeout);

      final data = _tryJson(response.body);
      if (response.statusCode == 200 && data != null) return data;

      return {'success': false, 'reactions': [], 'total': 0};
    } catch (e) {
      print("❌ getReactions error: $e");
      return {'success': false, 'reactions': [], 'total': 0};
    }
  }
}
