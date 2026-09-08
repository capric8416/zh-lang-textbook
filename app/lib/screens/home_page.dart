import 'package:flutter/material.dart';

import '../models/textbook.dart';
import '../services/textbook_repository.dart';
import 'mode_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.repository = const TextbookRepository()});

  final TextbookRepository repository;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _grade = 2;
  Semester _semester = Semester.second;
  bool _loading = false;
  String? _error;

  Future<void> _continue() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final selection = TextbookSelection(grade: _grade, semester: _semester);
    try {
      final Textbook textbook = await widget.repository.load(selection);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ModePage(selection: selection, textbook: textbook),
        ),
      );
    } on TextbookLoadException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = '载入教材失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 34, 28, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '文',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontFamilyFallback: ['KaiTi', 'STKaiti'],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        '语文基础巩固与练习',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '选择教材，开始复习字、词、句与诗词',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 34),
                      DropdownButtonFormField<int>(
                        initialValue: _grade,
                        decoration: const InputDecoration(
                          labelText: '年级',
                          prefixIcon: Icon(Icons.school_outlined),
                        ),
                        items: [
                          for (var grade = 1; grade <= 6; grade++)
                            DropdownMenuItem(
                              value: grade,
                              child: Text('$grade年级'),
                            ),
                        ],
                        onChanged: _loading
                            ? null
                            : (value) => setState(() => _grade = value ?? 2),
                      ),
                      const SizedBox(height: 18),
                      SegmentedButton<Semester>(
                        segments: const [
                          ButtonSegment(
                            value: Semester.first,
                            label: Text('上学期'),
                            icon: Icon(Icons.wb_sunny_outlined),
                          ),
                          ButtonSegment(
                            value: Semester.second,
                            label: Text('下学期'),
                            icon: Icon(Icons.park_outlined),
                          ),
                        ],
                        selected: {_semester},
                        onSelectionChanged: _loading
                            ? null
                            : (value) =>
                                  setState(() => _semester = value.first),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 18),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        onPressed: _loading ? null : _continue,
                        icon: _loading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.arrow_forward),
                        label: Text(_loading ? '正在载入教材…' : '进入教材'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
