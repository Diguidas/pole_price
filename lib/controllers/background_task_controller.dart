import 'package:flutter/foundation.dart';

enum BgTaskStatus { running, success, error }

class BgTask {
  final String id;
  final String title;
  BgTaskStatus status;
  dynamic result;
  Object? error;

  BgTask({required this.id, required this.title}) : status = BgTaskStatus.running;
}

/// Fila global de tarefas longas (ex.: publicar preços no SAP) que rodam em
/// segundo plano sem prender o usuário na tela que as disparou. O progresso
/// e o resultado ficam visíveis no card flutuante (BackgroundTaskOverlay),
/// que existe em todas as telas via AppShell.
class BackgroundTaskController extends ChangeNotifier {
  BackgroundTaskController._();
  static final BackgroundTaskController instance = BackgroundTaskController._();

  final List<BgTask> _tasks = [];
  List<BgTask> get tasks => List.unmodifiable(_tasks);

  /// Dispara [action] e retorna imediatamente — não espera a conclusão.
  /// Chame [addListener] para ser avisado quando o status mudar.
  BgTask run({
    required String id,
    required String title,
    required Future<dynamic> Function() action,
  }) {
    _tasks.removeWhere((t) => t.id == id);
    final task = BgTask(id: id, title: title);
    _tasks.add(task);
    notifyListeners();

    action().then((result) {
      task.status = BgTaskStatus.success;
      task.result = result;
      notifyListeners();
    }).catchError((err) {
      task.status = BgTaskStatus.error;
      task.error = err;
      notifyListeners();
    });

    return task;
  }

  void dismiss(String id) {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
  }
}
