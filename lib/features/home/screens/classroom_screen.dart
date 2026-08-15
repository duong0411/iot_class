import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/providers/student_provider.dart';
import '../widgets/schedule_management_dialog.dart';

class ClassroomScreen extends StatelessWidget {
  const ClassroomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deviceProvider = Provider.of<DeviceProvider>(context);
    final studentProvider = Provider.of<StudentProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        centerTitle: true,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Text(
              'Lớp Học Thông Minh',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.alarm_on, color: Colors.cyanAccent),
            tooltip: 'Lịch Auto & Lời Dẫn Xiaozhi',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const ScheduleManagementDialog(),
              );
            },
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (deviceProvider.isMqttConnected && deviceProvider.isClassroomDeviceOnline)
                  ? Colors.green.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (deviceProvider.isMqttConnected && deviceProvider.isClassroomDeviceOnline) ? Colors.green : Colors.red,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: (deviceProvider.isMqttConnected && deviceProvider.isClassroomDeviceOnline) ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 6),
                Text(
                  (deviceProvider.isMqttConnected && deviceProvider.isClassroomDeviceOnline) ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    color: (deviceProvider.isMqttConnected && deviceProvider.isClassroomDeviceOnline) ? Colors.green : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          deviceProvider.requestClassroomStatus();
          await Future.delayed(const Duration(milliseconds: 600));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cảnh báo khi thiết bị ESP32 Ngoại Tuyến (Rút điện / Mất WiFi / Không nhận dữ liệu)
              if (!deviceProvider.isClassroomDeviceOnline)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.redAccent, size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🔴 Thiết Bị ESP32 Ngoại Tuyến (OFFLINE)',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Mạch ESP32 không gửi dữ liệu (Có thể bị rút điện hoặc mất WiFi). Vui lòng kiểm tra lại thiết bị!',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              // Thẻ tổng quan điểm danh nhanh
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFF0284C7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyan.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sỉ Số Điểm Danh RFID',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${studentProvider.presentCount} / ${studentProvider.totalCount} Học Sinh',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Icon(Icons.badge, color: Colors.cyanAccent, size: 42),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              const Text(
                'Môi Trường Lớp Học (ESP32)',
                style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Grid Cảm biến (Nhiệt độ, Độ ẩm, Ánh sáng)
              Row(
                children: [
                  Expanded(
                    child: _buildSensorCard(
                      title: 'Nhiệt Độ',
                      value: '${deviceProvider.classroomTemp.toStringAsFixed(1)}°C',
                      icon: Icons.thermostat,
                      color: Colors.orangeAccent,
                      statusText: 'Cảm biến DHT11',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSensorCard(
                      title: 'Độ Ẩm',
                      value: '${deviceProvider.classroomHumi.toStringAsFixed(1)}%',
                      icon: Icons.water_drop,
                      color: Colors.blueAccent,
                      statusText: 'Độ ẩm không khí',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSensorCard(
                      title: 'Ánh Sáng',
                      value: deviceProvider.classroomLightStatus,
                      icon: Icons.wb_sunny,
                      color: Colors.amber,
                      statusText: 'Cảm biến Quang',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // THẺ CÀI ĐẶT LỊCH AUTOMATION & LỜI DẪN XIAOZHI
              InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => const ScheduleManagementDialog(),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.teal.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.alarm_on, color: Colors.cyanAccent, size: 32),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cài Đặt Lịch Auto & Lời Dẫn Xiaozhi',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Đặt giờ tự động và tùy chỉnh lời nói của Xiaozhi ESP32 từ xa qua MQTT',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.white70),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // THẺ CHỌN CHẾ ĐỘ VẬN HÀNH (AUTO / MANUAL)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: deviceProvider.isClassroomAutoMode ? Colors.cyanAccent.withOpacity(0.5) : Colors.orangeAccent.withOpacity(0.5),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              deviceProvider.isClassroomAutoMode ? Icons.smart_toy_rounded : Icons.touch_app_rounded,
                              color: deviceProvider.isClassroomAutoMode ? Colors.cyanAccent : Colors.orangeAccent,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Chế Độ: ${deviceProvider.classroomMode}',
                              style: TextStyle(
                                color: deviceProvider.isClassroomAutoMode ? Colors.cyanAccent : Colors.orangeAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: !deviceProvider.isClassroomAutoMode, // true = MANUAL, false = AUTO
                          activeColor: Colors.orangeAccent,
                          inactiveThumbColor: Colors.cyanAccent,
                          inactiveTrackColor: Colors.cyan.withOpacity(0.3),
                          onChanged: (_) => deviceProvider.toggleClassroomMode(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (!deviceProvider.isClassroomAutoMode) deviceProvider.toggleClassroomMode();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                              decoration: BoxDecoration(
                                color: deviceProvider.isClassroomAutoMode ? Colors.cyan.withOpacity(0.2) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: deviceProvider.isClassroomAutoMode ? Colors.cyanAccent : Colors.white10),
                              ),
                              child: const Center(
                                child: Text('🤖 TỰ ĐỘNG (AUTO)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              if (deviceProvider.isClassroomAutoMode) deviceProvider.toggleClassroomMode();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                              decoration: BoxDecoration(
                                color: !deviceProvider.isClassroomAutoMode ? Colors.orange.withOpacity(0.2) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: !deviceProvider.isClassroomAutoMode ? Colors.orangeAccent : Colors.white10),
                              ),
                              child: const Center(
                                child: Text('🎮 THỦ CÔNG (MANUAL)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      deviceProvider.isClassroomAutoMode
                          ? '🤖 Đang ở chế độ TỰ ĐỘNG: Quạt & Đèn tự chạy theo cảm biến Nhiệt độ (>= 27°C) & Ánh sáng.'
                          : '🔓 Đang ở chế độ THỦ CÔNG: Cho phép BẬT/TẮT toàn bộ thiết bị tự do trên App (Dùng khi ra về).',
                      style: TextStyle(
                        color: deviceProvider.isClassroomAutoMode ? Colors.cyanAccent.withOpacity(0.8) : Colors.orangeAccent.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                'Điều Khiển Thiết Bị Lớp Học',
                style: TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Switche Quạt, Đèn & Cửa
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                childAspectRatio: 1.3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  // Quạt Lớp Học
                  _buildDeviceCard(
                    title: 'Quạt Lớp Học',
                    subtitle: deviceProvider.classroomFanState ? 'Trạng thái: BẬT (GPIO4)' : 'Trạng thái: TẮT (GPIO4)',
                    icon: Icons.air,
                    isOn: deviceProvider.classroomFanState,
                    activeColor: Colors.cyanAccent,
                    onToggle: () => deviceProvider.toggleClassroomFan(),
                  ),
                  // Đèn Lớp Học
                  _buildDeviceCard(
                    title: 'Đèn Lớp Học',
                    subtitle: deviceProvider.classroomLedState ? 'Trạng thái: BẬT (GPIO14)' : 'Trạng thái: TẮT (GPIO14)',
                    icon: Icons.lightbulb,
                    isOn: deviceProvider.classroomLedState,
                    activeColor: Colors.amberAccent,
                    onToggle: () => deviceProvider.toggleClassroomLed(),
                  ),
                  // Cửa Sổ / Cửa Lớp Học (Servo GPIO13)
                  _buildDeviceCard(
                    title: 'Cửa Sổ / Cửa Lớp',
                    subtitle: deviceProvider.classroomDoorState ? 'Trạng thái: BẬT (Mở 90°)' : 'Trạng thái: TẮT (Đóng 0°)',
                    icon: Icons.window,
                    isOn: deviceProvider.classroomDoorState,
                    activeColor: Colors.greenAccent,
                    onToggle: () => deviceProvider.toggleClassroomDoor(),
                  ),
                  // RFID Card Reader Status
                  _buildInfoCard(
                    title: 'Đầu Đọc RFID',
                    subtitle: 'Module RC522 (SPI)',
                    icon: Icons.nfc,
                    statusText: 'Đang chờ quẹt thẻ...',
                    color: Colors.purpleAccent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSensorCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required String statusText,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 20),
              Text(
                title,
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            statusText,
            style: const TextStyle(color: Colors.white38, fontSize: 9),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isOn,
    required Color activeColor,
    required VoidCallback onToggle,
  }) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isOn ? activeColor.withOpacity(0.15) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOn ? activeColor : Colors.white12,
            width: isOn ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isOn ? activeColor.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: isOn ? activeColor : Colors.white38, size: 22),
                ),
                Switch(
                  value: isOn,
                  onChanged: (_) => onToggle(),
                  activeColor: activeColor,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isOn ? activeColor : Colors.white38,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String statusText,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              Icon(Icons.wifi, color: color, size: 16),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
