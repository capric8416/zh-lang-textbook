import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zh_textbook/models/pet.dart';
import 'package:zh_textbook/services/account_api.dart';
import 'package:zh_textbook/services/local_study_identity.dart';
import 'package:zh_textbook/services/pet_growth.dart';
import 'package:zh_textbook/services/practice_progress.dart';
import 'package:zh_textbook/services/study_state_sync.dart';

class StudyStateApi extends AccountApi {
  Map<String, dynamic> state;
  int conflictCount;
  int putCount = 0;

  StudyStateApi(this.state, {this.conflictCount = 0});

  @override
  bool get configured => true;
  @override
  Future<String?> get token async => 'token';
  @override
  Future<String?> get accountId async => 'student-a';

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    Map<String, String>? queryParameters,
    bool authenticated = true,
    String? tokenOverride,
  }) async {
    if (path == 'me/study-state') return Map<String, dynamic>.from(state);
    expect(path, 'me/pet-profile');
    expect(method, 'PUT');
    putCount++;
    if (conflictCount-- > 0) {
      throw const AccountApiException('conflict', statusCode: 409);
    }
    final revision = (body!['baseRevision'] as int) + 1;
    state = {...state, 'petProfile': body['profile'], 'petRevision': revision};
    return {'petProfile': body['profile'], 'petRevision': revision};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const accountId = 'student-a';
  final namespace = LocalStudyIdentity.accountNamespace(accountId);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('restores progress and pet profile on a fresh device', () async {
    final remotePet = const PetProfile(
      name: '团团',
      species: PetSpecies.cat,
      breed: 'cat',
      growthPoints: 120,
      majorStage: 2,
      claimedEvents: {'question:book:q1'},
    );
    final api = StudyStateApi({
      'progress': [
        {
          'textbookKey': 'book',
          'questionKey': 'q1:writeHanzi',
          'correctCount': 3,
          'wrongCount': 1,
          'lastCorrectAt': '2026-10-21T02:00:00.000Z',
          'lastWrongAt': '2026-10-20T02:00:00.000Z',
        },
      ],
      'petProfile': remotePet.toJson(),
      'petRevision': 4,
    });

    await StudyStateSync.synchronize(api: api);

    final progress = await PracticeProgressStore.open(
      'book',
      namespace: namespace,
    );
    final question = progress.progress.forQuestion('q1:writeHanzi');
    expect(question.correctCount, 3);
    expect(question.wrongCount, 1);
    final pet = await PetGrowthStore.open(namespace: namespace);
    expect(pet.profile.name, '团团');
    expect(pet.profile.species, PetSpecies.cat);
    expect(pet.profile.growthPoints, 120);
    expect(pet.syncRevision, 4);
    expect(pet.dirty, isFalse);
    expect(api.putCount, 0);
  });

  test(
    'uploads local pet changes and retries an optimistic conflict',
    () async {
      final api = StudyStateApi({
        'progress': <Object>[],
        'petProfile': const PetProfile(growthPoints: 100).toJson(),
        'petRevision': 2,
      }, conflictCount: 1);
      await StudyStateSync.synchronize(api: api);
      final pet = await PetGrowthStore.open(namespace: namespace);
      expect(await pet.rename('星星'), isTrue);

      await StudyStateSync.synchronize(api: api);

      final restored = await PetGrowthStore.open(namespace: namespace);
      expect(restored.profile.name, '星星');
      expect(restored.profile.growthPoints, 100);
      expect(restored.syncRevision, 3);
      expect(restored.dirty, isFalse);
      expect(api.putCount, 2);
    },
  );

  test('remote progress never reduces newer local counters', () async {
    final local = await PracticeProgressStore.open(
      'book',
      namespace: namespace,
    );
    await local.recordAt(
      'q1:writeHanzi',
      correct: true,
      occurredAt: DateTime.utc(2026, 10, 22),
    );
    await local.recordAt(
      'q1:writeHanzi',
      correct: true,
      occurredAt: DateTime.utc(2026, 10, 23),
    );
    final api = StudyStateApi({
      'progress': [
        {
          'textbookKey': 'book',
          'questionKey': 'q1:writeHanzi',
          'correctCount': 1,
          'wrongCount': 0,
          'lastCorrectAt': '2026-10-21T00:00:00.000Z',
          'lastWrongAt': null,
        },
      ],
      'petProfile': null,
      'petRevision': 0,
    });

    await StudyStateSync.synchronize(api: api);

    final restored = await PracticeProgressStore.open(
      'book',
      namespace: namespace,
    );
    expect(restored.progress.forQuestion('q1:writeHanzi').correctCount, 2);
  });
}
