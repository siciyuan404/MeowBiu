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
  bool _isProcessing = false;
  
  // 音频播放器
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  
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
        extensions: ['mp3', 'wav', 'ogg', 'aac', 'm4a'],
      );
      
      final XFile? file = await openFile(
        acceptedTypeGroups: [audioGroup],
      );
      
      if (file != null) {
        setState(() {
          _localFilePath = file.path;
          _trimStart = 0;
          _trimEnd = 0;
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
        extensions: ['mp4', 'mov', 'avi', 'mkv', 'webm'],
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
      final duration = await _audioPlayer.setFilePath(path);
      if (duration != null && mounted) {
        setState(() {
          _totalDuration = duration.inMilliseconds / 1000.0;
          _trimEnd = _totalDuration;
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
          await _audioPlayer.setFilePath(_localFilePath!);
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
    
    setState(() => _isProcessing = true);
    
    try {
      final result = await AudioEditorService.extractAudioFromVideo(
        videoPath: _localFilePath!,
        startTime: _trimStart,
        duration: _trimEnd - _trimStart,
      );
      
      if (result != null && mounted) {
        setState(() {
          _localFilePath = result;
          _source = AudioSource.localFile; // 转换为本地文件
        });
        await _loadAudioDuration(result);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音频提取成功!')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音频提取失败')),
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
        setState(() => _isProcessing = false);
      }
    }
  }
  
  /// 裁切音频
  Future<void> _trimAudio() async {
    if (_localFilePath == null) return;
    
    setState(() => _isProcessing = true);
    
    try {
      final result = await AudioEditorService.trimAudio(
        audioPath: _localFilePath!,
        startTime: _trimStart,
        duration: _trimEnd - _trimStart,
      );
      
      if (result != null && mounted) {
        setState(() {
          _localFilePath = result;
          _trimStart = 0;
          _trimEnd = _totalDuration;
        });
        await _loadAudioDuration(result);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音频裁切成功!')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音频裁切失败')),
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
        setState(() => _isProcessing = false);
      }
    }
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
      body: Form(
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
            
            // 裁切控制（仅对视频提取和音频裁切显示）
            if ((_source == AudioSource.videoExtract || _source == AudioSource.audioTrim) 
                && _localFilePath != null) ...[
              const SizedBox(height: 24),
              _buildTrimControls(),
            ],
            
            // 处理按钮
            if ((_source == AudioSource.videoExtract || _source == AudioSource.audioTrim) 
                && _localFilePath != null
                && (_trimEnd - _trimStart > 0)) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isProcessing 
                    ? null 
                    : (_source == AudioSource.videoExtract 
                        ? _extractAudioFromVideo 
                        : _trimAudio),
                icon: _isProcessing 
                    ? const SizedBox(
                        width: 16, 
                        height: 16, 
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_source == AudioSource.videoExtract 
                    ? '提取音频' 
                    : '裁切音频'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
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
          ],
        ),
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
        if (!Uri.tryParse(value)!.isAbsolute) {
          return '请输入有效的 URL';
        }
        return null;
      },
    );
  }
  
  Widget _buildMediaFileSelector() {
    final isVideo = _source == AudioSource.videoExtract;
    final exts = isVideo 
        ? ['mp4', 'mov', 'avi', 'mkv', 'webm']
        : ['mp3', 'wav', 'ogg', 'aac', 'm4a'];
    
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
            ],
          ),
        ],
      ],
    );
  }
  
  Widget _buildTrimControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.content_cut, size: 20),
            const SizedBox(width: 8),
            const Text(
              '裁切设置',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _playPreview,
              icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
              label: Text(_isPlaying ? '停止' : '预览'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // 开始时间
        Row(
          children: [
            const SizedBox(width: 80, child: Text('开始:')),
            Expanded(
              child: Slider(
                value: _trimStart,
                min: 0,
                max: _totalDuration,
                onChanged: (value) {
                  setState(() {
                    _trimStart = value;
                    if (_trimEnd <= _trimStart) {
                      _trimEnd = _trimStart + 1;
                    }
                  });
                },
              ),
            ),
            SizedBox(
              width: 60,
              child: Text(_formatDuration(_trimStart)),
            ),
          ],
        ),
        
        // 结束时间
        Row(
          children: [
            const SizedBox(width: 80, child: Text('结束:')),
            Expanded(
              child: Slider(
                value: _trimEnd,
                min: 0,
                max: _totalDuration,
                onChanged: (value) {
                  setState(() {
                    _trimEnd = value;
                    if (_trimEnd <= _trimStart) {
                      _trimStart = _trimEnd - 1;
                    }
                  });
                },
              ),
            ),
            SizedBox(
              width: 60,
              child: Text(_formatDuration(_trimEnd)),
            ),
          ],
        ),
        
        // 时长信息
        Center(
          child: Text(
            '裁切后时长: ${_formatDuration(_trimEnd - _trimStart)}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
        ),
      ],
    );
  }
  
  String _formatDuration(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
