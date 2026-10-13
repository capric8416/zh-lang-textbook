import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/services/account_api.dart';

void main() {
  test(
    'PBKDF2-HMAC-SHA256 verifier uses UTF-8 password and base64 salt',
    () async {
      expect(
        await AccountApi.deriveVerifier('password', 'c2FsdA==', 1),
        'Eg+2z/z4syxD5yJSVsT4N6hlSMkszDVICAWYfLcL4Xs=',
      );
    },
  );
}
