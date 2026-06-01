part of '../home_screen.dart';

class _SettingsView extends StatelessWidget {
  const _SettingsView({
    super.key,
    required this.speechMode,
    required this.speechEngine,
    required this.networkOnline,
    required this.onBack,
    required this.onPreEntryTap,
    required this.onModeSelected,
    required this.onEngineSelected,
    required this.onNetworkTap,
  });

  final String speechMode;
  final String speechEngine;
  final bool networkOnline;
  final VoidCallback onBack;
  final VoidCallback onPreEntryTap;
  final ValueChanged<String> onModeSelected;
  final ValueChanged<String> onEngineSelected;
  final VoidCallback onNetworkTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      children: [
        const _SettingsSectionLabel('数据'),
        _SettingsGroup(
          children: [
            _SettingsTile(
              title: '数据预录入',
              subtitle: '老人信息、亲属、经历与照片统一管理',
              onTap: onPreEntryTap,
              showChevron: true,
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SettingsSectionLabel('语音'),
        _SettingsGroup(
          children: [
            _SettingsSubBlock(
              title: '听写引擎',
              helper: '推荐 vivo，本地代理需启动；失败可改系统识别',
              children: [
                _ModeButton(
                  label: 'vivo 听写（推荐）',
                  active: speechEngine == 'vivo',
                  onTap: () => onEngineSelected('vivo'),
                ),
                _ModeButton(
                  label: '系统听写（备用）',
                  active: speechEngine == 'system',
                  onTap: () => onEngineSelected('system'),
                ),
              ],
            ),
            const _SettingsRowDivider(),
            _SettingsSubBlock(
              title: '系统听写语言',
              helper: '仅在选择「系统听写」时生效',
              children: [
                _ModeButton(
                  label: '自动识别',
                  active: speechMode == '自动识别',
                  onTap: () => onModeSelected('自动识别'),
                ),
                _ModeButton(
                  label: '普通话优先',
                  active: speechMode == '普通话优先',
                  onTap: () => onModeSelected('普通话优先'),
                ),
                _ModeButton(
                  label: '方言优先',
                  active: speechMode == '方言优先',
                  onTap: () => onModeSelected('方言优先'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SettingsSectionLabel('系统'),
        _SettingsGroup(
          children: [
            _SettingsTile(
              title: '是否联网',
              subtitle: '默认离线可用，需要时再联网',
              trailing: _OnOffChip(online: networkOnline),
              onTap: onNetworkTap,
            ),
            const _SettingsRowDivider(),
            const _DatabasePathTile(),
          ],
        ),
      ],
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: AppTheme.textCaption,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surface1,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.borderHairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _SettingsRowDivider extends StatelessWidget {
  const _SettingsRowDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppTheme.borderHairline,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showChevron = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.text,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 19,
                          height: 1.4,
                          fontWeight: FontWeight.w400,
                          color: AppTheme.textSoft,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
              if (showChevron) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: AppTheme.textCaption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSubBlock extends StatelessWidget {
  const _SettingsSubBlock({
    required this.title,
    required this.helper,
    required this.children,
  });

  final String title;
  final String helper;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AppTheme.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            helper,
            style: const TextStyle(
              fontSize: 19,
              height: 1.4,
              fontWeight: FontWeight.w400,
              color: AppTheme.textSoft,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _OnOffChip extends StatelessWidget {
  const _OnOffChip({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: online ? AppTheme.primary : AppTheme.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
          color: online ? AppTheme.primary : AppTheme.borderHairline,
          width: 1,
        ),
      ),
      child: Text(
        online ? '已开启' : '已关闭',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: online ? Colors.white : AppTheme.primaryDeep,
        ),
      ),
    );
  }
}

class _DatabasePathTile extends StatelessWidget {
  const _DatabasePathTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: LocalDatabase.getDatabasePathForDebug(),
      builder: (context, snapshot) {
        final path = snapshot.data ?? '读取中...';
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '本地数据库文件',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                LocalDatabase.storageHint(),
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.textSoft,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                path,
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.4,
                  color: AppTheme.text,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
