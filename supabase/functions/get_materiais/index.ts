// ============================================================
// Edge Function: sync-materials
// Localização: supabase/functions/sync-materials/index.ts
//
// Responsabilidade:
//   - Busca todos os materiais da API SAP (GET, Basic auth via secrets)
//   - Faz upsert na tabela materials do Supabase
//   - Preserva campos manuais (empresa, marca, gramatura, custos etc)
//   - Retorna resumo: inseridos, atualizados, erros
// ============================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// ------------------------------------
// Tipos
// ------------------------------------

interface SapMaterial {
  MATNR: string
  NOME: string
  UNIDADE_VENDA: string
  PESO_UNIDADE: string
  UNIDADE_PESO: string
  PESO_CAIXA: string
}

interface SapResponse {
  SUCCESS: boolean
  DATA: SapMaterial[]
  MESSAGE: string
}

interface MaterialRow {
  material_code: string
  description: string
  unidade_venda: string
  peso_unidade: number
  unidade_peso: string
  peso_caixa: number
  last_sap_sync_at: string
}

interface SyncResult {
  success: boolean
  total_from_sap: number
  upserted: number
  errors: string[]
  duration_ms: number
}

// ------------------------------------
// Helpers
// ------------------------------------

function parseDecimal(value: string): number {
  // SAP manda "0.700000 " com espaço no final
  return parseFloat(value.trim()) || 0
}

function cleanMatnr(matnr: string): string {
  // Remove zeros à esquerda do código do material
  return matnr.replace(/^0+/, '') || matnr
}

function mapSapToRow(mat: SapMaterial): MaterialRow {
  const pesoCaixa  = parseDecimal(mat.PESO_CAIXA)
  const pesoUnidade = parseDecimal(mat.PESO_UNIDADE)

  return {
    material_code:    cleanMatnr(mat.MATNR),
    description:      mat.NOME?.trim() ?? '',
    unidade_venda:    mat.UNIDADE_VENDA?.trim() ?? '',
    peso_unidade:     pesoUnidade,
    unidade_peso:     mat.UNIDADE_PESO?.trim() ?? 'KG',
    peso_caixa:       pesoCaixa,
    // fator_conversao é coluna GENERATED ALWAYS (calculada pelo banco)
    last_sap_sync_at: new Date().toISOString(),
  }
}

// ------------------------------------
// Handler principal
// ------------------------------------

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const startTime = Date.now()

  try {
    // Supabase client com service role (para upsert sem RLS)
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { persistSession: false } }
    )

    // ---- 1. Busca materiais no SAP ----
    console.log('[sync-materials] Buscando materiais no SAP...')

    const sapUrlRaw = Deno.env.get('SAP_URL')
    const sapUser = Deno.env.get('SAP_USER')
    const sapPass = Deno.env.get('SAP_PASS')
    if (!sapUrlRaw) throw new Error('Secret SAP_URL não configurado')
    if (!sapUser) throw new Error('Secret SAP_USER não configurado')
    if (!sapPass) throw new Error('Secret SAP_PASS não configurado')

    // Mesmo host das outras funções; só troca o último segmento do path
    const sapUrl = sapUrlRaw.replace(/\/[^\/]+$/, '/get_materiais')

    const sapResponse = await fetch(sapUrl, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Basic ${btoa(`${sapUser}:${sapPass}`)}`,
      },
      // Timeout de 30s para a chamada SAP
      signal: AbortSignal.timeout(30_000),
    })

    if (!sapResponse.ok) {
      throw new Error(
        `SAP retornou HTTP ${sapResponse.status}: ${await sapResponse.text()}`
      )
    }

    const sapData: SapResponse = await sapResponse.json()

    if (!sapData.SUCCESS) {
      throw new Error(`SAP reportou erro: ${sapData.MESSAGE}`)
    }

    const materiais = sapData.DATA
    console.log(`[sync-materials] ${materiais.length} materiais recebidos do SAP`)

    if (!materiais || materiais.length === 0) {
      const result: SyncResult = {
        success: true,
        total_from_sap: 0,
        upserted: 0,
        errors: [],
        duration_ms: Date.now() - startTime,
      }
      return new Response(JSON.stringify(result), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // ---- 2. Mapeia para o formato da tabela materials ----
    const rows: MaterialRow[] = materiais.map(mapSapToRow)

    // ---- 3. Upsert em lotes de 500 para não estourar o payload ----
    const BATCH_SIZE = 500
    const errors: string[] = []
    let upserted = 0

    for (let i = 0; i < rows.length; i += BATCH_SIZE) {
      const batch = rows.slice(i, i + BATCH_SIZE)

      const { error, count } = await supabase
        .from('materials')
        .upsert(batch, {
          onConflict: 'material_code',
          // Só atualiza os campos que vêm do SAP.
          // Campos manuais (empresa, marca, gramatura, categoria etc)
          // NÃO estão no batch então não são sobrescritos.
          ignoreDuplicates: false,
        })
        .select('material_code', { count: 'exact', head: true })

      if (error) {
        console.error(`[sync-materials] Erro no lote ${i}–${i + BATCH_SIZE}:`, error)
        errors.push(`Lote ${Math.floor(i / BATCH_SIZE) + 1}: ${error.message}`)
      } else {
        upserted += count ?? batch.length
        console.log(
          `[sync-materials] Lote ${Math.floor(i / BATCH_SIZE) + 1}: ${batch.length} registros processados`
        )
      }
    }

    // ---- 4. Retorna resumo ----
    const result: SyncResult = {
      success: errors.length === 0,
      total_from_sap: materiais.length,
      upserted,
      errors,
      duration_ms: Date.now() - startTime,
    }

    console.log('[sync-materials] Concluído:', result)

    return new Response(JSON.stringify(result), {
      status: errors.length > 0 ? 207 : 200, // 207 = partial success
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('[sync-materials] Erro fatal:', err)

    const result: SyncResult = {
      success: false,
      total_from_sap: 0,
      upserted: 0,
      errors: [err instanceof Error ? err.message : String(err)],
      duration_ms: Date.now() - startTime,
    }

    return new Response(JSON.stringify(result), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})