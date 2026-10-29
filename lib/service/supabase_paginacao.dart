import 'package:pole_price/utils/semana_custo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// O PostgREST (Supabase) limita cada resposta a 1000 linhas (max-rows).
/// Estes helpers evitam que consultas grandes sejam cortadas em silêncio.
const int kPaginaSupabase = 1000;

/// Executa [busca] página a página (com `.range(ini, fim)`) até esgotar.
/// A consulta DEVE ter `.order(...)` por coluna estável para a paginação
/// não repetir nem pular linhas.
///
/// Ex.: `paginar((a, b) => sb.from('t').select().order('id').range(a, b))`
Future<List<Map<String, dynamic>>> paginar(
  Future<dynamic> Function(int ini, int fim) busca,
) async {
  final todas = <Map<String, dynamic>>[];
  for (var ini = 0;; ini += kPaginaSupabase) {
    final res = await busca(ini, ini + kPaginaSupabase - 1);
    final lote = (res as List).cast<Map<String, dynamic>>();
    todas.addAll(lote);
    if (lote.length < kPaginaSupabase) break;
  }
  return todas;
}

/// Divide [chaves] em blocos (limite de tamanho da URL em `inFilter`) e
/// concatena o resultado de [busca] para cada bloco.
Future<List<Map<String, dynamic>>> emBlocos(
  List<String> chaves,
  Future<List<Map<String, dynamic>>> Function(List<String> parte) busca, {
  int tamanho = 150,
}) async {
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < chaves.length; i += tamanho) {
    final fim = i + tamanho > chaves.length ? chaves.length : i + tamanho;
    out.addAll(await busca(chaves.sublist(i, fim)));
  }
  return out;
}

/// Custo vigente de um produto: o da semana atual ou, na falta dele, o
/// último registrado antes dela.
class CustoVigente {
  final double? cpv;
  final double? dedPct;
  final double? dvPct;
  final String periodo; // AAAASS

  const CustoVigente({
    this.cpv,
    this.dedPct,
    this.dvPct,
    required this.periodo,
  });

  /// Semanas de defasagem em relação à semana atual (0 = em dia).
  int get semanasDeAtraso => SemanaCusto.semanasDeAtraso(periodo);
}

double? _num(dynamic v) => v == null ? null : double.tryParse(v.toString());

/// Para cada código em [codigos], o custo da semana atual ou, se não houver,
/// o mais recente já registrado (períodos futuros são ignorados e períodos
/// fora do padrão AAAASS, como 'MANUAL', também).
Future<Map<String, CustoVigente>> custosVigentes(
  SupabaseClient supabase,
  List<String> codigos,
) async {
  if (codigos.isEmpty) return {};
  final semanaAtual = SemanaCusto.atual();
  final rows = await emBlocos(
    codigos,
    (parte) => paginar((a, b) => supabase
        .from('product_costs')
        .select('product_code, cost_value, ded_pct, dv_pct, period')
        .inFilter('product_code', parte)
        .order('product_code')
        .order('period')
        .range(a, b)),
  );

  final melhor = <String, Map<String, dynamic>>{};
  for (final r in rows) {
    final code = r['product_code']?.toString();
    final periodo = r['period']?.toString();
    if (code == null || !SemanaCusto.valida(periodo)) continue;
    if (periodo!.compareTo(semanaAtual) > 0) continue; // semana futura
    final atual = melhor[code];
    if (atual == null || periodo.compareTo(atual['period'] as String) > 0) {
      melhor[code] = r;
    }
  }

  return {
    for (final e in melhor.entries)
      e.key: CustoVigente(
        cpv: _num(e.value['cost_value']),
        dedPct: _num(e.value['ded_pct']),
        dvPct: _num(e.value['dv_pct']),
        periodo: e.value['period'] as String,
      ),
  };
}

/// Período (AAAASS) mais recente já importado em `product_costs`, ignorando
/// formatos legados ('MANUAL', '2025.05'). Pagina em ordem decrescente e para
/// na primeira página que contiver um período válido (o primeiro válido é o
/// maior). `null` se não houver nenhum.
Future<String?> ultimoPeriodoCustos(SupabaseClient supabase) async {
  for (var ini = 0;; ini += kPaginaSupabase) {
    final res = await supabase
        .from('product_costs')
        .select('period')
        .order('period', ascending: false)
        .range(ini, ini + kPaginaSupabase - 1);
    final lote = (res as List).cast<Map<String, dynamic>>();
    String? melhor;
    for (final r in lote) {
      final p = r['period']?.toString();
      if (SemanaCusto.valida(p) && (melhor == null || p!.compareTo(melhor) > 0)) {
        melhor = p;
      }
    }
    if (melhor != null) return melhor;
    if (lote.length < kPaginaSupabase) return null;
  }
}
