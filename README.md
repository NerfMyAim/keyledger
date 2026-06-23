# KeyLedger

Tableau de gestion local pour un stock de licences et leurs attributions. Il fonctionne sans installation : ouvrez `index.html` dans un navigateur moderne, ou publiez le dossier tel quel sur Netlify.

## Première utilisation

1. Ouvrez **Import & sauvegarde**.
2. Sélectionnez les deux fichiers `cles-disponibles.csv` et `cles-disponibles (1).csv` dans **Importer le stock CSV**. Ils seront fusionnés et dédoublonnés.
3. Les 9 attributions visibles dans l’ancien tableau sont déjà préchargées. Si besoin, sélectionnez également `Lovable App.html` pour relire le fichier ; les lignes déjà présentes seront ignorées.
4. Utilisez **Attribuer une clé** : la clé reste dans l’inventaire, passe automatiquement à « Attribuée » et affiche le pseudo client associé.

Les données sont enregistrées dans le stockage local du navigateur. Exportez régulièrement une sauvegarde JSON dans l’onglet **Import & sauvegarde**.

## Netlify et Discord

Déployé tel quel sur Netlify, KeyLedger reste une application locale : chaque navigateur possède ses propres données. Pour un partage entre ordinateurs ou un bot Discord qui crée des attributions automatiquement, il faudra ajouter :

- une base de données partagée (par exemple Supabase) ;
- une fonction Netlify qui valide les requêtes Discord ;
- les secrets Discord dans les variables d’environnement Netlify, jamais dans le JavaScript du site.

Le site suit les échéances mais ne remet jamais automatiquement une clé attribuée dans le stock. Toute réutilisation doit respecter les conditions de la licence et l’engagement vendu au client.
