import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const SAP_URL  = Deno.env.get("SAP_URL")!;
    const SAP_USER = Deno.env.get("SAP_USER")!;
    const SAP_PASS = Deno.env.get("SAP_PASS")!;
    const SUPA_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPA_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    if (!SAP_URL)  throw new Error("Secret SAP_URL não configurado");
    if (!SAP_USER) throw new Error("Secret SAP_USER não configurado");
    if (!SAP_PASS) throw new Error("Secret SAP_PASS não configurado");

    const body = await req.json();
    if (!body?.pltyp) throw new Error("Campo 'pltyp' obrigatório no body");

    const supabase  = createClient(SUPA_URL, SUPA_KEY);
    const basicAuth = btoa(`${SAP_USER}:${SAP_PASS}`);

    // ── CSRF token ──────────────────────────────────────────────────────
    const csrfRes = await fetch(SAP_URL, {
      method: "GET",
      headers: { "Authorization": `Basic ${basicAuth}`, "X-CSRF-Token": "Fetch" },
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

    // ── Monta payload com operadores opcionais ───────────────────────────
    const sapPayload: Record<string, string> = {
      action: "lista",
      pltyp: body.pltyp,
    };

    if (body.datab) {
      sapPayload.datab    = body.datab;
      sapPayload.datab_op = body.datab_op ?? "GE";
    }
    if (body.datbi) {
      sapPayload.datbi    = body.datbi;
      sapPayload.datbi_op = body.datbi_op ?? "LE";
    }
 if (body.matnr)      sapPayload.matnr       = body.matnr;
if (body.kznep)    { sapPayload.kznep       = body.kznep;
                     sapPayload.kznep_op    = body.kznep_op ?? "EQ"; }
if (body.loevm_ko) { sapPayload.loevm_ko    = body.loevm_ko;
                     sapPayload.loevm_ko_op = body.loevm_ko_op ?? "EQ"; }

    // ── POST ao SAP ──────────────────────────────────────────────────────
    const dataRes = await fetch(SAP_URL, {
      method: "POST",
      headers: {
        "Authorization": `Basic ${basicAuth}`,
        "Content-Type":  "application/json",
        "X-CSRF-Token":  csrfToken,
        "Cookie":        cookieHeader,
      },
      body: JSON.stringify(sapPayload),
    });

    // ── Sem dados → retorna vazio sem erro ───────────────────────────────
    if (dataRes.status === 204 || dataRes.status === 404) {
      return new Response(
        JSON.stringify({ ok: true, semDados: true, listas: 0, itens: 0, data: [] }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    const dataBody = await dataRes.text();

    if (!dataRes.ok) {
      throw new Error(`SAP POST falhou: ${dataRes.status} — ${dataBody.slice(0, 300)}`);
    }

    let sapData: any[];
    try {
      const parsed = JSON.parse(dataBody);
      sapData = Array.isArray(parsed) ? parsed : (parsed?.data ?? []);
    } catch {
      throw new Error(`Resposta SAP não é JSON válido: ${dataBody.slice(0, 200)}`);
    }

    // Sem itens após parse → retorna vazio sem erro
    if (sapData.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, semDados: true, listas: 0, itens: 0, data: [] }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    // ── Persiste no Supabase ─────────────────────────────────────────────
    let totalItems = 0;

    for (const entry of sapData) {
      const materials: any[] = Array.isArray(entry.MATERIALS) ? entry.MATERIALS : [];
      if (materials.length === 0) continue;

      const rows = materials
        .filter((m) => m?.MATNR)
        .map((m) => ({
          pltyp:     entry.PLTYP?.trim()      ?? "",
          datab:     entry.DATAB?.trim()      ?? "",
          datbi:     entry.DATBI?.trim()      ?? "",
          matnr:     m.MATNR?.trim()          ?? "",
          knumt:     m.KNUMT?.trim()          ?? "",
          krech:     m.KRECH?.trim()          ?? "",
          kbetr:     parseFloat(m.KBETR)      || null,
          mxwrt:     parseFloat(m.MXWRT)      || null,
          konwa:     m.KONWA?.trim()          ?? "",
          kpein:     parseFloat(m.KPEIN)      || null,
          kmein:     m.KMEIN?.trim()          ?? "",
          kg_sug:    parseFloat(m.KG_SUG)     || null,
          kg_min:    parseFloat(m.KG_MIN)     || null,
          perc:      m.PERC?.trim()           ?? "",
          kznep:     m.KZNEP?.trim()          ?? "",
          loevm_ko:  m.LOEVM_KO?.trim()       ?? "",
          synced_at: new Date().toISOString(),
        }));

      if (rows.length === 0) continue;

      const { error } = await supabase
        .from("price_list_items")
        .upsert(rows, { onConflict: "pltyp,datab,datbi,matnr" });

      if (error) throw new Error(`Erro ao salvar price_list_items: ${error.message}`);
      totalItems += rows.length;
    }

    return new Response(
      JSON.stringify({ ok: true, semDados: false, listas: sapData.length, itens: totalItems, data: sapData }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
    );

  } catch (err) {
    console.error("Erro na swift-handler:", err);
    return new Response(
      JSON.stringify({ ok: false, error: (err as Error).message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 },
    );
  }
});