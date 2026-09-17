enum PetSpecies { dog, cat }

enum PetExpression { happy, wink, starry, radiant }

enum PetCelebrationType { lesson, unit }

class PetProfile {
  const PetProfile({
    this.species = PetSpecies.dog,
    this.breed = 'default',
    this.growthPoints = 0,
    this.majorStage = 0,
    this.claimedEvents = const {},
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
  );

  final PetSpecies species;
  final String breed;
  final int growthPoints;
  final int majorStage;
  final Set<String> claimedEvents;

  Map<String, dynamic> toJson() => {
    'species': species.name,
    'breed': breed,
    'growth_points': growthPoints,
    'major_stage': majorStage,
    'claimed_events': claimedEvents.toList()..sort(),
  };

  PetProfile copyWith({
    int? growthPoints,
    int? majorStage,
    Set<String>? claimedEvents,
  }) => PetProfile(
    species: species,
    breed: breed,
    growthPoints: growthPoints ?? this.growthPoints,
    majorStage: majorStage ?? this.majorStage,
    claimedEvents: claimedEvents ?? this.claimedEvents,
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
