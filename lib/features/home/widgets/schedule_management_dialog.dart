import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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
  static const String _apiBase = 'https://duynguyen.io.vn';

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

    setState(() {
      _schedules = [
        ScheduleModel(
          id: 'sched_morning',
          hour: 7,
          minute: 45,
          prompt: 'Đã đến giờ truy bài, các bạn học sinh chuẩn bị vào lớp!',
          enabled: true,
        ),
        ScheduleModel(
          id: 'sched_evening',
          hour: 17,
          minute: 0,
          prompt: 'Đã đến giờ tan học, các bạn học sinh có thể ra về!',
          enabled: true,
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
    final jsonList = _schedules.map((e) => e.toJson()).toList();

    try {
      final response = await http
          .post(
            Uri.parse('$_apiBase/api/schedule'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'schedules': jsonList}),
          )
          .timeout(const Duration(seconds: 90));
      if (kDebugMode) print('HTTP Schedule Sync Status: ${response.statusCode}');
      if (response.statusCode == 200) {
        try {
          final body = jsonDecode(response.body);
          final list = body['schedules'];
          if (list is List) {
            setState(() {
              _schedules = list.map((e) => ScheduleModel.fromJson(e)).toList();
            });
            await _saveSchedules();
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) print('HTTP Schedule Sync Error: $e');
    }

    final mqttService = _getMqttService(context);
    if (mqttService != null) {
      mqttService.publishScheduleSet(jsonList);
    }
  }

  IconData _sourceIcon(String source) {
    switch (source) {
      case 'mp3':
        return Icons.audio_file;
      case 'youtube':
        return Icons.ondemand_video;
      default:
        return Icons.record_voice_over;
    }
  }

  Color _sourceColor(String source) {
    switch (source) {
      case 'mp3':
        return Colors.lightGreenAccent;
      case 'youtube':
        return Colors.redAccent;
      default:
        return Colors.amberAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.alarm_on, color: Colors.cyanAccent, size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Lịch Auto & Lời Dẫn Xiaozhi',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
              'TTS giọng nói · tải MP3 · hoặc dán link YouTube để Xiaozhi phát đúng giờ',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const Divider(color: Colors.white24, height: 24),
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
                                  color: item.enabled ? Colors.cyan.withOpacity(0.5) : Colors.white12,
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
                                      const SizedBox(width: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _sourceColor(item.audioSource).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: _sourceColor(item.audioSource).withOpacity(0.5)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(_sourceIcon(item.audioSource), size: 14, color: _sourceColor(item.audioSource)),
                                            const SizedBox(width: 4),
                                            Text(
                                              item.sourceLabel,
                                              style: TextStyle(color: _sourceColor(item.audioSource), fontSize: 11, fontWeight: FontWeight.w600),
                                            ),
                                          ],
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
                                          _saveAndPublish(context);
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
                                        onPressed: () => _showEditor(context, index: index),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                        onPressed: () {
                                          setState(() => _schedules.removeAt(index));
                                          _saveAndPublish(context);
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    item.audioSource == 'youtube'
                                        ? (item.youtubeUrl.isEmpty ? '(Chưa có link YouTube)' : item.youtubeUrl)
                                        : item.audioSource == 'mp3'
                                            ? (item.audioUrl.isEmpty ? '(Chưa có file MP3)' : item.audioUrl.split('/').last)
                                            : (item.prompt.isEmpty ? '(Không có lời dẫn)' : '"${item.prompt}"'),
                                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditor(context),
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
                      final mqttSvc = _getMqttService(context);
                      if (mqttSvc != null && !mqttSvc.isConnected) {
                        await mqttSvc.connect();
                      }
                      await _saveAndPublish(context);
                      await Future.delayed(const Duration(milliseconds: 300));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Đã lưu và đồng bộ lịch (TTS / MP3 / YouTube)!'),
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

  void _showEditor(BuildContext context, {int? index}) {
    final editing = index != null ? _schedules[index] : null;
    TimeOfDay selectedTime = editing != null
        ? TimeOfDay(hour: editing.hour, minute: editing.minute)
        : TimeOfDay.now();
    final promptController = TextEditingController(text: editing?.prompt ?? '');
    final youtubeController = TextEditingController(text: editing?.youtubeUrl ?? '');
    String audioSource = editing?.audioSource ?? 'tts';
    String audioUrl = editing?.audioUrl ?? '';
    String? pickedFileName;
    bool busy = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickMp3() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: const ['mp3'],
                withData: true,
              );
              if (result == null || result.files.isEmpty) return;
              final file = result.files.first;
              if (file.bytes == null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Không đọc được file MP3'), backgroundColor: Colors.redAccent),
                  );
                }
                return;
              }
              setDialogState(() => busy = true);
              try {
                final req = http.MultipartRequest(
                  'POST',
                  Uri.parse('$_apiBase/api/schedule/audio/upload'),
                );
                req.fields['hour'] = selectedTime.hour.toString();
                req.fields['minute'] = selectedTime.minute.toString();
                req.files.add(http.MultipartFile.fromBytes(
                  'file',
                  file.bytes!,
                  filename: file.name,
                  contentType: MediaType('audio', 'mpeg'),
                ));
                final streamed = await req.send().timeout(const Duration(seconds: 60));
                final body = await streamed.stream.bytesToString();
                final json = jsonDecode(body);
                if (streamed.statusCode == 200 && json['success'] == true) {
                  setDialogState(() {
                    audioUrl = (json['audioUrl'] ?? json['audio_url'] ?? '').toString();
                    pickedFileName = file.name;
                    audioSource = 'mp3';
                  });
                } else {
                  throw Exception(json['message'] ?? 'Upload thất bại');
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Upload MP3 lỗi: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              } finally {
                setDialogState(() => busy = false);
              }
            }

            Future<void> prepareYoutube() async {
              final url = youtubeController.text.trim();
              if (url.isEmpty) return;
              setDialogState(() => busy = true);
              try {
                final response = await http
                    .post(
                      Uri.parse('$_apiBase/api/schedule/audio/youtube'),
                      headers: {'Content-Type': 'application/json'},
                      body: jsonEncode({
                        'url': url,
                        'hour': selectedTime.hour,
                        'minute': selectedTime.minute,
                        'id': editing?.id ?? 'new',
                      }),
                    )
                    .timeout(const Duration(seconds: 180));
                final json = jsonDecode(response.body);
                if (response.statusCode == 200 && json['success'] == true) {
                  setDialogState(() {
                    audioUrl = (json['audioUrl'] ?? json['audio_url'] ?? '').toString();
                    audioSource = 'youtube';
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ Đã lấy audio từ YouTube'), backgroundColor: Colors.green),
                    );
                  }
                } else {
                  throw Exception(json['message'] ?? 'YouTube thất bại');
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('YouTube lỗi: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              } finally {
                setDialogState(() => busy = false);
              }
            }

            Widget sourceChip(String value, String label, IconData icon) {
              final selected = audioSource == value;
              return ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: selected ? Colors.black : Colors.white70),
                    const SizedBox(width: 4),
                    Text(label, style: TextStyle(color: selected ? Colors.black : Colors.white70, fontSize: 12)),
                  ],
                ),
                selected: selected,
                selectedColor: Colors.cyanAccent,
                backgroundColor: const Color(0xFF0F172A),
                onSelected: busy
                    ? null
                    : (_) => setDialogState(() {
                          audioSource = value;
                          if (value == 'tts') {
                            audioUrl = '';
                          }
                        }),
              );
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text(
                editing == null ? 'Thêm Mốc Lịch Tự Động' : 'Sửa Mốc Lịch Tự Động',
                style: const TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Giờ phát', style: TextStyle(color: Colors.white70)),
                        trailing: Text(
                          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        onTap: busy
                            ? null
                            : () async {
                                final picked = await showTimePicker(context: context, initialTime: selectedTime);
                                if (picked != null) setDialogState(() => selectedTime = picked);
                              },
                      ),
                      const SizedBox(height: 8),
                      const Text('Nguồn âm thanh', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          sourceChip('tts', 'TTS', Icons.record_voice_over),
                          sourceChip('mp3', 'MP3', Icons.audio_file),
                          sourceChip('youtube', 'YouTube', Icons.ondemand_video),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (audioSource == 'tts') ...[
                        TextField(
                          controller: promptController,
                          enabled: !busy,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 3,
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
                      if (audioSource == 'mp3') ...[
                        OutlinedButton.icon(
                          onPressed: busy ? null : pickMp3,
                          icon: const Icon(Icons.upload_file, color: Colors.lightGreenAccent),
                          label: Text(
                            pickedFileName ?? (audioUrl.isEmpty ? 'Chọn / tải file MP3 lên' : 'Đổi file MP3'),
                            style: const TextStyle(color: Colors.lightGreenAccent),
                          ),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.lightGreenAccent)),
                        ),
                        if (audioUrl.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(audioUrl, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: promptController,
                          enabled: !busy,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 1,
                          decoration: const InputDecoration(
                            labelText: 'Ghi chú (tuỳ chọn)',
                            labelStyle: TextStyle(color: Colors.white54),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                          ),
                        ),
                      ],
                      if (audioSource == 'youtube') ...[
                        TextField(
                          controller: youtubeController,
                          enabled: !busy,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Link YouTube',
                            labelStyle: TextStyle(color: Colors.redAccent),
                            hintText: 'https://www.youtube.com/watch?v=...',
                            hintStyle: TextStyle(color: Colors.white38),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.redAccent)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: busy ? null : prepareYoutube,
                          icon: busy
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.download, color: Colors.white),
                          label: Text(busy ? 'Đang lấy audio...' : 'Lấy audio từ YouTube', style: const TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                        ),
                        if (audioUrl.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('Đã sẵn sàng: ${audioUrl.split('/').last}', style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 12)),
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'File dài sẽ được loa stream (tải + phát dần), không cần cắt tay. Nên dùng MP3; YouTube backend chuyển sang MP3 trước.',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                      if (busy && audioSource != 'youtube')
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(ctx),
                  child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: busy
                      ? null
                      : () {
                          if (audioSource == 'tts' && promptController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Nhập lời dẫn TTS'), backgroundColor: Colors.orange),
                            );
                            return;
                          }
                          if (audioSource == 'mp3' && audioUrl.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Hãy tải file MP3 trước'), backgroundColor: Colors.orange),
                            );
                            return;
                          }
                          if (audioSource == 'youtube' && (youtubeController.text.trim().isEmpty || audioUrl.isEmpty)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Dán link YouTube và bấm Lấy audio'), backgroundColor: Colors.orange),
                            );
                            return;
                          }

                          final model = ScheduleModel(
                            id: editing?.id ?? 'sched_${DateTime.now().millisecondsSinceEpoch}',
                            hour: selectedTime.hour,
                            minute: selectedTime.minute,
                            prompt: promptController.text.trim(),
                            enabled: editing?.enabled ?? true,
                            audioSource: audioSource,
                            audioUrl: audioSource == 'tts' ? '' : audioUrl,
                            youtubeUrl: audioSource == 'youtube' ? youtubeController.text.trim() : '',
                          );

                          setState(() {
                            if (index != null) {
                              _schedules[index] = model;
                            } else {
                              _schedules.add(model);
                            }
                          });
                          _saveAndPublish(this.context);
                          Navigator.pop(ctx);
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
                  child: Text(editing == null ? 'Thêm' : 'Lưu Sửa', style: const TextStyle(color: Colors.black)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
