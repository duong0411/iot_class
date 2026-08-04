import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/student_model.dart';

class AttendanceLog {
  final String studentName;
  final String studentCode;
  final String rfidUid;
  final DateTime timestamp;

  AttendanceLog({
    required this.studentName,
    required this.studentCode,
    required this.rfidUid,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'studentName': studentName,
        'studentCode': studentCode,
        'rfidUid': rfidUid,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AttendanceLog.fromJson(Map<String, dynamic> json) => AttendanceLog(
        studentName: json['studentName'] ?? '',
        studentCode: json['studentCode'] ?? '',
        rfidUid: json['rfidUid'] ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      );
}

class StudentProvider extends ChangeNotifier {
  static const String _storageKey = 'classroom_students_db';
  static const String _logStorageKey = 'classroom_attendance_logs';

  List<StudentModel> _students = [];
  List<StudentModel> get students => _students;

  List<AttendanceLog> _logs = [];
  List<AttendanceLog> get logs => _logs;

  String? _lastScannedUnmappedUid;
  String? get lastScannedUnmappedUid => _lastScannedUnmappedUid;

  StudentProvider() {
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final rawStudents = prefs.getString(_storageKey);
    if (rawStudents != null && rawStudents.isNotEmpty) {
      _students = StudentModel.decodeList(rawStudents);
    } else {
      // Dữ liệu học sinh mẫu ban đầu
      _students = [
        StudentModel(id: '1', name: 'Nguyễn Văn A', studentCode: 'HS001', rfidUid: 'A1B2C3D4', className: 'Lớp 10A1'),
        StudentModel(id: '2', name: 'Trần Thị B', studentCode: 'HS002', rfidUid: 'E5F6G7H8', className: 'Lớp 10A1'),
        StudentModel(id: '3', name: 'Lê Văn C', studentCode: 'HS003', rfidUid: '13A4B5C6', className: 'Lớp 10A1'),
      ];
      await _saveStudents();
    }

    final rawLogs = prefs.getString(_logStorageKey);
    if (rawLogs != null && rawLogs.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(rawLogs);
        _logs = jsonList.map((item) => AttendanceLog.fromJson(item)).toList();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _saveStudents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, StudentModel.encodeList(_students));
  }

  Future<void> _saveLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final rawLogs = jsonEncode(_logs.map((l) => l.toJson()).toList());
    await prefs.setString(_logStorageKey, rawLogs);
  }

  // Thêm học sinh mới
  Future<void> addStudent(String name, String studentCode, String rfidUid, String className) async {
    final newStudent = StudentModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      studentCode: studentCode,
      rfidUid: rfidUid.trim().toUpperCase(),
      className: className,
    );

    _students.add(newStudent);
    if (_lastScannedUnmappedUid == rfidUid.toUpperCase()) {
      _lastScannedUnmappedUid = null;
    }
    await _saveStudents();
    notifyListeners();
  }

  // Sửa thông tin học sinh
  Future<void> updateStudent(String id, String name, String studentCode, String rfidUid, String className) async {
    final index = _students.indexWhere((s) => s.id == id);
    if (index != -1) {
      _students[index] = _students[index].copyWith(
        name: name,
        studentCode: studentCode,
        rfidUid: rfidUid.trim().toUpperCase(),
        className: className,
      );
      await _saveStudents();
      notifyListeners();
    }
  }

  // Xóa 1 học sinh
  Future<void> deleteStudent(String id) async {
    _students.removeWhere((s) => s.id == id);
    await _saveStudents();
    notifyListeners();
  }

  // Xóa toàn bộ danh sách học sinh
  Future<void> deleteAllStudents() async {
    _students.clear();
    await _saveStudents();
    notifyListeners();
  }

  // Khôi phục danh sách học sinh mẫu
  Future<void> restoreSampleStudents() async {
    _students = [
      StudentModel(id: '1', name: 'Nguyễn Văn A', studentCode: 'HS001', rfidUid: 'A1B2C3D4', className: 'Lớp 10A1'),
      StudentModel(id: '2', name: 'Trần Thị B', studentCode: 'HS002', rfidUid: 'E5F6G7H8', className: 'Lớp 10A1'),
      StudentModel(id: '3', name: 'Lê Văn C', studentCode: 'HS003', rfidUid: '13A4B5C6', className: 'Lớp 10A1'),
    ];
    await _saveStudents();
    notifyListeners();
  }

  // Xử lý Sự cố quẹt thẻ RFID từ ESP32 qua MQTT
  void handleRFIDScanned(String uid) {
    final upperUid = uid.trim().toUpperCase();
    final index = _students.indexWhere((s) => s.rfidUid == upperUid);

    if (index != -1) {
      final student = _students[index];
      student.isPresent = true;
      student.lastCheckIn = DateTime.now();

      // Thêm log điểm danh
      _logs.insert(
        0,
        AttendanceLog(
          studentName: student.name,
          studentCode: student.studentCode,
          rfidUid: upperUid,
          timestamp: student.lastCheckIn!,
        ),
      );

      _saveStudents();
      _saveLogs();
      _lastScannedUnmappedUid = null;
    } else {
      // Thẻ chưa được đăng ký cho học sinh nào
      _lastScannedUnmappedUid = upperUid;
    }

    notifyListeners();
  }

  void clearUnmappedUid() {
    _lastScannedUnmappedUid = null;
    notifyListeners();
  }

  // Xóa toàn bộ nhật ký lịch sử điểm danh
  Future<void> clearAttendanceLogs() async {
    _logs.clear();
    await _saveLogs();
    notifyListeners();
  }

  // Đặt lại điểm danh đầu ngày
  Future<void> resetAllAttendance() async {
    for (var s in _students) {
      s.isPresent = false;
      s.lastCheckIn = null;
    }
    await _saveStudents();
    notifyListeners();
  }

  int get presentCount => _students.where((s) => s.isPresent).length;
  int get totalCount => _students.length;
}
