import 'dart:convert';

class StudentModel {
  final String id;
  final String name;
  final String studentCode;
  final String rfidUid;
  final String className;
  bool isPresent;
  DateTime? lastCheckIn;

  StudentModel({
    required this.id,
    required this.name,
    required this.studentCode,
    required this.rfidUid,
    this.className = 'Lớp 10A1',
    this.isPresent = false,
    this.lastCheckIn,
  });

  StudentModel copyWith({
    String? id,
    String? name,
    String? studentCode,
    String? rfidUid,
    String? className,
    bool? isPresent,
    DateTime? lastCheckIn,
  }) {
    return StudentModel(
      id: id ?? this.id,
      name: name ?? this.name,
      studentCode: studentCode ?? this.studentCode,
      rfidUid: rfidUid ?? this.rfidUid,
      className: className ?? this.className,
      isPresent: isPresent ?? this.isPresent,
      lastCheckIn: lastCheckIn ?? this.lastCheckIn,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'studentCode': studentCode,
      'rfidUid': rfidUid.toUpperCase(),
      'className': className,
      'isPresent': isPresent,
      'lastCheckIn': lastCheckIn?.toIso8601String(),
    };
  }

  factory StudentModel.fromJson(Map<String, dynamic> json) {
    return StudentModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      studentCode: json['studentCode'] ?? '',
      rfidUid: (json['rfidUid'] ?? '').toString().toUpperCase(),
      className: json['className'] ?? 'Lớp 10A1',
      isPresent: json['isPresent'] ?? false,
      lastCheckIn: json['lastCheckIn'] != null ? DateTime.tryParse(json['lastCheckIn']) : null,
    );
  }

  static String encodeList(List<StudentModel> students) {
    return jsonEncode(students.map((s) => s.toJson()).toList());
  }

  static List<StudentModel> decodeList(String rawJson) {
    if (rawJson.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(rawJson);
      return list.map((item) => StudentModel.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }
}
