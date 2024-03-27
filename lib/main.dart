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

const String lastOpenPathKey = "LAST_OPEN_PATH";
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
  final TextEditingController _mainCtrl = TextEditingController();
  final TextEditingController _tagsCtrl = TextEditingController();
  int _noteId = 0;
  String? _currentTag;

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: "Hey-Hey",
          menus: [
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(label: "New DB file", onSelected: _newDbFile),
              PlatformMenuItem(label: "Open DB file", onSelected: _openDbFile),
              PlatformMenuItem(label: "Open latest DB file", onSelected: _openLatestDbFile),
            ]),
            PlatformMenuItem(label: "Quit", onSelected: () => exit(0)),
          ],
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text(widget.title),
          leading: IconButton(icon: const Icon(Icons.add_box_rounded), onPressed: () => setState(() {
            _noteId = 0;
            _mainCtrl.text = "";
            _tagsCtrl.text = "";
            _currentTag = null;
          })),
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
                            child: OutlinedButton(child: Text(tag), onPressed: () => setState(() {
                              _noteId = 0;
                              _mainCtrl.text = "";
                              _tagsCtrl.text = "";
                              _currentTag = tag;
                            })),
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
                          onPressed: () => setState(() {
                            _noteId = note.noteId;
                            _mainCtrl.text = note.note;
                            _tagsCtrl.text = note.tags;
                            _currentTag = null;
                          }),
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
      FlutterPlatformAlert.showAlert(windowTitle: "Tag required", text: 'Please add at least 1 tag, e.g. "Work", "New" or "TODO"');
      return;
    }
    if (data.isNotEmpty) {
      if (_noteId == 0) { // INSERT
        final newNoteId = await Db.instance.database!.rawInsert("INSERT INTO note (data) VALUES (?);", [data]);
        tags.forEach((tag) async {
          late final int tagId;
          final tagIdOpt = await Db.instance.database!.rawQuery("SELECT tag_id FROM tag WHERE name = ?;", [tag]);
          if (tagIdOpt.isNotEmpty) { // Tag exists
            tagId = int.parse(tagIdOpt.first["tag_id"].toString());
          } else {                   // New tag
            tagId = await Db.instance.database!.rawInsert("INSERT INTO tag (name) VALUES (?);", [tag]);
          }
          
          await Db.instance.database!.rawInsert("INSERT INTO note_to_tag (note_id, tag_id) VALUES (?, ?);", [newNoteId, tagId]);
        });
        await FlutterPlatformAlert.showAlert(windowTitle: "Success", text: "New note added");
        setState(() {
          _noteId = newNoteId;
          //! _mainCtrl.text = same;
          //! _tagsCtrl.text = same;
          //! _currentTag = null;
        });
      } else { // UPDATE
        await Db.instance.database!.rawUpdate("UPDATE note SET data = ? WHERE note_id = ?;", [data, _noteId]);
        // TODO update tags
        await FlutterPlatformAlert.showAlert(windowTitle: "Success", text: "Updated");
        setState(() {}); // refresh
      }
    }
  }

  void _newDbFile() async {
    final path = await FilePicker.platform.saveFile(dialogTitle: "Create a new DB file", fileName: "workspace.db", allowedExtensions: ["db"], lockParentWindow: true);
    if (path != null) {
      Settings.instance.settings.setString(lastOpenPathKey, path);
      await Db.instance.createDb(path);
      setState(() {}); // refresh
    }
  }

  void _openDbFile() async {
    final path = await _getStartFile();
    if (path != null) {
      await Db.instance.openDb(path);
      setState(() {}); // refresh
    }
  }

  void _openLatestDbFile() async {
    final path = Settings.instance.settings.getString(lastOpenPathKey) ?? await _getStartFile();
    if (path != null) {
      await Db.instance.openDb(path);
      setState(() {}); // refresh
    }
  }

  Future<String?> _getStartFile() async {
    final FilePickerResult? res = await FilePicker.platform.pickFiles(dialogTitle: "Select a DB file", type: FileType.custom, allowedExtensions: ["db"], lockParentWindow: true);
    final path = res?.files.first.path;
    if (path != null)
      Settings.instance.settings.setString(lastOpenPathKey, path);
    return path;
  }

  Future<Widget> _searchByTag(String tag) async {
    final rows = await Db.instance.database!.rawQuery("SELECT data FROM note INNER JOIN note_to_tag USING (note_id) INNER JOIN tag USING (tag_id) WHERE name = ?;", [tag]);
    final children = rows.map((e) => TrixContainer(child: MarkdownWidget(data: e["data"].toString(), shrinkWrap: true))).toList();
    return ListView(children: children);
  }
}
