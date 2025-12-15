import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import '../services/cloud_service.dart';
import '../memo/memo_store.dart';
import 'cloud_md_viewer.dart';

class CloudPage extends StatefulWidget {
  const CloudPage({super.key});

  @override
  State<CloudPage> createState() => CloudPageState();
}

class CloudPageState extends State<CloudPage> {
  bool _isConnected = false;
  bool _isLoading = false;
  String _currentPath = '/';
  List<webdav.File> _files = [];
  String? _error;

  final TextEditingController _urlController = TextEditingController(text: 'http://');
  final TextEditingController _userController = TextEditingController(text: 'admin');
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _rootController =
      TextEditingController(text: '/BellMemo');

  /// 供外部（HomeShell）调用：打开设置面板
  void openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => _buildSettingsSheet(ctx),
    );
  }

  /// 供外部（HomeShell）调用：刷新列表
  Future<void> refresh() async {
    if (!_isConnected) return;
    await _loadFiles();
  }

  @override
  void initState() {
    super.initState();
    _checkSavedConnection();
  }

  Future<void> _checkSavedConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('cloud_url');
    final user = prefs.getString('cloud_user');
    final pass = prefs.getString('cloud_pass');
    final root = prefs.getString('cloud_root');

    if (url != null && user != null && pass != null) {
      _urlController.text = url;
      _userController.text = user;
      _passController.text = pass;
      if (root != null && root.isNotEmpty) {
        _rootController.text = root;
        CloudService().setMemoRoot(root);
      }
      _connect(url, user, pass);
    }
  }

  Future<void> _connect(String url, String user, String pass) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      CloudService().setMemoRoot(_rootController.text);
      await CloudService().connect(url, user, pass);
      final effectiveUrl = CloudService().effectiveUrl ?? url;
      final effectiveRoot = CloudService().memoRoot;
      
      // 保存凭据
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cloud_url', effectiveUrl);
      await prefs.setString('cloud_user', user);
      await prefs.setString('cloud_pass', pass);
      await prefs.setString('cloud_root', _rootController.text.trim());

      setState(() {
        _isConnected = true;
        // 默认打开备份目录（更符合使用预期，也避免 WebDAV 根目录为空导致“黑屏感”）
        _currentPath = effectiveRoot;
      });
      // 如果自动补全了 /dav，顺便更新输入框
      _urlController.text = effectiveUrl;
      _rootController.text = effectiveRoot;
      // 注意：CloudPage 可能被嵌入在外层 Scaffold（HomeShell）里。
      // 这里不要用 hasDrawer 来 pop，否则可能误 pop 掉路由，表现为“黑屏”。
      if (mounted && (Scaffold.maybeOf(context)?.isDrawerOpen ?? false)) {
        Navigator.pop(context);
      }
      
      await _loadFiles();
      
      // 连接成功后，触发一次自动备份
      _syncAllMemos(silent: true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isConnected = false;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final files = await CloudService().listFiles(_currentPath);
      debugPrint('Cloud listFiles($_currentPath) => ${files.length} items');
      if (files.isNotEmpty) {
        final preview = files.take(8).map((f) {
          final n = f.name ?? '';
          final p = f.path ?? '';
          final d = f.isDir ?? false;
          return '$n(dir=$d,path=$p)';
        }).join(', ');
        debugPrint('Cloud items: $preview');
      }
      // 排序：文件夹在前，文件在后
      files.sort((a, b) {
        if ((a.isDir ?? false) == (b.isDir ?? false)) {
          return (a.name ?? '').compareTo(b.name ?? '');
        }
        return (a.isDir ?? false) ? -1 : 1;
      });
      
      if (mounted) {
        setState(() {
          _files = files;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _syncAllMemos({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    
    try {
      final memos = await MemoStore().loadAll();
      int successCount = 0;
      for (final memo in memos) {
        await CloudService().syncMemoToCloud(memo);
        successCount++;
      }
      
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份完成: $successCount 个备忘录')),
        );
      }
      
      // 刷新文件列表
      _loadFiles();
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败: $e')),
        );
      }
    } finally {
      if (!silent && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToFolder(String folderName) {
    setState(() {
      if (_currentPath == '/') {
        _currentPath = '/$folderName';
      } else {
        _currentPath = '$_currentPath/$folderName';
      }
    });
    _loadFiles();
  }

  void _navigateUp() {
    if (_currentPath == '/') return;
    final parent = _currentPath.substring(0, _currentPath.lastIndexOf('/'));
    setState(() {
      _currentPath = parent.isEmpty ? '/' : parent;
    });
    _loadFiles();
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cloud_url');
    await prefs.remove('cloud_user');
    await prefs.remove('cloud_pass');
    await prefs.remove('cloud_root');
    CloudService().disconnect();
    
    // 如果是在 Drawer 里点击退出，先关闭 Drawer
    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }

    setState(() {
      _isConnected = false;
      _files = [];
      _currentPath = '/';
      _urlController.text = 'http://';
      _userController.text = 'admin';
      _passController.clear();
      _rootController.text = '/BellMemo';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConnected) {
      return _buildLoginForm(context);
    }
    return _buildFileBrowserBody(context);
  }

  Widget _buildSettingsSheet(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '服务端设置',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('连接配置', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'http://192.168.1.x:5244/dav',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rootController,
                decoration: const InputDecoration(
                  labelText: '备份目录（云端路径）',
                  hintText: '/BellMemo 或 /local/BellMemo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () {
                          _connect(
                            _urlController.text,
                            _userController.text,
                            _passController.text,
                          );
                          Navigator.pop(context);
                        },
                  icon: const Icon(Icons.save),
                  label: const Text('保存并重连'),
                ),
              ),
              const Divider(height: 48),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.backup, color: Colors.green),
                title: const Text('立即备份所有备忘录',
                    style: TextStyle(color: Colors.green)),
                onTap: () {
                  Navigator.pop(context);
                  _syncAllMemos();
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('断开连接', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _logout();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_sync, size: 64, color: Colors.blue),
                const SizedBox(height: 16),
                const Text('连接 Bell Cloud', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: '服务器地址 (WebDAV)',
                    hintText: 'http://192.168.1.x:5244/dav',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _userController,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _rootController,
                  decoration: const InputDecoration(
                    labelText: '备份目录（云端路径）',
                    hintText: '/local/BellMemo（推荐）',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.folder),
                  ),
                ),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _isLoading
                        ? null
                        : () => _connect(
                              _urlController.text,
                              _userController.text,
                              _passController.text,
                            ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('连接'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileBrowserBody(BuildContext context) {
    final bool isRoot = _currentPath == '/';
    return WillPopScope(
      onWillPop: () async {
        if (!isRoot) {
          _navigateUp();
          return false;
        }
        return true;
      },
      child: _isLoading
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
                          Text(
                            '加载失败',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _loadFiles,
                            icon: const Icon(Icons.refresh),
                            label: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      // 路径面包屑
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceVariant
                            .withOpacity(0.3),
                        child: Text(
                          '路径: $_currentPath',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: _files.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.folder_open,
                                        size: 64, color: Colors.grey[300]),
                                    const SizedBox(height: 16),
                                    const Text('空文件夹'),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _files.length,
                                itemBuilder: (context, index) {
                                  final file = _files[index];
                                  final isDir = file.isDir ?? false;
                                  final name = file.name ?? '';
                                  final isMd =
                                      name.toLowerCase().endsWith('.md');

                                  return ListTile(
                                    leading: Icon(
                                      isDir
                                          ? Icons.folder
                                          : isMd
                                              ? Icons.description
                                              : Icons.insert_drive_file,
                                      color: isDir
                                          ? Colors.amber
                                          : (isMd ? Colors.blue : Colors.grey),
                                    ),
                                    title: Text(name.isEmpty ? '未命名' : name),
                                    subtitle: isDir
                                        ? null
                                        : Text(_formatSize(file.size ?? 0)),
                                    trailing: isDir
                                        ? const Icon(Icons.chevron_right)
                                        : null,
                                    onTap: name.isEmpty
                                        ? null
                                        : () {
                                            if (isDir) {
                                              _navigateToFolder(name);
                                            } else if (isMd) {
                                              final filePath = _currentPath == '/'
                                                  ? '/$name'
                                                  : '$_currentPath/$name';
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      CloudMdViewer(
                                                    filePath: filePath,
                                                    fileName: name,
                                                  ),
                                                ),
                                              );
                                            } else {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        '暂只支持预览 Markdown 文件')),
                                              );
                                            }
                                          },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
