import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../memo/memo.dart';
import '../memo/memo_store.dart';
import '../services/cloud_service.dart';
import 'memo_editor_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoPage extends StatefulWidget {
  const MemoPage({super.key});

  @override
  State<MemoPage> createState() => MemoPageState();
}

class MemoPageState extends State<MemoPage> {
  final MemoStore _store = MemoStore();

  bool _loading = true;
  List<Memo> _memos = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void createNewMemo() => _openEditor();
  Future<void> reload() => _reload();

  Future<void> _reload() async {
    setState(() => _loading = true);
    final memos = await _store.loadAll();
    if (!mounted) return;
    setState(() {
      _memos = memos;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_memos.isEmpty) {
      return _EmptyState(onCreate: () => _openEditor());
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _memos.length,
        itemBuilder: (context, index) {
          final memo = _memos[index];
          return _MemoCard(
            memo: memo,
            onTap: () => _openEditor(memo: memo),
            onDelete: () => _delete(memo),
          );
        },
      ),
    );
  }

  Future<void> _delete(Memo memo) async {
    await _store.delete(memo.id);
    await _deleteMemoFromCloudIfConfigured(memo.id);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已删除')));
  }

  Future<void> _deleteMemoFromCloudIfConfigured(String memoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('cloud_url');
      final user = prefs.getString('cloud_user');
      final pass = prefs.getString('cloud_pass');
      final root = prefs.getString('cloud_root');

      if (url == null || user == null || pass == null) return;
      if (root != null && root.isNotEmpty) {
        CloudService().setMemoRoot(root);
      }

      if (!CloudService().isConnected) {
        await CloudService().connect(url, user, pass);
      }

      await CloudService().deleteMemoFromCloud(memoId);
    } catch (_) {
      // 云端删除失败不影响本地删除
    }
  }

  Future<void> _openEditor({Memo? memo}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MemoEditorPage(memo: memo),
      ),
    );

    if (saved == true) {
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.note_alt_outlined, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              '还没有备忘录',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              '点击按钮创建第一条',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('新建备忘录'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoCard extends StatelessWidget {
  final Memo memo;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _MemoCard({
    required this.memo,
    required this.onTap,
    required this.onDelete,
  });

  String _getPreviewText() {
    try {
      if (memo.content.startsWith('[') || memo.content.startsWith('{')) {
         final json = jsonDecode(memo.content);
         final doc = quill.Document.fromJson(json);
         return doc.toPlainText().trim();
      }
    } catch (_) {}
    return memo.content;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final preview = _getPreviewText();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      memo.title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: '删除',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  preview,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    _format(memo.updatedAt),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _format(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays == 1) return '昨天';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
