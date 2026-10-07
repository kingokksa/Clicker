import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../models/clicker_config.dart';
import '../../models/click_settings.dart';
import '../../services/app_state.dart';
import '../../widgets/click_settings_panel.dart';

class HumanizePage extends StatelessWidget {
  const HumanizePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final config = state.clickerConfig;
    final settings = ClickSettings.fromConfig(config);

    Widget panel(List<ClickSettingGroup> groups) => ClickSettingsPanel(
      settings: settings,
      groups: groups,
      onChanged: (s) => state.setClickerConfig(s.applyTo(config)),
    );

    return ScaffoldPage.scrollable(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Icon(FluentIcons.accounts, size: 20, color: state.accentColor),
          const SizedBox(width: 10),
          const Text('拟人模式', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 16),
        _card(context, title: '拟人模式', icon: FluentIcons.accounts,
          child: panel(const [ClickSettingGroup.humanLike])),
        const SizedBox(height: 12),
        _card(context, title: '随机延迟', icon: FluentIcons.clock,
          child: panel(const [ClickSettingGroup.randomDelay])),
        const SizedBox(height: 12),
        _card(context, title: '随机偏移', icon: FluentIcons.open_in_new_tab,
          child: panel(const [ClickSettingGroup.randomOffset])),
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

  Widget _buildJitter(BuildContext context, ClickerConfig config, AppState state) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
