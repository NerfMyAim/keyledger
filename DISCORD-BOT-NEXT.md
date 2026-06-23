# Étape suivante : synchronisation Discord

Le tableau local est volontairement séparé du bot : un bot ne peut pas écrire dans le stockage du navigateur d’un site statique. Pour une synchronisation fiable, remplacez le stockage local par une base partagée avant de connecter Discord.

## Architecture recommandée

```text
Commande Discord / attribuer
        ↓
Bot Discord (hébergé)
        ↓  requête authentifiée
Fonction Netlify
        ↓
Base de données partagée (Supabase)
        ↓
KeyLedger déployé sur Netlify
```

## Données minimales d’une attribution

```json
{
  "key": "clé choisie dans le stock",
  "pseudo": "pseudo Discord",
  "discordId": "identifiant Discord",
  "email": "optionnel",
  "assignedAt": "2026-06-23T18:30",
  "endsAt": "optionnel",
  "notes": "numéro de ticket"
}
```

La fonction serveur doit refuser une clé absente du stock, enregistrer l’attribution et garder un journal. Elle ne doit jamais rendre automatiquement une clé attribuée disponible : toute fin de contrat doit être vérifiée selon les conditions de licence et ce qui a été vendu au client.

## Secrets nécessaires plus tard

- `DISCORD_BOT_TOKEN` : uniquement dans l’hébergeur du bot ;
- `DISCORD_PUBLIC_KEY` : pour vérifier les interactions Discord ;
- URL et clé serveur de la base Supabase : uniquement dans les fonctions Netlify.

Ne placez jamais ces valeurs dans `app.js`, dans un dépôt public ou dans une page Netlify statique.
