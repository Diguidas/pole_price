import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const SAP_URL = Deno.env.get("SAP_URL");
    const SAP_USER = Deno.env.get("SAP_USER");
    const SAP_PASS = Deno.env.get("SAP_PASS");
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!SAP_URL) throw new Error("Secret SAP_URL não configurado");
    if (!SAP_USER) throw new Error("Secret SAP_USER não configurado");
    if (!SAP_PASS) throw new Error("Secret SAP_PASS não configurado");

    const supabase = createClient(SUPABASE_URL!, SUPABASE_SERVICE_ROLE_KEY!);
    const basicAuth = btoa(`${SAP_USER}:${SAP_PASS}`);

    // ── Etapa 1: GET para obter CSRF token ──
    console.log("Buscando CSRF token em:", SAP_URL);
    const csrfRes = await fetch(SAP_URL, {
      method: "GET",
      headers: {
        "Authorization": `Basic ${basicAuth}`,
        "X-CSRF-Token": "Fetch",
      },
    });

    const csrfToken = csrfRes.headers.get("x-csrf-token");

    // getSetCookie() é o método correto no Deno para múltiplos Set-Cookie
    // headers.get("set-cookie") falha porque junta tudo numa string
    const setCookies: string[] =
      typeof (csrfRes.headers as any).getSetCookie === "function"
        ? (csrfRes.headers as any).getSetCookie()
        : (csrfRes.headers.get("set-cookie") ?? "")
            .split(/,(?=\s*\w+=)/)
            .filter(Boolean);

    const cookieHeader = setCookies
      .map((c: string) => c.split(";")[0].trim())
      .join("; ");

    console.log("CSRF GET status:", csrfRes.status);
    console.log("CSRF token:", csrfToken);
    console.log("Cookies:", cookieHeader.slice(0, 300));

    if (!csrfToken) {
      const body = await csrfRes.text();
      throw new Error(
        `SAP não retornou X-CSRF-Token. Status: ${csrfRes.status}. Body: ${body.slice(0, 300)}`
      );
    }

    // ── Etapa 2: POST com token + cookie da mesma sessão ──
    console.log("Enviando POST...");
    const dataRes = await fetch(SAP_URL, {
      method: "POST",
      headers: {
        "Authorization": `Basic ${basicAuth}`,
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Cookie": cookieHeader,
      },
      body: JSON.stringify({ envio_geral: "X" }),
    });

    const dataBody = await dataRes.text();
    console.log("SAP POST status:", dataRes.status);
    console.log("SAP POST body:", dataBody.slice(0, 500));

    if (!dataRes.ok) {
      throw new Error(
        `SAP POST falhou: ${dataRes.status} — ${dataBody.slice(0, 300)}`
      );
    }

    const sapData = JSON.parse(dataBody);

    if (!Array.isArray(sapData)) {
      throw new Error(
        `SAP retornou formato inesperado: ${JSON.stringify(sapData).slice(0, 200)}`
      );
    }

    // ── Etapa 3: upsert no Supabase ──
    let totalLists = 0;
    let totalMaterials = 0;

    for (const entry of sapData) {
      const h = entry.HEADER;

      await supabase.from("price_lists").upsert({
        id: h.ID.trim(),
        description: h.DESCRIPTION.trim(),
        created_at_sap: h.CREATED_AT.trim(),
        updated_at_sap: h.UPDATED_AT.trim(),
        currency: h.CURRENCY.trim(),
        total_items: parseInt(h.TOTAL_ITEMS.trim(), 10),
      });

      totalLists++;

      const materials = (entry.MATERIALS ?? []).map((m: any) => ({
        price_list_id: h.ID.trim(),
        product_id: m.PRODUCT_ID.trim(),
        description: m.DESCRIPTION_PRODUCT.trim(),
        price: parseFloat(m.PRICE.trim()),
        is_fixed: m.IS_FIXED.trim() === "1",
        can_give_discount: m.CAN_GIVE_DISCOUNT.trim() === "X",
        porcentagem: parseFloat(m.PORCENTAGEM.replace("%", "").trim()),
      }));

      if (materials.length > 0) {
        await supabase
          .from("materials")
          .upsert(materials, { onConflict: "price_list_id,product_id" });

        totalMaterials += materials.length;
      }
    }

    return new Response(
      JSON.stringify({
        ok: true,
        message: `Sync concluído: ${totalLists} listas, ${totalMaterials} materiais`,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      }
    );
  } catch (err) {
    console.error("Erro na get-price-lists:", err);
    return new Response(
      JSON.stringify({ ok: false, error: (err as Error).message }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 500,
      }
    );
  }
});