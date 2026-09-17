enum PetSpecies { dog, cat }

enum PetExpression { happy, wink, starry, radiant }

enum PetCelebrationType { lesson, unit }

class PetBreed {
  const PetBreed({
    required this.id,
    required this.name,
    required this.species,
    required this.unlockStage,
    required this.coat,
    required this.marking,
    required this.earDrop,
  });
  final String id, name;
  final PetSpecies species;
  final int unlockStage;
  final int coat, marking;
  final double earDrop;
}

class PetDecoration {
  const PetDecoration({
    required this.id,
    required this.name,
    required this.unlockStage,
    this.color = 0xffe85d75,
    this.background = 0x00000000,
  });
  final String id, name;
  final int unlockStage, color, background;
}

const petBreeds = <PetBreed>[
  PetBreed(
    id: 'default',
    name: '小狗',
    species: PetSpecies.dog,
    unlockStage: 0,
    coat: 0xffd89955,
    marking: 0xff8d552f,
    earDrop: .85,
  ),
  PetBreed(
    id: 'shiba',
    name: '柴犬',
    species: PetSpecies.dog,
    unlockStage: 1,
    coat: 0xffd98245,
    marking: 0xff6e3f27,
    earDrop: .1,
  ),
  PetBreed(
    id: 'corgi',
    name: '柯基',
    species: PetSpecies.dog,
    unlockStage: 2,
    coat: 0xffe9a45d,
    marking: 0xffb96d38,
    earDrop: 1.3,
  ),
  PetBreed(
    id: 'golden',
    name: '金毛',
    species: PetSpecies.dog,
    unlockStage: 3,
    coat: 0xffefc15b,
    marking: 0xffb47b28,
    earDrop: .8,
  ),
  PetBreed(
    id: 'tabby',
    name: '狸花猫',
    species: PetSpecies.cat,
    unlockStage: 4,
    coat: 0xffa87552,
    marking: 0xff593b32,
    earDrop: -.5,
  ),
];

const petDecorations = <PetDecoration>[
  PetDecoration(id: 'none', name: '清爽', unlockStage: 0, color: 0x00000000),
  PetDecoration(
    id: 'blue-collar',
    name: '蓝色项圈',
    unlockStage: 1,
    color: 0xff3d9be9,
  ),
  PetDecoration(
    id: 'red-scarf',
    name: '红围巾',
    unlockStage: 2,
    color: 0xffe85d75,
  ),
  PetDecoration(
    id: 'meadow',
    name: '草地背景',
    unlockStage: 3,
    background: 0xffd8f3dc,
  ),
  PetDecoration(
    id: 'star-bandana',
    name: '星星头巾',
    unlockStage: 4,
    color: 0xffffb703,
  ),
];

PetBreed petBreed(String id) =>
    petBreeds.firstWhere((b) => b.id == id, orElse: () => petBreeds.first);
PetDecoration petDecoration(String id) => petDecorations.firstWhere(
  (d) => d.id == id,
  orElse: () => petDecorations.first,
);

class PetProfile {
  const PetProfile({
    this.species = PetSpecies.dog,
    this.breed = 'default',
    this.growthPoints = 0,
    this.majorStage = 0,
    this.claimedEvents = const {},
    this.unlockedBreeds = const {'default'},
    this.unlockedDecorations = const {'none'},
    this.selectedDecoration = 'none',
  });

  factory PetProfile.fromJson(Map<String, dynamic> json) => PetProfile(
    species: PetSpecies.values.firstWhere(
      (value) => value.name == json['species'],
      orElse: () => PetSpecies.dog,
    ),
    breed: json['breed'] is String ? json['breed'] as String : 'default',
    growthPoints: json['growth_points'] is int
        ? json['growth_points'] as int
        : 0,
    majorStage: json['major_stage'] is int ? json['major_stage'] as int : 0,
    claimedEvents: json['claimed_events'] is List
        ? (json['claimed_events'] as List).whereType<String>().toSet()
        : const {},
    unlockedBreeds: {
      ...(json['unlocked_breeds'] is List
          ? (json['unlocked_breeds'] as List).whereType<String>()
          : const <String>[]),
      'default',
    },
    unlockedDecorations: {
      ...(json['unlocked_decorations'] is List
          ? (json['unlocked_decorations'] as List).whereType<String>()
          : const <String>[]),
      'none',
    },
    selectedDecoration: json['selected_decoration'] is String
        ? json['selected_decoration'] as String
        : 'none',
  );

  final PetSpecies species;
  final String breed;
  final int growthPoints;
  final int majorStage;
  final Set<String> claimedEvents;
  final Set<String> unlockedBreeds;
  final Set<String> unlockedDecorations;
  final String selectedDecoration;

  Map<String, dynamic> toJson() => {
    'species': species.name,
    'breed': breed,
    'growth_points': growthPoints,
    'major_stage': majorStage,
    'claimed_events': claimedEvents.toList()..sort(),
    'unlocked_breeds': unlockedBreeds.toList()..sort(),
    'unlocked_decorations': unlockedDecorations.toList()..sort(),
    'selected_decoration': selectedDecoration,
  };

  PetProfile copyWith({
    int? growthPoints,
    int? majorStage,
    Set<String>? claimedEvents,
    String? breed,
    PetSpecies? species,
    Set<String>? unlockedBreeds,
    Set<String>? unlockedDecorations,
    String? selectedDecoration,
  }) => PetProfile(
    species: species ?? this.species,
    breed: breed ?? this.breed,
    growthPoints: growthPoints ?? this.growthPoints,
    majorStage: majorStage ?? this.majorStage,
    claimedEvents: claimedEvents ?? this.claimedEvents,
    unlockedBreeds: unlockedBreeds ?? this.unlockedBreeds,
    unlockedDecorations: unlockedDecorations ?? this.unlockedDecorations,
    selectedDecoration: selectedDecoration ?? this.selectedDecoration,
  );
}

class PetCelebration {
  const PetCelebration.lesson({required this.title, required this.threshold})
    : type = PetCelebrationType.lesson,
      unitName = null;

  const PetCelebration.unit({required this.unitName})
    : type = PetCelebrationType.unit,
      title = null,
      threshold = null;

  final PetCelebrationType type;
  final String? title;
  final String? unitName;
  final int? threshold;

  PetExpression get expression => switch (threshold) {
    80 => PetExpression.wink,
    90 => PetExpression.starry,
    100 => PetExpression.radiant,
    _ => PetExpression.happy,
  };
}
