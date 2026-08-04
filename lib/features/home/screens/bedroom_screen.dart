import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/models/node_model.dart';
import '../../../core/utils/responsive.dart';
import '../widgets/device_control_card.dart';

class BedroomScreen extends StatelessWidget {
  final String nodeId;

  const BedroomScreen({super.key, required this.nodeId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF001A15), Color(0xFF0A0E21)],
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

                          _sectionTitle('Điều khiển thiết bị'),
                          const SizedBox(height: 12),

                          DeviceControlCard(
                            title: 'Đèn phòng ngủ',
                            icon: Icons.lightbulb_rounded,
                            isOn: node.bedroomLight,
                            onToggle: () => devices.toggleBedroomLight(nodeId),
                            activeColor: const Color(0xFFFFD700),
                            description: node.bedroomLight ? 'Đang bật' : 'Đang tắt',
                            isOffline: !node.isOnline,
                          ).animate(delay: 100.ms).fadeIn().slideX(begin: -0.2),
                          const SizedBox(height: 12),

                          DeviceControlCard(
                            title: 'Quạt phòng ngủ',
                            icon: Icons.wind_power_rounded,
                            isOn: node.bedroomFan,
                            onToggle: () => devices.toggleBedroomFan(nodeId),
                            activeColor: AppTheme.secondary,
                            description: node.bedroomFan ? 'Đang bật' : 'Đang tắt',
                            isOffline: !node.isOnline,
                          ).animate(delay: 150.ms).fadeIn().slideX(begin: 0.2),
                          const SizedBox(height: 12),

                          DeviceControlCard(
                            title: 'Cửa',
                            icon: Icons.door_front_door_rounded,
                            isOn: node.curtain,
                            onToggle: () => devices.toggleCurtain(nodeId),
                            activeColor: const Color(0xFFB47AEA),
                            description: node.curtain ? 'Đang mở' : 'Đang đóng',
                            isOffline: !node.isOnline,
                            extra: Column(
                              children: [
                                const SizedBox(height: 8),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: const Color(0xFFB47AEA),
                                    inactiveTrackColor: const Color(0xFFB47AEA).withValues(alpha: 0.2),
                                    thumbColor: const Color(0xFFB47AEA),
                                    overlayColor: const Color(0xFFB47AEA).withValues(alpha: 0.2),
                                    valueIndicatorColor: const Color(0xFFB47AEA),
                                    valueIndicatorTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    trackHeight: 4,
                                  ),
                                  child: Slider(
                                    value: node.curtainAngle,
                                    min: 0,
                                    max: 180,
                                    divisions: 180,
                                    label: '${node.curtainAngle.round()}°',
                                    onChanged: (val) {},
                                    onChangeEnd: (val) {
                                      devices.setCurtainAngle(nodeId, val);
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
                          ).animate(delay: 200.ms).fadeIn().slideX(begin: -0.2),

                          const SizedBox(height: 32),

                          // Tóm tắt trạng thái
                          _sectionTitle('Tổng quan'),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _summaryTile(
                                  icon: Icons.lightbulb_rounded,
                                  label: 'Đèn',
                                  isOn: node.bedroomLight,
                                  color: const Color(0xFFFFD700),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _summaryTile(
                                  icon: Icons.wind_power_rounded,
                                  label: 'Quạt',
                                  isOn: node.bedroomFan,
                                  color: AppTheme.secondary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _summaryTile(
                                  icon: Icons.door_front_door_rounded,
                                  label: 'Cửa',
                                  isOn: node.curtain,
                                  color: const Color(0xFFB47AEA),
                                ),
                              ),
                            ],
                          ),
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
                colors: [Color(0xFF00D4AA), Color(0xFF007ACC)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.bed_rounded, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _summaryTile({
    required IconData icon,
    required String label,
    required bool isOn,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: isOn ? color.withValues(alpha: 0.1) : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOn ? color.withValues(alpha: 0.4) : AppTheme.bgCardLight,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: isOn ? color : AppTheme.textMuted, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: isOn ? AppTheme.textPrimary : AppTheme.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            isOn ? 'BẬT' : 'TẮT',
            style: TextStyle(
              color: isOn ? color : AppTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
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
