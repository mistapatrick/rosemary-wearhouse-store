#!/bin/sh
# One-time hardening: host the two third-party libraries from YOUR OWN site instead of a CDN.
# Run on a computer with internet, inside the project folder:   sh tools/vendor.sh
set -e
mkdir -p vendor
curl -fsSL https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js -o vendor/supabase.js
curl -fsSL https://cdn.jsdelivr.net/npm/exceljs@4.4.0/dist/exceljs.min.js -o vendor/exceljs.min.js
for f in vendor/supabase.js vendor/exceljs.min.js; do
  printf "%s  sha384-%s\n" "$f" "$(openssl dgst -sha384 -binary "$f" | openssl base64 -A)"
done
echo "Next: in config.js add   export const VENDORED = true;   then commit and push the vendor folder."
echo "Then remove https://cdn.jsdelivr.net from script-src in vercel.json and index.html."
