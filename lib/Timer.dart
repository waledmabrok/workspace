import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/material.dart';

import 'core/models.dart';

class TimeTicker {
  static final ValueNotifier<DateTime> now = ValueNotifier(DateTime.now());

  static void start() {
    Timer.periodic(const Duration(seconds: 1), (_) {
      now.value = DateTime.now();
    });
  }
}

class SessionsNotifier {
  // 🔥 ده اللي كل التابات هيسمعوا منه
  static final ValueNotifier<List<Session>> sessions =
      ValueNotifier<List<Session>>([]);
}
