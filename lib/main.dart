import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/device_provider.dart';
import 'core/providers/student_provider.dart';
import 'features/auth/screens/splash_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/services/notification_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  
  // Khởi tạo NotificationService trong isolate nền
  // await NotificationService().init(); // Gây crash background isolate trên một số máy ảo

  // final data = message.data;
  // final title = data['title'] ?? '⚠️ Cảnh báo khẩn cấp';
  // final body = data['body'] ?? 'Phát hiện sự cố nguy hiểm!';

  // await NotificationService().showWarningNotification(
  //   id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
  //   title: title,
  //   body: body,
  // );
  
  print("FCM Background Message Processed: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await dotenv.load(fileName: ".env");
  
  // Đăng ký Background Handler cho FCM
  // FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler); // Tạm thời vô hiệu hóa để tránh crash máy ảo 16k

  // Yêu cầu quyền thông báo (cho iOS / Android 13+)
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // Khởi tạo NotificationService cho Local Notification (nếu cần thiết)
  await NotificationService().init();

  // Chỉ set overlay style (status bar trong suốt) — không dùng edgeToEdge
  // vì gây vòng lặp WindowInsets trên emulator Android
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => DeviceProvider()),
      ],
      child: MaterialApp(
        title: 'Lớp Học Thông Minh',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const SplashScreen(),
      ),
    );
  }
}

