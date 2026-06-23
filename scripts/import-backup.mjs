// Usage: SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... npm run import:backup -- ./keyledger-backup.json
import { readFile } from 'node:fs/promises';
import { createClient } from '@supabase/supabase-js';

const file = process.argv[2];
if (!file || !process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error('Provide a backup JSON path plus SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.');
}
const backup = JSON.parse(await readFile(file, 'utf8'));
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
const keys = backup.stock.filter((key) => /^[a-f0-9]{32}$/i.test(key.key)).map((key) => ({
  key_value: key.key, license_type: key.type || '', source_date: key.sourceDate || '', state: key.state || 'available', note: key.note || ''
}));
const { error } = await supabase.from('inventory_keys').upsert(keys, { onConflict: 'key_value' });
if (error) throw error;
const { data: inventory, error: inventoryError } = await supabase.from('inventory_keys').select('id,key_value');
if (inventoryError) throw inventoryError;
const ids = new Map(inventory.map((key) => [key.key_value, key.id]));
const allAssignments = [...(backup.assignments || []), ...(backup.archive || [])];
const assignments = allAssignments.flatMap((assignment) => {
  const keyId = ids.get(assignment.key);
  if (!keyId) return [];
  return [{
    source_id: assignment.id || `${assignment.key}-${assignment.pseudo}-${assignment.assignedAt}`,
    key_id: keyId,
    discord_id: assignment.discordId || '',
    discord_name: assignment.pseudo || 'Inconnu',
    email: assignment.email || '',
    assigned_at: assignment.assignedAt || new Date().toISOString(),
    ends_at: assignment.endsAt || null,
    status: assignment.archivedAt ? 'archived' : (assignment.status || 'active'),
    notes: assignment.notes || '',
    archived_at: assignment.archivedAt || null
  }];
});
if (assignments.length) {
  const { error: assignmentError } = await supabase.from('assignments').upsert(assignments, { onConflict: 'source_id' });
  if (assignmentError) throw assignmentError;
}
console.log(`${keys.length} inventory keys and ${assignments.length} assignments imported.`);
