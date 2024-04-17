import 'package:sqflite/sqflite.dart';
import 'package:tommynotes/note.dart';

class Db {
  Db._();
  static final Db instance = Db._();
  static Database? _database;

  Future<void> openDb(String path) async {
    _database = await openDatabase(path, onConfigure: _enableFk);
  }

  Future<void> closeDb() async {
    return _database?.close().then((_) => _database = null);
  }

  Future<void> createDb(String path) async {
    _database = await openDatabase(path, version: 1, onConfigure: _enableFk, onCreate: (db, version) async {
      final tx = db.batch();
      tx.execute("""
        CREATE TABLE note (
          note_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
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
      tx.execute("""CREATE VIRTUAL TABLE notedata USING FTS5(data);""");
      tx.execute("""  
        CREATE TABLE tag (
          tag_id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
          name VARCHAR(64) UNIQUE NOT NULL,
          created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        );""");
      tx.execute("""  
        CREATE TABLE image (
          guid UUID PRIMARY KEY NOT NULL,
          data BLOB NOT NULL,
          created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        );""");
      tx.execute("""  
        CREATE TABLE note_to_tag (
          note_id INTEGER NOT NULL REFERENCES note (note_id) ON UPDATE RESTRICT ON DELETE CASCADE,
          tag_id  INTEGER NOT NULL REFERENCES tag (tag_id) ON UPDATE RESTRICT ON DELETE CASCADE,
          created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (note_id, tag_id)
        );""");
      tx.execute("""  
        CREATE TABLE metadata (
          key VARCHAR(64) PRIMARY KEY NOT NULL,
          value VARCHAR(255) NOT NULL,
          created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        );""");
      // schema_version: 1=initial; 2=add full-text-search;
      tx.execute("INSERT INTO metadata (key, value) VALUES ('author', 'Artem Mitrakov, https://github.com/mitrakov, mitrakov-artem@yandex.ru'), ('schema_version', '2');");

      await tx.commit(noResult: true, continueOnError: false);
    });
  }

  bool isConnected() {
    return _database != null && _database!.isOpen;
  }

  /// returns new generated note_id > 0
  Future<int> insertNote(String data) async {
    if (_database == null) return Future.value(0);

    return await _database!.rawInsert("INSERT INTO note (data) VALUES (?);", [data]);
  }

  /// returns the number of rows affected
  Future<int> updateNote(int noteId, String data) async {
    if (_database == null) return Future.value(0);

    return await _database!.rawUpdate("UPDATE note SET data = ? WHERE note_id = ?;", [data, noteId]);
  }

  Future<void> deleteNote(int noteId) async {
    if (_database == null) return;

    final tx = _database!.batch();
    tx.rawDelete("DELETE FROM note WHERE note_id = ?;", [noteId]); // TODO soft delete?
    tx.rawDelete("DELETE FROM tag  WHERE tag_id NOT IN (SELECT DISTINCT tag_id FROM note_to_tag);");
    await tx.commit(noResult: true, continueOnError: false);
  }

  Future<Iterable<Note>> getNotes() async {
    if (_database == null) return Future.value([]);

    final dbResult = await _database!.rawQuery(
        "SELECT note_id, data, GROUP_CONCAT(name, ', ') AS tags FROM note INNER JOIN note_to_tag USING (note_id) INNER JOIN tag USING (tag_id) GROUP BY note_id;"
    );
    return dbResult.map((e) => Note(noteId: int.parse(e["note_id"].toString()), note: e["data"].toString(), tags: e["tags"].toString()));
  }

  Future<Iterable<String>> getTags() async {
    if (_database == null) return Future.value([]);

    final dbResult = await _database!.rawQuery("SELECT name FROM tag;");
    return dbResult.map((e) => e["name"].toString());
  }

  Future<Iterable<String>> searchByTag(String tag) async {
    if (_database == null) return Future.value([]);

    final rows = await _database!.rawQuery("SELECT data FROM note INNER JOIN note_to_tag USING (note_id) INNER JOIN tag USING (tag_id) WHERE name = ?;", [tag]);
    return rows.map((e) => e["data"].toString());
  }

  Future<void> linkTagsToNote(int noteId, Iterable<String> tags) async {
    if (_database == null) return;

    // find tag IDs by tag names
    final tagIds = await Future.wait(tags.map((tag) async {
      final tagIdOpt = await _database!.rawQuery("SELECT tag_id FROM tag WHERE name = ?;", [tag]);
      return tagIdOpt.isNotEmpty ? int.parse(tagIdOpt.first["tag_id"].toString()) : await _database!.rawInsert("INSERT INTO tag (name) VALUES (?);", [tag]);
    }));

    final tx = _database!.batch();
    tagIds.forEach((tagId) => tx.rawInsert("INSERT INTO note_to_tag (note_id, tag_id) VALUES (?, ?);", [noteId, tagId]));
    await tx.commit(noResult: true, continueOnError: false);
  }

  Future<void> unlinkTagsFromNote(int noteId, Iterable<String> tags) async {
    if (_database == null) return;

    // FROM https://github.com/tekartik/sqflite/blob/master/sqflite/doc/sql.md:
    // A common mistake is to expect to use IN (?) and give a list of values. This does not work. Instead you should list each argument one by one.
    final IN = List.filled(tags.length, '?').join(', ');
    final tx = _database!.batch();
    tx.rawDelete("DELETE FROM note_to_tag WHERE note_id = ? AND tag_id IN (SELECT tag_id FROM tag WHERE name IN ($IN));", [noteId, ...tags]);
    tx.rawDelete("DELETE FROM tag WHERE tag_id NOT IN (SELECT DISTINCT tag_id FROM note_to_tag);");
    await tx.commit(noResult: true, continueOnError: false);
  }

  // this is necessary to enable Foreign Keys support!
  void _enableFk(Database db) async {
    await db.execute("PRAGMA foreign_keys=ON;");
  }
}
