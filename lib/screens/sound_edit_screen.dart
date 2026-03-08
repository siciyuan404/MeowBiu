import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../models/cat_sound.dart';
import '../providers/sound_provider.dart';
import '../services/audio_editor_service.dart';

/// 音频来源类型
enum AudioSource {
  localFile,   // 本地音频文件
  networkUrl,  // 网络链接
  videoExtract, // 从视频提取
  audioTrim,   // 裁切现有音频
}

/// 音频编辑屏幕
/// 支持添加新音频和裁切/提取现有音频
class SoundEditScreen extends ConsumerStatefulWidget {
  final CatSound? sound;
  final String? categoryId;
  
  const SoundEditScreen({
    Key? key, 
    this.sound,
    this.categoryId,
  }) : super(key: key);

  @override
  ConsumerState<SoundEditScreen> createState() => _SoundEditScreenState();
}

class _SoundEditScreenState extends ConsumerState<SoundEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  
  AudioSource _source = AudioSource.localFile;
  String? _localFilePath;
  bool _isLoading = false;
  
  // 裁切相关
  double _trimStart = 0;
  double _trimEnd = 0;
  double _totalDuration = 0;
  double _processingProgress = 0;
  bool _isProcessing = false;
  
  // 音频播放器
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isPreviewReady = false;
  
  // 裁切模式：精确 vs 快速
  bool _preciseTrim = false;
  
  @override
  void initState() {
    super.initState();
    
    // 如果是编辑模式，填充已有数据
    if (widget.sound != null) {
      _nameController.text = widget.sound!.name;
      
      if (widget.sound!.sourceType == AudioSourceType.local) {
        _source = AudioSource.localFile;
        _localFilePath = widget.sound!.audioPath;
      } else if (widget.sound!.sourceType == AudioSourceType.network) {
        _source = AudioSource.networkUrl;
        _urlController.text = widget.sound!.audioPath;
      }
    }
    
    // 监听播放状态
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
        
        // 播放完成后自动停止
        if (state.processingState == ProcessingState.completed) {
          _audioPlayer.stop();
          _audioPlayer.seek(Duration(milliseconds: (_trimStart * 1000).toInt()));
        }
      }
    });
    
    // 监听位置用于预览
    _audioPlayer.positionStream.listen((position) {
      if (mounted && _isPlaying) {
        // 如果播放超出裁切范围，自动停止
        if (position.inMilliseconds / 1000 >= _trimEnd) {
          _audioPlayer.stop();
        }
      }
    });
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
  
  /// 选择本地音频文件
  Future<void> _pickAudioFile() async {
    try {
      final XTypeGroup audioGroup = XTypeGroup(
        label: '音频文件',
        extensions: ['mp3', 'wav', 'ogg', 'aac', 'm4a', 'flac'],
      );
      
      final XFile? file = await openFile(
        acceptedTypeGroups: [audioGroup],
      );
      
      if (file != null) {
        setState(() {
          _localFilePath = file.path;
          _trimStart = 0;
          _trimEnd = 0;
          _totalDuration = 0;
        });
        await _loadAudioDuration(file.path);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败: $e')),
      );
    }
  }
  
  /// 选择本地视频文件
  Future<void> _pickVideoFile() async {
    try {
      final XTypeGroup videoGroup = XTypeGroup(
        label: '视频文件',
        extensions: ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'],
      );
      
      final XFile? file = await openFile(
        acceptedTypeGroups: [videoGroup],
      );
      
      if (file != null) {
        setState(() {
          _localFilePath = file.path;
          _trimStart = 0;
          _trimEnd = 0;
        });
        
        // 获取视频时长
        final duration = await AudioEditorService.getMediaDuration(file.path);
        if (duration != null && mounted) {
          setState(() {
            _totalDuration = duration;
            _trimEnd = duration;
          });
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已选择视频: ${file.name}\n时长: ${_formatDuration(_totalDuration)}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择视频失败: $e')),
      );
    }
  }
  
  /// 加载音频时长
  Future<void> _loadAudioDuration(String path) async {
    try {
      // 先尝试用 just_audio 获取
      var duration = await _audioPlayer.setFilePath(path);
      
      if (duration == null) {
        // 备用：用 FFprobe 获取
        final probeDuration = await AudioEditorService.getMediaDuration(path);
        if (probeDuration != null) {
          duration = Duration(milliseconds: (probeDuration * 1000).toInt());
        }
      }
      
      if (duration != null && mounted) {
        setState(() {
          _totalDuration = duration.inMilliseconds / 1000.0;
          _trimEnd = _totalDuration;
          _isPreviewReady = true;
        });
      }
    } catch (e) {
      print('Error loading audio: $e');
    }
  }
  
  /// 播放/暂停预览
  Future<void> _playPreview() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.stop();
      } else {
        if (_localFilePath != null) {
          // 设置裁切范围播放
          if (!_isPreviewReady) {
            await _audioPlayer.setFilePath(_localFilePath!);
            _isPreviewReady = true;
          }
          
          // 跳转到开始位置
          await _audioPlayer.seek(Duration(milliseconds: (_trimStart * 1000).toInt()));
          await _audioPlayer.play();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('播放失败: $e')),
      );
    }
  }
  
  /// 停止播放
  Future<void> _stopPreview() async {
    await _audioPlayer.stop();
  }
  
  /// 从视频提取音频
  Future<void> _extractAudioFromVideo() async {
    if (_localFilePath == null) return;
    if (_trimEnd - _trimStart <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请设置有效的裁切范围')),
      );
      return;
    }
    
    setState(() {
      _isProcessing = true;
      _processingProgress = 0;
    });
    
    try {
      final result = await AudioEditorService.extractAudioFromVideo(
        videoPath: _localFilePath!,
        startTime: _trimStart,
        duration: _trimEnd - _trimStart,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _processingProgress = progress);
          }
        },
      );
      
      if (result != null && mounted) {
        setState(() {
          _localFilePath = result;
          _source = AudioSource.localFile;
          _trimStart = 0;
          _trimEnd = _totalDuration;
        });
        await _loadAudioDuration(result);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('音频提取成功!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('音频提取失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提取失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingProgress = 0;
        });
      }
    }
  }
  
  /// 裁切音频
  Future<void> _trimAudio() async {
    if (_localFilePath == null) return;
    if (_trimEnd - _trimStart <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请设置有效的裁切范围')),
      );
      return;
    }
    
    setState(() {
      _isProcessing = true;
      _processingProgress = 0;
    });
    
    try {
      final result = await AudioEditorService.trimAudio(
        audioPath: _localFilePath!,
        startTime: _trimStart,
        duration: _trimEnd - _trimStart,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _processingProgress = progress);
          }
        },
      );
      
      if (result != null && mounted) {
        setState(() {
          _localFilePath = result;
          _trimStart = 0;
          _trimEnd = _totalDuration;
        });
        await _loadAudioDuration(result);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('音频裁切成功!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('音频裁切失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('裁切失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingProgress = 0;
        });
      }
    }
  }
  
  /// 设置裁切范围预设
  void _setTrimPreset(String preset) {
    if (_totalDuration <= 0) return;
    
    setState(() {
      switch (preset) {
        case '1s':
          _trimStart = 0;
          _trimEnd = 1;
          break;
        '3s':
          _trimStart = 0;
          _trimEnd = 3;
          break;
        '5s':
          _trimStart = 0;
          _trimEnd = 5;
          break;
        '10s':
          _trimStart = 0;
          _trimEnd = 10 > _totalDuration ? _totalDuration : 10;
          break;
        'full':
          _trimStart = 0;
          _trimEnd = _totalDuration;
          break;
        'half':
          _trimStart = 0;
          _trimEnd = _totalDuration / 2;
          break;
        'middle':
          final center = _totalDuration / 2;
          _trimStart = (center - 2.5).clamp(0, _totalDuration);
          _trimEnd = (center + 2.5).clamp(0, _totalDuration);
          break;
      }
    });
  }
  
  /// 保存猫声
  Future<void> _saveSound() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    final name = _nameController.text.trim();
    String audioPath;
    AudioSourceType sourceType;
    
    switch (_source) {
      case AudioSource.localFile:
      case AudioSource.videoExtract:
      case AudioSource.audioTrim:
        if (_localFilePath == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请先选择文件')),
          );
          return;
        }
        audioPath = _localFilePath!;
        sourceType = AudioSourceType.local;
        break;
      case AudioSource.networkUrl:
        audioPath = _urlController.text.trim();
        sourceType = AudioSourceType.network;
        break;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final soundManager = ref.read(soundManagerProvider.notifier);
      
      if (widget.sound == null) {
        await soundManager.addSound(
          name: name,
          audioPath: audioPath,
          sourceType: sourceType,
          categoryId: widget.categoryId,
        );
      } else {
        final updatedSound = CatSound(
          id: widget.sound!.id,
          name: name,
          audioPath: audioPath,
          sourceType: sourceType,
          cachedPath: sourceType == widget.sound!.sourceType ? widget.sound!.cachedPath : null,
          playCount: widget.sound!.playCount,
          lastPlayed: widget.sound!.lastPlayed,
        );
        
        await soundManager.updateSound(updatedSound);
      }
      
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  /// 清除缓存
  Future<void> _clearCache() async {
    if (widget.sound == null || !widget.sound!.isCached) {
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      final result = await ref.read(soundManagerProvider.notifier).clearSoundCache(widget.sound!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result ? '缓存已清除' : '清除缓存失败')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除缓存失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final isEditing = widget.sound != null;
    final showTrimControls = (_source == AudioSource.videoExtract || _source == AudioSource.audioTrim) 
        && _localFilePath != null && _totalDuration > 0;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑猫声' : '添加猫声'),
        actions: [
          if (isEditing && widget.sound!.isCached)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearCache,
              tooltip: '清除缓存',
            ),
        ],
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 名称输入
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    hintText: '输入猫声名称',
                    prefixIcon: Icon(Icons.pets),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入名称';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 24),
                
                // 音频来源选择
                const Text(
                  '音频来源',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                
                _buildSourceOption(
                  icon: Icons.folder_open,
                  title: '本地音频文件',
                  subtitle: '选择 MP3、WAV 等音频文件',
                  value: AudioSource.localFile,
                ),
                _buildSourceOption(
                  icon: Icons.link,
                  title: '网络链接',
                  subtitle: '输入音频文件的 URL',
                  value: AudioSource.networkUrl,
                ),
                _buildSourceOption(
                  icon: Icons.video_file,
                  title: '从视频提取音频',
                  subtitle: '从视频文件中提取并裁切音频',
                  value: AudioSource.videoExtract,
                ),
                _buildSourceOption(
                  icon: Icons.content_cut,
                  title: '裁切现有音频',
                  subtitle: '对音频文件进行裁切',
                  value: AudioSource.audioTrim,
                ),
                
                const SizedBox(height: 16),
                
                // 来源详情
                _buildSourceDetails(),
                
                // 裁切控制面板
                if (showTrimControls) ...[
                  const SizedBox(height: 24),
                  _buildTrimControls(),
                ],
                
                // 处理按钮
                if (showTrimControls && (_trimEnd - _trimStart > 0)) ...[
                  const SizedBox(height: 16),
                  _buildProcessButton(),
                ],
                
                const SizedBox(height: 24),
                
                // 缓存状态（仅编辑模式）
                if (isEditing && widget.sound!.isNetworkSource) ...[
                  Card(
                    child: ListTile(
                      leading: Icon(
                        widget.sound!.isCached ? Icons.check_circle : Icons.info_outline,
                        color: widget.sound!.isCached ? Colors.green : null,
                      ),
                      title: Text(widget.sound!.isCached ? '已缓存' : '未缓存'),
                      subtitle: widget.sound!.isCached 
                          ? const Text('点击右上角按钮可清除缓存')
                          : const Text('首次播放后将自动缓存'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                // 保存按钮
                ElevatedButton(
                  onPressed: _isLoading ? null : _saveSound,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: _isLoading 
                      ? const CircularProgressIndicator()
                      : Text(isEditing ? '保存' : '添加'),
                ),
                
                // 底部安全区域
                const SizedBox(height: 32),
              ],
            ),
          ),
          
          // 处理中的遮罩层
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(32),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _source == AudioSource.videoExtract 
                              ? '正在提取音频...' 
                              : '正在裁切音频...',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _processingProgress > 0 ? _processingProgress : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_processingProgress * 100).toInt()}%',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildSourceOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required AudioSource value,
  }) {
    final isSelected = _source == value;
    
    return Card(
      elevation: isSelected ? 2 : 0,
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: RadioListTile<AudioSource>(
        value: value,
        groupValue: _source,
        onChanged: (v) {
          setState(() {
            _source = v!;
            _stopPreview();
          });
        },
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(subtitle),
        secondary: Icon(icon),
      ),
    );
  }
  
  Widget _buildSourceDetails() {
    switch (_source) {
      case AudioSource.localFile:
        return _buildLocalFileSelector();
      case AudioSource.networkUrl:
        return _buildNetworkUrlInput();
      case AudioSource.videoExtract:
      case AudioSource.audioTrim:
        return _buildMediaFileSelector();
    }
  }
  
  Widget _buildLocalFileSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _pickAudioFile,
          icon: const Icon(Icons.folder_open),
          label: const Text('选择音频文件'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        if (_localFilePath != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  File(_localFilePath!).uri.pathSegments.last,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_totalDuration > 0) ...[
                const SizedBox(width: 8),
                Text(
                  _formatDuration(_totalDuration),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
  
  Widget _buildNetworkUrlInput() {
    return TextFormField(
      controller: _urlController,
      decoration: const InputDecoration(
        labelText: '音频 URL',
        hintText: 'https://example.com/audio.mp3',
        prefixIcon: Icon(Icons.link),
      ),
      validator: (value) {
        if (_source != AudioSource.networkUrl) return null;
        if (value == null || value.trim().isEmpty) {
          return '请输入 URL';
        }
        final uri = Uri.tryParse(value);
        if (uri == null || !uri.isAbsolute) {
          return '请输入有效的 URL';
        }
        return null;
      },
    );
  }
  
  Widget _buildMediaFileSelector() {
    final isVideo = _source == AudioSource.videoExtract;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: isVideo ? _pickVideoFile : _pickAudioFile,
          icon: Icon(isVideo ? Icons.video_file : Icons.audio_file),
          label: Text(isVideo ? '选择视频文件' : '选择音频文件'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        if (_localFilePath != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  File(_localFilePath!).uri.pathSegments.last,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_totalDuration > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatDuration(_totalDuration),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
  
  Widget _buildTrimControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                const Icon(Icons.content_cut, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '裁切设置',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                // 快速裁切开关
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('精确', style: TextStyle(fontSize: 12)),
                    Switch(
                      value: _preciseTrim,
                      onChanged: (value) => setState(() => _preciseTrim = value),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // 快速预设按钮
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPresetChip('1s', '1秒'),
                _buildPresetChip('3s', '3秒'),
                _buildPresetChip('5s', '5秒'),
                _buildPresetChip('10s', '10秒'),
                _buildPresetChip('half', '一半'),
                _buildPresetChip('middle', '中间5秒'),
                _buildPresetChip('full', '完整'),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // 波形/进度可视化区域
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _buildWaveformVisualization(),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 开始时间滑块
            _buildTimeSlider(
              label: '开始',
              value: _trimStart,
              min: 0,
              max: _totalDuration,
              onChanged: (value) {
                setState(() {
                  _trimStart = value;
                  if (_trimEnd <= _trimStart) {
                    _trimEnd = (_trimStart + 1).clamp(0, _totalDuration);
                  }
                });
              },
              activeColor: Colors.green,
            ),
            
            // 结束时间滑块
            _buildTimeSlider(
              label: '结束',
              value: _trimEnd,
              min: 0,
              max: _totalDuration,
              onChanged: (value) {
                setState(() {
                  _trimEnd = value;
                  if (_trimEnd <= _trimStart) {
                    _trimStart = (_trimEnd - 1).clamp(0, _totalDuration);
                  }
                });
              },
              activeColor: Colors.red,
            ),
            
            const SizedBox(height: 8),
            
            // 时长信息与预览
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          '裁切后时长',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDuration(_trimEnd - _trimStart),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 预览按钮
                FilledButton.icon(
                  onPressed: _playPreview,
                  icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                  label: Text(_isPlaying ? '停止' : '预览'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(100, 48),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildPresetChip(String value, String label) {
    return ActionChip(
      label: Text(label),
      onPressed: () => _setTrimPreset(value),
    );
  }
  
  Widget _buildWaveformVisualization() {
    // 简化的波形可视化
    // 实际项目中可以使用 audio_waveforms 包获取真实波形数据
    return CustomPaint(
      size: const Size(double.infinity, 60),
      painter: WaveformPainter(
        trimStart: _trimStart,
        trimEnd: _trimEnd,
        totalDuration: _totalDuration,
        waveformColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        selectedColor: Theme.of(context).colorScheme.primary,
        backgroundColor: Colors.transparent,
      ),
    );
  }
  
  Widget _buildTimeSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required Color activeColor,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: activeColor,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: activeColor,
              thumbColor: activeColor,
              inactiveTrackColor: activeColor.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            _formatDuration(value),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildProcessButton() {
    final isExtract = _source == AudioSource.videoExtract;
    
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isProcessing ? null : () {
              // 重置为完整长度
              setState(() {
                _trimStart = 0;
                _trimEnd = _totalDuration;
              });
            },
            icon: const Icon(Icons.refresh),
            label: const Text('重置'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: _isProcessing 
                ? null 
                : (isExtract ? _extractAudioFromVideo : _trimAudio),
            icon: Icon(isExtract ? Icons.music_note : Icons.content_cut),
            label: Text(isExtract ? '提取音频' : '裁切音频'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
      ],
    );
  }
  
  String _formatDuration(double seconds) {
    if (seconds < 0) seconds = 0;
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = ((seconds * 100) % 100).floor();
    
    if (mins > 0) {
      return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }
}

/// 波形可视化画笔
class WaveformPainter extends CustomPainter {
  final double trimStart;
  final double trimEnd;
  final double totalDuration;
  final Color waveformColor;
  final Color selectedColor;
  final Color backgroundColor;
  
  WaveformPainter({
    required this.trimStart,
    required this.trimEnd,
    required this.totalDuration,
    required this.waveformColor,
    required this.selectedColor,
    required this.backgroundColor,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (totalDuration <= 0) return;
    
    final startX = (trimStart / totalDuration) * size.width;
    final endX = (trimEnd / totalDuration) * size.width;
    
    // 绘制未选中区域（变暗）
    final unselectedPaint = Paint()
      ..color = waveformColor
      ..style = PaintingStyle.fill;
    
    // 左侧未选中
    canvas.drawRect(
      Rect.fromLTWH(0, 0, startX, size.height),
      unselectedPaint,
    );
    
    // 右侧未选中
    canvas.drawRect(
      Rect.fromLTWH(endX, 0, size.width - endX, size.height),
      unselectedPaint,
    );
    
    // 绘制选中区域边框
    final selectedBorderPaint = Paint()
      ..color = selectedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawRect(
      Rect.fromLTWH(startX, 0, endX - startX, size.height),
      selectedBorderPaint,
    );
    
    // 绘制模拟波形（在选中区域内）
    final wavePaint = Paint()
      ..color = selectedColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    
    final waveWidth = 3.0;
    final waveGap = 2.0;
    final centerY = size.height / 2;
    
    // 生成伪随机波形（实际项目应使用真实波形数据）
    for (var i = startX; i < endX; i += waveWidth + waveGap) {
      final height = 8 + ((((i * 7) % 17) + 3) % 20);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(i + waveWidth / 2, centerY),
            width: waveWidth,
            height: height,
          ),
          const Radius.circular(1),
        ),
        wavePaint,
      );
    }
    
    // 绘制手柄
    final handlePaint = Paint()
      ..color = selectedColor
      ..style = PaintingStyle.fill;
    
    // 开始手柄
    canvas.drawCircle(Offset(startX, size.height / 2), 6, handlePaint);
    
    // 结束手柄
    canvas.drawCircle(Offset(endX, size.height / 2), 6, handlePaint);
  }
  
  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return trimStart != oldDelegate.trimStart ||
           trimEnd != oldDelegate.trimEnd ||
           totalDuration != oldDelegate.totalDuration;
  }
}
