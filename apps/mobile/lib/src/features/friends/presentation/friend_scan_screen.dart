import 'package:flutter/material.dart';

class FriendScanScreen extends StatelessWidget {
  const FriendScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void pending(String message) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('扫一扫')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2925),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 112,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Text(
              '扫描方圆里好友二维码后，仍需发送好友申请并等待对方同意。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF66736D), height: 1.45),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => pending('相机扫码能力接入后即可扫描'),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('打开相机'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => pending('二维码相册识别能力接入后即可选择'),
                icon: const Icon(Icons.photo_outlined),
                label: const Text('从相册选择'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
