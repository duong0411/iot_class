import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/providers/student_provider.dart';
import '../widgets/schedule_management_dialog.dart';

class ClassroomScreen extends StatelessWidget {
  const ClassroomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final device = Provider.of<DeviceProvider>(context);
    final students = Provider.of<StudentProvider>(context);
    final alarm = device.classroomGas || device.classroomFire;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text('Lớp học thông minh', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Lịch và lời dẫn',
            onPressed: () => showDialog(context: context, builder: (_) => const ScheduleManagementDialog()),
            icon: const Icon(Icons.alarm_on, color: Colors.cyanAccent),
          ),
          _onlineChip(device.isMqttConnected && device.isClassroomDeviceOnline),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          device.requestClassroomStatus();
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!device.isClassroomDeviceOnline) _banner(
              color: Colors.redAccent,
              icon: Icons.wifi_off,
              title: 'ESP32 đang ngoại tuyến',
              body: 'Kiểm tra nguồn và WiFi. Portal cấu hình: SmartClassroom_C2 → 192.168.4.1',
            ),
            if (alarm) _banner(
              color: device.classroomFire ? Colors.deepOrange : Colors.amber,
              icon: device.classroomFire ? Icons.local_fire_department : Icons.cloud,
              title: device.classroomFire && device.classroomGas
                  ? 'Cháy và CO2'
                  : device.classroomFire
                      ? 'Báo cháy'
                      : 'Báo CO2 / khí gas',
              body: 'Còi trên mạch đang kêu. Thông báo này vẫn hiện khi bạn thoát app, miễn là điện thoại có mạng.',
            ),
            _summary(students),
            const SizedBox(height: 16),
            const _SectionTitle('Môi trường'),
            Row(
              children: [
                _sensor('Nhiệt độ', '${device.classroomTemp.toStringAsFixed(1)}°C', Icons.thermostat, Colors.orangeAccent, 'DHT11'),
                const SizedBox(width: 10),
                _sensor('Độ ẩm', '${device.classroomHumi.toStringAsFixed(0)}%', Icons.water_drop, Colors.lightBlueAccent, 'DHT11'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _sensor(
                  'Ánh sáng',
                  '${device.classroomLightPercent}%',
                  device.classroomLightDark ? Icons.nightlight : Icons.wb_sunny,
                  Colors.amber,
                  device.classroomLightStatus,
                ),
                const SizedBox(width: 10),
                _sensor(
                  'Thân nhiệt',
                  device.classroomBody == null ? '--' : '${device.classroomBody!.toStringAsFixed(1)}°C',
                  Icons.personal_injury,
                  Colors.pinkAccent,
                  'MLX90614',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _sensor('CO2 / Gas', device.classroomGas ? 'BÁO' : 'Ổn', Icons.cloud, device.classroomGas ? Colors.redAccent : Colors.greenAccent, 'Digital DO'),
                const SizedBox(width: 10),
                _sensor('Cháy', device.classroomFire ? 'BÁO' : 'Ổn', Icons.local_fire_department, device.classroomFire ? Colors.deepOrange : Colors.greenAccent, 'Digital DO'),
              ],
            ),
            const SizedBox(height: 18),
            _actuatorCard(
              icon: Icons.lightbulb,
              color: Colors.amberAccent,
              title: 'Đèn chiếu sáng lớp học',
              auto: device.isLedAuto,
              isOn: device.classroomLedState,
              rule: 'Tự động: bật khi ánh sáng < 40%, tắt khi ≥ 45%',
              reason: device.classroomLedReason,
              onMode: (auto) => device.setClassroomLedMode(auto),
              onPower: device.toggleClassroomLed,
            ),
            const SizedBox(height: 12),
            _actuatorCard(
              icon: Icons.air,
              color: Colors.cyanAccent,
              title: 'Quạt thông gió và làm mát',
              auto: device.isFanAuto,
              isOn: device.classroomFanState,
              rule: 'Tự động: bật khi nhiệt độ > 30°C hoặc có khói/gas, tắt khi ≤ 29.5°C',
              reason: device.classroomFanReason,
              onMode: (auto) => device.setClassroomFanMode(auto),
              onPower: device.toggleClassroomFan,
            ),
            const SizedBox(height: 12),
            _doorCard(device),
            const SizedBox(height: 12),
            _scheduleTile(context),
          ],
        ),
      ),
    );
  }

  Widget _onlineChip(bool online) {
    final color = online ? Colors.greenAccent : Colors.redAccent;
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(online ? 'ONLINE' : 'OFFLINE', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}

Widget _banner({required Color color, required IconData icon, required String title, required String body}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _summary(StudentProvider students) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF1E3A8A), Color(0xFF0284C7)]),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Điểm danh RFID', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text(
                '${students.presentCount} / ${students.totalCount} học sinh',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const Icon(Icons.badge, color: Colors.cyanAccent, size: 40),
      ],
    ),
  );
}

Widget _sensor(String title, String value, IconData icon, Color color, String note) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text(note, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    ),
  );
}

Widget _actuatorCard({
  required IconData icon,
  required Color color,
  required String title,
  required bool auto,
  required bool isOn,
  required String rule,
  required String reason,
  required ValueChanged<bool> onMode,
  required VoidCallback onPower,
}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: isOn ? color : Colors.white12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            Text(isOn ? 'BẬT' : 'TẮT', style: TextStyle(color: isOn ? color : Colors.white38, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        Text(rule, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 6),
        Text(reason, style: TextStyle(color: color, fontSize: 13)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _modeButton('Tự động', auto, color, () => onMode(true))),
            const SizedBox(width: 8),
            Expanded(child: _modeButton('Thủ công', !auto, Colors.orangeAccent, () => onMode(false))),
            const SizedBox(width: 8),
            Switch(value: isOn, activeThumbColor: color, onChanged: (_) => onPower()),
          ],
        ),
      ],
    ),
  );
}

Widget _modeButton(String label, bool selected, Color color, VoidCallback onTap) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? color : Colors.white12),
      ),
      child: Text(label, style: TextStyle(color: selected ? color : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
    ),
  );
}

Widget _doorCard(DeviceProvider device) {
  final open = device.classroomDoorState;
  final body = device.classroomBody;
  final bodyText = body == null ? 'chưa đọc' : '${body.toStringAsFixed(1)}°C';
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: open ? Colors.greenAccent : Colors.white12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.door_front_door, color: Colors.greenAccent),
            const SizedBox(width: 8),
            const Expanded(child: Text('Cửa tự động lớp học', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            Text(open ? 'MỞ ${device.classroomDoorAngle.toStringAsFixed(0)}°' : 'ĐÓNG', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Servo SG90. Tự động mở khi học sinh quẹt thẻ hợp lệ và thân nhiệt 33°C – 40°C, rồi đóng sau 5 giây.',
          style: TextStyle(color: Colors.white60, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text('Thân nhiệt gần nhất: $bodyText', style: const TextStyle(color: Colors.white, fontSize: 13)),
        if (device.classroomLastUid.isNotEmpty)
          Text('Thẻ ${device.classroomLastUid} · ${device.classroomRfidResult.isEmpty ? 'đã quẹt' : device.classroomRfidResult}',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: device.toggleClassroomDoor,
            child: Text(open ? 'Đóng cửa' : 'Mở cửa'),
          ),
        ),
      ],
    ),
  );
}

Widget _scheduleTile(BuildContext context) {
  return ListTile(
    tileColor: const Color(0xFF134E4A),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    leading: const Icon(Icons.record_voice_over, color: Colors.cyanAccent),
    title: const Text('Lịch và lời dẫn Xiaozhi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    subtitle: const Text('Giọng nói theo giờ học', style: TextStyle(color: Colors.white70)),
    trailing: const Icon(Icons.chevron_right, color: Colors.white70),
    onTap: () => showDialog(context: context, builder: (_) => const ScheduleManagementDialog()),
  );
}
