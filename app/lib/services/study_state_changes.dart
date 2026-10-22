import 'package:flutter/foundation.dart';

class StudyStateChanges {
  StudyStateChanges._();

  static final ValueNotifier<int> petProfile = ValueNotifier(0);

  static void petProfileChanged() => petProfile.value++;
}
