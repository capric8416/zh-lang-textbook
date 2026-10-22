import 'package:flutter/material.dart';
import 'dart:async';

import '../models/textbook.dart';
import '../services/account_api.dart';
import '../services/practice_record_sync.dart';
import '../services/study_state_sync.dart';
import '../services/textbook_repository.dart';
import '../services/textbook_preference.dart';
import 'account_center.dart';
import 'mode_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.repository = const TextbookRepository()});

  final TextbookRepository repository;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int? _grade;
  Semester? _semester;
  bool _selectionReady = false;
  bool _authReady = false;
  bool _authenticated = false;
  bool _selectionTouched = false;
  bool _loading = false;
  String? _error;
  int _tabIndex = 0;
  final AccountApi _accountApi = AccountApi();

  @override
  void initState() {
    super.initState();
    _restoreAuthentication();
  }

  Future<void> _restoreAuthentication() async {
    var authenticated = false;
    try {
      final token = await _accountApi.token;
      final accountId = await _accountApi.accountId;
      authenticated =
          token != null &&
          token.isNotEmpty &&
          accountId != null &&
          accountId.isNotEmpty;
    } catch (_) {
      // If secure storage is temporarily unavailable, fail closed to login.
    }
    if (authenticated) {
      await _restoreSelection();
      try {
        await StudyStateSync.synchronize(api: _accountApi);
      } catch (_) {
        // Keep local state available while the service is offline.
      }
      StudyStateSync.bind(_accountApi);
      PracticeRecordSync.schedule(api: _accountApi);
    }
    if (!mounted) return;
    setState(() {
      _authenticated = authenticated;
      _authReady = true;
    });
  }

  Future<void> _authenticatedNow() async {
    if (!mounted) return;
    setState(() {
      _authReady = false;
      _tabIndex = 0;
    });
    await _restoreSelection();
    try {
      await StudyStateSync.synchronize(api: _accountApi);
    } catch (_) {
      // Login remains usable offline after authentication succeeds.
    }
    StudyStateSync.bind(_accountApi);
    PracticeRecordSync.schedule(api: _accountApi);
    if (!mounted) return;
    setState(() {
      _authenticated = true;
      _authReady = true;
    });
  }

  void _signedOut() {
    StudyStateSync.unbind();
    if (!mounted) return;
    setState(() {
      _authenticated = false;
      _grade = null;
      _semester = null;
      _selectionTouched = false;
      _selectionReady = false;
      _tabIndex = 0;
    });
  }

  Future<void> _restoreSelection() async {
    final accountId = await _accountApi.accountId;
    if (accountId == null) return;
    try {
      await TextbookPreference.synchronize(_accountApi);
    } catch (_) {
      // Offline selections stay available and pending changes retry on login.
    }
    final selection = await TextbookPreference.load(accountId);
    if (!mounted) return;
    setState(() {
      if (!_selectionTouched) {
        _grade = selection?.grade;
        _semester = selection?.semester;
      }
      _selectionReady = true;
    });
  }

  Future<void> _continue() async {
    final grade = _grade;
    final semester = _semester;
    if (_loading || !_selectionReady || grade == null || semester == null) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final selection = TextbookSelection(grade: grade, semester: semester);
    try {
      final Textbook textbook = await widget.repository.load(selection);
      if (!mounted) return;
      final accountId = await _accountApi.accountId;
      if (accountId != null) {
        await TextbookPreference.save(accountId, selection);
        unawaited(
          TextbookPreference.synchronize(_accountApi).catchError((_) {}),
        );
      }
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
    if (!_authReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_authenticated) {
      return Scaffold(
        body: SafeArea(
          child: AccountCenter(
            api: _accountApi,
            onAuthenticated: _authenticatedNow,
          ),
        ),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: _tabIndex == 1
          ? SafeArea(
              child: AccountCenter(api: _accountApi, onSignedOut: _signedOut),
            )
          : SafeArea(
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
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
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
                                  : (value) => setState(() {
                                      _selectionTouched = true;
                                      _grade = value;
                                    }),
                            ),
                            const SizedBox(height: 18),
                            SegmentedButton<Semester>(
                              emptySelectionAllowed: true,
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
                              selected: {?_semester},
                              onSelectionChanged: _loading
                                  ? null
                                  : (value) => setState(() {
                                      _selectionTouched = true;
                                      _semester = value.firstOrNull;
                                    }),
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
                              onPressed:
                                  _loading ||
                                      !_selectionReady ||
                                      _grade == null ||
                                      _semester == null
                                  ? null
                                  : _continue,
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '学习',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
