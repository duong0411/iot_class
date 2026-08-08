import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/schedule_model.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/services/mqtt_service.dart';

class ScheduleManagementDialog extends StatefulWidget {
  const ScheduleManagementDialog({super.key});

  @override
  State<ScheduleManagementDialog> createState() => _ScheduleManagementDialogState();
}

class _ScheduleManagementDialogState extends State<ScheduleManagementDialog> {
  static const String _storageKey = 'classroom_schedules_list';

  List<ScheduleModel> _schedules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_storageKey);
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final List<dynamic> list = jsonDecode(rawJson);
        setState(() {
          _schedules = list.map((e) => ScheduleModel.fromJson(e)).toList();
          _isLoading = false;
        });
        return;
      } catch (_) {}
    }

    // Default sample schedules
    setState(() {
      _schedules = [
        ScheduleModel(
          id: 'sched_morning',
          hour: 7,
          minute: 45,
          prompt: 'Đã đến giờ truy bài, các bạn học sinh chuẩn bị vào lớp!',
          enabled: true,
          action: 'NONE',
        ),
        ScheduleModel(
          id: 'sched_evening',
          hour: 17,
          minute: 0,
          prompt: 'Đã đến giờ tan học, các bạn học sinh có thể ra về!',
          enabled: true,
          action: 'NONE',
        ),
      ];
      _isLoading = false;
    });
    _saveSchedules();
  }

  Future<void> _saveSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _schedules.map((e) => e.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }

  MqttService? _getMqttService(BuildContext context) {
    try {
      return Provider.of<MqttService>(context, listen: false);
    } catch (_) {
      try {
        final devProvider = Provider.of<DeviceProvider>(context, listen: false);
        return devProvider.mqttService;
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _saveAndPublish(BuildContext context) async {
    await _saveSchedules();
    final mqttService = _getMqttService(context);
    if (mqttService != null) {
      final jsonList = _schedules.map((e) => e.toJson()).toList();
      if (kDebugMode) print('Publishing ${jsonList.length} schedules to MQTT...');
      mqttService.publishScheduleSet(jsonList);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.alarm_on, color: Colors.cyanAccent, size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Lịch Auto & Lời Dẫn Xiaozhi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Cài đặt mốc giờ tự động và chỉnh sửa lời dẫn qua Loa Xiaozhi',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const Divider(color: Colors.white24, height: 24),

            // Schedule List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
                  : _schedules.isEmpty
                      ? const Center(
                          child: Text(
                            'Chưa có mốc lịch nào. Nhấn "+ Thêm Lịch" bên dưới!',
                            style: TextStyle(color: Colors.white38),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _schedules.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = _schedules[index];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: item.enabled
                                      ? Colors.cyan.withOpacity(0.5)
                                      : Colors.white12,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        item.timeFormatted,
                                        style: TextStyle(
                                          color: item.enabled ? Colors.cyanAccent : Colors.white54,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Spacer(),
                                      // Switch ON/OFF
                                      Switch(
                                        value: item.enabled,
                                        activeColor: Colors.cyanAccent,
                                        onChanged: (val) {
                                          setState(() {
                                            _schedules[index] = item.copyWith(enabled: val);
                                          });
                                          _saveAndPublish(context);
                                        },
                                      ),
                                      // Edit Button
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
                                        tooltip: 'Chỉnh sửa lịch',
                                        onPressed: () => _showEditDialog(context, index),
                                      ),
                                      // Delete Button
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                        tooltip: 'Xóa mốc lịch',
                                        onPressed: () {
                                          setState(() {
                                            _schedules.removeAt(index);
                                          });
                                          _saveAndPublish(context);
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.record_voice_over, color: Colors.amberAccent, size: 16),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          item.prompt.isEmpty ? '(Không có lời dẫn)' : '"${item.prompt}"',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            const SizedBox(height: 16),

            // Footer Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddDialog(context),
                    icon: const Icon(Icons.add, color: Colors.cyanAccent),
                    label: const Text('Thêm Lịch', style: TextStyle(color: Colors.cyanAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.cyanAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // Ensure MQTT is connected before publishing
                      final mqttSvc = _getMqttService(context);
                      if (mqttSvc != null && !mqttSvc.isConnected) {
                        if (kDebugMode) print('[Schedule] MQTT not connected, reconnecting...');
                        await mqttSvc.connect();
                      }
                      await _saveAndPublish(context);
                      // Small delay to ensure MQTT message is sent
                      await Future.delayed(const Duration(milliseconds: 300));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Đã lưu và gửi toàn bộ Lịch tự động qua MQTT!'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 2),
                        ),
                      );
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.send, color: Colors.black),
                    label: const Text('Lưu & Đồng Bộ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    TimeOfDay selectedTime = TimeOfDay.now();
    final promptController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('Thêm Mốc Lịch Tự Động', style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: const Text('Giờ phát thông báo', style: TextStyle(color: Colors.white70)),
                      trailing: Text(
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedTime = picked;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: promptController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Lời dẫn giọng nói Xiaozhi',
                        labelStyle: TextStyle(color: Colors.cyanAccent),
                        hintText: 'Nhập câu thoại để Xiaozhi phát âm...',
                        hintStyle: TextStyle(color: Colors.white38),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _schedules.add(
                        ScheduleModel(
                          id: 'sched_${DateTime.now().millisecondsSinceEpoch}',
                          hour: selectedTime.hour,
                          minute: selectedTime.minute,
                          prompt: promptController.text.trim(),
                          enabled: true,
                          action: 'NONE',
                        ),
                      );
                    });
                    _saveAndPublish(context);
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
                  child: const Text('Thêm', style: TextStyle(color: Colors.black)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditDialog(BuildContext context, int index) {
    final item = _schedules[index];
    TimeOfDay selectedTime = TimeOfDay(hour: item.hour, minute: item.minute);
    final promptController = TextEditingController(text: item.prompt);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('Sửa Mốc Lịch Tự Động', style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: const Text('Giờ phát thông báo', style: TextStyle(color: Colors.white70)),
                      trailing: Text(
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.cyanAccent, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setDialogState(() {
                            selectedTime = picked;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: promptController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Lời dẫn giọng nói Xiaozhi',
                        labelStyle: TextStyle(color: Colors.cyanAccent),
                        hintText: 'Nhập câu thoại để Xiaozhi phát âm...',
                        hintStyle: TextStyle(color: Colors.white38),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _schedules[index] = item.copyWith(
                        hour: selectedTime.hour,
                        minute: selectedTime.minute,
                        prompt: promptController.text.trim(),
                        action: 'NONE',
                      );
                    });
                    _saveAndPublish(context);
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
                  child: const Text('Lưu Sửa', style: TextStyle(color: Colors.black)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
