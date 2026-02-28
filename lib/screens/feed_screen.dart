// screens/feed_screen.dart
//
// ✅ Full rewrite (fixed) with:
// - Heart icon always visible (no missing icon bug)
// - Optimistic like toggle + rollback
// - Comments bottom sheet:
//   - Inline replying
//   - Replies under parent
//   - Emoji reactions toggle + refresh
//   - Mentions via MentionTextField
// - Poll voting works (tap option calls onVote)
// - Poll "View votes" supported (optional) + no null-crashes
// - Fix reply SnackBar message
// - Composer listener so Send button updates immediately
//
// ✅ NEW (requested):
// - 3 dots menu (top right of each post)
// - Delete Post + Pin/Unpin Post (only for AM / Manager)
// - Optimistic delete/pin + rollback if API fails
// - Optional "Pinned" badge + pinned posts sorted on top

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';

import '../models/feed_post.dart';
import '../services/feed_service.dart';
import '../models/database_access.dart';
import 'create_post_dialog.dart';
import '../widgets/mention_text_field.dart';

class FeedScreen extends StatefulWidget {
  final DatabaseAccess selectedDb;
  final String userEmail;
  final String userName;

  /// ✅ NEW: pass user's designation if you have it (AM/Manager/FOH/BOH etc).
  /// Not required to update old callers (default '').
  final String userDesignation;

  const FeedScreen({
    super.key,
    required this.selectedDb,
    required this.userEmail,
    required this.userName,
    this.userDesignation = '',
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final FeedService _feedService = FeedService();
  final ScrollController _scrollController = ScrollController();

  final int _pageSize = 20;
  List<FeedPost> _posts = [];
  bool _loading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 250) {
      _loadMorePosts();
    }
  }

  // ===========================================
  // ROLE CHECK
  // ===========================================
  bool get _isAmOrManager {
    final access = widget.selectedDb.access.toLowerCase().trim();
    return access == 'manager' ||
          access == 'am' ||
          access == 'assistant manager';
  }

  // ===========================================
  // COLORS BY DESIGNATION
  // ===========================================
  Color _getColorForDesignation(String designation) {
    final des = designation.toLowerCase();
    switch (des) {
      case 'manager':
        return Colors.purple;
      case 'am':
        return Colors.orange;
      case 'boh':
        return Colors.blue;
      case 'foh':
        return Colors.green;
      default:
        return const Color(0xFF4CC9F0);
    }
  }

  // ===========================================
  // INITIALS
  // ===========================================
  String _getInitials(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return parts[0][0].toUpperCase();
  }

  // ===========================================
  // TIME AGO
  // ===========================================
  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'Unknown';

    DateTime date;
    if (dateTime is DateTime) {
      date = dateTime;
    } else if (dateTime is String) {
      try {
        date = DateTime.parse(dateTime).toLocal();
      } catch (_) {
        return 'Unknown';
      }
    } else {
      return 'Unknown';
    }

    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 5) return 'Just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${date.day}/${date.month}/${date.year}';
  }

  // ===========================================
  // PINNED SORT
  // ===========================================
  List<FeedPost> _sortPinnedFirst(List<FeedPost> posts) {
    final list = List<FeedPost>.from(posts);
    list.sort((a, b) {
      final ap = (a.isPinned ?? false) ? 1 : 0;
      final bp = (b.isPinned ?? false) ? 1 : 0;
      if (bp != ap) return bp.compareTo(ap);
      // Secondary: newest first (if createdAt parsable)
      DateTime? ad;
      DateTime? bd;
      try {
        if (a.createdAt is String) ad = DateTime.parse(a.createdAt as String);
      } catch (_) {}
      try {
        if (b.createdAt is String) bd = DateTime.parse(b.createdAt as String);
      } catch (_) {}
      if (ad != null && bd != null) return bd.compareTo(ad);
      return 0;
    });
    return list;
  }

  // ===========================================
  // LOAD POSTS
  // ===========================================
  Future<void> _loadPosts() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final posts = await _feedService.fetchFeedPosts(
        db: widget.selectedDb.dbName,
        userEmail: widget.userEmail,
        page: 1,
        limit: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        _posts = _sortPinnedFirst(posts);
        _hasMore = posts.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ _loadPosts error: $e");
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMorePosts() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    try {
      final nextPage = (_posts.length ~/ _pageSize) + 1;

      final posts = await _feedService.fetchFeedPosts(
        db: widget.selectedDb.dbName,
        userEmail: widget.userEmail,
        page: nextPage,
        limit: _pageSize,
      );

      if (!mounted) return;
      setState(() {
        _posts.addAll(posts);
        _posts = _sortPinnedFirst(_posts);
        _hasMore = posts.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ _loadMorePosts error: $e");
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshPosts() async {
    setState(() {
      _posts.clear();
      _hasMore = true;
    });
    await _loadPosts();
  }

  void _showCreatePostDialog() {
    showCreatePostDialog(
      context,
      widget.selectedDb.dbName,
      widget.userEmail,
      _refreshPosts,
    );
  }

  // ===========================================
  // LIKE TOGGLE (optimistic + rollback)
  // ===========================================
  Future<void> _toggleLike(FeedPost post) async {
    final index = _posts.indexWhere((p) => p.id == post.id);
    if (index == -1) return;

    final prev = _posts[index];
    final willLike = !prev.isLiked;

    setState(() {
      _posts[index] = prev.copyWith(
        isLiked: willLike,
        likes: max(0, prev.likes + (willLike ? 1 : -1)),
      );
    });

    try {
      final success = await _feedService.likePost(
        db: widget.selectedDb.dbName,
        postId: post.id,
        userEmail: widget.userEmail,
      );

      if (!success && mounted) {
        setState(() => _posts[index] = prev);
      }
    } catch (e) {
      debugPrint("❌ _toggleLike error: $e");
      if (mounted) setState(() => _posts[index] = prev);
    }
  }

  // ===========================================
  // DOUBLE TAP LIKE
  // ===========================================
  void _handleDoubleTap(FeedPost post) {
    if (!post.isLiked) {
      _toggleLike(post);

      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: '',
        pageBuilder: (context, a1, a2) => const SizedBox.shrink(),
        transitionBuilder: (context, a1, a2, child) {
          return ScaleTransition(
            scale: CurvedAnimation(parent: a1, curve: Curves.elasticOut),
            child: const Center(
              child: Icon(Icons.favorite, color: Colors.red, size: 110),
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 450),
      );
    }
  }

  // ===========================================
  // COMMENTS SHEET
  // ===========================================
  void _openComments(FeedPost post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (_) => _CommentsSheet(
        dbName: widget.selectedDb.dbName,
        postId: post.id,
        currentUserEmail: widget.userEmail,
        currentUserName: widget.userName,
        getInitials: _getInitials,
        getColorForDesignation: _getColorForDesignation,
        formatDateTime: _formatDateTime,
        feedService: _feedService,
        onAnyChange: () async {
          await _refreshPosts();
        },
      ),
    );
  }

  // ===========================================
  // LIKES SHEET
  // ===========================================
  void _showLikesSheet(FeedPost post) async {
    final likes = await _feedService.getLikes(
      db: widget.selectedDb.dbName,
      postId: post.id,
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF172A45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: 520,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.favorite, color: Colors.red, size: 26),
                const SizedBox(width: 12),
                Text(
                  '${likes.length} ${likes.length == 1 ? 'like' : 'likes'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: likes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.favorite_border,
                              size: 48, color: Colors.white.withOpacity(0.12)),
                          const SizedBox(height: 16),
                          Text(
                            'No likes yet',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: likes.length,
                      separatorBuilder: (_, __) =>
                          Divider(color: Colors.white.withOpacity(0.06)),
                      itemBuilder: (context, index) {
                        final like = likes[index];
                        final isCurrentUser =
                            like['userEmail'] == widget.userEmail;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                _getColorForDesignation(like['designation'] ?? ''),
                            child: Text(
                              _getInitials(like['userName'] ?? like['userEmail']),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                like['userName'] ?? like['userEmail'],
                                style: TextStyle(
                                  color: isCurrentUser
                                      ? const Color(0xFF4CC9F0)
                                      : Colors.white,
                                  fontWeight: isCurrentUser
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              if (isCurrentUser) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4CC9F0).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'You',
                                    style: TextStyle(
                                      color: Color(0xFF4CC9F0),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            _formatDateTime(like['createdAt']),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================
  // POLL VOTES SHEET
  // ===========================================
  void _showPollVotesSheet(Poll poll) async {
    final votes = await _feedService.getPollVotes(
      db: widget.selectedDb.dbName,
      pollId: poll.id,
    );

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF172A45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        height: 520,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.poll, color: Color(0xFF4CC9F0), size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    poll.question,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: votes.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.how_to_vote,
                              size: 48, color: Colors.white.withOpacity(0.12)),
                          const SizedBox(height: 16),
                          Text(
                            'No votes yet',
                            style: TextStyle(color: Colors.white.withOpacity(0.55)),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: poll.options.length,
                      itemBuilder: (context, index) {
                        final option = poll.options[index];
                        final optionVotes =
                            votes.where((v) => v['optionId'] == option.id).toList();
                        final percentage = votes.isNotEmpty
                            ? (optionVotes.length / votes.length * 100)
                            : 0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      option.text,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4CC9F0).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(0xFF4CC9F0).withOpacity(0.3),
                                      ),
                                    ),
                                    child: Text(
                                      '${optionVotes.length} (${percentage.toStringAsFixed(1)}%)',
                                      style: const TextStyle(
                                        color: Color(0xFF4CC9F0),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ...optionVotes.map(
                                (vote) => Padding(
                                  padding:
                                      const EdgeInsets.only(left: 16, bottom: 8),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: _getColorForDesignation(
                                            vote['designation'] ?? ''),
                                        child: Text(
                                          _getInitials(
                                              vote['userName'] ?? vote['userEmail']),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              vote['userName'] ?? vote['userEmail'],
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                              ),
                                            ),
                                            Text(
                                              _formatDateTime(vote['createdAt']),
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.45),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (index < poll.options.length - 1)
                                Divider(
                                  color: Colors.white.withOpacity(0.08),
                                  height: 22,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================
  // HANDLE VOTE
  // ===========================================
  Future<void> _handleVote(FeedPost post, String optionId) async {
    if (post.poll == null) return;

    bool success;

    if (post.poll!.hasVoted) {
      final votedOption = post.poll!.options.firstWhere(
        (opt) => opt.isSelected,
        orElse: () => post.poll!.options.first,
      );

      if (votedOption.id == optionId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('You already voted for this option'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 1),
          ),
        );
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF172A45),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Change vote?', style: TextStyle(color: Colors.white)),
          content: Text(
            'Switch to "${post.poll!.options.firstWhere((opt) => opt.id == optionId).text}"?',
            style: TextStyle(color: Colors.white.withOpacity(0.9)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel',
                  style: TextStyle(color: Colors.white.withOpacity(0.7))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CC9F0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Change'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      success = await _feedService.changeVoteInPoll(
        db: widget.selectedDb.dbName,
        pollId: post.poll!.id,
        oldOptionId: votedOption.id,
        newOptionId: optionId,
        userEmail: widget.userEmail,
      );
    } else {
      success = await _feedService.voteInPoll(
        db: widget.selectedDb.dbName,
        pollId: post.poll!.id,
        optionId: optionId,
        userEmail: widget.userEmail,
      );
    }

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(post.poll!.hasVoted ? 'Vote changed!' : 'Vote recorded!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 1),
        ),
      );
      await _refreshPosts();
    }
  }

  // ===========================================
  // POST MENU (3 dots)
  // ===========================================
  Future<void> _openPostMenu(FeedPost post) async {
    if (!_isAmOrManager) return;

    final isPinned = post.isPinned ?? false;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF172A45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              leading: Icon(
                isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                color: const Color(0xFF4CC9F0),
              ),
              title: Text(
                isPinned ? 'Unpin post' : 'Pin post',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete post',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (action == 'pin') {
      await _togglePin(post);
    } else if (action == 'delete') {
      await _deletePost(post);
    }
  }

  // ===========================================
  // PIN/UNPIN (optimistic + rollback)
  // ===========================================
  Future<void> _togglePin(FeedPost post) async {
    final index = _posts.indexWhere((p) => p.id == post.id);
    if (index == -1) return;

    final prev = _posts[index];
    final wasPinned = prev.isPinned ?? false;
    final willPin = !wasPinned;

    setState(() {
      _posts[index] = prev.copyWith(isPinned: willPin);
      _posts = _sortPinnedFirst(_posts);
    });

    try {
      // ✅ You must implement this in FeedService
      final ok = await _feedService.pinPost(
        db: widget.selectedDb.dbName,
        postId: post.id,
        userEmail: widget.userEmail,
        pin: willPin,
      );

      if (!ok && mounted) {
        setState(() => _posts[index] = prev);
        setState(() => _posts = _sortPinnedFirst(_posts));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to update pin'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(willPin ? 'Post pinned' : 'Post unpinned'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _posts[index] = prev);
      setState(() => _posts = _sortPinnedFirst(_posts));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // ===========================================
  // DELETE POST (confirm + optimistic + rollback)
  // ===========================================
  Future<void> _deletePost(FeedPost post) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF172A45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete post?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently remove the post.',
          style: TextStyle(color: Colors.white.withOpacity(0.85)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prevPosts = List<FeedPost>.from(_posts);

    setState(() => _posts.removeWhere((p) => p.id == post.id));

    try {
      // ✅ You must implement this in FeedService
      final ok = await _feedService.deletePost(
        db: widget.selectedDb.dbName,
        postId: post.id,
        userEmail: widget.userEmail,
      );

      if (!ok && mounted) {
        setState(() => _posts = prevPosts);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to delete post'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Post deleted'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _posts = prevPosts);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // ===========================================
  // BUILD
  // ===========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      appBar: AppBar(
        title: const Text(
          'Feed',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        backgroundColor: const Color(0xFF172A45),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF4CC9F0)),
            onPressed: _refreshPosts,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshPosts,
        backgroundColor: const Color(0xFF172A45),
        color: const Color(0xFF4CC9F0),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: _posts.length + 1,
          itemBuilder: (context, index) {
            if (index == _posts.length) {
              if (_loading) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF4CC9F0),
                      strokeWidth: 2,
                    ),
                  ),
                );
              }
              if (_hasMore) return const SizedBox(height: 20);

              return Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.celebration,
                          size: 48, color: Colors.white.withOpacity(0.12)),
                      const SizedBox(height: 16),
                      Text(
                        'You\'re all caught up!',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Check back later for new posts',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final post = _posts[index];

            return PostCard(
              key: ValueKey(post.id),
              post: post,

              // ✅ NEW
              canManagePost: _isAmOrManager,
              onMenu: () => _openPostMenu(post),

              onLike: () => _toggleLike(post),
              onDoubleTap: () => _handleDoubleTap(post),
              onComment: () => _openComments(post),
              onShowLikes: () => _showLikesSheet(post),
              onShowVotes: post.poll == null ? null : () => _showPollVotesSheet(post.poll!),
              onVote: (optionId) => _handleVote(post, optionId),
              getColorForDesignation: _getColorForDesignation,
              formatDateTime: _formatDateTime,
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreatePostDialog,
        backgroundColor: const Color(0xFF4CC9F0),
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

// ===========================================
// POST CARD
// ===========================================
class PostCard extends StatelessWidget {
  final FeedPost post;

  // ✅ NEW (menu)
  final bool canManagePost;
  final VoidCallback onMenu;

  final VoidCallback onLike;
  final VoidCallback onDoubleTap;
  final VoidCallback onComment;
  final VoidCallback onShowLikes;
  final VoidCallback? onShowVotes;
  final void Function(String optionId) onVote;

  final Color Function(String) getColorForDesignation;
  final String Function(dynamic) formatDateTime;

  const PostCard({
    super.key,
    required this.post,

    // ✅ NEW
    required this.canManagePost,
    required this.onMenu,

    required this.onLike,
    required this.onDoubleTap,
    required this.onComment,
    required this.onShowLikes,
    required this.onShowVotes,
    required this.onVote,
    required this.getColorForDesignation,
    required this.formatDateTime,
  });

  @override
  Widget build(BuildContext context) {
    final isLiked = post.isLiked;
    final isPinned = post.isPinned ?? false;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF172A45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onDoubleTap: onDoubleTap,
            borderRadius: BorderRadius.circular(20),
            splashColor: const Color(0xFF4CC9F0).withOpacity(0.08),
            highlightColor: const Color(0xFF4CC9F0).withOpacity(0.04),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              getColorForDesignation(post.authorDesignation ?? ''),
                              getColorForDesignation(post.authorDesignation ?? '')
                                  .withOpacity(0.5),
                            ],
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFF172A45),
                          child: Text(
                            post.authorName.isNotEmpty
                                ? post.authorName
                                    .substring(0, min(1, post.authorName.length))
                                    .toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    post.authorName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: getColorForDesignation(
                                            post.authorDesignation ?? '')
                                        .withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    post.authorDesignation ?? 'Staff',
                                    style: TextStyle(
                                      color: getColorForDesignation(
                                          post.authorDesignation ?? ''),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (isPinned) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.amber.withOpacity(0.35)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.push_pin, size: 12, color: Colors.amber),
                                        SizedBox(width: 4),
                                        Text(
                                          'Pinned',
                                          style: TextStyle(
                                            color: Colors.amber,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatDateTime(post.createdAt),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.55),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ✅ NEW: 3 dots menu (AM/Manager only)
                      if (canManagePost)
                        IconButton(
                          onPressed: onMenu,
                          icon: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.8)),
                          splashRadius: 20,
                        ),
                    ],
                  ),
                ),

                // Content
                if (post.content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      post.content,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ),

                // Image
                if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: post.imageUrl!.startsWith('data:image')
                          ? Image.memory(
                              base64Decode(post.imageUrl!.split(',').last),
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 300,
                              errorBuilder: (_, __, ___) => _imgError(),
                            )
                          : Image.network(
                              post.imageUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: 300,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  height: 300,
                                  color: Colors.white12,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF4CC9F0),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (_, __, ___) => _imgError(),
                            ),
                    ),
                  ),

                // Poll (fixed: onTap calls onVote)
                if (post.poll != null)
                  _PollCardInline(
                    poll: post.poll!,
                    onVote: onVote,
                    onShowVotes: onShowVotes,
                  ),

                // Bulk Mentions
                if (post.bulkMentions.isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: post.bulkMentions.map((bulk) {
                        final upperBulk = bulk.toUpperCase();
                        Color badgeColor;
                        switch (upperBulk) {
                          case 'FOH':
                            badgeColor = Colors.green;
                            break;
                          case 'BOH':
                            badgeColor = Colors.blue;
                            break;
                          case 'EVERYONE':
                          case 'ALL':
                            badgeColor = Colors.purple;
                            break;
                          default:
                            badgeColor = const Color(0xFF4CC9F0);
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: badgeColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: badgeColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            '@$bulk',
                            style: TextStyle(
                              color: badgeColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                // Action bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  child: Row(
                    children: [
                      AnimatedScale(
                        scale: isLiked ? 1.10 : 1.0,
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        child: IconButton(
                          onPressed: onLike,
                          icon: Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            color:
                                isLiked ? Colors.red : Colors.white.withOpacity(0.75),
                          ),
                          iconSize: 28,
                          splashRadius: 20,
                        ),
                      ),
                      GestureDetector(
                        onTap: post.likes > 0 ? onShowLikes : null,
                        child: Text(
                          '${post.likes} ${post.likes == 1 ? 'like' : 'likes'}',
                          style: TextStyle(
                            color: isLiked ? Colors.red : Colors.white.withOpacity(0.72),
                            fontWeight: isLiked ? FontWeight.bold : FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        onPressed: onComment,
                        icon: const Icon(Icons.comment_outlined, color: Colors.white70),
                        iconSize: 26,
                        splashRadius: 20,
                      ),
                      Text(
                        '${post.comments} ${post.comments == 1 ? 'comment' : 'comments'}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Share feature coming soon!'),
                              backgroundColor: const Color(0xFF4CC9F0),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.share_outlined, color: Colors.white70),
                        iconSize: 24,
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _imgError() {
    return Container(
      height: 300,
      color: Colors.white12,
      child: const Center(
        child: Icon(Icons.broken_image, color: Colors.red, size: 50),
      ),
    );
  }
}

// ===========================================
// POLL CARD (inline) - fixed tap + optional "View votes"
// ===========================================
class _PollCardInline extends StatelessWidget {
  final Poll poll;
  final void Function(String optionId) onVote;
  final VoidCallback? onShowVotes;

  const _PollCardInline({
    required this.poll,
    required this.onVote,
    required this.onShowVotes,
  });

  @override
  Widget build(BuildContext context) {
    final totalVotes = poll.options.fold<int>(0, (sum, opt) => sum + opt.votes);
    final hasVoted = poll.hasVoted;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasVoted
                ? const Color(0xFF4CC9F0).withOpacity(0.3)
                : Colors.white.withOpacity(0.05),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.poll,
                  color: hasVoted
                      ? const Color(0xFF4CC9F0)
                      : Colors.white.withOpacity(0.7),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    poll.question,
                    style: TextStyle(
                      color: hasVoted ? const Color(0xFF4CC9F0) : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      height: 1.4,
                    ),
                  ),
                ),
                if (onShowVotes != null && totalVotes > 0)
                  TextButton(
                    onPressed: onShowVotes,
                    child: const Text(
                      'View votes',
                      style: TextStyle(
                        color: Color(0xFF4CC9F0),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            ...poll.options.map(
              (opt) => _PollOption(
                option: opt,
                totalVotes: totalVotes,
                onTap: () => onVote(opt.id), // ✅ FIXED
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: hasVoted
                        ? Colors.green.withOpacity(0.1)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hasVoted ? Icons.check_circle : Icons.how_to_vote,
                        color: hasVoted
                            ? Colors.green
                            : Colors.white.withOpacity(0.5),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hasVoted ? 'Voted' : 'Tap to vote',
                        style: TextStyle(
                          color: hasVoted
                              ? Colors.green
                              : Colors.white.withOpacity(0.55),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (totalVotes > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CC9F0).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF4CC9F0).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.people,
                            size: 14, color: Color(0xFF4CC9F0)),
                        const SizedBox(width: 6),
                        Text(
                          '$totalVotes ${totalVotes == 1 ? 'vote' : 'votes'}',
                          style: const TextStyle(
                            color: Color(0xFF4CC9F0),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PollOption extends StatelessWidget {
  final PollOption option;
  final int totalVotes;
  final VoidCallback onTap;

  const _PollOption({
    required this.option,
    required this.totalVotes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = totalVotes > 0 ? (option.votes / totalVotes * 100) : 0.0;
    final isSelected = option.isSelected;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: const Color(0xFF4CC9F0), width: 1.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isSelected)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.check_circle,
                        color: Color(0xFF4CC9F0), size: 18),
                  ),
                Expanded(
                  child: Text(
                    option.text,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                Text(
                  '${option.votes}',
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF4CC9F0)
                        : Colors.white.withOpacity(0.55),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ✅ FIXED width: use LayoutBuilder instead of MediaQuery width (prevents overflow)
            LayoutBuilder(
              builder: (context, constraints) {
                final barWidth = constraints.maxWidth * (percentage / 100);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Container(
                        height: 40,
                        width: constraints.maxWidth,
                        color: Colors.white.withOpacity(0.05),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                        height: 40,
                        width: barWidth,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              isSelected
                                  ? const Color(0xFF4CC9F0)
                                  : const Color(0xFF4CC9F0).withOpacity(0.65),
                              isSelected
                                  ? const Color(0xFF4CC9F0).withOpacity(0.8)
                                  : const Color(0xFF4CC9F0).withOpacity(0.35),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  option.text,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Text(
                                '${percentage.toStringAsFixed(1)}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================
// COMMENTS SHEET
// ===========================================
class _CommentsSheet extends StatefulWidget {
  final String dbName;
  final String postId;
  final String currentUserEmail;
  final String currentUserName;

  final String Function(String) getInitials;
  final Color Function(String) getColorForDesignation;
  final String Function(dynamic) formatDateTime;

  final FeedService feedService;
  final Future<void> Function() onAnyChange;

  const _CommentsSheet({
    required this.dbName,
    required this.postId,
    required this.currentUserEmail,
    required this.currentUserName,
    required this.getInitials,
    required this.getColorForDesignation,
    required this.formatDateTime,
    required this.feedService,
    required this.onAnyChange,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final DraggableScrollableController _dragController =
      DraggableScrollableController();

  final TextEditingController _composer = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _loading = true;
  bool _submitting = false;

  List<Map<String, dynamic>> _threads = [];

  String? _replyToCommentId;
  String? _replyToAuthor;

  @override
  void initState() {
    super.initState();

    // ✅ so Send button updates immediately when typing
    _composer.addListener(() {
      if (mounted) setState(() {});
    });

    _loadComments();
  }

  @override
  void dispose() {
    _composer.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _loading = true);

    try {
      final raw = await widget.feedService.getComments(
        db: widget.dbName,
        postId: widget.postId,
      );

      final threads = _normalizeThreads(raw);

      if (!mounted) return;
      setState(() {
        _threads = threads;
        _loading = false;
      });
    } catch (e) {
      debugPrint("❌ _loadComments error: $e");
      if (!mounted) return;

      setState(() => _loading = false);

      // ✅ keep existing comments visible
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to load comments'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<Map<String, dynamic>> _normalizeThreads(List<dynamic> raw) {
    final list = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final hasNested = list.any((c) => c['replies'] != null);
    if (hasNested) {
      for (final c in list) {
        if (c['replies'] is List) {
          c['replies'] = (c['replies'] as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
        } else {
          c['replies'] = <Map<String, dynamic>>[];
        }
      }
      return list;
    }

    final byId = <String, Map<String, dynamic>>{};
    for (final c in list) {
      final id = (c['id'] ?? '').toString();
      if (id.isEmpty) continue;
      byId[id] = c..putIfAbsent('replies', () => <Map<String, dynamic>>[]);
    }

    final roots = <Map<String, dynamic>>[];
    for (final c in byId.values) {
      final parentId = c['parentCommentId']?.toString();
      if (parentId == null || parentId.isEmpty || !byId.containsKey(parentId)) {
        roots.add(c);
      } else {
        (byId[parentId]!['replies'] as List).add(c);
      }
    }

    return roots;
  }

  void _setReplyTarget({required String commentId, required String author}) {
    setState(() {
      _replyToCommentId = commentId;
      _replyToAuthor = author;
    });

    _dragController.animateTo(
      0.95,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );

    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _focus.requestFocus();
    });
  }

  void _clearReplyTarget() {
    setState(() {
      _replyToCommentId = null;
      _replyToAuthor = null;
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _submitting) return;

    // ✅ Fix: capture reply state BEFORE clearing
    final wasReply = _replyToCommentId != null;

    setState(() => _submitting = true);
    try {
      final result = await widget.feedService.addComment(
        db: widget.dbName,
        postId: widget.postId,
        userEmail: widget.currentUserEmail,
        content: text,
        parentCommentId: _replyToCommentId,
      );

      if (!mounted) return;

      if (result != null) {
        _composer.clear();
        _clearReplyTarget();
        await _loadComments();
        await widget.onAnyChange();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(wasReply ? 'Reply posted!' : 'Comment posted!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ send comment error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reactToComment({
    required String commentId,
    required String emoji,
  }) async {
    try {
      await widget.feedService.toggleReaction(
        db: widget.dbName,
        commentId: commentId,
        userEmail: widget.currentUserEmail,
        emoji: emoji,
      );
      await _loadComments();
    } catch (e) {
      debugPrint("❌ reactToComment error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _dragController,
      initialChildSize: 0.90,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0A192F),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline,
                        color: Color(0xFF4CC9F0), size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Comments',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              if (_replyToCommentId != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF172A45),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.reply,
                          color: Color(0xFF4CC9F0), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Replying to @${_replyToAuthor ?? ''}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: _clearReplyTarget,
                        icon: const Icon(Icons.close,
                            color: Colors.white54, size: 18),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF4CC9F0),
                          strokeWidth: 2,
                        ),
                      )
                    : _threads.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chat_bubble_outline,
                                    size: 64,
                                    color: Colors.white.withOpacity(0.10)),
                                const SizedBox(height: 14),
                                Text(
                                  'No comments yet',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.55),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Be the first to comment',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.35),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 12),
                            itemCount: _threads.length,
                            itemBuilder: (context, index) {
                              final comment = _threads[index];
                              return _CommentThread(
                                comment: comment,
                                isReply: false,
                                currentUserEmail: widget.currentUserEmail,
                                getInitials: widget.getInitials,
                                getColorForDesignation:
                                    widget.getColorForDesignation,
                                formatDateTime: widget.formatDateTime,
                                onReply: (commentId, author) => _setReplyTarget(
                                  commentId: commentId,
                                  author: author,
                                ),
                                onReact: (commentId, emoji) => _reactToComment(
                                  commentId: commentId,
                                  emoji: emoji,
                                ),
                              );
                            },
                          ),
              ),

              // composer
              Container(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 10,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF172A45),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withOpacity(0.08),
                      width: 0.8,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          const Color(0xFF4CC9F0).withOpacity(0.20),
                      child: Text(
                        widget.getInitials(widget.currentUserName),
                        style: const TextStyle(
                          color: Color(0xFF4CC9F0),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: MentionTextField(
                            controller: _composer,
                            dbName: widget.dbName,
                            currentUserEmail: widget.currentUserEmail,
                            hintText: _replyToCommentId != null
                                ? 'Write a reply... (@ to mention)'
                                : 'Add a comment... (@ to mention)',
                            maxLines: 4,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                            onMentionSelected: (_) {},
                            focusNode: _focus,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: _composer.text.trim().isNotEmpty
                            ? const Color(0xFF4CC9F0)
                            : const Color(0xFF4CC9F0).withOpacity(0.35),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: IconButton(
                        onPressed: _composer.text.trim().isNotEmpty ? _send : null,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send,
                                color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CommentThread extends StatelessWidget {
  final Map<String, dynamic> comment;
  final bool isReply;
  final String currentUserEmail;

  final String Function(String) getInitials;
  final Color Function(String) getColorForDesignation;
  final String Function(dynamic) formatDateTime;

  final void Function(String commentId, String author) onReply;
  final void Function(String commentId, String emoji) onReact;

  const _CommentThread({
    required this.comment,
    required this.isReply,
    required this.currentUserEmail,
    required this.getInitials,
    required this.getColorForDesignation,
    required this.formatDateTime,
    required this.onReply,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final replies =
        (comment['replies'] is List) ? (comment['replies'] as List) : const [];
    return Padding(
      padding: EdgeInsets.only(bottom: isReply ? 10 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentTile(
            comment: comment,
            isReply: isReply,
            currentUserEmail: currentUserEmail,
            getInitials: getInitials,
            getColorForDesignation: getColorForDesignation,
            formatDateTime: formatDateTime,
            onReply: onReply,
            onReact: onReact,
          ),
          if (replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 8),
              child: Column(
                children: replies
                    .map((r) => _CommentThread(
                          comment: Map<String, dynamic>.from(r as Map),
                          isReply: true,
                          currentUserEmail: currentUserEmail,
                          getInitials: getInitials,
                          getColorForDesignation: getColorForDesignation,
                          formatDateTime: formatDateTime,
                          onReply: onReply,
                          onReact: onReact,
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Map<String, dynamic> comment;
  final bool isReply;
  final String currentUserEmail;

  final String Function(String) getInitials;
  final Color Function(String) getColorForDesignation;
  final String Function(dynamic) formatDateTime;

  final void Function(String commentId, String author) onReply;
  final void Function(String commentId, String emoji) onReact;

  const _CommentTile({
    required this.comment,
    required this.isReply,
    required this.currentUserEmail,
    required this.getInitials,
    required this.getColorForDesignation,
    required this.formatDateTime,
    required this.onReply,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrentUser = (comment['userEmail'] ?? '') == currentUserEmail;

    final reactionCounts = (comment['reactions']?['counts'] is Map)
        ? Map<String, dynamic>.from(comment['reactions']['counts'])
        : <String, dynamic>{};
    final totalReactions = (comment['reactions']?['total'] is int)
        ? comment['reactions']['total'] as int
        : 0;

    final authorName =
        (comment['userName'] ?? comment['userEmail'] ?? '').toString();
    final designation = (comment['userDesignation'] ?? '').toString();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: isReply ? 15 : 18,
          backgroundColor: getColorForDesignation(designation),
          child: Text(
            getInitials(authorName),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: isReply ? 10 : 12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isCurrentUser
                  ? const Color(0xFF4CC9F0).withOpacity(0.10)
                  : Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCurrentUser
                    ? const Color(0xFF4CC9F0).withOpacity(0.22)
                    : Colors.white.withOpacity(0.06),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              authorName,
                              style: TextStyle(
                                color: isCurrentUser
                                    ? const Color(0xFF4CC9F0)
                                    : Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: isReply ? 13 : 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCurrentUser) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CC9F0).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'You',
                                style: TextStyle(
                                  color: Color(0xFF4CC9F0),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ] else if (designation.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: getColorForDesignation(designation)
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                designation,
                                style: TextStyle(
                                  color: getColorForDesignation(designation),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Text(
                      formatDateTime(comment['createdAt']),
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.45), fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  (comment['content'] ?? '').toString(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: isReply ? 14 : 15,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => onReply(comment['id'].toString(), authorName),
                      icon: const Icon(Icons.reply, size: 14),
                      label: const Text('Reply', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white60,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    _EmojiChip(
                        emoji: '❤️',
                        onTap: () => onReact(comment['id'].toString(), '❤️')),
                    _EmojiChip(
                        emoji: '😂',
                        onTap: () => onReact(comment['id'].toString(), '😂')),
                    _EmojiChip(
                        emoji: '😮',
                        onTap: () => onReact(comment['id'].toString(), '😮')),
                    _EmojiChip(
                        emoji: '👍',
                        onTap: () => onReact(comment['id'].toString(), '👍')),
                    _EmojiChip(
                        emoji: '🔥',
                        onTap: () => onReact(comment['id'].toString(), '🔥')),
                  ],
                ),
                if (totalReactions > 0) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 22,
                    child: Row(
                      children: [
                        SizedBox(
                          height: 22,
                          width: 60,
                          child: Stack(
                            children: reactionCounts.keys
                                .take(3)
                                .toList()
                                .asMap()
                                .entries
                                .map((entry) {
                              final i = entry.key;
                              final emoji = entry.value;
                              return Positioned(
                                left: i * 18.0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF172A45),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.12)),
                                  ),
                                  child: Text(emoji,
                                      style: const TextStyle(fontSize: 12)),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$totalReactions',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.55), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmojiChip extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;

  const _EmojiChip({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}
