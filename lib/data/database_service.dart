import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

class DatabaseService {
  static const _dbName = 'doable.db';
  static const _dbVersion = 1;

  static Database? _db;
  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  static Future<Database> instance() async {
    await _ensureInitialized();
    if (_db != null) return _db!;
    final base = await getDatabasesPath();
    final path = p.join(base, _dbName);
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT,
            time TEXT,
            date TEXT,
            has_notification INTEGER NOT NULL DEFAULT 0,
            repeat_rule TEXT,
            completed INTEGER NOT NULL DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT
          )
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
      },
    );
    return _db!;
  }
}
