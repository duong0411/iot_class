class DeviceModel {
  final String id;
  final String name;
  final bool isOn;
  final String room;
  final String icon;
  final Map<String, dynamic>? extra;

  DeviceModel({
    required this.id,
    required this.name,
    required this.isOn,
    required this.room,
    required this.icon,
    this.extra,
  });

  DeviceModel copyWith({
    String? id,
    String? name,
    bool? isOn,
    String? room,
    String? icon,
    Map<String, dynamic>? extra,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      isOn: isOn ?? this.isOn,
      room: room ?? this.room,
      icon: icon ?? this.icon,
      extra: extra ?? this.extra,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isOn': isOn,
      'room': room,
      'icon': icon,
      'extra': extra,
    };
  }
}
