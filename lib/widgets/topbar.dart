/* import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:pole_price/models/regra_ajuste.dart';
import 'package:pole_price/widgets/tabela_precos.dart';

Widget _topBar() {
  return Container(
    height: 70,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    color: Colors.white,
    child: Row(
      children: [
        const Text(
          "Gestão de Preços",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const Spacer(),

        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B00),
          ),
          onPressed: controller.selecionada == null
              ? null
              : () async {
                  final confirm = await showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text("Confirmar"),
                      content: const Text("Salvar para aprovação?"),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text("Cancelar"),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text("Salvar"),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await controller.salvar();
                  }
                },
          child: const Text("Salvar para aprovação"),
        ),
      ],
    ),
  );
}

Widget _painelEsquerdo() {
  return Column(
    children: [
      DropdownButton(
        value: controller.selecionada,
        hint: const Text("Selecionar tabela"),
        items: controller.listas.map((l) {
          return DropdownMenuItem(value: l, child: Text(l.description));
        }).toList(),
        onChanged: (val) {
          if (val != null) {
            controller.selecionarLista(val);
          }
        },
      ),

      const SizedBox(height: 10),

      TextField(
        decoration: const InputDecoration(hintText: "Buscar material..."),
        onChanged: controller.buscar,
      ),

      const SizedBox(height: 10),

      Expanded(child: TabelaPrecos(controller: controller)),
    ],
  );
}

Widget _painelDireito() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _listasFilhas(),
      const SizedBox(height: 16),
      Expanded(child: _excecoes()),
    ],
  );
}

Widget _listasFilhas() {
  return Container(
    padding: const EdgeInsets.all(12),
    color: Colors.white,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Listas destino"),

        Wrap(
          spacing: 8,
          children: controller.targets.map((id) {
            return Chip(
              label: Text(id),
              onDeleted: () => controller.toggleTarget(id),
            );
          }).toList(),
        ),

        DropdownButton(
          hint: const Text("Adicionar lista"),
          items: controller.listas.map((l) {
            return DropdownMenuItem(value: l.id, child: Text(l.description));
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              controller.toggleTarget(val);
            }
          },
        ),
      ],
    ),
  );
}

Widget _excecoes() {
  String nivel = 'Tabela';
  String tipo = 'Percentual';
  final valorController = TextEditingController();

  return Container(
    padding: const EdgeInsets.all(12),
    color: Colors.white,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Exceções e ajustes"),

        DropdownButton(
          value: nivel,
          items: [
            'Tabela',
            'Grupo',
            'Material',
          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) {},
        ),

        DropdownButton(
          value: tipo,
          items: [
            'Percentual',
            'Fixo',
          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) {},
        ),

        TextField(
          controller: valorController,
          decoration: const InputDecoration(hintText: "Valor"),
        ),

        ElevatedButton(
          onPressed: () {
            final valor = double.tryParse(valorController.text) ?? 0;

            controller.addRegra(
              RegraAjuste(
                targetListId: controller.targets.isNotEmpty
                    ? controller.targets.first
                    : '',
                nivel: nivel,
                tipo: tipo,
                valor: valor,
              ),
            );
          },
          child: const Text("Adicionar"),
        ),

        const Divider(),

        Expanded(
          child: ListView(
            children: controller.regras.map((r) {
              return ListTile(
                title: Text("${r.nivel} - ${r.tipo}"),
                subtitle: Text("${r.valor}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => controller.removeRegra(r),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    ),
  );
}
 */