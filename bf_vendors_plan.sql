-- ══════════════════════════════════════════════════════════════════════════════
-- BÉNIN FONCIER — Migration : Plan d'abonnement + Logs webhook
-- Exécuter EN DEUXIÈME dans : Supabase Dashboard → SQL Editor → New Query
-- ══════════════════════════════════════════════════════════════════════════════
--
-- ⚠️  PRÉREQUIS : Exécuter d'abord 00_init_profiles_and_vendors.sql
--                (crée tables profiles, bf_vendors, bf_webhook_log)
--
-- Ce script ajoute les colonnes de plan à bf_vendors et configure le RLS complet
-- ══════════════════════════════════════════════════════════════════════════════

-- ① Vérifier que bf_vendors existe (devrait venir de 00_init_...)
-- Les colonnes plan sont déjà dans 00_init... mais on les vérifie ici
SELECT 'Tables bf_vendors et bf_webhook_log doivent exister.' as prerequisite;

-- Si tu viens directement ici sans avoir exécuté 00_init_...,
-- décommente les lignes ci-dessous pour créer les tables de base :
/*
CREATE TABLE IF NOT EXISTS bf_vendors (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID,
  phone TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  plan TEXT DEFAULT 'free',
  plan_expires_at TIMESTAMPTZ,
  plan_activated_at TIMESTAMPTZ,
  plan_transaction_id TEXT,
  plan_amount INTEGER DEFAULT 0,
  plan_annual BOOLEAN DEFAULT FALSE,
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bf_webhook_log (
  id BIGSERIAL PRIMARY KEY,
  transaction_id TEXT NOT NULL UNIQUE,
  vendor_phone TEXT,
  status TEXT NOT NULL,
  message TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);
*/

-- ② Index pour les lookups par téléphone (utilisé par le webhook)
-- Déjà dans 00_init..., mais on renforce ici
CREATE INDEX IF NOT EXISTS idx_bf_vendors_phone ON bf_vendors (phone);
CREATE INDEX IF NOT EXISTS idx_bf_vendors_plan  ON bf_vendors (plan);
CREATE INDEX IF NOT EXISTS idx_bf_webhook_txid ON bf_webhook_log (transaction_id, status);

-- ③ Vérifier que RLS est activé (déjà dans 00_init_..., mais on renforce)
-- Si exécution répétée, ces commandes sont idempotentes
ALTER TABLE bf_webhook_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE bf_vendors ENABLE ROW LEVEL SECURITY;

-- ④ Vérification : les policies de bf_webhook_log
-- Policy SELECT pour admin (créée dans 00_init_...)
-- On peut voir les policies existantes :
SELECT
  tablename,
  policyname,
  permissive,
  roles,
  qual as policy_condition
FROM pg_policies
WHERE tablename IN ('bf_vendors', 'bf_webhook_log')
ORDER BY tablename, policyname;

-- ⑤ Vérification des colonnes plan dans bf_vendors
SELECT
  column_name,
  data_type,
  column_default
FROM information_schema.columns
WHERE table_name = 'bf_vendors'
  AND column_name LIKE 'plan%'
ORDER BY column_name;

-- ⑥ Vérification de bf_webhook_log
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_name = 'bf_webhook_log'
ORDER BY column_name;

-- ⑦ Vérification des indexes
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE tablename IN ('bf_vendors', 'bf_webhook_log')
ORDER BY tablename, indexname;

-- ⑧ Vérification rapide : compter les vendors
SELECT COUNT(*) as total_vendors FROM bf_vendors;
SELECT COUNT(*) as total_webhook_logs FROM bf_webhook_log;

-- ⑨ Test d'insertion simulée dans bf_webhook_log (OPTIONNEL - à décommenter)
-- Cette requête teste que la table webhook_log accepte les données
-- Décommente si tu veux tester ; sinon, le webhook FedaPay fera la première insertion
-- INSERT INTO bf_webhook_log (transaction_id, vendor_phone, status, message)
-- VALUES ('TEST_' || to_char(now(), 'YYYYMMDDHH24MISS'), '+229XXXXXXXX', 'test', 'Test webhook log');

COMMIT;
