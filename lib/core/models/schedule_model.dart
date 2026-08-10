class ScheduleModel {
  final String id;
  final int hour;
  final int minute;
  final String prompt;
  final bool enabled;
  final String action; // 'NONE', 'ON', 'OFF'
  /// 'tts' | 'mp3' | 'youtube'
  final String audioSource;
  final String audioUrl;
  final String youtubeUrl;

  ScheduleModel({
    required this.id,
    required this.hour,
    required this.minute,
    required this.prompt,
    this.enabled = true,
    this.action = 'NONE',
    this.audioSource = 'tts',
    this.audioUrl = '',
    this.youtubeUrl = '',
  });

  String get timeFormatted {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get sourceLabel {
    switch (audioSource) {
      case 'mp3':
        return 'File MP3';
      case 'youtube':
        return 'YouTube';
      default:
        return 'Giọng nói (TTS)';
    }
  }

  ScheduleModel copyWith({
    String? id,
    int? hour,
    int? minute,
    String? prompt,
    bool? enabled,
    String? action,
    String? audioSource,
    String? audioUrl,
    String? youtubeUrl,
  }) {
    return ScheduleModel(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      prompt: prompt ?? this.prompt,
      enabled: enabled ?? this.enabled,
      action: action ?? this.action,
      audioSource: audioSource ?? this.audioSource,
      audioUrl: audioUrl ?? this.audioUrl,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hour': hour,
      'minute': minute,
      'prompt': prompt,
      'enabled': enabled,
      'action': action,
      'audioSource': audioSource,
      'audioUrl': audioUrl,
      'audio_url': audioUrl,
      'youtubeUrl': youtubeUrl,
    };
  }

  factory ScheduleModel.fromJson(Map<String, dynamic> json) {
    final source = (json['audioSource'] ?? json['audio_source'] ?? 'tts').toString();
    final url = (json['audioUrl'] ?? json['audio_url'] ?? '').toString();
    return ScheduleModel(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      hour: (json['hour'] as num?)?.toInt() ?? 0,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      prompt: json['prompt']?.toString() ?? '',
      enabled: json['enabled'] ?? true,
      action: json['action']?.toString() ?? 'NONE',
      audioSource: source,
      audioUrl: url,
      youtubeUrl: (json['youtubeUrl'] ?? json['youtube_url'] ?? '').toString(),
    );
  }
}
