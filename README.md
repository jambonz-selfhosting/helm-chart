# jambonz Helm Chart

Helm chart for deploying [jambonz](https://jambonz.org) (open-source CPaaS) on Kubernetes.

## Architecture Overview

Running a VoIP platform in Kubernetes requires special configuration due to the nature of SIP and RTP protocols.

### Why Special Nodepools Are Needed

Standard Kubernetes networking doesn't work well for VoIP traffic because:

- **SIP protocol limitations**: SIP messages contain IP addresses in the message headers (e.g Contact header) and body (SDP). When traffic passes through standard k8s networking/NAT, the IP addresses in the SIP headers don't match the actual source, breaking call setup.
- **No ingress controller support**: Unlike HTTP, there are no mature ingress controllers for SIP traffic.
- **RTP port requirements**: RTP media streams require predictable port ranges that can be opened in firewalls.

The solution is to run SIP and RTP workloads on dedicated nodepools with **host networking** enabled, allowing pods to use the node's network interface directly. Creating a cluster with these dedicated nodepools is a firm requirement of running jambonz in Kubernetes.

> Don't worry: the cluster setup is largely handled by the terraform scripts linked in each provider guide below.

### Required Nodepools

| Nodepool | Host Networking | Purpose | Pods |
|----------|-----------------|---------|------|
| Default | No | Core jambonz services | api-server, webapp, feature-server, mysql, redis, grafana, etc. |
| SIP | Yes | SIP signaling | sbc-sip daemonset |
| RTP | Yes | Media processing | sbc-rtp daemonset |

> **Note**: For smaller deployments, SIP and RTP can share a single nodepool. However, separate nodepools are recommended for production.

## Getting Started

Choose your cloud provider for a complete step-by-step deployment guide:

- [AWS EKS](./docs/eks.md)
- [Google Cloud GKE](./docs/gke.md)
- [Azure AKS](./docs/aks.md)
- [Exoscale SKS](./docs/sks.md)

## Configuration Reference

The table below lists the most commonly configured values. Set these with `--set` flags during `helm install` or by editing `values.yaml` directly. See `values.yaml` for the full list of options.

### Required

| Value | Description |
|-------|-------------|
| `cloud` | Cloud provider: `aws`, `gcp`, `azure`, or `exoscale` |
| `baseUrl` | Your domain (e.g. `jambonz.example.com`) |

All portal hostnames are derived automatically from `baseUrl`:

| Portal | Hostname |
|--------|----------|
| Webapp | `jambonz.example.com` |
| API | `api.jambonz.example.com` |
| Grafana | `grafana.jambonz.example.com` |
| Homer | `homer.jambonz.example.com` |

### Security

These ship with preset defaults. **Change them before any production deployment.**

| Value | Description |
|-------|-------------|
| `jwt.secret` | JWT signing secret (base64-encoded) |
| `db.mysql.secret` | MySQL password (base64-encoded) |
| `monitoring.postgres.secret` | Homer Postgres password (base64-encoded) |
| `drachtio.secret` | Drachtio shared secret (base64-encoded) |

### Features

| Value | Description | Default |
|-------|-------------|---------|
| `global.traefik.tls.enabled` | Enable HTTPS for web portals via cert-manager + Let's Encrypt | `false` |
| `global.traefik.clusterIssuer` | Cert-manager ClusterIssuer name | `letsencrypt-prod` |
| `global.traefik.email` | Email address for Let's Encrypt registration | — |
| `global.cassandra.enabled` | Use Cassandra backend for Jaeger trace storage | `false` |
| `global.logging.enabled` | Deploy Loki + Promtail for centralized pod logging | `true` |
| `sbc.sip.ssl.enabled` | Enable SIPS (TLS) and Secure WebSocket listeners on the SBC | `false` |
| `rtpengine.recordings.enabled` | Enable call recording to persistent storage | `false` |

### Scaling

| Value | Description | Default |
|-------|-------------|---------|
| `featureServer.replicas` | Number of feature-server (call processing) pods | `3` |
| `api.replicas` | Number of API server pods | `1` |
| `sbcInbound.replicas` | Number of inbound call-routing pods | `1` |
| `sbcOutbound.replicas` | Number of outbound call-routing pods | `1` |
