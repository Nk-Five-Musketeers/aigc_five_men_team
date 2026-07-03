import 'package:dio/dio.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../core/services/chat_attachment_service.dart';
import '../core/utils/caption_text.dart';
import '../data/models/chat_message.dart';
import '../data/models/extracted_relation_hint.dart';
import '../data/models/memory_extraction_payload.dart';
import '../data/models/relation_conflict_record.dart';
import '../data/local_db/local_database.dart';
import '../data/repositories/chat_repository.dart';
import '../core/voice_input/voice_input.dart';
import 'profile_photo_reply.dart';
import 'relation_extractor.dart';
import 'prompt_task_router.dart';
import 'user_archive_cache.dart';
import '../data/models/profile_photo.dart';
import '../data/models/profile_video.dart';
import 'profile_video_reply.dart';

enum _MediaLookupKind { none, photo, video }

class ChatProvider extends ChangeNotifier {
  ChatProvider({ChatRepository? repository})
      : _repository = repository ?? ChatRepository() {
    _initFuture = _initializeLocalHistory();
  }

  static const String defaultUserId = 'local_user_default';
  static const String defaultConversationId = 'local_conversation_home';
  static const String _photoNotFoundReply = '对不起，没有找到您需要的图片。';
  static const String _videoNotFoundReply = '对不起，没有找到您需要的视频。';

  final ChatRepository _repository;
  final List<ChatMessage> _messages = <ChatMessage>[];
  late final Future<void> _initFuture;

  /// 当前本地使用者（老人账号）；周围人与会话均按此划分。
  String _activeUserId = defaultUserId;
  late String _activeConversationId;

  List<RelationConflictRecord> _pendingConflicts = <RelationConflictRecord>[];

  bool _isSending = false;
  int _userTurnCount = 0;
  String _lastUserText = '';

  /// 最近一次「看照片」检索原话；用于用户说「不是这张」时换批展示。
  String? _activePhotoQueryText;
  final Set<String> _shownPhotoIdsForActiveQuery = <String>{};

  /// 最近一次「看视频」检索原话。
  String? _activeVideoQueryText;
  final Set<String> _shownVideoIdsForActiveQuery = <String>{};

  UserArchiveCache? _archiveCache;
  Future<UserArchiveCache>? _archivePrefetchFuture;

  bool get isSending => _isSending;

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  String get activeUserId => _activeUserId;

  String get activeConversationId => _activeConversationId;

  List<RelationConflictRecord> get pendingRelationConflicts =>
      List.unmodifiable(_pendingConflicts);

  /// 语音转写后整理：优先大模型润色，失败再本地 NLP，仍失败则返回 [raw]。
  Future<String> polishSpeechBeforeSend(String raw) async {
    await _initFuture;
    final t = raw.trim();
    if (t.isEmpty) return raw;

    final namesHint = await _knownNamesHintForSpeechPolish();

    try {
      final polished = await _repository
          .polishSpeechTranscript(t, knownNamesHint: namesHint)
          .timeout(const Duration(seconds: 45));
      final out = polished.trim();
      if (out.isNotEmpty) return out;
    } catch (e, st) {
      debugPrint('[speech_polish] 大模型润色失败，尝试本地: $e\n$st');
    }
    try {
      final polished = await _repository
          .polishSpeechTranscriptLocal(t)
          .timeout(const Duration(seconds: 8));
      final out = polished.trim();
      if (out.isNotEmpty) return out;
    } catch (e, st) {
      debugPrint('[speech_polish] 本地 NLP 不可用: $e\n$st');
    }
    return t;
  }

  /// 供语音润色对照的档案人名/称谓（不写入对话抽取逻辑）。
  Future<String> _knownNamesHintForSpeechPolish() async {
    try {
      final cache = await _ensureArchivePrefetched();
      return cache.buildKnownNamesHint();
    } catch (_) {
      return '';
    }
  }

  /// 首次用户发言前预读本地库（档案文字 + 照片列表），后续复用内存快照。
  Future<UserArchiveCache> _ensureArchivePrefetched() async {
    if (_archiveCache != null && _archiveCache!.ownerUserId == _activeUserId) {
      return _archiveCache!;
    }
    _archivePrefetchFuture ??= UserArchiveCache.load(_activeUserId);
    _archiveCache = await _archivePrefetchFuture!;
    if (_archiveCache!.ownerUserId != _activeUserId) {
      _invalidateArchiveCache();
      return _ensureArchivePrefetched();
    }
    return _archiveCache!;
  }

  void _invalidateArchiveCache() {
    _archiveCache = null;
    _archivePrefetchFuture = null;
  }

  /// 预录入或设置变更后重新加载档案快照（照片 / 视频 / 文字）。
  Future<void> reloadUserArchive() async {
    await _initFuture;
    _invalidateArchiveCache();
    await _ensureArchivePrefetched();
    notifyListeners();
  }

  Future<void> sendMessage(
    String content, {
    Duration networkTimeout = const Duration(seconds: 110),
  }) async {
    await _initFuture;
    final text = content.trim();
    if (text.isEmpty || _isSending) return;

    _userTurnCount += 1;
    _lastUserText = text;
    final userMessage = _textMessage(content: text, isUser: true);
    _messages.add(userMessage);
    await _trySaveMessage(userMessage);
    _isSending = true;
    notifyListeners();

    final mediaKind = _mediaLookupKindFor(text);
    if (mediaKind == _MediaLookupKind.video) {
      await _handleVideoMediaRequest(text, userMessage.id);
      return;
    }
    if (mediaKind == _MediaLookupKind.photo) {
      await _handlePhotoMediaRequest(text, userMessage.id);
      return;
    }

    try {
      final promptContext = await _buildPromptContextAsync(
        photoLookupNote: null,
      );
      final reply = await _repository
          .sendMessage(
            history: _messages,
            promptContext: promptContext,
          )
          .timeout(networkTimeout);
      final assistantMessage = _textMessage(content: reply, isUser: false);
      _messages.add(assistantMessage);
      await _trySaveMessage(assistantMessage);
      await _extractRelationsFromRecentChat(sourceMessageId: userMessage.id);
      await _insertSupportCardIfNeeded(text);
    } catch (error) {
      final errorMessage = ChatMessage(
        id: _newId('error'),
        content: _buildErrorMessage(error),
        isUser: false,
        timestamp: DateTime.now(),
        kind: ChatMessageKind.error,
      );
      _messages.add(errorMessage);
      await _trySaveMessage(errorMessage);
      await _extractRelationsFromRecentChat(sourceMessageId: userMessage.id);
      await _insertLocalMemoryPrompt(text);
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  void sendOption(String text) {
    sendMessage(text);
  }

  /// 用户通过「+」上传图片或视频：图片与视频分轨入库。
  Future<void> sendAttachment(
    PickedChatAttachment picked, {
    String? caption,
    Duration networkTimeout = const Duration(seconds: 110),
  }) async {
    if (picked.isImage) {
      await _sendImageAttachment(
        picked,
        caption: caption,
        networkTimeout: networkTimeout,
      );
    } else {
      await _sendVideoAttachment(
        picked,
        caption: caption,
        networkTimeout: networkTimeout,
      );
    }
  }

  Future<void> _sendImageAttachment(
    PickedChatAttachment picked, {
    String? caption,
    Duration networkTimeout = const Duration(seconds: 110),
  }) async {
    await _initFuture;
    if (_isSending) return;

    final trimmedCaption = caption?.trim() ?? '';
    const defaultLabel = '分享了一张照片';
    final displayText =
        trimmedCaption.isNotEmpty ? trimmedCaption : defaultLabel;

    final messageId = _newId('user');
    final attachmentId = _newId('att');
    final profilePhotoId = _newId('photo');

    final photo = ProfilePhotoModel(
      id: profilePhotoId,
      ownerUserId: _activeUserId,
      filePath: picked.stablePath,
      storageType: kIsWeb
          ? ProfilePhotoStorageType.webLocal
          : ProfilePhotoStorageType.filePath,
      category: ProfilePhotoCategory.memory,
      caption: cleanAlbumCaption(displayText),
      metadata: {
        'source': 'chat',
        'media_type': 'image',
        'message_id': messageId,
        'attachment_id': attachmentId,
        'original_name': picked.originalName,
        'mime': picked.mimeType,
      },
    );

    final userMessage = ChatMessage(
      id: messageId,
      content: displayText,
      isUser: true,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.attachment,
      attachmentMediaType: ChatAttachmentMediaType.image,
      imagePath: picked.stablePath,
      profilePhotoId: profilePhotoId,
      attachmentId: attachmentId,
    );

    await _finalizeAttachmentSend(
      picked: picked,
      userMessage: userMessage,
      attachmentId: attachmentId,
      profilePhotoId: profilePhotoId,
      displayText: displayText,
      beforeLlm: () async {
        await LocalDatabase.insertProfilePhoto(photo);
      },
      photoLookupNote:
          '【系统】老人刚刚在对话中上传了一张照片，说明文字：$displayText。请温和回应并自然引导其补充照片中的人物、地点或年代。',
      localFallbackReply: '这张照片我已经收到了。您慢慢讲讲，里面都有谁、是在哪儿拍的？',
      networkTimeout: networkTimeout,
    );
  }

  Future<void> _sendVideoAttachment(
    PickedChatAttachment picked, {
    String? caption,
    Duration networkTimeout = const Duration(seconds: 110),
  }) async {
    await _initFuture;
    if (_isSending) return;

    final trimmedCaption = caption?.trim() ?? '';
    const defaultLabel = '分享了一段视频';
    final displayText =
        trimmedCaption.isNotEmpty ? trimmedCaption : defaultLabel;

    final messageId = _newId('user');
    final videoId = _newId('video');

    final video = ProfileVideoModel(
      id: videoId,
      ownerUserId: _activeUserId,
      filePath: picked.stablePath,
      category: ProfileVideoCategory.memory,
      caption: cleanAlbumCaption(displayText),
      messageId: messageId,
      mime: picked.mimeType,
      metadata: {
        'source': 'chat',
        'attachment_id': videoId,
        'original_name': picked.originalName,
      },
    );

    final userMessage = ChatMessage(
      id: messageId,
      content: displayText,
      isUser: true,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.attachment,
      attachmentMediaType: ChatAttachmentMediaType.video,
      videoPath: picked.stablePath,
      attachmentId: videoId,
    );

    await _finalizeAttachmentSend(
      picked: picked,
      userMessage: userMessage,
      attachmentId: videoId,
      profilePhotoId: null,
      displayText: displayText,
      beforeLlm: () async {
        await LocalDatabase.insertProfileVideo(video);
      },
      photoLookupNote:
          '【系统】老人刚刚在对话中上传了一段视频，说明文字：$displayText。请温和回应并自然引导其补充视频中的人物、地点或年代。不要提及照片。',
      localFallbackReply: '这段视频我已经收到了。您慢慢讲讲，里面都有什么？',
      networkTimeout: networkTimeout,
    );
  }

  Future<void> _finalizeAttachmentSend({
    required PickedChatAttachment picked,
    required ChatMessage userMessage,
    required String attachmentId,
    required String? profilePhotoId,
    required String displayText,
    required Future<void> Function() beforeLlm,
    required String photoLookupNote,
    required String localFallbackReply,
    Duration networkTimeout = const Duration(seconds: 110),
  }) async {
    _userTurnCount += 1;
    _lastUserText = displayText;
    _messages.add(userMessage);
    _isSending = true;
    notifyListeners();

    try {
      await beforeLlm();
      await LocalDatabase.insertAttachment({
        'id': attachmentId,
        'message_id': userMessage.id,
        'type': picked.type.name,
        'file_path': picked.stablePath,
        'mime': picked.mimeType,
        'size': picked.sizeBytes,
        'metadata': json.encode({
          if (profilePhotoId != null) 'profile_photo_id': profilePhotoId,
          if (picked.isVideo) 'profile_video_id': attachmentId,
          'original_name': picked.originalName,
          'source': 'chat',
          'owner_user_id': _activeUserId,
        }),
      });
      await _saveMessage(userMessage);
      await reloadUserArchive();

      final promptContext = await _buildPromptContextAsync(
        photoLookupNote: photoLookupNote,
      );
      final reply = await _repository
          .sendMessage(
            history: _messages,
            promptContext: promptContext,
          )
          .timeout(networkTimeout);
      final assistantMessage = _textMessage(content: reply, isUser: false);
      _messages.add(assistantMessage);
      await _trySaveMessage(assistantMessage);
      await _extractRelationsFromRecentChat(sourceMessageId: userMessage.id);
    } catch (error) {
      debugPrint('[sendAttachment] LLM 回复失败，使用本地回应: $error');
      final assistantMessage = _textMessage(
        content: localFallbackReply,
        isUser: false,
      );
      _messages.add(assistantMessage);
      await _trySaveMessage(assistantMessage);
      try {
        await _extractRelationsFromRecentChat(sourceMessageId: userMessage.id);
      } catch (_) {}
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  /// 删除一条本地聊天记录（数据库 + 当前内存列表）。
  Future<void> deleteMessageById(String messageId) async {
    await _initFuture;
    await LocalDatabase.deleteMessageById(messageId);
    _messages.removeWhere((m) => m.id == messageId);
    await reloadUserArchive();
  }

  /// 清空默认会话的全部聊天历史，并插入一条新的欢迎语。
  Future<void> clearHomeConversationHistory() async {
    await _initFuture;
    await LocalDatabase.deleteAllMessagesInConversation(_activeConversationId);
    _messages.clear();
    _userTurnCount = 0;
    _clearPhotoBrowseSession();
    _clearVideoBrowseSession();
    final welcome = ChatMessage(
      id: _newId('welcome'),
      content: '今天想聊什么？我在这里陪着您，慢慢说就好。',
      isUser: false,
      timestamp: DateTime.now(),
    );
    _messages.add(welcome);
    await _trySaveMessage(welcome);
    notifyListeners();
  }

  /// 新建一位本地使用者并切换到该账号。
  Future<void> createLocalProfile(String displayName) async {
    await _initFuture;
    final name = displayName.trim();
    if (name.isEmpty) return;
    final id = 'user_${DateTime.now().microsecondsSinceEpoch}';
    await LocalDatabase.insertUser({
      'id': id,
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
    });
    await LocalDatabase.ensureHomeConversationForUser(id);
    await setActiveUserId(id);
  }

  Future<void> setActiveUserId(String userId) async {
    await _initFuture;
    if (_activeUserId == userId) return;
    _invalidateArchiveCache();
    _clearPhotoBrowseSession();
    _clearVideoBrowseSession();
    _activeUserId = userId;
    _activeConversationId =
        await LocalDatabase.ensureHomeConversationForUser(userId);
    await _loadMessagesFromDb();
    await _reloadPendingConflicts();
    notifyListeners();
  }

  Future<void> resolveRelationConflictUi(String conflictId, bool useNew) async {
    await _initFuture;
    await LocalDatabase.resolveRelationConflict(
      conflictId: conflictId,
      useNew: useNew,
    );
    await _reloadPendingConflicts();
    notifyListeners();
  }

  ChatMessage _textMessage({
    required String content,
    required bool isUser,
  }) {
    return ChatMessage(
      id: _newId(isUser ? 'user' : 'assistant'),
      content: content,
      isUser: isUser,
      timestamp: DateTime.now(),
    );
  }

  ChatMessage _photoMessage(ProfilePhotoModel photo) {
    final label = ProfilePhotoReplyResolver.describePhoto(photo);
    return ChatMessage(
      id: _newId('photo'),
      content: photo.caption?.trim().isNotEmpty == true
          ? photo.caption!.trim()
          : '给您看这张$label',
      isUser: false,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.photo,
      imagePath: photo.filePath,
      profilePhotoId: photo.id,
    );
  }

  Future<void> _emitProfilePhotos(List<ProfilePhotoModel> photos) async {
    for (final photo in photos) {
      final msg = _photoMessage(photo);
      _messages.add(msg);
      await _trySaveMessage(msg);
    }
  }

  Future<void> _emitProfileVideos(List<ProfileVideoModel> videos) async {
    for (final video in videos) {
      final label = ProfileVideoReplyResolver.describeVideo(video);
      final msg = ChatMessage(
        id: _newId('video'),
        content: video.caption?.trim().isNotEmpty == true
            ? video.caption!.trim()
            : '给您看这段$label',
        isUser: false,
        timestamp: DateTime.now(),
        kind: ChatMessageKind.attachment,
        attachmentMediaType: ChatAttachmentMediaType.video,
        videoPath: video.filePath,
        attachmentId: video.id,
      );
      _messages.add(msg);
      await _trySaveMessage(msg);
    }
  }

  /// 用户要照片但未命中本地档案时，给大模型一句内部提示（写入档案摘要末尾）。
  void _clearPhotoBrowseSession() {
    _activePhotoQueryText = null;
    _shownPhotoIdsForActiveQuery.clear();
  }

  void _clearVideoBrowseSession() {
    _activeVideoQueryText = null;
    _shownVideoIdsForActiveQuery.clear();
  }

  /// 图片与视频检索互斥：视频意图优先；换一批时按当前浏览会话判定。
  _MediaLookupKind _mediaLookupKindFor(String text) {
    if (ProfileVideoReplyResolver.hasVideoIntent(text)) {
      return _MediaLookupKind.video;
    }
    if (ProfilePhotoReplyResolver.hasPhotoIntent(text)) {
      return _MediaLookupKind.photo;
    }
    if (ProfileVideoReplyResolver.isRejectionPhrase(text) &&
        _activeVideoQueryText != null &&
        _activeVideoQueryText!.isNotEmpty) {
      return _MediaLookupKind.video;
    }
    if (ProfilePhotoReplyResolver.isRejectionPhrase(text) &&
        _activePhotoQueryText != null &&
        _activePhotoQueryText!.isNotEmpty) {
      return _MediaLookupKind.photo;
    }
    return _MediaLookupKind.none;
  }

  Future<void> _emitAssistantReplyAndFinish({
    required String content,
    required String sourceMessageId,
    bool extractRelations = true,
  }) async {
    try {
      final hint = _textMessage(content: content, isUser: false);
      _messages.add(hint);
      await _trySaveMessage(hint);
      if (extractRelations) {
        await _extractRelationsFromRecentChat(sourceMessageId: sourceMessageId);
      }
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<void> _handleVideoMediaRequest(
    String text,
    String userMessageId,
  ) async {
    await reloadUserArchive();
    final archive = await _ensureArchivePrefetched();
    final isRejection = ProfileVideoReplyResolver.isRejectionPhrase(text);

    ProfileVideoReplyResult videoReply;
    if (isRejection &&
        _activeVideoQueryText != null &&
        _activeVideoQueryText!.isNotEmpty) {
      videoReply = await ProfileVideoReplyResolver.resolve(
        userText: text,
        cache: archive,
        repository: _repository,
        excludeVideoIds: _shownVideoIdsForActiveQuery,
        isRejection: true,
        previousQueryText: _activeVideoQueryText,
      );
    } else {
      if (ProfileVideoReplyResolver.hasVideoIntent(text)) {
        _activeVideoQueryText = text;
        _shownVideoIdsForActiveQuery.clear();
        _clearPhotoBrowseSession();
      }
      videoReply = await ProfileVideoReplyResolver.resolve(
        userText: text,
        cache: archive,
        repository: _repository,
        isRejection: isRejection,
      );
      if (videoReply.queryText != null && videoReply.videoRequested) {
        _activeVideoQueryText = videoReply.queryText;
      }
    }

    if (videoReply.status == ProfileVideoReplyStatus.matched) {
      try {
        await _emitProfileVideos(videoReply.videos);
        _shownVideoIdsForActiveQuery
            .addAll(videoReply.videos.map((v) => v.id));
        await _extractRelationsFromRecentChat(sourceMessageId: userMessageId);
      } finally {
        _isSending = false;
        notifyListeners();
      }
      return;
    }

    if (isRejection &&
        videoReply.status == ProfileVideoReplyStatus.exhausted) {
      await _emitAssistantReplyAndFinish(
        content: '相关视频都给您看过了。您可以说想看哪一类，比如「家庭视频」。',
        sourceMessageId: userMessageId,
      );
      return;
    }

    await _emitAssistantReplyAndFinish(
      content: _videoNotFoundReply,
      sourceMessageId: userMessageId,
      extractRelations: false,
    );
  }

  Future<void> _handlePhotoMediaRequest(
    String text,
    String userMessageId,
  ) async {
    await reloadUserArchive();
    final archive = await _ensureArchivePrefetched();
    final isRejection = ProfilePhotoReplyResolver.isRejectionPhrase(text);

    ProfilePhotoReplyResult photoReply;
    if (isRejection &&
        _activePhotoQueryText != null &&
        _activePhotoQueryText!.isNotEmpty) {
      photoReply = await ProfilePhotoReplyResolver.resolve(
        userText: text,
        cache: archive,
        repository: _repository,
        excludePhotoIds: _shownPhotoIdsForActiveQuery,
        isRejection: true,
        previousQueryText: _activePhotoQueryText,
      );
    } else {
      if (ProfilePhotoReplyResolver.hasPhotoIntent(text)) {
        _activePhotoQueryText = text;
        _shownPhotoIdsForActiveQuery.clear();
        _clearVideoBrowseSession();
      }
      photoReply = await ProfilePhotoReplyResolver.resolve(
        userText: text,
        cache: archive,
        repository: _repository,
        isRejection: isRejection,
      );
      if (photoReply.queryText != null && photoReply.photoRequested) {
        _activePhotoQueryText = photoReply.queryText;
      }
    }

    if (photoReply.status == ProfilePhotoReplyStatus.matched) {
      try {
        await _emitProfilePhotos(photoReply.photos);
        _shownPhotoIdsForActiveQuery
            .addAll(photoReply.photos.map((p) => p.id));
        await _extractRelationsFromRecentChat(sourceMessageId: userMessageId);
      } finally {
        _isSending = false;
        notifyListeners();
      }
      return;
    }

    if (isRejection &&
        photoReply.status == ProfilePhotoReplyStatus.exhausted) {
      await _emitAssistantReplyAndFinish(
        content: '相关照片都给您看过了。您可以说要看哪一类，比如「家庭照片」或家里人名字。',
        sourceMessageId: userMessageId,
      );
      return;
    }

    await _emitAssistantReplyAndFinish(
      content: _photoNotFoundReply,
      sourceMessageId: userMessageId,
      extractRelations: false,
    );
  }

  Future<void> _insertSupportCardIfNeeded(String latestUserText) async {
    if (_userTurnCount % 3 == 0) {
      final card = ChatMessage(
        id: _newId('cognitive'),
        title: '小小回忆练习',
        content: '我这里有一张老家院子的照片。您还记得院子里常放着什么吗？',
        isUser: false,
        timestamp: DateTime.now(),
        kind: ChatMessageKind.cognitivePrompt,
        cueLabel: '老家小院',
        options: const <String>['水缸', '自行车', '再想想'],
      );
      _messages.add(card);
      await _trySaveMessage(card);
      return;
    }

    if (_mentionsMemory(latestUserText) || _userTurnCount % 2 == 0) {
      final card = ChatMessage(
        id: _newId('memory'),
        title: '记忆锚点',
        content: '记得您说过以前常骑自行车去上班。那时候早晨路上会不会有点冷？',
        isUser: false,
        timestamp: DateTime.now(),
        kind: ChatMessageKind.memoryPrompt,
        cueLabel: '1986 · 自行车',
        options: const <String>['有点冷', '不太冷', '记不清了'],
      );
      _messages.add(card);
      await _trySaveMessage(card);
    }
  }

  Future<void> _insertLocalMemoryPrompt(String latestUserText) async {
    if (!_mentionsMemory(latestUserText)) return;
    final memoryPrompt = ChatMessage(
      id: _newId('local-memory'),
      title: '我们慢慢回忆',
      content: '您刚刚提到了以前的事。要不要从“老家小院的午后”开始说起？',
      isUser: false,
      timestamp: DateTime.now(),
      kind: ChatMessageKind.memoryPrompt,
      cueLabel: '老家小院',
      options: const <String>['好呀', '想看照片', '再等等'],
    );
    _messages.add(memoryPrompt);
    await _trySaveMessage(memoryPrompt);
  }

  bool _mentionsMemory(String text) {
    return text.contains('以前') ||
        text.contains('照片') ||
        text.contains('女儿') ||
        text.contains('上班') ||
        text.contains('老家') ||
        text.contains('自行车') ||
        text.contains('记得');
  }

  /// 与 `server/prompts` v1.1 对齐；通过 PromptTaskRouter 决定 active_task。
  Future<Map<String, dynamic>> _buildPromptContextAsync({
    String? photoLookupNote,
  }) async {
    try {
      final archive = await _ensureArchivePrefetched();
      final user = archive.user;
      final route = await PromptTaskRouter.resolve(
        userText: _lastUserText,
        ownerUserId: _activeUserId,
        recentHistory: _messages,
      );
      var profileBrief = archive.elderProfileBrief;
      final note = photoLookupNote?.trim();
      if (note != null && note.isNotEmpty) {
        profileBrief = '$profileBrief\n$note';
      }
      return <String, dynamic>{
        'global': <String, dynamic>{
          'dialect': (user?['dialect'] as String?)?.trim().isNotEmpty == true
              ? user!['dialect']
              : '天津话',
          'sensitive_topics': _splitTaboo(user?['taboo'] as String?),
          'elder_profile_brief': profileBrief,
        },
        'memory_snippets': route.memorySnippets,
        if (route.activeTask != null) 'active_task': route.activeTask,
        if (route.activeTask != null) 'task': route.taskParams,
      };
    } catch (_) {
      // 降级：仅 global，无任务模块
      return <String, dynamic>{
        'global': <String, dynamic>{
          'dialect': '天津话',
          'sensitive_topics': <String>[],
          'elder_profile_brief': '（暂无详细档案）',
        },
        'memory_snippets': <String>[],
      };
    }
  }

  /// 从 users.taboo 字段拆分敏感话题列表。
  static List<String> _splitTaboo(String? taboo) {
    if (taboo == null || taboo.trim().isEmpty) return <String>[];
    return taboo
        .split(RegExp(r'[,，;；、\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String _buildErrorMessage(Object error) {
    if (error is TimeoutException) {
      return '我这会儿思考有点慢，先把这句记下了。您可以继续说下一句。';
    }
    if (error is DioException) {
      final detail = _dioUserHint(error);
      return '我这会儿有点连不上大模型服务，但我还在。$detail';
    }
    return '我刚刚没有听清楚，您可以再慢慢说一遍。';
  }

  String _dioUserHint(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return '请在电脑上先启动本地代理：在含 env 与 aigc_five_men_team 的仓库根目录执行 `conda activate ./env` 后运行 `python aigc_five_men_team\\server\\local_chat_server.py`（需配置 VIVO_APP_KEY），并确认地址为 ${AppConstants.apiBaseUrl}。';
    }
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      return '（详情：${data['error']}）';
    }
    if (e.message != null && e.message!.isNotEmpty) {
      return '（${e.message}）';
    }
    return '';
  }

  String _newId(String prefix) {
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
  }

  Future<void> _initializeLocalHistory() async {
    try {
      await LocalDatabase.insertUser({
        'id': defaultUserId,
        'name': '',
        'created_at': DateTime.now().toIso8601String(),
      });
      _activeConversationId =
          await LocalDatabase.ensureHomeConversationForUser(_activeUserId);
      await LocalDatabase.addConversationMember(
        _activeConversationId,
        _activeUserId,
        role: 'owner',
      );
      await _loadMessagesFromDb();
      await _reloadPendingConflicts();
    } catch (e, st) {
      debugPrint('ChatProvider: 本地数据库初始化失败: $e');
      debugPrint('$st');
      if (_messages.isEmpty) {
        _messages.add(
          ChatMessage(
            id: 'welcome_fallback',
            content: '今天想聊什么？我在这里陪着您，慢慢说就好。',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      }
    }
    unawaited(VoiceInputService.prepareEngine());
    notifyListeners();
  }

  Future<void> _loadMessagesFromDb() async {
    final rows = await LocalDatabase.getMessagesForConversation(
      _activeConversationId,
    );
    _messages
      ..clear()
      ..addAll(rows.map(_chatMessageFromRow));
    _userTurnCount = _messages.where((m) => m.isUser).length;

    if (_messages.isEmpty) {
      final welcome = ChatMessage(
        id: _newId('welcome'),
        content: '今天想聊什么？我在这里陪着您，慢慢说就好。',
        isUser: false,
        timestamp: DateTime.now(),
      );
      _messages.add(welcome);
      await _trySaveMessage(welcome);
    }
  }

  Future<void> _reloadPendingConflicts() async {
    try {
      final rows =
          await LocalDatabase.getPendingRelationConflicts(_activeUserId);
      _pendingConflicts =
          rows.map(RelationConflictRecord.fromRow).toList(growable: false);
    } catch (_) {
      _pendingConflicts = [];
    }
  }

  /// 在助手回复写入后调用：用大模型从近期对话 JSON 抽取人物，失败则回退本地规则。
  Future<void> _extractRelationsFromRecentChat(
      {required String sourceMessageId}) async {
    await LocalDatabase.ensureUserExists(_activeUserId);

    var llmHintCount = 0;
    var ruleHintCount = 0;
    var processed = 0;

    try {
      final transcript = _buildExtractionTranscript();
      if (transcript.isEmpty) {
        await LocalDatabase.recordRelationExtractionSummary(
          userId: _activeUserId,
          llmHintCount: 0,
          ruleHintCount: 0,
          hintsProcessed: 0,
        );
        return;
      }

      final nearbySummary = await _nearbySummaryForLlm();
      var payload = MemoryExtractionPayload.empty();

      try {
        payload = await _repository
            .extractFullMemoryFromChat(
              transcriptMessages: transcript,
              existingNearbySummary: nearbySummary,
              existingUserSummary: await _userProfileSummaryForLlm(),
            )
            .timeout(const Duration(seconds: 55));
        llmHintCount = payload.people.length;
      } catch (e, st) {
        debugPrint('[relation_extract] LLM 调用失败: $e\n$st');
      }

      var hints = payload.people;
      if (hints.isEmpty) {
        final fullText = transcript.map((e) => e['content'] ?? '').join('\n');
        hints = RelationExtractor.extract(fullText);
        ruleHintCount = hints.length;
      }

      try {
        await _applyElderProfilePatch(payload.elderProfilePatch);
      } catch (e, st) {
        debugPrint('[relation_extract] 更新老人本人档案失败: $e\n$st');
      }
      try {
        await _applyExtractedFamilyMembers(payload.familyMemberRows);
      } catch (e, st) {
        debugPrint('[relation_extract] 家庭成员写入失败: $e\n$st');
      }
      try {
        await _applyExtractedMemoryEvents(payload.memoryEventRows);
      } catch (e, st) {
        debugPrint('[relation_extract] 记忆事件写入失败: $e\n$st');
      }
      try {
        await _applyDailyLifePatch(
          payload.dailyLifePatch,
          sourceMessageId: sourceMessageId,
          rawJson: payload.rawAssistantJson,
        );
      } catch (e, st) {
        debugPrint('[relation_extract] 每日生活记录写入失败: $e\n$st');
      }

      for (final h in hints) {
        try {
          await _applyExtractedHint(h, sourceMessageId);
          processed++;
        } catch (e, st) {
          debugPrint('[relation_extract] 写入周围人失败 (${h.name}): $e\n$st');
        }
      }

      await LocalDatabase.recordRelationExtractionSummary(
        userId: _activeUserId,
        llmHintCount: llmHintCount,
        ruleHintCount: ruleHintCount,
        hintsProcessed: processed,
      );

      await _reloadPendingConflicts();
      notifyListeners();
    } catch (e, st) {
      debugPrint('[relation_extract] 抽取流程异常: $e\n$st');
      await LocalDatabase.recordRelationExtractionSummary(
        userId: _activeUserId,
        llmHintCount: llmHintCount,
        ruleHintCount: ruleHintCount,
        hintsProcessed: processed,
      );
    }
  }

  /// 收录用户文本与附件说明，供抽取模型使用。
  List<Map<String, String>> _buildExtractionTranscript() {
    final userLines = _messages.where((m) {
      if (!m.isUser) return false;
      if (m.kind == ChatMessageKind.text) return true;
      if (m.kind == ChatMessageKind.attachment) return true;
      return false;
    }).toList();
    const maxUserTurns = 28;
    final recent = userLines.length > maxUserTurns
        ? userLines.sublist(userLines.length - maxUserTurns)
        : userLines;
    return recent.map((m) {
      var content = m.content;
      if (m.kind == ChatMessageKind.attachment) {
        final mediaLabel = m.attachmentMediaType ==
                ChatAttachmentMediaType.video
            ? '视频'
            : '照片';
        content = '[上传了$mediaLabel] $content';
      }
      return <String, String>{
        'role': 'user',
        'content': content,
      };
    }).toList();
  }

  Future<String> _userProfileSummaryForLlm() async {
    try {
      final u = await LocalDatabase.getUserById(_activeUserId);
      if (u == null) return '（尚无老人档案）';
      final parts = <String>[];
      void add(String label, String key) {
        final v = (u[key] as String?)?.trim();
        if (v != null && v.isNotEmpty) {
          parts.add('$label:$v');
        }
      }

      add('称呼', 'name');
      add('性别', 'gender');
      add('出生年月', 'birth_year');
      add('籍贯', 'hometown');
      add('现居地', 'current_address');
      add('职业经历', 'career');
      add('兴趣爱好', 'hobbies');
      add('饮食习惯', 'food_preference');
      add('性格', 'personality');
      add('忌讳', 'taboo');
      add('方言', 'dialect');
      add('照护提醒', 'care_notes');
      add('健康注意事项', 'medical_notes');
      return parts.isEmpty ? '（尚无老人档案）' : parts.join('；');
    } catch (_) {
      return '（读取老人档案失败）';
    }
  }

  Future<void> _applyElderProfilePatch(Map<String, String> patch) async {
    if (patch.isEmpty) return;
    await LocalDatabase.ensureUserExists(_activeUserId);
    await LocalDatabase.updateUser(_activeUserId, patch);
  }

  Future<void> _applyExtractedFamilyMembers(
    List<Map<String, dynamic>> rows,
  ) async {
    for (final raw in rows) {
      final r = Map<String, dynamic>.from(raw);
      final name = (r['name'] as String?)?.trim() ?? '';
      if (name.length < 2) continue;
      final relation = (r['relation'] as String?)?.trim() ?? '';
      final existing = await LocalDatabase.findFamilyMemberByOwnerNameRelation(
        _activeUserId,
        name,
        relation,
      );
      if (existing != null) {
        final id = (existing['id'] as num).toInt();
        final patch = <String, dynamic>{};
        r.forEach((key, value) {
          if (key == 'name') return;
          if (value == null) return;
          if (value is String && value.trim().isEmpty) return;
          patch[key] = value;
        });
        if (patch.isNotEmpty) {
          await LocalDatabase.updateFamilyMember(id, patch);
        }
      } else {
        await LocalDatabase.insertFamilyMember({
          'owner_user_id': _activeUserId,
          ...r,
        });
      }
    }
  }

  Future<void> _applyExtractedMemoryEvents(
    List<Map<String, dynamic>> rows,
  ) async {
    for (final raw in rows) {
      final r = Map<String, dynamic>.from(raw);
      final title = (r['title'] as String?)?.trim() ?? '';
      if (title.length < 2) continue;
      final eventTime = (r['event_time'] as String?)?.trim() ?? '';
      final eid = await LocalDatabase.findMemoryEventIdByOwnerTitleEventTime(
        _activeUserId,
        title,
        eventTime,
      );
      if (eid != null) {
        final patch = <String, dynamic>{};
        r.forEach((key, value) {
          if (key == 'title' || key == 'event_time') return;
          if (value == null) return;
          if (value is String && value.trim().isEmpty) return;
          patch[key] = value;
        });
        if (patch.isNotEmpty) {
          await LocalDatabase.updateMemoryEvent(eid, patch);
        }
      } else {
        await LocalDatabase.insertMemoryEvent({
          'owner_user_id': _activeUserId,
          ...r,
        });
      }
    }
  }

  String _extractedFieldStr(dynamic v) => v?.toString().trim() ?? '';

  Future<void> _applyDailyLifePatch(
    Map<String, dynamic>? patch, {
    required String sourceMessageId,
    String? rawJson,
  }) async {
    if (patch == null || patch.isEmpty) return;
    var dateStr = _extractedFieldStr(patch['date']);
    if (dateStr.isEmpty) {
      dateStr = DateTime.now().toIso8601String().split('T').first;
    }
    final breakfast = _extractedFieldStr(patch['breakfast']);
    final lunch = _extractedFieldStr(patch['lunch']);
    final dinner = _extractedFieldStr(patch['dinner']);
    final activities = _extractedFieldStr(patch['activities']);
    final peopleMet = _extractedFieldStr(patch['people_met']);
    final placesWent = _extractedFieldStr(patch['places_went']);
    final mood = _extractedFieldStr(patch['mood']);
    final hasContent = breakfast.isNotEmpty ||
        lunch.isNotEmpty ||
        dinner.isNotEmpty ||
        activities.isNotEmpty ||
        peopleMet.isNotEmpty ||
        placesWent.isNotEmpty ||
        mood.isNotEmpty;
    if (!hasContent) return;

    await LocalDatabase.upsertDailyLifeRecordByDate({
      'owner_user_id': _activeUserId,
      'date': dateStr,
      'breakfast': breakfast,
      'lunch': lunch,
      'dinner': dinner,
      'activities': activities,
      'people_met': peopleMet,
      'places_went': placesWent,
      'mood': mood,
      'source_dialog': sourceMessageId,
      'raw_extract': rawJson ?? json.encode(patch),
    });
  }

  Future<String> _nearbySummaryForLlm() async {
    try {
      final rows = await LocalDatabase.getNearbyPeopleForUser(_activeUserId);
      if (rows.isEmpty) return '（尚无已保存条目）';
      final lines = <String>[];
      for (final r in rows) {
        final name = (r['name'] as String?)?.trim() ?? '';
        final rel = (r['relation'] as String?)?.trim() ?? '';
        final phone = (r['phone'] as String?)?.trim() ?? '';
        final note = (r['note'] as String?)?.trim() ?? '';
        lines.add(
          '- $name | 关系:${rel.isEmpty ? '（空）' : rel} | 电话:${phone.isEmpty ? '（空）' : phone}'
          '${note.isEmpty ? '' : ' | 备注:$note'}',
        );
      }
      return lines.join('\n');
    } catch (_) {
      return '（读取周围人档案失败）';
    }
  }

  bool _meaningfullyDifferent(String? a, String? b) {
    final x = (a ?? '').trim();
    final y = (b ?? '').trim();
    if (x.isEmpty || y.isEmpty) return false;
    return x != y;
  }

  /// 比较规范化后的姓名，避免仅空格差异触发「姓名冲突」。
  bool _meaningfullyDifferentPersonName(String? a, String? b) {
    final x = LocalDatabase.normalizePersonName(a);
    final y = LocalDatabase.normalizePersonName(b);
    if (x.length < 2 || y.length < 2) return false;
    return x != y;
  }

  /// 先按姓名匹配；否则在称谓槽位上仅对应一条档案时，按称谓视为同一人（用于姓名更正，避免重复建条）。
  Future<Map<String, dynamic>?> _resolveExistingNearbyRow(
    ExtractedRelationHint h,
  ) async {
    final norm = LocalDatabase.normalizePersonName(h.name);
    if (norm.length < 2) return null;

    final byName = await LocalDatabase.findNearbyPersonByNormalizedName(
      _activeUserId,
      norm,
    );
    if (byName != null) return byName;

    // 同一称谓下可有多人：仅当抽取端显式给出 same_relation_key（用户强调「某人不对/记错」等）
    // 时才按称谓槽位对齐已有行，否则一律新建档案，避免误把新人合并进旧人并弹出冲突。
    final srk = LocalDatabase.normalizeRelationLabel(h.sameRelationKey);
    if (srk.isEmpty) return null;

    final candidates = await LocalDatabase.findNearbyPeopleByNormalizedRelation(
      _activeUserId,
      srk,
    );
    if (candidates.length != 1) return null;
    return candidates.first;
  }

  Future<void> _applyExtractedHint(
      ExtractedRelationHint h, String sourceMessageId) async {
    final norm = LocalDatabase.normalizePersonName(h.name);
    if (norm.length < 2) return;

    final existing = await _resolveExistingNearbyRow(h);

    if (existing == null) {
      await LocalDatabase.upsertNearbyPerson({
        'id': 'nearby_${DateTime.now().microsecondsSinceEpoch}',
        'owner_user_id': _activeUserId,
        'name': h.name.trim(),
        'relation': h.relation,
        'phone': h.phone,
        'note': h.note,
      });
      return;
    }

    final id = existing['id'] as String;
    final oldName = existing['name'] as String?;
    final oldRel = existing['relation'] as String?;
    final oldPhone = existing['phone'] as String?;
    final oldNote = existing['note'] as String?;

    // 同一档案同一时间只保留一条待确认冲突（insert 内会先删该档案旧 pending）。
    // 单次抽取内优先提示：姓名 > 称谓 > 电话 > 备注。
    String? conflictField;
    String? conflictOld;
    String? conflictNew;
    if (_meaningfullyDifferentPersonName(oldName, h.name)) {
      conflictField = 'name';
      conflictOld = oldName;
      conflictNew = h.name.trim();
    } else if (h.relation != null &&
        _meaningfullyDifferent(oldRel, h.relation)) {
      conflictField = 'relation';
      conflictOld = oldRel;
      conflictNew = h.relation;
    } else if (h.phone != null && _meaningfullyDifferent(oldPhone, h.phone)) {
      conflictField = 'phone';
      conflictOld = oldPhone;
      conflictNew = h.phone;
    } else if (h.note != null &&
        h.note!.trim().isNotEmpty &&
        _meaningfullyDifferent(oldNote, h.note!.trim())) {
      conflictField = 'note';
      conflictOld = oldNote;
      conflictNew = h.note!.trim();
    }

    if (conflictField != null) {
      await LocalDatabase.insertRelationConflict(
        id: _newId('rc'),
        ownerUserId: _activeUserId,
        personName: h.name.trim(),
        fieldName: conflictField,
        nearbyPersonId: id,
        oldValue: conflictOld,
        newValue: conflictNew,
        sourceMessageId: sourceMessageId,
      );
    }

    Future<Map<String, dynamic>?> freshNearbyRow() async {
      final rows = await LocalDatabase.getNearbyPeopleForUser(_activeUserId);
      for (final r in rows) {
        if (r['id'] == id) return r;
      }
      return null;
    }

    if (h.relation != null) {
      if (!_meaningfullyDifferent(oldRel, h.relation) &&
          (oldRel ?? '').trim().isEmpty) {
        final cur = await freshNearbyRow();
        if (cur != null) {
          await LocalDatabase.upsertNearbyPerson({
            ...cur,
            'relation': h.relation,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }
    }

    if (h.phone != null) {
      if (!_meaningfullyDifferent(oldPhone, h.phone) &&
          (oldPhone ?? '').trim().isEmpty) {
        final cur = await freshNearbyRow();
        if (cur != null) {
          await LocalDatabase.upsertNearbyPerson({
            ...cur,
            'phone': h.phone,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }
    }

    if (h.note != null && h.note!.trim().isNotEmpty) {
      final n = h.note!.trim();
      if (!_meaningfullyDifferent(oldNote, n) &&
          (oldNote ?? '').trim().isEmpty) {
        final cur = await freshNearbyRow();
        if (cur != null) {
          await LocalDatabase.upsertNearbyPerson({
            ...cur,
            'note': n,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }
    }
  }

  Future<void> _saveMessage(ChatMessage message) async {
    await LocalDatabase.insertMessage({
      'id': message.id,
      'conversation_id': _activeConversationId,
      'user_id': message.isUser ? _activeUserId : null,
      'content': message.content,
      'type': message.kind.name,
      'timestamp': message.timestamp.toIso8601String(),
      'extra': json.encode({
        'is_user': message.isUser,
        'title': message.title,
        'options': message.options,
        'cue_label': message.cueLabel,
        'image_path': message.imagePath,
        'profile_photo_id': message.profilePhotoId,
        'attachment_media_type': message.attachmentMediaType?.name,
        'video_path': message.videoPath,
        'attachment_id': message.attachmentId,
      }),
    });
  }

  Future<void> _trySaveMessage(ChatMessage message) async {
    try {
      await _saveMessage(message);
    } catch (_) {
      // Keep UI available even when local DB is temporarily unavailable.
    }
  }

  ChatMessage _chatMessageFromRow(Map<String, dynamic> row) {
    final extra = LocalDatabase.decodeJson(row['extra'] as String?)
            as Map<String, dynamic>? ??
        <String, dynamic>{};
    final kindName = row['type'] as String?;
    final kind = ChatMessageKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => ChatMessageKind.text,
    );
    ChatAttachmentMediaType? attachmentMediaType;
    final mediaTypeRaw = extra['attachment_media_type'] as String?;
    if (mediaTypeRaw != null) {
      attachmentMediaType = ChatAttachmentMediaType.values.firstWhere(
        (value) => value.name == mediaTypeRaw,
        orElse: () => ChatAttachmentMediaType.image,
      );
    }
    return ChatMessage(
      id: row['id'] as String,
      content: row['content'] as String? ?? '',
      isUser: extra['is_user'] as bool? ?? false,
      timestamp: DateTime.tryParse(row['timestamp'] as String? ?? '') ??
          DateTime.now(),
      kind: kind,
      title: extra['title'] as String?,
      cueLabel: extra['cue_label'] as String?,
      options: (extra['options'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      imagePath: extra['image_path'] as String?,
      profilePhotoId: extra['profile_photo_id'] as String?,
      attachmentMediaType: attachmentMediaType,
      videoPath: extra['video_path'] as String?,
      attachmentId: extra['attachment_id'] as String?,
    );
  }

  @override
  void dispose() {
    LocalDatabase.close();
    super.dispose();
  }
}
