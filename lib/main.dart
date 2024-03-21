import 'package:flutter/material.dart';
import 'package:markdown_widget/widget/markdown.dart';
import 'package:tommynotes/trixcontainer.dart';

void main() {
  runApp(const MyApp());
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
                          OutlinedButton(onPressed: () {}, child: Text("Save")),
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
