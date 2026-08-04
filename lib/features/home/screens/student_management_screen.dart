import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/student_provider.dart';
import '../../../core/models/student_model.dart';

class StudentManagementScreen extends StatefulWidget {
  const StudentManagementScreen({super.key});

  @override
  State<StudentManagementScreen> createState() => _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showAddEditStudentDialog(BuildContext context, [StudentModel? student]) {
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    final isEditing = student != null;

    final nameController = TextEditingController(text: student?.name ?? '');
    final codeController = TextEditingController(text: student?.studentCode ?? '');
    final rfidController = TextEditingController(
      text: student?.rfidUid ?? studentProvider.lastScannedUnmappedUid ?? '',
    );
    final classController = TextEditingController(text: student?.className ?? 'Lớp 10A1');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(isEditing ? Icons.edit : Icons.person_add, color: Colors.cyanAccent),
            const SizedBox(width: 8),
            Text(
              isEditing ? 'Sửa Học Sinh' : 'Đăng Ký Học Sinh Mới',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField(nameController, 'Họ và Tên Học Sinh', Icons.person),
              const SizedBox(height: 12),
              _buildTextField(codeController, 'Mã Học Sinh (MSSV)', Icons.badge),
              const SizedBox(height: 12),
              _buildTextField(classController, 'Lớp Học', Icons.class_),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(rfidController, 'Mã Thẻ RFID (UID)', Icons.nfc),
                  ),
                  if (studentProvider.lastScannedUnmappedUid != null)
                    IconButton(
                      icon: const Icon(Icons.download, color: Colors.cyanAccent),
                      tooltip: 'Lấy mã thẻ vừa quẹt',
                      onPressed: () {
                        rfidController.text = studentProvider.lastScannedUnmappedUid!;
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          if (student != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _confirmDeleteSingle(context, student);
              },
              child: const Text('Xóa Học Sinh', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final name = nameController.text.trim();
              final code = codeController.text.trim();
              final rfid = rfidController.text.trim();
              final className = classController.text.trim();

              if (name.isEmpty || code.isEmpty || rfid.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vui lòng điền đầy đủ thông tin!')),
                );
                return;
              }

              if (isEditing) {
                await studentProvider.updateStudent(student.id, name, code, rfid, className);
              } else {
                await studentProvider.addStudent(name, code, rfid, className);
              }

              if (mounted) Navigator.pop(ctx);
            },
            child: Text(isEditing ? 'Lưu' : 'Thêm Mới', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAll(BuildContext context) {
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Xóa Tất Cả Học Sinh?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn xóa TOÀN BỘ danh sách học sinh không? Hành động này không thể hoàn tác.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await studentProvider.deleteAllStudents();
              if (mounted) Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã xóa toàn bộ danh sách học sinh!')),
              );
            },
            child: const Text('Xóa Tất Cả', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSingle(BuildContext context, StudentModel student) {
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Xóa Học Sinh?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa học sinh "${student.name}" (MSSV: ${student.studentCode}) không?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await studentProvider.deleteStudent(student.id);
              if (mounted) Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Đã xóa học sinh ${student.name}')),
              );
            },
            child: const Text('Xóa Học Sinh', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmClearLogs(BuildContext context) {
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.history_toggle_off, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Xóa Lịch Sử Điểm Danh?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn xóa TOÀN BỘ nhật ký lịch sử điểm danh không?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await studentProvider.clearAttendanceLogs();
              if (mounted) Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã xóa toàn bộ nhật ký điểm danh!')),
              );
            },
            child: const Text('Xóa Nhật Ký', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.cyanAccent, size: 20),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final studentProvider = Provider.of<StudentProvider>(context);

    // Lọc danh sách học sinh theo ô tìm kiếm
    final filteredStudents = studentProvider.students.where((s) {
      final q = _searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(q) ||
          s.studentCode.toLowerCase().contains(q) ||
          s.rfidUid.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text('Điểm Danh & Quản Lý RFID', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: const Color(0xFF1E293B),
            onSelected: (value) async {
              if (value == 'clear_all') {
                _confirmDeleteAll(context);
              } else if (value == 'clear_logs') {
                _confirmClearLogs(context);
              } else if (value == 'restore_sample') {
                await studentProvider.restoreSampleStudents();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã khôi phục danh sách học sinh mẫu!')),
                  );
                }
              } else if (value == 'reset_attendance') {
                await studentProvider.resetAllAttendance();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã đặt lại trạng thái điểm danh đầu ngày!')),
                  );
                }
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, color: Colors.redAccent, size: 20),
                    SizedBox(width: 8),
                    Text('Xóa Danh Sách Học Sinh', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear_logs',
                child: Row(
                  children: [
                    Icon(Icons.history_toggle_off, color: Colors.orangeAccent, size: 20),
                    SizedBox(width: 8),
                    Text('Xóa Lịch Sử Điểm Danh', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'restore_sample',
                child: Row(
                  children: [
                    Icon(Icons.restore, color: Colors.cyanAccent, size: 20),
                    SizedBox(width: 8),
                    Text('Khôi Phục Dữ Liệu Mẫu', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'reset_attendance',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt, color: Colors.greenAccent, size: 20),
                    SizedBox(width: 8),
                    Text('Đặt Lại Điểm Danh (Vắng)', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyanAccent,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Danh Sách Học Sinh'),
            Tab(icon: Icon(Icons.history), text: 'Lịch Sử Điểm Danh'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Banner thông báo nếu phát hiện thẻ RFID mới vừa quẹt trên ESP32
          if (studentProvider.lastScannedUnmappedUid != null)
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purpleAccent),
              ),
              child: Row(
                children: [
                  const Icon(Icons.nfc, color: Colors.purpleAccent, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '💳 Thẻ RFID mới vừa quẹt!',
                          style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'Mã UID: ${studentProvider.lastScannedUnmappedUid}',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purpleAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    onPressed: () => _showAddEditStudentDialog(context),
                    child: const Text('Đăng ký', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                    onPressed: () => studentProvider.clearUnmappedUid(),
                  ),
                ],
              ),
            ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: DANH SÁCH HỌC SINH
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white),
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Tìm kiếm theo tên, MSSV, RFID...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                          prefixIcon: const Icon(Icons.search, color: Colors.cyanAccent),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),

                    Expanded(
                      child: filteredStudents.isEmpty
                          ? const Center(
                              child: Text('Chưa có học sinh nào trong danh sách', style: TextStyle(color: Colors.white38)),
                            )
                          : ListView.builder(
                              itemCount: filteredStudents.length,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              itemBuilder: (ctx, i) {
                                final s = filteredStudents[i];
                                return Dismissible(
                                  key: Key(s.id),
                                  direction: DismissDirection.endToStart,
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.delete, color: Colors.white),
                                  ),
                                  onDismissed: (_) async {
                                    await studentProvider.deleteStudent(s.id);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Đã xóa học sinh ${s.name}')),
                                    );
                                  },
                                  child: Card(
                                    color: const Color(0xFF1E293B),
                                    margin: const EdgeInsets.only(bottom: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(
                                        color: s.isPresent ? Colors.green : Colors.white10,
                                        width: s.isPresent ? 1.5 : 1,
                                      ),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: s.isPresent ? Colors.green : Colors.blueGrey,
                                        child: Icon(
                                          s.isPresent ? Icons.check : Icons.person,
                                          color: Colors.white,
                                        ),
                                      ),
                                      title: Text(
                                        s.name,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Text(
                                        'MSSV: ${s.studentCode} | UID: ${s.rfidUid}\nTrạng thái: ${s.isPresent ? "CÓ MẶT" : "VẮNG"}',
                                        style: TextStyle(
                                          color: s.isPresent ? Colors.greenAccent : Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
                                            tooltip: 'Sửa thông tin',
                                            onPressed: () => _showAddEditStudentDialog(context, s),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                            tooltip: 'Xóa học sinh',
                                            onPressed: () => _confirmDeleteSingle(context, s),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),

                // TAB 2: LỊCH SỬ ĐIỂM DANH THỜI GIAN THỰC
                Column(
                  children: [
                    if (studentProvider.logs.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Tổng cộng: ${studentProvider.logs.length} lượt điểm danh',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 18),
                              label: const Text('Xóa Nhật Ký', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () => _confirmClearLogs(context),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: studentProvider.logs.isEmpty
                          ? const Center(
                              child: Text('Chưa có lịch sử điểm danh nào', style: TextStyle(color: Colors.white38)),
                            )
                          : ListView.builder(
                              itemCount: studentProvider.logs.length,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              itemBuilder: (ctx, i) {
                                final log = studentProvider.logs[i];
                                final timeStr =
                                    "${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')} (${log.timestamp.day}/${log.timestamp.month})";

                                return Card(
                                  color: const Color(0xFF1E293B),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: const Icon(Icons.verified, color: Colors.greenAccent),
                                    title: Text(log.studentName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    subtitle: Text('MSSV: ${log.studentCode} | UID: ${log.rfidUid}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                    trailing: Text(timeStr, style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.cyan,
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text('Thêm Học Sinh', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        onPressed: () => _showAddEditStudentDialog(context),
      ),
    );
  }
}
