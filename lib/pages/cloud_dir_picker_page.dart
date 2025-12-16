import 'package:flutter/material.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

import '../services/cloud_service.dart';

class CloudDirPickerPage extends StatefulWidget {
  final String initialPath;

  const CloudDirPickerPage({super.key, required this.initialPath});

  @override
  State<CloudDirPickerPage> createState() => _CloudDirPickerPageState();
}

class _CloudDirPickerPageState extends State<CloudDirPickerPage> {
  late String _currentPath;
  bool _loading = false;
  String? _error;
  List<webdav.File> _dirs = const [];

  @override
  void initState() {
    super.initState();
    _currentPath = _normalize(widget.initialPath);
    _load();
  }

  String _normalize(String input) {
    final t = input.trim();
    if (t.isEmpty) return '/';
    if (!t.startsWith('/')) return '/$t';
    return t;
  }

  String _parentOf(String path) {
    if (path == '/') return '/';
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return '/';
    return path.substring(0, idx);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await CloudService().listFiles(_currentPath);
      final dirs = items.where((f) => (f.isDir ?? false) == true).toList();
      dirs.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
      if (!mounted) return;
      setState(() => _dirs = dirs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _enter(webdav.File dir) {
    final name = (dir.name ?? '').trim();
    if (name.isEmpty || name == '/') return;
    setState(() {
      _currentPath = _currentPath == '/' ? '/$name' : '$_currentPath/$name';
    });
    _load();
  }

  void _up() {
    if (_currentPath == '/') return;
    setState(() => _currentPath = _parentOf(_currentPath));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isRoot = _currentPath == '/';
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择目录'),
        leading: IconButton(
          tooltip: '退出',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _currentPath),
            child: const Text('确定'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Theme.of(context)
                .colorScheme
                .surfaceVariant
                .withOpacity(0.3),
            child: Row(
              children: [
                IconButton(
                  tooltip: '上级目录',
                  onPressed: isRoot ? null : _up,
                  icon: const Icon(Icons.arrow_upward),
                ),
                Expanded(
                  child: Text(
                    _currentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null)
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off, size: 56),
                              const SizedBox(height: 12),
                              const Text('加载失败'),
                              const SizedBox(height: 8),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : (_dirs.isEmpty)
                        ? const Center(child: Text('空文件夹'))
                        : ListView.builder(
                            itemCount: _dirs.length,
                            itemBuilder: (ctx, i) {
                              final d = _dirs[i];
                              final name = (d.name ?? '').trim();
                              if (name.isEmpty || name == '/') {
                                return const SizedBox.shrink();
                              }
                              return ListTile(
                                leading: const Icon(Icons.folder, color: Colors.amber),
                                title: Text(name),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _enter(d),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}


