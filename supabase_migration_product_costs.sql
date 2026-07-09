-- Migração: product_costs passa a suportar CPV + Ded% + DV% via import de planilha
-- Chave de upsert: (product_code, period)

-- 1. Novas colunas
alter table public.product_costs
  add column if not exists ded_pct numeric,
  add column if not exists dv_pct numeric;

-- 2. Garante a constraint única usada pelo upsert (product_code, period)
--    Necessário para o "on_conflict" do processarUploadCustos funcionar.
alter table public.product_costs
  add constraint product_costs_code_period_key unique (product_code, period);
