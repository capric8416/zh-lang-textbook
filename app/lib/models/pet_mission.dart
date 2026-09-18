import 'pet.dart';
import 'quick_practice.dart';

enum PetMissionKind {
  studyDesk,
  lightLamp,
  fillBookcase,
  bloomFlower,
  tidyToys,
}

enum PetMissionSource { invitation, furniture }

class PetCompanionMission {
  const PetCompanionMission({
    required this.kind,
    required this.source,
    required this.title,
    required this.intro,
    required this.steps,
    required this.completion,
    required this.targetFurnitureId,
  }) : assert(steps.length == 3);

  factory PetCompanionMission.forQuickPractice({
    required QuickPracticeAction action,
    required String petName,
    String? furnitureId,
    Set<String>? unlockedFurniture,
  }) {
    var kind = _kindFor(furnitureId, action);
    if (furnitureId == null &&
        unlockedFurniture != null &&
        !unlockedFurniture.contains(_furnitureFor(kind))) {
      kind = PetMissionKind.studyDesk;
    }
    final target = furnitureId ?? _furnitureFor(kind);
    final source = furnitureId == null
        ? PetMissionSource.invitation
        : PetMissionSource.furniture;
    return switch (kind) {
      PetMissionKind.studyDesk => PetCompanionMission(
        kind: kind,
        source: source,
        title: '布置学习桌',
        intro: '$petName想和你完成三题，把学习桌整理好。',
        steps: const ['摆好第一件文具', '放好练习本', '学习桌整理好啦'],
        completion: '学习桌已经准备好啦！',
        targetFurnitureId: target,
      ),
      PetMissionKind.lightLamp => PetCompanionMission(
        kind: kind,
        source: source,
        title: '点亮小台灯',
        intro: '$petName想和你完成三题，把小台灯点亮。',
        steps: const ['擦亮灯罩', '接好灯线', '小台灯亮起来啦'],
        completion: '小台灯亮起来了！',
        targetFurnitureId: target,
      ),
      PetMissionKind.fillBookcase => PetCompanionMission(
        kind: kind,
        source: source,
        title: '装满小书柜',
        intro: '$petName想和你完成三题，为书柜找三本书。',
        steps: const ['放入第一本书', '放入第二本书', '小书柜装好啦'],
        completion: '小书柜多了三本书！',
        targetFurnitureId: target,
      ),
      PetMissionKind.bloomFlower => PetCompanionMission(
        kind: kind,
        source: source,
        title: '让花儿开放',
        intro: '$petName想听你完成三题，让小花慢慢开放。',
        steps: const ['花苗探出头', '长出一片新叶', '小花开放啦'],
        completion: '花盆里开出了一朵小花！',
        targetFurnitureId: target,
      ),
      PetMissionKind.tidyToys => PetCompanionMission(
        kind: kind,
        source: source,
        title: '整理玩具箱',
        intro: '$petName想和你完成三题，把玩具整理好。',
        steps: const ['收好一个玩具', '再收好一个玩具', '玩具箱整理好啦'],
        completion: '玩具箱变得整整齐齐！',
        targetFurnitureId: target,
      ),
    };
  }

  final PetMissionKind kind;
  final PetMissionSource source;
  final String title;
  final String intro;
  final List<String> steps;
  final String completion;
  final String targetFurnitureId;

  static PetMissionKind _kindFor(
    String? furnitureId,
    QuickPracticeAction action,
  ) => switch (furnitureId) {
    'desk-lamp' => PetMissionKind.lightLamp,
    'bookcase' => PetMissionKind.fillBookcase,
    'flower-pot' => PetMissionKind.bloomFlower,
    'toy-box' => PetMissionKind.tidyToys,
    _ => switch (action) {
      QuickPracticeAction.characters => PetMissionKind.lightLamp,
      QuickPracticeAction.readAloud => PetMissionKind.bloomFlower,
      QuickPracticeAction.mistakeFirst => PetMissionKind.tidyToys,
      QuickPracticeAction.mixedReview => PetMissionKind.fillBookcase,
    },
  };

  static String _furnitureFor(PetMissionKind kind) => switch (kind) {
    PetMissionKind.studyDesk => 'study-desk',
    PetMissionKind.lightLamp => 'desk-lamp',
    PetMissionKind.fillBookcase => 'bookcase',
    PetMissionKind.bloomFlower => 'flower-pot',
    PetMissionKind.tidyToys => 'toy-box',
  };
}

String petMissionKindLabel(PetMissionKind kind) => switch (kind) {
  PetMissionKind.studyDesk => '整理学习桌',
  PetMissionKind.lightLamp => '点亮台灯',
  PetMissionKind.fillBookcase => '整理书柜',
  PetMissionKind.bloomFlower => '照顾花朵',
  PetMissionKind.tidyToys => '整理玩具',
};

bool isKnownFurnitureId(String id) => petFurniture.any((item) => item.id == id);

class QuickPracticeLaunch {
  const QuickPracticeLaunch({
    required this.mission,
    required this.flowId,
    required this.source,
    this.parentFlowId,
    this.roomId,
    this.furnitureId,
  });

  final PetCompanionMission mission;
  final String flowId;
  final PetMissionSource source;
  final String? parentFlowId;
  final String? roomId;
  final String? furnitureId;

  QuickPracticeLaunch repeat({required String nextFlowId}) =>
      QuickPracticeLaunch(
        mission: mission,
        flowId: nextFlowId,
        source: PetMissionSource.invitation,
        parentFlowId: flowId,
        roomId: roomId,
        furnitureId: furnitureId,
      );
}
