import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:t/t.dart' as t;
import '../../core/constants/app_constants.dart';
import '../models/course_model.dart';
import 'telegram_auth_service.dart';

class TelegramChannelInfo {
  final int id;
  final String name;
  final bool isChannel;
  final bool isGroup;
  final int memberCount;
  final int messageCount;
  final int? accessHash;

  TelegramChannelInfo({
    required this.id,
    required this.name,
    required this.isChannel,
    required this.isGroup,
    this.memberCount = 0,
    this.messageCount = 0,
    this.accessHash,
  });

  factory TelegramChannelInfo.fromMap(Map<String, dynamic> map) {
    return TelegramChannelInfo(
      id: map['id'] is int ? map['id'] : int.parse('${map['id']}'),
      name: map['name'] ?? map['title'] ?? 'Untitled Channel',
      isChannel: map['is_channel'] == true,
      isGroup: map['is_group'] == true,
      memberCount: map['member_count'] ?? map['participants_count'] ?? 0,
      messageCount: map['message_count'] ?? 0,
      accessHash: map['access_hash'] is int ? map['access_hash'] : (map['access_hash'] != null ? int.tryParse('${map['access_hash']}') : null),
    );
  }
}

class TelegramImportService {
  static const int apiId = AppConstants.telegramApiId;
  static const String apiHash = AppConstants.telegramApiHash;

  static final Map<int, int> _channelAccessHashMap = {};

  static void cacheChannelAccessHash(int channelId, int accessHash) {
    _channelAccessHashMap[channelId] = accessHash;
  }

  /// Fetch user's real Telegram channels & supergroups directly via active MTProto session
  static Future<List<TelegramChannelInfo>> getAvailableChannels(String phone) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.isEmpty) return [];

    debugPrint('[TelegramImportService] 🔍 Fetching real Telegram channels/groups for $cleanPhone');

    try {
      final client = await TelegramAuthService.getClient();
      final res = await client.messages.getDialogs(
        excludePinned: false,
        folderId: null,
        offsetDate: DateTime.fromMillisecondsSinceEpoch(0),
        offsetId: 0,
        offsetPeer: const t.InputPeerEmpty(),
        limit: 100,
        hash: 0,
      );

      if (res.error != null) {
        final err = res.error!.errorMessage;
        debugPrint('[TelegramImportService] getDialogs RPC error: ${res.error!.errorCode} - $err');
        if (TelegramAuthService.isMigrateError(err)) {
          final targetDc = TelegramAuthService.extractDcFromMigrateError(err);
          debugPrint('[TelegramImportService] Migrating to DC $targetDc for getDialogs...');
          final migratedClient = await TelegramAuthService.getClient(dcId: targetDc, forceNew: true);
          final retryRes = await migratedClient.messages.getDialogs(
            excludePinned: false,
            folderId: null,
            offsetDate: DateTime.fromMillisecondsSinceEpoch(0),
            offsetId: 0,
            offsetPeer: const t.InputPeerEmpty(),
            limit: 100,
            hash: 0,
          );
          return _parseDialogsResult(retryRes);
        }
      }

      return _parseDialogsResult(res);
    } catch (e) {
      debugPrint('[TelegramImportService] MTProto dialogs fetch exception: $e');
    }

    return [];
  }

  static List<TelegramChannelInfo> _parseDialogsResult(t.Result<t.MessagesDialogsBase> res) {
    final List<TelegramChannelInfo> realChannels = [];
    final List<t.ChatBase> chats = [];

    if (res.result is t.MessagesDialogs) {
      chats.addAll((res.result as t.MessagesDialogs).chats);
    } else if (res.result is t.MessagesDialogsSlice) {
      chats.addAll((res.result as t.MessagesDialogsSlice).chats);
    }

    debugPrint('[TelegramImportService] Parsed ${chats.length} raw chats from Telegram getDialogs');

    for (final chat in chats) {
      if (chat is t.Channel) {
        if (chat.accessHash != null) {
          _channelAccessHashMap[chat.id] = chat.accessHash!;
        }
        debugPrint('   📺 Channel: id=${chat.id}, title="${chat.title}", broadcast=${chat.broadcast}, megagroup=${chat.megagroup}, participants=${chat.participantsCount}');
        realChannels.add(TelegramChannelInfo(
          id: chat.id,
          name: chat.title,
          isChannel: chat.broadcast,
          isGroup: chat.megagroup,
          memberCount: chat.participantsCount ?? 0,
          accessHash: chat.accessHash,
        ));
      } else if (chat is t.Chat) {
        debugPrint('   👥 Group: id=${chat.id}, title="${chat.title}", participants=${chat.participantsCount}');
        realChannels.add(TelegramChannelInfo(
          id: chat.id,
          name: chat.title,
          isChannel: false,
          isGroup: true,
          memberCount: chat.participantsCount,
          accessHash: null,
        ));
      }
    }

    debugPrint('[TelegramImportService] ✅ Total valid channels/groups found: ${realChannels.length}');
    return realChannels;
  }

  /// Resolve public Telegram channel username (e.g. @flutter_dev or t.me/flutter_dev)
  static Future<TelegramChannelInfo?> resolvePublicChannel(String username) async {
    var clean = username.trim().replaceAll('https://t.me/', '').replaceAll('t.me/', '').replaceAll('@', '');
    if (clean.isEmpty) return null;

    try {
      final client = await TelegramAuthService.getClient();
      final res = await client.contacts.resolveUsername(username: clean);
      if (res.result is t.ContactsResolvedPeer) {
        final resolved = res.result as t.ContactsResolvedPeer;
        for (final chat in resolved.chats) {
          if (chat is t.Channel) {
            if (chat.accessHash != null) {
              _channelAccessHashMap[chat.id] = chat.accessHash!;
            }
            return TelegramChannelInfo(
              id: chat.id,
              name: chat.title,
              isChannel: chat.broadcast,
              isGroup: chat.megagroup,
              memberCount: chat.participantsCount ?? 0,
              accessHash: chat.accessHash,
            );
          } else if (chat is t.Chat) {
            return TelegramChannelInfo(
              id: chat.id,
              name: chat.title,
              isChannel: false,
              isGroup: true,
              memberCount: chat.participantsCount,
              accessHash: null,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[TelegramImportService] resolveUsername error: $e');
    }
    return null;
  }

  /// Sync real Telegram channel messages into CourseModel exactly matching reference architecture
  static Future<CourseModel> syncCourseFromTelegram({
    required String phone,
    required int channelId,
    int? accessHash,
    String? channelName,
  }) async {
    final sw = Stopwatch()..start();
    debugPrint('[TelegramImportService] 🚀 Starting fast sync for channel $channelId ($channelName, accessHash: $accessHash)');

    try {
      var client = await TelegramAuthService.getClient();
      
      int? effectiveAccessHash = accessHash ?? _channelAccessHashMap[channelId];
      if (effectiveAccessHash == null) {
        final channels = await getAvailableChannels(phone);
        final found = channels.where((c) => c.id == channelId).firstOrNull;
        if (found?.accessHash != null) {
          effectiveAccessHash = found!.accessHash;
          _channelAccessHashMap[channelId] = effectiveAccessHash!;
        }
      }

      t.InputPeerBase peer;
      if (effectiveAccessHash != null) {
        peer = t.InputPeerChannel(channelId: channelId, accessHash: effectiveAccessHash);
      } else {
        peer = t.InputPeerChat(chatId: channelId);
      }

      // 1. Discover Forum Topics via paginated RPC
      final Map<int, String> topicsMap = {0: 'General'};
      try {
        int offsetTopicId = 0;
        int offsetTopic = 0;
        for (int p = 0; p < 20; p++) {
          final topicsRes = await client.messages.getForumTopics(
            peer: peer,
            offsetDate: DateTime.fromMillisecondsSinceEpoch(0),
            offsetId: offsetTopicId,
            offsetTopic: offsetTopic,
            limit: 100,
          );
          if (topicsRes.error != null) {
            final err = topicsRes.error!.errorMessage;
            debugPrint('[TelegramImportService] ⚠️ getForumTopics note: ${topicsRes.error!.errorCode} - $err');
            if (TelegramAuthService.isMigrateError(err)) {
              final targetDc = TelegramAuthService.extractDcFromMigrateError(err);
              client = await TelegramAuthService.getClient(dcId: targetDc, forceNew: true);
              continue;
            }
            break;
          }
          if (topicsRes.result is t.MessagesForumTopics) {
            final forumTopics = (topicsRes.result as t.MessagesForumTopics).topics;
            if (forumTopics.isEmpty) break;
            for (final top in forumTopics) {
              if (top is t.ForumTopic && top.title.trim().isNotEmpty) {
                topicsMap[top.id] = top.title.trim();
              }
            }
            if (forumTopics.length < 100) break;
            final last = forumTopics.last;
            if (last is t.ForumTopic) {
              offsetTopicId = last.id;
              offsetTopic = last.id;
            } else {
              break;
            }
          } else {
            break;
          }
        }
        debugPrint('[TelegramImportService] 📂 Discovered ${topicsMap.length} forum topics/sub-modules:');
        topicsMap.forEach((tid, tTitle) {
          debugPrint('   ↳ [Topic #$tid] "$tTitle"');
        });
      } catch (e) {
        debugPrint('[TelegramImportService] getForumTopics exception: $e');
      }

      final List<t.MessageBase> allRawMessages = [];
      int offsetId = 0;
      const int batchLimit = 100;
      const int maxMessagesToFetch = 8000;

      // 2. Fetch message history with non-blocking streaming
      while (allRawMessages.length < maxMessagesToFetch) {
        final historyRes = await client.messages.getHistory(
          peer: peer,
          offsetId: offsetId,
          offsetDate: DateTime.fromMillisecondsSinceEpoch(0),
          addOffset: 0,
          limit: batchLimit,
          maxId: 0,
          minId: 0,
          hash: 0,
        );

        if (historyRes.error != null) {
          final err = historyRes.error!.errorMessage;
          debugPrint('[TelegramImportService] ❌ getHistory error: ${historyRes.error!.errorCode} - $err');
          if (TelegramAuthService.isMigrateError(err)) {
            final targetDc = TelegramAuthService.extractDcFromMigrateError(err);
            debugPrint('[TelegramImportService] Migrating to DC $targetDc for getHistory...');
            client = await TelegramAuthService.getClient(dcId: targetDc, forceNew: true);
            continue;
          }
          break;
        }

        final List<t.MessageBase> batch = [];
        int? totalChannelCount;
        if (historyRes.result is t.MessagesMessages) {
          batch.addAll((historyRes.result as t.MessagesMessages).messages);
        } else if (historyRes.result is t.MessagesMessagesSlice) {
          final slice = historyRes.result as t.MessagesMessagesSlice;
          batch.addAll(slice.messages);
          totalChannelCount = slice.count;
        } else if (historyRes.result is t.MessagesChannelMessages) {
          final cm = historyRes.result as t.MessagesChannelMessages;
          batch.addAll(cm.messages);
          totalChannelCount = cm.count;
        }

        if (batch.isEmpty) break;
        allRawMessages.addAll(batch);
        debugPrint('[TelegramImportService] 📥 History batch: +${batch.length} messages (Total: ${allRawMessages.length}${totalChannelCount != null ? ' / $totalChannelCount' : ''})');

        // Discover Topic Creation/Edit actions inside message history
        for (final m in batch) {
          if (m is t.MessageService) {
            if (m.action is t.MessageActionTopicCreate) {
              final act = m.action as t.MessageActionTopicCreate;
              if (act.title.trim().isNotEmpty) {
                topicsMap[m.id] = act.title.trim();
              }
            } else if (m.action is t.MessageActionTopicEdit) {
              final act = m.action as t.MessageActionTopicEdit;
              if (act.title != null && act.title!.trim().isNotEmpty) {
                topicsMap[m.id] = act.title!.trim();
              }
            }
          }
        }

        if (batch.length < batchLimit) break;

        int minId = 0x7FFFFFFF;
        for (final m in batch) {
          int? mId;
          if (m is t.Message) {
            mId = m.id;
          } else if (m is t.MessageService) {
            mId = m.id;
          } else if (m is t.MessageEmpty) {
            mId = m.id;
          }
          if (mId != null && mId < minId) minId = mId;
        }

        if (minId == 0x7FFFFFFF || (minId >= offsetId && offsetId != 0)) {
          break;
        }
        offsetId = minId;
      }

      // Sort messages in chronological order (oldest to newest)
      final messages = allRawMessages.whereType<t.Message>().toList();
      messages.sort((a, b) => a.id.compareTo(b.id));

      // 3. Map messages into modules by topic ID and message reply inheritance
      final Map<int, int> messageToTopicMap = {};
      final Map<int, Map<String, dynamic>> modulesDict = {};

      for (int i = 0; i < messages.length; i++) {
        final msg = messages[i];
        if (msg.media == null) continue;

        int topicId = 0;
        if (msg.replyTo is t.MessageReplyHeader) {
          final replyHeader = msg.replyTo as t.MessageReplyHeader;
          if (replyHeader.replyToTopId != null && replyHeader.replyToTopId! > 0) {
            topicId = replyHeader.replyToTopId!;
          } else if (replyHeader.forumTopic && replyHeader.replyToMsgId != null && replyHeader.replyToMsgId! > 0) {
            topicId = replyHeader.replyToMsgId!;
          } else if (replyHeader.replyToMsgId != null && messageToTopicMap.containsKey(replyHeader.replyToMsgId)) {
            topicId = messageToTopicMap[replyHeader.replyToMsgId]!;
          } else if (replyHeader.replyToMsgId != null && topicsMap.containsKey(replyHeader.replyToMsgId)) {
            topicId = replyHeader.replyToMsgId!;
          }
        }

        messageToTopicMap[msg.id] = topicId;

        final topicTitle = topicsMap[topicId] ?? (topicId == 0 ? 'General' : 'Topic #$topicId');
        if (!modulesDict.containsKey(topicId)) {
          modulesDict[topicId] = {
            'id': topicId,
            'title': topicTitle,
            'lessons': <CourseLesson>[],
            'notes': <CourseNote>[],
          };
        } else if (modulesDict[topicId]!['title'].toString().startsWith('Topic #') && topicsMap.containsKey(topicId)) {
          modulesDict[topicId]!['title'] = topicsMap[topicId]!;
        }

        final media = msg.media;
        if (media is t.MessageMediaDocument && media.document is t.Document) {
          final doc = media.document as t.Document;
          final mime = doc.mimeType.toLowerCase();

          String? fileName;
          num duration = 0;
          bool isVideo = false;

          for (final attr in doc.attributes) {
            if (attr is t.DocumentAttributeFilename) {
              fileName = attr.fileName;
            } else if (attr is t.DocumentAttributeVideo) {
              isVideo = true;
              duration = attr.duration;
            }
          }

          if (mime.startsWith('video/') ||
              mime == 'application/octet-stream' ||
              mime == 'video/x-matroska') {
            if (fileName != null && (fileName.endsWith('.mp4') || fileName.endsWith('.mkv') || fileName.endsWith('.mov') || fileName.endsWith('.webm') || fileName.endsWith('.avi'))) {
              isVideo = true;
            }
          }

          if (fileName == null || fileName.trim().isEmpty) {
            final firstLine = msg.message.trim().split('\n').first;
            fileName = firstLine.isNotEmpty ? (firstLine.length > 80 ? '${firstLine.substring(0, 77)}...' : firstLine) : (isVideo ? 'Lesson ${msg.id}' : 'Note ${msg.id}');
          }

          final cleanName = _cleanTitle(fileName);

          if (isVideo) {
            final fileRefHex = _bytesToHex(doc.fileReference);
            final streamUrl = 'http://127.0.0.1:${AppConstants.localProxyPort}/tg_stream?dc_id=${doc.dcId}&doc_id=${doc.id}&access_hash=${doc.accessHash}&size=${doc.size}&mime=${Uri.encodeComponent(doc.mimeType)}&file_ref=$fileRefHex';

            final lesson = CourseLesson(
              id: msg.id,
              title: cleanName,
              duration: duration > 0 ? duration : (doc.size ~/ (128 * 1024)),
              size: doc.size,
              videoUrl: streamUrl,
            );
            (modulesDict[topicId]!['lessons'] as List<CourseLesson>).add(lesson);
          } else {
            final fileRefHex = _bytesToHex(doc.fileReference);
            final streamUrl = 'http://127.0.0.1:${AppConstants.localProxyPort}/tg_stream?dc_id=${doc.dcId}&doc_id=${doc.id}&access_hash=${doc.accessHash}&size=${doc.size}&mime=${Uri.encodeComponent(doc.mimeType)}&file_ref=$fileRefHex';

            final note = CourseNote(
              id: msg.id,
              title: cleanName,
              fileName: fileName,
              fileUrl: streamUrl,
              size: doc.size,
              text: msg.message.trim().isNotEmpty ? msg.message.trim() : 'Reference document from Telegram channel',
            );
            (modulesDict[topicId]!['notes'] as List<CourseNote>).add(note);
          }
        } else if (media is t.MessageMediaPhoto) {
          final firstLine = msg.message.trim().split('\n').first;
          final photoTitle = firstLine.isNotEmpty ? _cleanTitle(firstLine) : 'Photo Note ${msg.id}';
          final note = CourseNote(
            id: msg.id,
            title: photoTitle,
            fileName: '$photoTitle.jpg',
            size: 0,
            text: msg.message.trim(),
          );
          (modulesDict[topicId]!['notes'] as List<CourseNote>).add(note);
        }
      }

      // Filter and sort modules (General/Topic 0 first, then topic ID ascending)
      final List<CourseModule> parsedModules = [];
      final activeEntries = modulesDict.values.where((m) =>
          (m['lessons'] as List).isNotEmpty || (m['notes'] as List).isNotEmpty).toList();

      activeEntries.sort((a, b) {
        final aId = a['id'] as int;
        final bId = b['id'] as int;
        if (aId == 0) return -1;
        if (bId == 0) return 1;
        return aId.compareTo(bId);
      });

      for (final entry in activeEntries) {
        final modId = entry['id'] as int;
        var modTitle = entry['title'].toString().trim();
        if (modTitle.isEmpty || modTitle.toLowerCase() == 'general') {
          modTitle = activeEntries.length > 1 ? 'General & Overview' : (channelName ?? 'Lectures & Materials');
        }

        parsedModules.add(CourseModule(
          id: modId,
          title: modTitle,
          lessons: entry['lessons'] as List<CourseLesson>,
          notes: entry['notes'] as List<CourseNote>,
        ));
      }

      if (parsedModules.isEmpty) {
        parsedModules.add(CourseModule(
          id: 1,
          title: 'Course Content',
          lessons: [],
          notes: [],
        ));
      }

      final title = channelName ?? 'Telegram Course #$channelId';
      final totalLessons = parsedModules.fold<int>(0, (sum, m) => sum + m.lessons.length);
      final totalNotes = parsedModules.fold<int>(0, (sum, m) => sum + m.notes.length);

      debugPrint('[TelegramImportService] 📊 SYNC REPORT FOR "$title":');
      for (final mod in parsedModules) {
        debugPrint('  📚 [Sub-Module: "${mod.title}" (ID: ${mod.id})] - ${mod.lessons.length} videos, ${mod.notes.length} notes');
      }
      debugPrint('🏁 Total: $totalLessons Video Lectures, $totalNotes Documents across ${parsedModules.length} Sub-Modules in ${sw.elapsedMilliseconds}ms');

      return CourseModel(
        id: '$channelId',
        channelId: channelId,
        title: title,
        description: 'Synced from Telegram channel "$title". Contains $totalLessons video lectures and $totalNotes reference documents.',
        modules: parsedModules,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[TelegramImportService] Error syncing channel: $e');
      rethrow;
    }
  }


  static String _cleanTitle(String rawTitle) {
    var title = rawTitle.trim();
    if (title.isEmpty) return 'Untitled Lesson';

    // Remove common file extension suffixes
    title = title.replaceAll(RegExp(r'\.(mp4|mkv|mov|webm|avi|ts|flv|3gp|wmv|m4v|pdf|epub|zip|rar|txt|doc|docx)$', caseSensitive: false), '');

    // Remove channel @ handles and web URLs
    title = title.replaceAll(RegExp(r'@[A-Za-z0-9_]+'), '').replaceAll(RegExp(r'https?:\/\/\S+'), '');

    // Remove resolution and codec tags like [1080p], (720p), [x264], etc.
    title = title.replaceAll(RegExp(r'\[(?:\d{3,4}p|x264|x265|HEVC|WEBRip|HD)\]', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\((?:\d{3,4}p|x264|x265|HEVC|WEBRip|HD)\)', caseSensitive: false), '');

    // Normalize underscores and multiple spaces
    title = title.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    return title.isNotEmpty ? title : 'Untitled Lesson';
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

