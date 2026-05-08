import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await [Permission.storage].request();
  runApp(MoelyApp());
}

class MoelyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moely AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  Interpreter? _interpreter;
  Map<String, dynamic> _vocab = {};
  Map<String, String> _food = {};
  bool _loading = true;
  final TextEditingController _ctrl = TextEditingController();
  final List<Map<String, String>> _messages = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dir = Directory('/storage/emulated/0/Moely');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        setState(() {
          _loading = false;
          _messages.add({'bot': '📁 Folder Moely sudah dibuat. Masukkan model.tflite, vocab.json, dan makanan.json ke folder itu.'});
        });
        return;
      }
      final modelFile = File('${dir.path}/model.tflite');
      final vocabFile = File('${dir.path}/vocab.json');
      final foodFile = File('${dir.path}/makanan.json');
      if (!await modelFile.exists() || !await vocabFile.exists()) {
        setState(() {
          _loading = false;
          _messages.add({'bot': '❌ File model atau vocab tidak ditemukan. Letakkan kedua file di folder Moely.'});
        });
        return;
      }
      _interpreter = await Interpreter.fromFile(modelFile);
      String vJson = await vocabFile.readAsString();
      _vocab = json.decode(vJson);
      if (await foodFile.exists()) {
        String fJson = await foodFile.readAsString();
        _food = Map<String,String>.from(json.decode(fJson));
      }
      setState(() {
        _loading = false;
        _messages.add({'bot': '✅ Moely siap! Tanya tentang makanan.'});
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _messages.add({'bot': '⚠️ Error: $e'});
      });
    }
  }

  String _generate(String prompt) {
    if (_interpreter == null) return "Model error";
    final char2idx = Map<String,int>.from(_vocab['char2idx'] ?? {});
    final idx2char = List<String>.from(_vocab['idx2char'] ?? []);
    final vocabSize = _vocab['vocab_size'] ?? 0;
    final seqLen = _vocab['seq_length'] ?? 5;
    if (char2idx.isEmpty) return "Vocab error";
    String lastChars = prompt.length >= seqLen ? prompt.substring(prompt.length - seqLen) : prompt.padLeft(seqLen, ' ');
    List<int> ids = lastChars.split('').map((c) => char2idx[c] ?? 0).toList();
    List<double> input = List.filled(seqLen * vocabSize, 0.0);
    for (int i=0; i<seqLen; i++) input[i*vocabSize + ids[i]] = 1.0;
    var output = List.filled(vocabSize, 0.0);
    _interpreter!.run(input, output);
    int nextIdx = 0;
    double maxVal = -1e9;
    for (int i=0; i<output.length; i++) {
      if (output[i] > maxVal) { maxVal = output[i]; nextIdx = i; }
    }
    if (nextIdx >= idx2char.length) return "?";
    return idx2char[nextIdx];
  }

  void _send() async {
    String q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _messages.add({'user': q});
      _ctrl.clear();
    });
    String? ans;
    for (var entry in _food.entries) {
      if (q.toLowerCase().contains(entry.key.toLowerCase())) {
        ans = entry.value;
        break;
      }
    }
    if (ans == null) {
      String result = "";
      String context = q;
      for (int i=0; i<40; i++) {
        String next = _generate(context);
        if (next == "\n" || next == "" || next == "?") break;
        result += next;
        context = (context + next).length > 60 ? (context + next).substring((context+next).length-60) : context+next;
      }
      ans = result.trim().isEmpty ? "Maaf kurang paham." : result;
    }
    setState(() => _messages.add({'bot': ans!}));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Moely AI'), backgroundColor: Colors.black),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(child: ListView.builder(
                padding: EdgeInsets.all(8),
                itemCount: _messages.length,
                itemBuilder: (ctx, i) {
                  bool isUser = _messages[i].containsKey('user');
                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isUser ? Colors.blueAccent : Colors.grey[800],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_messages[i][isUser ? 'user' : 'bot']!),
                    ),
                  );
                },
              )),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(30)),
                margin: EdgeInsets.all(8),
                child: Row(children: [
                  Expanded(child: TextField(controller: _ctrl, style: TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Ketik...', border: InputBorder.none), onSubmitted: (_) => _send())),
                  IconButton(icon: Icon(Icons.send, color: Colors.cyanAccent), onPressed: _send),
                ]),
              )
            ]),
    );
  }
}
