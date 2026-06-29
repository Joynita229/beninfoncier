/**
 * ══════════════════════════════════════════════════════════════════════════════
 * BÉNIN FONCIER — Edge Function : happy
 * ══════════════════════════════════════════════════════════════════════════════
 *
 * Rôle : répondre aux messages du chat HAPPY et générer des conseils fonciers via OpenAI.
 *
 * Déploiement :
 *   supabase functions deploy happy --no-verify-jwt
 *
 * Variables d'environnement requises :
 *   OPENAI_API_KEY -> clé OpenAI (Dashboard Supabase → Settings → Secrets)
 *
 * Note : le front-end envoie une requête POST vers /functions/v1/happy
 *       avec { compartment: 'chat', message: '...' }
 *
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }

  if (req.method === 'GET') {
    return json({ ok: true, message: 'HAPPY endpoint is live.' })
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  if (!OPENAI_API_KEY) {
    return json({ error: 'OPENAI_API_KEY is not configured' }, 500)
  }

  let payload: any
  try {
    payload = await req.json()
  } catch {
    return json({ error: 'Invalid JSON body' }, 400)
  }

  const userMessage = typeof payload.message === 'string' ? payload.message.trim() : ''
  if (!userMessage) {
    return json({ error: 'Missing message' }, 400)
  }

  const systemPrompt = `Tu es HAPPY, juriste spécialisée en droit foncier béninois et assistant client. ` +
    `Réponds de manière claire, professionnelle et concise. Fournis des conseils pratiques liés au marché foncier au Bénin, ` +
    `aux risques de titre foncier, à la vérification notariale et à la protection des acheteurs. ` +
    `Ne donnes pas de conseils financiers, mais orientes vers des vérifications légales concrètes.`

  const openAiPayload = {
    model: 'gpt-4o-mini',
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userMessage }
    ],
    temperature: 0.7,
    max_tokens: 400,
    top_p: 1,
  }

  try {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify(openAiPayload),
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error('[HAPPY] OpenAI error', response.status, errorText)
      return json({ error: 'OpenAI request failed', details: errorText }, response.status)
    }

    const result = await response.json()
    const reply = result?.choices?.[0]?.message?.content || ''
    return json({ reply, model: result.model || null })
  } catch (error) {
    console.error('[HAPPY] Error calling OpenAI', error)
    return json({ error: 'Failed to call OpenAI', details: String(error) }, 500)
  }
})

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  })
}
