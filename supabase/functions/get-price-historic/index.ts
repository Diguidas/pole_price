// supabase/functions/get-price-historic/index.ts

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

    if (!SAP_URL)  throw new Error("Secret SAP_URL não configurado");
    if (!SAP_USER) throw new Error("Secret SAP_USER não configurado");
    if (!SAP_PASS) throw new Error("Secret SAP_PASS não configurado");

    const body = await req.json();

    // ── Validação mínima ─────────────────────────────────────────────────────
    // Aceita: body.matnr (string) OU body.materials (array de { matnr })
    const hasSingleMatnr = typeof body?.matnr === "string" && body.matnr.trim() !== "";
    const hasMateriaisList =
      Array.isArray(body?.materials) && body.materials.length > 0;

    if (!hasSingleMatnr && !hasMateriaisList) {
      throw new Error(
        "Informe 'matnr' (string) ou 'materials' (array de { matnr }) no body."
      );
    }

    const basicAuth = btoa(`${SAP_USER}:${SAP_PASS}`);

    // ── CSRF token ───────────────────────────────────────────────────────────
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
      throw new Error(
        `SAP não retornou X-CSRF-Token. Status: ${csrfRes.status}. Body: ${text.slice(0, 300)}`
      );
    }

    // ── Monta payload SAP ────────────────────────────────────────────────────
    const sapPayload: Record = {
      action: "historico",
    };

    // Datas com operadores (mesmo padrão de get-price-lists)
    if (body.datab) {
      sapPayload.datab    = body.datab;
      sapPayload.datab_op = body.datab_op ?? "GE";
    }
    if (body.datbi) {
      sapPayload.datbi    = body.datbi;
      sapPayload.datbi_op = body.datbi_op ?? "LE";
    }

    // Materiais: normaliza para sempre enviar o array ao SAP
    if (hasSingleMatnr) {
      sapPayload.materials = [{ matnr: body.matnr.trim() }];
    } else {
      sapPayload.materials = (body.materials as Array)
        .filter((m) => m?.matnr?.trim())
        .map((m) => ({ matnr: m.matnr.trim() }));
    }

    if ((sapPayload.materials as unknown[]).length === 0) {
      throw new Error("Nenhum código de material válido informado.");
    }

    // ── POST ao SAP ──────────────────────────────────────────────────────────
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

    // Sem dados → retorna vazio sem erro (mesmo padrão de get-price-lists)
    if (dataRes.status === 204 || dataRes.status === 404) {
      return new Response(
        JSON.stringify({ ok: true, semDados: true, data: [] }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    const dataBody = await dataRes.text();

    if (!dataRes.ok) {
      throw new Error(`SAP POST falhou: ${dataRes.status} — ${dataBody.slice(0, 300)}`);
    }

    let sapData: unknown[];
    try {
      const parsed = JSON.parse(dataBody);
      sapData = Array.isArray(parsed) ? parsed : (parsed?.data ?? []);
    } catch {
      throw new Error(`Resposta SAP não é JSON válido: ${dataBody.slice(0, 200)}`);
    }

    if (sapData.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, semDados: true, data: [] }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
      );
    }

    // ── Retorna dados ao cliente (sem persistir — igual ao padrão ao vivo) ───
    return new Response(
      JSON.stringify({ ok: true, semDados: false, data: sapData }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
    );

  } catch (err) {
    console.error("Erro na get-price-historic:", err);
    return new Response(
      JSON.stringify({ ok: false, error: (err as Error).message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 },
    );
  }
});
