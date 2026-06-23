import { createClient } from '@supabase/supabase-js';

const required = (name) => {
  const value = process.env[name];
  if (!value) throw new Error(`Missing server configuration: ${name}`);
  return value;
};
const supabaseUrl = () => process.env.SUPABASE_URL || process.env.SUPABASE_DATABASE_URL || '';
const response = (statusCode, body) => new Response(JSON.stringify(body), {
  status: statusCode,
  headers: { 'content-type': 'application/json; charset=utf-8' }
});

async function adminClient(request) {
  const authorization = request.headers.get('authorization') || '';
  if (!authorization.startsWith('Bearer ')) throw new Error('Missing user session');
  const url = supabaseUrl();
  if (!url) throw new Error('Missing server configuration: SUPABASE_URL');
  const serviceRoleKey = required('SUPABASE_SERVICE_ROLE_KEY');
  const client = createClient(url, serviceRoleKey);
  const token = authorization.slice(7);
  const { data: { user }, error: authError } = await client.auth.getUser(token);
  if (authError || !user) throw new Error('Invalid user session');
  const { data: profile, error: profileError } = await client.from('profiles').select('is_admin').eq('user_id', user.id).maybeSingle();
  if (profileError || !profile?.is_admin) throw new Error('Administrator access required');
  // La clé serveur garde l'accès aux données, tandis que le JWT utilisateur permet
  // à la fonction SQL assign_available_key de contrôler auth.uid() et is_admin().
  return createClient(url, serviceRoleKey, { global: { headers: { Authorization: authorization } } });
}

export default async (request) => {
  try {
    const client = await adminClient(request);
    if (request.method === 'GET') {
      const [inventory, assignments] = await Promise.all([
        client.from('inventory_keys').select('*').order('created_at'),
        client.from('assignments').select('*, inventory_keys(key_value, license_type)').order('assigned_at', { ascending: false })
      ]);
      if (inventory.error) throw inventory.error;
      if (assignments.error) throw assignments.error;
      return response(200, { inventory: inventory.data, assignments: assignments.data });
    }
    if (request.method === 'POST') {
      const body = await request.json();
      if (!body.discordName?.trim()) return response(400, { error: 'discordName is required' });
      if (!body.keyId) return response(400, { error: 'keyId is required' });
      const { data, error } = await client.rpc('assign_inventory_key', {
        p_key_id: body.keyId,
        p_discord_name: body.discordName.trim(),
        p_discord_id: body.discordId?.trim() || '',
        p_email: body.email?.trim() || '',
        p_assigned_at: body.assignedAt || null,
        p_ends_at: body.endsAt || null,
        p_notes: body.notes?.trim() || ''
      });
      if (error) return response(409, { error: error.message });
      return response(201, { assignment: data });
    }
    if (request.method === 'PATCH') {
      const body = await request.json();
      if (body.action === 'finish') {
        const { error } = await client.rpc('finish_assignment', { p_assignment_id: body.assignmentId });
        if (error) return response(409, { error: error.message });
        return response(200, { ok: true });
      }
      if (body.action === 'note') {
        const { error } = await client.rpc('update_key_note', { p_key_id: body.keyId, p_note: body.note || '' });
        if (error) return response(409, { error: error.message });
        return response(200, { ok: true });
      }
      if (body.action === 'update-assignment') {
        const { error } = await client.from('assignments').update({
          discord_name: body.discordName?.trim(), discord_id: body.discordId?.trim() || '', email: body.email?.trim() || '',
          assigned_at: body.assignedAt, ends_at: body.endsAt || null, status: body.status, notes: body.notes?.trim() || ''
        }).eq('id', body.assignmentId);
        if (error) return response(409, { error: error.message });
        return response(200, { ok: true });
      }
      return response(400, { error: 'Unknown action' });
    }
    return response(405, { error: 'Method not allowed' });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected error';
    const status = /session|access|required/i.test(message) ? 401 : 500;
    return response(status, { error: message });
  }
};
