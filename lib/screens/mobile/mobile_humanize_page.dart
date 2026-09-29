/// 移动端拟人模式页面 — 与桌面端 HumanizePage 功能对齐：
/// 拟人化节奏（±40% 抖动、贝塞尔轨迹、随机暂停）、随机延迟、随机偏移、按键抖动。
/// 底层行为由 ClickService 消费 [ClickerConfig] 字段实现（与桌面端同一份引擎），
/// 本页只负责 Material 风格的 UI；所有改动走 MobileAppState.setClickerConfig。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/clicker_config.dart';
import '../../services/mobile_app_state.dart';

class MobileHumanizePage extends StatelessWidget {
  const MobileHumanizePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MobileAppState>();
    final config = state.clickerConfig;
    final isDark = state.themeMode == 'dark';
    final accent = state.accentColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('拟人模式'),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : accent.withValues(alpha: 0.1),
        foregroundColor: isDark ? Colors.white : accent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _card(isDark, '拟人模式', Icons.people_outline, accent,
              '在点击间隔上叠加 ±40% 随机抖动，使节奏更接近真人操作',
              _buildHumanLike(config, state, isDark, accent)),
          const SizedBox(height: 12),
          _card(isDark, '随机延迟', Icons.more_time, accent,
              '每次点击额外附加一段 N~M 毫秒的随机延迟',
              _buildRandomDelay(config, state, isDark)),
          const SizedBox(height: 12),
          _card(isDark, '随机偏移', Icons.open_with, accent,
              '点击位置在目标点附近 N~M 像素内随机偏移',
              _buildRandomOffset(config, state, isDark, accent)),
          const SizedBox(height: 12),
          _card(isDark, '按键抖动', Icons.keyboard_outlined, accent,
              '键盘按键间隔附加 N~M 毫秒的随机抖动',
              _buildJitter(config, state, isDark)),
        ],
      ),
    );
  }

  Widget _card(bool isDark, String title, IconData icon, Color accent,
      String subtitle, Widget child) {
    return Card(
      color: isDark ? const Color(0xFF22223A) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
          const SizedBox(height: 6),
          Text(subtitle,
              style: TextStyle(
                  fontSize: 11, color: isDark ? Colors.white38 : Colors.black45)),
          const SizedBox(height: 10),
          child,
        ]),
      ),
    );
  }

  // ─── 拟人模式（总开关 + 贝塞尔轨迹 + 随机暂停） ─────────

  Widget _buildHumanLike(
      ClickerConfig config, MobileAppState state, bool isDark, Color accent) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _switchRow('启用拟人模式', config.humanLikeEnabled, accent,
          (v) => state.setClickerConfig(config.copyWith(humanLikeEnabled: v))),
      if (config.humanLikeEnabled) ...[
        const Divider(height: 20),
        _switchRow('贝塞尔轨迹', config.humanLikeBezierCurve, accent,
            (v) => state.setClickerConfig(config.copyWith(humanLikeBezierCurve: v))),
        const SizedBox(height: 4),
        _switchRow('随机暂停', config.humanLikeRandomPause, accent,
            (v) => state.setClickerConfig(config.copyWith(humanLikeRandomPause: v))),
        if (config.humanLikeRandomPause) ...[
          const SizedBox(height: 10),
          Row(children: [
            const SizedBox(width: 70, child: Text('暂停概率', style: TextStyle(fontSize: 12))),
            Expanded(
              child: Slider(
                value: config.humanLikePauseChance.toDouble(),
                min: 1,
                max: 20,
                divisions: 19,
                label: '${config.humanLikePauseChance}%',
                onChanged: (v) => state.setClickerConfig(
                    config.copyWith(humanLikePauseChance: v.round())),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text('${config.humanLikePauseChance}%',
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const SizedBox(width: 70, child: Text('暂停时长', style: TextStyle(fontSize: 12))),
            _numField(config.humanLikePauseMinMs, isDark, (v) {
              if (v > 0) {
                state.setClickerConfig(config.copyWith(humanLikePauseMinMs: v));
              }
            }),
            const SizedBox(width: 6),
            const Text('-', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            _numField(config.humanLikePauseMaxMs, isDark, (v) {
              if (v > 0) {
                state.setClickerConfig(config.copyWith(humanLikePauseMaxMs: v));
              }
            }),
            const SizedBox(width: 6),
            const Text('ms', style: TextStyle(fontSize: 12)),
          ]),
        ],
      ],
    ]);
  }

  // ─── 随机延迟 ─────────────────────────────────────────────

  Widget _buildRandomDelay(
      ClickerConfig config, MobileAppState state, bool isDark) {
    final enabled = config.randomDelayMinMs > 0 || config.randomDelayMaxMs > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _switchRow('启用随机延迟', enabled, state.accentColor, (v) {
        // 开：落到默认 10~50ms；关：清零（关闭判定即 min/max 均为 0）
        state.setClickerConfig(config.copyWith(
          randomDelayMinMs: v ? 10 : 0,
          randomDelayMaxMs: v ? 50 : 0,
        ));
      }),
      if (enabled) ...[
        const SizedBox(height: 10),
        Row(children: [
          const SizedBox(width: 70, child: Text('最小', style: TextStyle(fontSize: 12))),
          _numField(config.randomDelayMinMs, isDark, (v) =>
              state.setClickerConfig(config.copyWith(randomDelayMinMs: v))),
          const SizedBox(width: 6),
          const Text('-', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          _numField(config.randomDelayMaxMs, isDark, (v) =>
              state.setClickerConfig(config.copyWith(randomDelayMaxMs: v))),
          const SizedBox(width: 6),
          const Text('ms', style: TextStyle(fontSize: 12)),
        ]),
      ],
    ]);
  }

  // ─── 随机偏移 ─────────────────────────────────────────────

  Widget _buildRandomOffset(
      ClickerConfig config, MobileAppState state, bool isDark, Color accent) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _switchRow('启用随机偏移', config.randomOffsetEnabled, accent,
          (v) => state.setClickerConfig(config.copyWith(randomOffsetEnabled: v))),
      if (config.randomOffsetEnabled) ...[
        const SizedBox(height: 10),
        Row(children: [
          const SizedBox(width: 70, child: Text('范围', style: TextStyle(fontSize: 12))),
          _numField(config.randomOffsetMinPx, isDark, (v) =>
              state.setClickerConfig(config.copyWith(randomOffsetMinPx: v))),
          const SizedBox(width: 6),
          const Text('~', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          _numField(config.randomOffsetMaxPx, isDark, (v) =>
              state.setClickerConfig(config.copyWith(randomOffsetMaxPx: v))),
          const SizedBox(width: 6),
          const Text('px', style: TextStyle(fontSize: 12)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const SizedBox(width: 70),
          Expanded(
            child: Slider(
              value: config.randomOffsetMaxPx.toDouble().clamp(1.0, 50.0),
              min: 1,
              max: 50,
              divisions: 49,
              label: '${config.randomOffsetMaxPx}px',
              onChanged: (v) => state.setClickerConfig(
                  config.copyWith(randomOffsetMaxPx: v.round())),
            ),
          ),
        ]),
      ],
    ]);
  }

  // ─── 按键抖动 ─────────────────────────────────────────────

  Widget _buildJitter(ClickerConfig config, MobileAppState state, bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _switchRow('启用按键抖动', config.jitterEnabled, state.accentColor,
          (v) => state.setClickerConfig(config.copyWith(jitterEnabled: v))),
      if (config.jitterEnabled) ...[
        const SizedBox(height: 10),
        Row(children: [
          const SizedBox(width: 70, child: Text('范围', style: TextStyle(fontSize: 12))),
          _numField(config.jitterMinMs, isDark, (v) =>
              state.setClickerConfig(config.copyWith(jitterMinMs: v))),
          const SizedBox(width: 6),
          const Text('~', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          _numField(config.jitterMaxMs, isDark, (v) =>
              state.setClickerConfig(config.copyWith(jitterMaxMs: v))),
          const SizedBox(width: 6),
          const Text('ms', style: TextStyle(fontSize: 12)),
        ]),
      ],
    ]);
  }

  // ─── 复用控件 ─────────────────────────────────────────────

  Widget _switchRow(String label, bool value, Color accent, ValueChanged<bool> onChanged) {
    return Row(children: [
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      Switch(value: value, onChanged: onChanged),
    ]);
  }

  Widget _numField(int value, bool isDark, ValueChanged<int> onChanged) {
    return SizedBox(
      width: 62,
      height: 36,
      child: TextField(
        controller: TextEditingController(text: value.toString()),
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          filled: true,
          fillColor: isDark ? const Color(0xFF303050) : const Color(0xFFF0F0F8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (v) {
          final p = int.tryParse(v);
          if (p != null && p >= 0) onChanged(p);
        },
      ),
    );
  }
}
