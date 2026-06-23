# Tutoriel simple : relier KeyLedger à Discord

L’objectif final est simple : tu exécutes une commande dans Discord, par exemple `/attribuer`, et le bot inscrit automatiquement le client et la clé dans KeyLedger.

Aujourd’hui, KeyLedger est local : il garde ses données dans ton navigateur. C’est pratique pour démarrer, mais un bot Discord ne peut pas écrire dans ce navigateur. Il faut donc ajouter une base de données partagée avant de connecter le bot.

## Les 3 morceaux à avoir

1. **KeyLedger sur Netlify** : le site que tu consultes.
2. **Supabase** : la base de données qui conserve le stock et les attributions, accessible à la fois par le site et le bot.
3. **Le bot Discord** : il reçoit la commande, demande une clé libre à la base, puis crée l’attribution.

## Étape 1 — mettre le site en ligne

1. Crée un compte Netlify.
2. Dépose le contenu du dossier `keyledger` sur Netlify (ou connecte-le plus tard à GitHub).
3. Ouvre l’URL générée par Netlify.

À ce stade, les données restent encore locales. Continue à faire une sauvegarde JSON depuis KeyLedger.

## Étape 2 — créer la base partagée

1. Crée un projet Supabase.
2. Crée deux tables :
   - `keys` : `id`, `key`, `type`, `state` (`available`, `assigned`, `review`), `created_at`.
   - `assignments` : `id`, `key_id`, `discord_id`, `discord_name`, `email`, `assigned_at`, `ends_at`, `status`, `notes`.
3. Importe le stock et les attributions actuelles dans ces tables.
4. Règle les permissions : le site ne doit voir que les données de ton compte, et seule une fonction serveur peut attribuer une clé.

Une fois cette étape faite, on modifiera KeyLedger pour lire et écrire dans Supabase à la place du stockage local.

## Étape 3 — créer l’application Discord

1. Va dans le portail développeur Discord et crée une **New Application**.
2. Dans l’onglet **Bot**, crée le bot et garde son token privé.
3. Dans **OAuth2 / URL Generator**, coche `bot` et `applications.commands`, puis ajoute le bot à ton serveur.
4. Ne colle jamais le token dans le site, dans un fichier public ou dans Discord. Il doit rester dans les variables secrètes de l’hébergeur du bot.

## Étape 4 — la commande à prévoir

Le bot peut commencer avec une seule commande :

```text
/attribuer client:@pseudo email:client@email.com echeance:2026-07-01 ticket:1234
```

Le comportement attendu :

1. Vérifier que la personne qui lance la commande possède le rôle revendeur.
2. Chercher une clé dont `state = available`.
3. Créer une ligne dans `assignments` avec l’ID Discord du client.
4. Passer la clé à `assigned` dans la même opération.
5. Répondre au revendeur avec la clé par message éphémère, afin qu’elle ne soit pas exposée dans le salon.
6. KeyLedger affiche immédiatement « Attribuée » et le pseudo du client.

Le bot ne doit jamais attribuer une clé déjà marquée `assigned` ou `review`.

## Ce que j’aurai besoin de savoir pour le construire avec toi

- le serveur Discord ciblé ;
- le rôle Discord autorisé à distribuer les clés ;
- si le bot doit répondre dans un ticket précis ou en message privé ;
- le format que tu veux pour la commande ;
- le compte Netlify et le projet Supabase créés (sans jamais m’envoyer de token dans le chat).

Quand tu as créé le projet Supabase et l’application Discord, reviens avec les noms des tables et le comportement souhaité ; on pourra brancher KeyLedger et écrire le bot proprement.
