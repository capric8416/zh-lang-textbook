import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/pet.dart';
import '../models/practice.dart';
import '../models/textbook.dart';
import 'learning_mastery.dart';
import 'practice_progress.dart';

class PetGrowthSyncResult {
  const PetGrowthSyncResult({
    required this.profile,
    required this.mastery,
    required this.celebrations,
    required this.changed,
  });

  final PetProfile profile;
  final TextbookMastery mastery;
  final List<PetCelebration> celebrations;
  final bool changed;
}

class PetGrowthEngine {
  const PetGrowthEngine._();

  static const questionPoints = 10;
  static const unitPoints = 100;
  static const milestonePoints = {60: 30, 80: 20, 90: 20, 100: 30};

  static Set<String> breedsForStage(int stage) =>
      petBreeds.where((b) => b.unlockStage <= stage).map((b) => b.id).toSet();
  static Set<String> decorationsForStage(int stage) => petDecorations
      .where((d) => d.unlockStage <= stage)
      .map((d) => d.id)
      .toSet();
  static Set<String> furnitureForStage(int stage) => petFurniture
      .where((item) => item.unlockStage <= stage)
      .map((item) => item.id)
      .toSet();

  static PetGrowthSyncResult synchronize({
    required PetProfile profile,
    required String textbookKey,
    required Textbook textbook,
    required PracticeCatalog catalog,
    required PracticeProgress progress,
    required bool emitCelebrations,
  }) {
    final mastery = calculateTextbookMastery(
      textbook: textbook,
      catalog: catalog,
      progress: progress,
    );
    final claimed = {...profile.claimedEvents};
    var points = profile.growthPoints;
    var majorStage = profile.majorStage;
    var changed = false;
    final lessonCelebrations = <PetCelebration>[];
    final unitCelebrations = <PetCelebration>[];

    for (final unit in mastery.units) {
      for (final lesson in unit.lessons) {
        for (final questionId in lesson.masteredQuestionIds) {
          final key = 'question:$textbookKey:$questionId';
          if (claimed.add(key)) {
            points += questionPoints;
            changed = true;
          }
        }

        int? highestNewMilestone;
        for (final threshold in lessonMilestones) {
          if (!lesson.reaches(threshold)) continue;
          final key = 'lesson:$textbookKey:${lesson.chapterId}:$threshold';
          if (claimed.add(key)) {
            points += milestonePoints[threshold]!;
            highestNewMilestone = threshold;
            changed = true;
          }
        }
        if (emitCelebrations && highestNewMilestone != null) {
          lessonCelebrations.add(
            PetCelebration.lesson(
              title: lesson.chapterName,
              threshold: highestNewMilestone,
            ),
          );
        }
      }

      if (unit.isComplete) {
        final key = 'unit:$textbookKey:${unit.unitId}';
        if (claimed.add(key)) {
          points += unitPoints;
          majorStage++;
          changed = true;
          if (emitCelebrations) {
            unitCelebrations.add(PetCelebration.unit(unitName: unit.unitName));
          }
        }
      }
    }

    final unlockedBreeds = {
      ...profile.unlockedBreeds,
      ...breedsForStage(majorStage),
    };
    final unlockedDecorations = {
      ...profile.unlockedDecorations,
      ...decorationsForStage(majorStage),
    };
    final unlockedFurniture = {
      ...profile.unlockedFurniture,
      ...furnitureForStage(majorStage),
    };
    final normalizedBreed = unlockedBreeds.contains(profile.breed)
        ? profile.breed
        : 'default';
    final normalizedDecoration =
        unlockedDecorations.contains(profile.selectedDecoration)
        ? profile.selectedDecoration
        : 'none';
    final normalizedRoom =
        petRooms.any((room) => room.id == profile.selectedRoom)
        ? profile.selectedRoom
        : 'living-room';
    changed =
        changed ||
        unlockedBreeds.length != profile.unlockedBreeds.length ||
        unlockedDecorations.length != profile.unlockedDecorations.length ||
        unlockedFurniture.length != profile.unlockedFurniture.length ||
        normalizedBreed != profile.breed ||
        normalizedDecoration != profile.selectedDecoration ||
        normalizedRoom != profile.selectedRoom;
    return PetGrowthSyncResult(
      profile: profile.copyWith(
        growthPoints: points,
        majorStage: majorStage,
        claimedEvents: claimed,
        unlockedBreeds: unlockedBreeds,
        unlockedDecorations: unlockedDecorations,
        breed: normalizedBreed,
        selectedDecoration: normalizedDecoration,
        selectedRoom: normalizedRoom,
        unlockedFurniture: unlockedFurniture,
      ),
      mastery: mastery,
      celebrations: [...lessonCelebrations, ...unitCelebrations],
      changed: changed,
    );
  }
}

class PetGrowthStore {
  PetGrowthStore._(this._preferences, this._profile);

  static const _key = 'pet_growth_profile';
  final SharedPreferences _preferences;
  PetProfile _profile;

  PetProfile get profile => _profile;

  Future<bool> selectBreed(String id) async {
    if (!_profile.unlockedBreeds.contains(id)) return false;
    final breed = petBreed(id);
    _profile = _profile.copyWith(breed: breed.id, species: breed.species);
    return _save();
  }

  Future<bool> selectDecoration(String id) async {
    if (!_profile.unlockedDecorations.contains(id)) return false;
    _profile = _profile.copyWith(selectedDecoration: id);
    return _save();
  }

  Future<bool> selectRoom(String id) async {
    if (!petRooms.any((room) => room.id == id)) return false;
    _profile = _profile.copyWith(selectedRoom: id);
    return _save();
  }

  Future<bool> _save() async => _preferences.setString(
    _key,
    jsonEncode({'version': 3, 'profile': _profile.toJson()}),
  );

  static Future<PetGrowthStore> open() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    try {
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PetGrowthStore._(
          preferences,
          PetProfile.fromJson(
            decoded['profile'] is Map
                ? (decoded['profile'] as Map).cast<String, dynamic>()
                : decoded,
          ),
        );
      }
    } on FormatException {
      // A malformed optional pet profile should not block learning.
    }
    return PetGrowthStore._(preferences, const PetProfile());
  }

  Future<PetGrowthSyncResult> synchronize({
    required String textbookKey,
    required Textbook textbook,
    required PracticeCatalog catalog,
    required PracticeProgress progress,
    required bool emitCelebrations,
  }) async {
    final result = PetGrowthEngine.synchronize(
      profile: _profile,
      textbookKey: textbookKey,
      textbook: textbook,
      catalog: catalog,
      progress: progress,
      emitCelebrations: emitCelebrations,
    );
    _profile = result.profile;
    if (result.changed) await _save();
    return result;
  }
}
