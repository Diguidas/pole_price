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
      const body = await csrfRes.text();
      throw new Error(`SAP não retornou X-CSRF-Token. Status: ${csrfRes.status}. Body: ${body.slice(0, 300)}`);
    }

    // ── POST action catalogo ─────────────────────────────────────────────
    const dataRes = await fetch(SAP_URL, {
      method: "POST",
      headers: {
        "Authorization": `Basic ${basicAuth}`,
        "Content-Type":  "application/json",
        "X-CSRF-Token":  csrfToken,
        "Cookie":        cookieHeader,
      },
      body: JSON.stringify({ action: "catalogo" }),
    });

    const dataBody = await dataRes.text();
    if (!dataRes.ok) {
      throw new Error(`SAP POST falhou: ${dataRes.status} — ${dataBody.slice(0, 300)}`);
    }

    const raw = JSON.parse(dataBody);

    // Loga estrutura para debug
    console.log("SAP catalogo — chaves raiz:", Object.keys(raw));
    console.log("Primeiro item listas:", JSON.stringify(
      (raw.listas ?? raw.Listas ?? raw.LISTAS ?? raw.price_lists ?? [])[0]
    ));
    console.log("Primeiro item grupos:", JSON.stringify(
      (raw.grupos ?? raw.Grupos ?? raw.GRUPOS ?? raw.price_groups ?? [])[0]
    ));

    // Normaliza — tenta as variações de chave mais comuns
    const rawListas: any[] = raw.listas ?? raw.Listas ?? raw.LISTAS ?? raw.price_lists ?? [];
    const rawGrupos: any[] = raw.grupos ?? raw.Grupos ?? raw.GRUPOS ?? raw.price_groups ?? [];

    if (!Array.isArray(rawListas) || !Array.isArray(rawGrupos)) {
      throw new Error(
        `SAP retornou estrutura inesperada. Chaves recebidas: ${Object.keys(raw).join(", ")}`
      );
    }

    // ── Normaliza campos de lista (case-insensitive) ─────────────────────
    const lists = rawListas
      .map((l: any) => {
        const pltyp = (l.pltyp ?? l.PLTYP ?? l.Pltyp ?? l.id ?? "")?.toString().trim();
        const ptext = (l.ptext ?? l.PTEXT ?? l.Ptext ?? l.description ?? l.desc ?? pltyp)?.toString().trim();
        return { pltyp, ptext };
      })
      .filter((l) => l.pltyp !== "");

    // ── Normaliza campos de grupo (case-insensitive) ─────────────────────
    const groups = rawGrupos
      .map((g: any) => {
        const kdgrp = (g.kdgrp ?? g.KDGRP ?? g.Kdgrp ?? g.id ?? "")?.toString().trim();
        const ktext = (g.ktext ?? g.KTEXT ?? g.Ktext ?? g.description ?? g.desc ?? kdgrp)?.toString().trim();
        return { kdgrp, ktext };
      })
      .filter((g) => g.kdgrp !== "");

    console.log(`Listas normalizadas: ${lists.length} | Grupos normalizados: ${groups.length}`);

    // ── Upsert price_lists ───────────────────────────────────────────────
    if (lists.length > 0) {
      const { error } = await supabase
        .from("price_lists")
        .upsert(lists, { onConflict: "pltyp" });
      if (error) throw new Error(`Erro ao salvar price_lists: ${error.message}`);
    }

    // ── Upsert price_groups ──────────────────────────────────────────────
    if (groups.length > 0) {
      const { error } = await supabase
        .from("price_groups")
        .upsert(groups, { onConflict: "kdgrp" });
      if (error) throw new Error(`Erro ao salvar price_groups: ${error.message}`);
    }

    return new Response(
      JSON.stringify({ ok: true, listas: lists.length, grupos: groups.length }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 },
    );

  } catch (err) {
    console.error("Erro na sync-price-catalog:", err);
    return new Response(
      JSON.stringify({ ok: false, error: (err as Error).message }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 },
    );
  }
});