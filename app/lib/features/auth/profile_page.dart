import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/providers.dart';
import '../../domain/entities/quota.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authRepositoryProvider);
    final account = auth.current();
    final quota = auth.quota();

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    child: Text(
                      account.displayName.characters.first,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(account.displayName,
                            style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          account.isGuest
                              ? '游客模式 · 字幕可免费试看 5 分钟'
                              : account.email ?? '',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  if (account.isGuest)
                    FilledButton(
                      onPressed: () => _showLoginSheet(context),
                      child: const Text('登录'),
                    )
                  else
                    TextButton(
                      onPressed: () async {
                        await auth.logout();
                        setState(() {});
                      },
                      child: const Text('退出'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _QuotaCard(quota: quota),
          const SizedBox(height: 8),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.cloud_outlined),
                  title: Text('转录服务'),
                  subtitle: Text('faster-whisper 高精度档 · 端侧 sherpa-onnx 离线档'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.translate),
                  title: Text('翻译'),
                  subtitle: Text('多语言对照（可插拔翻译源）'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('关于 MyLangLean'),
                  subtitle: Text('OORA 风格播客跟读学习 · HarmonyOS / iOS'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLoginSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('登录后每月获赠 ${Env.monthlyQuotaSec ~/ 60} 分钟转录额度',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '邮箱',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                if (_emailCtrl.text.isEmpty || _pwdCtrl.text.isEmpty) return;
                await ref.read(authRepositoryProvider).login(
                      email: _emailCtrl.text.trim(),
                      password: _pwdCtrl.text,
                    );
                if (context.mounted) Navigator.pop(context);
                setState(() {});
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('登录 / 注册'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.quota});
  final UserQuota quota;

  @override
  Widget build(BuildContext context) {
    final usedMin = (quota.usedSec / 60).toStringAsFixed(0);
    final totalMin = quota.limitSec ~/ 60;
    final remainMin = (quota.remainingSec / 60).toStringAsFixed(0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18),
                const SizedBox(width: 6),
                const Text('本月转录额度'),
                const Spacer(),
                Text('已用 $usedMin / $totalMin 分钟',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: quota.usedRatio.clamp(0, 1),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text('剩余 $remainMin 分钟（每月 1 日重置）',
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}
