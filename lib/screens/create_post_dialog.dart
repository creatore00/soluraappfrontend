// screens/create_post_dialog.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/session.dart';
import '../widgets/mention_text_field.dart';

Future<void> showCreatePostDialog(
  BuildContext context,
  String dbName,
  String userEmail,
  VoidCallback onPostCreated,
) async {
  final TextEditingController contentController = TextEditingController();
  final List<XFile> selectedImages = [];
  final List<XFile> selectedVideos = [];
  
  // Poll related
  bool hasPoll = false;
  String pollQuestion = '';
  List<TextEditingController> pollOptionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool pollMultipleChoice = false;
  
  bool isSubmitting = false;

  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          backgroundColor: const Color(0xFF172A45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          title: Row(
            children: [
              Icon(Icons.post_add, color: const Color(0xFF4CC9F0), size: 28),
              const SizedBox(width: 12),
              const Text(
                'Create Post',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Container(
            width: 550,
            constraints: const BoxConstraints(maxHeight: 600),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Text input with mentions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: MentionTextField(
                      controller: contentController,
                      dbName: dbName,
                      currentUserEmail: userEmail,
                      hintText: "What's on your mind? Use @ to mention colleagues...",
                      maxLines: 5,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                      onMentionSelected: (employee) {
                        // Handle mention selection if needed
                        print('Selected: ${employee['fullName']}');
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Images preview
                  if (selectedImages.isNotEmpty)
                    Container(
                      height: 100,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: selectedImages.length,
                        itemBuilder: (context, index) {
                          return Stack(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  image: DecorationImage(
                                    image: FileImage(File(selectedImages[index].path)),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 12,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      selectedImages.removeAt(index);
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.8),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  
                  // Videos preview
                  if (selectedVideos.isNotEmpty)
                    Container(
                      height: 100,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: selectedVideos.length,
                        itemBuilder: (context, index) {
                          return Stack(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.black54,
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.video_library,
                                    color: Colors.white.withOpacity(0.7),
                                    size: 40,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 12,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      selectedVideos.removeAt(index);
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.8),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  
                  // Poll section
                  if (hasPoll)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF4CC9F0).withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Poll',
                                style: TextStyle(
                                  color: Color(0xFF4CC9F0),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                                onPressed: () {
                                  setState(() {
                                    hasPoll = false;
                                    pollQuestion = '';
                                    pollOptionControllers = [
                                      TextEditingController(),
                                      TextEditingController(),
                                    ];
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            onChanged: (value) => pollQuestion = value,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Ask a question...',
                              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFF4CC9F0)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ...List.generate(pollOptionControllers.length, (index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                                    ),
                                    child: Center(
                                      child: Text(
                                        String.fromCharCode(65 + index),
                                        style: TextStyle(color: Colors.white.withOpacity(0.7)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: pollOptionControllers[index],
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        hintText: 'Option ${index + 1}',
                                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.05),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide.none,
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: const BorderSide(color: Color(0xFF4CC9F0)),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                    ),
                                  ),
                                  if (index >= 2)
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                                      onPressed: () {
                                        setState(() {
                                          pollOptionControllers.removeAt(index);
                                        });
                                      },
                                    ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: pollOptionControllers.length < 5 
                              ? () {
                                  setState(() {
                                    pollOptionControllers.add(TextEditingController());
                                  });
                                }
                              : null,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Option'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF4CC9F0),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Text(
                                'Multiple choice',
                                style: TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(width: 12),
                              Switch(
                                value: pollMultipleChoice,
                                onChanged: (value) {
                                  setState(() {
                                    pollMultipleChoice = value;
                                  });
                                },
                                activeColor: const Color(0xFF4CC9F0),
                                activeTrackColor: const Color(0xFF4CC9F0).withOpacity(0.5),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  
                  const SizedBox(height: 16),
                  
                  // Action buttons for media
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildActionButton(
                          icon: Icons.image,
                          label: 'Image',
                          color: Colors.green,
                          onTap: () async {
                            final picker = ImagePicker();
                            final images = await picker.pickMultiImage();
                            if (images.isNotEmpty) {
                              setState(() {
                                selectedImages.addAll(images);
                              });
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                        _buildActionButton(
                          icon: Icons.videocam,
                          label: 'Video',
                          color: Colors.orange,
                          onTap: () async {
                            final picker = ImagePicker();
                            final video = await picker.pickVideo(source: ImageSource.gallery);
                            if (video != null) {
                              setState(() {
                                selectedVideos.add(video);
                              });
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                        _buildActionButton(
                          icon: Icons.poll,
                          label: 'Poll',
                          color: Colors.purple,
                          onTap: () {
                            setState(() {
                              hasPoll = !hasPoll;
                              if (!hasPoll) {
                                pollQuestion = '';
                                pollOptionControllers = [
                                  TextEditingController(),
                                  TextEditingController(),
                                ];
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Info message
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A192F).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF4CC9F0).withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: const Color(0xFF4CC9F0),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Type @ to mention colleagues. They will be notified.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isSubmitting
                      ? Colors.white.withOpacity(0.3)
                      : const Color(0xFF4CC9F0),
                  fontSize: 16,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (contentController.text.trim().isEmpty && 
                          selectedImages.isEmpty && 
                          selectedVideos.isEmpty && 
                          !hasPoll) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter some content or add media'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }

                      setState(() => isSubmitting = true);

try {
  // Parse mentions from content
  final mentionRegex = RegExp(r'@([^\s@]+)');
  final matches = mentionRegex.allMatches(contentController.text);
  
  final List<String> mentions = [];
  final List<String> bulkMentions = [];
  
  for (final match in matches) {
    final mention = match.group(1) ?? '';
    final cleanMention = mention.trim();
    
    if (cleanMention.isNotEmpty) {
      // Check if it's a bulk mention (FOH, BOH, EVERYONE - case insensitive)
      final upperMention = cleanMention.toUpperCase();
      if (upperMention == 'FOH' || 
          upperMention == 'BOH' || 
          upperMention == 'EVERYONE' ||
          upperMention == 'ALL') {
        bulkMentions.add(upperMention);
      } else {
        mentions.add(cleanMention);
      }
    }
  }

  // Prepare attachments
  final attachments = [];
  
  // Process images
  for (var image in selectedImages) {
    final bytes = await image.readAsBytes();
    attachments.add({
      'type': 'image',
      'name': image.name,
      'data': base64Encode(bytes),
      'size': bytes.length,
    });
  }
  
  // Process videos (metadata only)
  for (var video in selectedVideos) {
    final file = File(video.path);
    final fileSize = await file.length();
    attachments.add({
      'type': 'video',
      'name': video.name,
      'size': fileSize,
    });
  }

  // Prepare poll data
  Map<String, dynamic>? pollData;
  if (hasPoll) {
    final options = pollOptionControllers
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    
    if (pollQuestion.trim().isNotEmpty && options.length >= 2) {
      pollData = {
        'question': pollQuestion.trim(),
        'options': options,
        'multipleChoice': pollMultipleChoice,
      };
    }
  }

  // Build request body
  final requestBody = {
    'db': dbName,
    'authorEmail': userEmail,
    'content': contentController.text.trim(),
    'attachments': attachments,
    'visibility': 'all',
    'mentions': mentions,
  };
  
  // Only add bulkMentions if there are any
  if (bulkMentions.isNotEmpty) {
    requestBody['bulkMentions'] = bulkMentions;
  }
  
  // Add poll data if exists
  if (pollData != null) {
    requestBody['poll'] = pollData;
  }

  print('📝 Creating post with:');
  print('   - Mentions: $mentions');
  print('   - Bulk mentions: $bulkMentions');
  print('   - Attachments: ${attachments.length}');
  print('   - Has poll: ${pollData != null}');

  final response = await http.post(
    Uri.parse("${AuthService.baseUrl}/feed/create"),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(requestBody),
  );

  final data = jsonDecode(response.body);

  if (data['success'] == true) {
    if (dialogContext.mounted) {
      Navigator.pop(dialogContext);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post created successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      onPostCreated();
    }
  } else {
    throw Exception(data['message'] ?? 'Failed to create post');
  }
} catch (e) {
  if (dialogContext.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error: ${e.toString()}'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }
} finally {
  if (dialogContext.mounted) {
    setState(() => isSubmitting = false);
  }
}
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CC9F0),
                foregroundColor: Colors.white,
                minimumSize: const Size(120, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Post',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        );
      },
    ),
  );
}

Widget _buildActionButton({
  required IconData icon,
  required String label,
  required Color color,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}