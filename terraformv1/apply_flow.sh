#!/usr/bin/env bash
set -euo pipefail

# ──────────────── Resolver Kubernetes ───────────────────────────────
if command -v kubectl >/dev/null 2>&1; then
  KCTL="kubectl"
elif command -v microk8s >/dev/null 2>&1; then
  KCTL="microk8s kubectl"
else
  echo "No se encontró ni kubectl ni microk8s" >&2
  exit 1
fi
echo " Usando '$KCTL' como cliente Kubernetes"

# ─────────────────────────── Configuración ──────────────────────────────────
JSON_DIR="/home/upm/shared/sdedge-ns/json"   # carpeta con todos los .json
NAMESPACE="rdsv"                             # namespace de los pods Ryu
COMMON_JSONS=(
  "from-cpe.json"
  "to-cpe.json"
  "broadcast-from-axs.json"
  "from-mpls.json"
  "to-voip-gw.json"
)

# ────────────────────────── Verificaciones previas ──────────────────────────
[[ -d "$JSON_DIR" ]] || { echo " Carpeta $JSON_DIR no existe"; exit 1; }
command -v curl >/dev/null || { echo "curl no encontrado"; exit 1; }

# ───────────────────────────── Descubrir e identificar sites ──────────────────────────────
mapfile -t EDGE_DIRS < <(find "$JSON_DIR" -maxdepth 1 -type d -name 'sdedge*' | sort)
if [[ ${#EDGE_DIRS[@]} -eq 0 ]]; then
  echo " No se encontró ninguna carpeta sdedge* en $JSON_DIR"
  exit 1
fi
echo "🔎 Detectados $((${#EDGE_DIRS[@]})) sites → ${EDGE_DIRS[*]##*/}"

# ───────────────────────────── Bucle por cada site ──────────────────────────
for EDGE_DIR in "${EDGE_DIRS[@]}"; do
  NETNUM=$(basename "$EDGE_DIR" | sed 's/^sdedge//')
  SITE="site${NETNUM}"
  SVC="knf-ctrl-${SITE}-svc"

  echo
  echo "═══════════════  Cargando reglas en ${SITE}  ═══════════════"

  # 1) Esperar a que el Pod esté Ready
  echo "⏳ Esperando Pod Ryu (${SITE})..."
  $KCTL wait --for=condition=ready \
    pod -l k8s-app="knf-ctrl-${SITE}" -n "$NAMESPACE" --timeout=120s

  # 2) Obtener NodePort (REST)
  NODEPORT="$($KCTL get svc -n "$NAMESPACE" "$SVC" \
    -o jsonpath='{.spec.ports[?(@.name=="rest")].nodePort}')"

  # Usar siempre localhost para el acceso desde el propio nodo/VM
  FLOW_URL="http://localhost:${NODEPORT}/stats/flowentry/add"
  echo "🎯 Endpoint REST (NodePort) = ${FLOW_URL}"

  # 3) Enviar JSONs comunes
  for F in "${COMMON_JSONS[@]}"; do
    FILE="${JSON_DIR}/${F}"
    [[ -f "$FILE" ]] || { echo " $FILE no existe, se salta"; continue; }
    echo " ➜ $F"
    curl -s -H 'Content-Type: application/json' -X POST -d @"$FILE" "$FLOW_URL"
  done

  # 4) Enviar el específico sdedgeX/to-voip.json
  SPEC="${EDGE_DIR}/to-voip.json"
  if [[ -f "$SPEC" ]]; then
    echo " ➜ $(basename "$SPEC")"
    curl -s -H 'Content-Type: application/json' -X POST -d @"$SPEC" "$FLOW_URL"
  else
    echo "  $SPEC no encontrado, se omite"
  fi

  echo "✅ Reglas cargadas en ${SITE}"

  # 5) Abrir GUI
  GUI_URL="http://localhost:${NODEPORT}/home/index.html"
  echo "🌐 Abriendo FlowManager GUI en ${GUI_URL}"
  firefox "$GUI_URL" &
done

echo
echo " Todas las reglas SDN se han inyectado con éxito"
