import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/engagement_event.dart';

typedef EngagementIdFactory = String Function();
typedef EngagementClock = DateTime Function();

class EngagementEventStore {
  EngagementEventStore._({
    required this._preferences,
    required this._events,
    required this._anonymousInstallId,
    required this._sessionId,
    required this._sequence,
    required this._idFactory,
    required this._clock,
    required this._maxEvents,
    required this._retention,
  });

  static const storageKey = 'pet_engagement_event_log';
  static const maxEvents = 1000;
  static const retentionDays = 90;

  final SharedPreferences _preferences;
  List<EngagementEvent> _events;
  final String _anonymousInstallId;
  final String _sessionId;
  int _sequence;
  final EngagementIdFactory _idFactory;
  final EngagementClock _clock;
  final int _maxEvents;
  final Duration _retention;

  List<EngagementEvent> get events => List.unmodifiable(_events);
  String get anonymousInstallId => _anonymousInstallId;
  String get sessionId => _sessionId;
  String newId() => _idFactory();

  static Future<EngagementEventStore> open({
    EngagementIdFactory? idFactory,
    EngagementClock? clock,
    String? sessionId,
    int maxEventCount = maxEvents,
    Duration retention = const Duration(days: retentionDays),
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final makeId = idFactory ?? _randomId;
    final now = clock ?? DateTime.now;
    var installId = makeId();
    var sequence = 0;
    final events = <EngagementEvent>[];
    final raw = preferences.getString(storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = decoded.cast<String, dynamic>();
          if (map['anonymous_install_id'] case final String stored
              when stored.isNotEmpty) {
            installId = stored;
          }
          if (map['sequence'] is int) sequence = map['sequence'] as int;
          if (map['events'] is List) {
            for (final item in map['events'] as List) {
              try {
                if (item is Map) {
                  events.add(
                    EngagementEvent.fromJson(item.cast<String, dynamic>()),
                  );
                }
              } catch (_) {
                // A corrupt optional analytics record must not block learning.
              }
            }
          }
        }
      } catch (_) {
        // Start a fresh optional log when its container cannot be decoded.
      }
    }
    return EngagementEventStore._(
      preferences: preferences,
      events: events,
      anonymousInstallId: installId,
      sessionId: sessionId ?? makeId(),
      sequence: sequence,
      idFactory: makeId,
      clock: now,
      maxEvents: maxEventCount,
      retention: retention,
    );
  }

  Future<EngagementEvent> append({
    required EngagementEventType type,
    EngagementEventContext context = const EngagementEventContext(),
    String? eventId,
    DateTime? occurredAt,
  }) async {
    final id = eventId ?? _idFactory();
    final existing = _events.where((event) => event.eventId == id).firstOrNull;
    if (existing != null) return existing;
    final timestamp = occurredAt ?? _clock();
    final event = EngagementEvent(
      eventId: id,
      schemaVersion: EngagementEvent.currentSchemaVersion,
      type: type,
      occurredAtUtc: timestamp.toUtc(),
      localDate: EngagementEvent.localDateFor(timestamp),
      anonymousInstallId: _anonymousInstallId,
      sessionId: _sessionId,
      sequence: ++_sequence,
      context: context,
    );
    _events = _prune([..._events, event], timestamp);
    await _save();
    return event;
  }

  Future<void> acknowledge(Iterable<String> eventIds) async {
    final ids = eventIds.toSet();
    _events = [
      for (final event in _events)
        if (ids.contains(event.eventId))
          event.copyWith(deliveryState: EngagementDeliveryState.acknowledged)
        else
          event,
    ];
    await _save();
  }

  List<EngagementEvent> _prune(
    List<EngagementEvent> events,
    DateTime reference,
  ) {
    final cutoff = reference.toUtc().subtract(_retention);
    final retained =
        events.where((event) => !event.occurredAtUtc.isBefore(cutoff)).toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence));
    while (retained.length > _maxEvents) {
      final acknowledged = retained.indexWhere(
        (event) => event.deliveryState == EngagementDeliveryState.acknowledged,
      );
      retained.removeAt(acknowledged < 0 ? 0 : acknowledged);
    }
    return retained;
  }

  Future<bool> _save() => _preferences.setString(
    storageKey,
    jsonEncode({
      'version': 1,
      'anonymous_install_id': _anonymousInstallId,
      'sequence': _sequence,
      'events': [for (final event in _events) event.toJson()],
    }),
  );

  static String _randomId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}

class EngagementMetrics {
  const EngagementMetrics({
    required this.invitationClickThrough,
    required this.quickCompletion,
    required this.voluntaryRepeat,
    required this.nextDayReturn,
  });

  factory EngagementMetrics.fromEvents(Iterable<EngagementEvent> input) {
    final events = <String, EngagementEvent>{
      for (final event in input) event.eventId: event,
    }.values;
    Set<String> flows(EngagementEventType type) => events
        .where((event) => event.type == type)
        .map((event) => event.context.flowId ?? event.eventId)
        .toSet();

    final invitations = flows(EngagementEventType.invitationPresented);
    final invitationStarts = events
        .where(
          (event) =>
              event.type == EngagementEventType.quickPracticeStarted &&
              event.context.launchSource == EngagementLaunchSource.invitation,
        )
        .map((event) => event.context.flowId ?? event.eventId)
        .toSet();
    final starts = flows(EngagementEventType.quickPracticeStarted);
    final completions = flows(EngagementEventType.quickPracticeCompleted);
    final repeats = flows(EngagementEventType.repeatPracticeStarted);
    final visitDays = events
        .where(
          (event) => event.type == EngagementEventType.companionSurfaceViewed,
        )
        .map((event) => '${event.anonymousInstallId}:${event.localDate}')
        .toSet();
    final returns = events
        .where((event) => event.type == EngagementEventType.nextDayReturn)
        .map((event) => '${event.anonymousInstallId}:${event.localDate}')
        .toSet();
    final latestDate = events
        .map((event) => event.localDate)
        .fold<String?>(
          null,
          (latest, date) =>
              latest == null || date.compareTo(latest) > 0 ? date : latest,
        );
    final eligibleVisits = latestDate == null
        ? const <String>{}
        : visitDays.where((key) => !key.endsWith(':$latestDate')).toSet();
    return EngagementMetrics(
      invitationClickThrough: _rate(
        invitationStarts.length,
        invitations.length,
      ),
      quickCompletion: _rate(completions.length, starts.length),
      voluntaryRepeat: _rate(repeats.length, completions.length),
      nextDayReturn: _rate(returns.length, eligibleVisits.length),
    );
  }

  final double invitationClickThrough;
  final double quickCompletion;
  final double voluntaryRepeat;
  final double nextDayReturn;

  static double _rate(int numerator, int denominator) =>
      denominator == 0 ? 0 : numerator / denominator;
}
