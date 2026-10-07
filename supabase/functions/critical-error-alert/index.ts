import { createClient } from 'npm:@supabase/supabase-js@2';

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });

Deno.serve(async (request) => {
  if (request.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  const authorization = request.headers.get('authorization') ?? '';
  const token = authorization.replace(/^Bearer\s+/i, '');
  if (!token || token === authorization) return json(401, { error: 'unauthorized' });

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const secretKeys = Deno.env.get('SUPABASE_SECRET_KEYS');
  const webhook = Deno.env.get('MINDTRACK_CRITICAL_ALERT_WEBHOOK');
  let adminKey: string | undefined;
  try {
    adminKey = secretKeys ? JSON.parse(secretKeys).default : undefined;
  } catch {
    return json(503, { error: 'supabase_secret_keys_invalid' });
  }
  if (!supabaseUrl || !adminKey || !webhook) {
    return json(503, { error: 'alert_delivery_not_configured' });
  }

  let webhookUrl: URL;
  try {
    webhookUrl = new URL(webhook);
  } catch {
    return json(503, { error: 'alert_webhook_invalid' });
  }
  if (webhookUrl.protocol !== 'https:' || webhookUrl.username || webhookUrl.password) {
    return json(503, { error: 'alert_webhook_invalid' });
  }

  const admin = createClient(supabaseUrl, adminKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) return json(401, { error: 'unauthorized' });

  const cutoff = new Date(Date.now() - 5 * 60_000).toISOString();
  const { data: event, error: readError } = await admin
    .from('client_error_events')
    .select('id, category, app_version, created_at, alert_claimed_at')
    .eq('user_id', authData.user.id)
    .eq('severity', 'critical')
    .is('alert_sent_at', null)
    .gte('created_at', cutoff)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (readError) return json(500, { error: 'event_lookup_failed' });
  if (!event) return json(200, { status: 'no_pending_event' });
  if (!/^[a-z0-9_]{1,80}$/.test(event.category)) {
    return json(422, { error: 'event_category_invalid' });
  }

  const staleClaim = new Date(Date.now() - 2 * 60_000).toISOString();
  let claimQuery = admin
    .from('client_error_events')
    .update({ alert_claimed_at: new Date().toISOString() })
    .eq('id', event.id)
    .is('alert_sent_at', null);
  claimQuery = event.alert_claimed_at
    ? claimQuery.lt('alert_claimed_at', staleClaim)
    : claimQuery.is('alert_claimed_at', null);
  const { data: claimed, error: claimError } = await claimQuery.select('id').maybeSingle();
  if (claimError) return json(500, { error: 'event_claim_failed' });
  if (!claimed) return json(202, { status: 'already_claimed_or_sent' });

  const occurredAt = event.created_at;
  const appVersion = /^[a-zA-Z0-9.+-]{1,40}$/.test(event.app_version)
    ? event.app_version
    : '';
  const alert = {
    text: `[MindTrack] Kritik senkronizasyon hatası: ${event.category}`,
    content: `[MindTrack] Kritik senkronizasyon hatası: ${event.category}`,
    source: 'mindtrack',
    severity: 'critical',
    category: event.category,
    appVersion,
    occurredAt,
  };

  try {
    const response = await fetch(webhookUrl, {
      method: 'POST',
      redirect: 'error',
      signal: AbortSignal.timeout(8_000),
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify(alert),
    });
    if (!response.ok) throw new Error(`webhook_http_${response.status}`);

    const { error: markError } = await admin
      .from('client_error_events')
      .update({ alert_sent_at: new Date().toISOString(), alert_claimed_at: null })
      .eq('id', event.id);
    if (markError) return json(500, { error: 'event_mark_failed' });
    return json(200, { status: 'sent' });
  } catch {
    await admin
      .from('client_error_events')
      .update({ alert_claimed_at: null })
      .eq('id', event.id);
    return json(502, { error: 'alert_delivery_failed' });
  }
});
