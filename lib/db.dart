import 'package:sqflite/sqflite.dart';

class Db {
  Db._();
  static final Db instance = Db._();
  static Database? _database;

  Database? get database => _database;

  Future<void> openDb(String path) async {
    _database = await openDatabase(path);
  }

  Future<void> createDb(String path) async {
    _database = await openDatabase(path, version: 1, onCreate: (db, version) async {
      await db.execute("""
        CREATE TABLE note (
          note_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
          data TEXT NOT NULL,
          author VARCHAR(64) NOT NULL DEFAULT '',
          client VARCHAR(255) NOT NULL DEFAULT '',
          user_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          colour INTEGER NOT NULL DEFAULT 16777215,
          rank TINYINT NOT NULL DEFAULT 0,
          is_visible BOOLEAN NOT NULL DEFAULT true,
          is_favourite BOOLEAN NOT NULL DEFAULT false,
          is_deleted BOOLEAN NOT NULL DEFAULT false,
          created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        );""");

      await db.execute("""  
        CREATE TABLE tag (
          tag_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
          name VARCHAR(64) UNIQUE NOT NULL,
          created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        );""");

      await db.execute("""  
        CREATE TABLE image (
          guid UUID PRIMARY KEY NOT NULL,
          data BLOB NOT NULL,
          created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        );""");

      await db.execute("""  
        CREATE TABLE note_to_tag (
          note_id INTEGER NOT NULL REFERENCES note (note_id) ON UPDATE RESTRICT ON DELETE CASCADE,
          tag_id INTEGER NOT NULL REFERENCES tag (tag_id) ON UPDATE RESTRICT ON DELETE CASCADE,
          created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (note_id, tag_id)
        );""");

      await db.execute("""  
        CREATE TABLE metadata (
          key VARCHAR(64) PRIMARY KEY NOT NULL,
          value VARCHAR(255) NOT NULL,
          created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        );""");

      await db.execute("INSERT INTO metadata (key, value) VALUES ('author', 'Artem Mitrakov, https://github.com/mitrakov, mitrakov-artem@yandex.ru'), ('schema_version', '1');");
    });
  }
}
