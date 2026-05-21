#!/usr/bin/env bash
# web.sh — gère srv-web-11 (serveur web : node_exporter + app NodeJS)
# Usage :
#   ./web.sh                  → SSH interactif
#   ./web.sh deploy           → sync app/ + rebuild image + restart conteneur
#   ./web.sh status           → état node_exporter + conteneur + endpoints
#   ./web.sh logs             → logs du conteneur node-metrics-app
#   ./web.sh stop-node-exp    → arrête node_exporter (test alerte InstanceDown)
#   ./web.sh start-node-exp   → redémarre node_exporter
#   ./web.sh traffic [N]      → génère N requêtes sur toutes les routes (défaut 30)
#   ./web.sh run <cmd>        → exécute <cmd> à distance

set -euo pipefail

HOST="92.39.62.91"
USER="ubuntu"
REMOTE_DIR="~/node-metrics-app"
CONTAINER="node-metrics-app"

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
PERM=$(stat -f "%A" "$SSH_KEY" 2>/dev/null || stat -c "%a" "$SSH_KEY")
[ "$PERM" != "600" ] && chmod 600 "$SSH_KEY"

SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
ssh_run()  { ssh  "${SSH_OPTS[@]}" "$USER@$HOST" "$@"; }
ssh_tty()  { ssh  "${SSH_OPTS[@]}" -t "$USER@$HOST" "$@"; }
rsync_to() { rsync -avz -e "ssh ${SSH_OPTS[*]}" "$@"; }

cmd=${1:-ssh}; shift || true

case "$cmd" in
  ssh|"")
    echo "→ Connexion à srv-web-11 ($HOST)…"
    exec ssh "${SSH_OPTS[@]}" "$USER@$HOST"
    ;;

  deploy)
    if [ ! -d "$REPO_DIR/app" ]; then
      echo "❌ Dossier app/ introuvable dans $REPO_DIR" >&2; exit 1
    fi
    echo "→ Sync app/ → srv-web-11:$REMOTE_DIR/"
    rsync_to --delete --exclude 'node_modules' \
      "$REPO_DIR/app/" "$USER@$HOST:$REMOTE_DIR/"

    echo "→ Rebuild image Docker…"
    ssh_run "cd $REMOTE_DIR && sudo docker build -t $CONTAINER ."

    echo "→ Restart conteneur (recrée pour prendre la nouvelle image)…"
    ssh_run "sudo docker rm -f $CONTAINER 2>/dev/null; sudo docker run -d --name $CONTAINER --restart unless-stopped -p 3000:3000 $CONTAINER"

    echo "→ Vérification endpoint…"
    sleep 2
    ssh_run 'curl -fsS http://localhost:3000/health && echo'
    ;;

  status)
    echo "=== node_exporter (systemd) ==="
    ssh_run 'systemctl is-active node_exporter; systemctl status node_exporter --no-pager -l | head -5'
    echo
    echo "=== Conteneur app NodeJS ==="
    ssh_run "sudo docker ps --filter name=$CONTAINER --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
    echo
    echo "=== Endpoints ==="
    ssh_run 'curl -sf http://localhost:9100/metrics | head -1 && echo "  ✓ node_exporter:9100 OK"' || echo "  ✗ node_exporter:9100 KO"
    ssh_run 'curl -sf http://localhost:3000/health && echo "  ✓ app:3000 OK"' || echo "  ✗ app:3000 KO"
    ;;

  logs)
    ssh_tty "sudo docker logs -f --tail=100 $CONTAINER"
    ;;

  stop-node-exp)
    echo "→ Arrêt de node_exporter (déclenche InstanceDown après ~75s)…"
    ssh_run 'sudo systemctl stop node_exporter && echo "  arrêté à $(date)"'
    ;;

  start-node-exp)
    echo "→ Démarrage de node_exporter…"
    ssh_run 'sudo systemctl start node_exporter && sleep 1 && systemctl is-active node_exporter'
    ;;

  traffic)
    N=${1:-30}
    echo "→ Génération de $N batches de requêtes sur toutes les routes…"
    ssh_run "for i in \$(seq 1 $N); do
      curl -s -o /dev/null http://localhost:3000/
      curl -s -o /dev/null http://localhost:3000/health
      curl -s -o /dev/null http://localhost:3000/users
      curl -s -o /dev/null -X POST http://localhost:3000/orders
      curl -s -o /dev/null http://localhost:3000/slow &
      curl -s -o /dev/null http://localhost:3000/error
      curl -s -o /dev/null http://localhost:3000/inexistant
    done; wait; echo terminé"
    ;;

  run)
    ssh_tty "$@"
    ;;

  *)
    echo "Usage: $0 [ssh|deploy|status|logs|stop-node-exp|start-node-exp|traffic [N]|run <cmd>]" >&2
    exit 1
    ;;
esac
