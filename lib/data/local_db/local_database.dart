import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:uuid/uuid.dart';

class LocalDatabase {
  LocalDatabase._();

  static Database? _db;
  static bool _dbFactoryReady = false;

  static const _dbName = 'bluecare.db';
  static const _dbVersion = 8;

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
    );

    return _db!;
  }

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

  static void _initDatabaseFactoryForCurrentPlatform() {
    if (_dbFactoryReady) return;
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
      _dbFactoryReady = true;
      return;
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _dbFactoryReady = true;
  }

  // Helper utilities: use async methods only (no blocking IO)

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE users(
        id TEXT PRIMARY KEY,
        name TEXT,
        birth_year TEXT,
        hometown TEXT,
        career TEXT,
        hobbies TEXT,
        food_preference TEXT,
        personality TEXT,
        taboo TEXT,
        dialect TEXT,
        avatar_path TEXT,
        metadata TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE conversations(
        id TEXT PRIMARY KEY,
        title TEXT,
        created_at TEXT,
        last_message_id TEXT,
        owner_user_id TEXT,
        FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE conversation_members(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        role TEXT,
        UNIQUE(conversation_id, user_id),
        FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE messages(
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        user_id TEXT,
        content TEXT,
        type TEXT,
        timestamp TEXT,
        extra TEXT,
        FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE attachments(
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        type TEXT,
        file_path TEXT,
        mime TEXT,
        size INTEGER,
        metadata TEXT,
        FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE nearby_people(
        id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL,
        name TEXT,
        relation TEXT,
        photo_path TEXT,
        phone TEXT,
        birthday TEXT,
        location TEXT,
        address TEXT,
        contact_freq TEXT,
        note TEXT,
        is_emergency_contact INTEGER DEFAULT 0,
        distance_meters REAL,
        is_active INTEGER DEFAULT 1,
        metadata TEXT,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_messages_conversation ON messages(conversation_id)');
    await db
        .execute('CREATE INDEX idx_messages_timestamp ON messages(timestamp)');
    await db.execute(
        'CREATE INDEX idx_messages_conversation_timestamp ON messages(conversation_id, timestamp DESC)');
    await db.execute(
        'CREATE INDEX idx_attachments_message ON attachments(message_id)');
    await db.execute(
        'CREATE INDEX idx_nearby_people_owner ON nearby_people(owner_user_id)');

    await db.execute('''
      CREATE TABLE relation_conflicts(
        id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL,
        nearby_person_id TEXT,
        person_name TEXT NOT NULL,
        field_name TEXT NOT NULL,
        old_value TEXT,
        new_value TEXT,
        source_message_id TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT,
        resolved_at TEXT,
        FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(nearby_person_id) REFERENCES nearby_people(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_relation_conflicts_owner ON relation_conflicts(owner_user_id, status)');

    await db.execute('''
      CREATE TABLE life_events(
        id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL,
        event_time TEXT,
        title TEXT,
        description TEXT,
        location TEXT,
        people_involved TEXT,
        emotion TEXT,
        photo_paths TEXT,
        video_paths TEXT,
        importance INTEGER,
        source TEXT,
        verified INTEGER DEFAULT 0,
        used_count INTEGER DEFAULT 0,
        last_used TEXT,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_life_records(
        record_id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL,
        date TEXT,
        breakfast TEXT,
        lunch TEXT,
        dinner TEXT,
        activities TEXT,
        people_met TEXT,
        places_went TEXT,
        mood TEXT,
        raw_extract TEXT,
        source_dialog_id TEXT,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_life_events_owner ON life_events(owner_user_id)');
  }

  static Future<void> _upgradeSchema(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _ensureCoreTables(db);
      await db.execute('''
        CREATE TABLE IF NOT EXISTS nearby_people(
          id TEXT PRIMARY KEY,
          owner_user_id TEXT NOT NULL,
          name TEXT,
          relation TEXT,
          photo_path TEXT,
          phone TEXT,
          birthday TEXT,
          location TEXT,
          address TEXT,
          contact_freq TEXT,
          note TEXT,
          is_emergency_contact INTEGER DEFAULT 0,
          distance_meters REAL,
          is_active INTEGER DEFAULT 1,
          metadata TEXT,
          created_at TEXT,
          updated_at TEXT,
          FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_nearby_people_owner ON nearby_people(owner_user_id)');
      await _migrateLegacyChatMessages(db);
    }
    if (oldVersion < 3) {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_messages_conversation_timestamp ON messages(conversation_id, timestamp DESC)');
    }
    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE conversations ADD COLUMN owner_user_id TEXT');
      } catch (_) {
        // Column may already exist on partial installs.
      }
      await db.rawUpdate(
        'UPDATE conversations SET owner_user_id = ? WHERE id = ? AND (owner_user_id IS NULL OR owner_user_id = \'\')',
        [legacyDefaultUserId, legacyDefaultConversationId],
      );
      await db.execute('''
        CREATE TABLE IF NOT EXISTS relation_conflicts(
          id TEXT PRIMARY KEY,
          owner_user_id TEXT NOT NULL,
          nearby_person_id TEXT,
          person_name TEXT NOT NULL,
          field_name TEXT NOT NULL,
          old_value TEXT,
          new_value TEXT,
          source_message_id TEXT,
          status TEXT NOT NULL DEFAULT 'pending',
          created_at TEXT,
          resolved_at TEXT,
          FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE,
          FOREIGN KEY(nearby_person_id) REFERENCES nearby_people(id) ON DELETE SET NULL
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_relation_conflicts_owner ON relation_conflicts(owner_user_id, status)');
    }
    if (oldVersion < 6) {
      // 为旧版数据库添加新列，逐个尝试以兼容已存在的列
      try {
        await db.execute('ALTER TABLE nearby_people ADD COLUMN photo_path TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE nearby_people ADD COLUMN birthday TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE nearby_people ADD COLUMN location TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE nearby_people ADD COLUMN contact_freq TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE nearby_people ADD COLUMN is_active INTEGER DEFAULT 1');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS life_events(
          id TEXT PRIMARY KEY,
          owner_user_id TEXT NOT NULL,
          event_time TEXT,
          title TEXT,
          description TEXT,
          location TEXT,
          people_involved TEXT,
          emotion TEXT,
          photo_paths TEXT,
          video_paths TEXT,
          importance INTEGER,
          source TEXT,
          verified INTEGER DEFAULT 0,
          used_count INTEGER DEFAULT 0,
          last_used TEXT,
          created_at TEXT,
          updated_at TEXT,
          FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_life_events_owner ON life_events(owner_user_id)');
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS daily_life_records(
          record_id TEXT PRIMARY KEY,
          owner_user_id TEXT NOT NULL,
          date TEXT,
          breakfast TEXT,
          lunch TEXT,
          dinner TEXT,
          activities TEXT,
          people_met TEXT,
          places_went TEXT,
          mood TEXT,
          raw_extract TEXT,
          source_dialog_id TEXT,
          created_at TEXT,
          updated_at TEXT,
          FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_daily_life_user_date ON daily_life_records(owner_user_id, date)');
    }
    if (oldVersion < 5) {
      // 为旧版数据库添加新列（若不存在则忽略错误）
      try {
        await db.execute('ALTER TABLE users ADD COLUMN birth_year TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN hometown TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN career TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN hobbies TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN food_preference TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN personality TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN taboo TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE users ADD COLUMN dialect TEXT');
      } catch (_) {}
    }
    if (newVersion > _dbVersion) {
      return;
    }
  }

  static Future<void> _ensureCoreTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users(
        id TEXT PRIMARY KEY,
        name TEXT,
        birth_year TEXT,
        hometown TEXT,
        career TEXT,
        hobbies TEXT,
        food_preference TEXT,
        personality TEXT,
        taboo TEXT,
        dialect TEXT,
        avatar_path TEXT,
        metadata TEXT,
        created_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversations(
        id TEXT PRIMARY KEY,
        title TEXT,
        created_at TEXT,
        last_message_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversation_members(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        role TEXT,
        UNIQUE(conversation_id, user_id),
        FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages(
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        user_id TEXT,
        content TEXT,
        type TEXT,
        timestamp TEXT,
        extra TEXT,
        FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attachments(
        id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        type TEXT,
        file_path TEXT,
        mime TEXT,
        size INTEGER,
        metadata TEXT,
        FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS life_events(
        id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL,
        event_time TEXT,
        title TEXT,
        description TEXT,
        location TEXT,
        people_involved TEXT,
        emotion TEXT,
        photo_paths TEXT,
        video_paths TEXT,
        importance INTEGER,
        source TEXT,
        verified INTEGER DEFAULT 0,
        used_count INTEGER DEFAULT 0,
        last_used TEXT,
        created_at TEXT,
        updated_at TEXT,
        FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_attachments_message ON attachments(message_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_life_events_owner ON life_events(owner_user_id)');
  }

  static Future<void> _migrateLegacyChatMessages(Database db) async {
    final legacyExists = await _tableExists(db, 'chat_messages');
    if (!legacyExists) return;

    const legacyUserId = 'local_user_default';
    const legacyConversationId = 'local_conversation_home';
    final now = DateTime.now().toIso8601String();
    await db.insert(
        'users',
        {
          'id': legacyUserId,
          'name': '王阿姨',
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert(
        'conversations',
        {
          'id': legacyConversationId,
          'title': '默认陪伴会话',
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert(
        'conversation_members',
        {
          'conversation_id': legacyConversationId,
          'user_id': legacyUserId,
          'role': 'owner',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);

    final oldRows = await db.query('chat_messages', orderBy: 'timestamp ASC');
    for (final row in oldRows) {
      await db.insert(
          'messages',
          {
            'id':
                (row['id'] ?? 'legacy_${DateTime.now().microsecondsSinceEpoch}')
                    .toString(),
            'conversation_id': legacyConversationId,
            'user_id': (row['is_user'] as int? ?? 0) == 1 ? legacyUserId : null,
            'content': row['content'] as String? ?? '',
            'type': 'text',
            'timestamp': row['timestamp'] as String? ?? now,
            'extra': json.encode({
              'is_user': (row['is_user'] as int? ?? 0) == 1,
              'migrated_from': 'chat_messages',
            }),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  static Future<bool> _tableExists(Database db, String tableName) async {
    final result = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ? AND name = ?',
      whereArgs: ['table', tableName],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  static Future<void> insertUser(Map<String, dynamic> user) async {
    final db = await instance();
    await db.insert('users', user,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, dynamic>?> getUserById(String id) async {
    final db = await instance();
    final res = await db.query('users', where: 'id = ?', whereArgs: [id]);
    if (res.isEmpty) return null;
    return res.first;
  }

  /// [nearby_people] / [relation_conflicts] 引用 users(id)，若缺少对应行，插入会因外键失败。
  static Future<void> ensureUserExists(String userId, {String? displayName}) async {
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
    final rows = await db.query('users', where: 'id = ?', whereArgs: [userId], limit: 1);
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
      {'metadata': encodeJson(meta)},
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

  static Future<int> removeNearbyPerson(String id) async {
    final db = await instance();
    return await db.delete('nearby_people', where: 'id = ?', whereArgs: [id]);
  }

  /// 人物姓名用于匹配时的规范化（与抽取逻辑一致）。
  static String normalizePersonName(String? name) {
    if (name == null) return '';
    return name.trim().replaceAll(RegExp(r'\s+'), '');
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
    assert(<String>{'relation', 'note', 'phone'}.contains(fieldName));
    await ensureUserExists(ownerUserId);
    final db = await instance();
    if (nearbyPersonId != null) {
      final dup = await db.query(
        'relation_conflicts',
        where:
            'owner_user_id = ? AND nearby_person_id = ? AND field_name = ? AND status = ?',
        whereArgs: [ownerUserId, nearbyPersonId, fieldName, 'pending'],
        limit: 1,
      );
      if (dup.isNotEmpty) return;
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

    await db.update(
      'relation_conflicts',
      {
        'status': useNew ? 'use_new' : 'keep_old',
        'resolved_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [conflictId],
    );
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
  static Future<int> deleteAllMessagesInConversation(String conversationId) async {
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
    final lastId =
        latest.isEmpty ? null : latest.first['id'] as String?;
    await db.update(
      'conversations',
      {'last_message_id': lastId},
      where: 'id = ?',
      whereArgs: [conversationId],
    );
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
