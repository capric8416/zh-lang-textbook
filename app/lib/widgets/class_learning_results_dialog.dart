import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/textbook.dart';
import '../services/account_api.dart';
import '../services/class_learning_records.dart';

class ClassLearningResultsDialog extends StatefulWidget {
  const ClassLearningResultsDialog({
    super.key,
    required this.api,
    required this.classId,
    required this.className,
  });

  final AccountApi api;
  final String classId;
  final String className;

  @override
  State<ClassLearningResultsDialog> createState() =>
      _ClassLearningResultsDialogState();
}

class _ClassLearningResultsDialogState
    extends State<ClassLearningResultsDialog> {
  static const _initialPageSize = 100;
  static const _exportPageSize = 500;

  final List<Map<String, dynamic>> _loadedRecords = [];
  final Set<String> _loadedIds = {};
  List<Map<String, dynamic>> _visibleRecords = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _exporting = false;
  bool _cancelExportRequested = false;
  ClassLearningRecordsCursor? _nextCursor;
  int _exportFetched = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    if (_loading && _loadedRecords.isNotEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _loadedRecords.clear();
      _loadedIds.clear();
      _visibleRecords = [];
      _nextCursor = null;
      _hasMore = true;
    });
    await _loadMore(initial: true);
  }

  Future<void> _loadMore({bool initial = false}) async {
    if ((!initial && (!_hasMore || _loadingMore)) || !mounted) return;
    if (!initial) setState(() => _loadingMore = true);
    try {
      final page = await ClassLearningRecords.fetchPage(
        widget.api,
        widget.classId,
        cursor: _nextCursor,
        limit: _initialPageSize,
      );
      if (!mounted) return;
      for (final record in page.records) {
        final id = record['id'] as String?;
        if (id == null || _loadedIds.add(id)) _loadedRecords.add(record);
      }
      _loadedRecords.sort(
        (a, b) => '${b['occurredAt']}'.compareTo('${a['occurredAt']}'),
      );
      setState(() {
        _visibleRecords = _limitVisibleRecords(_loadedRecords);
        _nextCursor = page.cursor;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _limitVisibleRecords(
    List<Map<String, dynamic>> records,
  ) {
    final visibleCounts = <String, int>{};
    return records
        .where((record) {
          final studentId = record['studentId'] as String? ?? '';
          final count = visibleCounts[studentId] ?? 0;
          if (count >= 500) return false;
          visibleCounts[studentId] = count + 1;
          return true;
        })
        .toList(growable: false);
  }

  List<_QuestionGroup> get _questionGroups {
    final groups = <String, _QuestionGroup>{};
    for (final record in _visibleRecords) {
      final key = [
        record['textbookKey'],
        record['questionId'],
        record['direction'],
      ].join('\u0000');
      final group = groups.putIfAbsent(key, () => _QuestionGroup(record));
      group.attempts.add(
        _AttemptRecord({
          'studentId': record['studentId'],
          'displayName': record['displayName'],
          'username': record['username'],
        }, record),
      );
    }
    final result = groups.values.toList()
      ..sort((a, b) {
        final errorRate = b.errorRate.compareTo(a.errorRate);
        if (errorRate != 0) return errorRate;
        final attemptErrorRate = b.attemptErrorRate.compareTo(
          a.attemptErrorRate,
        );
        if (attemptErrorRate != 0) return attemptErrorRate;
        final attemptCount = b.attempts.length.compareTo(a.attempts.length);
        if (attemptCount != 0) return attemptCount;
        return '${a.question['prompt']}'.compareTo('${b.question['prompt']}');
      });
    return result;
  }

  Future<void> _exportAll() async {
    if (_exporting) return;
    var cancelled = false;
    setState(() {
      _exporting = true;
      _cancelExportRequested = false;
      _exportFetched = 0;
    });
    try {
      final records = <Map<String, dynamic>>[];
      final knownIds = <String>{};
      ClassLearningRecordsCursor? cursor;
      while (true) {
        if (_cancelExportRequested) {
          cancelled = true;
          return;
        }
        final page = await ClassLearningRecords.fetchPage(
          widget.api,
          widget.classId,
          cursor: cursor,
          limit: _exportPageSize,
        );
        if (_cancelExportRequested) {
          cancelled = true;
          return;
        }
        for (final record in page.records) {
          final id = record['id'] as String?;
          if (id == null || knownIds.add(id)) records.add(record);
        }
        if (mounted) setState(() => _exportFetched = records.length);
        if (!page.hasMore) break;
        cursor = page.cursor;
      }
      final reportRecords = await _addLessonLabels(records);
      if (_cancelExportRequested) {
        cancelled = true;
        return;
      }
      final html = _buildReportHtml(reportRecords);
      if (_cancelExportRequested) {
        cancelled = true;
        return;
      }
      final directory =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      await directory.create(recursive: true);
      if (_cancelExportRequested) {
        cancelled = true;
        return;
      }
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final safeClassName = widget.className.replaceAll(
        RegExp(r'[^\w\-\u4e00-\u9fff]'),
        '_',
      );
      final file = File(
        '${directory.path}/$safeClassName-学习记录-$timestamp.html',
      );
      await file.writeAsString(html, encoding: utf8);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出 ${records.length} 条历史记录：${file.path}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportFetched = 0;
        });
        if (cancelled) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已取消导出，未生成报告文件。')));
        }
      }
    }
  }

  void _cancelExport() {
    if (!_exporting) return;
    setState(() => _cancelExportRequested = true);
  }

  Future<List<Map<String, dynamic>>> _addLessonLabels(
    List<Map<String, dynamic>> records,
  ) async {
    final labelsByBook =
        <String, Map<String, ({String unit, String lesson})>>{};
    for (final textbookKey
        in records
            .map((record) => record['textbookKey'] as String? ?? '')
            .toSet()) {
      if (!RegExp(
        r'^zh-lang-grade[0-9]+[ab]-textbook-struct\.json$',
      ).hasMatch(textbookKey)) {
        continue;
      }
      try {
        final source = await rootBundle.loadString(
          'assets/json_reviewed/$textbookKey',
        );
        final textbook = Textbook.fromJsonString(source);
        final labels = <String, ({String unit, String lesson})>{};
        void visit(ContentNode node, String unitName) {
          labels.putIfAbsent(
            node.id,
            () => (unit: unitName, lesson: node.displayTitle),
          );
          for (final child in node.children) {
            visit(child, unitName);
          }
        }

        for (final unit in textbook.contents) {
          for (final chapter in unit.chapters) {
            visit(chapter, unit.name);
          }
        }
        labelsByBook[textbookKey] = labels;
      } catch (_) {
        // Keep raw IDs as fallbacks if a textbook asset is unavailable.
      }
    }
    return records.map((record) {
      final textbookKey = record['textbookKey'] as String? ?? '';
      final chapterId = record['chapterId'] as String? ?? '';
      final label = labelsByBook[textbookKey]?[chapterId];
      return <String, dynamic>{
        ...record,
        'unitName': label?.unit ?? '未识别单元',
        'lessonName': label?.lesson ?? chapterId,
      };
    }).toList();
  }

  String _buildReportHtml(List<Map<String, dynamic>> records) {
    final payload = jsonEncode(records)
        .replaceAll('<', r'\u003c')
        .replaceAll('>', r'\u003e')
        .replaceAll('&', r'\u0026')
        .replaceAll('\u2028', r'\u2028')
        .replaceAll('\u2029', r'\u2029');
    final escapedClassName = const HtmlEscape().convert(widget.className);
    return '''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>$escapedClassName学习报告</title>
<style>
:root{color-scheme:light;--ink:#263449;--muted:#728096;--line:#e6eaf0;--blue:#356ae6;--red:#c84d55;--green:#21845b;--paper:#f5f7fb;--card:#fff}*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:15px/1.6 system-ui,-apple-system,"Segoe UI","Noto Sans CJK SC",sans-serif}.wrap{max-width:1200px;margin:0 auto;padding:32px 22px 60px}.hero{padding:28px 30px;border-radius:22px;background:linear-gradient(120deg,#233d72,#497ce2);color:#fff;box-shadow:0 14px 34px #29477a24}.eyebrow{font-size:12px;letter-spacing:.16em;text-transform:uppercase;opacity:.75}.hero h1{margin:5px 0;font-size:clamp(25px,4vw,36px)}.hero p{margin:0;opacity:.85}.stats{display:flex;gap:12px;flex-wrap:wrap;margin-top:22px}.stat{min-width:120px;padding:11px 15px;border:1px solid #ffffff35;border-radius:13px;background:#ffffff12}.stat b{display:block;font-size:21px}.toolbar{display:grid;grid-template-columns:repeat(4,minmax(150px,1fr));gap:12px;margin:22px 0;padding:17px;border:1px solid var(--line);border-radius:18px;background:var(--card);box-shadow:0 4px 14px #1d35570a}.field label{display:block;margin:0 0 5px;color:var(--muted);font-size:12px}.field select{width:100%;padding:10px;border:1px solid var(--line);border-radius:10px;background:#fff;color:var(--ink);font:inherit}.section-title{display:flex;align-items:end;justify-content:space-between;margin:26px 2px 12px}.section-title h2{margin:0;font-size:20px}.muted{color:var(--muted)}.question{margin:12px 0;overflow:hidden;border:1px solid var(--line);border-radius:17px;background:var(--card);box-shadow:0 5px 18px #1d35570a}.qhead{display:grid;grid-template-columns:1fr auto;gap:18px;align-items:center;padding:18px 20px;cursor:pointer}.qtitle{font-weight:750;font-size:17px}.qprompt{margin-top:5px;color:var(--muted);white-space:pre-wrap}.meta{margin-top:8px;color:var(--muted);font-size:13px}.badge{display:inline-flex;align-items:center;padding:7px 11px;border-radius:999px;background:#fff0ef;color:var(--red);font-weight:750;white-space:nowrap}.badge.low{background:#e9f7ef;color:var(--green)}.qbody{display:none;padding:0 20px 20px;border-top:1px solid var(--line)}.question.open .qbody{display:block}.qdetails{display:flex;flex-wrap:wrap;gap:8px;margin:14px 0;color:var(--muted);font-size:13px}.pill{padding:5px 9px;border-radius:8px;background:#f1f4f9}.students{display:grid;gap:10px}.student{border:1px solid var(--line);border-radius:13px;overflow:hidden}.student-head{display:grid;grid-template-columns:1fr auto;gap:10px;padding:12px 14px;background:#fafbfd}.student-name{font-weight:700}.student-score{font-weight:750}.attempts{width:100%;border-collapse:collapse;font-size:13px}.attempts th,.attempts td{padding:9px 11px;text-align:left;vertical-align:top;border-top:1px solid var(--line)}.attempts th{color:var(--muted);font-weight:600;background:#fcfdff}.ok{color:var(--green);font-weight:700}.bad{color:var(--red);font-weight:700}.empty{padding:40px;text-align:center;color:var(--muted);border:1px dashed #cbd3df;border-radius:16px;background:#fff}@media(max-width:760px){.wrap{padding:18px 12px 40px}.toolbar{grid-template-columns:1fr 1fr}.qhead{grid-template-columns:1fr}.badge{justify-self:start}.attempts{display:block;overflow:auto}.student-head{grid-template-columns:1fr}.hero{padding:22px}.stat{flex:1}}
</style></head><body><main class="wrap"><header class="hero"><div class="eyebrow">Class learning report</div><h1>$escapedClassName · 学习报告</h1><p>按题目汇总班级作答表现；展开题目查看学生正确率及逐次作答。</p><div class="stats" id="stats"></div></header>
<section class="toolbar"><div class="field"><label for="unitFilter">筛选单元</label><select id="unitFilter"><option value="">全部单元</option></select></div><div class="field"><label for="lessonFilter">筛选课文</label><select id="lessonFilter"><option value="">全部课文</option></select></div><div class="field"><label for="questionSort">题目排序</label><select id="questionSort"><option value="error-desc">学生错误率：高到低</option><option value="error-asc">学生错误率：低到高</option><option value="attempt-error-desc">错误作答率：高到低</option><option value="attempts-desc">作答次数：多到少</option></select></div><div class="field"><label for="studentSort">题内学生排序</label><select id="studentSort"><option value="accuracy-asc">学生正确率：低到高</option><option value="accuracy-desc">学生正确率：高到低</option></select></div></section>
<div class="section-title"><h2>题目表现</h2><span class="muted" id="resultCount"></span></div><section id="questions"></section></main>
<script>
const records=$payload;
const byId=id=>document.getElementById(id), unitFilter=byId('unitFilter'), lessonFilter=byId('lessonFilter'), questionSort=byId('questionSort'), studentSort=byId('studentSort');
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const correct=r=>r.isCorrect===true||r.isCorrect===1;
const groupBy=(items,keyFn)=>{const m=new Map();for(const item of items){const k=keyFn(item);if(!m.has(k))m.set(k,[]);m.get(k).push(item)}return m};
const units=[...new Set(records.map(r=>r.unitName).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'zh-CN'));
for(const unit of units){const o=document.createElement('option');o.value=unit;o.textContent=unit;unitFilter.append(o)}
function updateLessons(){const current=lessonFilter.value;lessonFilter.innerHTML='<option value="">全部课文</option>';const lessons=[...new Set(records.filter(r=>!unitFilter.value||r.unitName===unitFilter.value).map(r=>r.lessonName).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'zh-CN'));for(const lesson of lessons){const o=document.createElement('option');o.value=lesson;o.textContent=lesson;lessonFilter.append(o)}if(lessons.includes(current))lessonFilter.value=current;render()}
function render(){const filtered=records.filter(r=>(!unitFilter.value||r.unitName===unitFilter.value)&&(!lessonFilter.value||r.lessonName===lessonFilter.value));const questions=[...groupBy(filtered,r=>[r.textbookKey,r.questionId,r.direction].join('|')).values()].map(attempts=>{const q=attempts[0], students=[...groupBy(attempts,r=>r.studentId).entries()].map(([studentId,rows])=>({studentId,rows,name:rows[0].displayName||rows[0].username||studentId,username:rows[0].username||'',accuracy:rows.filter(correct).length/rows.length}));const wrongStudents=students.filter(s=>s.rows.some(r=>!correct(r))).length;return{q,attempts,students,studentErrorRate:students.length?wrongStudents/students.length:0,attemptErrorRate:attempts.length?attempts.filter(r=>!correct(r)).length/attempts.length:0}});
const sort=questionSort.value;questions.sort((a,b)=>sort==='error-asc'?a.studentErrorRate-b.studentErrorRate:sort==='attempt-error-desc'?b.attemptErrorRate-a.attemptErrorRate:sort==='attempts-desc'?b.attempts.length-a.attempts.length:b.studentErrorRate-a.studentErrorRate);
const right=filtered.filter(correct).length,wrong=filtered.length-right;byId('stats').innerHTML='<div class="stat"><b>'+filtered.length+'</b>答题记录</div><div class="stat"><b>'+questions.length+'</b>道题</div><div class="stat"><b>'+right+'</b>正确作答</div><div class="stat"><b>'+wrong+'</b>错误作答</div>';byId('resultCount').textContent='当前筛选 '+questions.length+' 道题 · '+filtered.length+' 条记录';
if(!questions.length){byId('questions').innerHTML='<div class="empty">当前筛选条件下没有答题记录</div>';return}
byId('questions').innerHTML=questions.map((item,index)=>{const q=item.q;const err=(item.studentErrorRate*100).toFixed(1),attemptErr=(item.attemptErrorRate*100).toFixed(1);const students=[...item.students].sort((a,b)=>studentSort.value==='accuracy-desc'?b.accuracy-a.accuracy:a.accuracy-b.accuracy||a.name.localeCompare(b.name,'zh-CN'));return '<article class="question" id="q'+index+'"><div class="qhead" onclick="this.parentElement.classList.toggle(&#39;open&#39;)"><div><div class="qtitle">'+esc(q.source)+' · '+esc(q.prompt)+'</div><div class="meta">'+esc(q.unitName)+' / '+esc(q.lessonName)+' · '+esc(q.textbookKey)+' · '+esc(q.chapterId)+' · '+esc(q.category)+' · '+esc(q.direction)+'</div></div><span class="badge '+(item.studentErrorRate===0?'low':'')+'">学生错误率 '+err+'%</span></div><div class="qbody"><div class="qdetails"><span class="pill">题目 ID：'+esc(q.questionId)+'</span><span class="pill">题型：'+esc(q.questionKind)+'</span><span class="pill">错误学生：'+item.students.filter(s=>s.rows.some(r=>!correct(r))).length+'/'+item.students.length+'</span><span class="pill">错误作答率：'+attemptErr+'%</span><span class="pill">标准答案：'+esc(q.expectedAnswer)+'</span></div><div class="students">'+students.map(s=>'<section class="student"><div class="student-head"><div><div class="student-name">'+esc(s.name)+'</div><div class="muted">'+esc(s.username)+' · '+s.rows.length+' 次作答</div></div><div class="student-score">正确率 '+(s.accuracy*100).toFixed(1)+'% ('+s.rows.filter(correct).length+'/'+s.rows.length+')</div></div><table class="attempts"><thead><tr><th>结果</th><th>学生作答</th><th>作答时间</th><th>记录 ID</th><th>入库时间</th><th>学生 ID</th><th>班级 ID</th></tr></thead><tbody>'+[...s.rows].sort((a,b)=>String(b.occurredAt).localeCompare(String(a.occurredAt))).map(r=>'<tr><td class="'+(correct(r)?'ok':'bad')+'">'+(correct(r)?'正确':'错误')+'</td><td>'+esc(r.studentAnswer)+'</td><td>'+esc(r.occurredAt)+'</td><td>'+esc(r.id)+'</td><td>'+esc(r.createdAt)+'</td><td>'+esc(r.studentId)+'</td><td>'+esc(r.classId)+'</td></tr>').join('')+'</tbody></table></section>').join('')+'</div></div></article>'}).join('')}
unitFilter.addEventListener('change',updateLessons);lessonFilter.addEventListener('change',render);questionSort.addEventListener('change',render);studentSort.addEventListener('change',render);updateLessons();
</script></body></html>''';
  }

  @override
  Widget build(BuildContext context) {
    final groups = _questionGroups;
    final records = _visibleRecords;
    final correct = records.where(_isCorrect).length;
    final wrong = records.length - correct;
    final studentCount = _loadedRecords
        .map((record) => record['studentId'])
        .toSet()
        .length;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 900,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.className}学习记录',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (_loading || _loadingMore || _exporting)
                const LinearProgressIndicator(),
              if (_error != null) ...[const SizedBox(height: 8), Text(_error!)],
              if (!_loading) ...[
                Text(
                  '已加载 ${_loadedRecords.length} 条 · 当前显示 ${records.length} 条（每人最近 500 条；正确 $correct，需订正 $wrong）· $studentCount 名学生 · ${groups.length} 道题${_hasMore ? '。统计仅基于已加载记录。' : '。已加载全部记录。'}',
                ),
                if (_exporting)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('正在下载全量历史记录，已取得 $_exportFetched 条…'),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: groups.isEmpty
                      ? Center(
                          child: Text(
                            _error == null ? '当前班级暂无已上传做题记录' : '加载失败，可重试。',
                          ),
                        )
                      : ListView.builder(
                          itemCount: groups.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index < groups.length) {
                              return _buildQuestionTile(groups[index]);
                            }
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: OutlinedButton.icon(
                                  onPressed: _loadingMore || _exporting
                                      ? null
                                      : _loadMore,
                                  icon: _loadingMore
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.expand_more),
                                  label: Text(
                                    _loadingMore
                                        ? '正在加载更多…'
                                        : '加载更多记录（已加载 ${_loadedRecords.length} 条）',
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ] else
                const Spacer(),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _loading || _loadingMore || _exporting
                        ? null
                        : _exportAll,
                    icon: _exporting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(_exporting ? '正在导出…' : '导出 HTML 报告'),
                  ),
                  if (_exporting) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _cancelExportRequested ? null : _cancelExport,
                      child: Text(_cancelExportRequested ? '正在取消…' : '取消导出'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _loading || _loadingMore ? null : _loadInitial,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionTile(_QuestionGroup group) {
    final question = group.question;
    final direction = _directionName(question['direction']);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('${question['source'] ?? ''} · ${question['prompt'] ?? ''}'),
      subtitle: Text(
        '${question['textbookKey']} · ${question['chapterId']} · $direction · ${group.attempts.length} 次作答 / ${group.studentCount} 人 · 错误学生 ${group.wrongStudentCount}/${group.studentCount}（${(group.errorRate * 100).toStringAsFixed(1)}%）· 错误作答 ${group.wrongCount}/${group.attempts.length}（${(group.attemptErrorRate * 100).toStringAsFixed(1)}%）',
      ),
      children: [
        _detail('题目 ID', question['questionId']),
        _detail(
          '题型 / 分类',
          '${question['questionKind']} / ${question['category']}',
        ),
        _detail('题目内容', question['prompt']),
        _detail('标准答案', question['expectedAnswer']),
        for (final attempt in group.attempts) _buildAttemptTile(attempt),
      ],
    );
  }

  Widget _buildAttemptTile(_AttemptRecord attempt) {
    final record = attempt.record;
    final correct = _isCorrect(record);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${attempt.student['displayName']} · ${attempt.student['username']} · ${correct ? '正确' : '错误'}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: correct
                    ? Colors.green.shade800
                    : Theme.of(context).colorScheme.error,
              ),
            ),
            _detail('学生作答', record['studentAnswer']),
            _detail('记录 ID', record['id']),
            _detail(
              '学生 ID / 班级 ID',
              '${record['studentId']} / ${record['classId']}',
            ),
            _detail('作答时间', record['occurredAt']),
            _detail('入库时间', record['createdAt']),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text('$label：${value ?? ''}'),
  );

  String _directionName(Object? value) => switch (value) {
    'writeHanzi' => '看拼音写汉字',
    'writePinyin' => '看汉字写拼音',
    'listenWriteHanzi' => '听写',
    'readAloud' => '朗读',
    _ => '$value',
  };

  bool _isCorrect(Map<String, dynamic> record) =>
      record['isCorrect'] == true || record['isCorrect'] == 1;
}

class _AttemptRecord {
  const _AttemptRecord(this.student, this.record);

  final Map<String, dynamic> student;
  final Map<String, dynamic> record;
}

class _QuestionGroup {
  _QuestionGroup(this.question);

  final Map<String, dynamic> question;
  final List<_AttemptRecord> attempts = [];

  int get wrongCount =>
      attempts.where((attempt) => !_isCorrectRecord(attempt.record)).length;
  int get studentCount =>
      attempts.map((attempt) => attempt.student['studentId']).toSet().length;
  int get wrongStudentCount => attempts
      .where((attempt) => !_isCorrectRecord(attempt.record))
      .map((attempt) => attempt.student['studentId'])
      .toSet()
      .length;
  double get errorRate =>
      studentCount == 0 ? 0 : wrongStudentCount / studentCount;
  double get attemptErrorRate =>
      attempts.isEmpty ? 0 : wrongCount / attempts.length;

  static bool _isCorrectRecord(Map<String, dynamic> record) =>
      record['isCorrect'] == true || record['isCorrect'] == 1;
}
