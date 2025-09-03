#########################################################################
#  VNF-CPE (site1 / site2) – versión actualizada                       #
#########################################################################

resource "kubernetes_pod" "vnf_cpe" {
  for_each = local.vnf_cpe_instances   # site1 y site2

  metadata {
    name      = "vnf-cpe-${each.key}"
    namespace = "rdsv"

    labels = {
      "k8s-app" = "vnf-cpe-${each.key}"
    }

     annotations = {
  "k8s.v1.cni.cncf.io/networks" = jsonencode([
    {
      name      = "extnet${each.value.netnum}"    
      interface = "net${each.value.netnum}"        
    }
  ])
}
}


  spec {
    container {
      name  = "vnf-cpe"
      image = "educaredes/vnf-cpe"

      # --- Parche: resolvemos WAN_IP ANTES de modificar rutas por defecto ---
      command = [
        "/bin/sh", "-c",
        <<-EOT
          set -e -x
          /usr/share/openvswitch/scripts/ovs-ctl start
          while [ ! -e /var/run/openvswitch/db.sock ]; do echo '⏳ Esperando OVS…'; sleep 1; done

          ################################ [1] Resolver ACCESS
          while true; do
            ACCESS_IP=$(getent hosts ${each.value.access_service_name} | awk '{print $1}')
            [ -n "$ACCESS_IP" ] && break
            echo '⏳ Esperando IP de vnf-access…'; sleep 2
          done
          echo "🌐 CPE $(hostname -i) → access $ACCESS_IP"

          ################################ [2] Resolver WAN antes de tocar rutas
          while true; do
            WAN_IP=$(getent hosts vnf-wan-${each.key}-pod | awk '{print $1}')
            [ -n "$WAN_IP" ] && break
            echo "⏳ Esperando IP de vnf-wan-${each.key}-pod…"; sleep 2
          done
          echo "🎯 WAN_IP=$WAN_IP"

           while true; do
  RYU_IP=$(getent hosts knf-ctrl-${each.key}-svc | awk '{print $1}')
  if [ -n "$RYU_IP" ]; then
    echo "🔗 Ryu controller IP: $RYU_IP"
    break
  fi
  echo "⏳ Esperando IP de controller…"
  sleep 2
done

          

          ################################ BRINT  (access ↔ cpe)
          # 1. Crear bridge OVS dentro del contenedor CPE
          ovs-vsctl add-br brint

          # 2. Asignar IP interna al bridge (LAN cliente)
          ifconfig brint 192.168.255.254/24

          # 3. Crear túnel VXLAN ID 4 hacia Access
          ip link add axscpe type vxlan id 4 remote $ACCESS_IP dstport 8742 dev eth0 || true
          ovs-vsctl add-port brint axscpe
          ifconfig axscpe up

          # 4. Ajustar MTU para evitar fragmentación VXLAN
          ifconfig brint mtu 1400

          # 5. Asignar IP pública al vCPE (interfaz netX)
          ifconfig net${each.value.netnum} ${each.value.vcpepubip}/24

          # 6. Rutas para poder alcanzar primero al Pod Access
          ip route add $ACCESS_IP/32 via 169.254.1.1
          ip route add $RYU_IP/32 via 169.254.1.1 dev eth0

          # 6 bis. Retorno al clúster Kubernetes (POD y Service CIDR)
          ip route add 10.0.0.0/15      via 169.254.1.1   # Pods
          ip route add 10.152.183.0/24  via 169.254.1.1   # Services

          # 7. Ahora modificamos la ruta por defecto
          ip route del 0.0.0.0/0 via 169.254.1.1
          ip route add 0.0.0.0/0 via ${each.value.vcpegw}

          # 8. Ruta hacia la subred privada del cliente
          ip route add ${each.value.custprefix} via 192.168.255.253

          ################################  Interfaz pública + NAT
          /vnx_config_nat brint net${each.value.netnum}

          ################################ [4] BRWAN   (cpe ↔ wan)
          # WAN_IP ya está resuelto. Sólo queda crear el bridge y túneles.
          ip route add $WAN_IP/32 via 169.254.1.1
          ovs-vsctl add-br brwan
          ifconfig brwan mtu 1400          
          ifconfig brwan up     

           ## 3. Activar el modo SDN en VNF:wan"
        ovs-vsctl set bridge brwan protocols=OpenFlow10,OpenFlow12,OpenFlow13
        ovs-vsctl set-fail-mode brwan secure
        ovs-vsctl set bridge brwan other-config:datapath-id=0000000000000002
        ovs-vsctl set-controller brwan tcp:$RYU_IP:6633
        ovs-vsctl set-manager ptcp:6632

          #######  Conectar ambos bridges a Ryu ###
   ######################################

          ip link add cpewan type vxlan id 5 remote $WAN_IP dstport 8741 dev eth0
          ovs-vsctl add-port brwan cpewan
          ifconfig cpewan up

          # VXLAN entre sites (sr1 ↔ sr2)
          ip link add sr1sr2 type vxlan id 12 remote ${each.value.remotesite} dstport 8742 dev net${each.value.netnum}
          ovs-vsctl add-port brwan sr1sr2
          ifconfig sr1sr2 up

          #########################################
   

          sleep infinity
        EOT
      ]

       security_context {
      privileged = true
      capabilities { add = ["NET_ADMIN", "SYS_ADMIN"] }
    }
  }

  # Segundo contenedor: metrics exporter
  container {
    name  = "node-exporter"
    image = "quay.io/prometheus/node-exporter:latest"

    port {
      container_port = 9100
      name           = "metrics"
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
#########################################################################
#  Servicio headless para descubrir la IP del CPE                       #
#########################################################################

resource "kubernetes_service" "vnf_cpe" {
  for_each = local.vnf_cpe_instances

  metadata {
    name      = "vnf-cpe-service-${each.key}"
    namespace = "rdsv"
  }

  spec {
    cluster_ip = "None"
    selector   = { "k8s-app" = "vnf-cpe-${each.key}" }
  }
}
