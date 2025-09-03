# TFM – Proyecto Terraform para SD-WAN
## Descripción del proyecto
Este proyecto implementa una arquitectura **SD-WAN (Software-Defined Wide Area Network)** utilizando **infraestructura como código (IaC)** como **Terraform**, controladores SDN con **Ryu**, y monitoreo con **Prometheus** y **Grafana**.
La solución se compone de múltiples **KNFs (Kubernetes Network Functions)** que representan funciones de red virtualizadas, desplegadas automáticamente mediante scripts de Terraform.
Este proyecto tiene como objetivo configurar los switches dentro de las KNFs para que sean controlados mediante OpenFlow desde el controlador SDN Ryu. Se busca garantizar la conectividad IPv4 dentro de la red corporativa y su acceso a Internet, además de gestionar la calidad del servicio mediante la API REST de Ryu. 

La figura a continuación representa la arquitectura del entorno implementado, detallando los componentes clave y sus interacciones dentro de la red. A partir de esta base, se introdujeron modificaciones que permitieron integrar un controlador RYU alojado en una KNF dedicada, así como gestionar la calidad de servicio (QoS) mediante la aplicación qos_simpleswitch_13.py.

<img width="1058" height="461" alt="image" src="https://github.com/user-attachments/assets/f820e6cd-a188-4587-9c76-3857c9dcb958" />


## Componentes Principales
- **KNF:access, KNF:cpe, KNF:wan**  
  Funciones de red virtualizadas (VNFs) configuradas con Terraform. Representan nodos de acceso, operación y conectividad.

- **Ryu**  
  Controlador SDN que gestiona las reglas de enrutamiento y reenvío dinámicamente en la red. Controla el flujo de tráfico a través de OpenFlow.

- **Prometheus**  
  Sistema de monitoreo que recopila métricas en tiempo real de los diferentes PODs, incluyendo tráfico, latencia y disponibilidad.

- **Grafana**  
  Plataforma de visualización que genera dashboards gráficos basados en los datos recolectados por Prometheus. Permitirá analizar el comportamiento de las KNFs.

La siguiente imágen muestra los distintos servicios configurados dentro de cada uno de las Centrales de proximidad mediante terraform (K8s).

<img width="1132" height="686" alt="image" src="https://github.com/user-attachments/assets/cf3e3bd7-7eaf-49eb-a970-295dd15e96b8" />

---

## 🛠️ Requisitos

- [Terraform](https://www.terraform.io/downloads.html) v1.x  
- [Git](https://git-scm.com/)  
- Cuenta en GitHub  
- Acceso a proveedor (AWS, GCP, VMware, etc.)

---
## 🛠️ Instalación y Configuración

1. **Clonar el repositorio:**

    ```bash
    git clone https://github.com/jimmyto-09/TFM.git
    cd terraformv1
    ```

2. **Inicializa Terraform:**

    ```bash
    terraform init
    ```

3. **Previsualiza los cambios:**

    ```bash
    terraform plan
    ```

4. **Aplicar la configuración**

    ```bash
    terraform plan
    ```

5. **Aplicar las reglas y qos**

    ```bash
   chmod +x reglas.sh
   ./reglas.sh
   chmod +x qos.sh
   ./qos.sh
    ```

---

##  Monitoreo y Visualización

Una vez desplegada la infraestructura, puedes acceder a los paneles de monitoreo y métricas a través de los siguientes servicios:

### Grafana
- **URL:** [http://localhost:3000](http://localhost:3000)
- **Usuario por defecto:** `admin`
- **Contraseña por defecto:** `admin`
- Permite visualizar dashboards con métricas de tráfico, estado de los KNFs, uso de recursos, etc.

### Prometheus
- **URL:** [http://localhost:9090](http://localhost:9090)
- Interfaz para:
  - Consultar métricas en tiempo real
  - Ver el estado de los targets monitorizados





