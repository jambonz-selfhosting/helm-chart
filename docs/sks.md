# Deploying jambonz on Exoscale SKS

This guide walks you through deploying jambonz on an SKS cluster from start to finish.

## Prerequisites

- Exoscale account with permissions to create SKS clusters
- [Exoscale CLI](https://community.exoscale.com/documentation/tools/exoscale-command-line-interface/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [helm](https://helm.sh/docs/intro/install/)
- [terraform](https://www.terraform.io/downloads)

## Step 1: Create the Cluster

Use the terraform scripts to create an SKS cluster with the required nodepools:

https://github.com/jambonz-selfhosting/terraform/tree/main/exoscale/provision-sks-cluster

The terraform will create:
- SKS cluster with three nodepools: system, sip, and rtp
- Security groups for each nodepool
- Elastic IPs for SIP nodes (used by the eip-allocator init container)
- A `jambonz` namespace in the cluster
- A Kubernetes secret (`exoscale-eip-creds`) containing your Exoscale API credentials, used by the eip-allocator to assign Elastic IPs to SIP nodes

After terraform completes, set the generated kubeconfig as active:
```bash
export KUBECONFIG=./kubeconfig
```

Verify connectivity:
```bash
kubectl get nodes -o wide
```

You should see nodes from all three nodepools (system, sip, rtp).

Note the terraform outputs — you'll need several values when installing the Helm chart:
```bash
terraform output
```

Key outputs:
- `system_nodepool_instance_pool_id` — needed for the Traefik LoadBalancer annotation
- `eip_allocator_helm_values` — contains the Helm values for eip-allocator configuration

## Step 2: Install jambonz

> **Note**: The `jambonz` namespace is already created by Terraform — no need to create it manually.

Install the Traefik ingress controller. Use the `system_nodepool_instance_pool_id` from the terraform output:
```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik --namespace jambonz \
  --set "service.annotations.service\.beta\.kubernetes\.io/exoscale-loadbalancer-service-instancepool-id=<instance-pool-id>"
```

### Storage class configuration

Exoscale's CSI driver creates two storage classes (`exoscale-sbs` and `exoscale-bs-retain`) but does not mark either as default. You must specify one when installing the chart via `storageClassName`.

You can verify available storage classes with:
```bash
kubectl get sc
```

### EIP allocator credentials

The Terraform script creates a Kubernetes secret called `exoscale-eip-creds` in the `jambonz` namespace containing your Exoscale API key and secret. The eip-allocator init container uses these credentials to assign Elastic IPs to SIP nodes at startup — you do not need to provide your Exoscale credentials again when installing the Helm chart.

You can verify the secret was created:
```bash
kubectl -n jambonz get secret exoscale-eip-creds
```

### Install the chart

Create a values file (e.g. `my-values.yaml`) with your configuration. At minimum you need to set:

```yaml
cloud: exoscale
baseUrl: jambonz.example.com
storageClassName: exoscale-sbs

sbc:
  eipAllocator:
    enabled: true
    sipEipGroupRole: <cluster-name>-sip-node
    rtpEipGroupRole: <cluster-name>-rtp-node
    exoscaleApiKeySecret: exoscale-eip-creds
    exoscaleZone: <your-zone>
```

Replace `<cluster-name>` with the SKS cluster name (e.g. `jambonz-voip-sks-cluster`) and `<your-zone>` with the Exoscale zone (e.g. `ch-gva-2`). These values are available from `terraform output eip_allocator_helm_values`.

Then install:
```bash
helm install jambonz --namespace=jambonz -f my-values.yaml .
```

This automatically sets up hostnames for all portals (`jambonz.example.com`, `api.jambonz.example.com`, `grafana.jambonz.example.com`, `homer.jambonz.example.com`).

It takes a few minutes for storage to be provisioned and databases to be initialized. Monitor progress:
```bash
kubectl -n jambonz get pods
```

Wait until all pods show `Running` or `Completed` status before continuing.

## Step 3: Set up DNS

Get the load balancer IP:
```bash
kubectl -n jambonz get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Create DNS A records in your DNS provider, all pointing to this IP:
- `jambonz.example.com` (webapp)
- `api.jambonz.example.com` (API)
- `grafana.jambonz.example.com` (Grafana)
- `homer.jambonz.example.com` (Homer)

## Step 4: Enable HTTPS

Install cert-manager:
```bash
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.5.3/cert-manager.crds.yaml
kubectl create namespace cert-manager
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.5.3/cert-manager.yaml
```

Add the following to your values file:
```yaml
global:
  traefik:
    tls:
      enabled: true
      clusterIssuer: letsencrypt-prod
      email: your@email.com
```

Upgrade the cluster:
```bash
helm -n jambonz upgrade jambonz . -f my-values.yaml
```

Verify certificates have been issued (this may take 1-3 minutes):
```bash
kubectl -n jambonz get certificate
```

## Step 5: Log In

### jambonz portal
Go to `https://<your-webapp-hostname>` and log in with user `admin` and password `admin`. You will be prompted to reset the password.

### Grafana
Go to `https://<your-grafana-hostname>` and log in with user `admin` and password `admin`. You will be prompted to reset the password.

### Homer
Homer access is generally not needed since pcaps are available in the jambonz portal under Recent Calls. If you need it, go to `https://<your-homer-hostname>` with user `admin` and password `sipcapture`.

## Next Steps

### View pod logs in Grafana

To view Kubernetes pod logs in Grafana, add Loki as a datasource:
1. Navigate to **Connections > Datasources**
2. Search for Loki and add it
3. Set the connection URL to: `http://loki-stack.logging.svc.cluster.local:3100`
4. Click **Save and test**

To view logs, go to the **Explore** tab, set the datasource to Loki, and use label filters.

### Enable SIPS over TLS and Secure WebSockets

Skip this section if you only need standard SIP over UDP/TCP.

Since Traefik doesn't front SIP traffic, we use a DNS challenge with Let's Encrypt to generate TLS certificates.

1. Add the following to your values file:
```yaml
sbc:
  sip:
    ssl:
      enabled: true
      hostname: sip.jambonz.example.com
```

2. Generate the certificate using certbot:
```bash
certbot certonly --manual --preferred-challenges=dns \
  --email your@email.com \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --agree-tos \
  -d sip.jambonz.example.com \
  -d *.sip.jambonz.example.com
```

3. When prompted, add two TXT records to your DNS. The certificate will be generated at:
```
Certificate: /etc/letsencrypt/live/sip.jambonz.example.com/fullchain.pem
Key:         /etc/letsencrypt/live/sip.jambonz.example.com/privkey.pem
```

4. Copy the certificate and key contents into your values file under `sbc.sip.ssl.crt` and `sbc.sip.ssl.key`.

5. Upgrade the cluster:
```bash
helm -n jambonz upgrade jambonz . -f my-values.yaml
```

The sbc-sip pod will restart with drachtio listening on:
- 5061/tcp (SIP over TLS)
- 8443/tcp (SIP over WSS)

6. Add DNS A records for the SIP hostname pointing to the public IPs of nodes in the SIP nodepool.

See the [Configuration Reference](../README.md#configuration-reference) for additional options.