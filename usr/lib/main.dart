import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:clipboard/clipboard.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const FlashCardApp());
}

class FlashCardApp extends StatelessWidget {
  const FlashCardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlashCard Pro',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system, // Will be overridden by app state
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String storageKey = 'flashapp_data_v1';
  static const String themeKey = 'flashapp_theme';

  final Map<String, dynamic> defaultStructure = {
    'Bangla': <Map<String, String>>[],
    'English': <Map<String, String>>[],
    'Math': <Map<String, String>>[],
    'Gk': <Map<String, String>>[],
    'Nursing': {
      'General': <Map<String, String>>[],
      'NCLEX': <Map<String, String>>[],
    },
  };

  late Map<String, dynamic> data;
  bool isDarkMode = true;
  String mainView = 'Question Update'; // or 'Exam'
  final List<String> categories = ['Bangla', 'English', 'Math', 'Gk', 'Nursing'];
  final List<String> nursingSubs = ['General', 'NCLEX'];

  // UI selections
  String selectedCategory = 'Bangla';
  String selectedNursingSub = 'General';

  // Editor states
  String qText = '';
  String aText = '';
  int? editingIdx;
  String? editingSub;

  // Exam states
  List<Map<String, String>> examList = [];
  int examIdx = 0;
  bool showAnswer = false;
  bool shuffleOnStart = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final rawData = prefs.getString(storageKey);
    final rawTheme = prefs.getString(themeKey);
    setState(() {
      data = rawData != null ? jsonDecode(rawData) as Map<String, dynamic> : Map.from(defaultStructure);
      isDarkMode = rawTheme == 'dark';
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(data));
    await prefs.setString(themeKey, isDarkMode ? 'dark' : 'light');
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resetExam();
  }

  void _resetExam() {
    setState(() {
      showAnswer = false;
      examIdx = 0;
      examList = [];
    });
  }

  List<Map<String, String>> getCategoryArray(String cat, [String? sub]) {
    if (cat == 'Nursing') {
      return (data['Nursing'] as Map<String, dynamic>)[sub] as List<Map<String, String>>? ?? [];
    }
    return data[cat] as List<Map<String, String>>? ?? [];
  }

  void writeCategoryArray(String cat, List<Map<String, String>> arr, [String? sub]) {
    setState(() {
      if (cat == 'Nursing') {
        (data['Nursing'] as Map<String, dynamic>)[sub!] = arr;
      } else {
        data[cat] = arr;
      }
      _saveData();
    });
  }

  void handleAddOrUpdate() {
    final q = qText.trim();
    final a = aText.trim();
    if (q.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('প্রশ্ন লিখুন')));
      return;
    }
    if (a.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('উত্তর লিখুন')));
      return;
    }

    final arr = getCategoryArray(selectedCategory == 'Nursing' ? 'Nursing' : selectedCategory, selectedCategory == 'Nursing' ? selectedNursingSub : null);
    if (editingIdx != null) {
      arr[editingIdx!] = {'question': q, 'answer': a};
    } else {
      arr.add({'question': q, 'answer': a});
    }
    writeCategoryArray(selectedCategory == 'Nursing' ? 'Nursing' : selectedCategory, arr, selectedCategory == 'Nursing' ? selectedNursingSub : null);

    setState(() {
      qText = '';
      aText = '';
      editingIdx = null;
      editingSub = null;
    });
  }

  void startEdit(int itemIdx) {
    setState(() {
      editingIdx = itemIdx;
      if (selectedCategory == 'Nursing') editingSub = selectedNursingSub;
      final arr = getCategoryArray(selectedCategory == 'Nursing' ? 'Nursing' : selectedCategory, selectedCategory == 'Nursing' ? selectedNursingSub : null);
      final it = arr[itemIdx];
      qText = it['question']!;
      aText = it['answer']!;
    });
  }

  void deleteItem(int idx) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('মুছে ফেলতে চান?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('না')),
          TextButton(
            onPressed: () {
              final arr = getCategoryArray(selectedCategory == 'Nursing' ? 'Nursing' : selectedCategory, selectedCategory == 'Nursing' ? selectedNursingSub : null);
              arr.removeAt(idx);
              writeCategoryArray(selectedCategory == 'Nursing' ? 'Nursing' : selectedCategory, arr, selectedCategory == 'Nursing' ? selectedNursingSub : null);
              Navigator.pop(ctx);
            },
            child: const Text('হ্যাঁ'),
          ),
        ],
      ),
    );
  }

  void prepareExam() {
    final arr = getCategoryArray(selectedCategory == 'Nursing' ? 'Nursing' : selectedCategory, selectedCategory == 'Nursing' ? selectedNursingSub : null);
    if (arr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('এই ক্যাটাগরিতে কোনো প্রশ্ন নেই — আগে Question Update এ গিয়ে যোগ করুন।')));
      return;
    }
    List<Map<String, String>> list = List.from(arr);
    if (shuffleOnStart) {
      list.shuffle(Random());
    }
    setState(() {
      examList = list;
      examIdx = 0;
      showAnswer = false;
      mainView = 'Exam';
    });
  }

  void importJSON(String raw) {
    try {
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final merged = Map<String, dynamic>.from(data);
      for (final key in parsed.keys) {
        if (key == 'Nursing' && parsed[key] is Map) {
          merged['Nursing'] = merged['Nursing'] ?? {'General': <Map<String, String>>[], 'NCLEX': <Map<String, String>>[]};
          for (final sub in (parsed[key] as Map<String, dynamic>).keys) {
            (merged['Nursing'] as Map<String, dynamic>)[sub] = ((merged['Nursing'] as Map<String, dynamic>)[sub] as List<Map<String, String>>? ?? []) + ((parsed[key] as Map<String, dynamic>)[sub] as List<Map<String, String>>? ?? []);
          }
        } else if (parsed[key] is List) {
          merged[key] = (merged[key] as List<Map<String, String>>? ?? []) + (parsed[key] as List<Map<String, String>>);
        }
      }
      setState(() {
        data = merged;
        _saveData();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import সম্পন্ন হয়েছে')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ইমপোর্ট ব্যর্থ: সঠিক JSON নয়')));
    }
  }

  void exportJSON() {
    final jsonStr = jsonEncode(data);
    Share.share(jsonStr, subject: 'FlashCard Export', filename: 'flashapp_export.json');
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: isDarkMode ? ThemeData.dark() : ThemeData.light(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('FlashCard Pro — আপনার প্রশ্নপত্র'),
          actions: [
            ToggleButtons(
              isSelected: [mainView == 'Question Update', mainView == 'Exam'],
              onPressed: (idx) => setState(() => mainView = idx == 0 ? 'Question Update' : 'Exam'),
              children: const [Text('Question Update'), Text('Exam')],
            ),
            IconButton(
              icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => setState(() => isDarkMode = !isDarkMode),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 600;
            return Row(
              children: [
                if (isWide) Expanded(flex: 1, child: _buildSidebar()),
                Expanded(flex: 2, child: _buildMainArea()),
              ],
            );
          },
        ),
        drawer: Drawer(child: _buildSidebar()),
        bottomNavigationBar: const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('Made with ❤️ — FlashCard Pro. Local-only storage. Use Export to backup.', textAlign: TextAlign.center, style: TextStyle(fontSize: 10)),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ক্যাটাগরি', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...categories.map((c) => ElevatedButton(
                onPressed: () => setState(() => selectedCategory = c),
                style: ElevatedButton.styleFrom(backgroundColor: selectedCategory == c ? Colors.blue : null),
                child: Text(c),
              )),
          if (selectedCategory == 'Nursing') ...[
            const SizedBox(height: 16),
            const Text('Nursing Subcategory', style: TextStyle(fontSize: 12)),
            ...nursingSubs.map((s) => ElevatedButton(
                  onPressed: () => setState(() => selectedNursingSub = s),
                  style: ElevatedButton.styleFrom(backgroundColor: selectedNursingSub == s ? Colors.blue : null),
                  child: Text(s),
                )),
          ],
          const SizedBox(height: 16),
          Row(children: [
            const Text('Shuffle on prepare'),
            Checkbox(value: shuffleOnStart, onChanged: (v) => setState(() => shuffleOnStart = v!)),
          ]),
          Text('Selected: $selectedCategory${selectedCategory == 'Nursing' ? ' / $selectedNursingSub' : ''}', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          const Text('Quick Actions', style: TextStyle(fontWeight: FontWeight.bold)),
          ElevatedButton(onPressed: () => setState(() => {qText = ''; aText = ''; editingIdx = null;}), child: const Text('New Question')),
          ElevatedButton(onPressed: prepareExam, child: const Text('Start Exam')),
          ElevatedButton(onPressed: exportJSON, child: const Text('Export All')),
          ElevatedButton(onPressed: () => FlutterClipboard.paste().then((raw) => importJSON(raw)), child: const Text('Import JSON')),
          const SizedBox(height: 16),
          const Text('ব্যবহার নির্দেশ', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('1. প্রথমে ক্যাটাগরি সিলেক্ট করুন।\n2. Question Update এ গিয়ে প্রশ্ন ও উত্তর যোগ করুন।\n3. Exam এ গিয়ে Prepare করুন বা Start চাপুন।\n4. প্রয়োজনে Export/Import করে ব্যাকআপ রাখুন।', style: TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildMainArea() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Text('$mainView - $selectedCategory${selectedCategory == 'Nursing' ? ' / $selectedNursingSub' : ''}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (mainView == 'Question Update') ...[
            _buildEditorPanel(),
            const SizedBox(height: 16),
            _buildListPanel(),
          ] else
            _buildExamPanel(),
        ],
      ),
    );
  }

  Widget _buildEditorPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('প্রশ্ন ও উত্তর যোগ / আপডেট ${editingIdx != null ? '(সম্পাদনা করছে)' : ''}', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(controller: TextEditingController(text: qText)..selection = TextSelection.collapsed(offset: qText.length), onChanged: (v) => qText = v, decoration: const InputDecoration(labelText: 'প্রশ্ন'), maxLines: 3),
            TextField(controller: TextEditingController(text: aText)..selection = TextSelection.collapsed(offset: aText.length), onChanged: (v) => aText = v, decoration: const InputDecoration(labelText: 'উত্তর'), maxLines: 3),
            Row(children: [
              ElevatedButton(onPressed: handleAddOrUpdate, child: Text(editingIdx != null ? 'আপডেট করুন' : 'যোগ করুন')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => setState(() => {qText = ''; aText = ''; editingIdx = null; editingSub = null;}), child: const Text('রিসেট')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: exportJSON, child: const Text('Export JSON')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => FlutterClipboard.paste().then((raw) => importJSON(raw)), child: const Text('Import JSON')),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildListPanel() {
    final arr = getCategoryArray(selectedCategory == 'Nursing' ? 'Nursing' : selectedCategory, selectedCategory == 'Nursing' ? selectedNursingSub : null);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(children: [
              Text('এই ক্যাটাগরির প্রশ্নসমূহ (${arr.length})', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              const Text('Shuffle on Exam start'),
              Checkbox(value: shuffleOnStart, onChanged: (v) => setState(() => shuffleOnStart = v!)),
              OutlinedButton(onPressed: () => showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('সব মুছে ফেলবেন?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('না')), TextButton(onPressed: () => {writeCategoryArray(selectedCategory == 'Nursing' ? 'Nursing' : selectedCategory, [], selectedCategory == 'Nursing' ? selectedNursingSub : null); Navigator.pop(ctx);}, child: const Text('হ্যাঁ'))])), child: const Text('Clear', style: TextStyle(fontSize: 12))),
            ]),
            if (arr.isEmpty) const Text('কোনো প্রশ্ন নেই — উপরে ফরম ভরে যোগ করুন।') else
              ...arr.map((it) => Card(
                    child: ListTile(
                      title: Text('Q: ${it['question']}'),
                      subtitle: Text('A: ${it['answer']!.length > 120 ? '${it['answer']!.substring(0, 120)}...' : it['answer']}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit), onPressed: () => startEdit(arr.indexOf(it))),
                        IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => deleteItem(arr.indexOf(it))),
                      ]),
                    ),
                  )),
            ElevatedButton(onPressed: prepareExam, child: const Text('Exam শুরু করুন')),
          ],
        ),
      ),
    );
  }

  Widget _buildExamPanel() {
    if (examList.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Text('Exam list খালি — আগে Question Update এ গিয়ে প্রশ্ন যোগ করুন অথবা Prepare Exam চাপুন।'),
              ElevatedButton(onPressed: prepareExam, child: const Text('Prepare from current selection')),
            ],
          ),
        ),
      );
    }
    final current = examList[examIdx];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Flashcard ${examIdx + 1} / ${examList.length}'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16.0),
              height: 150,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(current['question']!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (showAnswer) ...[
                    const SizedBox(height: 16),
                    Text('উত্তর: ${current['answer']}'),
                  ],
                ],
              ),
            ),
            Row(children: [
              ElevatedButton(onPressed: () => setState(() => showAnswer = !showAnswer), child: Text(showAnswer ? 'Hide Answer' : 'Show Answer')),
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => {examIdx = max(0, examIdx - 1); showAnswer = false;})),
              IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => setState(() => {examIdx = min(examList.length - 1, examIdx + 1); showAnswer = false;})),
              IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() => {examIdx = 0; showAnswer = false;})),
              IconButton(icon: const Icon(Icons.shuffle), onPressed: () => setState(() => {examList.shuffle(Random()); examIdx = 0; showAnswer = false;})),
            ]),
          ],
        ),
      ),
    );
  }
}
