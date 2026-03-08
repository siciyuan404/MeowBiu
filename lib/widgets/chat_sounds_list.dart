import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/cat_sound.dart';
import '../providers/sound_provider.dart';
import 'chat_bubble.dart';

// 修改为有状态组件
class ChatSoundsList extends ConsumerStatefulWidget {
  final String categoryId;
  final VoidCallback onAddSound;
  final Function(CatSound) onEditSound;
  final Function(CatSound) onDeleteSound;
  final Function(CatSound) onClearCache;
  final Function(CatSound) onCopySound;
  
  const ChatSoundsList({
    Key? key,
    required this.categoryId,
    required this.onAddSound,
    required this.onEditSound,
    required this.onDeleteSound,
    required this.onClearCache,
    required this.onCopySound,
  }) : super(key: key);
  
  @override
  ConsumerState<ChatSoundsList> createState() => _ChatSoundsListState();
}

class _ChatSoundsListState extends ConsumerState<ChatSoundsList> {
  // 添加滚动控制器
  final ScrollController _scrollController = ScrollController();
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final soundsAsync = ref.watch(categorySoundsProvider(widget.categoryId));
    final theme = Theme.of(context);
    
    // 与AppBar相同的背景颜色
    final appBarBackgroundColor = const Color(0xFFF9F9F9);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: soundsAsync.when(
        data: (sounds) {
          if (sounds.isEmpty) {
            return const Center(
              child: Text('暂无音频，点击底部 + 按钮添加喵音~'),
            );
          }
          
          // 使用Stack和ShaderMask实现渐隐效果
          return Stack(
            children: [
              // 顶部渐隐效果
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 60, // 顶部渐隐区域高度
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        appBarBackgroundColor.withOpacity(0.0),
                        appBarBackgroundColor,
                      ],
                    ),
                  ),
                ),
              ),
              
              // 底部渐隐效果
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 100, // 渐隐区域高度
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        appBarBackgroundColor.withOpacity(0.0),
                        appBarBackgroundColor,
                      ],
                    ),
                  ),
                ),
              ),
              
              // 列表视图
              ListView.builder(
                controller: _scrollController,
                itemCount: sounds.length,
                padding: const EdgeInsets.only(bottom: 100), // 为渐隐区域留出空间
                itemBuilder: (context, index) {
                  final sound = sounds[index];
                  
                  return ChatBubble(
                    sound: sound,
                    avatarIndex: index,
                    onLongPress: () => _showSoundOptions(context, sound),
                  );
                },
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text('加载失败: $error'),
        ),
      ),
    );
  }

  // 显示音频操作选项
  void _showSoundOptions(BuildContext context, CatSound sound) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.of(context).pop();
                widget.onEditSound(sound);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制'),
              onTap: () {
                Navigator.of(context).pop();
                widget.onCopySound(sound);
              },
            ),
            if (sound.isNetworkSource && sound.isCached)
              ListTile(
                leading: const Icon(Icons.cleaning_services),
                title: const Text('清理缓存'),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onClearCache(sound);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.of(context).pop();
                widget.onDeleteSound(sound);
              },
            ),
          ],
        ),
      ),
    );
  }
} 