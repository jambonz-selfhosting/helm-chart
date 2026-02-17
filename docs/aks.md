# Deploying jambonz on Azure AKS

This guide walks you through deploying jambonz on an AKS cluster from start to finish.

## Prerequisites

- Azure account with permissions to create AKS clusters
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [helm](https://helm.sh/docs/intro/install/)
- [terraform](https://www.terraform.io/downloads)

## Step 1: Create the Cluster

Use the terraform scripts to create an AKS cluster with the required nodepools:

https://github.com/jambonz-selfhosting/terraform/tree/main/azure

The terraform will create:
- AKS cluster with default nodepool
- SIP nodepool with appropriate labels, taints, and network security rules
- RTP nodepool with appropriate labels, taints, and network security rules

After terraform completes, configure kubectl:
```bash
az aks get-credentials --resource-group <resource-group> --name <cluster-name>
```

Verify connectivity:
```bash
kubectl get nodes -o wide
```

You should see nodes from all three nodepools (default, sip, rtp).

## Step 2: Install jambonz

Create a namespace:
```bash
kubectl create namespace jambonz
```

Install the Traefik ingress controller:
```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik --namespace jambonz
```

Install the jambonz helm chart. Replace the domain with your own:
```bash
helm install jambonz --namespace=jambonz \
--set "cloud=azure" \
--set "baseUrl=jambonz.example.com" \
.
```

This automatically sets up hostnames for all portals (`jambonz.example.com`, `api.jambonz.example.com`, `grafana.jambonz.example.com`, `homer.jambonz.example.com`).

It takes a few minutes for storage to be provisioned and databases to be initialized. Monitor progress:
```bash
kubectl -n jambonz get pods
```

Wait until all pods show `Running` or `Completed` status before continuing.

## Step 3: Set up DNS

Get the load balancer public IP:
```bash
kubectl -n jambonz get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

You can also find it in the Azure portal under **Load balancers**.

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

Edit `values.yaml` and set:
- `global.traefik.tls.enabled` to `true`
- `global.traefik.clusterIssuer` to `letsencrypt-prod`
- `global.traefik.email` to your email address (shared with Let's Encrypt)

Upgrade the cluster:
```bash
helm -n jambonz upgrade jambonz .
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

1. Edit `values.yaml` and set `sbc.sip.ssl.enabled` to `true` and `sbc.sip.ssl.hostname` to your SIP hostname (e.g. `sip.jambonz.example.com`).

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

4. Copy the certificate and key contents into `values.yaml` under `sbc.sip.ssl.crt` and `sbc.sip.ssl.key`.

5. Upgrade the cluster:
```bash
helm -n jambonz upgrade jambonz .
```

The sbc-sip pod will restart with drachtio listening on:
- 5061/tcp (SIP over TLS)
- 8443/tcp (SIP over WSS)

6. Add DNS A records for the SIP hostname pointing to the public IPs of nodes in the SIP nodepool.

### Enable call recording

Edit `values.yaml` and set `rtpengine.recordings.enabled` to `true`, then upgrade:
```bash
helm -n jambonz upgrade jambonz .
```

See the [Configuration Reference](../README.md#configuration-reference) for additional options.
