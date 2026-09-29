import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 动态类型
enum FeedType {
  announcement('公告', Icons.campaign, Color(0xFF4A7DFF)),
  update('版本更新', Icons.system_update_alt, Color(0xFF00A88E)),
  newContent('新内容', Icons.pets, Color(0xFFFF7A45)),
  activity('活动', Icons.emoji_events, Color(0xFF8B5CF6));

  const FeedType(this.label, this.icon, this.color);

  /// 类型标签文案
  final String label;

  /// 类型图标
  final IconData icon;

  /// 类型主题色
  final Color color;
}

/// 官方动态数据模型
class FeedItem {
  final String id;
  final FeedType type;
  final String title;
  final String content;
  final DateTime time;
  final int likes;
  final int comments;
  final bool pinned;

  const FeedItem({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.time,
    required this.likes,
    required this.comments,
    this.pinned = false,
  });
}

/// 官方动态页面
/// 展示 MeowBiu 官方发布的版本更新、新内容与活动公告。
/// 当前使用内置示例数据，后续可替换为接口拉取。
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  /// 已点赞的动态 id 集合（本地交互状态）
  final Set<String> _likedIds = {};

  /// 内置官方动态数据（时间基于当前时刻计算，保证"刚刚/N小时前"显示自然）
  List<FeedItem> _loadFeedItems() {
    final now = DateTime.now();
    return [
      FeedItem(
        id: 'v1.4.13',
        type: FeedType.update,
        title: 'v1.4.13 版本更新：裁剪功能全面优化',
        content:
            '从视频提取音频的裁剪功能迎来重大升级：\n'
            '• 视频时长探测提速，选视频后秒级加载\n'
            '• 提取/裁切过程实时显示进度，支持中途取消\n'
            '• 精确/快速双模式，满足不同精度需求\n'
            '• 修复了裁剪范围错乱的问题',
        time: now.subtract(const Duration(hours: 2)),
        likes: 128,
        comments: 23,
        pinned: true,
      ),
      FeedItem(
        id: 'new-sounds-09',
        type: FeedType.newContent,
        title: '新一批萌猫叫声上线',
        content:
            '喵～这次新增了 10 种全新猫咪叫声，包含撒娇、踩奶、呼噜、生气等经典场景，快去首页听听有没有你家的同款！',
        time: now.subtract(const Duration(days: 1, hours: 3)),
        likes: 256,
        comments: 41,
      ),
      FeedItem(
        id: 'waveform-preview',
        type: FeedType.update,
        title: '功能预告：真实波形预览即将上线',
        content:
            '还在用滑块盲调裁切范围？下个版本将引入真实音频波形显示，裁切时可以直接看到声音的起伏，精确到每一个音节。敬请期待！',
        time: now.subtract(const Duration(days: 2)),
        likes: 89,
        comments: 15,
      ),
      FeedItem(
        id: 'miaow-contest',
        type: FeedType.activity,
        title: '首届"喵声大赛"开启报名',
        content:
            '晒出你家猫咪最特别的一声叫，点赞最高的 3 位铲屎官将获得官方限定猫猫徽章与定制周边。投稿方式：添加你的猫声并命名为「参赛-猫咪名字」。',
        time: now.subtract(const Duration(days: 4, hours: 5)),
        likes: 512,
        comments: 88,
      ),
      FeedItem(
        id: 'v1.4.12',
        type: FeedType.announcement,
        title: 'v1.4.12 版本更新说明',
        content:
            '本次更新：修复了部分设备上音频缓存导致的播放异常，优化了暗色主题下的对比度表现，并提升了长列表的滚动流畅度。',
        time: now.subtract(const Duration(days: 9)),
        likes: 67,
        comments: 9,
      ),
    ];
  }

  /// 相对时间格式化
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 2) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }

  /// 下拉刷新（模拟刷新，后续可替换为真实接口）
  Future<void> _onRefresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已是最新动态'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// 点赞切换
  void _toggleLike(FeedItem item) {
    setState(() {
      if (_likedIds.contains(item.id)) {
        _likedIds.remove(item.id);
      } else {
        _likedIds.add(item.id);
      }
    });
  }

  /// 查看动态详情
  void _showDetail(FeedItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _FeedDetailSheet(item: item, time: _formatTime(item.time)),
    );
  }

  /// 评论/分享提示（暂无后端，先占位）
  void _showPlaceholder(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _loadFeedItems();

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: Theme.of(context).colorScheme.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // 页面标题区
          _buildHeader(context),

          const SizedBox(height: 16),

          // 动态列表
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _FeedCard(
                item: item,
                timeText: _formatTime(item.time),
                liked: _likedIds.contains(item.id),
                onTap: () => _showDetail(item),
                onLike: () => _toggleLike(item),
                onComment: () => _showPlaceholder('评论功能即将上线'),
                onShare: () => _showPlaceholder('分享功能即将上线'),
              ),
            ),

          // 底部提示
          const SizedBox(height: 8),
          Center(
            child: Text(
              '— 已经到底啦 —',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 页面标题区
  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: SvgPicture.asset(
            'assets/images/icon_nav_cat.svg',
            height: 26,
            colorFilter: ColorFilter.mode(
              colorScheme.primary,
              BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '官方动态',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            Text(
              '喵语的最新消息都在这里',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 单条动态卡片
class _FeedCard extends StatelessWidget {
  final FeedItem item;
  final String timeText;
  final bool liked;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;

  const _FeedCard({
    required this.item,
    required this.timeText,
    required this.liked,
    required this.onTap,
    required this.onLike,
    required this.onComment,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final typeColor = item.type.color;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部：官方头像 + 昵称 + 时间 + 类型标签
              Row(
                children: [
                  // 官方头像
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: SvgPicture.asset(
                        'assets/images/cat_avatar_1.svg',
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'MeowBiu 官方',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            if (item.pinned) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '置顶',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: typeColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          timeText,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 类型标签
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(item.type.icon, size: 12, color: typeColor),
                        const SizedBox(width: 4),
                        Text(
                          item.type.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: typeColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 标题
              Text(
                item.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 6),

              // 正文（最多显示 3 行，详情见底部弹窗）
              Text(
                item.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),

              const SizedBox(height: 12),

              // 配图占位（后续接入真实图片时替换）
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      typeColor.withValues(alpha: 0.18),
                      typeColor.withValues(alpha: 0.06),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    item.type.icon,
                    size: 36,
                    color: typeColor.withValues(alpha: 0.55),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 互动条
              Row(
                children: [
                  // 点赞
                  _buildAction(
                    context,
                    icon: liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? Colors.redAccent : colorScheme.onSurfaceVariant,
                    label: '${item.likes + (liked ? 1 : 0)}',
                    onTap: onLike,
                  ),
                  const SizedBox(width: 24),
                  // 评论
                  _buildAction(
                    context,
                    icon: Icons.chat_bubble_outline,
                    color: colorScheme.onSurfaceVariant,
                    label: '${item.comments}',
                    onTap: onComment,
                  ),
                  const Spacer(),
                  // 分享
                  IconButton(
                    onPressed: onShare,
                    icon: Icon(
                      Icons.share_outlined,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: '分享',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAction(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// 动态详情底部弹窗
class _FeedDetailSheet extends StatelessWidget {
  final FeedItem item;
  final String time;

  const _FeedDetailSheet({required this.item, required this.time});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final typeColor = item.type.color;
    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: SvgPicture.asset(
                        'assets/images/cat_avatar_1.svg',
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MeowBiu 官方',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(item.type.icon, size: 12, color: typeColor),
                        const SizedBox(width: 4),
                        Text(
                          item.type.label,
                          style: TextStyle(
                            fontSize: 11,
                            color: typeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 标题
              Text(
                item.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 8),

              // 全文
              Text(
                item.content,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 16),

              // 配图占位
              Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      typeColor.withValues(alpha: 0.2),
                      typeColor.withValues(alpha: 0.06),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    item.type.icon,
                    size: 48,
                    color: typeColor.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
