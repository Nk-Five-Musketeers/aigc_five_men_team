import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._();

  static Database? _db;

  static Future<Database> instance() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'bluecare.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE chat_messages(
          id TEXT PRIMARY KEY,
          content TEXT NOT NULL,
          is_user INTEGER NOT NULL,
          timestamp TEXT NOT NULL
        )
      ''');
    });
    return _db!;
  }
}
