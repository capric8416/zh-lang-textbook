import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/account_api.dart';
import '../widgets/class_join_code_dialog.dart';

const _roleNames = {
  'super_admin': '超级管理员',
  'group_admin': '集团管理员',
  'school_admin': '学校管理员',
  'class_admin': '班级管理员',
  'student': '学生',
};

class AccountCenter extends StatefulWidget {
  const AccountCenter({super.key, this.api});
  final AccountApi? api;

  @override
  State<AccountCenter> createState() => _AccountCenterState();
}

class _AccountCenterState extends State<AccountCenter> {
  late final AccountApi _api = widget.api ?? AccountApi();
  Map<String, dynamic>? _me;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (await _api.token == null) {
        if (mounted) {
          setState(() {
            _me = null;
            _loading = false;
          });
        }
        return;
      }
      final result = await _api.request('me');
      if (mounted) {
        setState(() {
          _me = result;
          _loading = false;
        });
      }
    } catch (error) {
      await _api.clearToken();
      if (mounted) {
        setState(() {
          _me = null;
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_me == null) {
      return _SignInPanel(api: _api, onSignedIn: _load, error: _error);
    }
    final account = _me!['account'] as Map<String, dynamic>;
    final role = account['role'] as String? ?? 'student';
    final student = role == 'student';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                child: Text(
                  (account['displayName'] as String? ?? '我').substring(0, 1),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account['displayName'] as String? ??
                          account['username'] as String? ??
                          '',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${_roleNames[role] ?? role} · ${account['username'] ?? ''}',
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '退出登录',
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (student)
            _StudentClassCard(
              api: _api,
              classInfo: _me!['class'] as Map<String, dynamic>?,
              onChanged: _load,
            ),
          if (role == 'class_admin') _ClassManagement(api: _api),
          if (!student)
            _AccountManagement(
              api: _api,
              role: role,
              accountId: account['id'] as String,
            ),
          _ChangePassword(api: _api, onChanged: _load),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    await _api.logout();
    if (mounted) {
      setState(() {
        _me = null;
      });
    }
  }
}

class _SignInPanel extends StatefulWidget {
  const _SignInPanel({required this.api, required this.onSignedIn, this.error});
  final AccountApi api;
  final VoidCallback onSignedIn;
  final String? error;
  @override
  State<_SignInPanel> createState() => _SignInPanelState();
}

class _SignInPanelState extends State<_SignInPanel> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _pendingJoinCode;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.account_circle_outlined,
                    size: 54,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _register ? '创建学生账号' : '登录账号',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (!widget.api.configured)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        '账号服务还未配置。当前教材与练习仍可离线使用。',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (_register) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _displayName,
                      decoration: const InputDecoration(labelText: '姓名/显示名称'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _username,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[A-Za-z0-9_@-]'),
                      ),
                      LengthLimitingTextInputFormatter(32),
                    ],
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      helperText: '4–32 位，仅限英文字母、数字及 _ - @',
                    ),
                    validator: (value) {
                      final username = value?.trim() ?? '';
                      if (username.runes.length < 4 ||
                          username.runes.length > 32) {
                        return '用户名长度需为 4–32 位';
                      }
                      if (!RegExp(r'^[A-Za-z0-9_@-]+$').hasMatch(username)) {
                        return '仅允许英文字母、数字及 _ - @';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: '密码'),
                    validator: (v) =>
                        (v == null || v.length < 8) ? '至少 8 位' : null,
                    onFieldSubmitted: (_) {
                      if (!_busy && widget.api.configured) _submit();
                    },
                  ),
                  if (_error != null || widget.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error ?? widget.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy || !widget.api.configured ? null : _submit,
                    child: Text(
                      _busy
                          ? '请稍候…'
                          : _register
                          ? '创建并登录'
                          : '登录',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _register = !_register;
                            _error = null;
                          }),
                    child: Text(_register ? '已有账号？登录' : '没有账号？注册学生账号'),
                  ),
                  if (!_register)
                    TextButton.icon(
                      onPressed: _busy ? null : _scanAndJoin,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('先扫描班级二维码'),
                    ),
                  if (!_register)
                    TextButton.icon(
                      onPressed: _busy ? null : _enterJoinCode,
                      icon: const Icon(Icons.keyboard),
                      label: const Text('输入入班码'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _submit() async {
    if (_busy) return;
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        final proof = await AccountApi.newPasswordProof(_password.text);
        await widget.api.request(
          'auth/register',
          method: 'POST',
          authenticated: false,
          body: {
            'username': _username.text.trim(),
            ...proof,
            'displayName': _displayName.text.trim(),
          },
        );
      }
      await widget.api.login(_username.text.trim(), _password.text);
      if (_pendingJoinCode case final code?) {
        await widget.api.request(
          'classes/join',
          method: 'POST',
          body: {'code': code},
        );
      }
      widget.onSignedIn();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanAndJoin() async {
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _QrScannerPage()));
    if (code == null || !mounted) return;
    setState(() {
      _pendingJoinCode = code;
      _error = '已读取入班码。登录或创建学生账号后会自动加入班级。';
    });
  }

  Future<void> _enterJoinCode() async {
    final code = await _requestJoinCode(context);
    if (code == null || !mounted) return;
    setState(() {
      _pendingJoinCode = code;
      _error = '已读取入班码。登录或创建学生账号后会自动加入班级。';
    });
  }
}

class _StudentClassCard extends StatelessWidget {
  const _StudentClassCard({
    required this.api,
    required this.classInfo,
    required this.onChanged,
  });
  final AccountApi api;
  final Map<String, dynamic>? classInfo;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('我的班级', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            classInfo == null
                ? '尚未加入班级'
                : classInfo!['name'] as String? ?? '班级',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _scan(context),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('扫码加入/更换'),
              ),
              OutlinedButton.icon(
                onPressed: () => _enterCode(context),
                icon: const Icon(Icons.keyboard),
                label: const Text('输入入班码'),
              ),
              if (classInfo != null)
                TextButton(
                  onPressed: () async {
                    await api.request('me/class', method: 'DELETE');
                    onChanged();
                  },
                  child: const Text('退出班级'),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _scan(BuildContext context) async {
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _QrScannerPage()));
    if (code == null) return;
    try {
      await api.request('classes/join', method: 'POST', body: {'code': code});
      onChanged();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _enterCode(BuildContext context) async {
    final code = await _requestJoinCode(context);
    if (code == null || !context.mounted) return;
    try {
      await api.request('classes/join', method: 'POST', body: {'code': code});
      onChanged();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _AccountManagement extends StatefulWidget {
  const _AccountManagement({
    required this.api,
    required this.role,
    required this.accountId,
  });
  final AccountApi api;
  final String role;
  final String accountId;
  @override
  State<_AccountManagement> createState() => _AccountManagementState();
}

class _AccountManagementState extends State<_AccountManagement> {
  List<dynamic> _tree = [];
  bool _busy = true;
  String? _error;
  int _loadGeneration = 0;
  String? get _newRole => switch (widget.role) {
    'super_admin' => 'group_admin',
    'group_admin' => 'school_admin',
    'school_admin' => 'class_admin',
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final result = await widget.api.request('accounts/tree');
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _tree = result['tree'] as List<dynamic>? ?? [];
          _busy = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = error.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '账号管理',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_newRole != null)
                IconButton(
                  tooltip: '创建${_roleNames[_newRole]}',
                  onPressed: _create,
                  icon: const Icon(Icons.person_add_alt_1),
                ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          if (!_busy && _tree.isEmpty) const Text('暂时没有下级账号'),
          for (final item in _tree)
            _AccountTreeNode(
              api: widget.api,
              item: item as Map<String, dynamic>,
              canManage:
                  item['parentId'] == widget.accountId &&
                  (widget.role != 'class_admin' || item['role'] == 'student'),
              refresh: _load,
            ),
        ],
      ),
    ),
  );

  Future<void> _create() async {
    var role = _newRole;
    if (widget.role == 'super_admin') {
      role = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择要创建的角色'),
          children: [
            for (final value in ['super_admin', 'group_admin'])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, value),
                child: Text(_roleNames[value]!),
              ),
          ],
        ),
      );
    }
    if (!mounted) return;
    if (role == null) return;
    final created = await showDialog<_NewAccountData>(
      context: context,
      builder: (_) => _CreateAccountDialog(role: role!),
    );
    if (created == null) return;
    try {
      final proof = await AccountApi.newPasswordProof(created.password);
      final result = await widget.api.request(
        'accounts',
        method: 'POST',
        body: {
          'username': created.username,
          'displayName': created.name,
          ...proof,
          'role': role,
        },
      );
      if (!mounted) return;
      setState(() {
        _tree = [
          ..._tree,
          <String, dynamic>{
            'id': result['id'],
            'username': created.username,
            'displayName': created.name.trim().isEmpty
                ? created.username
                : created.name.trim(),
            'role': role,
            'parentId': widget.accountId,
            'mustChangePassword': true,
            'disabled': false,
            'children': <dynamic>[],
          },
        ];
        _error = null;
      });
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _AccountTreeNode extends StatelessWidget {
  const _AccountTreeNode({
    required this.api,
    required this.item,
    required this.canManage,
    required this.refresh,
  });
  final AccountApi api;
  final Map<String, dynamic> item;
  final bool canManage;
  final VoidCallback refresh;
  @override
  Widget build(BuildContext context) {
    final canRemoveStudent = canManage && item['role'] == 'student';
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 16),
      title: Text(
        '${item['displayName']} · ${_roleNames[item['role']] ?? item['role']}',
      ),
      subtitle: Text(
        '${item['username']}${item['disabled'] == true ? ' · 已停用' : ''}',
      ),
      trailing: canManage
          ? PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'remove_student') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('移出并加入黑名单？'),
                      content: Text(
                        '确定将「${item['displayName']}」移出当前班级吗？该学生将无法再次加入此班级，直到从黑名单解除。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('移出并拉黑'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    try {
                      await api.request(
                        'classes/members/${item['id']}',
                        method: 'DELETE',
                      );
                      refresh();
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    }
                  }
                } else if (action == 'reset') {
                  final pass = await _promptPassword(context);
                  if (pass != null) {
                    final proof = await AccountApi.newPasswordProof(pass);
                    await api.request(
                      'accounts/${item['id']}',
                      method: 'PATCH',
                      body: {
                        'resetSalt': proof['salt'],
                        'resetIterations': proof['iterations'],
                        'resetVerifier': proof['verifier'],
                      },
                    );
                  }
                } else if (action == 'disable') {
                  await api.request(
                    'accounts/${item['id']}',
                    method: 'PATCH',
                    body: {'disabled': !(item['disabled'] == true)},
                  );
                }
                refresh();
              },
              itemBuilder: (_) => canRemoveStudent
                  ? const [
                      PopupMenuItem(
                        value: 'remove_student',
                        child: Text('移出班级并加入黑名单'),
                      ),
                    ]
                  : [
                      PopupMenuItem(
                        value: 'disable',
                        child: Text(item['disabled'] == true ? '启用账号' : '停用账号'),
                      ),
                      const PopupMenuItem(
                        value: 'reset',
                        child: Text('重置初始密码'),
                      ),
                    ],
            )
          : const Icon(Icons.account_circle_outlined),
      children: [
        for (final child in (item['children'] as List<dynamic>? ?? []))
          _AccountTreeNode(
            api: api,
            item: child as Map<String, dynamic>,
            canManage: false,
            refresh: refresh,
          ),
      ],
    );
  }
}

class _NewAccountData {
  const _NewAccountData(this.username, this.name, this.password);
  final String username, name, password;
}

class _CreateAccountDialog extends StatefulWidget {
  const _CreateAccountDialog({required this.role});
  final String role;
  @override
  State<_CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends State<_CreateAccountDialog> {
  final _form = GlobalKey<FormState>();
  final _u = TextEditingController(),
      _n = TextEditingController(),
      _p = TextEditingController();
  @override
  void dispose() {
    _u.dispose();
    _n.dispose();
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('创建${_roleNames[widget.role]}'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _u,
            decoration: const InputDecoration(labelText: '用户名'),
            validator: (v) =>
                (v == null || v.trim().length < 3) ? '至少 3 个字符' : null,
          ),
          TextFormField(
            controller: _n,
            decoration: const InputDecoration(labelText: '姓名/显示名称'),
          ),
          TextFormField(
            controller: _p,
            obscureText: true,
            decoration: const InputDecoration(labelText: '初始密码（至少 8 位）'),
            validator: (v) => (v == null || v.length < 8) ? '至少 8 位' : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              _NewAccountData(_u.text.trim(), _n.text.trim(), _p.text),
            );
          }
        },
        child: const Text('创建'),
      ),
    ],
  );
}

class _ClassManagement extends StatefulWidget {
  const _ClassManagement({required this.api});
  final AccountApi api;
  @override
  State<_ClassManagement> createState() => _ClassManagementState();
}

class _ClassManagementState extends State<_ClassManagement> {
  List<dynamic> _classes = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await widget.api.request('classes');
      if (mounted) {
        setState(() => _classes = v['classes'] as List<dynamic>? ?? []);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '班级',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: '创建班级',
                onPressed: _create,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          for (final c in _classes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(c['name'] as String),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: '管理黑名单',
                    icon: const Icon(Icons.block),
                    onPressed: () => _showBlacklist(c as Map<String, dynamic>),
                  ),
                  IconButton(
                    tooltip: '显示入班二维码',
                    icon: const Icon(Icons.qr_code_2),
                    onPressed: () => _showQr(c as Map<String, dynamic>),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
  Future<void> _create() async {
    final name = await _textDialog(context, '创建班级', '班级名称');
    if (name == null) return;
    try {
      await widget.api.request('classes', method: 'POST', body: {'name': name});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _showQr(Map<String, dynamic> c) async {
    try {
      final r = await widget.api.request(
        'classes/join-code',
        method: 'POST',
        body: {'classId': c['id']},
      );
      final code = r['code'];
      if (code is! String || code.isEmpty) {
        throw const FormatException('服务器未返回有效的班级入班码');
      }
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => ClassJoinCodeDialog(
          className: c['name'] as String? ?? '班级',
          code: code,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _showBlacklist(Map<String, dynamic> c) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ClassBlacklistDialog(
        api: widget.api,
        classId: c['id'] as String,
        className: c['name'] as String? ?? '班级',
      ),
    );
  }
}

class _ClassBlacklistDialog extends StatefulWidget {
  const _ClassBlacklistDialog({
    required this.api,
    required this.classId,
    required this.className,
  });

  final AccountApi api;
  final String classId;
  final String className;

  @override
  State<_ClassBlacklistDialog> createState() => _ClassBlacklistDialogState();
}

class _ClassBlacklistDialogState extends State<_ClassBlacklistDialog> {
  List<dynamic> _students = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.request(
        'classes/${widget.classId}/blacklist',
      );
      if (mounted) {
        setState(() {
          _students = result['students'] as List<dynamic>? ?? [];
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 460,
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.className}黑名单',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            if (!_loading && _error == null && _students.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('黑名单为空', textAlign: TextAlign.center),
              ),
            if (!_loading && _students.isNotEmpty)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final raw in _students)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(raw['displayName'] as String? ?? '学生'),
                        subtitle: Text(raw['username'] as String? ?? ''),
                        trailing: TextButton(
                          onPressed: () => _remove(raw as Map<String, dynamic>),
                          child: const Text('解除'),
                        ),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _remove(Map<String, dynamic> student) async {
    try {
      await widget.api.request(
        'classes/${widget.classId}/blacklist/${student['studentId']}',
        method: 'DELETE',
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _ChangePassword extends StatefulWidget {
  const _ChangePassword({required this.api, required this.onChanged});
  final AccountApi api;
  final VoidCallback onChanged;
  @override
  State<_ChangePassword> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<_ChangePassword> {
  final _old = TextEditingController();
  final _next = TextEditingController();

  @override
  void dispose() {
    _old.dispose();
    _next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: const Text('修改密码'),
      childrenPadding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _old,
          obscureText: true,
          decoration: const InputDecoration(labelText: '当前密码'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _next,
          obscureText: true,
          decoration: const InputDecoration(labelText: '新密码（至少 8 位）'),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: () async {
            try {
              final username =
                  (await widget.api.request('me'))['account']['username']
                      as String;
              final parameters = await widget.api.passwordParameters(username);
              final oldVerifier = await AccountApi.deriveVerifier(
                _old.text,
                parameters['salt'] as String,
                parameters['iterations'] as int,
              );
              final newProof = await AccountApi.newPasswordProof(_next.text);
              await widget.api.request(
                'me/password',
                method: 'POST',
                body: {
                  'oldVerifier': oldVerifier,
                  'newSalt': newProof['salt'],
                  'newIterations': newProof['iterations'],
                  'newVerifier': newProof['verifier'],
                },
              );
              await widget.api.clearToken();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('密码已修改，请重新登录')));
              }
              widget.onChanged();
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error.toString())));
              }
            }
          },
          child: const Text('保存新密码'),
        ),
      ],
    ),
  );
}

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();
  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  bool _handled = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫描班级二维码')),
    body: MobileScanner(
      onDetect: (capture) {
        if (_handled) return;
        final value = capture.barcodes.firstOrNull?.rawValue;
        if (value == null || value.isEmpty) return;
        _handled = true;
        Navigator.of(context).pop(value);
      },
    ),
  );
}

Future<String?> _textDialog(
  BuildContext context,
  String title,
  String label,
) async {
  final controller = TextEditingController();
  final value = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  controller.dispose();
  return value;
}

Future<String?> _requestJoinCode(BuildContext context) async {
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('输入入班码'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        decoration: InputDecoration(
          labelText: '二维码内容或入班码',
          hintText: '可粘贴 join: 开头的完整内容',
          suffixIcon: IconButton(
            tooltip: '粘贴',
            icon: const Icon(Icons.content_paste),
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text case final text?) {
                controller.text = text.trim();
                controller.selection = TextSelection.collapsed(
                  offset: controller.text.length,
                );
              }
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: const Text('加入班级'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (code == null || code.trim().isEmpty) return null;
  return code.trim();
}

Future<String?> _promptPassword(BuildContext context) =>
    _textDialog(context, '重置初始密码', '至少 8 位');
