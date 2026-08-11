-- Necessário para o botão "Limites SAP" (valor inferior/superior por material).
-- mxwrt (já existente) passa a ser o "valor inferior" digitado manualmente;
-- gkwrt (novo) é o "valor superior". Ambos NULL = enviados como 0,00 puro
-- ao SAP (sem fallback automático).
alter table public.price_draft_items
  add column if not exists gkwrt numeric;
