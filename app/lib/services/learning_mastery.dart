import '../models/practice.dart';
import '../models/textbook.dart';
import 'practice_progress.dart';

const lessonMilestones = [60, 80, 90, 100];

class LessonMastery {
  const LessonMastery({
    required this.chapterId,
    required this.chapterName,
    required this.questions,
    required this.masteredQuestionIds,
  });

  final String chapterId;
  final String chapterName;
  final List<PracticeQuestion> questions;
  final Set<String> masteredQuestionIds;

  int get masteredCount => masteredQuestionIds.length;
  int get totalCount => questions.length;
  bool get isEligible => totalCount > 0;
  int get percentage => isEligible ? masteredCount * 100 ~/ totalCount : 0;
  bool reaches(int threshold) =>
      isEligible && masteredCount * 100 >= totalCount * threshold;
  bool get isPassed => reaches(60);
  bool get isComplete => reaches(100);
}

class UnitMastery {
  const UnitMastery({
    required this.unitId,
    required this.unitName,
    required this.lessons,
  });

  final String unitId;
  final String unitName;
  final List<LessonMastery> lessons;

  List<LessonMastery> get eligibleLessons =>
      lessons.where((lesson) => lesson.isEligible).toList(growable: false);

  bool get isComplete =>
      eligibleLessons.isNotEmpty &&
      eligibleLessons.every((lesson) => lesson.isPassed);
}

class TextbookMastery {
  const TextbookMastery(this.units);

  final List<UnitMastery> units;

  Iterable<LessonMastery> get lessons => units.expand((unit) => unit.lessons);

  LessonMastery? get nextIncompleteLesson {
    for (final lesson in lessons) {
      if (lesson.isEligible && !lesson.isComplete) return lesson;
    }
    return null;
  }

  bool get isComplete {
    final eligibleUnits = units
        .where((unit) => unit.eligibleLessons.isNotEmpty)
        .toList(growable: false);
    return eligibleUnits.isNotEmpty &&
        eligibleUnits.every((unit) => unit.isComplete);
  }
}

TextbookMastery calculateTextbookMastery({
  required Textbook textbook,
  required PracticeCatalog catalog,
  required PracticeProgress progress,
}) {
  final units = <UnitMastery>[];
  for (final unit in textbook.index.where((item) => item.id != 'appendix')) {
    final lessons = <LessonMastery>[];
    for (final chapter in unit.chapters) {
      final uniqueQuestions = <String, PracticeQuestion>{
        for (final question in catalog.forChapter(chapter.id))
          question.id: question,
      }.values.toList(growable: false);
      final mastered = <String>{};
      for (final question in uniqueQuestions) {
        final isMastered = PracticeDirection.values
            .where(question.supportsDirection)
            .any(
              (direction) =>
                  progress
                      .forQuestion(question.attemptId(direction))
                      .correctCount >
                  0,
            );
        if (isMastered) mastered.add(question.id);
      }
      lessons.add(
        LessonMastery(
          chapterId: chapter.id,
          chapterName: chapter.name,
          questions: uniqueQuestions,
          masteredQuestionIds: mastered,
        ),
      );
    }
    units.add(
      UnitMastery(unitId: unit.id, unitName: unit.name, lessons: lessons),
    );
  }
  return TextbookMastery(units);
}
