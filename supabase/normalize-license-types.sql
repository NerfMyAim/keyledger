-- Uniformise les libellés techniques de l'inventaire KeyLedger.
-- À exécuter une seule fois dans Supabase SQL Editor.
update public.inventory_keys
set license_type = case
  when lower(license_type) like '%lifetime%' then 'Lifetime'
  when lower(license_type) like '%annual%' or lower(license_type) like '%annuel%' or lower(license_type) like '%an pro%' then '1 An Pro'
  when lower(license_type) like '%monthly%' or lower(license_type) like '%mensuel%' or lower(license_type) like '%mois%' or lower(license_type) like '%month%' then '1 Mois'
  else license_type
end;

-- La livraison SellAuth mensuelle suit désormais le type unifié « 1 Mois ».
update public.sellauth_variant_mappings
set license_type = '1 Mois'
where variant_name = '1 Mois';

select license_type, state, count(*)
from public.inventory_keys
group by license_type, state
order by license_type, state;
