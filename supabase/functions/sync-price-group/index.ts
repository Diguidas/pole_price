// Edge Function: sync-price-group
// Action SAP: "grupo" (A912)
// Popula: price_group_items
// Body esperado: { pltyp, kdgrp, datab?, datbi?, datab_op?, datbi_op?, matnr?, kznep? }
// ============================================================

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
    if (!body?.pltyp) throw new Error("Campo \'pltyp\' obrigatório no body");
    if (!body?.kdgrp) throw new Error("Campo \'kdgrp\' obrigatório no body");

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
        : (csrfRes.headers.get("set-cookie") ?? "").split(/,(?=\\s*\\w+=)/).filter(Boolean);
    const cookieHeader = setCookies.map((c: string) => c.split(";")[0].trim()).join("; ");

    if (!csrfToken) {
      const text = await csrfRes.text();
      throw new Error(`SAP não retornou X-CSRF-Token. Status: ${csrfRes.status}. Body: ${text.slice(0, 300)}`);
    }

    // ── Monta payload ────────────────────────────────────────────────────
    const sapPayload: Record<string, string> = {
      action: "grupo",
      pltyp:  body.pltyp,
      kdgrp:  body.kdgrp,
    };
    if (body.datab) {
      sapPayload.datab    = body.datab;
      sapPayload.datab_op = body.datab_op ?? "GE";
    }
    if (body.datbi) {
      sapPayload.datbi    = body.datbi;
      sapPayload.datbi_op = body.datbi_op ?? "LE";
    }
    if (body.matnr) sapPayload.matnr = body.matnr;
    if (body.kznep) sapPayload.kznep = body.kznep;

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

    if (dataRes.status === 204) {
      return new Response(
        JSON.stringify({ ok: true, semDados: true, grupos: 0, itens: 0 }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    const dataBody = await dataRes.text();
    if (!dataRes.ok) throw new Error(`SAP POST falhou: ${dataRes.status} — ${dataBody.slice(0, 300)}`);

    let sapData: any[];
    try {
      const parsed = JSON.parse(dataBody);
      sapData = Array.isArray(parsed) ? parsed : (parsed?.data ?? []);
    } catch {
      throw new Error(`Resposta SAP não é JSON válido: ${dataBody.slice(0, 200)}`);
    }

    if (sapData.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, semDados: true, grupos: 0, itens: 0 }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    // ── Persiste no Supabase ─────────────────────────────────────────────
    // O SAP pode retornar chaves em MAIÚSCULAS ou minúsculas — tratamos os dois casos
    // com o helper str() abaixo, igual ao que sync-price-list já faz.
    const str  = (v: any) => (v ?? "").toString().trim();
    const num  = (v: any) => parseFloat(str(v)) || null;

    let totalItems = 0;

    for (const entry of sapData) {
      // Aceita MATERIALS (maiúsculo) ou materials (minúsculo)
      const materials: any[] = Array.isArray(entry.MATERIALS)
        ? entry.MATERIALS
        : Array.isArray(entry.materials)
          ? entry.materials
          : [];

      if (materials.length === 0) continue;

      // Aceita PLTYP/KDGRP/DATAB/DATBI ou pltyp/kdgrp/datab/datbi
      const pltyp = str(entry.PLTYP ?? entry.pltyp);
      const kdgrp = str(entry.KDGRP ?? entry.kdgrp);
      const datab = str(entry.DATAB ?? entry.datab);
      const datbi = str(entry.DATBI ?? entry.datbi);

      const rows = materials
        .filter((m: any) => str(m.MATNR ?? m.matnr))
        .map((m: any) => ({
          pltyp,
          kdgrp,
          datab,
          datbi,
          matnr:    str(m.MATNR    ?? m.matnr),
          knumt:    str(m.KNUMT    ?? m.knumt),
          krech:    str(m.KRECH    ?? m.krech),
          kbetr:    num(m.KBETR    ?? m.kbetr),
          mxwrt:    num(m.MXWRT    ?? m.mxwrt),
          konwa:    str(m.KONWA    ?? m.konwa),
          kpein:    num(m.KPEIN    ?? m.kpein),
          kmein:    str(m.KMEIN    ?? m.kmein),
          kg_sug:   num(m.KG_SUG   ?? m.kg_sug),
          kg_min:   num(m.KG_MIN   ?? m.kg_min),
          perc:     str(m.PERC     ?? m.perc),
          kznep:    str(m.KZNEP    ?? m.kznep),
          loevm_ko: str(m.LOEVM_KO ?? m.loevm_ko),
          synced_at: new Date().toISOString(),
        }));

      if (rows.length === 0) continue;

      const { error } = await supabase
        .from("price_group_items")
        .upsert(rows, { onConflict: "pltyp,kdgrp,datab,datbi,matnr" });

      if (error) throw new Error(`Erro ao salvar price_group_items: ${error.message}`);
      totalItems += rows.length;
    }

    return new Response(
      JSON.stringify({ ok: true, semDados: false, grupos: sapData.length, itens: totalItems, data: sapData, }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
    );
  } catch (err) {
    console.error("Erro na sync-price-group:", err);
    return new Response(
      JSON.stringify({ ok: true, semDados: true, grupos: 0, itens: 0, data: [] }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 },
    );
  }
});