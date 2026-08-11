import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/**
 * Payload esperado (montado pelo DraftPricingService.applyDraft):
 * {
 *   pltyp: string,
 *   items: [
 *     {
 *       MATNR:  string,
 *       KBETR:  number,
 *       KONWA:  string,   // moeda (ex: BRL)
 *       KMEIN:  string,   // unidade (ex: KG)
 *       KRECH:  string,   // regra de cálculo (ex: C)
 *       DATAB:  string,   // YYYYMMDD
 *       DATBI:  string,   // YYYYMMDD
 *       MXWRT:  number,   // valor inferior da faixa de preço (editável por material no Pole Price)
 *       GKWRT:  number,   // valor superior da faixa de preço (idem)
 *       STATUS: string,   // '' | 'L' | 'X' — igual para todos os itens do draft
 *     }
 *   ]
 * }
 *
 * O SAP recebe um objeto com PLTYP no topo e a lista de itens em ITEMS.
 * STATUS é repetido linha a linha conforme definido pelo usuário no draft.
 *
 * Resposta do SAP agora inclui "falhas": [{ matnr, erro }] — a BDC do lado
 * ABAP passou a checar mensagens de erro (E/A) após cada CALL TRANSACTION
 * e reporta por material quando a gravação não foi confirmada. Antes disso
 * o SAP sempre respondia {"ok":true} mesmo quando nada era gravado.
 */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const SAP_URL_RAW = Deno.env.get("SAP_URL")!;
    const SAP_URL = SAP_URL_RAW.replace(/\/[^\/]+$/, "/post_new_preco");
    const SAP_USER = Deno.env.get("SAP_USER")!;
    const SAP_PASS = Deno.env.get("SAP_PASS")!;

    if (!SAP_URL)  throw new Error("Secret SAP_URL não configurado");
    if (!SAP_USER) throw new Error("Secret SAP_USER não configurado");
    if (!SAP_PASS) throw new Error("Secret SAP_PASS não configurado");

    const body = await req.json();

    if (!body?.pltyp)              throw new Error("Campo 'pltyp' obrigatório");
    if (!Array.isArray(body.items) || body.items.length === 0)
                                   throw new Error("Campo 'items' obrigatório e não pode ser vazio");

    const basicAuth = btoa(`${SAP_USER}:${SAP_PASS}`);

    // ── CSRF token ────────────────────────────────────────────────────────
    const csrfRes = await fetch(SAP_URL, {
      method: "GET",
      headers: {
        "Authorization": `Basic ${basicAuth}`,
        "X-CSRF-Token":  "Fetch",
      },
    });

    const csrfToken = csrfRes.headers.get("x-csrf-token");
    const setCookies: string[] =
      typeof (csrfRes.headers as any).getSetCookie === "function"
        ? (csrfRes.headers as any).getSetCookie()
        : (csrfRes.headers.get("set-cookie") ?? "").split(/,(?=\s*\w+=)/).filter(Boolean);
    const cookieHeader = setCookies.map((c: string) => c.split(";")[0].trim()).join("; ");

    if (!csrfToken) {
      const text = await csrfRes.text();
      throw new Error(`SAP não retornou X-CSRF-Token. Status: ${csrfRes.status}. Body: ${text.slice(0, 300)}`);
    }

    // O SAP espera KBETR/MXWRT como string com vírgula decimal e 2 casas
    // (ex.: "140,06"). Number + JSON sempre usaria ponto, e ruído de ponto
    // flutuante (ex.: 140.06000000000004, comum após aplicar exceções de
    // preço) pode ser mal interpretado do outro lado — toFixed(2) arredonda
    // e normaliza antes de trocar o separador.
    const formatValor = (v: unknown) =>
      Number(v ?? 0).toFixed(2).replace(".", ",");

    // ── Monta payload SAP ─────────────────────────────────────────────────
    // Formato: action "post_new_preco", PLTYP no topo, ITEMS com cada linha
    const sapPayload = {
      action: "post_new_preco",
      PLTYP: body.pltyp,
      ITEMS: body.items.map((item: any) => ({
        MATNR:  String(item.MATNR  ?? "").trim(),
        KBETR:  formatValor(item.KBETR),
        KONWA:  String(item.KONWA  ?? "BRL").trim(),
        KMEIN:  String(item.KMEIN  ?? "KG").trim(),
        KRECH:  String(item.KRECH  ?? "C").trim(),
        DATAB:  String(item.DATAB  ?? "").trim(),
        DATBI:  String(item.DATBI  ?? "").trim(),
        MXWRT:  formatValor(item.MXWRT),
        GKWRT:  formatValor(item.GKWRT),
        STATUS: String(item.STATUS ?? "").trim(), // '' | 'L' | 'X'
      })),
    };

    // ── POST ao SAP ───────────────────────────────────────────────────────
    const sapRes = await fetch(SAP_URL, {
      method: "POST",
      headers: {
        "Authorization": `Basic ${basicAuth}`,
        "Content-Type":  "application/json",
        "X-CSRF-Token":  csrfToken,
        "Cookie":        cookieHeader,
      },
      body: JSON.stringify(sapPayload),
    });

    const sapBody = await sapRes.text();

    if (!sapRes.ok) {
      throw new Error(`SAP retornou erro ${sapRes.status}: ${sapBody.slice(0, 400)}`);
    }

    let sapResponse: any = {};
    try { sapResponse = JSON.parse(sapBody); } catch { /* SAP pode retornar vazio */ }

    // O ABAP agora reporta por material quando a BDC não confirma a gravação
    // (ex.: chave duplicada, pop-up de sobreposição de vigência, material
    // bloqueado). Repassamos essa lista no topo da resposta para o Pole
    // Price poder avisar o usuário quais materiais não foram atualizados.
    const falhas = Array.isArray(sapResponse?.falhas) ? sapResponse.falhas : [];

    return new Response(
      JSON.stringify({
        ok:    true,
        pltyp: body.pltyp,
        itens: body.items.length,
        falhas,
        sap:   sapResponse,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
    );

  } catch (err) {
    console.error("Erro em push-sap-prices:", err);
    return new Response(
      JSON.stringify({ ok: false, error: (err as Error).message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 },
    );
  }
});
