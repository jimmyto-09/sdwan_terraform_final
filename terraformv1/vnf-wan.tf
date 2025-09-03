resource "kubernetes_pod" "vnf_wan" {
  for_each = local.vnf_wan_instances

  metadata {
    name      = "vnf-wan-${each.key}"
    namespace = "rdsv"
    labels = {
      "k8s-app" = "vnf-wan-${each.key}"
    }
    annotations = {
      "k8s.v1.cni.cncf.io/networks" = jsonencode([
        {
          name      = "mplswan"
          interface = "net1"
        }
      ])
    }
  }

  spec {
    # Contenedor principal: VNF WAN
    container {
      name  = "vnf-wan"
      image = "educaredes/vnf-wan"

      command = [
        "/bin/sh",
        "-c",
        <<-EOT
          set -e -x
          /usr/share/openvswitch/scripts/ovs-ctl start
          while [ ! -e /var/run/openvswitch/db.sock ]; do
            echo '⏳ Esperando OVS...'
            sleep 1
          done

          while true; do
            ACCESS_IP=$(getent hosts vnf-access-${each.key}-service | awk '{print $1}')
            if [ ! -z "$ACCESS_IP" ]; then break; fi
            echo "⏳ Esperando IP de vnf-access-${each.key}..."
            sleep 2
          done

          WAN_IP=$(hostname -i)
          echo "🌐 IP local (wan): $WAN_IP"
          echo "🎯 IP remota (access): $ACCESS_IP"

          ip link del axswan 2>/dev/null || true

          # Configuración BRWAN
          while true; do
            CPE_IP=$(getent hosts ${each.value.cpe_service_name} | awk '{print $1}')
            if [ ! -z "$CPE_IP" ]; then break; fi
            echo "⏳ Esperando IP de vnf-cpe..."
            sleep 2
          done

          ovs-vsctl add-br brwan

          ip link add axswan type vxlan id 3 remote $ACCESS_IP dstport 4788 dev eth0
          ovs-vsctl add-port brwan axswan
          ovs-vsctl add-port brwan net1
          ip link set axswan up
          ip route del $ACCESS_IP via 169.254.1.1 dev eth0 2>/dev/null || true
          ip route add $ACCESS_IP via 169.254.1.1 dev eth0

          ip link del cpewan 2>/dev/null || true
          ip link add cpewan type vxlan id 5 remote $CPE_IP dstport 8741 dev eth0
          ovs-vsctl add-port brwan cpewan
          ifconfig cpewan up

          # Conectar bridge a controlador Ryu
          while true; do
            RYU_IP=$(getent hosts knf-ctrl-${each.key}-svc | awk '{print $1}')
            if [ -n "$RYU_IP" ]; then
              echo "🔗 Ryu controller IP: $RYU_IP"
              break
            fi
            echo "⏳ Esperando IP de controller…"
            sleep 2
          done

          ovs-vsctl set bridge brwan protocols=OpenFlow10,OpenFlow12,OpenFlow13
          ovs-vsctl set-fail-mode brwan secure
          ovs-vsctl set bridge brwan other-config:datapath-id=0000000000000001
          ovs-vsctl set-controller brwan tcp:$RYU_IP:6633
          ovs-vsctl set-manager ptcp:6632

          sleep infinity
        EOT
      ]

      security_context {
        privileged = true
        capabilities { add = ["NET_ADMIN", "SYS_ADMIN"] }
      }
    }

    # Sidecar: metrics exporter
    container {
      name  = "node-exporter"
      image = "quay.io/prometheus/node-exporter:latest"

      port {
        name           = "metrics"
        container_port = 9100
      }

      resources {
        limits = {
          cpu    = "100m"
          memory = "64Mi"
        }
        requests = {
          cpu    = "50m"
          memory = "32Mi"
        }
      }
    }

   
    }
  }


# Servicio headless para exponer IP real del Pod WAN
resource "kubernetes_service" "vnf_wan_pod" {
  for_each = local.vnf_wan_instances

  metadata {
    name      = "vnf-wan-${each.key}-pod"
    namespace = "rdsv"
  }

  spec {
    cluster_ip = "None"
    selector   = {
      "k8s-app" = "vnf-wan-${each.key}"
    }
  }
}
