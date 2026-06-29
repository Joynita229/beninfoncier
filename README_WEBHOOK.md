# 🔐 Guide de Déploiement — Webhook FedaPay × Supabase
## Bénin Foncier · SIPI-AFRIK · TECH+

---

## Architecture

```
Utilisateur paye → FedaPay widget
                         ↓
              FedaPay API confirme
                         ↓
        FedaPay → POST /functions/v1/fedapay-webhook
                         ↓
         Edge Function vérifie signature HMAC
                         ↓
         Double-check via API FedaPay (sk_live_...)
                         ↓
         UPDATE bf_vendors SET plan = 'elite'...
                         ↓
          Client poll Supabase → plan activé ✅
```

---

## ÉTAPE 1 — SQL (5 min)

Dans **Supabase → SQL Editor → New Query**, exécuter :

```
supabase/migrations/20260613_bf_vendors_plan.sql
```

Vérifie que les colonnes `plan`, `plan_expires_at`, etc. apparaissent dans `bf_vendors`.

---

## ÉTAPE 2 — Installer Supabase CLI

```bash
npm install -g supabase
supabase login
supabase link --project-ref VOTRE_PROJECT_ID
```

---

## ÉTAPE 3 — Configurer les secrets

```bash
supabase secrets set FEDAPAY_SECRET_KEY=sk_live_VOTRE_CLE
supabase secrets set FEDAPAY_WEBHOOK_SECRET=whsec_VOTRE_SECRET
```

Pour récupérer `FEDAPAY_WEBHOOK_SECRET` :
- FedaPay Dashboard → Intégrations → Webhooks → Créer un webhook
- URL : `https://VOTRE_ID.supabase.co/functions/v1/fedapay-webhook`
- Événements : `transaction.approved`, `transaction.declined`
- Copier le **Signing Secret** généré

---

## ÉTAPE 4 — Déployer l'Edge Function

```bash
supabase functions deploy fedapay-webhook --no-verify-jwt
```

`--no-verify-jwt` est requis car FedaPay n'envoie pas de JWT Supabase.

---

## ÉTAPE 5 — Tester en sandbox

```bash
# Simuler un webhook FedaPay en sandbox
curl -X POST https://VOTRE_ID.supabase.co/functions/v1/fedapay-webhook \
  -H "Content-Type: application/json" \
  -H "x-fedapay-signature: sha256=TEST_SKIP" \
  -d '{
    "name": "transaction.approved",
    "entity": {
      "id": 99999,
      "status": "approved",
      "amount": 40000,
      "custom_metadata": "{\"vendor_phone\":\"+22901000001\",\"plan\":\"solo\",\"annual\":\"false\"}"
    }
  }'
```

Vérifier dans `bf_webhook_log` que le log apparaît.

---

## ÉTAPE 6 — Vérifier dans Supabase

```sql
-- Voir les logs webhook
SELECT * FROM bf_webhook_log ORDER BY created_at DESC LIMIT 20;

-- Vérifier l'activation d'un plan
SELECT phone, plan, plan_expires_at, plan_transaction_id
FROM bf_vendors
WHERE plan != 'free'
ORDER BY plan_activated_at DESC;
```

---

## Sécurité — Ce que le webhook garantit

| Risque | Protection |
|--------|-----------|
| Webhook forgé | Signature HMAC-SHA256 vérifiée |
| Transaction non payée | Double-vérification via API FedaPay |
| Double traitement | Idempotence via `bf_webhook_log` |
| Plan activé côté client | Client lit Supabase, n'écrit plus jamais |
| Accès non autorisé | RLS Supabase sur `bf_vendors` |
| Service Role exposée | Utilisée uniquement dans l'Edge Function |

---

## Variables d'environnement — Récapitulatif

| Variable | Où la trouver |
|----------|--------------|
| `FEDAPAY_SECRET_KEY` | FedaPay Dashboard → API → sk_live_... |
| `FEDAPAY_WEBHOOK_SECRET` | FedaPay Dashboard → Webhooks → Signing Secret |
| `SUPABASE_URL` | Auto-injecté par Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | Auto-injecté par Supabase |

---

*SIPI-AFRIK · TECH+ · beninfoncier.bj*
