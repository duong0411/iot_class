import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/device_provider.dart';
import '../widgets/device_control_card.dart';
import '../widgets/sensor_card.dart';
import '../widgets/servo_indicator.dart';

class LivingRoomScreen extends StatelessWidget {
  const LivingRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D0A1A), Color(0xFF0A0E21)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Consumer<DeviceProvider>(
                    builder: (context, devices, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          
                          // Sensor row
                          _sectionTitle('Thông số môi trường'),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: SensorCard(
                                  title: 'Nhiệt độ',
                                  icon: Icons.thermostat_rounded,
                                  value: devices.livingRoomTemp.toStringAsFixed(1),
                                  color: AppTheme.warning,
                                  unit: '°C',
                                ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.2),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SensorCard(
                                  title: 'Độ ẩm',
                                  icon: Icons.water_drop_rounded,
                                  value: devices.livingRoomHumidity.toStringAsFixed(0),
                                  color: AppTheme.info,
                                  unit: '%',
                                ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.2),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Controls
                          _sectionTitle('Điều khiển thiết bị'),
                          const SizedBox(height: 12),

                          // Door control with servo
                          DeviceControlCard(
                            title: 'Cửa phòng khách',
                            icon: Icons.sensor_door_rounded,
                            isOn: devices.livingRoomDoor,
                            onToggle: () => devices.toggleLivingRoomDoor(),
                            activeColor: AppTheme.secondary,
                            description: devices.livingRoomDoor ? 'Đang mở' : 'Đang đóng',
                            isOffline: !devices.isKitchenOnline,
                            extra: Column(
                              children: [
                                const SizedBox(height: 12),
                                ServoIndicator(
                                  angle: devices.livingRoomDoor ? 90 : 0,
                                  label: 'Servo SG90',
                                  isActive: devices.livingRoomDoor,
                                ),
                              ],
                            ),
                          ).animate(delay: 200.ms).fadeIn().slideX(begin: -0.2),
                          const SizedBox(height: 12),

                          // Clothes dryer with servo
                          DeviceControlCard(
                            title: 'Giàn phơi quần áo',
                            icon: Icons.dry_cleaning_rounded,
                            isOn: devices.clothesDryer,
                            onToggle: () => devices.toggleClothesDryer(),
                            activeColor: const Color(0xFFFFB347),
                            description: devices.clothesDryer ? 'Đang phơi ra ngoài' : 'Đang thu vào',
                            isOffline: !devices.isKitchenOnline,
                            extra: Column(
                              children: [
                                const SizedBox(height: 12),
                                ServoIndicator(
                                  angle: devices.clothesDryerAngle,
                                  label: 'Servo SG90 - Góc ${devices.clothesDryerAngle.toStringAsFixed(0)}°',
                                  isActive: devices.clothesDryer,
                                ),
                                if (devices.clothesDryer) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.warning.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.wb_sunny_rounded, color: AppTheme.warning, size: 14),
                                        const SizedBox(width: 6),
                                        const Text(
                                          'Giàn phơi đang ở ngoài trời',
                                          style: TextStyle(color: AppTheme.warning, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ).animate(delay: 250.ms).fadeIn().slideX(begin: 0.2),
                          const SizedBox(height: 32),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.arrow_back_ios_rounded, size: 18, color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phòng Khách',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Không gian sinh hoạt chung',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF3D35CC)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.weekend_rounded, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
