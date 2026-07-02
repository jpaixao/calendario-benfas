#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$HOME/repos/calendario-benfas"
URL="https://www.zerozero.pt/agenda_ics.php?id_equipa=4&code=97c4e695460023a46f2200249c73d1c257e0fee9850bf&matches=1&imp"
OUT="$REPO_DIR/benfica.ics"
TMP="$REPO_DIR/.benfica.ics.tmp"
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

cd "$REPO_DIR"
export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_ed25519_cron -o IdentitiesOnly=yes"
# garantir branch principal (ajusta se usas master)
git checkout main >/dev/null 2>&1 || true
git pull --rebase >/dev/null

# download (headers "browser-like")
curl -L --fail \
  -H "User-Agent: Mozilla/5.0" \
  -H "Accept: text/calendar,*/*" \
  -H "Referer: https://www.zerozero.pt/" \
  "$URL" -o "$TMP"

# validação mínima (tem de ter calendário e eventos)
if ! grep -q "BEGIN:VCALENDAR" "$TMP"; then
  echo "download não parece um ics (sem BEGIN:VCALENDAR). primeiras linhas:"
  head -n 50 "$TMP" || true
  exit 1
fi

if ! grep -q "BEGIN:VEVENT" "$TMP"; then
  echo "ics sem eventos (sem BEGIN:VEVENT). primeiras linhas:"
  head -n 80 "$TMP" || true
  exit 1
fi

# normalizar CRLF -> LF e garantir utf-8
# se o ficheiro já for utf-8 válido, mantém
# se não for, converte de windows-1252 (cp1252) para utf-8
if iconv -f UTF-8 -t UTF-8 "$TMP" >/dev/null 2>&1; then
  tr -d '\r' < "$TMP" > "$OUT"
else
  iconv -f WINDOWS-1252 -t UTF-8 "$TMP" | tr -d '\r' > "$OUT"
fi

rm -f "$TMP"

# commit/push apenas se houver alterações
if ! git diff --quiet -- "$OUT"; then
  git add "$OUT"
  git commit -m "update benfica.ics ($(date -u +'%Y-%m-%dT%H:%M:%SZ'))" >/dev/null
  git push >/dev/null
  echo "updated and pushed"
else
  echo "no changes"
fi
