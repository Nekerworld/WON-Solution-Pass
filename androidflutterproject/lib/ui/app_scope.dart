import 'package:flutter/widgets.dart';

import '../app/ai_agent.dart';
import '../app/app_controller.dart';
import '../data/bank_store.dart';
import '../data/key_value_storage.dart';
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
    required this.ai,
  });

  final AppController controller;
  final BankStore store;
  final MockBank bank;
  final EventLog events;
  final Pathfinder pathfinder;
  final AiAgent ai;
}

/// 의존성 조립. 백엔드·외부 LLM·실제 금융 API 없이 기기 안의 가상 은행과 모의 AI만 사용한다.
AppServices createServices(KeyValueStorage storage, {double latencyScale = 1, bool headless = false}) {
  final events = EventLog();
  final store = BankStore(events: events, storage: storage);
  final bank = MockBank(store: store, events: events, latencyScale: latencyScale);
  final pathfinder = Pathfinder(events: events);
  final ai = AiAgent(events: events, latencyScale: () => bank.latencyScale);
  final controller = AppController(
    store: store,
    bank: bank,
    events: events,
    pathfinder: pathfinder,
    ai: ai,
    storage: storage,
    headless: headless,
  );
  return AppServices(controller: controller, store: store, bank: bank, events: events, pathfinder: pathfinder, ai: ai);
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.services;

  static AppController controllerOf(BuildContext context) => of(context).controller;

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.services != services;
}
