import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/data_service.dart';
import 'screens/home_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/product_db.dart'; // للوصول إلى ProductDb
import 'core/db_helper_Subscribe.dart'; // للوصول إلى SubscriptionDb

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  WidgetsFlutterBinding.ensureInitialized();
  await AdminDataService.instance.init();

  //  await AdminDataService.instance.loadAll();
  await loadData();
  //  await AdminDataService.instance.loadPasswords();
  runApp(const WorkspaceCashierApp());
}

Future<void> loadData() async {
  final products = await ProductDb.getProducts();
  final subscriptions = await SubscriptionDb.getPlans();

  AdminDataService.instance.products
    ..clear()
    ..addAll(products);

  AdminDataService.instance.subscriptions
    ..clear()
    ..addAll(subscriptions);
}

class WorkspaceCashierApp extends StatelessWidget {
  const WorkspaceCashierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WorkSpace Cashier',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0F1A),
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),

        // تخصيص الـ Dialog
        dialogTheme: DialogTheme(
          backgroundColor: const Color(0xFF1A2233), // لون خلفية الدايلوج
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titleTextStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          contentTextStyle: const TextStyle(
            fontSize: 16,
            color: Colors.white70,
          ),
        ),

        // تخصيص أزرار TextButton زي اللي جوه SimpleDialogOption
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFFF2A2A), // لون النص + الأيقونة
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // تخصيص أزرار ElevatedButton (زي زرار الدخول)
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5387FF),
            foregroundColor: Colors.white,
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),

      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: HomeRouter(),
      ),
    );
  }
}

////كدا واقف ان الاشتراكات ملهاش نهايه هو بيحسب سعرها وخلاص
