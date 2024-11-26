// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:native_context_menu/native_context_menu.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' show basename;
import 'package:window_manager/window_manager.dart';
import 'package:tommynotes/db.dart';
import 'package:tommynotes/note.dart';
import 'package:tommynotes/settings.dart';
import 'package:tommynotes/trixcontainer.dart';
import 'package:tommynotes/trixicontext.dart';

const String _settingsRecentFilesKey = "RECENT_FILES";
const String _settingsNextHintKey = "HINT_NUMBER"; // zero-based, 0 = should show 0, etc.
const String _deleteKey = "Delete";
const List<String> _hints = [
  "This is Tommynotes, free cross-platform open-source app for taking virtual notes.\n"
  "Note that it's not a usual note-taking app with folders and subfolders which is often hard to organize.\n"
  "It's a (potentially) infinite feed of small events searchable by tag or keywords.\n\n"
  "RECOMMENDED usage:\nadd -> add -> add -> search\n\n"
  "Not recommended usage:\nadd -> find-existing-note -> edit\n\n"
  ,
];
final bool _isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

void main() async {
  // bug in Sqflite:
  // https://stackoverflow.com/questions/76158800  // add FFI support for Windows/Linux
  // https://stackoverflow.com/questions/75837229  // add sqlite.dll to Windows release manually
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  WidgetsFlutterBinding.ensureInitialized(); // allow async code in main()
  await Settings.instance.init(); // TODO check how long it takes
  if (_isDesktop) await windowManager.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Tommynotes",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const Main(),
    );
  }
}

class Main extends StatefulWidget {
  const Main({super.key});

  @override
  State<Main> createState() => _MainState();
}

class _MainState extends State<Main> {
  final _miniConfig = MarkdownConfig(configs: [                      // config to render small notes at the bottom
    const HrConfig(height: 0.2),
    const H1Config(style: TextStyle(fontSize: 12)),
    const H2Config(style: TextStyle(fontSize: 11)),
    const H3Config(style: TextStyle(fontSize: 10)),
    const H4Config(style: TextStyle(fontSize: 9)),
    const H5Config(style: TextStyle(fontSize: 8)),
    const H6Config(style: TextStyle(fontSize: 7)),
    const PreConfig(textStyle: TextStyle(fontSize: 10)),
    const PConfig(textStyle: TextStyle(fontSize: 10)),
    const CodeConfig(style: TextStyle(fontSize: 10)),
    const BlockquoteConfig(margin: EdgeInsets.all(2), padding: EdgeInsets.all(2)),
  ]);
  final TextEditingController _mainCtrl = TextEditingController();   // main text in "Edit" mode
  final TextEditingController _tagsCtrl = TextEditingController();   // comma-separated text in tags textbox
  final TextEditingController _searchCtrl = TextEditingController(); // global search query in "Search" textbox
  String? _path;                                                     // current path to DB file
  int _noteId = 0;                                                   // ID of the note to edit (0 = new note)
  String _oldTags = "";                                              // copy of "_tagsCtrl" to find the diff on update
  String? _searchBy;                                                 // null = no search (default), "" = search by keyword, "x" = search by tag 'x'

  @override
  void initState() {
    super.initState();
    // if (_isDesktop) windowManager.setFullScreen(true); // TODO: full window, not full-screen
    _showHint();
  }

  @override
  Widget build(BuildContext context) {
    return _isDesktop ? _buildForDesktop(context) : _buildForMobile(context);
  }

  Widget _buildForMobile(BuildContext context) {
    return Scaffold(
      body: !Db.instance.isConnected() ? const Center(child: Text("Welcome!\nOpen a DB file")) : FutureBuilder(
        future: Db.instance.getNotes(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final children = snapshot.data!.map((note) => TrixContainer(child: MarkdownWidget(
              data: note.note, // this may print: "get language error:Null check operator used on a null value", it's not our bad
              shrinkWrap: true
            ))).toList();
            return ListView(children: children); // TODO use ListView.builder for better performance
          } else return const CircularProgressIndicator();
        },
      ),
      floatingActionButton: FloatingActionButton.small(onPressed: _openDbFileWithDialog, child: const Icon(Icons.file_open)),
    );
  }

  Widget _buildForDesktop(BuildContext context) {
    if (_isDesktop) windowManager.setTitle(_path != null ? basename(_path!) : "Tommynotes");

    final recentFilesMenus = Settings.instance.settings.getStringList(_settingsRecentFilesKey)?.map((path) =>
      PlatformMenuItem(label: path, onSelected: () => _openDbFile(path))
    ).toList() ?? [];

    return PlatformMenuBar(
      menus: [ // TODO: create menu for Windows/Linux
        PlatformMenu(
          label: "",
          menus: [
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(label: "About Tommynotes", onSelected: _showAboutDialog),
            ]),
            PlatformMenuItem(label: "Quit", onSelected: () => exit(0)),
          ],
        ),
        PlatformMenu(
          label: "File",
          menus: [
            PlatformMenu(label: "Open Recent", menus: recentFilesMenus),
            PlatformMenuItemGroup(members: [
              PlatformMenuItem(label: "New File", onSelected: _newDbFile),
              PlatformMenuItem(label: "Open...", onSelected: _openDbFileWithDialog),
            ]),
            PlatformMenuItem(label: "Close File", onSelected: _closeDbFile),
          ],
        ),
      ],
      child: Shortcuts(
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.f1)                                                : AboutIntent(),
          SingleActivator(LogicalKeyboardKey.keyN, meta: Platform.isMacOS, control: !Platform.isMacOS): NewDbFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyO, meta: Platform.isMacOS, control: !Platform.isMacOS): OpenDbFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyS, meta: Platform.isMacOS, control: !Platform.isMacOS): SaveNoteIntent(),
          SingleActivator(LogicalKeyboardKey.keyW, meta: Platform.isMacOS, control: !Platform.isMacOS): CloseDbFileIntent(),
          SingleActivator(LogicalKeyboardKey.keyQ, meta: Platform.isMacOS, control: !Platform.isMacOS): CloseAppIntent(),
        },
        child: Actions(
          actions: {
            AboutIntent:       CallbackAction(onInvoke: (_) => _showAboutDialog()),
            NewDbFileIntent:   CallbackAction(onInvoke: (_) => _newDbFile()),
            OpenDbFileIntent:  CallbackAction(onInvoke: (_) => _openDbFileWithDialog()),
            SaveNoteIntent:    CallbackAction(onInvoke: (_) => _saveNote()),
            CloseDbFileIntent: CallbackAction(onInvoke: (_) => _closeDbFile()),
            CloseAppIntent:    CallbackAction(onInvoke: (_) => exit(0)),
          },
          child: Focus(               // needed for Shortcuts TODO RTFM about FocusNode
            autofocus: true,          // focused by default
            child: Scaffold(
              body: !Db.instance.isConnected() ? const Center(child: Text("Welcome!\nOpen or create a new DB file")) : Column(
                children: [
                  Flexible(
                    flex: 8,
                    child: Row(children: [ // [left: tags, right: main window]
                      Expanded( // tags
                        child: TrixContainer(
                          child: FutureBuilder(
                            future: Db.instance.getTags(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                final tags = snapshot.data!.map((tag) => Padding(
                                  padding: const EdgeInsets.only(top: 2), // Tag button on the left side
                                  child: OutlinedButton(
                                    child: Text(tag),
                                    onPressed: () => _setState(noteId: 0, oldTags: "", path: _path, searchBy: tag, mainCtrl: "", tagsCtrl: "", searchCtrl: "")
                                  ),
                                )).toList();
                                return ListView(children: [
                                  Row(children: [
                                    TrixIconTextButton.icon(
                                      icon: const Icon(Icons.add_box_rounded),
                                      label: const Text("New"),
                                      onPressed: () => _setState(noteId: 0, oldTags: "", path: _path, searchBy: null, mainCtrl: "", tagsCtrl: "", searchCtrl: ""),
                                    ),
                                    Expanded(child: TextFormField(
                                      controller: _searchCtrl,
                                      decoration: const InputDecoration(label: Text("Search"), border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)))),
                                      onEditingComplete: () => _setState(noteId: 0, oldTags: "", path: _path, searchBy: "", mainCtrl: "", tagsCtrl: "", searchCtrl: _searchCtrl.text)
                                    )),
                                  ]),
                                  const Text("Tags", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                  ...tags,
                                ]);
                              } else return const CircularProgressIndicator();
                            },
                          ),
                        ),
                      ),
                      Flexible( // main window
                        flex: 6,
                        child: Column(children: [ // [top: edit/render panels, bottom: edit-tags/buttons panels]
                          Expanded(child: _searchBy == null
                            ? Row(children: [ // [left: edit panel, right: render panel]
                                Expanded(child: TrixContainer(child: TextField(controller: _mainCtrl, maxLines: 1024, onChanged: (s) => setState(() {})))),
                                Expanded(child: TrixContainer(child: MarkdownWidget(data: _mainCtrl.text))),
                              ])
                            : TrixContainer(child: FutureBuilder(
                                future: _search(),
                                builder: (context, snapshot) => snapshot.data ?? const CircularProgressIndicator(),
                              )),
                          ),
                          Visibility(
                            visible: _searchBy == null,
                            child: TrixContainer(child: Row(children: [
                              // TODO: TextFormField can process ENTER key
                              SizedBox(
                                width: 300,
                                child: TextFormField(
                                  controller: _tagsCtrl,
                                  decoration: const InputDecoration(label: Text("Tags"), border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)))),
                                  onEditingComplete: _saveNote,
                                )
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton(onPressed: _saveNote, child: Text(_noteId == 0 ? "Save" : "Update")),
                            ])),
                          )],
                        ),
                      )],
                    ),
                  ),
                  Expanded(
                    child: TrixContainer(child: FutureBuilder(
                      future: Db.instance.getNotes(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          final children = snapshot.data!.map((note) =>
                            ContextMenuRegion(
                              menuItems: [MenuItem(title: _deleteKey)],
                              onItemSelected: (item) async {
                                if (item.title == _deleteKey) {
                                  await Db.instance.deleteNote(note.noteId);
                                  setState(() {}); // refresh
                                }
                              },
                              child: TrixContainer(child: TextButton( // button with a mini-note on the bottom
                                child: SizedBox(width: 200, child: MarkdownWidget(data: _miniNote(note.note), shrinkWrap: true, selectable: false, config: _miniConfig)),
                                onPressed: () => _setState(noteId: note.noteId, oldTags: note.tags, path: _path, searchBy: null, mainCtrl: note.note, tagsCtrl: note.tags, searchCtrl: ""),
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
          ),
        ),
      ),
    );
  }

  void _setState({required int noteId, required String oldTags, required String? path, required String? searchBy, required String mainCtrl, required String tagsCtrl, required String searchCtrl}) {
    setState(() { // list all state variables here!
      _mainCtrl.text = mainCtrl;
      _tagsCtrl.text = tagsCtrl;
      _searchCtrl.text = searchCtrl;
      _path = path;
      _noteId = noteId;
      _oldTags = oldTags;
      _searchBy = searchBy;
    });
  }

  void _saveNote() async {
    if (!Db.instance.isConnected()) return; // user may click ⌘+S on a closed DB file

    final data = _mainCtrl.text;
    final tags = _tagsCtrl.text.split(",").map((tag) => tag.trim()).where((tag) => tag.isNotEmpty);
    if (tags.isEmpty) {
      FlutterPlatformAlert.showAlert(windowTitle: "Tag required", text: 'Please add at least 1 tag,\ne.g. "Work", "New" or "TODO"', iconStyle: IconStyle.warning);
      return;
    }
    if (data.trim().isNotEmpty) {
      if (_noteId == 0) { // INSERT
        final newNoteId = await Db.instance.insertNote(data);
        await Db.instance.linkTagsToNote(newNoteId, tags);
        await FlutterPlatformAlert.showAlert(windowTitle: "Success", text: "New note added", iconStyle: IconStyle.information);
        _setState(noteId: newNoteId, oldTags: _oldTags, path: _path, searchBy: null, mainCtrl: _mainCtrl.text, tagsCtrl: _tagsCtrl.text, searchCtrl: "");
      } else {            // UPDATE
        await Db.instance.updateNote(_noteId, data);
        await _updateTags();
        await FlutterPlatformAlert.showAlert(windowTitle: "Success", text: "Updated", iconStyle: IconStyle.hand);
        _setState(noteId: _noteId, oldTags: _tagsCtrl.text, path: _path, searchBy: null, mainCtrl: _mainCtrl.text, tagsCtrl: _tagsCtrl.text, searchCtrl: "");
      }
    }
  }

  void _deleteNote(int noteId) async {
    const title = "Attention!";
    const text = "Do you want to delete this note?";
    final AlertButton result = await FlutterPlatformAlert.showAlert(windowTitle: title, text: text, alertStyle: AlertButtonStyle.yesNoCancel, iconStyle: IconStyle.stop);
    if (result == AlertButton.yesButton) {
      await Db.instance.deleteNote(noteId);
      setState(() {}); // refresh
    }
  }

  void _newDbFile() async {
    final path = await FilePicker.platform.saveFile(dialogTitle: "Create a new DB file", fileName: "workspace.db", allowedExtensions: ["db"], lockParentWindow: true);
    if (path != null) {
      await Db.instance.createDb(path);
      _addRecentFile(path);
      _setState(noteId: 0, oldTags: "", path: path, searchBy: null, mainCtrl: "", tagsCtrl: "", searchCtrl: "");
    }
  }

  void _openDbFile(String path) async {
    if (File(path).existsSync()) {
      await Db.instance.openDb(path);
      _addRecentFile(path);
      _setState(noteId: 0, oldTags: "", path: path, searchBy: null, mainCtrl: "", tagsCtrl: "", searchCtrl: "");
    } else {
      FlutterPlatformAlert.showAlert(windowTitle: "Error", text: 'File not found:\n$path', iconStyle: IconStyle.error);
      _removeFromRecentFiles(path);
      setState(() {}); // update menu
    }
  }

  void _openDbFileWithDialog() async {
    final FilePickerResult? res = _isDesktop
        ? await FilePicker.platform.pickFiles(dialogTitle: "Open a DB file", type: FileType.custom, allowedExtensions: ["db"], lockParentWindow: true)
        : await FilePicker.platform.pickFiles(dialogTitle: "Open a DB file", type: FileType.any);
    final path = res?.files.single.path;
    if (path != null)
      _openDbFile(path);
  }

  void _closeDbFile() async {
    await Db.instance.closeDb();
    _setState(noteId: 0, oldTags: "", path: null, searchBy: null, mainCtrl: "", tagsCtrl: "", searchCtrl: "");
  }
  
  void _showAboutDialog() async {
    final info = await PackageInfo.fromPlatform();
    final text = "v${info.version} (build: ${info.buildNumber})\n\n© Artem Mitrakov. All rights reserved\nmitrakov-artem@yandex.ru";
    FlutterPlatformAlert.showAlert(windowTitle: info.appName, text: text, iconStyle: IconStyle.information);
  }

  void _addRecentFile(String path) {
    final settings = Settings.instance.settings;
    final list = settings.getStringList(_settingsRecentFilesKey) ?? [];
    if (list.firstOrNull == path) return; // no changes needed
    if (list.contains(path))              // remove possible duplicates
      list.remove(path);
    list.insert(0, path);                 // prepend to the list
    settings.setStringList(_settingsRecentFilesKey, list);
  }

  void _removeFromRecentFiles(String path) {
    final settings = Settings.instance.settings;
    final list = settings.getStringList(_settingsRecentFilesKey) ?? [];
    list.remove(path);
    settings.setStringList(_settingsRecentFilesKey, list);
  }

  Future<Widget> _search() async {
    late Iterable<Note> rows;
    switch (_searchBy) {
      case null: rows = [];
      case "":   rows = await Db.instance.searchByKeyword(_searchCtrl.text);
      default:   rows = await Db.instance.searchByTag(_searchBy!);
    }

    final children = rows.map((note) => TrixContainer(child: Stack(
      alignment: Alignment.topRight,
      children: [
        MarkdownWidget(data: note.note, shrinkWrap: true),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TrixContainer(child: Text( "🔖 ${note.tags}")),
            const SizedBox(width: 8),
            FloatingActionButton(
              tooltip: "Edit",
              mini: true,
              backgroundColor: Colors.blue[50],
              onPressed: () => _setState(noteId: note.noteId, oldTags: note.tags, path: _path, searchBy: null, mainCtrl: note.note, tagsCtrl: note.tags, searchCtrl: ""),
              child: const Icon(Icons.edit),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              tooltip: "Delete",
              mini: true,
              backgroundColor: Colors.red[200],
              onPressed: () => _deleteNote(note.noteId),
              child: const Icon(Icons.remove_circle_outline_rounded),
            ),
          ],
        ),
      ]
    ))).toList();
    return ListView(children: children);
  }

  Future<void> _updateTags() async {
    final oldTags = _oldTags      .split(",").map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toSet();
    final newTags = _tagsCtrl.text.split(",").map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toSet();
    final rmTags  = oldTags.difference(newTags);
    final addTags = newTags.difference(oldTags);

    await Db.instance.unlinkTagsFromNote(_noteId, rmTags);
    await Db.instance.linkTagsToNote(_noteId, addTags);
  }

  void _showHint() {
    final settings = Settings.instance.settings;
    final currentHint = settings.getInt(_settingsNextHintKey) ?? 0;
    if (currentHint < _hints.length) {
      FlutterPlatformAlert.showAlert(windowTitle: "Tommynotes", text: _hints[currentHint], iconStyle: IconStyle.information);
      settings.setInt(_settingsNextHintKey, currentHint+1);
    }
  }

  String _miniNote(String note) => note.split("\n").take(4).map((s) => s.substring(0, min(28, s.length))).join("\n");
}

class AboutIntent       extends Intent {}
class NewDbFileIntent   extends Intent {}
class OpenDbFileIntent  extends Intent {}
class SaveNoteIntent    extends Intent {}
class CloseDbFileIntent extends Intent {}
class CloseAppIntent    extends Intent {}
