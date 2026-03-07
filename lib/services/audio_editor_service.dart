import 'dart:io';
import 'package:ffmpeg_kit_flutter_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_audio/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

class AudioEditorService {
  static final Dio _dio = Dio();

  /// 从视频中提取音频
  /// [videoPath] 视频文件路径或URL
  /// [startTime] 开始时间（秒）
  /// [duration] 持续时间（秒）
  /// 返回提取后的音频文件路径
  static Future<String?> extractAudioFromVideo({
    required String videoPath,
    double startTime = 0,
    double? duration,
  }) async {
    try {
      String inputPath = videoPath;
      final isRemote = videoPath.startsWith('http://') || videoPath.startsWith('https://');
      
      // 如果是远程视频，先下载到本地
      if (isRemote) {
        final tempDir = await getTemporaryDirectory();
        final videoExt = videoPath.split('.').last;
        inputPath = '${tempDir.path}/temp_video_${DateTime.now().millisecondsSinceEpoch}.$videoExt';
        
        await _dio.download(videoPath, inputPath);
      }

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${directory.path}/extracted_$timestamp.mp3';

      // 构建 FFmpeg 命令
      String command = '-i "$inputPath"';
      
      if (startTime > 0) {
        command += ' -ss $startTime';
      }
      
      if (duration != null) {
        command += ' -t $duration';
      }
      
      // 提取音频：-vn 忽略视频，-acodec libmp3lame 转为 MP3
      command += ' -vn -acodec libmp3lame -q:a 2 "$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      // 清理临时视频文件
      if (isRemote && File(inputPath).existsSync()) {
        await File(inputPath).delete();
      }

      if (ReturnCode.isSuccess(returnCode)) {
        return outputPath;
      } else {
        final logs = await session.getAllLogs();
        print('FFmpeg error: ${logs?.join(', ')}');
        return null;
      }
    } catch (e) {
      print('Error extracting audio: $e');
      return null;
    }
  }

  /// 裁切音频
  /// [audioPath] 音频文件路径或URL
  /// [startTime] 开始时间（秒）
  /// [duration] 持续时间（秒）
  /// 返回裁切后的音频文件路径
  static Future<String?> trimAudio({
    required String audioPath,
    required double startTime,
    required double duration,
  }) async {
    try {
      String inputPath = audioPath;
      final isRemote = audioPath.startsWith('http://') || audioPath.startsWith('https://');
      
      // 如果是远程音频，先下载到本地
      if (isRemote) {
        final tempDir = await getTemporaryDirectory();
        final audioExt = audioPath.split('.').last;
        inputPath = '${tempDir.path}/temp_audio_${DateTime.now().millisecondsSinceEpoch}.$audioExt';
        
        await _dio.download(audioPath, inputPath);
      }

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${directory.path}/trimmed_$timestamp.mp3';

      // 构建 FFmpeg 命令
      final command = '-i "$inputPath" -ss $startTime -t $duration -acodec libmp3lame -q:a 2 "$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      // 清理临时音频文件
      if (isRemote && File(inputPath).existsSync()) {
        await File(inputPath).delete();
      }

      if (ReturnCode.isSuccess(returnCode)) {
        return outputPath;
      } else {
        final logs = await session.getAllLogs();
        print('FFmpeg error: ${logs?.join(', ')}');
        return null;
      }
    } catch (e) {
      print('Error trimming audio: $e');
      return null;
    }
  }

  /// 获取媒体文件时长（秒）
  static Future<double?> getMediaDuration(String mediaPath) async {
    try {
      final isRemote = mediaPath.startsWith('http://') || mediaPath.startsWith('https://');
      
      if (isRemote) {
        // 远程文件需要先下载再获取时长，或者通过 FFprobe
        final tempDir = await getTemporaryDirectory();
        final ext = mediaPath.split('.').last;
        final tempPath = '${tempDir.path}/temp_check_${DateTime.now().millisecondsSinceEpoch}.$ext';
        
        await _dio.download(mediaPath, tempPath);
        
        final duration = await _getDurationFromFile(tempPath);
        await File(tempPath).delete();
        return duration;
      } else {
        return await _getDurationFromFile(mediaPath);
      }
    } catch (e) {
      print('Error getting duration: $e');
      return null;
    }
  }

  static Future<double?> _getDurationFromFile(String filePath) async {
    try {
      final session = await FFmpegKit.execute(
        '-i "$filePath" 2>&1 | grep "Duration" | cut -d " " -f 4 | sed s/,//'
      );
      // 简化处理：使用另一种方式获取时长
      final probeSession = await FFmpegKit.execute(
        '-i "$filePath" -f null -'
      );
      
      // 通过日志获取时长信息
      final logs = await probeSession.getAllLogsAsString();
      if (logs != null) {
        final durationMatch = RegExp(r'Duration: (\d+):(\d+):(\d+)\.(\d+)').firstMatch(logs);
        if (durationMatch != null) {
          final hours = int.parse(durationMatch.group(1)!);
          final minutes = int.parse(durationMatch.group(2)!);
          final seconds = int.parse(durationMatch.group(3)!);
          final milliseconds = int.parse(durationMatch.group(4)!);
          return hours * 3600 + minutes * 60 + seconds + milliseconds / 100.0;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
