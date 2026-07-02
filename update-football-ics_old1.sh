#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$HOME/repos/calendario-benfas"

# chave ssh dedicada sem passphrase
export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_ed25519_cron -o IdentitiesOnly=yes"

# URLs zerozero (sem x=2)
URL_BENFICA="https://www.zerozero.pt/agenda_ics.php?id_equipa=4&code=97c4e695460023a46f2200249c73d1c257e0fee9850bf&matches=1&imp"
URL_SPORTING="https://www.zerozero.pt/agenda_ics.php?id_equipa=16&code=e7ac4e16a11d88d1b529ae730425dcae633c33edb816d&matches=1&imp"

cd "$REPO_DIR"

git checkout main >/dev/null 2>&1 || true
git pull --rebase --autostash >/dev/null

fetch_and_write() {
  local name="$1"      # benfica | sporting
  local url="$2"
  local out="$REPO_DIR/${name}.ics"
  local tmp="$REPO_DIR/.${name}.ics.tmp"

  echo "updating ${name}.ics"

  curl -L --fail \
    -H "User-Agent: Mozilla/5.0" \
    -H "Accept: text/calendar,*/*" \
    -H "Referer: https://www.zerozero.pt/" \
    "$url" -o "$tmp"

  if ! grep -q "BEGIN:VCALENDAR" "$tmp"; then
    echo "download não parece um ics (sem BEGIN:VCALENDAR) - $name"
    head -n 50 "$tmp" || true
    rm -f "$tmp"
    exit 1
  fi

  if ! grep -q "BEGIN:VEVENT" "$tmp"; then
    echo "ics sem eventos (sem BEGIN:VEVENT) - $name"
    head -n 80 "$tmp" || true
    rm -f "$tmp"
    exit 1
  fi

  # normalizar CRLF -> LF e garantir UTF-8 (corrige acentos)
  if iconv -f UTF-8 -t UTF-8 "$tmp" >/dev/null 2>&1; then
    tr -d '\r' < "$tmp" > "$out"
  else
    iconv -f WINDOWS-1252 -t UTF-8 "$tmp" | tr -d '\r' > "$out"
  fi

  rm -f "$tmp"
}

fetch_and_write "benfica" "$URL_BENFICA"
fetch_and_write "sporting" "$URL_SPORTING"

# commit/push apenas se houver alterações
if ! git diff --quiet; then
  git add benfica.ics sporting.ics
  git commit -m "update ics ($(date -u +'%Y-%m-%dT%H:%M:%SZ'))" >/dev/null
  git push >/dev/null
  echo "updated and pushed"
else
  echo "no changes"
fi
