import 'pet.dart';
import 'pet_mission.dart';
import 'quick_practice.dart';

enum EngagementEventType {
  companionSurfaceViewed,
  invitationPresented,
  quickPracticeStarted,
  quickPracticeExited,
  quickPracticeCompleted,
  repeatPracticeStarted,
  nextDayReturn,
}

enum EngagementDeliveryState { pending, acknowledged }

enum EngagementSurface { modePage, petHome, quickPractice }

enum EngagementLaunchSource { invitation, furniture, repeat }

enum EngagementDurationBucket {
  underMinute,
  oneToThreeMinutes,
  overThreeMinutes,
}

class EngagementEventContext {
  const EngagementEventContext({
    this.textbookKey,
    this.surface,
    this.launchSource,
    this.quickPracticeAction,
    this.missionKind,
    this.roomId,
    this.furnitureId,
    this.durationBucket,
    this.flowId,
    this.parentFlowId,
  });

  factory EngagementEventContext.fromJson(Map<String, dynamic> json) =>
      EngagementEventContext(
        textbookKey: _string(json['textbook_key']),
        surface: _enumValue(EngagementSurface.values, json['surface']),
        launchSource: _enumValue(
          EngagementLaunchSource.values,
          json['launch_source'],
        ),
        quickPracticeAction: _enumValue(
          QuickPracticeAction.values,
          json['quick_practice_action'],
        ),
        missionKind: _enumValue(PetMissionKind.values, json['mission_kind']),
        roomId: _knownRoom(json['room_id']),
        furnitureId: _knownFurniture(json['furniture_id']),
        durationBucket: _enumValue(
          EngagementDurationBucket.values,
          json['duration_bucket'],
        ),
        flowId: _opaqueId(json['flow_id']),
        parentFlowId: _opaqueId(json['parent_flow_id']),
      );

  final String? textbookKey;
  final EngagementSurface? surface;
  final EngagementLaunchSource? launchSource;
  final QuickPracticeAction? quickPracticeAction;
  final PetMissionKind? missionKind;
  final String? roomId;
  final String? furnitureId;
  final EngagementDurationBucket? durationBucket;
  final String? flowId;
  final String? parentFlowId;

  Map<String, dynamic> toJson() => {
    if (textbookKey != null) 'textbook_key': textbookKey,
    if (surface != null) 'surface': surface!.name,
    if (launchSource != null) 'launch_source': launchSource!.name,
    if (quickPracticeAction != null)
      'quick_practice_action': quickPracticeAction!.name,
    if (missionKind != null) 'mission_kind': missionKind!.name,
    if (roomId != null) 'room_id': roomId,
    if (furnitureId != null) 'furniture_id': furnitureId,
    if (durationBucket != null) 'duration_bucket': durationBucket!.name,
    if (flowId != null) 'flow_id': flowId,
    if (parentFlowId != null) 'parent_flow_id': parentFlowId,
  };

  static T? _enumValue<T extends Enum>(List<T> values, Object? raw) =>
      raw is String
      ? values.where((value) => value.name == raw).firstOrNull
      : null;

  static String? _string(Object? value) {
    if (value is! String || value.isEmpty || value.length > 128) return null;
    return value;
  }

  static String? _opaqueId(Object? value) {
    if (value is! String || value.isEmpty || value.length > 64) return null;
    return value;
  }

  static String? _knownRoom(Object? value) =>
      value is String && petRooms.any((room) => room.id == value)
      ? value
      : null;

  static String? _knownFurniture(Object? value) =>
      value is String && isKnownFurnitureId(value) ? value : null;
}

class EngagementEvent {
  const EngagementEvent({
    required this.eventId,
    required this.schemaVersion,
    required this.type,
    required this.occurredAtUtc,
    required this.localDate,
    required this.anonymousInstallId,
    required this.sessionId,
    required this.sequence,
    required this.context,
    this.deliveryState = EngagementDeliveryState.pending,
    this.attemptCount = 0,
  });

  static const currentSchemaVersion = 1;

  factory EngagementEvent.fromJson(Map<String, dynamic> json) {
    final occurredAtRaw = json['occurred_at_utc'];
    final occurredAt = occurredAtRaw is String
        ? DateTime.tryParse(occurredAtRaw)
        : null;
    final type = EngagementEventContext._enumValue(
      EngagementEventType.values,
      json['event_type'],
    );
    final delivery = EngagementEventContext._enumValue(
      EngagementDeliveryState.values,
      json['delivery_state'],
    );
    final context = json['context'];
    if (occurredAt == null ||
        type == null ||
        json['event_id'] is! String ||
        (json['event_id'] as String).isEmpty ||
        json['anonymous_install_id'] is! String ||
        (json['anonymous_install_id'] as String).isEmpty ||
        json['session_id'] is! String ||
        (json['session_id'] as String).isEmpty ||
        json['sequence'] is! int ||
        context is! Map) {
      throw const FormatException('Invalid engagement event');
    }
    return EngagementEvent(
      eventId: json['event_id'] as String,
      schemaVersion: json['schema_version'] is int
          ? json['schema_version'] as int
          : currentSchemaVersion,
      type: type,
      occurredAtUtc: occurredAt.toUtc(),
      localDate: json['local_date'] is String
          ? json['local_date'] as String
          : _date(occurredAt.toLocal()),
      anonymousInstallId: json['anonymous_install_id'] as String,
      sessionId: json['session_id'] as String,
      sequence: json['sequence'] as int,
      context: EngagementEventContext.fromJson(context.cast<String, dynamic>()),
      deliveryState: delivery ?? EngagementDeliveryState.pending,
      attemptCount: json['attempt_count'] is int
          ? json['attempt_count'] as int
          : 0,
    );
  }

  final String eventId;
  final int schemaVersion;
  final EngagementEventType type;
  final DateTime occurredAtUtc;
  final String localDate;
  final String anonymousInstallId;
  final String sessionId;
  final int sequence;
  final EngagementEventContext context;
  final EngagementDeliveryState deliveryState;
  final int attemptCount;

  Map<String, dynamic> toJson() => {
    'event_id': eventId,
    'schema_version': schemaVersion,
    'event_type': type.name,
    'occurred_at_utc': occurredAtUtc.toUtc().toIso8601String(),
    'local_date': localDate,
    'anonymous_install_id': anonymousInstallId,
    'session_id': sessionId,
    'sequence': sequence,
    'context': context.toJson(),
    'delivery_state': deliveryState.name,
    'attempt_count': attemptCount,
  };

  EngagementEvent copyWith({
    EngagementDeliveryState? deliveryState,
    int? attemptCount,
  }) => EngagementEvent(
    eventId: eventId,
    schemaVersion: schemaVersion,
    type: type,
    occurredAtUtc: occurredAtUtc,
    localDate: localDate,
    anonymousInstallId: anonymousInstallId,
    sessionId: sessionId,
    sequence: sequence,
    context: context,
    deliveryState: deliveryState ?? this.deliveryState,
    attemptCount: attemptCount ?? this.attemptCount,
  );

  static String localDateFor(DateTime value) => _date(value.toLocal());

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
