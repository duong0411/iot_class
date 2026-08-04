import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/models/node_model.dart';
import '../../../core/utils/responsive.dart';
import '../widgets/device_control_card.dart';
import '../widgets/sensor_card.dart';

class KitchenLivingScreen extends StatelessWidget {
  final String nodeId;

  const KitchenLivingScreen({super.key, required this.nodeId});

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
          bottom: true,
          child: Consumer<DeviceProvider>(
            builder: (context, devices, _) {
              final NodeModel? node = devices.getNodeById(nodeId);
              if (node == null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.danger, size: 48),
                      const SizedBox(height: 16),
                      const Text('Không tìm thấy thiết bị.', style: TextStyle(color: Colors.white)),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Quay lại'),
                      ),
                    ],
                  ),
                );
              }

              final bool hasAlerts = node.gasDetector || node.fireDetector || node.rainDetector;

              return Column(
                children: [
                  _buildHeader(context, node),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: R.scrollPadding(context, extra: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),

                          // ── Cảnh báo ─────────────────────────────────
                          if (hasAlerts) ...[
                            _alertBanner(node),
                            const SizedBox(height: 16),
                          ],

                          // ── Cảm biến môi trường ───────────────────────
                          _sectionTitle('Cảm biến môi trường'),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: SensorCard(
                                  title: 'Nhiệt độ',
                                  icon: Icons.thermostat_rounded,
                                  value: node.temperature.toStringAsFixed(1),
                                  unit: '°C',
                                  color: AppTheme.warning,
                                ).animate(delay: 50.ms).fadeIn().slideY(begin: 0.2),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SensorCard(
                                  title: 'Độ ẩm',
                                  icon: Icons.water_drop_rounded,
                                  value: node.humidity.toStringAsFixed(0),
                                  unit: '%',
                                  color: AppTheme.info,
                                ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.2),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: SensorCard(
                                  title: 'Khí gas',
                                  icon: Icons.gas_meter_rounded,
                                  value: node.gasDetector ? 'Nguy hiểm' : 'An toàn',
                                  unit: '',
                                  valueFontSize: 16,
                                  color: node.gasDetector ? AppTheme.danger : AppTheme.success,
                                  isAlert: node.gasDetector,
                                ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.2),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SensorCard(
                                  title: 'Lửa',
                                  icon: Icons.local_fire_department_rounded,
                                  value: node.fireDetector ? 'Báo cháy' : 'An toàn',
                                  unit: '',
                                  valueFontSize: 16,
                                  color: node.fireDetector ? AppTheme.danger : AppTheme.success,
                                  isAlert: node.fireDetector,
                                ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SensorCard(
                                  title: 'Mưa',
                                  icon: Icons.cloudy_snowing,
                                  value: node.rainDetector ? 'Có mưa' : 'Tạnh',
                                  unit: '',
                                  valueFontSize: 16,
                                  color: node.rainDetector ? AppTheme.info : AppTheme.success,
                                  isAlert: false,
                                ).animate(delay: 250.ms).fadeIn().slideY(begin: 0.2),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // ── Thiết bị điều khiển ───────────────────────
                          _sectionTitle('Điều khiển thiết bị'),
                          const SizedBox(height: 12),

                          DeviceControlCard(
                            title: 'Đèn',
                            icon: Icons.lightbulb_rounded,
                            isOn: node.light,
                            onToggle: () => devices.toggleKitchenLight(nodeId),
                            activeColor: const Color(0xFFFFD700),
                            description: node.light ? 'Đang bật' : 'Đang tắt',
                            isOffline: !node.isOnline,
                          ).animate(delay: 250.ms).fadeIn().slideX(begin: -0.2),
                          const SizedBox(height: 12),

                          DeviceControlCard(
                            title: 'Quạt',
                            icon: Icons.wind_power_rounded,
                            isOn: node.fan,
                            onToggle: () => devices.toggleKitchenFan(nodeId),
                            activeColor: AppTheme.secondary,
                            description: node.fan ? 'Đang bật' : 'Đang tắt',
                            isOffline: !node.isOnline,
                          ).animate(delay: 300.ms).fadeIn().slideX(begin: 0.2),
                          const SizedBox(height: 12),

                          DeviceControlCard(
                            title: 'Cửa',
                            icon: Icons.sensor_door_rounded,
                            isOn: node.door,
                            onToggle: () => devices.toggleKitchenDoor(nodeId),
                            activeColor: AppTheme.primary,
                            description: node.door ? 'Đang mở' : 'Đang đóng',
                            isOffline: !node.isOnline,
                            extra: Column(
                              children: [
                                const SizedBox(height: 8),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: AppTheme.primary,
                                    inactiveTrackColor: AppTheme.primary.withValues(alpha: 0.2),
                                    thumbColor: AppTheme.primary,
                                    overlayColor: AppTheme.primary.withValues(alpha: 0.2),
                                    valueIndicatorColor: AppTheme.primary,
                                    valueIndicatorTextStyle: const TextStyle(color: Colors.white),
                                    trackHeight: 4,
                                  ),
                                  child: Slider(
                                    value: node.doorAngle,
                                    min: 0,
                                    max: 180,
                                    divisions: 180,
                                    label: '${node.doorAngle.round()}°',
                                    onChanged: (val) {},
                                    onChangeEnd: (val) {
                                      devices.setKitchenDoorAngle(nodeId, val);
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Đóng (0°)', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.7), fontSize: 11)),
                                      Text('Mở (180°)', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.7), fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ).animate(delay: 350.ms).fadeIn().slideX(begin: -0.2),
                          const SizedBox(height: 12),

                          DeviceControlCard(
                            title: 'Dàn phơi quần áo',
                            icon: Icons.dry_cleaning_rounded,
                            isOn: node.clothesDryer,
                            onToggle: () => devices.toggleClothesDryer(nodeId),
                            activeColor: const Color(0xFF4DD0E1),
                            description: node.clothesDryer ? 'Đang phơi' : 'Đã thu vào',
                            isOffline: !node.isOnline,
                            extra: Column(
                              children: [
                                const SizedBox(height: 8),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: const Color(0xFF4DD0E1),
                                    inactiveTrackColor: const Color(0xFF4DD0E1).withValues(alpha: 0.2),
                                    thumbColor: const Color(0xFF4DD0E1),
                                    overlayColor: const Color(0xFF4DD0E1).withValues(alpha: 0.2),
                                    valueIndicatorColor: const Color(0xFF4DD0E1),
                                    valueIndicatorTextStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                                    trackHeight: 4,
                                  ),
                                  child: Slider(
                                    value: node.clothesDryerAngle,
                                    min: 0,
                                    max: 180,
                                    divisions: 180,
                                    label: '${node.clothesDryerAngle.round()}°',
                                    onChanged: (val) {},
                                    onChangeEnd: (val) {
                                      devices.setClothesDryerAngle(nodeId, val);
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Thu vào (0°)', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.7), fontSize: 11)),
                                      Text('Phơi ra (180°)', style: TextStyle(color: AppTheme.textMuted.withValues(alpha: 0.7), fontSize: 11)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ).animate(delay: 400.ms).fadeIn().slideX(begin: 0.2),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, NodeModel node) {
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
              child: const Icon(Icons.arrow_back_ios_rounded,
                  size: 18, color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'ID: ${node.chipId}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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

  Widget _alertBanner(NodeModel node) {
    final isDanger = node.gasDetector || node.fireDetector;
    final color = isDanger ? AppTheme.danger : AppTheme.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(isDanger ? Icons.warning_amber_rounded : Icons.info_outline_rounded, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              node.gasDetector
                  ? '⚠️ Phát hiện rò rỉ khí gas! Kiểm tra ngay!'
                  : node.fireDetector
                      ? '🔥 Phát hiện lửa! Kiểm tra ngay!'
                      : '🌧️ Trời đang mưa! Dàn phơi đã được đóng.',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600),
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
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
