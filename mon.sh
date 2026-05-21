#!/usr/bin/env bash
# mon.sh — gère srv-mon-11 (serveur monitoring : Prometheus + Alertmanager)
# Usage :
#   ./mon.sh                  → SSH interactif
#   ./mon.sh deploy           → sync monitoring/ + reload Prometheus + reload Alertmanager
#   ./mon.sh status           → état des targets et conteneurs
#   ./mon.sh logs [service]   → logs (prometheus|alertmanager, défaut: prometheus)
#   ./mon.sh reload           → reload Prometheus + Alertmanager (sans sync)
#   ./mon.sh restart          → docker compose restart de la stack
#   ./mon.sh run <cmd>        → exécute <cmd> à distance

set -euo pipefail

HOST="85.217.162.187"
USER="ubuntu"
REMOTE_DIR="~/monitoring"

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
KEY_CANDIDATES=("$HOME/.ssh/m110/id_rsa" "$REPO_DIR/DocATaDispo/ssh_key")

# --- locate + fix SSH key ----------------------------------------------------
SSH_KEY=""
for k in "${KEY_CANDIDATES[@]}"; do
  [ -f "$k" ] && SSH_KEY="$k" && break
done
if [ -z "$SSH_KEY" ]; then
  echo "❌ Aucune clé SSH trouvée dans :" >&2
  printf '   - %s\n' "${KEY_CANDIDATES[@]}" >&2
  exit 1
fi
# normalize perms (macOS uses stat -f, Linux stat -c)
PERM=$(stat -f "%A" "$SSH_KEY" 2>/dev/null || stat -c "%a" "$SSH_KEY")
[ "$PERM" != "600" ] && chmod 600 "$SSH_KEY"

SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
ssh_run()  { ssh  "${SSH_OPTS[@]}" "$USER@$HOST" "$@"; }
ssh_tty()  { ssh  "${SSH_OPTS[@]}" -t "$USER@$HOST" "$@"; }
rsync_to() { rsync -avz -e "ssh ${SSH_OPTS[*]}" "$@"; }

cmd=${1:-ssh}; shift || true

case "$cmd" in
  ssh|"")
    echo "→ Connexion à srv-mon-11 ($HOST)…"
    exec ssh "${SSH_OPTS[@]}" "$USER@$HOST"
    ;;

  deploy)
    if [ ! -d "$REPO_DIR/monitoring" ]; then
      echo "❌ Dossier monitoring/ introuvable dans $REPO_DIR" >&2; exit 1
    fi
    echo "→ Sync monitoring/ → srv-mon-11:$REMOTE_DIR/"
    rsync_to --delete \
      --exclude '.env' --exclude 'alertmanager.yml' \
      "$REPO_DIR/monitoring/" "$USER@$HOST:$REMOTE_DIR/"

    echo "→ Vérif présence du .env distant (secret webhook Slack)…"
    if ! ssh_run "[ -f $REMOTE_DIR/.env ]"; then
      echo "⚠️  Pas de .env distant — Alertmanager ne pourra pas notifier Slack."
      echo "    Crée-le avec :"
      echo "      ./mon.sh run \"echo SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXX > $REMOTE_DIR/.env && chmod 600 $REMOTE_DIR/.env\""
    else
      echo "→ Régénération alertmanager.yml depuis le template…"
      ssh_run "cd $REMOTE_DIR && set -a && . ./.env && set +a && envsubst < alertmanager.yml.template > alertmanager.yml"
    fi

    echo "→ Reload Prometheus (hot reload)…"
    ssh_run 'curl -fsS -X POST http://localhost:9090/-/reload && echo "  ✓ Prometheus reload OK"'

    echo "→ Reload Alertmanager (hot reload)…"
    ssh_run 'if curl -fsS -X POST http://localhost:9093/-/reload; then echo "  ✓ Alertmanager reload OK"; else echo "  (reload AM échoué, fallback restart)"; sudo docker compose -f ~/monitoring/docker-compose.yml restart alertmanager; fi'
    ;;

  status)
    echo "=== Containers ==="
    ssh_run 'sudo docker compose -f ~/monitoring/docker-compose.yml ps'
    echo
    echo "=== Targets Prometheus ==="
    ssh_run 'curl -s http://localhost:9090/api/v1/targets' | python3 -c "
import json, sys
for t in json.load(sys.stdin)['data']['activeTargets']:
    print(f\"  {t['labels']['job']:15} {t['health']:6} {t['scrapeUrl']}\")
"
    echo
    echo "=== Active alerts ==="
    ssh_run 'curl -s http://localhost:9090/api/v1/alerts' | python3 -c "
import json, sys
a = json.load(sys.stdin)['data']['alerts']
print('  aucune') if not a else None
for x in a:
    print(f\"  {x['labels']['alertname']:20} {x['state']:8} {x['labels'].get('instance','')}\")
"
    ;;

  logs)
    svc=${1:-prometheus}
    ssh_tty "sudo docker logs -f --tail=100 $svc"
    ;;

  reload)
    ssh_run 'curl -fsS -X POST http://localhost:9090/-/reload && echo "  ✓ Prometheus reload OK"'
    ssh_run 'curl -fsS -X POST http://localhost:9093/-/reload && echo "  ✓ Alertmanager reload OK"'
    ;;

  restart)
    ssh_run "sudo docker compose -f $REMOTE_DIR/docker-compose.yml restart"
    ;;

  run)
    ssh_tty "$@"
    ;;

  *)
    echo "Usage: $0 [ssh|deploy|status|logs [service]|reload|restart|run <cmd>]" >&2
    exit 1
    ;;
esac
