# Cloudflare Pages — Guide Bénin Foncier
## Différences critiques vs Netlify

---

## Structure des projets

Cloudflare Pages ne gère pas les sous-domaines dans un seul projet
de la même façon que Netlify. Il faut **deux projets séparés** :

| Projet CF Pages        | Fichiers à déployer                          | Domaine custom           |
|------------------------|----------------------------------------------|--------------------------|
| `beninfoncier-main`    | `benin_foncier_v45_final.html` → `index.html`| beninfoncier.bj          |
|                        | `_headers_beninfoncier` → `_headers`         |                          |
|                        | `_redirects`                                  |                          |
| `beninfoncier-admin`   | `benin_foncier_admin_final.html` → `index.html` | admin.beninfoncier.bj |
|                        | `_headers_admin` → `_headers`                |                          |

**Important** : renommer les fichiers HTML en `index.html` avant le déploiement.

---

## ÉTAPE 1 — Dashboard Cloudflare (avant tout)

Dans **Speed → Optimization** pour CHAQUE projet :

```
Rocket Loader    → OFF  ← OBLIGATOIRE (casse les scripts inline)
Auto Minify HTML → OFF  ← OBLIGATOIRE (peut casser les templates)
Auto Minify JS   → OFF  ← OBLIGATOIRE
Auto Minify CSS  → Optionnel (sans risque)
```

Dans **Caching → Configuration** :
```
Browser Cache TTL → Respect Existing Headers
```

---

## ÉTAPE 2 — Déployer via CLI (recommandé)

```bash
# Installer Wrangler (CLI Cloudflare)
npm install -g wrangler
wrangler login

# Déployer la plateforme principale
wrangler pages deploy ./dist-main \
  --project-name=beninfoncier-main \
  --branch=production

# Déployer l'admin
wrangler pages deploy ./dist-admin \
  --project-name=beninfoncier-admin \
  --branch=production
```

Structure des dossiers à préparer :

```
dist-main/
├── index.html        ← renommer v45_final.html
├── _headers          ← renommer _headers_beninfoncier
└── _redirects

dist-admin/
├── index.html        ← renommer admin_final.html
└── _headers          ← renommer _headers_admin
```

---

## ÉTAPE 3 — Domaines custom

Dans chaque projet CF Pages → **Custom domains** :

```
beninfoncier-main  → beninfoncier.bj + www.beninfoncier.bj
beninfoncier-admin → admin.beninfoncier.bj
```

Cloudflare gère automatiquement les enregistrements DNS et les certificats SSL
si votre domaine est sur Cloudflare. Propagation instantanée dans ce cas.

---

## ÉTAPE 4 — Activer Cloudflare Web Analytics

Dans le Dashboard → **Analytics & Logs → Web Analytics** :
Ajouter le site `beninfoncier.bj`. Le script analytics est déjà autorisé
dans le CSP (`static.cloudflareinsights.com`).

---

## ÉTAPE 5 — Vérifier les headers en production

```bash
curl -I https://beninfoncier.bj | grep -E "x-frame|x-content|strict|content-security|referrer"
```

Résultat attendu :
```
x-frame-options: DENY
x-content-type-options: nosniff
strict-transport-security: max-age=63072000; includeSubDomains; preload
content-security-policy: default-src 'self'; ...
referrer-policy: strict-origin-when-cross-origin
```

Vérification complète : https://securityheaders.com/?q=beninfoncier.bj

---

## Différences `_headers` Netlify vs Cloudflare Pages

| Aspect                | Netlify              | Cloudflare Pages          |
|-----------------------|----------------------|---------------------------|
| Format du fichier     | Identique            | Identique                 |
| Sous-domaines         | 1 projet suffit      | 1 projet par sous-domaine |
| Rocket Loader         | N/A                  | Désactiver OBLIGATOIREMENT|
| Cache HTML            | Cache-Control suffit | + Surrogate-Control       |
| Analytics script      | Pas de script CF     | Ajouter static.cloudflareinsights.com au CSP |
| HTTPS enforcement     | Via _redirects       | Géré au niveau proxy CF   |
| DDoS                  | Basique              | Niveau entreprise inclus  |
| Edge Afrique          | Absent               | Lagos, Abidjan            |

---

*SIPI-AFRIK · TECH+ · beninfoncier.bj*
