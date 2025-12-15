import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/cloud_service.dart';

class CloudMdViewer extends StatefulWidget {
  final String filePath;
  final String fileName;

  const CloudMdViewer({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<CloudMdViewer> createState() => _CloudMdViewerState();
}

class _CloudMdViewerState extends State<CloudMdViewer> {
  String? _content;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      final content = await CloudService().readTextFile(widget.filePath);
      if (mounted) {
        setState(() {
          _content = content;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('加载失败: $_error'))
              : Markdown(
                  data: _content ?? '',
                  selectable: true,
                  padding: const EdgeInsets.all(16),
                ),
    );
  }
}

