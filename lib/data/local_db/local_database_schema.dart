part of 'local_database.dart';

const List<String> _requiredApplicationTables = <String>[
  'users',
  'family_members',
  'memory_events',
  'daily_life_records',
  'conversations',
  'conversation_members',
  'messages',
  'attachments',
  'nearby_people',
  'relation_conflicts',
  'profile_photos',
  'cognitive_tests',
];

/// 在每次打开库后执行：若任一张核心表缺失，则补跑幂等 DDL（不依赖 onCreate/onUpgrade 是否被触发）。
Future<void> _repairSchemaIfIncomplete(Database db) async {
  for (final name in _requiredApplicationTables) {
    if (!await _tableExists(db, name)) {
      debugPrint(
        'LocalDatabase: 表 "$name" 缺失，将补全完整结构（常见于空库文件已带版本号等情况）。',
      );
      await _createSchema(db);
      return;
    }
  }
}

void _initDatabaseFactoryForCurrentPlatform() {
  if (LocalDatabase._dbFactoryReady) return;
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
    LocalDatabase._dbFactoryReady = true;
    return;
  }
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  LocalDatabase._dbFactoryReady = true;
}

// Helper utilities: use async methods only (no blocking IO)

/// 完整业务 DDL；全部使用 `IF NOT EXISTS`，供 [onCreate]、[onOpen] 修复路径与安全复用。
Future<void> _createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS users(
      id TEXT PRIMARY KEY,
      name TEXT,
      avatar_path TEXT,
      metadata TEXT,
      created_at TEXT,
      updated_at TEXT,
      birth_year TEXT,
      hometown TEXT,
      career TEXT,
      hobbies TEXT,
      food_preference TEXT,
      personality TEXT,
      taboo TEXT,
      dialect TEXT,
      gender TEXT,
      current_address TEXT,
      care_notes TEXT,
      medical_notes TEXT
    )
  ''');

  await _createFamilyMemoryDailyTables(db);

  await db.execute('''
    CREATE TABLE IF NOT EXISTS conversations(
      id TEXT PRIMARY KEY,
      title TEXT,
      created_at TEXT,
      last_message_id TEXT,
      owner_user_id TEXT,
      FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE SET NULL
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
      is_active INTEGER NOT NULL DEFAULT 1,
      family_member_id INTEGER,
      metadata TEXT,
      created_at TEXT,
      updated_at TEXT,
      FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY(family_member_id) REFERENCES family_members(id) ON DELETE SET NULL
    )
  ''');

  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_messages_conversation_timestamp ON messages(conversation_id, timestamp DESC)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_attachments_message ON attachments(message_id)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_nearby_people_owner ON nearby_people(owner_user_id)');

  await _createProfilePhotoTables(db);
  await _createCognitiveTestTables(db);

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

/// 表2 家庭成员、表3 记忆事件、表5 每日生活记录（均归属 users.id）。
/// 使用 `IF NOT EXISTS`，便于 [onCreate] 与升级路径安全复用，并补全「只建了其中一张表」的中间状态。
Future<void> _createFamilyMemoryDailyTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS family_members(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_user_id TEXT NOT NULL,
      name TEXT,
      relation TEXT,
      photo_path TEXT,
      birthday TEXT,
      location TEXT,
      contact_freq TEXT,
      notes TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT,
      updated_at TEXT,
      FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_family_members_owner ON family_members(owner_user_id)');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS memory_events(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_user_id TEXT NOT NULL,
      event_time TEXT,
      title TEXT,
      description TEXT,
      location TEXT,
      people_involved TEXT,
      emotion TEXT,
      photo_paths TEXT,
      video_path TEXT,
      importance INTEGER NOT NULL DEFAULT 3,
      source TEXT,
      verified INTEGER NOT NULL DEFAULT 0,
      used_count INTEGER NOT NULL DEFAULT 0,
      last_used TEXT,
      created_at TEXT,
      updated_at TEXT,
      FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_events_owner ON memory_events(owner_user_id)');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS daily_life_records(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_user_id TEXT NOT NULL,
      date TEXT NOT NULL,
      breakfast TEXT,
      lunch TEXT,
      dinner TEXT,
      activities TEXT,
      people_met TEXT,
      places_went TEXT,
      mood TEXT,
      raw_extract TEXT,
      source_dialog TEXT,
      created_at TEXT,
      updated_at TEXT,
      FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE,
      UNIQUE(owner_user_id, date)
    )
  ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_daily_life_owner_date ON daily_life_records(owner_user_id, date DESC)');
}

Future<void> _ensurePreEntrySchema(Database db) async {
  await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN gender TEXT');
  await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN current_address TEXT');
  await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN care_notes TEXT');
  await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN medical_notes TEXT');
  await _tryAddColumn(
      db, 'ALTER TABLE nearby_people ADD COLUMN photo_path TEXT');
  await _tryAddColumn(db, 'ALTER TABLE nearby_people ADD COLUMN birthday TEXT');
  await _tryAddColumn(db, 'ALTER TABLE nearby_people ADD COLUMN location TEXT');
  await _tryAddColumn(
      db, 'ALTER TABLE nearby_people ADD COLUMN contact_freq TEXT');
  await _tryAddColumn(db,
      'ALTER TABLE nearby_people ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1');
  await _tryAddColumn(
      db, 'ALTER TABLE nearby_people ADD COLUMN family_member_id INTEGER');
  await _createProfilePhotoTables(db);
}

Future<void> _createProfilePhotoTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS profile_photos(
      id TEXT PRIMARY KEY,
      owner_user_id TEXT NOT NULL,
      file_path TEXT NOT NULL,
      storage_type TEXT NOT NULL DEFAULT 'file_path',
      category TEXT,
      caption TEXT,
      photo_time TEXT,
      location TEXT,
      people_involved TEXT,
      family_member_id INTEGER,
      memory_event_id INTEGER,
      is_favorite INTEGER NOT NULL DEFAULT 0,
      metadata TEXT,
      created_at TEXT,
      updated_at TEXT,
      FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE,
      FOREIGN KEY(family_member_id) REFERENCES family_members(id) ON DELETE SET NULL,
      FOREIGN KEY(memory_event_id) REFERENCES memory_events(id) ON DELETE SET NULL
    )
  ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_profile_photos_owner ON profile_photos(owner_user_id)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_profile_photos_category ON profile_photos(owner_user_id, category)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_profile_photos_family_member ON profile_photos(family_member_id)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_profile_photos_memory_event ON profile_photos(memory_event_id)');
}

Future<void> _createCognitiveTestTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS cognitive_tests(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_user_id TEXT NOT NULL,
      test_type TEXT NOT NULL,
      image_path TEXT,
      prompt_text TEXT,
      user_answer TEXT,
      is_valid INTEGER NOT NULL DEFAULT 0,
      score_note TEXT,
      created_at TEXT,
      FOREIGN KEY(owner_user_id) REFERENCES users(id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cognitive_tests_owner_time ON cognitive_tests(owner_user_id, created_at DESC)');
}

Future<void> _upgradeSchema(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await _ensureCoreTables(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS nearby_people(
        id TEXT PRIMARY KEY,
        owner_user_id TEXT NOT NULL,
        name TEXT,
        relation TEXT,
        phone TEXT,
        address TEXT,
        note TEXT,
        is_emergency_contact INTEGER DEFAULT 0,
        distance_meters REAL,
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
      await db
          .execute('ALTER TABLE conversations ADD COLUMN owner_user_id TEXT');
    } catch (_) {
      // Column may already exist on partial installs.
    }
    await db.rawUpdate(
      'UPDATE conversations SET owner_user_id = ? WHERE id = ? AND (owner_user_id IS NULL OR owner_user_id = \'\')',
      [
        LocalDatabase.legacyDefaultUserId,
        LocalDatabase.legacyDefaultConversationId
      ],
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
  if (oldVersion < 5) {
    await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN updated_at TEXT');
    await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN birth_year TEXT');
    await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN hometown TEXT');
    await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN career TEXT');
    await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN hobbies TEXT');
    await _tryAddColumn(
        db, 'ALTER TABLE users ADD COLUMN food_preference TEXT');
    await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN personality TEXT');
    await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN taboo TEXT');
    await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN dialect TEXT');

    await _createFamilyMemoryDailyTables(db);
  }
  if (oldVersion < 6) {
    await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN gender TEXT');
    await _tryAddColumn(
        db, 'ALTER TABLE users ADD COLUMN current_address TEXT');
    await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN care_notes TEXT');
    await _tryAddColumn(db, 'ALTER TABLE users ADD COLUMN medical_notes TEXT');

    await _tryAddColumn(
        db, 'ALTER TABLE nearby_people ADD COLUMN photo_path TEXT');
    await _tryAddColumn(
        db, 'ALTER TABLE nearby_people ADD COLUMN birthday TEXT');
    await _tryAddColumn(
        db, 'ALTER TABLE nearby_people ADD COLUMN location TEXT');
    await _tryAddColumn(
        db, 'ALTER TABLE nearby_people ADD COLUMN contact_freq TEXT');
    await _tryAddColumn(db,
        'ALTER TABLE nearby_people ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1');
    await _tryAddColumn(
        db, 'ALTER TABLE nearby_people ADD COLUMN family_member_id INTEGER');

    await _createFamilyMemoryDailyTables(db);
    await _createProfilePhotoTables(db);
    await _createCognitiveTestTables(db);
  }
  if (newVersion > LocalDatabase._dbVersion) {
    return;
  }
}

Future<void> _tryAddColumn(Database db, String sql) async {
  try {
    await db.execute(sql);
  } catch (_) {
    // Column may already exist on partial installs.
  }
}

Future<void> _ensureCoreTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS users(
      id TEXT PRIMARY KEY,
      name TEXT,
      avatar_path TEXT,
      metadata TEXT,
      created_at TEXT,
      updated_at TEXT,
      birth_year TEXT,
      hometown TEXT,
      career TEXT,
      hobbies TEXT,
      food_preference TEXT,
      personality TEXT,
      taboo TEXT,
      dialect TEXT,
      gender TEXT,
      current_address TEXT,
      care_notes TEXT,
      medical_notes TEXT
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
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_attachments_message ON attachments(message_id)');
}

Future<void> _migrateLegacyChatMessages(Database db) async {
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
          'id': (row['id'] ?? 'legacy_${DateTime.now().microsecondsSinceEpoch}')
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

Future<bool> _tableExists(Database db, String tableName) async {
  final result = await db.query(
    'sqlite_master',
    columns: ['name'],
    where: 'type = ? AND name = ?',
    whereArgs: ['table', tableName],
    limit: 1,
  );
  return result.isNotEmpty;
}
