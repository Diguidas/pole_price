import 'package:flutter/material.dart';
import 'package:pole_price/controllers/background_task_controller.dart';
import 'package:pole_price/service/draft_pricing_service.dart';

/// Card flutuante no canto inferior direito mostrando tarefas em segundo
/// plano (ex.: publicação de preços no SAP). Fica visível em qualquer tela
/// via AppShell, permitindo o usuário navegar livremente enquanto a tarefa
/// roda. Ao concluir, vira clicável para mostrar o resultado detalhado.
class BackgroundTaskOverlay extends StatefulWidget {
  const BackgroundTaskOverlay({super.key});

  @override
  State<BackgroundTaskOverlay> createState() => _BackgroundTaskOverlayState();
}

class _BackgroundTaskOverlayState extends State<BackgroundTaskOverlay> {
  static const _laranja = Color(0xFFFF6B00);
  static const _verde = Color(0xFF047857);
  static const _vermelho = Color(0xFFB91C1C);
  static const _texto = Color(0xFF0F172A);
  static const _subtexto = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    BackgroundTaskController.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    BackgroundTaskController.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tasks = BackgroundTaskController.instance.tasks;
    if (tasks.isEmpty) return const SizedBox.shrink();

    return Positioned(
      right: 20,
      bottom: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: tasks.map(_buildCard).toList(),
      ),
    );
  }

  Widget _buildCard(BgTask task) {
    Color cor;
    String rotulo;
    IconData? icone;
    switch (task.status) {
      case BgTaskStatus.running:
        cor = _laranja;
        rotulo = 'Enviando…';
        icone = null;
        break;
      case BgTaskStatus.success:
        cor = _verde;
        rotulo = 'Concluído';
        icone = Icons.check_circle_rounded;
        break;
      case BgTaskStatus.error:
        cor = _vermelho;
        rotulo = 'Concluído com pendências';
        icone = Icons.error_rounded;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: task.status == BgTaskStatus.running
              ? null
              : () => _abrirResultado(task),
          child: Container(
            width: 300,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (task.status == BgTaskStatus.running)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: _laranja,
                    ),
                  )
                else
                  Icon(icone, size: 20, color: cor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _texto,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        task.status == BgTaskStatus.running
                            ? rotulo
                            : '$rotulo — toque para ver',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: task.status == BgTaskStatus.running
                              ? _subtexto
                              : cor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (task.status != BgTaskStatus.running)
                  InkWell(
                    onTap: () =>
                        BackgroundTaskController.instance.dismiss(task.id),
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: _subtexto,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _abrirResultado(BgTask task) {
    showDialog(context: context, builder: (_) => _ResultadoDialog(task: task));
  }
}

class _ResultadoDialog extends StatelessWidget {
  final BgTask task;
  const _ResultadoDialog({required this.task});

  @override
  Widget build(BuildContext context) {
    final erro = task.error;
    List<Map<String, dynamic>>? falhas;
    String? erroGenerico;
    int total = 0;

    if (erro is SapPushFalhasException) {
      falhas = erro.falhas;
      total = erro.total;
    } else if (erro != null) {
      erroGenerico = erro.toString();
    } else if (task.result is int) {
      total = task.result as int;
    }

    final sucesso = task.status == BgTaskStatus.success;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            sucesso ? Icons.check_circle_rounded : Icons.warning_rounded,
            color: sucesso
                ? const Color(0xFF047857)
                : const Color(0xFFB45309),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(task.title, style: const TextStyle(fontSize: 15)),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sucesso)
                Text(
                  'Publicado com sucesso.'
                  '${total > 0 ? ' $total item(ns) enviado(s) e confirmado(s) no SAP.' : ''}',
                )
              else if (falhas != null) ...[
                Text(
                  '${falhas.length} de $total material(is) não foram '
                  'confirmados no SAP:',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                ...falhas.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${f['matnr']}  —  ${f['erro']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'O rascunho continua pendente em Aprovações. Corrija o que '
                  'for necessário (ex.: vigência sobreposta no SAP) e tente '
                  'aprovar novamente — não é preciso recriar a lista.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ] else
                Text(erroGenerico ?? 'Ocorreu um erro desconhecido.'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
