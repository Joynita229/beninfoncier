/**
 * ══════════════════════════════════════════════════════════════════════════════
 * BÉNIN FONCIER — Edge Function : fedapay-webhook
 * ══════════════════════════════════════════════════════════════════════════════
 *
 * Rôle : Réceptionner et traiter les webhooks FedaPay de manière sécurisée.
 *
 * Flux :
 *   1. FedaPay → POST /functions/v1/fedapay-webhook (transaction approuvée)
 *   2. Vérification signature HMAC-SHA256
 *   3. Vérification idempotence (doublon ?)
 *   4. Vérification indépendante via l'API FedaPay (double-check)
 *   5. Mise à jour bf_vendors (plan + expiry)
 *   6. Log dans bf_webhook_log
 *
 * Déploiement :
 *   supabase functions deploy fedapay-webhook --no-verify-jwt
 *
 * Variables d'environnement requises (Supabase Dashboard → Settings → Secrets) :
 *   FEDAPAY_SECRET_KEY       → Votre clé secrète FedaPay (sk_live_...)
 *   FEDAPAY_WEBHOOK_SECRET   → Secret webhook (Dashboard FedaPay → Webhooks)
 *   SUPABASE_URL             → Auto-injecté par Supabase
 *   SUPABASE_SERVICE_ROLE_KEY → Auto-injecté par Supabase
 * ══════════════════════════════════════════════════════════════════════════════
 */

import { serve }        from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ── Constantes ────────────────────────────────────────────────────────────────
const FEDAPAY_API      = 'https://api.fedapay.com/v1'
const PLAN_DURATIONS   = { solo: 30, expert: 30, elite: 30 } as Record<string, number>

// ── Variables d'environnement ────────────────────────────────────────────────
const FP_SECRET        = Deno.env.get('FEDAPAY_SECRET_KEY')!
const FP_WEBHOOK_SEC   = Deno.env.get('FEDAPAY_WEBHOOK_SECRET') ?? ''
const SB_URL           = Deno.env.get('SUPABASE_URL')!
const SB_SERVICE_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

// ── CORS headers (Supabase Edge Functions requirement) ───────────────────────
const CORS = {
  'Access-Control-Allow-Origin' : '*',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, x-fedapay-signature',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}

// ══════════════════════════════════════════════════════════════════════════════
serve(async (req: Request) => {

  // Preflight CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS })
  }

  // Accept GET for browser smoke test and POST for actual webhooks
  if (req.method !== 'POST' && req.method !== 'GET') {
    return json({ error: 'Method not allowed' }, 405)
  }

  if (req.method === 'GET') {
    return json({
      ok: true,
      message: 'FedaPay webhook endpoint is alive. Use POST from FedaPay.',
      method: 'GET'
    }, 200)
  }

  // ── 1. Lire le body brut (nécessaire pour vérifier la signature) ───────────
  const rawBody = await req.text()

  // ── 2. Vérifier la signature HMAC-SHA256 ──────────────────────────────────
  const signature = req.headers.get('x-fedapay-signature') ?? ''

  if (FP_WEBHOOK_SEC) {
    const valid = await verifyHMAC(rawBody, signature, FP_WEBHOOK_SEC)
    if (!valid) {
      console.error('[BF-WEBHOOK] Signature invalide — requête rejetée')
      return json({ error: 'Signature invalide' }, 401)
    }
  } else {
    // En production, FEDAPAY_WEBHOOK_SECRET doit toujours être défini
    console.warn('[BF-WEBHOOK] FEDAPAY_WEBHOOK_SECRET non défini — signature non vérifiée')
  }

  // ── 3. Parser l'événement ─────────────────────────────────────────────────
  let event: FedaPayEvent
  try {
    event = JSON.parse(rawBody)
  } catch {
    return json({ error: 'JSON invalide' }, 400)
  }

  console.log(`[BF-WEBHOOK] Événement reçu : ${event.name}`)

  // On ne traite que les transactions approuvées
  if (event.name !== 'transaction.approved') {
    return json({ message: `Événement ignoré : ${event.name}` }, 200)
  }

  const tx    = event.entity
  const txId  = tx.id
  const meta  = parseMetadata(tx.custom_metadata)

  // ── 4. Idempotence — déjà traité ? ────────────────────────────────────────
  const sb = createClient(SB_URL, SB_SERVICE_KEY)

  const { data: existing } = await sb
    .from('bf_webhook_log')
    .select('id')
    .eq('transaction_id', String(txId))
    .eq('status', 'processed')
    .maybeSingle()

  if (existing) {
    console.log(`[BF-WEBHOOK] Transaction ${txId} déjà traitée — idempotence OK`)
    return json({ message: 'Déjà traité' }, 200)
  }

  // ── 5. Double-vérification via l'API FedaPay ──────────────────────────────
  const verified = await fetchTransaction(txId)

  if (!verified) {
    await logWebhook(sb, txId, 'error', 'Vérification API FedaPay échouée', meta)
    return json({ error: 'Transaction non vérifiable' }, 400)
  }

  if (verified.status !== 'approved') {
    await logWebhook(sb, txId, 'rejected', `Statut: ${verified.status}`, meta)
    return json({ error: `Statut inattendu: ${verified.status}` }, 400)
  }

  // ── 6. Extraire les informations du plan ──────────────────────────────────
  const vendorPhone = normalizePhone(meta.vendor_phone || tx.customer?.phone_number?.number)
  const planKey     = String(meta.plan ?? '').trim().toLowerCase()
  const isAnnual    = meta.annual === 'true' || meta.annual === true

  if (!vendorPhone || !planKey) {
    await logWebhook(sb, txId, 'error', `Metadata manquante: phone=${vendorPhone}, plan=${planKey}`, meta)
    return json({ error: 'Metadata incomplète' }, 400)
  }

  if (!PLAN_DURATIONS[planKey]) {
    await logWebhook(sb, txId, 'error', `Plan inconnu: ${planKey}`, meta)
    return json({ error: `Plan inconnu: ${planKey}` }, 400)
  }

  // ── 7. Calculer l'expiration ──────────────────────────────────────────────
  const now       = new Date()
  const days      = isAnnual ? PLAN_DURATIONS[planKey] * 12 : PLAN_DURATIONS[planKey]
  const expiresAt = new Date(now)
  expiresAt.setDate(expiresAt.getDate() + days)

  // ── 8. Mettre à jour bf_vendors ───────────────────────────────────────────
  const { data: updatedRows, error: updateError } = await sb
    .from('bf_vendors')
    .update({
      plan               : planKey,
      plan_expires_at    : expiresAt.toISOString(),
      plan_activated_at  : now.toISOString(),
      plan_transaction_id: String(txId),
      plan_amount        : tx.amount ?? verified.amount,
      plan_annual        : isAnnual,
      updated_at         : now.toISOString(),
    })
    .eq('phone', vendorPhone)
    .select('phone')

  if (updateError) {
    console.error('[BF-WEBHOOK] Erreur Supabase:', updateError)
    await logWebhook(sb, txId, 'error', `DB error: ${updateError.message}`, meta)
    return json({ error: 'Erreur base de données' }, 500)
  }

  if (!updatedRows || updatedRows.length === 0) {
    await logWebhook(sb, txId, 'error', `Aucune ligne bf_vendors mise à jour pour ${vendorPhone}`, meta)
    return json({ error: 'Vendeur introuvable pour la mise à jour du plan' }, 404)
  }

  // ── 9. Logger le succès ───────────────────────────────────────────────────
  await logWebhook(sb, txId, 'processed',
    `Plan ${planKey} activé pour ${vendorPhone} jusqu'au ${expiresAt.toISOString().split('T')[0]}`,
    meta
  )

  console.log(`[BF-WEBHOOK] ✅ Plan ${planKey} activé — ${vendorPhone} — expire ${expiresAt.toISOString().split('T')[0]}`)

  return json({ success: true, plan: planKey, expires_at: expiresAt.toISOString() }, 200)
})

// ══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════════════════════════════

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' }
  })
}

/**
 * Vérifie la signature HMAC-SHA256 de FedaPay.
 * Format header : "sha256=<hex_hash>"
 */
async function verifyHMAC(payload: string, signature: string, secret: string): Promise<boolean> {
  try {
    const enc = new TextEncoder()
    const key = await crypto.subtle.importKey(
      'raw', enc.encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false, ['sign']
    )
    const mac     = await crypto.subtle.sign('HMAC', key, enc.encode(payload))
    const expected = Array.from(new Uint8Array(mac))
      .map(b => b.toString(16).padStart(2, '0')).join('')
    const received = signature.replace(/^sha256=/, '')

    // Comparaison en temps constant (anti-timing attack)
    if (received.length !== expected.length) return false
    let diff = 0
    for (let i = 0; i < received.length; i++) {
      diff |= received.charCodeAt(i) ^ expected.charCodeAt(i)
    }
    return diff === 0
  } catch {
    return false
  }
}

/**
 * Vérifie la transaction directement auprès de l'API FedaPay.
 * Garantit que le webhook n'a pas été forgé.
 */
async function fetchTransaction(txId: number): Promise<FedaPayTransaction | null> {
  try {
    const res = await fetch(`${FEDAPAY_API}/transactions/${txId}`, {
      headers: {
        'Authorization': `Bearer ${FP_SECRET}`,
        'Content-Type' : 'application/json',
      }
    })
    if (!res.ok) {
      console.error(`[BF-WEBHOOK] API FedaPay ${res.status}:`, await res.text())
      return null
    }
    const data = await res.json()
    // FedaPay enveloppe dans { v1: { transaction: {...} } } ou { transaction: {...} }
    return data?.v1?.transaction ?? data?.transaction ?? data
  } catch (e) {
    console.error('[BF-WEBHOOK] Erreur fetch FedaPay:', e)
    return null
  }
}

function normalizePhone(value: unknown): string {
  if (typeof value !== 'string') return ''
  const trimmed = value.trim()
  if (!trimmed) return ''
  const normalized = trimmed.replace(/\s+/g, '')
  if (/^\d{8}$/.test(normalized)) return `+229${normalized}`
  return normalized
}

function parseMetadata(raw: unknown): Record<string, unknown> {
  if (!raw) return {}
  if (typeof raw === 'object') return raw as Record<string, unknown>
  try { return JSON.parse(String(raw)) } catch { return {} }
}

async function logWebhook(
  sb: ReturnType<typeof createClient>,
  txId: number,
  status: string,
  message: string,
  meta: Record<string, unknown>
) {
  try {
    await sb.from('bf_webhook_log').insert({
      transaction_id: String(txId),
      vendor_phone  : (meta?.vendor_phone as string) ?? null,
      status,
      message,
      metadata     : meta,
      created_at   : new Date().toISOString(),
    })
  } catch (e) {
    console.error('[BF-WEBHOOK] Erreur log:', e)
  }
}

// ── Types ─────────────────────────────────────────────────────────────────────
interface FedaPayEvent {
  name  : string
  entity: FedaPayTransaction
}

interface FedaPayTransaction {
  id             : number
  status         : string
  amount         : number
  custom_metadata: unknown
  customer       ?: { phone_number?: { number?: string } }
}
