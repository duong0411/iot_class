class NodeModel {
  final String id;
  final String name;
  final String chipId;
  final String templateType;
  final Map<String, dynamic> state;
  bool isOnline;

  NodeModel({
    required this.id,
    required this.name,
    required this.chipId,
    required this.templateType,
    Map<String, dynamic>? state,
    this.isOnline = false,
  }) : state = state ?? {};

  factory NodeModel.fromJson(Map<String, dynamic> json) {
    return NodeModel(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      chipId: json['chipId'] ?? '',
      templateType: json['templateType'] ?? 'kitchen_living',
      state: json['state'] != null ? Map<String, dynamic>.from(json['state']) : {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'chipId': chipId,
      'templateType': templateType,
      'state': state,
    };
  }

  // Helper getters for specific template variables
  double get temperature => (state['temperature'] ?? 0.0).toDouble();
  double get humidity => (state['humidity'] ?? 0.0).toDouble();
  bool get light => state['light'] == true;
  bool get fan => state['fan'] == true;
  bool get door => state['door'] == true;
  double get doorAngle => (state['doorAngle'] ?? 0.0).toDouble();
  bool get clothesDryer => state['clothesDryer'] == true;
  double get clothesDryerAngle => (state['clothesDryerAngle'] ?? 0.0).toDouble();
  bool get gasDetector => state['gasDetector'] == true;
  bool get fireDetector => state['fireDetector'] == true;
  bool get rainDetector => state['rainDetector'] == true;

  bool get bedroomLight => state['bedroomLight'] == true;
  bool get bedroomFan => state['bedroomFan'] == true;
  bool get curtain => state['curtain'] == true;
  double get curtainAngle => (state['curtainAngle'] ?? 0.0).toDouble();

  int get kitchenLivingActiveCount => [light, fan, door, clothesDryer].where((d) => d).length;
  int get bedroomActiveCount => [bedroomLight, bedroomFan, curtain].where((d) => d).length;
}
