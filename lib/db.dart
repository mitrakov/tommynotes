// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:sqflite/sqflite.dart';

class Db {
  Db._();
  static final Db instance = Db._();
  static Database? _database;

  Database get database {
    if (_database != null) return _database!;
    else throw Exception("Database is not initialized. Call Db.instance.initDb() first.");
  }

  Future<void> initDb(String path) async {
    _database = await openDatabase(path);
  }
}
