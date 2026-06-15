import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/material_preco.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _laranja = Color(0xFFFF6B00);

/// Retorna a lista de [MaterialPreco] adicionados, ou null se cancelado.
class BuscaMaterialSheet extends StatefulWidget {
  final PrecoController controller;
  const BuscaMaterialSheet({super.key, required this.controller});

  @override
  State<BuscaMaterialSheet> createState() => _BuscaMaterialSheetState();
}

class _BuscaMaterialSheetState extends State<BuscaMaterialSheet> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  // ── Modo: material ou grupo ───────────────────────────────────────────────
  bool _modoGrupo = false;

  // ── Estado modo material ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _resultados = [];

  // ── Estado modo grupo ─────────────────────────────────────────────────────
  List<Map<String, dynamic>> _grupos = [];
  // clusterId → lista de produtos
  final Map<String, List<Map<String, dynamic>>> _materiaisPorGrupo = {};
  // quais grupos estão expandidos
  final Set<String> _expandidos = {};
  bool _loadingGrupos = false;

  // ── Compartilhado ─────────────────────────────────────────────────────────
  final Set<String> _selecionados = {};
  bool _loading = false;
  bool _confirmando = false;
  String? _erro;
  late final Set<String> _jaAdicionados;

  @override
  void initState() {
    super.initState();
    _jaAdicionados = widget.controller.materiais
        .where((m) => !m.removido)
        .map((m) => m.codigo)
        .toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) => _buscar(''));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Busca modo material ───────────────────────────────────────────────────

  Future<void> _buscar(String q) async {
    setState(() {
      _loading = true;
      _erro = null;
    });

    try {
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

      resultados.removeWhere(
          (p) => _jaAdicionados.contains(p['code']?.toString()));

      setState(() => _resultados = resultados);
    } catch (e) {
      setState(() => _erro = 'Erro ao buscar: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Busca modo grupo ──────────────────────────────────────────────────────

  Future<void> _carregarGrupos() async {
    if (_grupos.isNotEmpty) return;
    setState(() => _loadingGrupos = true);
    try {
      final res = await _supabase
          .from('pricing_clusters')
          .select('id, name')
          .order('name');
      setState(() => _grupos = List<Map<String, dynamic>>.from(res as List));
    } catch (e) {
      setState(() => _erro = 'Erro ao carregar grupos: $e');
    } finally {
      setState(() => _loadingGrupos = false);
    }
  }

  Future<void> _expandirGrupo(String clusterId) async {
    if (_materiaisPorGrupo.containsKey(clusterId)) {
      setState(() {
        if (_expandidos.contains(clusterId)) {
          _expandidos.remove(clusterId);
        } else {
          _expandidos.add(clusterId);
        }
      });
      return;
    }

    setState(() => _expandidos.add(clusterId));

    try {
      final res = await _supabase
          .from('products')
          .select('code, name, pricing_cluster_id')
          .eq('pricing_cluster_id', clusterId)
          .order('name');

      final materiais = List<Map<String, dynamic>>.from(res as List)
          .where((p) => !_jaAdicionados.contains(p['code']?.toString()))
          .toList();

      setState(() => _materiaisPorGrupo[clusterId] = materiais);
    } catch (e) {
      setState(() {
        _erro = 'Erro ao carregar materiais do grupo: $e';
        _expandidos.remove(clusterId);
      });
    }
  }

  // ── Seleção por grupo (todos os materiais do grupo) ───────────────────────

  void _toggleGrupo(String clusterId) {
    final materiais = _materiaisPorGrupo[clusterId] ?? [];
    if (materiais.isEmpty) return;

    final codigos = materiais.map((m) => m['code'].toString()).toSet();
    final todosMarcados = codigos.every(_selecionados.contains);

    setState(() {
      if (todosMarcados) {
        _selecionados.removeAll(codigos);
      } else {
        _selecionados.addAll(codigos);
      }
    });
  }

  bool _grupoTodosMarcado(String clusterId) {
    final materiais = _materiaisPorGrupo[clusterId] ?? [];
    if (materiais.isEmpty) return false;
    return materiais
        .map((m) => m['code'].toString())
        .every(_selecionados.contains);
  }

  bool _grupoAlgumMarcado(String clusterId) {
    final materiais = _materiaisPorGrupo[clusterId] ?? [];
    return materiais
        .map((m) => m['code'].toString())
        .any(_selecionados.contains);
  }

  // ── Toggle individual ─────────────────────────────────────────────────────

  void _toggle(String code) {
    setState(() {
      if (_selecionados.contains(code)) {
        _selecionados.remove(code);
      } else {
        _selecionados.add(code);
      }
    });
  }

  // ── Confirmar ─────────────────────────────────────────────────────────────

  Future<void> _confirmar() async {
    if (_selecionados.isEmpty) {
      Navigator.of(context).pop(<MaterialPreco>[]);
      return;
    }

    setState(() => _confirmando = true);

    try {
      final codigosList = _selecionados.toList();

      final prodRows = await _supabase
          .from('products')
          .select('code, name, pricing_cluster_id')
          .inFilter('code', codigosList);

      final Map<String, Map<String, dynamic>> prodMap = {
        for (final r in prodRows as List)
          r['code'].toString(): r as Map<String, dynamic>
      };

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

      final materiais = codigosList.map((code) {
        final prod = prodMap[code];
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
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildToggle(),
            if (!_modoGrupo) _buildSearchBar(),
            if (!_modoGrupo) _buildActionBar(),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            Expanded(
              child: _modoGrupo ? _buildListaGrupos() : _buildListaMateriais(),
            ),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Adicionar materiais',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Text(
                _modoGrupo
                    ? 'Selecione um grupo para ver seus materiais'
                    : 'Busque por código ou descrição',
                style:
                    const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
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

  // ── Toggle Material / Grupo ───────────────────────────────────────────────

  Widget _buildToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _toggleBtn(
              label: 'Por material',
              icon: Icons.inventory_2_outlined,
              ativo: !_modoGrupo,
              onTap: () {
                if (_modoGrupo) {
                  setState(() => _modoGrupo = false);
                  _searchController.clear();
                  _buscar('');
                }
              },
            ),
            _toggleBtn(
              label: 'Por grupo',
              icon: Icons.account_tree_outlined,
              ativo: _modoGrupo,
              onTap: () {
                if (!_modoGrupo) {
                  setState(() => _modoGrupo = true);
                  _carregarGrupos();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleBtn({
    required String label,
    required IconData icon,
    required bool ativo,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: ativo ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: ativo
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: ativo ? _laranja : const Color(0xFF9E9E9E),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      ativo ? FontWeight.w600 : FontWeight.w400,
                  color: ativo ? _laranja : const Color(0xFF9E9E9E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Campo de busca (modo material) ────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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

  // ── Barra de ações (modo material) ────────────────────────────────────────

  Widget _buildActionBar() {
    final todosVisiveis = _resultados.isNotEmpty &&
        _resultados
            .every((r) => _selecionados.contains(r['code']?.toString()));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Text(
            _resultados.isEmpty
                ? 'Nenhum resultado'
                : '${_resultados.length} resultado${_resultados.length != 1 ? 's' : ''}',
            style:
                const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
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

  // ── Lista modo material ───────────────────────────────────────────────────

  Widget _buildListaMateriais() {
    if (_erro != null) {
      return Center(
          child: Text(_erro!, style: const TextStyle(color: Colors.red)));
    }
    if (_resultados.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 32, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Nenhum resultado encontrado',
                style:
                    TextStyle(fontSize: 13, color: Colors.grey.shade400)),
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
        return _materialTile(
            code: code, name: name, marcado: marcado, onTap: () => _toggle(code));
      },
    );
  }

  // ── Lista modo grupo ──────────────────────────────────────────────────────

  Widget _buildListaGrupos() {
    if (_erro != null) {
      return Center(
          child: Text(_erro!, style: const TextStyle(color: Colors.red)));
    }
    if (_loadingGrupos) {
      return const Center(child: CircularProgressIndicator(color: _laranja));
    }
    if (_grupos.isEmpty) {
      return Center(
        child: Text('Nenhum grupo encontrado',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _grupos.length,
      itemBuilder: (context, index) {
        final grupo = _grupos[index];
        final clusterId = grupo['id'].toString();
        final nome = grupo['name']?.toString() ?? clusterId;
        final expandido = _expandidos.contains(clusterId);
        final materiais = _materiaisPorGrupo[clusterId];
        final todosMarcado = _grupoTodosMarcado(clusterId);
        final algumMarcado = _grupoAlgumMarcado(clusterId);
        final qtdSelecionados = materiais
                ?.where((m) => _selecionados.contains(m['code'].toString()))
                .length ??
            0;

        return Column(
          children: [
            // ── Linha do grupo ──────────────────────────────────────
            InkWell(
              onTap: () => _expandirGrupo(clusterId),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: algumMarcado
                      ? _laranja.withOpacity(0.04)
                      : const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: algumMarcado
                        ? _laranja.withOpacity(0.15)
                        : const Color(0xFFEEEEEE),
                  ),
                ),
                child: Row(
                  children: [
                    // Checkbox do grupo
                    GestureDetector(
                      onTap: materiais != null
                          ? () => _toggleGrupo(clusterId)
                          : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: todosMarcado
                              ? _laranja
                              : algumMarcado
                                  ? _laranja.withOpacity(0.3)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: algumMarcado
                                ? _laranja
                                : const Color(0xFFCCCCCC),
                            width: 1.5,
                          ),
                        ),
                        child: todosMarcado
                            ? const Icon(Icons.check,
                                size: 12, color: Colors.white)
                            : algumMarcado
                                ? const Icon(Icons.remove,
                                    size: 12, color: Colors.white)
                                : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Ícone grupo
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: _laranja.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.account_tree_outlined,
                          size: 13, color: _laranja),
                    ),
                    const SizedBox(width: 10),
                    // Nome
                    Expanded(
                      child: Text(
                        nome,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: algumMarcado
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: algumMarcado
                              ? const Color(0xFF212121)
                              : const Color(0xFF424242),
                        ),
                      ),
                    ),
                    // Badge qtd selecionados
                    if (qtdSelecionados > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _laranja,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$qtdSelecionados',
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    // Seta expand
                    AnimatedRotation(
                      turns: expandido ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.chevron_right,
                          size: 16, color: Color(0xFFBBBBBB)),
                    ),
                  ],
                ),
              ),
            ),

            // ── Materiais do grupo (expandido) ──────────────────────
            if (expandido) ...[
              if (materiais == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _laranja),
                    ),
                  ),
                )
              else if (materiais.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 40, top: 4, bottom: 4),
                  child: Text('Nenhum material disponível',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade400)),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Column(
                    children: materiais.map((m) {
                      final code = m['code'].toString();
                      final name = m['name']?.toString() ?? '';
                      final marcado = _selecionados.contains(code);
                      return _materialTile(
                        code: code,
                        name: name,
                        marcado: marcado,
                        onTap: () => _toggle(code),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  // ── Tile de material (compartilhado) ──────────────────────────────────────

  Widget _materialTile({
    required String code,
    required String name,
    required bool marcado,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color:
              marcado ? _laranja.withOpacity(0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: marcado
                ? _laranja.withOpacity(0.2)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: marcado ? _laranja : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color:
                      marcado ? _laranja : const Color(0xFFCCCCCC),
                  width: 1.5,
                ),
              ),
              child: marcado
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                  color:
                      marcado ? _laranja : const Color(0xFF616161),
                ),
              ),
            ),
            const SizedBox(width: 10),
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
            onPressed: _confirmando
                ? null
                : () => Navigator.pop(context, <MaterialPreco>[]),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF9E9E9E)),
            child:
                const Text('Cancelar', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _selecionados.isEmpty ? const Color(0xFFE0E0E0) : _laranja,
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
                : const Text('Confirmar',
                    style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}