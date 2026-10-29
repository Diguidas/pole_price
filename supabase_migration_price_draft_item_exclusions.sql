-- Migração: escolher QUAIS listas filhas recebem cada material de um rascunho.
--
-- Por padrão todo material do rascunho vai para a lista mãe e para todas as
-- listas filhas (price_draft_targets). Esta tabela guarda só as EXCEÇÕES:
-- cada linha diz "o material X NÃO vai para a lista filha Y".
--   • sem linha  → o material vai para a lista (comportamento anterior);
--   • a lista mãe sempre recebe todos os materiais (não aparece aqui).
-- Rascunhos antigos não precisam de nenhum dado nesta tabela.

create table if not exists public.price_draft_item_exclusions (
  draft_id    text not null,
  pltyp       text not null,   -- lista filha que NÃO recebe o material
  product_id  text not null,
  primary key (draft_id, pltyp, product_id)
);

create index if not exists price_draft_item_exclusions_draft_idx
  on public.price_draft_item_exclusions (draft_id);

alter table public.price_draft_item_exclusions enable row level security;

drop policy if exists "price_draft_item_exclusions_authenticated_all"
  on public.price_draft_item_exclusions;
create policy "price_draft_item_exclusions_authenticated_all"
  on public.price_draft_item_exclusions
  for all
  to authenticated
  using (true)
  with check (true);
