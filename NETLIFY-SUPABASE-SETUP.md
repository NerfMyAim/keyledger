# Mettre KeyLedger sur Netlify + Supabase

## Ce qui est déjà prêt dans ce dossier

- `supabase/schema.sql` : tables, statuts, permissions et attribution atomique ;
- `netlify/functions/ledger.mjs` : API serveur sécurisée ;
- `scripts/import-backup.mjs` : import de l’inventaire depuis une sauvegarde JSON ;
- `netlify.toml` et `.env.example` : structure Netlify.

## Déploiement

1. Crée un projet Supabase, puis exécute tout le contenu de `supabase/schema.sql` dans **SQL Editor**.
2. Active Supabase Auth (au minimum connexion par e-mail) et crée ton compte administrateur.
3. Dans le SQL Editor, exécute la ligne de promotion indiquée à la fin du schéma avec l’UUID de ton compte.
4. Dans Netlify, importe ce dossier depuis GitHub ou glisse-le dans le déploiement.
5. Ajoute dans **Site configuration > Environment variables** `SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY`, à partir de `.env.example`.
6. Exporte une sauvegarde JSON depuis KeyLedger. En local, installe les dépendances puis lance :

   ```bash
   npm install
   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npm run import:backup -- ./keyledger-backup-AAAA-MM-JJ.json
   ```

Ce script importe l’inventaire et l’historique des attributions. Il peut être relancé sans créer de doublons.

## Important

La fonction Netlify est prête, mais le tableau actuel reste volontairement en mode local tant que l’authentification Supabase du frontend n’est pas configurée. Cela évite d’exposer une clé serveur ou de rendre les clés publiques. La prochaine étape sera d’ajouter l’écran de connexion administrateur puis de connecter `app.js` à `/api/ledger`.

Ne mets jamais `SUPABASE_SERVICE_ROLE_KEY` ni un token Discord dans le JavaScript du navigateur.
