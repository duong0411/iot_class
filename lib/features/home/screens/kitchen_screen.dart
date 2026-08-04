import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/device_provider.dart';
import '../widgets/device_control_card.dart';
import '../widgets/sensor_card.dart';

class KitchenScreen extends StatelessWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A0A00), Color(0xFF0A0E21)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
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
                          
                          // Alert Status
                          if (devices.gasDetector || devices.fireDetector)
                            _buildAlertCard(devices).animate().fadeIn().shake(),
                          
                          // Sensors Section
                          _sectionTitle('Cảm biến'),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: SensorCard(
                                  title: 'Khí Gas',
                                  icon: Icons.gas_meter_rounded,
                                  value: devices.gasDetector ? 'NGUY HIỂM' : 'An toàn',
                                  isAlert: devices.gasDetector,
                                  color: devices.gasDetector ? AppTheme.danger : AppTheme.success,
                                  unit: '',
                                ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.2),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SensorCard(
                                  title: 'Lửa',
                                  icon: Icons.local_fire_department_rounded,
                                  value: devices.fireDetector ? 'PHÁT HIỆN' : 'Bình thường',
                                  isAlert: devices.fireDetector,
                                  color: devices.fireDetector ? AppTheme.danger : AppTheme.success,
                                  unit: '',
                                ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.2),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: SensorCard(
                                  title: 'Nhiệt độ',
                                  icon: Icons.thermostat_rounded,
                                  value: devices.kitchenTemp.toStringAsFixed(1),
                                  color: AppTheme.warning,
                                  unit: '°C',
                                ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SensorCard(
                                  title: 'Độ ẩm',
                                  icon: Icons.water_drop_rounded,
                                  value: devices.kitchenHumidity.toStringAsFixed(0),
                                  color: AppTheme.info,
                                  unit: '%',
                                ).animate(delay: 250.ms).fadeIn().slideY(begin: 0.2),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Control Devices
                          _sectionTitle('Điều khiển'),
                          const SizedBox(height: 12),
                          DeviceControlCard(
                            title: 'Đèn bếp',
                            icon: Icons.lightbulb_rounded,
                            isOn: devices.kitchenLight,
                            onToggle: () => devices.toggleKitchenLight(),
                            activeColor: const Color(0xFFFFD700),
                            description: devices.kitchenLight ? 'Đang bật' : 'Đang tắt',
                            isOffline: !devices.isKitchenOnline,
                          ).animate(delay: 300.ms).fadeIn().slideX(begin: -0.2),
                          const SizedBox(height: 12),
                          DeviceControlCard(
                            title: 'Quạt bếp',
                            icon: Icons.wind_power_rounded,
                            isOn: devices.kitchenFan,
                            onToggle: () => devices.toggleKitchenFan(),
                            activeColor: AppTheme.secondary,
                            description: devices.kitchenFan ? 'Đang bật' : 'Đang tắt',
                            isOffline: !devices.isKitchenOnline,
                          ).animate(delay: 350.ms).fadeIn().slideX(begin: 0.2),

                          // Test Alert Buttons (for demo)
                          const SizedBox(height: 24),
                          _sectionTitle('Kiểm tra cảnh báo (Demo)'),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _testButton(
                                  context,
                                  'Mô phỏng Gas',
                                  Icons.gas_meter_rounded,
                                  AppTheme.warning,
                                  () {
                                    // Toggle gas sensor for demo
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _testButton(
                                  context,
                                  'Mô phỏng Lửa',
                                  Icons.local_fire_department_rounded,
                                  AppTheme.danger,
                                  () {},
                                ),
                              ),
                            ],
                          ),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Phòng Bếp',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Bếp & Không gian ăn uống',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFFF4757)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.kitchen_rounded, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(DeviceProvider devices) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.danger, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_rounded, color: AppTheme.danger, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              devices.gasDetector ? 'Phát hiện rò rỉ khí gas!\nHãy mở cửa và thoát ra ngay!' : 'Phát hiện lửa trong bếp!\nGọi ngay 114!',
              style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600),
            ),
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

  Widget _testButton(BuildContext context, String text, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Flexible(child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );
  }
}
