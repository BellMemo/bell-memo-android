import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'memo.dart';

class MemoStore {
  static const _key = 'memos';

  Future<List<Memo>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];

    final memos = raw
        .map((s) => jsonDecode(s) as Map<String, dynamic>)
        .map(Memo.fromJson)
        .toList();

    memos.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return memos;
  }

  Future<void> upsert(Memo memo) async {
    final prefs = await SharedPreferences.getInstance();
    final memos = await loadAll();

    final idx = memos.indexWhere((m) => m.id == memo.id);
    if (idx >= 0) {
      memos[idx] = memo;
    } else {
      memos.add(memo);
    }

    await _saveAll(prefs, memos);
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final memos = await loadAll();
    memos.removeWhere((m) => m.id == id);
    await _saveAll(prefs, memos);
  }

  Future<void> _saveAll(SharedPreferences prefs, List<Memo> memos) async {
    final raw = memos.map((m) => jsonEncode(m.toJson())).toList();
    await prefs.setStringList(_key, raw);
  }
}
