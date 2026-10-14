import 'package:flutter/material.dart';

import 'models/pet.dart';
import 'widgets/pet_interaction_stage.dart';

/// A self-contained gallery for the interaction assets used by the learning
/// app. It deliberately stores no learning data and never writes a profile.
class PetInteractionsApp extends StatelessWidget {
  const PetInteractionsApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xffe16b45);
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return MaterialApp(
      title: '萌宠互动',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xfffffbf5),
        cardTheme: CardThemeData(
          color: const Color(0xfffffdf9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      home: const PetInteractionGalleryPage(),
    );
  }
}

class PetInteractionGalleryPage extends StatefulWidget {
  const PetInteractionGalleryPage({super.key});

  @override
  State<PetInteractionGalleryPage> createState() =>
      _PetInteractionGalleryPageState();
}

class _PetInteractionGalleryPageState extends State<PetInteractionGalleryPage> {
  static const _profile = PetProfile(
    name: '小语',
    breed: 'dog',
    selectedDecoration: 'blue-collar',
  );
  var _index = 0;

  _InteractionStep get _step => _steps[_index];

  void _changeStep(int delta) {
    final next = (_index + delta).clamp(0, _steps.length - 1);
    if (next == _index) return;
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('萌宠互动')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              '已解锁 ${_index + 1} / ${_steps.length}',
              key: const ValueKey('pet-interaction-progress'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _step.title,
              key: const ValueKey('pet-interaction-title'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              _step.description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Center(
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey('pet-interaction-${_step.id}'),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: PetInteractionStage(
                        cue: _step.cue,
                        profile: _profile,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('pet-interaction-previous'),
                    onPressed: _index == 0 ? null : () => _changeStep(-1),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('上一个'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('pet-interaction-next'),
                    onPressed: _index == _steps.length - 1
                        ? null
                        : () => _changeStep(1),
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(_index == _steps.length - 1 ? '全部解锁' : '下一个'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _InteractionStep {
  const _InteractionStep({
    required this.id,
    required this.cue,
    required this.title,
    required this.description,
  });

  final String id;
  final PetInteractionCue cue;
  final String title;
  final String description;
}

const _steps = <_InteractionStep>[
  _InteractionStep(
    id: 'invite',
    cue: PetInteractionCue.invite,
    title: '挥爪邀请',
    description: '小语抬起前爪、摇着尾巴，邀请你一起完成三题。',
  ),
  _InteractionStep(
    id: 'think',
    cue: PetInteractionCue.think,
    title: '安静思考',
    description: '答题时，小语会歪头眨眼，安静陪你慢慢想。',
  ),
  _InteractionStep(
    id: 'correct',
    cue: PetInteractionCue.correct,
    title: '答对庆祝',
    description: '答对后，小语跳起来、亮起星星眼、用力摇尾巴。',
  ),
  _InteractionStep(
    id: 'incorrect',
    cue: PetInteractionCue.incorrect,
    title: '温柔鼓励',
    description: '答错也没关系，小语会轻轻歪头，再抬头陪你试一次。',
  ),
  _InteractionStep(
    id: 'complete',
    cue: PetInteractionCue.complete,
    title: '完成送花',
    description: '完成任务时，小语叼着小花跑来，开心地跳一跳。',
  ),
  _InteractionStep(
    id: 'repeat',
    cue: PetInteractionCue.repeat,
    title: '书桌等你',
    description: '想再练一组时，小语会原地小跑，在书桌旁等你回来。',
  ),
  _InteractionStep(
    id: 'tail-wag',
    cue: PetInteractionCue.tailWag,
    title: '即时摇尾巴',
    description: '普通三题完成后，小语用更快的尾巴摆动表达开心。',
  ),
  _InteractionStep(
    id: 'flower-gift',
    cue: PetInteractionCue.flowerGift,
    title: '即时送小花',
    description: '朗读三题完成后，小语带着小花跑来感谢认真朗读的你。',
  ),
  _InteractionStep(
    id: 'study-together',
    cue: PetInteractionCue.studyTogether,
    title: '趴桌陪读',
    description: '写汉字或错题复习时，小语趴到书桌旁和你一起读。',
  ),
  _InteractionStep(
    id: 'lamp',
    cue: PetInteractionCue.lamp,
    title: '点亮小台灯',
    description: '完成学习任务后，台灯不断闪亮，小语在旁边摇尾巴。',
  ),
  _InteractionStep(
    id: 'bookcase',
    cue: PetInteractionCue.bookcase,
    title: '装满小书柜',
    description: '书柜里的书会上下跳动，表示又收好了一本书。',
  ),
  _InteractionStep(
    id: 'flower-pot',
    cue: PetInteractionCue.flowerPot,
    title: '花儿开放',
    description: '花瓣会呼吸般开合，小语陪着小花一起摇摆。',
  ),
  _InteractionStep(
    id: 'lesson-celebration',
    cue: PetInteractionCue.lessonCelebration,
    title: '课文通关庆祝',
    description: '课文目标完成时，小语从旁边跑来、跳起并迎来彩纸。',
  ),
  _InteractionStep(
    id: 'unit-celebration',
    cue: PetInteractionCue.unitCelebration,
    title: '单元礼花',
    description: '完成单元大阶段时，小语跳跃庆祝，满屏礼花持续落下。',
  ),
];
