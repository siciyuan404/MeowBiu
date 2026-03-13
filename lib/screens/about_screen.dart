import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/preference_service.dart';
import '../screens/update_page.dart';

/// 关于页面
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  PackageInfo _packageInfo = PackageInfo(
    appName: 'MeowBiu',
    packageName: 'com.example.meowbiu',
    version: '1.3.3',
    buildNumber: '3',
  );

  bool _autoUpdateEnabled = true;
  bool _updateSupported = true;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _loadUpdatePreferences();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _packageInfo = info;
    });
  }

  Future<void> _loadUpdatePreferences() async {
    final prefService = PreferenceService();
    await prefService.init();
    
    final enabled = prefService.isAutoUpdateEnabled();
    final supported = await prefService.isAutoUpdateSupported();
    
    setState(() {
      _autoUpdateEnabled = enabled;
      _updateSupported = supported;
    });
  }

  Future<void> _setAutoUpdateEnabled(bool value) async {
    final prefService = PreferenceService();
    await prefService.init();
    await prefService.setAutoUpdateEnabled(value);
    
    setState(() {
      _autoUpdateEnabled = value;
    });
  }

  Future<void> _copyToClipboard(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开链接')),
        );
      }
    }
  }

  void _navigateToUpdatePage() {
    Navigator.push(
      context, 
      MaterialPageRoute(builder: (context) => const UpdatePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 顶部应用栏
          SliverAppBar.large(
            title: const Text('关于'),
            centerTitle: true,
            pinned: true,
            floating: false,
            expandedHeight: 150,
            scrolledUnderElevation: 4.0,
            // 支持滚动收缩效果
            automaticallyImplyLeading: true,
          ),
          
          // 内容列表
          SliverList(
            delegate: SliverChildListDelegate([
              // README 项
              _buildListItem(
                context,
                icon: Icons.description_outlined,
                title: 'README',
                description: '查看GitHub项目地址与应用说明',
                onTap: () => _launchUrl('https://github.com/mxrain/MeowBiu'),
              ),
              
              // 版本发布项
              _buildListItem(
                context,
                icon: Icons.new_releases_outlined,
                title: '版本发布',
                description: '查看最新版本与更新日记',
                onTap: () => _launchUrl('https://github.com/mxrain/MeowBiu/releases'),
              ),
              
              // 自动更新项
              _buildListItem(
                context,
                icon: _autoUpdateEnabled && _updateSupported
                    ? Icons.update_outlined
                    : Icons.update_disabled_outlined,
                title: '自动更新',
                description: _updateSupported 
                    ? '检查并下载应用更新'
                    : '当前版本不支持自动更新',
                trailing: Switch(
                  value: _autoUpdateEnabled && _updateSupported,
                  onChanged: _updateSupported
                    ? (value) => _setAutoUpdateEnabled(value)
                    : null,
                ),
                onTap: _navigateToUpdatePage,
              ),
              
              // 版本信息项
              _buildListItem(
                context,
                icon: Icons.info_outlined,
                title: 'MeowBiu v${_packageInfo.version}',
                description: 'Build ${_packageInfo.buildNumber}',
                onTap: () {
                  final detailInfo = '应用名称: ${_packageInfo.appName}\n'
                      '包名: ${_packageInfo.packageName}\n'
                      '版本: ${_packageInfo.version}\n'
                      '构建号: ${_packageInfo.buildNumber}';
                  
                  _copyToClipboard(detailInfo, '版本信息已复制到剪贴板');
                },
              ),
              
              // 包名信息项
              _buildListItem(
                context,
                icon: null,
                title: 'Package name',
                description: _packageInfo.packageName,
                onTap: () {
                  _copyToClipboard(_packageInfo.packageName, '包名已复制到剪贴板');
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildListItem(
    BuildContext context, {
    IconData? icon,
    required String title,
    required String description,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      leading: icon != null
          ? Icon(
              icon,
              color: colorScheme.primary,
              size: 28,
            )
          : const SizedBox(width: 28),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
            ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ),
      trailing: trailing,
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
    );
  }
} 