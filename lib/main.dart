// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';
import 'package:markdown_widget/widget/markdown.dart';
import 'package:tommynotes/db.dart';
import 'package:tommynotes/note.dart';
import 'package:tommynotes/settings.dart';
import 'package:tommynotes/trixcontainer.dart';

const String lastOpenPathKey = "LAST_OPEN_PATH";

void main() async {
  // debugPaintSizeEnabled = true;
  WidgetsFlutterBinding.ensureInitialized(); // allow async code in main()
  await Settings.instance.init();
  final path = Settings.instance.settings.getString(lastOpenPathKey) ?? await getStartFile();
  await Db.instance.initDb(path);

  runApp(const MyApp());
}

Future<String> getStartFile() async {
  final FilePickerResult? res = await FilePicker.platform.pickFiles(dialogTitle: "Select a DB file", type: FileType.custom, allowedExtensions: ["db"], lockParentWindow: true);
  final result = res?.files.first.path ?? "";
  if (result.isNotEmpty)
    Settings.instance.settings.setString(lastOpenPathKey, result);
  return result;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        leading: IconButton(icon: const Icon(Icons.add_box_rounded), onPressed: () => setState(() {
          _noteId = 0;
          _mainCtrl.text = "";
          _tagsCtrl.text = "";
        })),
      ),
      body: Column(
        children: [
          Flexible(
            flex: 8,
            child: Row(
              children: [
                Expanded(
                  child: TrixContainer(
                    child: FutureBuilder(
                      future: _getTags(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          final tags = snapshot.data!.map((tag) => Text(tag)).toList();
                          return ListView(children: [const Text("Tags", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), ...tags]);
                        } else return const CircularProgressIndicator();
                      },
                    ),
                  ),
                ),
                Flexible(
                  flex: 6,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: TrixContainer(
                                child: TextField(controller: _mainCtrl, maxLines: 1024, onChanged: (s) => setState(() {})),
                              ),
                            ),
                            Expanded(child: TrixContainer(child: MarkdownWidget(data: _mainCtrl.text))),
                          ],
                        ),
                      ),
                      TrixContainer(
                        child: Row(children: [
                          SizedBox(width: 300, child: TextField(controller: _tagsCtrl, decoration: const InputDecoration(label: Text("Tags")))),
                          OutlinedButton(onPressed: _save, child: Text(_noteId == 0 ? "Add New" : "Save")),
                        ]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TrixContainer(
              child: FutureBuilder(
                future: _getNotes(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final futureResult = snapshot.data!;
                    final children = futureResult.map((note) =>
                      TrixContainer(
                        child: TextButton(child: Text(note.note.substring(0, min(note.note.length, 32))), onPressed: () => setState(() {
                          _noteId = note.noteId;
                          _mainCtrl.text = note.note;
                          _tagsCtrl.text = note.tags;
                        }))
                      )).toList(); // TODO 32 is total char count which is wrong
                    return ListView(scrollDirection: Axis.horizontal, children: children); // TODO use ListView.builder
                  } else return const CircularProgressIndicator();
                },
              ),
            ),
          )
        ],
      ),
    );
  }

  Future<Iterable<Note>> _getNotes() async {
    final dbResult = await Db.instance.database.rawQuery(
      "SELECT note_id, data, GROUP_CONCAT(name, ', ') AS tags FROM note INNER JOIN note_to_tag USING (note_id) INNER JOIN tag USING (tag_id) GROUP BY note_id;"
    );
    return dbResult.map((e) => Note(noteId: int.parse(e["note_id"].toString()), note: e["data"].toString(), tags: e["tags"].toString()));
  }

  Future<Iterable<String>> _getTags() async {
    final dbResult = await Db.instance.database.rawQuery("SELECT name FROM tag;");
    return dbResult.map((e) => e["name"].toString());
  }

  void _save() async {
    final data = _mainCtrl.text.trim();
    final tags = _tagsCtrl.text.split(",").map((tag) => tag.trim()).where((tag) => tag.isNotEmpty);
    if (tags.isEmpty) {
      FlutterPlatformAlert.showAlert(windowTitle: "Tag required", text: 'Please add at least 1 tag, e.g. "Work", "New" or "TODO"');
      return;
    }
    if (data.isNotEmpty) {
      if (_noteId == 0) { // INSERT
        final newNoteId = await Db.instance.database.rawInsert("INSERT INTO note (data) VALUES (?);", [data]);
        tags.forEach((tag) async {
          late final int tagId;
          final tagIdOpt = await Db.instance.database.rawQuery("SELECT tag_id FROM tag WHERE name = ?;", [tag]);
          if (tagIdOpt.isNotEmpty) { // Tag exists
            tagId = int.parse(tagIdOpt.first["tag_id"].toString());
          } else {                   // New tag
            tagId = await Db.instance.database.rawInsert("INSERT INTO tag (name) VALUES (?);", [tag]);
          }
          
          await Db.instance.database.rawInsert("INSERT INTO note_to_tag (note_id, tag_id) VALUES (?, ?);", [newNoteId, tagId]);
        });
        setState(() {
          _noteId = newNoteId;
          // text and tags are kept
        });
        FlutterPlatformAlert.showAlert(windowTitle: "Success", text: "New note added");
      } else { // UPDATE
        await Db.instance.database.rawUpdate("UPDATE note SET data = ? WHERE note_id = ?;", [data, _noteId]);
        // TODO update tags
        setState(() {}); // repaint
        FlutterPlatformAlert.showAlert(windowTitle: "Success", text: "Updated");
      }
    }
  }
}
