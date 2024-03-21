import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:markdown_widget/widget/markdown.dart';
import 'package:tommynotes/db.dart';
import 'package:tommynotes/trixcontainer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // allow async code in main()
  final path = await getStartFile();
  await Db.instance.initDb(path);
  runApp(const MyApp());
}

Future<String> getStartFile() async {
  final FilePickerResult? result = await FilePicker.platform.pickFiles(dialogTitle: "Select a DB file", type: FileType.custom, allowedExtensions: ["db"], lockParentWindow: true);
  return result?.files.first.path ?? "";
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Flutter Demo",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: "Flutter Demo Home Page"),
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
  String _data = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
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
                                child: TextField(maxLines: 1024, onChanged: (s) {
                                  setState(() {
                                    _data = s;
                                  });
                                }),
                              ),
                            ),
                            Expanded(child: TrixContainer(child: MarkdownWidget(data: _data))),
                          ],
                        ),
                      ),
                      TrixContainer(
                        child: Row(children: [
                          OutlinedButton(onPressed: () {}, child: Text("Tags here                                 ")),
                          OutlinedButton(onPressed: () async {
                            final db = await Db.instance.database;
                            final dbResult = await db.rawQuery("SELECT COUNT(*) FROM note;");
                            final result = dbResult.first.values.first;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("result: ${result}")));
                          }, child: Text("Save")),
                        ],),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
          Expanded(
            child: TrixContainer(
              child: ListView(scrollDirection: Axis.horizontal, children: const [
                Text("Note 1 "),
                Text("Note 2 "),
                Text("Note 3 "),
              ],),
            ),
          )
        ],
      ),
    );
  }
}
