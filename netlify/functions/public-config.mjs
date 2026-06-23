export default async () => {
  // L'extension Netlify nomme cette variable SUPABASE_DATABASE_URL ;
  // le déploiement manuel de KeyLedger utilisait SUPABASE_URL.
  const url = process.env.SUPABASE_URL || process.env.SUPABASE_DATABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    return new Response(JSON.stringify({ configured: false }), {
      headers: { 'content-type': 'application/json; charset=utf-8' }
    });
  }
  // Cette clé est publique par conception. La clé service_role reste uniquement côté serveur.
  return new Response(JSON.stringify({ configured: true, url, anonKey }), {
    headers: { 'content-type': 'application/json; charset=utf-8' }
  });
};
