import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DBProvider {
  DBProvider._();
  static final DBProvider db = DBProvider._();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await initDB();
    return _database!;
  }

  initDB() async {
    Directory docDir = await getApplicationDocumentsDirectory();
    final dbPath = path.join(docDir.path, "main.db");
    return await openDatabase(dbPath, version: 1, onCreate: (db, version) async {
      await db.execute("CREATE TABLE main (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, data TEXT NOT NULL, binary BLOB NULL, author VARCHAR(64) NOT NULL DEFAULT '', "
      "client VARCHAR(255) NOT NULL DEFAULT '', date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, colour INTEGER NOT NULL DEFAULT 16777215, is_visible BOOLEAN NOT NULL DEFAULT true, "
      "created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, is_deleted BOOLEAN NOT NULL DEFAULT false);");
    });

  }
}

