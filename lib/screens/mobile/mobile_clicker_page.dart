/// Mobile clicker page — Material Design auto-clicker controls.
/// Touch-oriented: tap, long press, drag, swipe. No mouse/keyboard options.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/mobile_app_state.dart';
import '../../models/clicker_config.dart';
import '../../services/screen_overlay_service.dart';
import '../../widgets/debounced_number_field.dart';

class MobileClickerPage extends StatelessWidget {
  const MobileClickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MobileAppState>();
    final config = state.clickerConfig;
    final isDark = state.themeMode == 'dark';
    final accent = state.accentColor;
    final isRunning = state.isClickerRunning;
    final floatingVisible = state.isFloatingPanelVisible;

    return Scaffold(
      body: SafeArea(
        child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ─── Big Start/Stop Button ─────────────────────────
          _buildBigButton(state, isRunning, accent),
          const SizedBox(height: 16),

          // ─── Status ────────────────────────────────────────
          if (isRunning || state.clickCount > 0)
            _buildStatusCard(state, accent, isDark),
          if (isRunning || state.clickCount > 0) const SizedBox(height: 12),

          // ─── Touch Action Type ─────────────────────────────
          _sectionTitle('操作类型', isDark),
          _touchActionSelector(state, config, accent, isDark),
          const SizedBox(height: 12),

          // ─── Action-specific settings ──────────────────────
          _buildActionSettings(context, state, config, accent, isDark),
          const SizedBox(height: 12),

          // ─── Position ──────────────────────────────────────
          if (config.touchAction == TouchAction.tap ||
              config.touchAction == TouchAction.longPress) ...[
            _sectionTitle('点击位置', isDark),
            _positionSelector(context, state, config, accent, isDark),
            const SizedBox(height: 12),
          ],

          // ─── Interval ──────────────────────────────────────
          _sectionTitle('操作间隔', isDark),
          _intervalSlider(state, config, accent, isDark),
          const SizedBox(height: 12),

          // ─── Repeat ────────────────────────────────────────
          _sectionTitle('重复模式', isDark),
          _repeatModeSelector(state, config, accent, isDark),
          const SizedBox(height: 8),
          _repeatConfig(state, config, isDark),
          const SizedBox(height: 80), // space for FAB
        ],
      ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _toggleFloatingPanel(context, state),
        icon: Icon(floatingVisible ? Icons.visibility_off : Icons.picture_in_picture_alt),
        label: Text(floatingVisible ? '关闭悬浮窗' : '悬浮窗模式'),
        backgroundColor: floatingVisible ? Colors.red : accent,
        foregroundColor: Colors.white,
      ),
    );
  }

  Future<void> _toggleFloatingPanel(BuildContext context, MobileAppState state) async {
    if (state.isFloatingPanelVisible) {
      await state.hideFloatingPanel();
      return;
    }
    // Check overlay permission first
    final hasPermission = await state.checkOverlayPermission();
    if (!hasPermission) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请授予悬浮窗权限后重试'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      // Request permission (opens system settings)
      await state.requestOverlayPermission();
      return;
    }
    await state.showFloatingPanel();
  }

  // ─── Big Button ───────────────────────────────────────────

  Widget _buildBigButton(MobileAppState state, bool isRunning, Color accent) {
    return SizedBox(
      width: double.infinity,
      height: 80,
      child: FilledButton(
        onPressed: () => state.toggleClicker(),
        style: FilledButton.styleFrom(
          backgroundColor: isRunning ? Colors.red : accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        child: Text(isRunning ? '停止' : '开始'),
      ),
    );
  }

  Widget _buildStatusCard(MobileAppState state, Color accent, bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF22223A) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(Icons.touch_app, color: accent, size: 20),
          const SizedBox(width: 8),
          Text('已执行 ${state.clickCount} 次',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87)),
        ]),
      ),
    );
  }

  // ─── Touch Action Selector ────────────────────────────────

  Widget _touchActionSelector(MobileAppState state, ClickerConfig config,
      Color accent, bool isDark) {
    final actions = {
      TouchAction.tap: ('点击', Icons.touch_app),
      TouchAction.longPress: ('长按', Icons.back_hand),
      TouchAction.drag: ('拖动', Icons.open_with),
      TouchAction.swipe: ('滑动', Icons.swipe),
    };
    return Wrap(spacing: 8, runSpacing: 6, children: actions.entries.map((e) =>
      _actionChip(e.value.$1, e.value.$2, config.touchAction == e.key, accent, isDark,
          () => state.setClickerConfig(config.copyWith(touchAction: e.key))),
    ).toList());
  }

  Widget _actionChip(String label, IconData icon, bool selected, Color accent,
      bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? accent : (isDark ? const Color(0xFF404060) : const Color(0xFFD0D0E0))),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16,
              color: selected ? accent : (isDark ? Colors.grey : Colors.black54)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: selected ? accent : (isDark ? Colors.grey : Colors.black54),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }

  // ─── Action-specific Settings ─────────────────────────────

  Widget _buildActionSettings(BuildContext context, MobileAppState state,
      ClickerConfig config, Color accent, bool isDark) {
    switch (config.touchAction) {
      case TouchAction.longPress:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('长按时长', isDark),
          Row(children: [
            Expanded(child: Slider(
              value: config.longPressDurationMs.clamp(100, 5000).toDouble(),
              min: 100, max: 5000,
              divisions: 49,
              activeColor: accent,
              onChanged: (v) => state.setClickerConfig(
                  config.copyWith(longPressDurationMs: v.round())),
            )),
            SizedBox(
              width: 70,
              child: Text('${config.longPressDurationMs} ms',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87)),
            ),
          ]),
        ]);

      case TouchAction.drag:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('拖动起止点', isDark),
          Card(
            color: isDark ? const Color(0xFF22223A) : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                // Start point
                Row(children: [
                  Text('起点', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87)),
                  const Spacer(),
                  _coordLabel(config.dragStartX, config.dragStartY, isDark),
                  const SizedBox(width: 8),
                  _pickButton('选择起点', accent, () => _pickDragStart(context, state, config)),
                ]),
                const Divider(height: 20),
                // End point
                Row(children: [
                  Text('终点', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87)),
                  const Spacer(),
                  _coordLabel(config.dragEndX, config.dragEndY, isDark),
                  const SizedBox(width: 8),
                  _pickButton('选择终点', accent, () => _pickDragEnd(context, state, config)),
                ]),
                const Divider(height: 20),
                // Duration
                Row(children: [
                  Text('拖动时长', style: TextStyle(fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black87)),
                  const Spacer(),
                  SizedBox(
                    width: 80,
                    child: DebouncedNumberField(
                      label: 'ms',
                      value: config.swipeDurationMs,
                      min: 50,
                      max: 10000,
                      isDark: isDark,
                      onChanged: (v) => state.setClickerConfig(
                          config.copyWith(swipeDurationMs: v)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ]);

      case TouchAction.swipe:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('滑动起止点', isDark),
          Card(
            color: isDark ? const Color(0xFF22223A) : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  Text('起点', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87)),
                  const Spacer(),
                  _coordLabel(config.swipeStartX, config.swipeStartY, isDark),
                  const SizedBox(width: 8),
                  _pickButton('选择起点', accent, () => _pickSwipeStart(context, state, config)),
                ]),
                const Divider(height: 20),
                Row(children: [
                  Text('终点', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87)),
                  const Spacer(),
                  _coordLabel(config.swipeEndX, config.swipeEndY, isDark),
                  const SizedBox(width: 8),
                  _pickButton('选择终点', accent, () => _pickSwipeEnd(context, state, config)),
                ]),
                const Divider(height: 20),
                Row(children: [
                  Text('滑动时长', style: TextStyle(fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black87)),
                  const Spacer(),
                  SizedBox(
                    width: 80,
                    child: DebouncedNumberField(
                      label: 'ms',
                      value: config.swipeDurationMs,
                      min: 50,
                      max: 10000,
                      isDark: isDark,
                      onChanged: (v) => state.setClickerConfig(
                          config.copyWith(swipeDurationMs: v)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ]);

      case TouchAction.tap:
        return const SizedBox.shrink();
    }
  }

  // ─── Position Selector ────────────────────────────────────

  Widget _positionSelector(BuildContext context, MobileAppState state,
      ClickerConfig config, Color accent, bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF22223A) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          // Position mode chips
          Row(children: [
            _chip('当前位置', config.positionMode == PositionMode.current, accent, isDark,
                () => state.setClickerConfig(config.copyWith(positionMode: PositionMode.current))),
            const SizedBox(width: 8),
            _chip('选择位置', config.positionMode == PositionMode.pick, accent, isDark,
                () => state.setClickerConfig(config.copyWith(positionMode: PositionMode.pick))),
            const SizedBox(width: 8),
            _chip('固定坐标', config.positionMode == PositionMode.fixed, accent, isDark,
                () => state.setClickerConfig(config.copyWith(positionMode: PositionMode.fixed))),
          ]),
          // Pick button or coordinate input
          if (config.positionMode == PositionMode.pick) ...[
            const SizedBox(height: 10),
            Row(children: [
              _coordLabel(config.fixedX, config.fixedY, isDark),
              const Spacer(),
              FilledButton.tonal(
                onPressed: () => _pickPosition(context, state, config),
                style: FilledButton.styleFrom(backgroundColor: accent.withValues(alpha: 0.15)),
                child: Text('屏幕取点', style: TextStyle(color: accent)),
              ),
            ]),
          ],
          if (config.positionMode == PositionMode.fixed) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: DebouncedNumberField(
                label: 'X', value: config.fixedX, min: 0, max: 99999,
                isDark: isDark,
                onChanged: (v) => state.setClickerConfig(config.copyWith(fixedX: v)),
              )),
              const SizedBox(width: 12),
              Expanded(child: DebouncedNumberField(
                label: 'Y', value: config.fixedY, min: 0, max: 99999,
                isDark: isDark,
                onChanged: (v) => state.setClickerConfig(config.copyWith(fixedY: v)),
              )),
            ]),
          ],
        ]),
      ),
    );
  }

  Future<void> _pickPosition(BuildContext context, MobileAppState state,
      ClickerConfig config) async {
    final result = await ScreenOverlayService.instance.startPick();
    if (result != null) {
      state.setClickerConfig(config.copyWith(
        fixedX: result.$1,
        fixedY: result.$2,
      ));
    }
  }

  Future<void> _pickDragStart(BuildContext context, MobileAppState state,
      ClickerConfig config) async {
    final result = await ScreenOverlayService.instance.startPick();
    if (result != null) {
      state.setClickerConfig(config.copyWith(
        dragStartX: result.$1,
        dragStartY: result.$2,
      ));
    }
  }

  Future<void> _pickDragEnd(BuildContext context, MobileAppState state,
      ClickerConfig config) async {
    final result = await ScreenOverlayService.instance.startPick();
    if (result != null) {
      state.setClickerConfig(config.copyWith(
        dragEndX: result.$1,
        dragEndY: result.$2,
      ));
    }
  }

  Future<void> _pickSwipeStart(BuildContext context, MobileAppState state,
      ClickerConfig config) async {
    final result = await ScreenOverlayService.instance.startPick();
    if (result != null) {
      state.setClickerConfig(config.copyWith(
        swipeStartX: result.$1,
        swipeStartY: result.$2,
      ));
    }
  }

  Future<void> _pickSwipeEnd(BuildContext context, MobileAppState state,
      ClickerConfig config) async {
    final result = await ScreenOverlayService.instance.startPick();
    if (result != null) {
      state.setClickerConfig(config.copyWith(
        swipeEndX: result.$1,
        swipeEndY: result.$2,
      ));
    }
  }

  // ─── Interval ─────────────────────────────────────────────

  Widget _intervalSlider(MobileAppState state, ClickerConfig config,
      Color accent, bool isDark) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('间隔',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(width: 12),
        SizedBox(
          width: 90,
          child: DebouncedNumberField(
            label: 'ms',
            value: config.intervalMs.round(),
            min: 10,
            max: 600000,
            isDark: isDark,
            onChanged: (v) => state.setClickerConfig(config.copyWith(intervalMs: v.toDouble())),
          ),
        ),
      ]),
      Slider(
        value: config.intervalMs.clamp(10, 5000),
        min: 10, max: 5000,
        divisions: 499,
        activeColor: accent,
        onChanged: (v) => state.setClickerConfig(config.copyWith(intervalMs: v)),
      ),
      Wrap(spacing: 6, children: [
        ('50ms', 50.0), ('100ms', 100.0), ('200ms', 200.0), ('500ms', 500.0), ('1秒', 1000.0),
      ].map((p) => _chip(p.$1, config.intervalMs == p.$2, accent, isDark,
          () => state.setClickerConfig(config.copyWith(intervalMs: p.$2)))).toList()),
    ]);
  }

  // ─── Repeat ───────────────────────────────────────────────

  Widget _repeatModeSelector(MobileAppState state, ClickerConfig config,
      Color accent, bool isDark) {
    return Wrap(spacing: 6, children: [
      _chip('无限', config.repeatMode == ClickRepeatMode.infinite, accent, isDark,
          () => state.setClickerConfig(config.copyWith(repeatMode: ClickRepeatMode.infinite))),
      _chip('按次数', config.repeatMode == ClickRepeatMode.count, accent, isDark,
          () => state.setClickerConfig(config.copyWith(repeatMode: ClickRepeatMode.count))),
      _chip('按时长', config.repeatMode == ClickRepeatMode.duration, accent, isDark,
          () => state.setClickerConfig(config.copyWith(repeatMode: ClickRepeatMode.duration))),
    ]);
  }

  Widget _repeatConfig(MobileAppState state, ClickerConfig config, bool isDark) {
    if (config.repeatMode == ClickRepeatMode.count) {
      return DebouncedNumberField(
        label: '次数',
        value: config.repeatCount,
        min: 1,
        max: 999999,
        isDark: isDark,
        onChanged: (v) => state.setClickerConfig(config.copyWith(repeatCount: v)),
      );
    }
    if (config.repeatMode == ClickRepeatMode.duration) {
      return DebouncedNumberField(
        label: '时长(秒)',
        value: config.durationSeconds,
        min: 1,
        max: 86400,
        isDark: isDark,
        onChanged: (v) => state.setClickerConfig(config.copyWith(durationSeconds: v)),
      );
    }
    return const SizedBox.shrink();
  }

  // ─── Helpers ──────────────────────────────────────────────

  Widget _sectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF9090B0) : const Color(0xFF6A6A80))),
    );
  }

  Widget _chip(String label, bool selected, Color accent, bool isDark,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? accent : (isDark ? const Color(0xFF404060) : const Color(0xFFD0D0E0))),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                color: selected ? accent : (isDark ? Colors.grey : Colors.black54),
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }

  Widget _coordLabel(int x, int y, bool isDark) {
    return Text('($x, $y)',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
            color: isDark ? Colors.white60 : Colors.black54));
  }

  Widget _pickButton(String label, Color accent, VoidCallback onTap) {
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: accent.withValues(alpha: 0.15),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: Size.zero,
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: accent)),
    );
  }

}
