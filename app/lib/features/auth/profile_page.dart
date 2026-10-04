import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/lan_discovery.dart';
import '../../data/providers.dart';
import '../../data/repositories/synced_library_repository.dart';
import '../../domain/entities/quota.dart';
import '../../domain/entities/user_preferences.dart';
import '../history/practice_stats.dart';
import '../update/update_flow.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _loginBusy = false;
  bool _registerMode = false;

  /// null = checking, true/false = PC service reachable.
  bool? _online;

  @override
  void initState() {
    super.initState();
    _refreshPing(silent: true);
  }

  Future<void> _refreshPing({bool silent = false}) async {
    if (!silent && mounted) setState(() => _online = null);
    final ok = await ref.read(mlApiProvider).ping();
    if (mounted) setState(() => _online = ok);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authRepositoryProvider);
    final account = auth.current();
    final quota = auth.quota();
    ref.watch(accountRefreshProvider);
    ref.watch(practiceRefreshProvider);
    final stats = PracticeStats.from(
        ref.read(practiceRepositoryProvider).recordings());

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
                            style:
                                Theme.of(context).textTheme.titleMedium),
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
          _LearningOverview(stats: stats),
          const SizedBox(height: 8),
          _QuotaCard(quota: quota),
          const SizedBox(height: 8),
          _ServiceCard(
            online: _online,
            onPing: () => _refreshPing(),
            onEditServer: _editServerUrl,
            onCheckUpdate: _checkUpdate,
          ),
          const SizedBox(height: 8),
          const _PreferencesCard(),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('转录服务'),
                  subtitle:
                      const Text('faster-whisper 高精度 · sherpa-onnx 离线档'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showServiceDialog(
                    context,
                    title: '转录服务',
                    body: '电脑端「字幕工坊」使用 faster-whisper 高精度模型，'
                        '生成逐词时间轴，实测人声清晰素材识别准确率接近 100%；'
                        '歌曲、强背景音乐等场景会自动切换无 VAD 全音频识别。\n'
                        '手机端规划接入 sherpa-onnx 离线模型，离线也能转录。',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.translate),
                  title: const Text('翻译'),
                  subtitle: const Text('多语言对照 · 可插拔翻译源'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showServiceDialog(
                    context,
                    title: '翻译服务',
                    body: '字幕工坊内置免配置翻译链：MyMemory → Google gtx → '
                        'LibreTranslate 自动降级，译文随字幕 JSON 一起保存，'
                        '播放时双语对照显示。\n'
                        '后续可接入 DeepL、有道或大模型等更多翻译源。',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bar_chart_outlined),
                  title: const Text('发音评分'),
                  subtitle: const Text('节奏 / 流利 / 语调启发式评分'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showServiceDialog(
                    context,
                    title: '发音评分',
                    body: '当前 V1 评分基于录音时长与原句节奏的贴合度、'
                        '停顿情况给出节奏、流利、语调三维参考分，'
                        '适合入门阶段跟节奏使用。\n'
                        'V2 将升级为音素级 GOP 强制对齐，'
                        '精确到每个发音并给出错音提示。',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于 MyLangLean'),
                  subtitle: const Text('版本 ${Env.appVersion}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showAbout(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                  title: const Text('重置学习数据',
                      style: TextStyle(color: Colors.redAccent)),
                  subtitle: const Text('清空全部跟读记录与录音文件'),
                  onTap: stats.count == 0 ? null : () => _resetData(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _showServiceDialog(
    BuildContext context, {
    required String title,
    required String body,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body, style: const TextStyle(height: 1.6)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了')),
        ],
      ),
    );
  }

  Future<void> _showAbout(BuildContext context) {
    // Custom dialog instead of showAboutDialog: without the full
    // flutter_localizations stack (blocked by the intl 0.17 pin) the stock
    // dialog shows English buttons.
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.school, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Env.appName,
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w600)),
                  Text('${Env.appVersion} 版',
                      style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        content: const Text(
          '© 2026 MyLangLean · 仅作个人语言学习使用\n\n'
          '把全网播客与本地音视频变成带逐词字幕、翻译、循环变速与'
          '影子跟读评分的私人外语课。\n'
          '核心学习闭环：听懂 → 模仿 → 说出。',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetData(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置学习数据？'),
        content: const Text('将清空全部跟读记录及对应的录音文件，且无法恢复。'
            '订阅与导入的内容不受影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('全部清空'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(practiceRepositoryProvider).clear();
      ref.read(practiceRefreshProvider.notifier).state++;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('学习数据已重置')),
      );
    }
  }

  Future<void> _editServerUrl() async {
    final api = ref.read(mlApiProvider);
    final url = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _ServerUrlDialog(initialUrl: api.baseUrl),
    );
    if (url == null || url.isEmpty || url == api.baseUrl) return;
    api.baseUrl = url;
    await ref.read(kvStoreProvider)?.set('api.base_url', url);
    ref.read(serverBaseUrlProvider.notifier).state = url;
    _refreshPing();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('服务器地址已保存')),
      );
    }
  }

  Future<void> _checkUpdate() => runUpdateCheck(
        context: context,
        api: ref.read(mlApiProvider),
        manual: true,
      );

  /// Reconciles server subscriptions after an account change and bumps the
  /// library refresh counter when the set changed.
  Future<void> _syncSubscriptions() async {
    final repo = ref.read(libraryRepositoryProvider);
    if (repo is! SyncedLibraryRepository) return;
    final changed = await repo.syncSubscriptions();
    if (changed) ref.read(libraryRefreshProvider.notifier).state++;
  }

  Future<void> _showLoginSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // Cover the shell's mini player / navigation bar as well.
      useRootNavigator: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> submit() async {
            final email = _emailCtrl.text.trim();
            final password = _pwdCtrl.text;
            final name = _nameCtrl.text.trim();
            if (email.isEmpty || password.isEmpty) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                const SnackBar(content: Text('请填写邮箱和密码')),
              );
              return;
            }
            if (_registerMode && password.length < 6) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                const SnackBar(content: Text('密码至少需要 6 位')),
              );
              return;
            }
            setSheetState(() => _loginBusy = true);
            try {
              final repo = ref.read(authRepositoryProvider);
              if (_registerMode) {
                await repo.register(
                    email: email, password: password, name: name);
              } else {
                await repo.login(email: email, password: password);
              }
              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext);
              setState(() {});
              await _syncSubscriptions();
            } catch (e) {
              if (!sheetContext.mounted) return;
              setSheetState(() => _loginBusy = false);
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                SnackBar(content: Text('$e')),
              );
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    _registerMode
                        ? '注册账号，同步订阅与学习数据'
                        : '登录后每月获赠 ${Env.monthlyQuotaSec ~/ 60} 分钟转录额度',
                    style: Theme.of(sheetContext).textTheme.titleMedium),
                const SizedBox(height: 14),
                // Login / register segmented switch.
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Row(children: [
                    _ModeTab(
                      text: '登录',
                      selected: !_registerMode,
                      onTap: _loginBusy
                          ? null
                          : () => setSheetState(
                              () => _registerMode = false),
                    ),
                    _ModeTab(
                      text: '注册',
                      selected: _registerMode,
                      onTap: _loginBusy
                          ? null
                          : () => setSheetState(
                              () => _registerMode = true),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                if (_registerMode) ...[
                  TextField(
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '昵称（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: '邮箱',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pwdCtrl,
                  obscureText: true,
                  onSubmitted: (_) => _loginBusy ? null : submit(),
                  decoration: InputDecoration(
                    labelText: '密码',
                    helperText: _registerMode ? '至少 6 位' : null,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loginBusy ? null : submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _loginBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_registerMode ? '注册并登录' : '登录'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
    _loginBusy = false;
    _registerMode = false;
    _emailCtrl.clear();
    _pwdCtrl.clear();
    _nameCtrl.clear();
  }
}

/// Server URL editor dialog.
///
/// Owns its [TextEditingController] and disposes it in [State.dispose],
/// which runs only after the dialog route is fully removed. Disposing
/// synchronously after [Navigator.pop] would race the route's exit
/// animation while the [TextField] is still mounted.
class _ServerUrlDialog extends StatefulWidget {
  const _ServerUrlDialog({required this.initialUrl});

  final String initialUrl;

  @override
  State<_ServerUrlDialog> createState() => _ServerUrlDialogState();
}

class _ServerUrlDialogState extends State<_ServerUrlDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialUrl);
  bool _discovering = false;

  Future<void> _autoDiscover() async {
    setState(() => _discovering = true);
    final url = await LanServerDiscovery.discover();
    if (!mounted) return;
    setState(() => _discovering = false);
    if (url != null) {
      _ctrl.text = url;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已发现服务器：$url')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未发现局域网服务器，请确认电脑端服务已启动、'
              '防火墙已放行且手机与电脑在同一网络'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('服务器地址'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '例如 http://192.168.1.10:8000',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _discovering ? null : _autoDiscover,
            icon: _discovering
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find),
            label: Text(_discovering ? '正在搜索…' : '自动发现局域网服务器'),
          ),
          const SizedBox(height: 8),
          const Text(
            '手机与电脑需在同一网络；USB 调试时可用 http://127.0.0.1:8000 配合 adb reverse。',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.black87 : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceCard extends ConsumerWidget {
  const _ServiceCard({
    required this.online,
    required this.onPing,
    required this.onEditServer,
    required this.onCheckUpdate,
  });

  final bool? online;
  final VoidCallback onPing;
  final VoidCallback onEditServer;
  final VoidCallback onCheckUpdate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseUrl = ref.watch(serverBaseUrlProvider);
    final Widget statusTrailing;
    if (online == null) {
      statusTrailing = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('检测中', style: TextStyle(fontSize: 12)),
        ],
      );
    } else {
      statusTrailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(online! ? Icons.cloud_done : Icons.cloud_off,
              size: 16,
              color: online! ? Colors.greenAccent.shade400 : Colors.white38),
          const SizedBox(width: 6),
          Text(online! ? '在线' : '离线',
              style: TextStyle(
                fontSize: 12,
                color: online!
                    ? Colors.greenAccent.shade400
                    : Colors.white38,
              )),
        ],
      );
    }

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('服务器地址'),
            subtitle: Text(baseUrl,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.edit, size: 18),
            onTap: onEditServer,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.electrical_services),
            title: const Text('连接状态'),
            trailing: statusTrailing,
            onTap: onPing,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('检查更新'),
            subtitle: const Text('当前版本 ${Env.appVersion}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onCheckUpdate,
          ),
        ],
      ),
    );
  }
}

class _LearningOverview extends StatelessWidget {
  const _LearningOverview({required this.stats});
  final PracticeStats stats;

  @override
  Widget build(BuildContext context) {
    final minutes = (stats.totalSec / 60).toStringAsFixed(1);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/history'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Row(
            children: [
              const SizedBox(width: 8),
              const Icon(Icons.insights, size: 20, color: Colors.white54),
              const SizedBox(width: 12),
              const Text('学习概览',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              _OverviewValue(value: '${stats.count}', label: '次跟读'),
              _OverviewValue(value: minutes, label: '分钟'),
              _OverviewValue(value: '${stats.avgScore}', label: '均分'),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewValue extends StatelessWidget {
  const _OverviewValue({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ],
      ),
    );
  }
}

class _PreferencesCard extends ConsumerWidget {
  const _PreferencesCard();

  /// Mirrors [Env.fontScales] order (double keys are not allowed in const
  /// maps on the supported toolchains).
  static const _fontLabels = ['小', '标准', '大', '特大', '超大'];
  static const _rateChoices = [0.75, 1.0, 1.25];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(preferencesProvider);
    final notifier = ref.read(preferencesProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tune, size: 18),
                SizedBox(width: 6),
                Text('播放与字幕默认设置',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            const _PrefLabel('字幕模式'),
            Wrap(
              spacing: 8,
              children: [
                for (final mode in SubtitlePref.values)
                  ChoiceChip(
                    label: Text(mode.label),
                    selected: prefs.subtitle == mode,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => notifier.setSubtitle(mode),
                  ),
              ],
            ),
            const _PrefLabel('字幕字号'),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < Env.fontScales.length; i++)
                  ChoiceChip(
                    label: Text(_fontLabels[i]),
                    selected:
                        (prefs.defaultFontScale - Env.fontScales[i]).abs() <
                            0.001,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) =>
                        notifier.setDefaultFontScale(Env.fontScales[i]),
                  ),
              ],
            ),
            const _PrefLabel('默认语速'),
            Wrap(
              spacing: 8,
              children: [
                for (final rate in _rateChoices)
                  ChoiceChip(
                    label: Text('${rate}x'),
                    selected:
                        (prefs.defaultRate - rate).abs() < 0.001,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => notifier.setDefaultRate(rate),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text('设置会在下次打开音频时生效，也可在播放页临时调整。',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

class _PrefLabel extends StatelessWidget {
  const _PrefLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(text,
          style: const TextStyle(fontSize: 12, color: Colors.white54)),
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
                Text(quota.isGuest ? '游客试看额度' : '本月转录额度'),
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
            Text(
              quota.isGuest
                  ? '登录后每月 1 日重置，获赠 $totalMin 分钟转录额度'
                  : '剩余 $remainMin 分钟（每月 1 日重置）',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
