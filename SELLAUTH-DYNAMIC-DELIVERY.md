# SellAuth Dynamic Delivery → KeyLedger

Cette intégration livre une clé depuis KeyLedger après le paiement SellAuth, puis crée l’attribution avec l’e-mail client et l’échéance correspondant à la variante achetée.

## 1. Déployer la fonction

Mets à jour le dépôt GitHub avec les nouveaux fichiers, puis laisse Netlify redéployer le site. La fonction sera disponible à :

```text
https://TON-SITE.netlify.app/.netlify/functions/sellauth-delivery
```

## 2. Ajouter le secret SellAuth à Netlify

Dans SellAuth : **Storefront → Configure → Miscellaneous**, copie le **Dynamic Delivery webhook secret**. Dans Netlify → **Environment variables**, crée :

```text
SELLAUTH_WEBHOOK_SECRET = le secret SellAuth
```

Sélectionne les scopes Functions / Production. Ce secret ne va jamais dans le navigateur, KeyLedger ou Discord.

## 3. Configurer les variantes dans Supabase

Dans Supabase SQL Editor, ajoute une ligne par variante SellAuth. Remplace les identifiants par les vrais `variant_id` visibles dans les événements SellAuth ou dans l’API SellAuth.

```sql
insert into public.sellauth_variant_mappings (variant_id, variant_name, license_type, duration_days) values
  ('VARIANT_ID_1_SEMAINE', '1 Semaine', '1 Semaine', 7),
  ('VARIANT_ID_1_MOIS', '1 Mois', '1 Mois', 30),
  ('VARIANT_ID_1_AN', '1 Ans', '1 An Pro', 365),
  ('VARIANT_ID_LIFETIME', 'Lifetime', 'Lifetime', null);
```

Le `license_type` doit correspondre exactement au type de clé dans l’inventaire KeyLedger. Une variante non configurée ou sans stock compatible reçoit une réponse « out of stock » ; aucune clé différente n’est substituée.

## 4. Configurer SellAuth

Pour chaque variante :

1. Active **Dynamic Delivery** dans la configuration produit/variante.
2. Mets l’URL de webhook Netlify ci-dessus.
3. Laisse le stock SellAuth en mode Dynamic Delivery (géré manuellement ou infini selon l’interface).
4. Conserve les instructions client dans **Override Instructions** : la fonction ne renvoie que la clé, SellAuth affiche les instructions séparément.

## Contrôles de sécurité

- La signature HMAC SellAuth est vérifiée avant toute attribution.
- Les tentatives SellAuth réutilisent le même livrable grâce à `unique_id` + `item_id`.
- Une clé attribuée passe à `assigned` ; elle ne peut pas être délivrée une seconde fois.
- L’e-mail, l’ID de facture, la variante et l’historique sont enregistrés dans Supabase / KeyLedger.
