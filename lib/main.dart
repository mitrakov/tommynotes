// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';
import 'package:markdown_widget/widget/markdown.dart';
import 'package:native_context_menu/native_context_menu.dart';
import 'package:tommynotes/db.dart';
import 'package:tommynotes/note.dart';
import 'package:tommynotes/settings.dart';
import 'package:tommynotes/trixcontainer.dart';

const String recentFilesKey = "RECENT_FILES";
const String deleteKey = "Delete";

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // allow async code in main()
  Settings.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Tommy Notes",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: "TommyNotes"),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _mainCtrl = TextEditingController(); // main text in "Edit" mode
  final TextEditingController _tagsCtrl = TextEditingController(); // comma-separated text in tags textbox
  int _noteId = 0;                                                 // ID of the note to edit (0 = new note)
  String _oldTags = "";                                            // copy of "_tagsCtrl" to find the diff on update
  String? _currentTag;                                             // user-selected tag to display related notes (usually null)

  @override
  Widget build(BuildContext context) {
    final recentFilesMenus = Settings.instance.settings.getStringList(recentFilesKey)?.map((path) =>
      PlatformMenuItem(label: path, onSelected: () => _openDbFile(path))
    ).toList() ?? [];

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: "Hey-Hey",
          menus: [
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(label: "New file", onSelected: _newDbFile),
              PlatformMenuItem(label: "Open...", onSelected: _openDbFileWithDialog),
              PlatformMenu(label: "Open recent", menus: recentFilesMenus),
            ]),
            PlatformMenuItem(label: "Quit", onSelected: () => exit(0)),
          ],
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text(widget.title),
          leading: IconButton(icon: const Icon(Icons.add_box_rounded), onPressed: () => _setState(noteId: 0, oldTags: "", currentTag: null, mainCtrl: "", tagsCtrl: "")),
        ),
        body: Db.instance.database == null ? const Center(child: Text("Welcome!\nOpen or create a new DB file")) : Column(
          children: [
            Flexible(
              flex: 8,
              child: Row(children: [
                Expanded(
                  child: TrixContainer(
                    child: FutureBuilder(
                      future: _getTags(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          final tags = snapshot.data!.map((tag) => Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: OutlinedButton(child: Text(tag), onPressed: () => _setState(noteId: 0, oldTags: "", currentTag: tag, mainCtrl: "", tagsCtrl: "")),
                          )).toList();
                          return ListView( children: [const Text("Tags", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), ...tags]);
                        } else return const CircularProgressIndicator();
                      },
                    ),
                  ),
                ),
                Flexible(
                  flex: 6,
                  child: Column(children: [
                    Expanded(child: _currentTag == null
                      ? Row(children: [
                          Expanded(child: TrixContainer(child: TextField(controller: _mainCtrl, maxLines: 1024, onChanged: (s) => setState(() {})))),
                          Expanded(child: TrixContainer(child: MarkdownWidget(data: _mainCtrl.text))),
                        ])
                      : TrixContainer(child: FutureBuilder(
                          future: _searchByTag(_currentTag!),
                          builder: (context, snapshot) => snapshot.data ?? const CircularProgressIndicator(),
                        )),
                    ),
                    Visibility(
                      visible: _currentTag == null,
                      child: TrixContainer(child: Row(children: [
                        SizedBox(width: 300, child: TextField(controller: _tagsCtrl, decoration: const InputDecoration(label: Text("Tags")))),
                        OutlinedButton(onPressed: _saveNote, child: Text(_noteId == 0 ? "Add New" : "Save")),
                      ])),
                    )],
                  ),
                )],
              ),
            ),
            Expanded(
              child: TrixContainer(child: FutureBuilder(
                future: _getNotes(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final children = snapshot.data!.map((note) =>
                      ContextMenuRegion(
                        menuItems: [MenuItem(title: deleteKey)],
                        onItemSelected: (item) async {
                          if (item.title == deleteKey) {
                            await Db.instance.database!.rawDelete("DELETE FROM note WHERE note_id = ?;", [note.noteId]); // TODO soft delete?
                            await Db.instance.database!.rawDelete("DELETE FROM tag  WHERE tag_id NOT IN (SELECT DISTINCT tag_id FROM note_to_tag);");
                            setState(() {}); // refresh
                          }
                        },
                        child: TrixContainer(child: TextButton(
                          child: Text(note.note.substring(0, min(note.note.length, 32))), // TODO 32 is total char count which is wrong
                          onPressed: () => _setState(noteId: note.noteId, oldTags: note.tags, currentTag: null, mainCtrl: note.note, tagsCtrl: note.tags),
                        )),
                      )
                    ).toList();
                    return ListView(scrollDirection: Axis.horizontal, children: children); // TODO use ListView.builder for better performance
                  } else return const CircularProgressIndicator();
                },
              )),
            ),
          ],
        ),
      ),
    );
  }

  void _setState({required int noteId, required String oldTags, required String? currentTag, required String mainCtrl, required String tagsCtrl}) {
    setState(() { // list all state variables here!
      _mainCtrl.text = mainCtrl;
      _tagsCtrl.text = tagsCtrl;
      _noteId = noteId;
      _oldTags = oldTags;
      _currentTag = currentTag;
    });
  }

  Future<Iterable<Note>> _getNotes() async {
    final dbResult = await Db.instance.database!.rawQuery(
      "SELECT note_id, data, GROUP_CONCAT(name, ', ') AS tags FROM note INNER JOIN note_to_tag USING (note_id) INNER JOIN tag USING (tag_id) GROUP BY note_id;"
    );
    return dbResult.map((e) => Note(noteId: int.parse(e["note_id"].toString()), note: e["data"].toString(), tags: e["tags"].toString()));
  }

  Future<Iterable<String>> _getTags() async {
    final dbResult = await Db.instance.database!.rawQuery("SELECT name FROM tag;");
    return dbResult.map((e) => e["name"].toString());
  }

  void _saveNote() async {
    final data = _mainCtrl.text.trim();
    final tags = _tagsCtrl.text.split(",").map((tag) => tag.trim()).where((tag) => tag.isNotEmpty);
    if (tags.isEmpty) {
      FlutterPlatformAlert.showAlert(windowTitle: "Tag required", text: 'Please add at least 1 tag,\ne.g. "Work", "New" or "TODO"');
      return;
    }
    if (data.isNotEmpty) {
      if (_noteId == 0) { // INSERT
        final newNoteId = await Db.instance.database!.rawInsert("INSERT INTO note (data) VALUES (?);", [data]);
        await _addTags(newNoteId, tags);
        await FlutterPlatformAlert.showAlert(windowTitle: "Success", text: "New note added");
        _setState(noteId: newNoteId, oldTags: _oldTags, currentTag: null, mainCtrl: _mainCtrl.text, tagsCtrl: _tagsCtrl.text);
      } else { // UPDATE
        await Db.instance.database!.rawUpdate("UPDATE note SET data = ? WHERE note_id = ?;", [data, _noteId]);
        await _updateTags();
        await FlutterPlatformAlert.showAlert(windowTitle: "Success", text: "Updated");
        _setState(noteId: _noteId, oldTags: _tagsCtrl.text, currentTag: null, mainCtrl: _mainCtrl.text, tagsCtrl: _tagsCtrl.text);
      }
    }
  }

  void _newDbFile() async {
    final path = await FilePicker.platform.saveFile(dialogTitle: "Create a new DB file", fileName: "workspace.db", allowedExtensions: ["db"], lockParentWindow: true);
    if (path != null) {
      await Db.instance.createDb(path);
      _addRecentFile(path);
      _setState(noteId: 0, oldTags: "", currentTag: null, mainCtrl: "", tagsCtrl: "");
    }
  }

  void _openDbFile(String path) async {
    if (File(path).existsSync()) {
      await Db.instance.openDb(path);
      _addRecentFile(path);
      _setState(noteId: 0, oldTags: "", currentTag: null, mainCtrl: "", tagsCtrl: "");
    } else {
      FlutterPlatformAlert.showAlert(windowTitle: "Error", text: 'File not found:\n$path');
      _removeFromRecentFiles(path);
      setState(() {}); // update menu
    }
  }

  void _openDbFileWithDialog() async {
    final FilePickerResult? res = await FilePicker.platform.pickFiles(dialogTitle: "Select a DB file", type: FileType.custom, allowedExtensions: ["db"], lockParentWindow: true);
    final path = res?.files.first.path;
    if (path != null)
      _openDbFile(path);
  }

  void _addRecentFile(String path) {
    final settings = Settings.instance.settings;
    final list = settings.getStringList(recentFilesKey) ?? [];
    if (list.firstOrNull == path) return; // no changes needed
    if (list.contains(path))              // remove possible duplicates
      list.remove(path);
    list.insert(0, path);                 // prepend to the list
    settings.setStringList(recentFilesKey, list);
  }

  void _removeFromRecentFiles(String path) {
    final settings = Settings.instance.settings;
    final list = settings.getStringList(recentFilesKey) ?? [];
    list.remove(path);
    settings.setStringList(recentFilesKey, list);
  }

  Future<Widget> _searchByTag(String tag) async {
    final rows = await Db.instance.database!.rawQuery("SELECT data FROM note INNER JOIN note_to_tag USING (note_id) INNER JOIN tag USING (tag_id) WHERE name = ?;", [tag]);
    final children = rows.map((e) => TrixContainer(child: MarkdownWidget(data: e["data"].toString(), shrinkWrap: true))).toList();
    return ListView(children: children);
  }

  Future<void> _updateTags() async {
    final oldTags = _oldTags      .split(",").map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toSet();
    final newTags = _tagsCtrl.text.split(",").map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toSet();
    final rmTags  = oldTags.difference(newTags);
    final addTags = newTags.difference(oldTags);
    print("noteId = $_noteId; rmTags = $rmTags; addTags = $addTags");

    // FROM https://github.com/tekartik/sqflite/blob/master/sqflite/doc/sql.md:
    // A common mistake is to expect to use IN (?) and give a list of values. This does not work. Instead you should list each argument one by one.
    final IN = List.filled(rmTags.length, '?').join(', ');
    await Db.instance.database!.rawDelete("DELETE FROM note_to_tag WHERE note_id = ? AND tag_id IN (SELECT tag_id FROM tag WHERE name IN ($IN));", [_noteId, ...rmTags]);
    await Db.instance.database!.rawDelete("DELETE FROM tag WHERE tag_id NOT IN (SELECT DISTINCT tag_id FROM note_to_tag);");
    await _addTags(_noteId, addTags);
  }

  Future<void> _addTags(int noteId, Iterable<String> tags) async {
    tags.forEach((tag) async {
      final tagIdOpt = await Db.instance.database!.rawQuery("SELECT tag_id FROM tag WHERE name = ?;", [tag]);
      final tagId = tagIdOpt.isNotEmpty ? int.parse(tagIdOpt.first["tag_id"].toString()) : await Db.instance.database!.rawInsert("INSERT INTO tag (name) VALUES (?);", [tag]);

      await Db.instance.database!.rawInsert("INSERT INTO note_to_tag (note_id, tag_id) VALUES (?, ?);", [noteId, tagId]);
    });
  }
}
