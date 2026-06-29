-- ══════════════════════════════════════════════════════════════════════════════
-- BÉNIN FONCIER — Migration complète : correction + tables manquantes + RLS
-- Exécuter DANS L'ORDRE dans Supabase Dashboard → SQL Editor → New Query
-- ══════════════════════════════════════════════════════════════════════════════
-- Ce script est IDEMPOTENT : vous pouvez l'exécuter plusieurs fois sans risque.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── 0. Vérifier l'état actuel ────────────────────────────────────────────────
SELECT '▶ Migration Bénin Foncier — démarrage' as step;

-- ── 1. Tables manquantes ──────────────────────────────────────────────────────

-- 1a. bf_documents — Archivage des actes (utilisé par le frontend v45)
CREATE TABLE IF NOT EXISTS bf_documents (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  ref text NOT NULL,
  type text NOT NULL,
  sous_type text,
  titre text NOT NULL,
  resume text,
  html_snapshot text,
  user_phone text,
  user_type text,
  montant integer DEFAULT 0,
  is_certified boolean DEFAULT false,
  parties jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Index pour les lookups par téléphone
CREATE INDEX IF NOT EXISTS idx_bf_documents_phone ON bf_documents(user_phone);
CREATE INDEX IF NOT EXISTS idx_bf_documents_ref ON bf_documents(ref);
CREATE INDEX IF NOT EXISTS idx_bf_documents_type ON bf_documents(type);

-- 1b. bf_affiliates — Programme de parrainage
CREATE TABLE IF NOT EXISTS bf_affiliates (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  code text NOT NULL UNIQUE,
  phone text NOT NULL,
  name text,
  clicks integer DEFAULT 0,
  conversions integer DEFAULT 0,
  commission_pending integer DEFAULT 0,
  commission_paid integer DEFAULT 0,
  kyc_status text DEFAULT 'pending',
  status text DEFAULT 'active',
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bf_affiliates_code ON bf_affiliates(code);
CREATE INDEX IF NOT EXISTS idx_bf_affiliates_phone ON bf_affiliates(phone);

-- 1c. bf_rif_requests — Dossiers RIF
CREATE TABLE IF NOT EXISTS bf_rif_requests (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  ref text NOT NULL,
  type text,
  phone text NOT NULL,
  zone text,
  parcelle text,
  coordgps text,
  montant integer DEFAULT 0,
  status text DEFAULT 'pending',
  rapport_url text,
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bf_rif_phone ON bf_rif_requests(phone);
CREATE INDEX IF NOT EXISTS idx_bf_rif_status ON bf_rif_requests(status);

-- 1d. bf_blog — Articles du blog
CREATE TABLE IF NOT EXISTS bf_blog (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  titre text NOT NULL,
  categorie text,
  auteur text DEFAULT 'SIPI-AFRIK',
  extrait text,
  contenu text,
  image_url text,
  slug text UNIQUE,
  status text DEFAULT 'draft',
  published_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bf_blog_status ON bf_blog(status);
CREATE INDEX IF NOT EXISTS idx_bf_blog_slug ON bf_blog(slug);

-- 1e. bf_admin_log — Journal des actions admin
CREATE TABLE IF NOT EXISTS bf_admin_log (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  action text NOT NULL,
  target_id text,
  target_type text,
  details jsonb,
  ip text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bf_admin_log_action ON bf_admin_log(action);

SELECT '✅ 5 nouvelles tables créées' as step;

-- ── 2. RLS : Activer sur les nouvelles tables ─────────────────────────────────
ALTER TABLE bf_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE bf_affiliates ENABLE ROW LEVEL SECURITY;
ALTER TABLE bf_rif_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE bf_blog ENABLE ROW LEVEL SECURITY;
ALTER TABLE bf_admin_log ENABLE ROW LEVEL SECURITY;

SELECT '✅ RLS activé sur les 5 tables' as step;

-- ── 3. Policies pour bf_documents ─────────────────────────────────────────────
-- Les utilisateurs peuvent gérer leurs propres documents (via x-user-phone)
-- L'admin peut tout voir via la table profiles

DROP POLICY IF EXISTS "Users read own docs" ON bf_documents;
CREATE POLICY "Users read own docs"
  ON bf_documents FOR SELECT
  USING (
    user_phone = current_setting('request.headers', true)::json->>'x-user-phone'
    OR EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Users insert own docs" ON bf_documents;
CREATE POLICY "Users insert own docs"
  ON bf_documents FOR INSERT
  WITH CHECK (
    user_phone = current_setting('request.headers', true)::json->>'x-user-phone'
    OR EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Users delete own docs" ON bf_documents;
CREATE POLICY "Users delete own docs"
  ON bf_documents FOR DELETE
  USING (
    user_phone = current_setting('request.headers', true)::json->>'x-user-phone'
    OR EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Admin full access on documents" ON bf_documents;
CREATE POLICY "Admin full access on documents"
  ON bf_documents FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

SELECT '✅ Policies bf_documents créées' as step;

-- ── 4. Policies pour bf_affiliates ────────────────────────────────────────────
DROP POLICY IF EXISTS "Admin full access on affiliates" ON bf_affiliates;
CREATE POLICY "Admin full access on affiliates"
  ON bf_affiliates
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

SELECT '✅ Policies bf_affiliates créées' as step;

-- ── 5. Policies pour bf_rif_requests ──────────────────────────────────────────
DROP POLICY IF EXISTS "Admin full access on rif" ON bf_rif_requests;
CREATE POLICY "Admin full access on rif"
  ON bf_rif_requests
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

SELECT '✅ Policies bf_rif_requests créées' as step;

-- ── 6. Policies pour bf_blog ──────────────────────────────────────────────────
DROP POLICY IF EXISTS "Admin full access on blog" ON bf_blog;
CREATE POLICY "Admin full access on blog"
  ON bf_blog
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Public read published blog" ON bf_blog;
CREATE POLICY "Public read published blog"
  ON bf_blog FOR SELECT
  USING (status = 'published');

SELECT '✅ Policies bf_blog créées' as step;

-- ── 7. Policies pour bf_admin_log ─────────────────────────────────────────────
DROP POLICY IF EXISTS "Admin full access on log" ON bf_admin_log;
CREATE POLICY "Admin full access on log"
  ON bf_admin_log
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

SELECT '✅ Policies bf_admin_log créées' as step;

-- ── 8. Correction RLS bf_vendors ──────────────────────────────────────────────
-- Problème : l'ancienne policy utilisait current_setting('request.jwt.claims')
-- mais le frontend n'envoie pas de JWT (juste la clé anon).
-- Solution : on permet la lecture via le header x-user-phone (custom header)
-- et on garde l'accès admin via auth.uid().

-- Supprimer l'ancienne policy obsolète
DROP POLICY IF EXISTS "Vendor reads own vendor record" ON bf_vendors;

-- Nouvelle policy : lecture via header x-user-phone (frontend) ou admin
CREATE POLICY "Vendor reads own vendor record"
  ON bf_vendors FOR SELECT
  USING (
    phone = current_setting('request.headers', true)::json->>'x-user-phone'
    OR EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

SELECT '✅ RLS bf_vendors corrigée (utilise x-user-phone header)' as step;

-- ── 9. Vérification finale ────────────────────────────────────────────────────
SELECT '═══════════ RÉCAPITULATIF ═══════════' as status;

SELECT table_name, column_count
FROM (
  SELECT table_name, COUNT(*) as column_count
  FROM information_schema.columns
  WHERE table_schema = 'public'
  GROUP BY table_name
) t
WHERE table_name IN (
  'profiles', 'bf_vendors', 'bf_webhook_log',
  'bf_documents', 'bf_affiliates', 'bf_rif_requests',
  'bf_blog', 'bf_admin_log'
)
ORDER BY table_name;

SELECT '═══════════ POLICIES RLS ═══════════' as status;

SELECT schemaname, tablename, policyname
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
    'profiles', 'bf_vendors', 'bf_webhook_log',
    'bf_documents', 'bf_affiliates', 'bf_rif_requests',
    'bf_blog', 'bf_admin_log'
  )
ORDER BY tablename, policyname;

SELECT '✅ Migration terminée avec succès !' as status;

COMMIT;
