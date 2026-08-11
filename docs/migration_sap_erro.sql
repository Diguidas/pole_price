-- Necessário para o recurso de "reprocessar apenas os materiais com falha".
-- Guarda, por item do draft, a mensagem de erro reportada pelo SAP quando a
-- BDC (post_new_preco) não confirma a gravação. NULL = confirmado/sem falha.
alter table public.price_draft_items
  add column if not exists sap_erro text;
