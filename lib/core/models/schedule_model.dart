class ScheduleModel {
  final String id;
  final int hour;
  final int minute;
  final String prompt;
  final bool enabled;
  final String action; // 'NONE', 'ON', 'OFF'

  ScheduleModel({
    required this.id,
    required this.hour,
    required this.minute,
    required this.prompt,
    this.enabled = true,
    this.action = 'NONE',
  });

  String get timeFormatted {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  ScheduleModel copyWith({
    String? id,
    int? hour,
    int? minute,
    String? prompt,
    bool? enabled,
    String? action,
  }) {
    return ScheduleModel(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      prompt: prompt ?? this.prompt,
      enabled: enabled ?? this.enabled,
      action: action ?? this.action,
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
    };
  }

  factory ScheduleModel.fromJson(Map<String, dynamic> json) {
    return ScheduleModel(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      hour: (json['hour'] as num?)?.toInt() ?? 0,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      prompt: json['prompt']?.toString() ?? '',
      enabled: json['enabled'] ?? true,
      action: json['action']?.toString() ?? 'NONE',
    );
  }
}
