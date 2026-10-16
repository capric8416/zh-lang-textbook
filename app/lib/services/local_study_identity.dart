import 'account_api.dart';

/// Identifies the local data partition for the active account.
class LocalStudyIdentity {
  LocalStudyIdentity._();

  static Future<String> currentNamespace({AccountApi? api}) async {
    final accountApi = api ?? AccountApi();
    final token = await accountApi.token;
    final accountId = await accountApi.accountId;
    if (token == null ||
        token.isEmpty ||
        accountId == null ||
        accountId.isEmpty) {
      throw StateError('请先登录后再访问学习资料');
    }
    return accountNamespace(accountId);
  }

  static String accountNamespace(String accountId) =>
      'account_${Uri.encodeComponent(accountId)}';
}
