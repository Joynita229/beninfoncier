-- ══════════════════════════════════════════════════════════════════════════════
-- BÉNIN FONCIER — Initialisation complète
-- Exécuter en PREMIER dans Supabase Dashboard → SQL Editor → New Query
-- ══════════════════════════════════════════════════════════════════════════════

-- ① Table profiles (gestion des rôles : admin, vendor, client, affiliate)
-- Cette table est liée à auth.users via son ID
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  phone TEXT UNIQUE,
  name TEXT,
  role TEXT DEFAULT 'client',  -- 'admin' | 'vendor' | 'client' | 'affiliate'
  status TEXT DEFAULT 'active', -- 'active' | 'suspended' | 'deleted'
  avatar_url TEXT,
  bio TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index sur les champs critiques
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email);
CREATE INDEX IF NOT EXISTS idx_profiles_phone ON profiles(phone);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);

-- ② Table bf_vendors (profils vendeurs détaillés)
CREATE TABLE IF NOT EXISTS bf_vendors (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  phone TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  company_name TEXT,
  address TEXT,
  city TEXT,
  region TEXT,
  cni_number TEXT,
  cni_photo_url TEXT,  -- lien vers Supabase Storage
  id_card_verified BOOLEAN DEFAULT false,
  bank_account TEXT,
  bank_name TEXT,
  
  -- Plan d'abonnement
  plan TEXT DEFAULT 'free',  -- 'free' | 'solo' | 'expert' | 'elite'
  plan_expires_at TIMESTAMPTZ DEFAULT NULL,
  plan_activated_at TIMESTAMPTZ DEFAULT NULL,
  plan_transaction_id TEXT DEFAULT NULL,
  plan_amount INTEGER DEFAULT 0,
  plan_annual BOOLEAN DEFAULT false,
  
  -- Statut général
  status TEXT DEFAULT 'active',  -- 'active' | 'pending' | 'suspended'
  kyc_status TEXT DEFAULT 'pending',  -- 'pending' | 'verified' | 'rejected'
  
  -- Affiliation
  referred_by TEXT,  -- téléphone du parrain (affiliate)
  affiliate_code TEXT UNIQUE,
  affiliate_earnings INTEGER DEFAULT 0,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ②bis : Ajouter les colonnes manquantes si la table bf_vendors existait déjà
ALTER TABLE bf_vendors
  ADD COLUMN IF NOT EXISTS company_name TEXT,
  ADD COLUMN IF NOT EXISTS address TEXT,
  ADD COLUMN IF NOT EXISTS city TEXT,
  ADD COLUMN IF NOT EXISTS region TEXT,
  ADD COLUMN IF NOT EXISTS cni_number TEXT,
  ADD COLUMN IF NOT EXISTS cni_photo_url TEXT,
  ADD COLUMN IF NOT EXISTS id_card_verified BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS bank_account TEXT,
  ADD COLUMN IF NOT EXISTS bank_name TEXT,
  ADD COLUMN IF NOT EXISTS plan TEXT DEFAULT 'free',
  ADD COLUMN IF NOT EXISTS plan_expires_at TIMESTAMPTZ DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS plan_activated_at TIMESTAMPTZ DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS plan_transaction_id TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS plan_amount INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS plan_annual BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS kyc_status TEXT DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS referred_by TEXT,
  ADD COLUMN IF NOT EXISTS affiliate_code TEXT,
  ADD COLUMN IF NOT EXISTS affiliate_earnings INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- Index pour les lookups
CREATE INDEX IF NOT EXISTS idx_bf_vendors_phone ON bf_vendors(phone);
CREATE INDEX IF NOT EXISTS idx_bf_vendors_plan ON bf_vendors(plan);
CREATE INDEX IF NOT EXISTS idx_bf_vendors_user_id ON bf_vendors(user_id);
CREATE INDEX IF NOT EXISTS idx_bf_vendors_city ON bf_vendors(city);

-- ③ Table bf_webhook_log (log des transactions FedaPay)
CREATE TABLE IF NOT EXISTS bf_webhook_log (
  id BIGSERIAL PRIMARY KEY,
  transaction_id TEXT NOT NULL UNIQUE,
  vendor_phone TEXT,
  status TEXT NOT NULL,  -- 'processed' | 'rejected' | 'error'
  message TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_bf_webhook_txid ON bf_webhook_log(transaction_id, status);
CREATE INDEX IF NOT EXISTS idx_bf_webhook_vendor ON bf_webhook_log(vendor_phone);

-- ④ RLS : Activer Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE bf_vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE bf_webhook_log ENABLE ROW LEVEL SECURITY;

-- ⑤ Policies pour profiles
CREATE POLICY "Users read own profile"
  ON profiles FOR SELECT
  USING (auth.uid() = id OR EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));

CREATE POLICY "Users update own profile"
  ON profiles FOR UPDATE
  USING (auth.uid() = id OR EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ))
  WITH CHECK (auth.uid() = id OR EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));

CREATE POLICY "Admins delete profiles"
  ON profiles FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));

-- ⑥ Policies pour bf_vendors (accès vendeur + admin)
CREATE POLICY "Vendor reads own vendor record"
  ON bf_vendors FOR SELECT
  USING (
    phone = current_setting('request.jwt.claims', true)::json->>'phone'
    OR EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Admin reads all vendors"
  ON bf_vendors FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));

CREATE POLICY "Admin updates vendors"
  ON bf_vendors FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));

CREATE POLICY "Admin deletes vendors"
  ON bf_vendors FOR DELETE
  USING (EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));

-- ⑦ Policies pour bf_webhook_log (admins only, append-only)
CREATE POLICY "Admins read webhook logs"
  ON bf_webhook_log FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  ));

CREATE POLICY "Webhook insert disabled for users"
  ON bf_webhook_log FOR INSERT
  WITH CHECK (false);  -- Les webhooks utilisent service_role_key

-- ⑧ Vérification
SELECT 'Tables créées avec succès !' as status;

SELECT
  table_name,
  column_count
FROM (
  SELECT table_name, COUNT(*) as column_count
  FROM information_schema.columns
  WHERE table_schema = 'public'
  GROUP BY table_name
) t
WHERE table_name IN ('profiles', 'bf_vendors', 'bf_webhook_log')
ORDER BY table_name;

COMMIT;
