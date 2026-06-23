import crypto from 'node:crypto';
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = () => process.env.SUPABASE_URL || process.env.SUPABASE_DATABASE_URL || '';
const plain = (status, body) => new Response(body, { status, headers: { 'content-type': 'text/plain; charset=utf-8' } });

function verifiedSignature(payload, receivedSignature) {
  const secret = process.env.SELLAUTH_WEBHOOK_SECRET;
  if (!secret || !receivedSignature) return false;
  // SellAuth documente la signature à partir de JSON.stringify(req.body),
  // donc du JSON analysé puis sérialisé, plutôt que des octets HTTP bruts.
  const expected = crypto.createHmac('sha256', secret).update(JSON.stringify(payload)).digest('hex');
  const received = Buffer.from(receivedSignature, 'utf8');
  const expectedBuffer = Buffer.from(expected, 'utf8');
  return received.length === expectedBuffer.length && crypto.timingSafeEqual(received, expectedBuffer);
}

export default async (request) => {
  if (request.method !== 'POST') return plain(405, 'Method not allowed.');
  const rawBody = await request.text();
  try {
    const payload = JSON.parse(rawBody);
    if (!verifiedSignature(payload, request.headers.get('x-signature'))) return plain(401, 'Invalid webhook signature.');
    if (payload.event !== 'INVOICE.ITEM.DELIVER-DYNAMIC' || !payload.item?.variant_id) return plain(400, 'Unsupported SellAuth delivery event.');
    const url = supabaseUrl();
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!url || !serviceRoleKey) throw new Error('Server configuration is incomplete.');
    const supabase = createClient(url, serviceRoleKey);
    const { data: key, error } = await supabase.rpc('deliver_sellauth_item', {
      p_unique_id: String(payload.unique_id || ''),
      p_item_id: String(payload.item.id || ''),
      p_invoice_id: String(payload.id || ''),
      p_variant_id: String(payload.item.variant_id),
      p_customer_email: String(payload.email || payload.customer?.email || '')
    });
    if (error) {
      if (/compatible key|not configured/i.test(error.message)) {
        console.warn('SellAuth delivery unavailable', { variantId: payload.item.variant_id, variantName: payload.item.variant?.name || '', reason: error.message });
        return plain(400, 'We are currently out of stock. Please wait for restock.');
      }
      throw error;
    }
    // Une seule ligne : SellAuth l'affiche comme le livrable de cet item.
    return plain(200, key);
  } catch (error) {
    console.error('SellAuth delivery failure', error);
    return plain(500, 'Temporary delivery error. Please retry shortly.');
  }
};
