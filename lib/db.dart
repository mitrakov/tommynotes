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
    if (_database == null) return 0;

    return _database!.transaction((tx) async {
      final noteId = await tx.rawInsert("INSERT INTO note DEFAULT VALUES;");
      await tx.rawInsert("INSERT INTO notedata (rowid, data) VALUES (?, ?);", [noteId, data]);
      return noteId;
    });
  }

  /// returns the number of rows affected
  Future<int> updateNote(int noteId, String data) async {
    if (_database == null) return 0;

    return await _database!.rawUpdate("UPDATE notedata SET data = ? WHERE rowid = ?;", [data, noteId]);
  }

  Future<void> deleteNote(int noteId) async {
    if (_database == null) return;

    final tx = _database!.batch();
    tx.rawDelete("DELETE FROM note     WHERE note_id = ?;", [noteId]); // TODO soft delete?
    tx.rawDelete("DELETE FROM notedata WHERE rowid = ?;", [noteId]);
    tx.rawDelete("DELETE FROM tag      WHERE tag_id NOT IN (SELECT DISTINCT tag_id FROM note_to_tag);");
    await tx.commit(noResult: true, continueOnError: false);
  }

  Future<Iterable<Note>> getNotes() async {
    if (_database == null) return [];

    final dbResult = await _database!.rawQuery("""
      SELECT note_id, data, GROUP_CONCAT(name, ', ') AS tags
      FROM note
      INNER JOIN notedata ON note_id = notedata.rowid
      INNER JOIN note_to_tag USING (note_id)
      INNER JOIN tag         USING (tag_id)
      GROUP BY note_id
      ;""");
    return dbResult.map((e) => Note(noteId: int.parse(e["note_id"].toString()), note: e["data"].toString(), tags: e["tags"].toString()));
  }

  Future<Iterable<String>> getTags() async {
    if (_database == null) return [];

    final dbResult = await _database!.rawQuery("SELECT name FROM tag;");
    return dbResult.map((e) => e["name"].toString());
  }

  Future<Iterable<Note>> searchByTag(String tag) async {
    if (_database == null) return [];

    final dbResult = await _database!.rawQuery("""
      SELECT note_id, data
      FROM notedata
      INNER JOIN note_to_tag ON notedata.rowid = note_id
      INNER JOIN tag USING (tag_id)
      WHERE name = ?
      ORDER BY note_to_tag.updated_at DESC
      ;""", [tag]);
    return dbResult.map((e) => Note(noteId: int.parse(e["note_id"].toString()), note: e["data"].toString(), tags: tag));
  }

  Future<Iterable<Note>> searchByKeyword(String word) async {
    if (_database == null) return [];
    if (word.isEmpty) return [];

    final dbResult = await _database!.rawQuery("""
      SELECT note_id, data, GROUP_CONCAT(name, ', ') AS tags
      FROM note
      INNER JOIN notedata ON note_id = notedata.rowid
      INNER JOIN note_to_tag USING (note_id)
      INNER JOIN tag         USING (tag_id)
      WHERE data MATCH ?
      GROUP BY note_id
      ORDER BY notedata.rank, note.updated_at
      ;""", [word]
    );
    return dbResult.map((e) => Note(noteId: int.parse(e["note_id"].toString()), note: e["data"].toString(), tags: e["tags"].toString()));
  }

  Future<void> linkTagsToNote(int noteId, Iterable<String> tags) async {
    if (_database == null) return;

    return _database!.transaction((tx) async {
      await Future.wait(tags.map((tag) async {
        final tagIdOpt = await tx.rawQuery("SELECT tag_id FROM tag WHERE name = ?;", [tag]);
        final tagId = tagIdOpt.isNotEmpty ? int.parse(tagIdOpt.first["tag_id"].toString()) : await tx.rawInsert("INSERT INTO tag (name) VALUES (?);", [tag]);
        await tx.rawInsert("INSERT INTO note_to_tag (note_id, tag_id) VALUES (?, ?);", [noteId, tagId]);
      }));
    });
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
