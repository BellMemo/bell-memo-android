import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:shared_preferences/shared_preferences.dart';

import '../memo/memo.dart';
import '../memo/memo_store.dart';
import '../services/cloud_service.dart';

class MemoEditorPage extends StatefulWidget {
  final Memo? memo;

  const MemoEditorPage({super.key, this.memo});

  @override
  State<MemoEditorPage> createState() => _MemoEditorPageState();
}

class _MemoEditorPageState extends State<MemoEditorPage> {
  final MemoStore _store = MemoStore();

  late final TextEditingController _titleCtrl;
  late final quill.QuillController _quillCtrl;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    _titleCtrl = TextEditingController(text: widget.memo?.title ?? '');
    _focusNode = FocusNode();
    _scrollController = ScrollController();

    _quillCtrl = _initQuillController(widget.memo);
  }

  quill.QuillController _initQuillController(Memo? memo) {
    try {
      if (memo != null && memo.content.isNotEmpty) {
        final json = jsonDecode(memo.content);
        if (json is List) {
          return quill.QuillController(
            document: quill.Document.fromJson(json),
            selection: const TextSelection.collapsed(offset: 0),
          );
        }
      }
    } catch (_) {
      // fallthrough to plain text / empty
    }

    if (memo != null && memo.content.isNotEmpty) {
      final doc = quill.Document()..insert(0, memo.content);
      return quill.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
    }

    return quill.QuillController.basic();
  }

  bool get _isDocEmpty => _quillCtrl.document.toPlainText().trim().isEmpty;

  Future<bool> _save({bool popAfterSave = true}) async {
    if (_saving) return false;
    setState(() => _saving = true);

    try {
      final title = _titleCtrl.text.trim();
      final isEmpty = title.isEmpty && _isDocEmpty;
      if (isEmpty) {
        if (popAfterSave && mounted) Navigator.pop(context, false);
        return false;
      }

      final now = DateTime.now();
      final contentJson = jsonEncode(_quillCtrl.document.toDelta().toJson());

      final toSave = (widget.memo == null)
          ? Memo(
              id: now.microsecondsSinceEpoch.toString(),
              title: title.isEmpty ? '无标题' : title,
              content: contentJson,
              createdAt: now,
              updatedAt: now,
            )
          : widget.memo!.copyWith(
              title: title.isEmpty ? '无标题' : title,
              content: contentJson,
              updatedAt: now,
            );

      await _store.upsert(toSave);
      await _syncSavedMemoToCloudIfConfigured(toSave);

      if (popAfterSave && mounted) Navigator.pop(context, true);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _syncSavedMemoToCloudIfConfigured(Memo memo) async {
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

      // 如果未连接则尝试连接一次；连接失败不影响本地保存
      if (!CloudService().isConnected) {
        await CloudService().connect(url, user, pass);
      }

      await CloudService().syncMemoToCloud(memo);
    } catch (_) {
      // 云同步失败不影响本地保存
    }
  }

  Future<bool> _onPop() async {
    // iOS Notes-style: auto-save on back if there's content.
    // If completely empty, just close.
    if ((_titleCtrl.text.trim().isEmpty && _isDocEmpty) || _saving) return true;
    await _save(popAfterSave: false);
    return true;
  }

  void _showFormatPanel() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        return SafeArea(
          child: quill.QuillSimpleToolbar(
            controller: _quillCtrl,
            config: const quill.QuillSimpleToolbarConfig(
              showFontFamily: false,
              showFontSize: false,
              showSubscript: false,
              showSuperscript: false,
              showSearchButton: false,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _quillCtrl.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final allow = await _onPop();
        if (allow && mounted) Navigator.pop(context, false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.memo == null ? '新建备忘录' : '编辑备忘录'),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else
              IconButton(
                tooltip: '保存',
                onPressed: () => _save(),
                icon: const Icon(Icons.check),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  controller: _titleCtrl,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: '标题',
                    border: InputBorder.none,
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _focusNode.requestFocus(),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: quill.QuillEditor(
                  controller: _quillCtrl,
                  focusNode: _focusNode,
                  scrollController: _scrollController,
                  config: const quill.QuillEditorConfig(
                    padding: EdgeInsets.all(16),
                    placeholder: '开始记录...',
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: BottomAppBar(
            height: 56,
            child: Row(
              children: [
                IconButton(
                  tooltip: '格式',
                  onPressed: _showFormatPanel,
                  icon: const Icon(Icons.text_fields),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '隐藏键盘',
                  onPressed: () => FocusScope.of(context).unfocus(),
                  icon: const Icon(Icons.keyboard_hide),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


