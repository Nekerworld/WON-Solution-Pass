import 'package:flutter/widgets.dart';

import '../app/case_controller.dart';
import '../data/bank_store.dart';
import '../data/mock_bank.dart';
import '../domain/event_log.dart';
import '../domain/pathfinder.dart';

class AppServices {
  const AppServices({
    required this.controller,
    required this.store,
    required this.bank,
    required this.events,
    required this.pathfinder,
  });

  final CaseController controller;
  final BankStore store;
  final MockBank bank;
  final EventLog events;
  final Pathfinder pathfinder;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.services;

  static CaseController controllerOf(BuildContext context) => of(context).controller;

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.services != services;
}
