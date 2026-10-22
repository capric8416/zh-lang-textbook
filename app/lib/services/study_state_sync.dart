import 'dart:async';

import '../models/pet.dart';
import 'account_api.dart';
import 'local_study_identity.dart';
import 'pet_growth.dart';
import 'practice_progress.dart';
import 'study_state_changes.dart';

class StudyStateSync {
  StudyStateSync._();

  static AccountApi? _boundApi;
  static Timer? _timer;
  static bool _listening = false;
  static Future<void> _tail = Future<void>.value();

  static void bind(AccountApi api) {
    _boundApi = api;
    if (_listening) return;
    StudyStateChanges.petProfile.addListener(_scheduleBound);
    _listening = true;
  }

  static void unbind() {
    _boundApi = null;
    _timer?.cancel();
  }

  static void _scheduleBound() {
    final api = _boundApi;
    if (api == null) return;
    _timer?.cancel();
    _timer = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(synchronize(api: api).catchError((_) {})),
    );
  }

  static Future<void> synchronize({required AccountApi api}) {
    final operation = _tail.then((_) => _synchronize(api));
    _tail = operation.catchError((_) {});
    return operation;
  }

  static Future<void> _synchronize(AccountApi api) async {
    if (!api.configured) return;
    final accountId = await api.accountId;
    final token = await api.token;
    if (accountId == null || token == null || token.isEmpty) return;

    var state = await api
        .request('me/study-state', tokenOverride: token)
        .timeout(const Duration(seconds: 15));
    if (await api.accountId != accountId) return;
    final progress = (state['progress'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList();
    await PracticeProgressStore.restoreRemote(accountId, progress);

    final namespace = LocalStudyIdentity.accountNamespace(accountId);
    for (var attempt = 0; attempt < 3; attempt++) {
      final local = await PetGrowthStore.open(namespace: namespace);
      final revision = state['petRevision'] is int
          ? state['petRevision'] as int
          : 0;
      final remoteJson = state['petProfile'];
      if (remoteJson is Map) {
        final remote = PetProfile.fromJson(remoteJson.cast<String, dynamic>());
        if (!local.dirty) {
          if (await local.acceptRemote(
            remote,
            revision,
            expectedLocalRevision: local.localRevision,
          )) {
            return;
          }
          continue;
        }
        final merged = _mergeProfiles(remote, local.profile);
        try {
          final saved = await api
              .request(
                'me/pet-profile',
                method: 'PUT',
                tokenOverride: token,
                body: {'profile': merged.toJson(), 'baseRevision': revision},
              )
              .timeout(const Duration(seconds: 15));
          final accepted = await local.acceptRemote(
            PetProfile.fromJson(
              (saved['petProfile'] as Map).cast<String, dynamic>(),
            ),
            saved['petRevision'] as int,
            expectedLocalRevision: local.localRevision,
          );
          if (accepted) return;
          state = {
            ...state,
            'petProfile': saved['petProfile'],
            'petRevision': saved['petRevision'],
          };
          continue;
        } on AccountApiException catch (error) {
          if (error.statusCode != 409) rethrow;
          state = await api
              .request('me/study-state', tokenOverride: token)
              .timeout(const Duration(seconds: 15));
          continue;
        }
      }

      try {
        final saved = await api
            .request(
              'me/pet-profile',
              method: 'PUT',
              tokenOverride: token,
              body: {'profile': local.profile.toJson(), 'baseRevision': 0},
            )
            .timeout(const Duration(seconds: 15));
        final accepted = await local.acceptRemote(
          PetProfile.fromJson(
            (saved['petProfile'] as Map).cast<String, dynamic>(),
          ),
          saved['petRevision'] as int,
          expectedLocalRevision: local.localRevision,
        );
        if (accepted) return;
        state = {
          ...state,
          'petProfile': saved['petProfile'],
          'petRevision': saved['petRevision'],
        };
      } on AccountApiException catch (error) {
        if (error.statusCode != 409) rethrow;
        state = await api
            .request('me/study-state', tokenOverride: token)
            .timeout(const Duration(seconds: 15));
      }
    }
    throw const AccountApiException('宠物档案同步冲突，请稍后重试');
  }

  static PetProfile _mergeProfiles(PetProfile remote, PetProfile local) {
    final furnitureStates = {...remote.furnitureStates};
    for (final entry in local.furnitureStates.entries) {
      if (entry.value == FurnitureVisualState.active ||
          !furnitureStates.containsKey(entry.key)) {
        furnitureStates[entry.key] = entry.value;
      }
    }
    return local.copyWith(
      growthPoints: local.growthPoints > remote.growthPoints
          ? local.growthPoints
          : remote.growthPoints,
      majorStage: local.majorStage > remote.majorStage
          ? local.majorStage
          : remote.majorStage,
      claimedEvents: {...remote.claimedEvents, ...local.claimedEvents},
      unlockedBreeds: {...remote.unlockedBreeds, ...local.unlockedBreeds},
      unlockedDecorations: {
        ...remote.unlockedDecorations,
        ...local.unlockedDecorations,
      },
      unlockedFurniture: {
        ...remote.unlockedFurniture,
        ...local.unlockedFurniture,
      },
      furnitureStates: furnitureStates,
      lastVisitDate: _latestDate(remote.lastVisitDate, local.lastVisitDate),
    );
  }

  static String? _latestDate(String? first, String? second) {
    if (first == null) return second;
    if (second == null) return first;
    return first.compareTo(second) >= 0 ? first : second;
  }
}
