// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
  final TextEditingController _ctrl = TextEditingController();
  int _noteId = 0;

  Future<Iterable<Note>> getNotes() async {
    final db = Db.instance.database;
    final dbResult = await db.rawQuery("SELECT note_id, data FROM note ORDER BY note_id;");
    return dbResult.map((e) => Note(noteId: int.parse(e["note_id"].toString()), note: e["data"].toString()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        leading: IconButton(icon: const Icon(Icons.add_box_rounded), onPressed: () => setState(() {
          _ctrl.text = "";
          _noteId = 0;
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
                    child: ListView(children: const [
                      Text("Tags", style: TextStyle(fontWeight: FontWeight.bold),),
                      Text("One"),
                      Text("Two"),
                      Text("Three"),
                    ]),
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
                                child: TextField(controller: _ctrl, maxLines: 1024, onChanged: (s) => setState(() {})),
                              ),
                            ),
                            Expanded(child: TrixContainer(child: MarkdownWidget(data: _ctrl.text))),
                          ],
                        ),
                      ),
                      TrixContainer(
                        child: Row(children: [
                          OutlinedButton(onPressed: () {}, child: const Text("Tags here                                 ")),
                          OutlinedButton(child: Text(_noteId == 0 ? "Add New" : "Save"), onPressed: () async {
                            final data = _ctrl.text.trim();
                            if (data.isNotEmpty) {
                              if (_noteId == 0) { // INSERT
                                final newId = await Db.instance.database.rawInsert("INSERT INTO note (data) VALUES (?);", [data]);
                                setState(() {
                                  _noteId = newId;
                                });
                              } else { // UPDATE
                                await Db.instance.database.rawUpdate("UPDATE note SET data = ? WHERE note_id = ?;", [data, _noteId]);
                                setState(() {}); // repaint
                              }
                              // TODO show OK dialog
                            }
                          }),
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
                future: getNotes(),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    final futureResult = snapshot.data!;
                    final children = futureResult.map((note) =>
                      TrixContainer(
                        child: TextButton(child: Text(note.note.substring(0, min(note.note.length, 32))), onPressed: () => setState(() {
                          _ctrl.text = note.note;
                          _noteId = note.noteId;
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
}
