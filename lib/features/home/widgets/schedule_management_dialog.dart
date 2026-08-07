import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/schedule_model.dart';
import '../../../core/services/mqtt_service.dart';

class ScheduleManagementDialog extends StatefulWidget {
  const ScheduleManagementDialog({super.key});

  @override
  State<ScheduleManagementDialog> createState() => _ScheduleManagementDialogState();
}

class _ScheduleManagementDialogState extends State<ScheduleManagementDialog> {
  // Lịch mẫu ban đầu
  List<ScheduleModel> _schedules = [
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

  @override
  Widget build(BuildContext context) {
    final mqttService = Provider.of<MqttService>(context, listen: false);

    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
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
              'Cài đặt giờ tự động và câu phát âm cho Xiaozhi ESP32 qua MQTT',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const Divider(color: Colors.white24, height: 24),

            // Schedule List
            Expanded(
              child: _schedules.isEmpty
                  ? const Center(
                      child: Text(
                        'Chưa có mốc lịch nào được cài đặt',
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
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: item.action == 'ON'
                                          ? Colors.green.withOpacity(0.2)
                                          : item.action == 'OFF'
                                              ? Colors.red.withOpacity(0.2)
                                              : Colors.grey.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.action == 'ON'
                                          ? 'Bật TB'
                                          : item.action == 'OFF'
                                              ? 'Tắt TB'
                                              : 'Chỉ đọc',
                                      style: TextStyle(
                                        color: item.action == 'ON'
                                            ? Colors.greenAccent
                                            : item.action == 'OFF'
                                                ? Colors.redAccent
                                                : Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Switch(
                                    value: item.enabled,
                                    activeColor: Colors.cyanAccent,
                                    onChanged: (val) {
                                      setState(() {
                                        _schedules[index] = item.copyWith(enabled: val);
                                      });
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _schedules.removeAt(index);
                                      });
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
                    onPressed: () {
                      final jsonList = _schedules.map((e) => e.toJson()).toList();
                      mqttService.publishScheduleSet(jsonList);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Đã phát tin nhắn MQTT cài đặt Lịch tự động!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.send, color: Colors.black),
                    label: const Text('Lưu & Gửi MQTT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
    String selectedAction = 'NONE';

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
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedAction,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Hành động thiết bị',
                        labelStyle: TextStyle(color: Colors.cyanAccent),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'NONE', child: Text('Chỉ phát giọng nói')),
                        DropdownMenuItem(value: 'ON', child: Text('Bật tất cả thiết bị + Nói')),
                        DropdownMenuItem(value: 'OFF', child: Text('Tắt tất cả thiết bị + Nói')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedAction = val);
                        }
                      },
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
                          action: selectedAction,
                        ),
                      );
                    });
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
}
