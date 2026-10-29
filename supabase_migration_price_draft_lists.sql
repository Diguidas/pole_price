-- Migração: vigência e status de envio ao SAP POR LISTA dentro de um rascunho.
--
-- Cada rascunho tem a lista mãe + N listas filhas (price_draft_targets). Esta
-- tabela guarda, para cada uma delas:
--   • a vigência (datab/datbi, formato SAP AAAAMMDD) que será enviada;
--   • o status: 'pending' (aguardando aprovação), 'sent' (enviada ao SAP) ou
--     'error' (enviada, mas o SAP não confirmou algum material).
-- Assim dá para aprovar/enviar só algumas listas e deixar as outras pendentes.
--
-- As linhas são criadas pelo app ao abrir o rascunho na tela de Aprovações
-- (vigência inicial = a do rascunho). Rascunhos antigos continuam funcionando.

create table if not exists public.price_draft_lists (
  draft_id      text        not null,
  pltyp         text        not null,
  is_master     boolean     not null default false,
  datab         text,
  datbi         text,
  status        text        not null default 'pending'
                            check (status in ('pending', 'sent', 'error')),
  sent_at       timestamptz,
  sent_by_email text,
  primary key (draft_id, pltyp)
);

create index if not exists price_draft_lists_draft_idx
  on public.price_draft_lists (draft_id);

-- Mesmo nível de acesso das demais tabelas de rascunho (ajuste se usar RLS
-- com políticas específicas).
alter table public.price_draft_lists enable row level security;

drop policy if exists "price_draft_lists_authenticated_all" on public.price_draft_lists;
create policy "price_draft_lists_authenticated_all"
  on public.price_draft_lists
  for all
  to authenticated
  using (true)
  with check (true);
