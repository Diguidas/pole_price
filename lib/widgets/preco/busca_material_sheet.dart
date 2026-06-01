import 'package:flutter/material.dart';
import 'package:pole_price/controllers/preco_controller.dart';
import 'package:pole_price/models/material_preco.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _laranja = Color(0xFFFF6B00);

class BuscaMaterialSheet extends StatefulWidget {
  final PrecoController controller;
  const BuscaMaterialSheet({super.key, required this.controller});

  @override
  State<BuscaMaterialSheet> createState() => _BuscaMaterialSheetState();
}

class _BuscaMaterialSheetState extends State<BuscaMaterialSheet> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _resultados = [];
  bool _loading = false;
  String? _erro;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _buscar(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _resultados = []);
      return;
    }

    setState(() {
      _loading = true;
      _erro = null;
    });

    try {
      final res = await _supabase
          .from('products')
          .select('code, name, pricing_cluster_id')
          .or('code.ilike.%$q%,name.ilike.%$q%')
          .order('name')
          .limit(30);

      setState(() => _resultados = List<Map<String, dynamic>>.from(res as List));
    } catch (e) {
      setState(() => _erro = 'Erro ao buscar: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _selecionar(Map<String, dynamic> product) async {
    // Busca CPV mais recente para o material
    double? cpv;
    try {
      final res = await _supabase
          .from('product_costs')
          .select('cost, period')
          .eq('product_id', product['code'])
          .order('period', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res != null) {
        cpv = (res['cost'] as num?)?.toDouble();
      }
    } catch (_) {
      // CPV não encontrado — continua sem ele
    }

    final material = MaterialPreco(
      codigo: product['code']?.toString() ?? '',
      description: product['name']?.toString() ?? '',
      precoAtual: 0,
      clusterId: product['pricing_cluster_id']?.toString(),
      cpv: cpv,
      datab: widget.controller.datab != null ? _fmtSap(widget.controller.datab!) : null,
      datbi: widget.controller.datbi != null ? _fmtSap(widget.controller.datbi!) : null,
      origemMaterial: OrigemMaterial.manual,
    );

    if (mounted) Navigator.of(context).pop(material);
  }

  String _fmtSap(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Título
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Adicionar material',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              // Campo de busca
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Buscar por código ou descrição...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: _buscar,
                ),
              ),

              const SizedBox(height: 8),

              // Resultados
              Expanded(
                child: _erro != null
                    ? Center(child: Text(_erro!, style: const TextStyle(color: Colors.red)))
                    : _resultados.isEmpty
                        ? Center(
                            child: Text(
                              _searchController.text.isEmpty
                                  ? 'Digite para buscar materiais'
                                  : 'Nenhum resultado encontrado',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: _resultados.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: Colors.grey.shade100),
                            itemBuilder: (_, i) {
                              final p = _resultados[i];
                              // Verifica se já está na lista
                              final jaAdicionado = widget.controller.materiais
                                  .any((m) => m.codigo == p['code'] && !m.removido);
                              return ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    p['code']?.toString() ?? '',
                                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                                  ),
                                ),
                                title: Text(
                                  p['name']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                trailing: jaAdicionado
                                    ? const Icon(Icons.check, color: Colors.green, size: 20)
                                    : const Icon(Icons.add_circle_outline,
                                        color: _laranja, size: 20),
                                onTap: jaAdicionado ? null : () => _selecionar(p),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}