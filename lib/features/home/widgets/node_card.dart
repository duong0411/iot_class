import 'package:flutter/material.dart';
import '../../../core/models/node_model.dart';
import '../../../core/theme/app_theme.dart';

class NodeCard extends StatelessWidget {
  final NodeModel node;
  final VoidCallback onTapManage;
  final VoidCallback onDelete;

  const NodeCard({
    super.key,
    required this.node,
    required this.onTapManage,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.textMuted.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Icon + Name + Status + Delete
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  node.templateType == 'kitchen_living' 
                      ? Icons.kitchen_rounded 
                      : Icons.bed_rounded,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'ID: ${node.chipId}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: node.isOnline ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: node.isOnline ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      node.isOnline ? 'ONLINE' : 'NGOẠI TUYẾN',
                      style: TextStyle(
                        color: node.isOnline ? Colors.green : Colors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Delete Button
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: onDelete,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          
          const SizedBox(height: 16),

          // Sensors
          if (node.templateType == 'kitchen_living')
            Row(
              children: [
                Expanded(
                  child: _buildSensorBox(
                    'Nhiệt độ',
                    '${node.temperature.toStringAsFixed(1)} °C',
                    Icons.thermostat,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSensorBox(
                    'Độ ẩm',
                    '${node.humidity.toStringAsFixed(1)} %',
                    Icons.water_drop,
                  ),
                ),
              ],
            ),

          if (node.templateType == 'kitchen_living')
            const SizedBox(height: 16),

          // Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Quick Actions
              Row(
                children: [
                  _buildQuickAction(Icons.bolt, node.isOnline),
                  const SizedBox(width: 8),
                  _buildQuickAction(Icons.power_settings_new, node.isOnline),
                ],
              ),
              // Manage Button
              GestureDetector(
                onTap: onTapManage,
                child: const Row(
                  children: [
                    Text(
                      'Quản lý',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppTheme.primary, size: 20),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSensorBox(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textMuted.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.textSecondary, size: 14),
              const SizedBox(width: 4),
              Text(
                title,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, bool isOnline) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isOnline ? AppTheme.primary.withOpacity(0.1) : AppTheme.bgDark,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        color: isOnline ? AppTheme.primary : AppTheme.textMuted,
        size: 16,
      ),
    );
  }
}
