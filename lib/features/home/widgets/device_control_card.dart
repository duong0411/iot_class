import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class DeviceControlCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isOn;
  final VoidCallback onToggle;
  final Color activeColor;
  final String description;
  final Widget? extra;
  final bool isOffline;

  const DeviceControlCard({
    super.key,
    required this.title,
    required this.icon,
    required this.isOn,
    required this.onToggle,
    required this.activeColor,
    required this.description,
    this.extra,
    this.isOffline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isOffline ? 0.5 : 1.0,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isOn ? activeColor.withOpacity(0.08) : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOn ? activeColor.withOpacity(0.4) : AppTheme.bgCardLight,
          width: 1.5,
        ),
        boxShadow: isOn
            ? [
                BoxShadow(
                  color: activeColor.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isOn ? activeColor.withOpacity(0.2) : AppTheme.bgCardLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: isOn ? activeColor : AppTheme.textMuted,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),

              // Title + Status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isOn ? AppTheme.textPrimary : AppTheme.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isOn ? activeColor : AppTheme.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          description,
                          style: TextStyle(
                            color: isOn ? activeColor : AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Toggle Switch
              GestureDetector(
                onTap: isOffline ? null : onToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 56,
                  height: 30,
                  decoration: BoxDecoration(
                    color: isOn ? activeColor : AppTheme.bgCardLight,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: isOn
                        ? [
                            BoxShadow(
                              color: activeColor.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (extra != null) extra!,
        ],
      ),
      ),
    );
  }
}
