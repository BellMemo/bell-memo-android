import 'package:flutter/material.dart';

import 'cloud_page.dart';
import 'memo_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _cloudVisited = false;

  final _memoPageKey = GlobalKey<MemoPageState>();
  final _cloudPageKey = GlobalKey<CloudPageState>();

  List<Widget> get _pages => [
        MemoPage(key: _memoPageKey),
        _cloudVisited ? CloudPage(key: _cloudPageKey) : const SizedBox.shrink(),
      ];

  String get _title => switch (_index) {
        0 => '备忘录',
        1 => '网盘',
        _ => 'BellMemo',
      };

  @override
  Widget build(BuildContext context) {
    final isCloud = _index == 1;
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: '菜单',
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(_title),
        actions: [
          if (isCloud)
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: () => _cloudPageKey.currentState?.refresh(),
            ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        Icons.notifications,
                        color:
                            Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'BellMemo',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.note_alt_outlined),
                      title: const Text('备忘录'),
                      selected: _index == 0,
                      onTap: () {
                        setState(() => _index = 0);
                        _memoPageKey.currentState?.reload();
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.cloud_outlined),
                      title: const Text('网盘（开发中...)'),
                      selected: _index == 1,
                      onTap: () {
                        setState(() {
                          _index = 1;
                          _cloudVisited = true;
                        });
                        Navigator.pop(context);
                      },
                    ),
                    if (isCloud) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.settings),
                        title: const Text('网盘设置'),
                        onTap: () {
                          Navigator.pop(context);
                          _cloudPageKey.currentState?.openSettings();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _memoPageKey.currentState?.createNewMemo(),
              icon: const Icon(Icons.add),
              label: const Text('新建'),
            )
          : null,
    );
  }
}
