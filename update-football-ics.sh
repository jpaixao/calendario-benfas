#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$HOME/repos/calendario-benfas"

# chave ssh dedicada sem passphrase
export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_ed25519_cron -o IdentitiesOnly=yes"

URL_BENFICA="https://www.zerozero.pt/agenda_ics.php?id_equipa=4&code=97c4e695460023a46f2200249c73d1c257e0fee9850bf&matches=1&imp"
URL_SPORTING="https://www.zerozero.pt/agenda_ics.php?id_equipa=16&code=e7ac4e16a11d88d1b529ae730425dcae633c33edb816d&matches=1&imp"

cd "$REPO_DIR"
git checkout main >/dev/null 2>&1 || true
git pull --rebase --autostash >/dev/null

merge_ics_keep_history() {
  local old_file="$1"   # ficheiro publicado atualmente (pode não existir)
  local new_file="$2"   # download atual do zerozero (já UTF-8 e LF)
  local out_file="$3"   # output final (merged)

  python3 - "$old_file" "$new_file" "$out_file" <<'PY'
import re, sys
from datetime import datetime

old_path, new_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

def read(path):
  try:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
      return f.read()
  except FileNotFoundError:
    return ""

def split_header(text):
  m = re.search(r"(?m)^BEGIN:VEVENT\s*$", text)
  if not m:
    return text.strip() + "\n", []
  header = text[:m.start()]
  events = re.findall(r"BEGIN:VEVENT.*?END:VEVENT", text, flags=re.S)
  return header, events

def uid_of(ev):
  m = re.search(r"(?m)^UID:(.+)\s*$", ev)
  return m.group(1).strip() if m else None

def dt_end_of(ev):
  # tenta DTEND; fallback DTSTART
  m = re.search(r"(?m)^(DTEND(?:;[^:]*)?):([0-9TZ]+)\s*$", ev)
  if not m:
    m = re.search(r"(?m)^(DTSTART(?:;[^:]*)?):([0-9TZ]+)\s*$", ev)
  if not m:
    return None
  val = m.group(2).strip()
  val = val[:-1] if val.endswith("Z") else val
  for fmt in ("%Y%m%dT%H%M%S", "%Y%m%dT%H%M", "%Y%m%d"):
    try:
      return datetime.strptime(val, fmt)
    except ValueError:
      pass
  return None

old_txt = read(old_path)
new_txt = read(new_path)

# header do output: usa o header do new (mantém VTIMEZONE etc)
new_header, new_events = split_header(new_txt)
old_header, old_events = split_header(old_txt)

def index_by_uid(events):
  d = {}
  for ev in events:
    u = uid_of(ev)
    if u:
      d[u] = ev
  return d

new_by_uid = index_by_uid(new_events)
old_by_uid = index_by_uid(old_events)

now = datetime.now()

# regra:
# - para UIDs presentes no new: usar new (atualiza resultados)
# - para UIDs que existiam no old mas já não vêm no new:
#   manter apenas se forem passados (END < now)
merged = dict(new_by_uid)

for u, ev in old_by_uid.items():
  if u in merged:
    continue
  end_dt = dt_end_of(ev)
  if end_dt and end_dt < now:
    merged[u] = ev

# ordenar por DTSTART/DTEND (o melhor que conseguimos)
def sort_key(ev):
  dt = dt_end_of(ev)
  return dt or datetime.min

events_sorted = sorted(merged.values(), key=sort_key)

out = new_header.rstrip() + "\n"
out += "\n".join(events_sorted).rstrip() + "\n"
if not out.endswith("END:VCALENDAR\n"):
  out += "END:VCALENDAR\n"

with open(out_path, "w", encoding="utf-8", newline="\n") as f:
  f.write(out)
PY
}

fetch_and_write() {
  local name="$1"
  local url="$2"

  local out="$REPO_DIR/${name}.ics"
  local tmp_raw="$REPO_DIR/.${name}.ics.raw"
  local tmp_new="$REPO_DIR/.${name}.ics.new"

  echo "updating ${name}.ics"

  curl -L --fail \
    -H "User-Agent: Mozilla/5.0" \
    -H "Accept: text/calendar,*/*" \
    -H "Referer: https://www.zerozero.pt/" \
    "$url" -o "$tmp_raw"

  # validações mínimas
  if ! grep -q "BEGIN:VCALENDAR" "$tmp_raw"; then
    echo "download não parece um ics (sem BEGIN:VCALENDAR) - $name"
    head -n 50 "$tmp_raw" || true
    rm -f "$tmp_raw"
    exit 1
  fi
  if ! grep -q "BEGIN:VEVENT" "$tmp_raw"; then
    echo "ics sem eventos (sem BEGIN:VEVENT) - $name"
    head -n 80 "$tmp_raw" || true
    rm -f "$tmp_raw"
    exit 1
  fi

  # normalizar CRLF -> LF e garantir UTF-8 (corrige acentos)
  if iconv -f UTF-8 -t UTF-8 "$tmp_raw" >/dev/null 2>&1; then
    tr -d '\r' < "$tmp_raw" > "$tmp_new"
  else
    iconv -f WINDOWS-1252 -t UTF-8 "$tmp_raw" | tr -d '\r' > "$tmp_new"
  fi
  rm -f "$tmp_raw"

  # merge: manter histórico (eventos passados) e atualizar UIDs existentes
  merge_ics_keep_history "$out" "$tmp_new" "$out"
  rm -f "$tmp_new"
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
