########################################
# Pod Ryu – uno por site (revisado)
########################################
resource "kubernetes_pod" "knf_ctrl" {
  for_each = var.vnf_sites            # { site1 = {...}, site2 = {...} }

  metadata {
    name      = "knf-ctrl-${each.key}"
    namespace = "rdsv"
    labels    = { "k8s-app" = "knf-ctrl-${each.key}" }
  }

  spec {
    ##################################
    # Contenedor principal Ryu
    ##################################
    container {
      name        = "ryu"
      image       = "abelrodrigo123/vnf-ryu:latest"
      working_dir = "/root"

      # Exponemos los puertos REST 
      port {
        name           = "rest"
        container_port = 8080
      }

       port {
        name           = "openflow"
        container_port = 6633
      }


      # Arrancamos Ryu sin lógica extra: las reglas se inyectan desde fuera
      command = [
        "sh", "-c", <<-EOSH
          set -e
          # Garantizamos que flowmanager sea importable
          [ -f flowmanager/__init__.py ] || mkdir -p flowmanager && touch flowmanager/__init__.py
          export PYTHONPATH=/root:$PYTHONPATH

          echo "🚀 Lanzando Ryu controller…"
          exec /usr/local/bin/ryu-manager \
            --ofp-tcp-listen-port 6633 \
            flowmanager.flowmanager \
            ryu.app.rest_conf_switch \
            ryu.app.ofctl_rest \
            ryu.app.rest_qos \
            qos_simple_switch_13
        EOSH
      ]
    }
  }
}

############################################
# Service  knf-ctrl 
############################################
resource "kubernetes_service" "knf_ctrl" {
  for_each = var.vnf_sites

  metadata {
    name      = "knf-ctrl-${each.key}-svc"     
    namespace = "rdsv"
  }

  spec {
    type     = "NodePort"                   
    selector = { "k8s-app" = "knf-ctrl-${each.key}" }

    # Puerto REST (8080) — 
    port {
      name        = "rest"
      port        = 8080
      target_port = 8080
      node_port   = each.key == "site1" ? 31880 : 31881
    }

    # Puerto OpenFlow (6633)
    port {
      name        = "openflow"
      port        = 6633
      target_port = 6633
    }
  }
}
