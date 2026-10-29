/// Período semanal dos custos (CPV / Ded% / DV%) no formato `AAAASS`
/// (ano + semana ISO 8601, ex.: `202643` = semana 43 de 2026).
///
/// Por ter sempre 6 dígitos, a ordenação alfabética coincide com a
/// cronológica (`202643` > `202641`).
class SemanaCusto {
  SemanaCusto._();

  static final _formato = RegExp(r'^(\d{4})(\d{2})$');

  /// `true` se [periodo] é `AAAASS` com semana entre 01 e o total de semanas
  /// ISO daquele ano (52 ou 53).
  static bool valida(String? periodo) {
    if (periodo == null) return false;
    final m = _formato.firstMatch(periodo);
    if (m == null) return false;
    final ano = int.parse(m.group(1)!);
    final semana = int.parse(m.group(2)!);
    return semana >= 1 && semana <= _semanasNoAno(ano);
  }

  /// Converte o texto de uma célula para `AAAASS`, aceitando `202643`,
  /// `202643.0` (número do Excel), `2026-43`, `2026-S43` e `2026S43`.
  /// Devolve `null` se não for uma semana válida.
  static String? normalizar(String? texto) {
    if (texto == null) return null;
    var t = texto.trim().toUpperCase();
    if (t.endsWith('.0')) t = t.substring(0, t.length - 2);
    final m = RegExp(r'^(\d{4})[-/ ]?S?(\d{1,2})$').firstMatch(t);
    if (m == null) return null;
    final p = '${m.group(1)}${m.group(2)!.padLeft(2, '0')}';
    return valida(p) ? p : null;
  }

  /// Semana ISO da data [d] (padrão: hoje) no formato `AAAASS`.
  static String atual([DateTime? d]) {
    final data = d ?? DateTime.now();
    // A semana ISO pertence ao ano da quinta-feira daquela semana.
    final quinta = DateTime(data.year, data.month, data.day)
        .add(Duration(days: DateTime.thursday - data.weekday));
    final primeiroJan = DateTime(quinta.year, 1, 1);
    final semana = ((quinta.difference(primeiroJan).inDays) ~/ 7) + 1;
    return '${quinta.year}${semana.toString().padLeft(2, '0')}';
  }

  /// `202643` → `2026-S43`. Valores fora do padrão voltam como vieram.
  static String rotulo(String? periodo) {
    if (!valida(periodo)) return periodo ?? '—';
    return '${periodo!.substring(0, 4)}-S${periodo.substring(4)}';
  }

  /// Quantas semanas [periodo] está atrás de [referencia] (padrão: semana
  /// atual). 0 = em dia; valores negativos = período no futuro.
  static int semanasDeAtraso(String periodo, [String? referencia]) {
    final ref = referencia ?? atual();
    return (_segundaDaSemana(ref).difference(_segundaDaSemana(periodo)).inDays) ~/ 7;
  }

  // ── Internos ──────────────────────────────────────────────────────────────

  static int _semanasNoAno(int ano) {
    // O ano tem 53 semanas ISO se 1º/jan ou 31/dez caem numa quinta-feira.
    final jan1 = DateTime(ano, 1, 1).weekday;
    final dez31 = DateTime(ano, 12, 31).weekday;
    return (jan1 == DateTime.thursday || dez31 == DateTime.thursday) ? 53 : 52;
  }

  static DateTime _segundaDaSemana(String periodo) {
    final ano = int.parse(periodo.substring(0, 4));
    final semana = int.parse(periodo.substring(4));
    // 4/jan sempre está na semana 1 ISO.
    final quatroJan = DateTime(ano, 1, 4);
    final segundaSemana1 =
        quatroJan.subtract(Duration(days: quatroJan.weekday - DateTime.monday));
    return segundaSemana1.add(Duration(days: (semana - 1) * 7));
  }
}
