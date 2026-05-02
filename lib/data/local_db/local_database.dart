import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._();

  static Database? _db;
  static bool _sqliteUnavailable = false;

  static Future<Database> instance() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'shiyi_memory.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: _createTables,
      onUpgrade: (db, oldVersion, newVersion) async {
        await _dropTables(db);
        await _createTables(db, newVersion);
      },
    );
    return _db!;
  }

  static Future<Database?> tryInstance() async {
    if (kIsWeb || _sqliteUnavailable) return null;

    try {
      return await instance();
    } catch (_) {
      _sqliteUnavailable = true;
      return null;
    }
  }

  static Future<void> _dropTables(Database db) async {
    await db.execute('DROP TABLE IF EXISTS elder_basic_info');
    await db.execute('DROP TABLE IF EXISTS family_members');
    await db.execute('DROP TABLE IF EXISTS memory_events');
    await db.execute('DROP TABLE IF EXISTS daily_life_records');
    await db.execute('DROP TABLE IF EXISTS conversation_records');
    await db.execute('DROP TABLE IF EXISTS chat_messages');
    await db.execute('DROP TABLE IF EXISTS memory_items');
    await db.execute('DROP TABLE IF EXISTS daily_notes');
    await db.execute('DROP TABLE IF EXISTS media_assets');
    await db.execute('DROP TABLE IF EXISTS memory_links');
  }

  static Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE elder_basic_info(
        id INTEGER PRIMARY KEY,
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
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE family_members(
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        relation TEXT,
        photo_path TEXT,
        birthday TEXT,
        location TEXT,
        contact_freq TEXT,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        source_dialog TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE memory_events(
        id INTEGER PRIMARY KEY,
        event_time TEXT,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
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
        source_dialog TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE daily_life_records(
        id INTEGER PRIMARY KEY,
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
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE conversation_records(
        id INTEGER PRIMARY KEY,
        session_date TEXT NOT NULL,
        duration INTEGER NOT NULL DEFAULT 0,
        dialog_json TEXT NOT NULL,
        new_memories TEXT,
        cognitive_score TEXT,
        quiz_results TEXT,
        processed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_memory_events_title ON memory_events(title)',
    );
    await db.execute(
      'CREATE INDEX idx_memory_events_last_used ON memory_events(last_used)',
    );
    await db.execute(
      'CREATE INDEX idx_daily_life_date ON daily_life_records(date)',
    );
    await db.execute(
      'CREATE INDEX idx_conversation_session_date ON conversation_records(session_date)',
    );
  }
}
