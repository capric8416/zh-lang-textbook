import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ClassJoinCodeDialog extends StatelessWidget {
  const ClassJoinCodeDialog({
    super.key,
    required this.className,
    required this.code,
  });

  final String className;
  final String code;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final qrSize = (screenSize.shortestSide * 0.55)
        .clamp(160.0, 220.0)
        .toDouble();

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: screenSize.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$className 入班码',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: QrImageView(
                    data: 'join:$code',
                    size: qrSize,
                    backgroundColor: Colors.white,
                    semanticsLabel: '班级入班二维码',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('请学生使用个人账号扫描；7 天后失效', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: 'join:$code'),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('入班码内容已复制')),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('复制内容'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('完成'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
