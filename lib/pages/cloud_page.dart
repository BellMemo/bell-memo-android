import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import '../services/cloud_service.dart';
import '../memo/memo_store.dart';
import 'cloud_dir_picker_page.dart';
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

  bool _isOpBusy = false;

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
        // 连接成功后，默认进入网盘根目录 /（而不是备份目录），让用户从顶层浏览
        _currentPath = '/';
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

  Future<void> _pickBackupDirFromCloud() async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先连接网盘后再选择目录')),
      );
      return;
    }
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CloudDirPickerPage(initialPath: _rootController.text),
      ),
    );
    if (selected == null || selected.trim().isEmpty) return;

    final path = selected.trim();
    _rootController.text = path;
    CloudService().setMemoRoot(path);

    // 保存并刷新当前目录
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloud_root', path);
    if (!mounted) return;
    setState(() => _currentPath = path);
    await _loadFiles();
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

  String _joinPath(String dir, String name) {
    if (dir == '/') return '/$name';
    return '${dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir}/$name';
  }

  String _resolveRemotePath(webdav.File file, String name) {
    final fp = (file.path ?? '').trim();
    if (fp.isNotEmpty) return fp;
    return _joinPath(_currentPath, name);
  }

  Future<void> _uploadToCurrentDir() async {
    if (!_isConnected || _isOpBusy) return;
    setState(() => _isOpBusy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      int ok = 0;
      for (final f in result.files) {
        final localPath = f.path;
        final name = f.name;
        if (localPath == null || localPath.isEmpty) continue;
        if (name.isEmpty) continue;

        final remotePath = _joinPath(_currentPath, name);
        await CloudService().uploadFile(localPath, remotePath);
        ok++;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已上传 $ok 个文件到 $_currentPath')),
      );
      await _loadFiles();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _isOpBusy = false);
    }
  }

  Future<void> _downloadFile(webdav.File file) async {
    if (!_isConnected || _isOpBusy) return;
    final name = (file.name ?? '').trim();
    if (name.isEmpty) return;
    if (file.isDir ?? false) return;

    setState(() => _isOpBusy = true);
    try {
      final remotePath = _resolveRemotePath(file, name);
      final dir = await getTemporaryDirectory();
      final localPath = p.join(dir.path, name);
      await CloudService().downloadFile(remotePath, localPath);
      await OpenFilex.open(localPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已下载到: $localPath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _isOpBusy = false);
    }
  }

  Future<void> _deleteRemote(webdav.File file) async {
    if (!_isConnected || _isOpBusy) return;
    final name = (file.name ?? '').trim();
    if (name.isEmpty) return;

    final remotePath = _resolveRemotePath(file, name);
    final isDir = file.isDir ?? false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除${isDir ? '文件夹' : '文件'}：$name ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _isOpBusy = true);
    try {
      await CloudService().deletePath(remotePath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除: $name')),
      );
      await _loadFiles();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _isOpBusy = false);
    }
  }

  Future<void> _createFolderInCurrentDir() async {
    if (!_isConnected || _isOpBusy) return;
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '文件夹名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    setState(() => _isOpBusy = true);
    try {
      final remote = _joinPath(_currentPath, name);
      await CloudService().createDir(remote);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已创建文件夹: $name')),
      );
      // 必须显式 await 刷新，确保新文件夹能刷出来
      await _loadFiles();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _isOpBusy = false);
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

  Future<void> _restoreAllMemosFromCloud({bool silent = false}) async {
    if (!_isConnected) return;
    if (!silent) setState(() => _isLoading = true);

    try {
      final remoteMemos =
          await CloudService().fetchMemosFromCloud(root: CloudService().memoRoot);
      final local = await MemoStore().loadAll();
      final localById = {for (final m in local) m.id: m};

      int created = 0;
      int updated = 0;
      int skipped = 0;

      for (final r in remoteMemos) {
        final l = localById[r.id];
        if (l == null) {
          await MemoStore().upsert(r);
          created++;
          continue;
        }
        if (r.updatedAt.isAfter(l.updatedAt)) {
          await MemoStore().upsert(r);
          updated++;
        } else {
          skipped++;
        }
      }

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '云端发现 ${remoteMemos.length} 条，导入完成：新增 $created，更新 $updated，跳过 $skipped（返回备忘录页可下拉刷新）',
            ),
          ),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拉取失败: $e')),
        );
      }
    } finally {
      if (!silent && mounted) setState(() => _isLoading = false);
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
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _pickBackupDirFromCloud,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('浏览选择备份目录（可退出）'),
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
                leading: const Icon(Icons.download, color: Colors.blue),
                title: const Text('从云端拉取历史备忘录',
                    style: TextStyle(color: Colors.blue)),
                subtitle: const Text('从备份目录读取 .md 并导入本地（若云端更新更晚则覆盖本地）'),
                onTap: () {
                  Navigator.pop(context);
                  _restoreAllMemosFromCloud();
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
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: '上级目录',
                              onPressed: isRoot ? null : _navigateUp,
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              tooltip: '回到备份目录',
                              onPressed: () {
                                setState(() => _currentPath = CloudService().memoRoot);
                                _loadFiles();
                              },
                              icon: const Icon(Icons.home_outlined),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '路径: $_currentPath',
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
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
                                    trailing: PopupMenuButton<String>(
                                      tooltip: '更多',
                                      onSelected: (v) {
                                        if (v == 'download') _downloadFile(file);
                                        if (v == 'delete') _deleteRemote(file);
                                      },
                                      itemBuilder: (ctx) => [
                                        if (!isDir)
                                          const PopupMenuItem(
                                            value: 'download',
                                            child: ListTile(
                                              leading: Icon(Icons.download),
                                              title: Text('下载'),
                                            ),
                                          ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: ListTile(
                                            leading: Icon(Icons.delete_outline),
                                            title: Text('删除'),
                                          ),
                                        ),
                                      ],
                                      child: isDir
                                          ? const Icon(Icons.chevron_right)
                                          : const Icon(Icons.more_vert),
                                    ),
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
                      // 通用网盘操作栏：任何目录（包括 /BellMemo）都可以上传/新建文件夹
                      SafeArea(
                        top: false,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border(
                              top: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withOpacity(0.5),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: (_isLoading || _isOpBusy)
                                      ? null
                                      : _uploadToCurrentDir,
                                  icon: const Icon(Icons.upload),
                                  label: const Text('上传'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: (_isLoading || _isOpBusy)
                                      ? null
                                      : _createFolderInCurrentDir,
                                  icon: const Icon(Icons.create_new_folder_outlined),
                                  label: const Text('新建文件夹'),
                                ),
                              ),
                            ],
                          ),
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
