# jambonz helm chart repository

This branch is served by GitHub Pages and is the published Helm chart
repository. It holds packaged charts (`*.tgz`) and the `index.yaml` that
describes them — the chart *source* lives on `main`.

```bash
helm repo add jambonz https://jambonz-selfhosting.github.io/helm-chart
helm repo update
helm search repo jambonz/jambonz --versions
helm install jambonz jambonz/jambonz --version <version> -n jambonz
```

Do not hand-edit `index.yaml`, and never replace a published `.tgz`: clients key
on the digest recorded in the index, so republishing a version makes upgrade
behaviour depend on which cache a client has. Publish a new chart version
instead.

Releases are published by `publish-chart.sh` in the fatp plugin, which merges the
index rather than regenerating it — regenerating drops every older version.
