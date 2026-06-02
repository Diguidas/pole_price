import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/material_preco.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _laranja = Color(0xFFFF6B00);

/// Retorna a lista de [MaterialPreco] adicionados, ou null se cancelado.
/// Substitui o sheet antigo que retornava apenas um material por vez.
class BuscaMaterialSheet extends StatefulWidget {
  final PrecoController controller;
  const BuscaMaterialSheet({super.key, required this.controller});

  @override
  State<BuscaMaterialSheet> createState() => _BuscaMaterialSheetState();
}

class _BuscaMaterialSheetState extends State<BuscaMaterialSheet> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  // Resultados da busca (excluindo já adicionados à sessão)
  List<Map<String, dynamic>> _resultados = [];

  // Códigos selecionados pelo usuário nesta sessão do sheet
  final Set<String> _selecionados = {};

  bool _loading = false;
  bool _confirmando = false;
  String? _erro;

  // Conjunto de códigos já presentes no controller (ocultar da lista)
  late final Set<String> _jaAdicionados;

  @override
  void initState() {
    super.initState();
    _jaAdicionados = widget.controller.materiais
        .where((m) => !m.removido)
        .map((m) => m.codigo)
        .toSet();
    // Carrega lista inicial ao abrir
    WidgetsBinding.instance.addPostFrameCallback((_) => _buscar(''));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Busca ─────────────────────────────────────────────────────────────────

  Future<void> _buscar(String q) async {
    setState(() {
      _loading = true;
      _erro = null;
    });

    try {
      // Com query vazia: carrega os primeiros produtos (lista inicial)
      // Com query preenchida: filtra por código ou nome
      final query = _supabase
          .from('products')
          .select('code, name, pricing_cluster_id')
          .order('name')
          .limit(30);

      final productsRes = q.trim().isEmpty
          ? await query
          : await _supabase
              .from('products')
              .select('code, name, pricing_cluster_id')
              .or('code.ilike.%$q%,name.ilike.%$q%')
              .order('name')
              .limit(30);

      List<Map<String, dynamic>> resultados =
          List<Map<String, dynamic>>.from(productsRes as List);

      // Fallback: busca por matnr em price_list_items → cruza com products
      // (apenas quando há query; lista inicial não precisa disso)
      if (resultados.isEmpty && q.trim().isNotEmpty) {
        final itemsRes = await _supabase
            .from('price_list_items')
            .select('matnr')
            .ilike('matnr', '%$q%')
            .limit(30);

        final matnrs = (itemsRes as List)
            .map((r) => r['matnr'].toString())
            .toSet()
            .toList();

        if (matnrs.isNotEmpty) {
          final prodRes = await _supabase
              .from('products')
              .select('code, name, pricing_cluster_id')
              .inFilter('code', matnrs)
              .order('name');
          resultados = List<Map<String, dynamic>>.from(prodRes as List);

          // Para matnrs sem cadastro em products, cria entrada mínima
          final encontrados =
              resultados.map((r) => r['code'].toString()).toSet();
          for (final matnr in matnrs) {
            if (!encontrados.contains(matnr)) {
              resultados.add({
                'code': matnr,
                'name': matnr,
                'pricing_cluster_id': null,
              });
            }
          }
        }
      }

      // Remove os materiais já presentes na sessão atual
      resultados.removeWhere((p) => _jaAdicionados.contains(p['code']?.toString()));

      setState(() => _resultados = resultados);
    } catch (e) {
      setState(() => _erro = 'Erro ao buscar: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Toggle de seleção ─────────────────────────────────────────────────────

  void _toggle(String code) {
    setState(() {
      if (_selecionados.contains(code)) {
        _selecionados.remove(code);
      } else {
        _selecionados.add(code);
      }
    });
  }

  // ── Confirmar seleção múltipla ────────────────────────────────────────────

  Future<void> _confirmar() async {
    if (_selecionados.isEmpty) {
      Navigator.of(context).pop(<MaterialPreco>[]);
      return;
    }

    setState(() => _confirmando = true);

    try {
      // Busca produtos selecionados (para ter cluster_id e nome garantidos)
      final codigosList = _selecionados.toList();

      final prodRows = await _supabase
          .from('products')
          .select('code, name, pricing_cluster_id')
          .inFilter('code', codigosList);

      final Map<String, Map<String, dynamic>> prodMap = {
        for (final r in prodRows as List)
          r['code'].toString(): r as Map<String, dynamic>
      };

      // Busca CPV mais recente (período mais alto) em lote
      final periodRes = await _supabase
          .from('product_costs')
          .select('period')
          .order('period', ascending: false)
          .limit(1)
          .maybeSingle();

      final latestPeriod = periodRes?['period'] as String?;

      Map<String, double> cpvMap = {};
      if (latestPeriod != null) {
        final cpvRows = await _supabase
            .from('product_costs')
            .select('product_code, cost_value')
            .eq('period', latestPeriod)
            .inFilter('product_code', codigosList);

        for (final row in cpvRows as List) {
          final code = row['product_code']?.toString();
          final cost = (row['cost_value'] as num?)?.toDouble();
          if (code != null && cost != null) cpvMap[code] = cost;
        }
      }

      // Monta os MaterialPreco
      final materiais = codigosList.map((code) {
        final prod = prodMap[code];
        // Fallback para item sem cadastro em products (veio do matnr)
        final resultadoFallback =
            _resultados.firstWhere((r) => r['code'] == code, orElse: () => {});

        return MaterialPreco(
          codigo: code,
          description: prod?['name']?.toString() ??
              resultadoFallback['name']?.toString() ??
              code,
          precoAtual: 0,
          clusterId: prod?['pricing_cluster_id']?.toString(),
          cpv: cpvMap[code],
          datab: widget.controller.datab != null
              ? _fmtSap(widget.controller.datab!)
              : null,
          datbi: widget.controller.datbi != null
              ? _fmtSap(widget.controller.datbi!)
              : null,
          origemMaterial: OrigemMaterial.manual,
          bloqueado: false,
          inativo: false,
        );
      }).toList();

      if (mounted) Navigator.of(context).pop(materiais);
    } catch (e) {
      setState(() {
        _confirmando = false;
        _erro = 'Erro ao confirmar: $e';
      });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmtSap(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 520,
        height: 580,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildSearchBar(),
            _buildActionBar(),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            Expanded(child: _buildList()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _laranja.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: _laranja,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Adicionar materiais',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Text(
                'Busque por código ou descrição',
                style: TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Color(0xFF9E9E9E)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ── Campo de busca ────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Buscar por código ou descrição...',
          hintStyle:
              const TextStyle(fontSize: 13, color: Color(0xFFBDBDBD)),
          prefixIcon:
              const Icon(Icons.search, size: 18, color: Color(0xFF9E9E9E)),
          suffixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _laranja),
                  ),
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF8F8F8),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _laranja, width: 1.5),
          ),
        ),
        onChanged: _buscar,
      ),
    );
  }

  // ── Barra de ações (contador + selecionar todos) ──────────────────────────

  Widget _buildActionBar() {
    final todosVisiveis = _resultados.isNotEmpty &&
        _resultados.every((r) => _selecionados.contains(r['code']?.toString()));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Text(
            _resultados.isEmpty
                ? 'Nenhum resultado'
                : '${_resultados.length} resultado${_resultados.length != 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
          ),
          const Spacer(),
          if (_resultados.isNotEmpty)
            InkWell(
              onTap: () {
                setState(() {
                  if (todosVisiveis) {
                    for (final r in _resultados) {
                      _selecionados.remove(r['code']?.toString());
                    }
                  } else {
                    for (final r in _resultados) {
                      final code = r['code']?.toString();
                      if (code != null) _selecionados.add(code);
                    }
                  }
                });
              },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      todosVisiveis ? Icons.deselect : Icons.select_all,
                      size: 14,
                      color: _laranja,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      todosVisiveis ? 'Desmarcar todos' : 'Selecionar todos',
                      style: const TextStyle(
                        fontSize: 11,
                        color: _laranja,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Lista de resultados ───────────────────────────────────────────────────

  Widget _buildList() {
    if (_erro != null) {
      return Center(
        child: Text(_erro!, style: const TextStyle(color: Colors.red)),
      );
    }

    if (_resultados.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 32,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 8),
            Text(
              'Nenhum resultado encontrado',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _resultados.length,
      itemBuilder: (context, index) {
        final p = _resultados[index];
        final code = p['code']?.toString() ?? '';
        final name = p['name']?.toString() ?? '';
        final marcado = _selecionados.contains(code);

        return InkWell(
          onTap: () => _toggle(code),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: marcado ? _laranja.withOpacity(0.05) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: marcado
                    ? _laranja.withOpacity(0.2)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                // Checkbox animado
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: marcado ? _laranja : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: marcado ? _laranja : const Color(0xFFCCCCCC),
                      width: 1.5,
                    ),
                  ),
                  child: marcado
                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                // Badge do código
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: marcado
                        ? _laranja.withOpacity(0.1)
                        : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    code,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: marcado
                          ? _laranja
                          : const Color(0xFF616161),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Descrição
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          marcado ? FontWeight.w500 : FontWeight.w400,
                      color: marcado
                          ? const Color(0xFF212121)
                          : const Color(0xFF424242),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          if (_selecionados.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _laranja.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_selecionados.length} selecionado${_selecionados.length != 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _laranja,
                ),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed:
                _confirmando ? null : () => Navigator.pop(context, <MaterialPreco>[]),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF9E9E9E)),
            child: const Text('Cancelar', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _selecionados.isEmpty
                  ? const Color(0xFFE0E0E0)
                  : _laranja,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed:
                _confirmando || _selecionados.isEmpty ? null : _confirmar,
            child: _confirmando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Confirmar', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}