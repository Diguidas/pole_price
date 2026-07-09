-- Histórico de PPC aprovado, por lista + material.
-- Alimenta o "PPC Atual" da tela de Gestão de Preços no ciclo seguinte.

create table if not exists public.ppc_historico (
  id uuid primary key default gen_random_uuid(),
  pltyp text not null,               -- lista de preço (price_lists.pltyp)
  product_code text not null,        -- material (products.code)
  ppc numeric not null,
  vigencia_datab text,               -- formato SAP YYYYMMDD
  vigencia_datbi text,
  draft_id uuid references public.price_drafts(id),
  aprovado_em timestamptz not null default now()
);

-- Um material só tem um PPC "vigente" por lista — upsert substitui o
-- registro anterior a cada nova aprovação.
alter table public.ppc_historico
  add constraint ppc_historico_pltyp_product_key unique (pltyp, product_code);

create index if not exists ppc_historico_pltyp_idx on public.ppc_historico (pltyp);
