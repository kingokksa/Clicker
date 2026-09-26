/// 拟人模式页面 — 集中管理所有拟人化 / 反检测设置：
/// 拟人化节奏（±40% 抖动、贝塞尔轨迹、随机暂停）、智能延迟、
/// 随机偏移、随机延迟范围、按键抖动。底层行为仍由 ClickService 消费
/// [ClickerConfig] 字段实现，此页面只负责配置。
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../models/clicker_config.dart';
import '../../services/app_state.dart';

class HumanizePage extends StatelessWidget {
  const HumanizePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final config = state.clickerConfig;

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Icon(FluentIcons.accounts, size: 20, color: state.accentColor),
          const SizedBox(width: 10),
          const Text('拟人模式', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
        _card(context, title: '拟人模式', icon: FluentIcons.accounts, child: _buildHumanLike(context, config, state)),
        const SizedBox(height: 12),
        _card(context, title: '随机延迟', icon: FluentIcons.clock, child: _buildRandomDelay(context, config, state)),
        const SizedBox(height: 12),
        _card(context, title: '随机偏移', icon: FluentIcons.open_in_new_tab, child: _buildRandomOffset(context, config, state)),
        const SizedBox(height: 12),
        _card(context, title: '按键抖动', icon: FluentIcons.shield, child: _buildJitter(context, config, state)),
      ],
    );
  }

  Widget _card(BuildContext context, {required String title, required IconData icon, required Widget child}) {
    return Card(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }

  Widget _subtitle(BuildContext context, String text) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF9090B0) : const Color(0xFF8A8A9A))),
    );
  }

  // ─── 拟人模式（总开关 + 贝塞尔轨迹 + 随机暂停） ─────────

  Widget _buildHumanLike(BuildContext context, ClickerConfig config, AppState state) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _subtitle(context, '在点击间隔上叠加 ±40% 随机抖动，使节奏更接近真人操作'),
      Row(children: [
        const Expanded(child: Text('启用拟人模式', style: TextStyle(fontSize: 13))),
        ToggleSwitch(
          checked: config.humanLikeEnabled,
          onChanged: (v) => state.setClickerConfig(config.copyWith(humanLikeEnabled: v)),
        ),
      ]),
      if (config.humanLikeEnabled) ...[
        const SizedBox(height: 12),
        const Divider(style: DividerThemeData(horizontalMargin: EdgeInsets.zero)),
        const SizedBox(height: 8),
        Row(children: [
          const Expanded(child: Text('贝塞尔轨迹', style: TextStyle(fontSize: 12))),
          ToggleSwitch(
            checked: config.humanLikeBezierCurve,
            onChanged: (v) => state.setClickerConfig(config.copyWith(humanLikeBezierCurve: v)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Expanded(child: Text('随机暂停', style: TextStyle(fontSize: 12))),
          ToggleSwitch(
            checked: config.humanLikeRandomPause,
            onChanged: (v) => state.setClickerConfig(config.copyWith(humanLikeRandomPause: v)),
          ),
        ]),
        if (config.humanLikeRandomPause) ...[
          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 80, child: Text('暂停概率:', style: TextStyle(fontSize: 11))),
            Expanded(child: Slider(
              value: config.humanLikePauseChance.toDouble(),
              min: 1, max: 20, divisions: 19,
              label: '${config.humanLikePauseChance}%',
              onChanged: (v) => state.setClickerConfig(config.copyWith(humanLikePauseChance: v.round())),
            )),
            const SizedBox(width: 8),
            Text('${config.humanLikePauseChance}%', style: const TextStyle(fontSize: 11)),
          ]),
          Row(children: [
            const SizedBox(width: 80, child: Text('暂停时长:', style: TextStyle(fontSize: 11))),
            SizedBox(width: 60, child: TextBox(
              controller: TextEditingController(text: config.humanLikePauseMinMs.toString()),
              placeholder: '200',
              onChanged: (v) { final p = int.tryParse(v); if (p != null && p > 0) state.setClickerConfig(config.copyWith(humanLikePauseMinMs: p)); },
            )),
            const SizedBox(width: 4),
            const Text('-', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            SizedBox(width: 60, child: TextBox(
              controller: TextEditingController(text: config.humanLikePauseMaxMs.toString()),
              placeholder: '800',
              onChanged: (v) { final p = int.tryParse(v); if (p != null && p > 0) state.setClickerConfig(config.copyWith(humanLikePauseMaxMs: p)); },
            )),
            const SizedBox(width: 4),
            const Text('ms', style: TextStyle(fontSize: 11)),
          ]),
        ],
      ],
    ]);
  }

  // ─── 随机延迟 ─────────────────────────────────────────────

  Widget _buildRandomDelay(BuildContext context, ClickerConfig config, AppState state) {
    final enabled = config.randomDelayMinMs > 0 || config.randomDelayMaxMs > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _subtitle(context, '每次点击额外附加一段 N~M 毫秒的随机延迟'),
      Row(children: [
        const Expanded(child: Text('启用随机延迟', style: TextStyle(fontSize: 13))),
        ToggleSwitch(checked: enabled, onChanged: (v) {
          state.setClickerConfig(config.copyWith(randomDelayMinMs: v ? 10 : 0, randomDelayMaxMs: v ? 50 : 0));
        }),
      ]),
      if (enabled) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Text('最小:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(
            controller: TextEditingController(text: config.randomDelayMinMs.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p >= 0) state.setClickerConfig(config.copyWith(randomDelayMinMs: p)); },
          )),
          const SizedBox(width: 12),
          const Text('最大:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(
            controller: TextEditingController(text: config.randomDelayMaxMs.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p >= 0) state.setClickerConfig(config.copyWith(randomDelayMaxMs: p)); },
          )),
          const Text(' ms', style: TextStyle(fontSize: 12)),
        ]),
      ],
    ]);
  }

  // ─── 随机偏移 ─────────────────────────────────────────────

  Widget _buildRandomOffset(BuildContext context, ClickerConfig config, AppState state) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _subtitle(context, '点击位置在目标点附近 N~M 像素内随机偏移'),
      Row(children: [
        const Expanded(child: Text('启用随机偏移', style: TextStyle(fontSize: 13))),
        ToggleSwitch(checked: config.randomOffsetEnabled, onChanged: (v) => state.setClickerConfig(config.copyWith(randomOffsetEnabled: v))),
      ]),
      if (config.randomOffsetEnabled) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Text('范围:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: TextBox(
            controller: TextEditingController(text: config.randomOffsetMinPx.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p >= 0) state.setClickerConfig(config.copyWith(randomOffsetMinPx: p)); },
          )),
          const SizedBox(width: 6), const Text('~', style: TextStyle(fontSize: 13)), const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(
            controller: TextEditingController(text: config.randomOffsetMaxPx.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p >= 0) state.setClickerConfig(config.copyWith(randomOffsetMaxPx: p)); },
          )),
          const Text(' px', style: TextStyle(fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        Slider(value: config.randomOffsetMaxPx.toDouble(), min: 1, max: 50, divisions: 49,
          label: '${config.randomOffsetMaxPx}px',
          onChanged: (v) => state.setClickerConfig(config.copyWith(randomOffsetMaxPx: v.round()))),
      ],
    ]);
  }

  // ─── 按键抖动 ─────────────────────────────────────────────

  Widget _buildJitter(BuildContext context, ClickerConfig config, AppState state) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _subtitle(context, '键盘按键间隔附加 N~M 毫秒的随机抖动'),
      Row(children: [
        const Expanded(child: Text('启用按键抖动', style: TextStyle(fontSize: 13))),
        ToggleSwitch(checked: config.jitterEnabled, onChanged: (v) => state.setClickerConfig(config.copyWith(jitterEnabled: v))),
      ]),
      if (config.jitterEnabled) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Text('范围:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          SizedBox(width: 70, child: TextBox(
            controller: TextEditingController(text: config.jitterMinMs.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p >= 0) state.setClickerConfig(config.copyWith(jitterMinMs: p)); },
          )),
          const SizedBox(width: 6), const Text('~', style: TextStyle(fontSize: 13)), const SizedBox(width: 6),
          SizedBox(width: 70, child: TextBox(
            controller: TextEditingController(text: config.jitterMaxMs.toString()),
            onChanged: (v) { final p = int.tryParse(v); if (p != null && p >= 0) state.setClickerConfig(config.copyWith(jitterMaxMs: p)); },
          )),
          const Text(' ms', style: TextStyle(fontSize: 12)),
        ]),
      ],
    ]);
  }
}