import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/textbook.dart';
import '../services/account_api.dart';
import '../services/practice_record_sync.dart';
import '../services/student_learning_history.dart';
import '../widgets/original_handwriting.dart';

class StudentLearningRecordsPage extends StatefulWidget {
  const StudentLearningRecordsPage({
    super.key,
    required this.accountId,
    this.api,
  });
  final String accountId;
  final AccountApi? api;

  @override
  State<StudentLearningRecordsPage> createState() =>
      _StudentLearningRecordsPageState();
}

class _StudentLearningRecordsPageState
    extends State<StudentLearningRecordsPage> {
  List<StudentLearningRecord> _records = [];
  final Map<String, Textbook?> _books = {};
  bool _loading = true;
  String? _error;
  bool? _correct;
  AttemptSyncState? _syncState;
  String _search = '';
  Timer? _refreshTimer;
  bool _refreshing = false;
  late final AccountApi _api = widget.api ?? AccountApi();

  @override
  void initState() {
    super.initState();
    PracticeRecordSync.changes.addListener(_scheduleRefresh);
    _load();
  }

  @override
  void dispose() {
    PracticeRecordSync.changes.removeListener(_scheduleRefresh);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _scheduleRefresh() {
    // Loading remote records itself updates sync status. Do not schedule a
    // second remote load in response to that notification.
    if (_refreshing || !mounted) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _load() async {
    if (_refreshing || !mounted) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      await _display(await StudentLearningHistory.load(widget.accountId));
      if (!mounted) return;
      await for (final records in StudentLearningHistory.refresh(
        _api,
        widget.accountId,
      )) {
        if (!mounted) break;
        await _display(records);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is AccountApiException && error.statusCode == 404
            ? '学习记录服务暂不可用，请稍后刷新。当前显示本机缓存。'
            : '远端记录读取失败，请刷新重试。当前显示本机保存的记录。';
        _loading = false;
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _display(List<StudentLearningRecord> records) async {
    for (final key in records.map((r) => r.text('textbookKey')).toSet()) {
      if (_books.containsKey(key)) continue;
      _books[key] = null;
      if (!RegExp(
        r'^zh-lang-grade[0-9]+[ab]-textbook-struct\.json$',
      ).hasMatch(key)) {
        continue;
      }
      try {
        _books[key] = Textbook.fromJsonString(
          await rootBundle.loadString('assets/json_reviewed/$key'),
        );
      } catch (_) {
        // The original record remains readable if its textbook is unavailable.
      }
    }
    if (!mounted) return;
    setState(() {
      _records = records;
      _error = null;
      _loading = false;
    });
  }

  String _bookName(StudentLearningRecord record) {
    final key = record.text('textbookKey');
    final match = RegExp(r'^zh-lang-grade(\d+)([ab])-').firstMatch(key);
    return match == null ? key : '${match[1]}年级${match[2] == 'a' ? '上' : '下'}册';
  }

  String _lessonName(StudentLearningRecord record) =>
      _books[record.text('textbookKey')]
          ?.node(record.text('chapterId'))
          ?.displayTitle ??
      record.text('chapterId');

  String _direction(StudentLearningRecord record) =>
      switch (record.text('direction')) {
        'writeHanzi' => '看拼音写汉字',
        'writePinyin' => '看汉字写拼音',
        'listenWriteHanzi' => '听写',
        'readAloud' => '朗读',
        final value => value,
      };

  @override
  Widget build(BuildContext context) {
    final visible = _records.where((r) {
      if (_correct != null && r.isCorrect != _correct) return false;
      if (_syncState != null && r.syncState != _syncState) return false;
      return [
        _bookName(r),
        _lessonName(r),
        r.text('prompt'),
        r.text('studentAnswer'),
        r.text('expectedAnswer'),
      ].join(' ').toLowerCase().contains(_search.trim().toLowerCase());
    }).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的学习记录'),
        actions: [
          IconButton(
            tooltip: '刷新记录',
            onPressed: _refreshing ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('查看账号的历史作答，包含以前班级及未加入班级时的记录；本机未上传的作答也会显示。'),
                        if (_refreshing) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                          const Text('正在从远端加载，当前显示已加载和本机保存的记录…'),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: '搜索教材、课文、题目或答案',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) => setState(() => _search = value),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ChoiceChip(
                              label: const Text('全部结果'),
                              selected: _correct == null,
                              onSelected: (_) =>
                                  setState(() => _correct = null),
                            ),
                            ChoiceChip(
                              label: const Text('正确'),
                              selected: _correct == true,
                              onSelected: (_) =>
                                  setState(() => _correct = true),
                            ),
                            ChoiceChip(
                              label: const Text('需巩固'),
                              selected: _correct == false,
                              onSelected: (_) =>
                                  setState(() => _correct = false),
                            ),
                            PopupMenuButton<String>(
                              tooltip: '筛选同步状态',
                              onSelected: (value) => setState(
                                () => _syncState = value == 'all'
                                    ? null
                                    : AttemptSyncState.values.byName(value),
                              ),
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'all',
                                  child: Text('全部同步状态'),
                                ),
                                for (final state in AttemptSyncState.values)
                                  PopupMenuItem(
                                    value: state.name,
                                    child: Text(state.label),
                                  ),
                              ],
                              child: Chip(
                                label: Text(
                                  '${_syncState?.label ?? '全部同步状态'} ▾',
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '共 ${_records.length} 次作答 · 当前显示 ${visible.length} 条（最新在前）',
                        ),
                        if (_error != null)
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        _records.isEmpty
                            ? (_error ??
                                  (_refreshing
                                      ? '正在读取学习记录…'
                                      : '还没有作答记录，完成练习批改后会显示在这里。'))
                            : '没有符合筛选条件的记录',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    sliver: SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) =>
                          _recordCard(visible[index]),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _recordCard(StudentLearningRecord record) {
    final time =
        record.occurredAt?.toLocal().toString().split('.').first ?? '时间未知';
    return Card(
      child: ExpansionTile(
        leading: Icon(
          record.isCorrect ? Icons.check_circle_outline : Icons.edit_note,
        ),
        title: Text(
          record.text('prompt').isEmpty ? '作答记录' : record.text('prompt'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${record.isCorrect ? '正确' : '需巩固'} · ${record.syncState.label}\n$time\n${_bookName(record)} · ${_lessonName(record)} · ${_direction(record)}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SelectableText('参考答案：${record.text('expectedAnswer')}'),
            ),
          ),
          if (record.text('direction') == 'readAloud')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  'ASR 识别结果：${record.text('studentAnswer').isEmpty ? '（未识别）' : record.text('studentAnswer')}',
                ),
              ),
            )
          else
            OriginalHandwriting(record: record.data),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                [
                  if (record.text('category').isNotEmpty)
                    '分类：${record.text('category')}',
                  if (record.text('source').isNotEmpty)
                    '来源：${record.text('source')}',
                  if (record.syncState == AttemptSyncState.unknown)
                    '这条记录保存在本机，但没有成功上传凭据，无法确认是否已上传。',
                  if (record.syncState == AttemptSyncState.pending)
                    '这条记录正在等待同步，可在“我的”页面查看原因并重试。',
                ].join('\n\n'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
