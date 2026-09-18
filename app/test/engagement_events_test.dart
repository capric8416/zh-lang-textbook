import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zh_textbook/models/engagement_event.dart';
import 'package:zh_textbook/models/pet_mission.dart';
import 'package:zh_textbook/models/quick_practice.dart';
import 'package:zh_textbook/services/engagement_events.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('事件只序列化允许的强类型上下文并可往返', () {
    final event = _event(
      id: 'event-1',
      type: EngagementEventType.quickPracticeStarted,
      context: const EngagementEventContext(
        textbookKey: 'grade2b',
        surface: EngagementSurface.petHome,
        launchSource: EngagementLaunchSource.furniture,
        quickPracticeAction: QuickPracticeAction.characters,
        missionKind: PetMissionKind.lightLamp,
        roomId: 'study-room',
        furnitureId: 'desk-lamp',
        flowId: 'flow-1',
      ),
    );
    final encoded = event.toJson();
    expect(
      encoded['context'],
      equals({
        'textbook_key': 'grade2b',
        'surface': 'petHome',
        'launch_source': 'furniture',
        'quick_practice_action': 'characters',
        'mission_kind': 'lightLamp',
        'room_id': 'study-room',
        'furniture_id': 'desk-lamp',
        'flow_id': 'flow-1',
      }),
    );
    expect(jsonEncode(encoded), isNot(contains('pet_name')));
    expect(jsonEncode(encoded), isNot(contains('answer')));
    expect(
      EngagementEvent.fromJson(encoded).context.missionKind,
      PetMissionKind.lightLamp,
    );
  });

  test('事件仓库幂等、优先裁剪已确认记录并忽略损坏记录', () async {
    SharedPreferences.setMockInitialValues({
      EngagementEventStore.storageKey: jsonEncode({
        'version': 1,
        'anonymous_install_id': 'install',
        'sequence': 1,
        'events': [
          {'broken': true},
          _event(
            id: 'old',
            type: EngagementEventType.companionSurfaceViewed,
            delivery: EngagementDeliveryState.acknowledged,
          ).toJson(),
        ],
      }),
    });
    var next = 0;
    final store = await EngagementEventStore.open(
      idFactory: () => 'generated-${next++}',
      sessionId: 'session',
      clock: () => DateTime.utc(2026, 9, 18),
      maxEventCount: 2,
    );
    expect(store.events.map((event) => event.eventId), ['old']);
    await store.append(
      eventId: 'same',
      type: EngagementEventType.invitationPresented,
    );
    await store.append(
      eventId: 'same',
      type: EngagementEventType.invitationPresented,
    );
    await store.append(
      eventId: 'new',
      type: EngagementEventType.quickPracticeStarted,
    );
    expect(store.events.map((event) => event.eventId), ['same', 'new']);
  });

  test('事件仓库按保留期裁剪且新事件保持待上报', () async {
    var now = DateTime.utc(2026, 1, 1);
    var id = 0;
    final store = await EngagementEventStore.open(
      idFactory: () => 'id-${id++}',
      sessionId: 'session',
      clock: () => now,
      retention: const Duration(days: 2),
    );
    await store.append(type: EngagementEventType.companionSurfaceViewed);
    now = DateTime.utc(2026, 1, 4);
    final recent = await store.append(
      type: EngagementEventType.invitationPresented,
    );
    expect(store.events, [recent]);
    expect(recent.deliveryState, EngagementDeliveryState.pending);
  });

  test('指标从去重事件投影邀请、完成、再练和次日回访', () {
    final events = [
      _event(
        id: 'present',
        type: EngagementEventType.invitationPresented,
        context: const EngagementEventContext(flowId: 'flow-1'),
      ),
      _event(
        id: 'start',
        type: EngagementEventType.quickPracticeStarted,
        context: const EngagementEventContext(
          flowId: 'flow-1',
          launchSource: EngagementLaunchSource.invitation,
        ),
      ),
      _event(
        id: 'complete',
        type: EngagementEventType.quickPracticeCompleted,
        context: const EngagementEventContext(flowId: 'flow-1'),
      ),
      _event(
        id: 'repeat',
        type: EngagementEventType.repeatPracticeStarted,
        context: const EngagementEventContext(flowId: 'flow-2'),
      ),
      _event(
        id: 'visit-1',
        type: EngagementEventType.companionSurfaceViewed,
        localDate: '2026-09-17',
      ),
      _event(
        id: 'visit-2',
        type: EngagementEventType.companionSurfaceViewed,
        localDate: '2026-09-18',
      ),
      _event(
        id: 'return',
        type: EngagementEventType.nextDayReturn,
        localDate: '2026-09-18',
      ),
      _event(
        id: 'return',
        type: EngagementEventType.nextDayReturn,
        localDate: '2026-09-18',
      ),
    ];
    final metrics = EngagementMetrics.fromEvents(events);
    expect(metrics.invitationClickThrough, 1);
    expect(metrics.quickCompletion, 1);
    expect(metrics.voluntaryRepeat, 1);
    expect(metrics.nextDayReturn, 1);
  });
}

EngagementEvent _event({
  required String id,
  required EngagementEventType type,
  EngagementEventContext context = const EngagementEventContext(),
  EngagementDeliveryState delivery = EngagementDeliveryState.pending,
  String localDate = '2026-09-17',
}) => EngagementEvent(
  eventId: id,
  schemaVersion: 1,
  type: type,
  occurredAtUtc: DateTime.utc(2026, 9, 17),
  localDate: localDate,
  anonymousInstallId: 'install',
  sessionId: 'session',
  sequence: id.hashCode,
  context: context,
  deliveryState: delivery,
);
