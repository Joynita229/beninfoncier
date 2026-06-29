#!/bin/bash
# ══════════════════════════════════════════════════════════════════
# SEC-007 : Calcul des hashes SRI pour les scripts CDN
# Exécuter : bash compute_sri.sh
# Puis remplacer les <script src> dans les fichiers HTML
# ══════════════════════════════════════════════════════════════════

echo "Calcul des hashes SRI..."

compute_sri() {
    local url="$1"
    local name="$2"
    local file=$(mktemp)
    curl -sL "$url" -o "$file"
    local hash=$(openssl dgst -sha384 -binary "$file" | openssl base64 -A)
    echo ""
    echo "=== $name ==="
    echo "URL : $url"
    echo "integrity=\"sha384-${hash}\""
    echo ""
    echo "Tag complet :"
    echo "<script src=\"$url\""
    echo "        integrity=\"sha384-${hash}\""
    echo "        crossorigin=\"anonymous\"></script>"
    rm "$file"
}

compute_sri "https://cdn.jsdelivr.net/npm/dompurify@3/dist/purify.min.js"        "DOMPurify 3"
compute_sri "https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.js"               "jsQR 1.4.0"
compute_sri "https://cdn.jsdelivr.net/npm/lucide@0.383.0/dist/umd/lucide.min.js" "Lucide 0.383.0"
compute_sri "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js" "Supabase JS 2"

echo ""
echo "⚠️  Tailwind CDN (cdn.tailwindcss.com) génère du CSS dynamiquement"
echo "    → SRI incompatible. Solution : Tailwind CLI compilé en production."

