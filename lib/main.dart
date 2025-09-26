import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:workspace/utils/colors.dart';
import 'Timer.dart';
import 'core/Db_helper.dart';
import 'core/data_service.dart';
import 'core/debug_close_shift.dart';
import 'screens/home_router.dart';
import 'screens/cashier/Closeshift_cashier.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/product_db.dart'; // للوصول إلى ProductDb
import 'core/db_helper_Subscribe.dart'; // للوصول إلى SubscriptionDb

void main() async {
  TimeTicker.start();
  /*  await DbHelper.instance.database; // تأكد DB جاهز
  print('calling closeShiftDetailed...');
  final shiftId = 'shift_test_1';
  // تأكد أن الشيفت موجود أو استعمل debugPopulateAndClose الذي ينشئ شيفت أولاً
  await debugPopulateAndClose();*/
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

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.transparent,
            backgroundColor: AppColorsDark.bgColor,
            overlayColor: Colors.blueAccent.withOpacity(0.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(color: AppColorsDark.mainColor, width: 1.5),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              // fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),

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
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.transparent,
          // الهينت يطلع كـ Label
          labelStyle: const TextStyle(
            color: Colors.white70,
          ), // لونه لما مش Focus
          floatingLabelStyle: const TextStyle(color: Colors.white),
          hintStyle: const TextStyle(color: Colors.white70),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white24, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: 12,
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
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Colors.blueAccent, // لون المؤشر
          selectionColor: Colors.blueAccent, // لون تحديد النص
          selectionHandleColor: Colors.blueAccent, // لون الهاندلز بتاعة التحديد
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1A2233), // لون الخلفية الداكن
          contentTextStyle: const TextStyle(
            color: Colors.white, // لون النص
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          behavior: SnackBarBehavior.floating, // يظهر بشكل floating
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 6,
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
