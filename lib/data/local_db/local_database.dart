import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:uuid/uuid.dart';

import '../models/profile_photo.dart';
import '../repositories/pre_entry_mapper.dart';

/// 某用户在本地库中已持久化的业务表快照（含预录入与对话抽取结果），重启后可读。
part 'stored_user_data_bundle.dart';
part 'local_database_schema.dart';

class LocalDatabase {
  LocalDatabase._();

  static Database? _db;
  static bool _dbFactoryReady = false;

  static const _dbName = 'bluecare.db';
  static const _dbVersion = 6;

  static const legacyDefaultUserId = 'local_user_default';
  static const legacyDefaultConversationId = 'local_conversation_home';

  static Future<Database> instance() async {
    if (_db != null) return _db!;
    _initDatabaseFactoryForCurrentPlatform();
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    debugPrint('LocalDatabase path: $path');

    _db = await openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _upgradeSchema(db, oldVersion, newVersion);
      },
      onOpen: (db) async {
        await _repairSchemaIfIncomplete(db);
        await _ensurePreEntrySchema(db);
      },
    );

    return _db!;
  }

  /// 业务所需全部表名；用于检测「仅有 bluecare.db 文件且 user_version 已对齐，但从未执行过建表」的损坏状态。
  static Future<String> getDatabasePathForDebug() async {
    _initDatabaseFactoryForCurrentPlatform();
    final dbPath = await getDatabasesPath();
    return join(dbPath, _dbName);
  }

  static String storageHint() {
    if (kIsWeb) {
      return '当前为 Web 端：数据库存储在浏览器本地(IndexedDB/OPFS)，不是独立 .db 文件。';
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return '当前为桌面端：会生成本地 SQLite 文件 bluecare.db。';
    }
    return '当前为移动端：会生成应用沙盒内的 SQLite 文件 bluecare.db。';
  }

  static Future<void> insertUser(Map<String, dynamic> user) async {
    final db = await instance();
    await db.insert('users', user, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// 按用户 id 局部更新老人基本信息表字段（不包含 id）；未出现在 [values] 中的列保持不变。
  static Future<int> updateUser(String id, Map<String, dynamic> values) async {
    final db = await instance();
    final patch = Map<String, dynamic>.from(values);
    patch.remove('id');
    if (patch.isEmpty) return 0;
    patch['updated_at'] = DateTime.now().toIso8601String();
    return db.update('users', patch, where: 'id = ?', whereArgs: [id]);
  }

  static Future<Map<String, dynamic>?> getUserById(String id) async {
    final db = await instance();
    final res = await db.query('users', where: 'id = ?', whereArgs: [id]);
    if (res.isEmpty) return null;
    return res.first;
  }

  /// [nearby_people] / [relation_conflicts] 引用 users(id)，若缺少对应行，插入会因外键失败。
  static Future<void> ensureUserExists(String userId,
      {String? displayName}) async {
    final db = await instance();
    final name = (displayName ?? '使用者').trim();
    await db.insert(
      'users',
      {
        'id': userId,
        'name': name.isEmpty ? '使用者' : name,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 在 users.metadata 中记录最近一次人物关系抽取摘要，便于在 DB 中核对功能是否执行。
  static Future<void> recordRelationExtractionSummary({
    required String userId,
    required int llmHintCount,
    required int ruleHintCount,
    required int hintsProcessed,
  }) async {
    await ensureUserExists(userId);
    final db = await instance();
    final rows =
        await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
    var meta = <String, dynamic>{};
    if (rows.isNotEmpty) {
      final raw = rows.first['metadata'] as String?;
      if (raw != null && raw.isNotEmpty) {
        try {
          final d = jsonDecode(raw);
          if (d is Map<String, dynamic>) {
            meta = Map<String, dynamic>.from(d);
          }
        } catch (_) {}
      }
    }
    final now = DateTime.now().toIso8601String();
    meta['last_relation_extract_at'] = now;
    meta['last_llm_hint_count'] = llmHintCount;
    meta['last_rule_hint_count'] = ruleHintCount;
    meta['last_hints_processed'] = hintsProcessed;
    await db.update(
      'users',
      {'metadata': json.encode(meta)},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  static Future<void> createConversation(Map<String, dynamic> convo) async {
    final db = await instance();
    await db.insert('conversations', convo,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> addConversationMember(
      String conversationId, String userId,
      {String? role}) async {
    final db = await instance();
    await db.insert(
      'conversation_members',
      {
        'conversation_id': conversationId,
        'user_id': userId,
        'role': role,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> insertMessage(Map<String, dynamic> message) async {
    final db = await instance();
    await db.insert('messages', message,
        conflictAlgorithm: ConflictAlgorithm.replace);
    // update conversation last_message_id
    if (message.containsKey('conversation_id') && message.containsKey('id')) {
      await db.update('conversations', {'last_message_id': message['id']},
          where: 'id = ?', whereArgs: [message['conversation_id']]);
    }
  }

  static Future<List<Map<String, dynamic>>> getMessagesForConversation(
      String conversationId,
      {int? limit,
      int? offset}) async {
    final db = await instance();
    final res = await db.query('messages',
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
        orderBy: 'timestamp ASC',
        limit: limit,
        offset: offset);
    return res;
  }

  static Future<List<Map<String, dynamic>>> getRecentMessagesForConversation(
    String conversationId, {
    int limit = 120,
    int offset = 0,
  }) async {
    final db = await instance();
    return db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }

  static Future<void> insertAttachment(Map<String, dynamic> attachment) async {
    final db = await instance();
    await db.insert('attachments', attachment,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getAttachmentsForMessage(
      String messageId) async {
    final db = await instance();
    return await db
        .query('attachments', where: 'message_id = ?', whereArgs: [messageId]);
  }

  static Future<void> upsertNearbyPerson(
      Map<String, dynamic> nearbyPerson) async {
    final db = await instance();
    final now = DateTime.now().toIso8601String();
    final payload = Map<String, dynamic>.from(nearbyPerson);
    payload['updated_at'] = payload['updated_at'] ?? now;
    payload['created_at'] = payload['created_at'] ?? now;
    final oid = payload['owner_user_id'] as String?;
    if (oid != null) {
      await ensureUserExists(oid);
    }
    await db.insert('nearby_people', payload,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> getNearbyPeopleForUser(
      String ownerUserId) async {
    final db = await instance();
    return await db.query(
      'nearby_people',
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
      orderBy: 'is_emergency_contact DESC, updated_at DESC',
    );
  }

  /// 按主键读取单条周围人档案。
  static Future<Map<String, dynamic>?> getNearbyPersonById(String id) async {
    final db = await instance();
    final rows = await db.query('nearby_people',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// 仅返回仍在联系中的周围人（`is_active = 1`）。
  static Future<List<Map<String, dynamic>>> listActiveNearbyPeopleForUser(
    String ownerUserId,
  ) async {
    final db = await instance();
    return db.query(
      'nearby_people',
      where: 'owner_user_id = ? AND IFNULL(is_active, 1) != 0',
      whereArgs: [ownerUserId],
      orderBy: 'is_emergency_contact DESC, updated_at DESC',
    );
  }

  static Future<int> removeNearbyPerson(String id) async {
    final db = await instance();
    return await db.delete('nearby_people', where: 'id = ?', whereArgs: [id]);
  }

  static Future<int?> confirmNearbyPersonAsFamilyMember(String nearbyId) async {
    final db = await instance();
    final rows = await db.query(
      'nearby_people',
      where: 'id = ?',
      whereArgs: [nearbyId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final nearby = rows.first;
    final ownerUserId = (nearby['owner_user_id'] as String?)?.trim();
    final name = (nearby['name'] as String?)?.trim() ?? '';
    final relation = (nearby['relation'] as String?)?.trim() ?? '';
    if (ownerUserId == null || ownerUserId.isEmpty || name.isEmpty) {
      throw ArgumentError('周围人记录缺少 owner_user_id 或姓名，无法确认入亲属表');
    }

    final patch = PreEntryMapper.buildFamilyMemberPatchFromNearby(nearby);
    final existing =
        await findFamilyMemberByOwnerNameRelation(ownerUserId, name, relation);
    final int familyMemberId;
    if (existing != null) {
      familyMemberId = (existing['id'] as num).toInt();
      final updatePatch = Map<String, dynamic>.from(patch)
        ..remove('owner_user_id')
        ..removeWhere((_, value) => value == null);
      await updateFamilyMember(familyMemberId, updatePatch);
    } else {
      familyMemberId = await insertFamilyMember(patch);
    }

    final metadata = _mergeMetadata(nearby['metadata'] as String?, {
      'confirmed_as_family_member': true,
      'family_member_id': familyMemberId,
      'confirmed_at': DateTime.now().toIso8601String(),
    });
    await db.update(
      'nearby_people',
      {
        'family_member_id': familyMemberId,
        'metadata': json.encode(metadata),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [nearbyId],
    );
    return familyMemberId;
  }

  static Map<String, dynamic> _mergeMetadata(
    String? raw,
    Map<String, dynamic> patch,
  ) {
    final result = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is Map<String, dynamic>) {
          result.addAll(decoded);
        }
      } catch (_) {}
    }
    result.addAll(patch);
    return result;
  }

  /// 人物姓名用于匹配时的规范化（与抽取逻辑一致）。
  static String normalizePersonName(String? name) {
    if (name == null) return '';
    return name.trim().replaceAll(RegExp(r'\s+'), '');
  }

  /// 称谓/关系字段规范化，用于判断是否为同一「关系槽位」（如女儿、儿子）。
  static String normalizeRelationLabel(String? relation) {
    if (relation == null) return '';
    return relation.trim().replaceAll(RegExp(r'\s+'), '');
  }

  /// 同一使用者名下，称谓规范化后相同的周围人条目（可能 0/1/多条）。
  static Future<List<Map<String, dynamic>>>
      findNearbyPeopleByNormalizedRelation(
    String ownerUserId,
    String normalizedRelation,
  ) async {
    if (normalizedRelation.isEmpty) return [];
    final rows = await getNearbyPeopleForUser(ownerUserId);
    return rows
        .where((r) =>
            normalizeRelationLabel(r['relation'] as String?) ==
            normalizedRelation)
        .toList();
  }

  /// 将 [removeId] 的非空字段合并进 [keepId]（不覆盖已有非空值），再删除冗余行，并把待处理冲突挂到保留行上。
  static Future<void> mergeNearbyPersonAbsorbDuplicate({
    required String keepId,
    required String removeId,
  }) async {
    if (keepId == removeId) return;
    final db = await instance();
    final keepRows = await db.query(
      'nearby_people',
      where: 'id = ?',
      whereArgs: [keepId],
      limit: 1,
    );
    final remRows = await db.query(
      'nearby_people',
      where: 'id = ?',
      whereArgs: [removeId],
      limit: 1,
    );
    if (keepRows.isEmpty || remRows.isEmpty) return;
    final k = keepRows.first;
    final r = remRows.first;
    if (k['owner_user_id'] != r['owner_user_id']) return;

    final now = DateTime.now().toIso8601String();
    final patch = <String, dynamic>{'updated_at': now};
    void takeIfEmpty(String col) {
      final kv = (k[col] as String?)?.trim() ?? '';
      final rv = (r[col] as String?)?.trim() ?? '';
      if (kv.isEmpty && rv.isNotEmpty) {
        patch[col] = r[col];
      }
    }

    takeIfEmpty('name');
    takeIfEmpty('relation');
    takeIfEmpty('phone');
    takeIfEmpty('address');
    takeIfEmpty('note');
    final kEmerg = (k['is_emergency_contact'] as int?) ?? 0;
    final rEmerg = (r['is_emergency_contact'] as int?) ?? 0;
    if (kEmerg == 0 && rEmerg != 0) {
      patch['is_emergency_contact'] = rEmerg;
    }

    if (patch.length > 1) {
      await db
          .update('nearby_people', patch, where: 'id = ?', whereArgs: [keepId]);
    }

    await db.update(
      'relation_conflicts',
      {'nearby_person_id': keepId},
      where: 'nearby_person_id = ? AND status = ?',
      whereArgs: [removeId, 'pending'],
    );
    await db.delete('nearby_people', where: 'id = ?', whereArgs: [removeId]);
  }

  // ignore: unused_element
  static Future<void> _dedupeNearbyPeopleSameNameAndRelation(
    Database db,
    String ownerUserId,
    String primaryId,
    String newName,
  ) async {
    final primaryRows = await db.query(
      'nearby_people',
      where: 'id = ?',
      whereArgs: [primaryId],
      limit: 1,
    );
    if (primaryRows.isEmpty) return;
    final primary = primaryRows.first;
    final rel = normalizeRelationLabel(primary['relation'] as String?);
    final normName = normalizePersonName(newName);
    if (normName.isEmpty || rel.isEmpty) return;

    final all = await db.query(
      'nearby_people',
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
    );
    for (final row in all) {
      final rid = row['id'] as String;
      if (rid == primaryId) continue;
      if (normalizePersonName(row['name'] as String?) != normName) continue;
      if (normalizeRelationLabel(row['relation'] as String?) != rel) continue;
      await mergeNearbyPersonAbsorbDuplicate(keepId: primaryId, removeId: rid);
    }
  }

  static Future<List<Map<String, dynamic>>> listUsers() async {
    final db = await instance();
    return db.query('users', orderBy: 'created_at ASC');
  }

  /// 返回当前使用者名下、姓名规范化后一致的一条周围人记录。
  static Future<Map<String, dynamic>?> findNearbyPersonByNormalizedName(
    String ownerUserId,
    String normalizedName,
  ) async {
    if (normalizedName.isEmpty) return null;
    final rows = await getNearbyPeopleForUser(ownerUserId);
    for (final r in rows) {
      final n = normalizePersonName(r['name'] as String?);
      if (n == normalizedName) return r;
    }
    return null;
  }

  // --- 表2：家庭成员 family_members ---

  static Future<int> insertFamilyMember(Map<String, dynamic> row) async {
    final db = await instance();
    final payload = Map<String, dynamic>.from(row);
    payload.remove('id');
    final oid = payload['owner_user_id'] as String?;
    if (oid != null) {
      await ensureUserExists(oid);
    }
    final now = DateTime.now().toIso8601String();
    payload['created_at'] = payload['created_at'] ?? now;
    payload['updated_at'] = payload['updated_at'] ?? now;
    payload['is_active'] = (payload['is_active'] as int?) ?? 1;
    return db.insert('family_members', payload);
  }

  static Future<int> updateFamilyMember(
    int id,
    Map<String, dynamic> values,
  ) async {
    final db = await instance();
    final patch = Map<String, dynamic>.from(values);
    patch.remove('id');
    if (patch.isEmpty) return 0;
    patch['updated_at'] = DateTime.now().toIso8601String();
    return db.update('family_members', patch, where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> deleteFamilyMember(int id) async {
    final db = await instance();
    return db.delete('family_members', where: 'id = ?', whereArgs: [id]);
  }

  static Future<Map<String, dynamic>?> getFamilyMemberById(int id) async {
    final db = await instance();
    final rows =
        await db.query('family_members', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  static Future<List<Map<String, dynamic>>> listFamilyMembersForUser(
    String ownerUserId,
  ) async {
    final db = await instance();
    return db.query(
      'family_members',
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
      orderBy: 'is_active DESC, updated_at DESC',
    );
  }

  /// 仅返回仍在世的家庭成员（`is_active = 1`）。
  static Future<List<Map<String, dynamic>>> listActiveFamilyMembersForUser(
    String ownerUserId,
  ) async {
    final db = await instance();
    return db.query(
      'family_members',
      where: 'owner_user_id = ? AND IFNULL(is_active, 1) != 0',
      whereArgs: [ownerUserId],
      orderBy: 'updated_at DESC',
    );
  }

  /// 按姓名关键词模糊查询家庭成员。
  static Future<List<Map<String, dynamic>>> searchFamilyMembersForUser(
    String ownerUserId, {
    required String keyword,
    int limit = 20,
  }) async {
    final db = await instance();
    final k = '%${keyword.trim()}%';
    if (k == '%%') return [];
    return db.query(
      'family_members',
      where: 'owner_user_id = ? AND IFNULL(name, \'\') LIKE ?',
      whereArgs: [ownerUserId, k],
      orderBy: 'updated_at DESC',
      limit: limit,
    );
  }

  /// 按姓名 + 关系查找家庭成员（关系为空时仅按姓名且至多一条才命中）。
  static Future<Map<String, dynamic>?> findFamilyMemberByOwnerNameRelation(
    String ownerUserId,
    String name,
    String relation,
  ) async {
    final db = await instance();
    final n = name.trim();
    final r = relation.trim();
    if (n.length < 2) return null;
    if (r.isNotEmpty) {
      final rows = await db.query(
        'family_members',
        where: 'owner_user_id = ? AND name = ? AND IFNULL(relation, \'\') = ?',
        whereArgs: [ownerUserId, n, r],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first;
    }
    final rows = await db.query(
      'family_members',
      where: 'owner_user_id = ? AND name = ?',
      whereArgs: [ownerUserId, n],
      limit: 2,
    );
    if (rows.length != 1) return null;
    return rows.first;
  }

  // --- 表3：记忆事件 memory_events ---

  static Future<int> insertMemoryEvent(Map<String, dynamic> row) async {
    final db = await instance();
    final payload = Map<String, dynamic>.from(row);
    payload.remove('id');
    final oid = payload['owner_user_id'] as String?;
    if (oid != null) {
      await ensureUserExists(oid);
    }
    final now = DateTime.now().toIso8601String();
    payload['created_at'] = payload['created_at'] ?? now;
    payload['updated_at'] = payload['updated_at'] ?? now;
    payload['importance'] = payload['importance'] ?? 3;
    payload['verified'] = (payload['verified'] as int?) ?? 0;
    payload['used_count'] = (payload['used_count'] as int?) ?? 0;
    return db.insert('memory_events', payload);
  }

  static Future<int> updateMemoryEvent(
    int id,
    Map<String, dynamic> values,
  ) async {
    final db = await instance();
    final patch = Map<String, dynamic>.from(values);
    patch.remove('id');
    if (patch.isEmpty) return 0;
    patch['updated_at'] = DateTime.now().toIso8601String();
    return db.update('memory_events', patch, where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> deleteMemoryEvent(int id) async {
    final db = await instance();
    return db.delete('memory_events', where: 'id = ?', whereArgs: [id]);
  }

  static Future<Map<String, dynamic>?> getMemoryEventById(int id) async {
    final db = await instance();
    final rows =
        await db.query('memory_events', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  static Future<List<Map<String, dynamic>>> listMemoryEventsForUser(
    String ownerUserId, {
    int? limit,
    int? offset,
  }) async {
    final db = await instance();
    return db.query(
      'memory_events',
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
      orderBy: 'importance DESC, updated_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// 按标题或描述关键词模糊查询记忆事件。
  static Future<List<Map<String, dynamic>>> searchMemoryEventsForUser(
    String ownerUserId, {
    required String keyword,
    int limit = 20,
  }) async {
    final db = await instance();
    final k = '%${keyword.trim()}%';
    if (k == '%%') return [];
    return db.query(
      'memory_events',
      where:
          'owner_user_id = ? AND (IFNULL(title, \'\') LIKE ? OR IFNULL(description, \'\') LIKE ?)',
      whereArgs: [ownerUserId, k, k],
      orderBy: 'importance DESC, updated_at DESC',
      limit: limit,
    );
  }

  /// 将 [used_count] 加一并更新 [last_used]（AI 引用记忆事件时调用）。
  static Future<void> touchMemoryEventUsage(int eventId) async {
    final db = await instance();
    final now = DateTime.now().toIso8601String();
    await db.rawUpdate(
      'UPDATE memory_events SET used_count = used_count + 1, last_used = ?, updated_at = ? WHERE id = ?',
      [now, now, eventId],
    );
  }

  /// 用于同一老人、同一标题与时间线的记忆事件更新而非重复插入。
  static Future<int?> findMemoryEventIdByOwnerTitleEventTime(
    String ownerUserId,
    String title,
    String eventTime,
  ) async {
    final db = await instance();
    final t = title.trim();
    if (t.length < 2) return null;
    final et = eventTime.trim();
    final rows = await db.rawQuery(
      'SELECT id FROM memory_events WHERE owner_user_id = ? AND title = ? AND IFNULL(event_time, \'\') = ? LIMIT 1',
      [ownerUserId, t, et],
    );
    if (rows.isEmpty) return null;
    final id = rows.first['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return int.tryParse(id?.toString() ?? '');
  }

  // --- 表4：照片档案 profile_photos ---

  static Future<void> insertProfilePhoto(ProfilePhotoModel photo) async {
    final db = await instance();
    await ensureUserExists(photo.ownerUserId);
    await db.insert(
      'profile_photos',
      photo.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 切换照片是否收藏（重点照片）。
  static Future<void> setProfilePhotoFavorite(
      String id, bool isFavorite) async {
    await updateProfilePhoto(id, {'is_favorite': isFavorite ? 1 : 0});
  }

  static Future<int> updateProfilePhoto(
    String id,
    Map<String, dynamic> values,
  ) async {
    final db = await instance();
    final patch = Map<String, dynamic>.from(values);
    patch.remove('id');
    patch.remove('owner_user_id');
    if (patch.isEmpty) return 0;
    patch['updated_at'] = DateTime.now().toIso8601String();
    return db.update('profile_photos', patch, where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> deleteProfilePhoto(String id) async {
    final db = await instance();
    return db.delete('profile_photos', where: 'id = ?', whereArgs: [id]);
  }

  static Future<ProfilePhotoModel?> getProfilePhotoById(String id) async {
    final db = await instance();
    final rows =
        await db.query('profile_photos', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ProfilePhotoModel.fromMap(rows.first);
  }

  static Future<List<ProfilePhotoModel>> listProfilePhotosForUser(
    String ownerUserId, {
    ProfilePhotoCategory? category,
  }) async {
    final rows = await listProfilePhotoRowsForUser(
      ownerUserId,
      category: category?.value,
    );
    return rows.map(ProfilePhotoModel.fromMap).toList();
  }

  /// 照片档案原始行（与 [listProfilePhotosForUser] 同源，便于统一查询层使用）。
  static Future<List<Map<String, dynamic>>> listProfilePhotoRowsForUser(
    String ownerUserId, {
    String? category,
    int? limit,
  }) async {
    final db = await instance();
    return db.query(
      'profile_photos',
      where: category == null
          ? 'owner_user_id = ?'
          : 'owner_user_id = ? AND category = ?',
      whereArgs: category == null ? [ownerUserId] : [ownerUserId, category],
      orderBy: 'is_favorite DESC, updated_at DESC',
      limit: limit,
    );
  }

  /// 按标签字段模糊查询照片（含各类别中文别名 → category 字段）。
  static Future<List<ProfilePhotoModel>> searchProfilePhotosForUser(
    String ownerUserId, {
    required String keyword,
    String? category,
    int limit = 12,
  }) async {
    final k = keyword.trim();
    if (k.length < 2) return [];

    final explicitCategory = category != null
        ? ProfilePhotoCategory.fromValue(category)
        : ProfilePhotoCategoryLabels.categoryFromUserPhrase(k);
    if (explicitCategory != null) {
      final rows = await listProfilePhotoRowsForUser(
        ownerUserId,
        category: explicitCategory.value,
        limit: limit,
      );
      if (rows.isNotEmpty) {
        return rows.map(ProfilePhotoModel.fromMap).toList();
      }
    }

    final matchedCategories =
        ProfilePhotoCategoryLabels.categoriesMatchingKeyword(k);
    if (matchedCategories.isNotEmpty) {
      final db = await instance();
      final placeholders =
          List.filled(matchedCategories.length, '?').join(', ');
      final catValues = matchedCategories.map((c) => c.value).toList();
      final rows = await db.query(
        'profile_photos',
        where: 'owner_user_id = ? AND category IN ($placeholders)',
        whereArgs: [ownerUserId, ...catValues],
        orderBy: 'is_favorite DESC, updated_at DESC',
        limit: limit,
      );
      if (rows.isNotEmpty) {
        return rows.map(ProfilePhotoModel.fromMap).toList();
      }
    }

    final db = await instance();
    final like = '%$k%';
    final rows = await db.query(
      'profile_photos',
      where:
          'owner_user_id = ? AND (IFNULL(caption, \'\') LIKE ? OR IFNULL(people_involved, \'\') LIKE ? OR IFNULL(location, \'\') LIKE ? OR IFNULL(category, \'\') LIKE ?)',
      whereArgs: [ownerUserId, like, like, like, like],
      orderBy: 'is_favorite DESC, updated_at DESC',
      limit: limit,
    );
    return rows.map(ProfilePhotoModel.fromMap).toList();
  }

  // --- 表5：每日生活记录 daily_life_records ---

  static Future<int> insertDailyLifeRecord(Map<String, dynamic> row) async {
    final db = await instance();
    final payload = Map<String, dynamic>.from(row);
    payload.remove('id');
    final oid = payload['owner_user_id'] as String?;
    if (oid != null) {
      await ensureUserExists(oid);
    }
    final now = DateTime.now().toIso8601String();
    payload['created_at'] = payload['created_at'] ?? now;
    payload['updated_at'] = payload['updated_at'] ?? now;
    return db.insert('daily_life_records', payload);
  }

  static Future<int> updateDailyLifeRecord(
    int id,
    Map<String, dynamic> values,
  ) async {
    final db = await instance();
    final patch = Map<String, dynamic>.from(values);
    patch.remove('id');
    patch.remove('owner_user_id');
    patch.remove('date');
    if (patch.isEmpty) return 0;
    patch['updated_at'] = DateTime.now().toIso8601String();
    return db
        .update('daily_life_records', patch, where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> deleteDailyLifeRecord(int id) async {
    final db = await instance();
    return db.delete('daily_life_records', where: 'id = ?', whereArgs: [id]);
  }

  static Future<Map<String, dynamic>?> getDailyLifeRecordById(int id) async {
    final db = await instance();
    final rows =
        await db.query('daily_life_records', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  static Future<Map<String, dynamic>?> getDailyLifeRecordByUserAndDate(
    String ownerUserId,
    String date,
  ) async {
    final db = await instance();
    final rows = await db.query(
      'daily_life_records',
      where: 'owner_user_id = ? AND date = ?',
      whereArgs: [ownerUserId, date],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  static Future<List<Map<String, dynamic>>> listDailyLifeRecordsForUser(
    String ownerUserId, {
    int? limit,
    int? offset,
  }) async {
    final db = await instance();
    return db.query(
      'daily_life_records',
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
      orderBy: 'date DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// 同一使用者同一天仅一条：存在则更新当日字段。
  static Future<int> upsertDailyLifeRecordByDate(
      Map<String, dynamic> row) async {
    final ownerUserId = row['owner_user_id'] as String?;
    final date = row['date'] as String?;
    if (ownerUserId == null ||
        ownerUserId.isEmpty ||
        date == null ||
        date.isEmpty) {
      throw ArgumentError('owner_user_id 与 date 不能为空');
    }
    await ensureUserExists(ownerUserId);
    final existing = await getDailyLifeRecordByUserAndDate(ownerUserId, date);
    if (existing != null) {
      final rid = (existing['id'] as num).toInt();
      final patch = Map<String, dynamic>.from(row);
      patch.remove('owner_user_id');
      patch.remove('date');
      patch.remove('id');
      patch.remove('created_at');
      return updateDailyLifeRecord(rid, patch);
    }
    return insertDailyLifeRecord(Map<String, dynamic>.from(row));
  }

  // --- cognitive_tests 认知干预记录（供 CAI prompt 频控） ---

  static Future<int> insertCognitiveTest(Map<String, dynamic> row) async {
    final db = await instance();
    final payload = Map<String, dynamic>.from(row);
    payload.remove('id');
    final oid = payload['owner_user_id'] as String?;
    if (oid != null) {
      await ensureUserExists(oid);
    }
    payload['created_at'] =
        payload['created_at'] ?? DateTime.now().toIso8601String();
    payload['is_valid'] = (payload['is_valid'] as int?) ?? 0;
    return db.insert('cognitive_tests', payload);
  }

  /// 统计今日认知测试总尝试次数（含有效与无效）。
  static Future<int> countCognitiveTestsToday(String ownerUserId) async {
    final db = await instance();
    final today = DateTime.now().toIso8601String().split('T').first;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM cognitive_tests WHERE owner_user_id = ? AND created_at >= ?',
      [ownerUserId, today],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  /// 获取最近一次认知测试时间。
  static Future<DateTime?> getLastCognitiveTestTime(String ownerUserId) async {
    final db = await instance();
    final rows = await db.query(
      'cognitive_tests',
      columns: ['created_at'],
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final ts = rows.first['created_at'] as String?;
    if (ts == null || ts.isEmpty) return null;
    return DateTime.tryParse(ts);
  }

  /// 从最近一条往回数连续无效作答的条数（用于频控：连续 2 次无效当天停）。
  static Future<int> getRecentInvalidStreak(String ownerUserId,
      {int limit = 2}) async {
    final db = await instance();
    final rows = await db.query(
      'cognitive_tests',
      columns: ['is_valid'],
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    int streak = 0;
    for (final r in rows) {
      if ((r['is_valid'] as int?) == 0) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  /// 列出某用户的认知测试记录（按时间倒序）。
  static Future<List<Map<String, dynamic>>> listCognitiveTestsForUser(
    String ownerUserId, {
    int? limit,
    int? offset,
  }) async {
    final db = await instance();
    return db.query(
      'cognitive_tests',
      where: 'owner_user_id = ?',
      whereArgs: [ownerUserId],
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// 每位使用者对应一个主会话；默认老人账号沿用历史 id `local_conversation_home`。
  static Future<String> ensureHomeConversationForUser(String userId) async {
    final db = await instance();
    final existing = await db.query(
      'conversations',
      where: 'owner_user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as String;
    }
    if (userId == legacyDefaultUserId) {
      final legacy = await db.query(
        'conversations',
        where: 'id = ?',
        whereArgs: [legacyDefaultConversationId],
        limit: 1,
      );
      if (legacy.isNotEmpty) {
        await db.update(
          'conversations',
          {'owner_user_id': userId},
          where: 'id = ?',
          whereArgs: [legacyDefaultConversationId],
        );
        return legacyDefaultConversationId;
      }
    }
    final uuid = const Uuid();
    final convId = userId == legacyDefaultUserId
        ? legacyDefaultConversationId
        : 'conv_${uuid.v4()}';
    final now = DateTime.now().toIso8601String();
    await db.insert('conversations', {
      'id': convId,
      'title': '陪伴会话',
      'created_at': now,
      'owner_user_id': userId,
    });
    await addConversationMember(convId, userId, role: 'owner');
    return convId;
  }

  static Future<List<Map<String, dynamic>>> getPendingRelationConflicts(
      String ownerUserId) async {
    final db = await instance();
    return db.query(
      'relation_conflicts',
      where: 'owner_user_id = ? AND status = ?',
      whereArgs: [ownerUserId, 'pending'],
      orderBy: 'created_at ASC',
    );
  }

  /// 删除某条周围人档案下所有「待处理」冲突（插入新冲突前调用，保证同一档案只提示一次）。
  static Future<int> deletePendingRelationConflictsForNearbyPerson(
    String ownerUserId,
    String nearbyPersonId,
  ) async {
    final db = await instance();
    return db.delete(
      'relation_conflicts',
      where: 'owner_user_id = ? AND nearby_person_id = ? AND status = ?',
      whereArgs: [ownerUserId, nearbyPersonId, 'pending'],
    );
  }

  /// 按主键删除冲突记录（解决冲突后清理）。
  static Future<int> deleteRelationConflictById(String id) async {
    final db = await instance();
    return db.delete('relation_conflicts', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> insertRelationConflict({
    required String id,
    required String ownerUserId,
    required String personName,
    required String fieldName,
    String? nearbyPersonId,
    String? oldValue,
    String? newValue,
    String? sourceMessageId,
  }) async {
    assert(<String>{'relation', 'note', 'phone', 'name'}.contains(fieldName));
    await ensureUserExists(ownerUserId);
    final db = await instance();
    if (nearbyPersonId != null) {
      await deletePendingRelationConflictsForNearbyPerson(
        ownerUserId,
        nearbyPersonId,
      );
    }
    await db.insert('relation_conflicts', {
      'id': id,
      'owner_user_id': ownerUserId,
      'nearby_person_id': nearbyPersonId,
      'person_name': personName,
      'field_name': fieldName,
      'old_value': oldValue,
      'new_value': newValue,
      'source_message_id': sourceMessageId,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> resolveRelationConflict({
    required String conflictId,
    required bool useNew,
  }) async {
    final db = await instance();
    final rows = await db.query(
      'relation_conflicts',
      where: 'id = ?',
      whereArgs: [conflictId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    if ((row['status'] as String?) != 'pending') return;
    final nearbyId = row['nearby_person_id'] as String?;
    final field = row['field_name'] as String;
    final newV = row['new_value'] as String?;

    if (useNew && nearbyId != null) {
      final col = switch (field) {
        'relation' => 'relation',
        'phone' => 'phone',
        'note' => 'note',
        'name' => 'name',
        _ => null,
      };
      if (col != null) {
        await db.update(
          'nearby_people',
          {
            col: newV,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [nearbyId],
        );
      }
    }

    await db
        .delete('relation_conflicts', where: 'id = ?', whereArgs: [conflictId]);
  }

  /// 合并写入备注（无冲突时追加）。
  static Future<void> mergeNearbyPersonNote(
      String nearbyPersonId, String appendedNote) async {
    final db = await instance();
    final rows = await db.query(
      'nearby_people',
      columns: ['note'],
      where: 'id = ?',
      whereArgs: [nearbyPersonId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final prev = (rows.first['note'] as String?)?.trim() ?? '';
    final next = prev.isEmpty
        ? appendedNote
        : prev.contains(appendedNote)
            ? prev
            : '$prev；$appendedNote';
    await db.update(
      'nearby_people',
      {
        'note': next,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [nearbyPersonId],
    );
  }

  /// 删除单条消息（attachments 表通过外键级联删除）。
  static Future<void> deleteMessageById(String messageId) async {
    final db = await instance();
    final rows = await db.query(
      'messages',
      columns: ['conversation_id'],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
    if (rows.isEmpty) return;
    final cid = rows.first['conversation_id'] as String?;
    if (cid != null) {
      await _refreshConversationLastMessageId(db, cid);
    }
  }

  /// 清空某会话下的全部消息。
  static Future<int> deleteAllMessagesInConversation(
      String conversationId) async {
    final db = await instance();
    final n = await db.delete(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
    await db.update(
      'conversations',
      {'last_message_id': null},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
    return n;
  }

  /// 统计当日某用户在 messages 表中的发言条数（用于判断"今日首次发言"）。
  static Future<int> countMessagesTodayByUser(
      String userId, String todayDate) async {
    final db = await instance();
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM messages WHERE user_id = ? AND timestamp >= ?",
      [userId, todayDate],
    );
    if (rows.isEmpty) return 0;
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  static Future<void> _refreshConversationLastMessageId(
      Database db, String conversationId) async {
    final latest = await db.query(
      'messages',
      columns: ['id'],
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    final lastId = latest.isEmpty ? null : latest.first['id'] as String?;
    await db.update(
      'conversations',
      {'last_message_id': lastId},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
  }

  // --- 统一查询：重启后读取已入库的预录入与档案数据 ---

  /// 一次性读取某用户在各业务表中的已存数据（并行查询，供界面或对话上下文使用）。
  static Future<StoredUserDataBundle> queryStoredUserDataForUser(
    String ownerUserId, {
    int familyLimit = 100,
    int memoryLimit = 100,
    int dailyLimit = 60,
    int nearbyLimit = 100,
    int photoLimit = 100,
    int cognitiveLimit = 50,
  }) async {
    await ensureUserExists(ownerUserId);
    final user = await getUserById(ownerUserId);
    final family = await listFamilyMembersForUser(ownerUserId);
    final memory = await listMemoryEventsForUser(
      ownerUserId,
      limit: memoryLimit,
    );
    final daily = await listDailyLifeRecordsForUser(
      ownerUserId,
      limit: dailyLimit,
    );
    final nearby = await getNearbyPeopleForUser(ownerUserId);
    final photos = await listProfilePhotoRowsForUser(
      ownerUserId,
      limit: photoLimit,
    );
    final conflicts = await getPendingRelationConflicts(ownerUserId);
    final cognitive = await listCognitiveTestsForUser(
      ownerUserId,
      limit: cognitiveLimit,
    );

    return StoredUserDataBundle(
      user: user,
      familyMembers: familyLimit >= family.length
          ? family
          : family.take(familyLimit).toList(),
      memoryEvents: memory,
      dailyLifeRecords: daily,
      nearbyPeople: nearbyLimit >= nearby.length
          ? nearby
          : nearby.take(nearbyLimit).toList(),
      profilePhotoRows: photos,
      pendingRelationConflicts: conflicts,
      cognitiveTests: cognitive,
    );
  }

  /// 预录入相关表快照（users / family_members / memory_events / profile_photos / nearby_people）。
  static Future<StoredUserDataBundle> queryPreEntryDataForUser(
    String ownerUserId, {
    int familyLimit = 100,
    int memoryLimit = 100,
    int photoLimit = 100,
    int nearbyLimit = 100,
  }) async {
    final all = await queryStoredUserDataForUser(
      ownerUserId,
      familyLimit: familyLimit,
      memoryLimit: memoryLimit,
      dailyLimit: 0,
      nearbyLimit: nearbyLimit,
      photoLimit: photoLimit,
      cognitiveLimit: 0,
    );
    return StoredUserDataBundle(
      user: all.user,
      familyMembers: all.familyMembers,
      memoryEvents: all.memoryEvents,
      nearbyPeople: all.nearbyPeople,
      profilePhotoRows: all.profilePhotoRows,
    );
  }

  /// 是否已有任意预录入或档案数据（用于判断重启后库内是否有可读内容）。
  static Future<bool> hasStoredDataForUser(String ownerUserId) async {
    final bundle = await queryStoredUserDataForUser(
      ownerUserId,
      familyLimit: 1,
      memoryLimit: 1,
      dailyLimit: 1,
      nearbyLimit: 1,
      photoLimit: 1,
      cognitiveLimit: 1,
    );
    return bundle.hasAnyData;
  }

  /// 将已入库档案整理为可注入大模型的摘要行（重启后调用即可读到预录入内容）。
  static Future<List<String>> queryMemoryContextLinesForUser(
    String ownerUserId, {
    int familyLimit = 10,
    int memoryLimit = 8,
    int dailyLimit = 4,
    int nearbyLimit = 20,
    int photoLimit = 6,
  }) async {
    try {
      final user = await getUserById(ownerUserId);
      final lines = <String>[];
      final userLabel = (user?['name'] as String?)?.trim();
      if (userLabel != null && userLabel.isNotEmpty) {
        lines.add('- 用户称呼：$userLabel。');
      }
      if (user != null) {
        const profilePairs = <String, String>{
          'gender': '性别',
          'birth_year': '出生年月',
          'hometown': '籍贯',
          'current_address': '现居地',
          'career': '职业经历',
          'hobbies': '兴趣爱好',
          'food_preference': '饮食习惯',
          'personality': '性格',
          'taboo': '忌讳话题',
          'dialect': '方言',
          'care_notes': '照护提醒',
          'medical_notes': '健康注意事项',
        };
        for (final e in profilePairs.entries) {
          final v = (user[e.key] as String?)?.trim();
          if (v != null && v.isNotEmpty) {
            lines.add('- 老人档案·${e.value}：$v');
          }
        }
      }

      final familyRows = await listFamilyMembersForUser(ownerUserId);
      if (familyRows.isEmpty) {
        lines.add('- 家庭成员表：暂无结构化记录。');
      } else {
        for (final r in familyRows.take(familyLimit)) {
          final name = (r['name'] as String?)?.trim() ?? '（姓名未填）';
          final rel = (r['relation'] as String?)?.trim() ?? '';
          final loc = (r['location'] as String?)?.trim() ?? '';
          final notes = (r['notes'] as String?)?.trim() ?? '';
          final active = ((r['is_active'] as int?) ?? 1) != 0;
          lines.add(
            '- 家人：${rel.isEmpty ? '亲属' : rel} $name'
            '${active ? '' : '（已故）'}'
            '${loc.isEmpty ? '' : '，住$loc'}'
            '${notes.isEmpty ? '' : '；$notes'}',
          );
        }
      }

      final memRows = await listMemoryEventsForUser(
        ownerUserId,
        limit: memoryLimit,
      );
      if (memRows.isEmpty) {
        lines.add('- 往事记忆库：暂无已保存事件。');
      } else {
        for (final r in memRows) {
          final t = (r['title'] as String?)?.trim() ?? '';
          final desc = (r['description'] as String?)?.trim() ?? '';
          final et = (r['event_time'] as String?)?.trim() ?? '';
          if (t.isEmpty && desc.isEmpty) continue;
          final head = et.isEmpty ? '' : '$et · ';
          if (desc.isEmpty) {
            lines.add('- 往事：$head$t');
          } else {
            lines.add('- 往事：$head$t${t.isEmpty ? '' : ' — '}$desc');
          }
        }
      }

      final dailyRows = await listDailyLifeRecordsForUser(
        ownerUserId,
        limit: dailyLimit,
      );
      if (dailyRows.isEmpty) {
        lines.add('- 每日生活记录：暂无。');
      } else {
        for (final r in dailyRows) {
          final d = (r['date'] as String?)?.trim() ?? '';
          final parts = <String>[];
          void add(String label, String col) {
            final v = (r[col] as String?)?.trim();
            if (v != null && v.isNotEmpty) parts.add('$label$v');
          }

          add('早', 'breakfast');
          add('午', 'lunch');
          add('晚', 'dinner');
          add('活动', 'activities');
          add('心情', 'mood');
          if (parts.isEmpty) continue;
          lines.add('- $d 日常：${parts.join('；')}');
        }
      }

      final photoRows = await listProfilePhotoRowsForUser(
        ownerUserId,
        limit: photoLimit,
      );
      if (photoRows.isEmpty) {
        lines.add('- 照片档案：暂无。');
      } else {
        for (final r in photoRows) {
          final cap = (r['caption'] as String?)?.trim() ?? '';
          final cat = (r['category'] as String?)?.trim() ?? '';
          final when = (r['photo_time'] as String?)?.trim() ?? '';
          final loc = (r['location'] as String?)?.trim() ?? '';
          final people = (r['people_involved'] as String?)?.trim() ?? '';
          final bits = <String>[];
          if (cat.isNotEmpty) bits.add(cat);
          if (when.isNotEmpty) bits.add(when);
          if (loc.isNotEmpty) bits.add(loc);
          if (people.isNotEmpty) bits.add('人物：$people');
          if (cap.isNotEmpty) bits.add(cap);
          if (bits.isEmpty) continue;
          lines.add('- 照片：${bits.join('，')}');
        }
      }

      final nearbyRows = await getNearbyPeopleForUser(ownerUserId);
      if (nearbyRows.isEmpty) {
        lines.add('- 周围人（邻居/朋友等）档案：暂无已保存条目。');
      } else {
        for (final r in nearbyRows.take(nearbyLimit)) {
          final name = (r['name'] as String?)?.trim() ?? '（未写姓名）';
          final rel = (r['relation'] as String?)?.trim() ?? '';
          final phone = (r['phone'] as String?)?.trim() ?? '';
          final note = (r['note'] as String?)?.trim() ?? '';
          final addr = (r['address'] as String?)?.trim() ?? '';
          lines.add(
            '- ${rel.isEmpty ? '亲友' : rel}：$name'
            '${phone.isEmpty ? '' : '，电话 $phone'}'
            '${addr.isEmpty ? '' : '，地址 $addr'}'
            '${note.isEmpty ? '' : '；$note'}',
          );
        }
      }
      return lines;
    } catch (_) {
      return <String>['- （读取本地记忆资料失败，仍可陪老人聊天。）'];
    }
  }

  static Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
  }

  // Convenience to serialize/deserialize JSON in 'metadata' or 'extra' fields
  static String encodeJson(Object? obj) => json.encode(obj);
  static dynamic decodeJson(String? jsonStr) =>
      jsonStr == null ? null : json.decode(jsonStr);
}
