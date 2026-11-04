# Install Cluster Components with Helm and Kustomize

The CKA asks you to "use Helm and Kustomize to install cluster components."  This page installs one component, [metrics-server](https://github.com/kubernetes-sigs/metrics-server), on the cluster from the [README](../README.md) twice: first with Helm, then with Kustomize.  metrics-server collects CPU and memory use from every kubelet, which is what `kubectl top` shows.

Start with a working cluster: finish the README through [Run a Test Workload](../README.md#run-a-test-workload), or through the upgrade.  It works on every size in [`examples`](../examples), including a single node.

During the exam you can open the [Helm docs](https://helm.sh/docs) as well as the Kubernetes docs, and the Kubernetes docs cover Kustomize.

## Why metrics-server Needs a Flag on This Cluster

metrics-server talks to each kubelet over HTTPS and checks the kubelet's certificate.  On a `kubeadm` cluster, each kubelet serves a self-signed certificate that the cluster's certificate authority didn't sign, so metrics-server refuses to connect.  The `--kubelet-insecure-tls` flag tells it to skip that check.  The metrics-server docs call the flag "for testing purposes only," which is fine for a practice lab.

Both installs below add that flag, each in its own way.

## Install metrics-server with Helm

[helm.sh: Installing Helm](https://helm.sh/docs/intro/install/)

Helm installs packages of Kubernetes manifests, called charts, and keeps track of each install, called a release.

***Perform the following steps on the Control Plane node, as `ubuntu`.***

**Install Helm from its Apt repository, with the steps from helm.sh:**

```bash
HELM_BUILDKITE_APT_KEY_ID="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"
sudo apt-get install curl gpg --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey > "${TMPDIR:-/tmp}/helm.asc"
# Ensure that the key ID matches to prevent a repository compromise from establishing an attacker controlled key
if [ "$(gpg --import --import-options=show-only --with-colons "${TMPDIR:-/tmp}/helm.asc" \
        | awk -F: '$1 == "fpr" {print $10}' | head -n 1)" != "${HELM_BUILDKITE_APT_KEY_ID}" ]; then
    echo "ERROR: Unexpected Helm APT key ID: potential key compromise"
    exit 1
fi
# Remove configuration left by earlier versions of these instructions
sudo rm -f /etc/apt/sources.list.d/helm-stable-debian.list /usr/share/keyrings/helm.gpg
sudo install -m 0644 -Dt /etc/apt/keyrings/ "${TMPDIR:-/tmp}/helm.asc"
sudo tee /etc/apt/sources.list.d/helm-stable-debian.sources > /dev/null <<EOF
Types: deb
URIs: https://packages.buildkite.com/helm-linux/helm-debian/any/
Suites: any
Components: main
Signed-By: /etc/apt/keyrings/helm.asc
EOF
sudo apt-get update
sudo apt-get install helm
helm version
```

The `exit 1` closes your shell if the key doesn't match, which is what you want.  If it happens, stop and check the helm.sh page.

**SAMPLE OUTPUT EXCERPT:**

```bash
version.BuildInfo{Version:"v4.3.0", GitCommit:"bec5b06ed841fe5269972d864d5177944fd5970f", GitTreeState:"clean", GoVersion:"go1.27.1", KubeClientVersion:"v1.37"}
```

**Add the metrics-server chart repository and find the chart:**

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm search repo metrics-server
```

**SAMPLE OUTPUT:**

```bash
"metrics-server" has been added to your repositories
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metrics-server" chart repository
Update Complete. ⎈Happy Helming!⎈
NAME                          CHART VERSION  APP VERSION  DESCRIPTION
metrics-server/metrics-server 3.14.0         0.9.0        Metrics Server is a scalable, efficient source ...
```

A chart takes settings, called values.  The chart's `args` value adds command-line flags to metrics-server.

**Install the chart into `kube-system`, with the flag:**

```bash
helm install metrics-server metrics-server/metrics-server --namespace kube-system --set "args={--kubelet-insecure-tls}"
kubectl -n kube-system rollout status deployment metrics-server
helm list -n kube-system
```

**SAMPLE OUTPUT EXCERPT:**

```bash
NAME: metrics-server
LAST DEPLOYED: Tue Nov  3 18:05:59 2026
NAMESPACE: kube-system
STATUS: deployed
REVISION: 1
...
deployment "metrics-server" successfully rolled out
NAME            NAMESPACE   REVISION  UPDATED                               STATUS    CHART                  APP VERSION
metrics-server  kube-system 1         2026-11-03 18:05:59.683314 -0600 CST  deployed  metrics-server-3.14.0  0.9.0
```

**Check that it works:**

```bash
kubectl top nodes
```

The first numbers can take a minute to show up.  Until then, you'll see `error: metrics not available yet`.

**SAMPLE OUTPUT:**

```bash
NAME               CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
control-plane-01   559m         27%      1892Mi          49%
worker-node-01     469m         23%      924Mi           24%
worker-node-02     154m         7%       809Mi           21%
```

Helm removes everything a release installed, so make room for the Kustomize install.

**Uninstall the release:**

```bash
helm uninstall metrics-server --namespace kube-system
```

**SAMPLE OUTPUT:**

```bash
release "metrics-server" uninstalled
```

## Install metrics-server with Kustomize

[kubernetes.io: Declarative Management of Kubernetes Objects Using Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)

Kustomize is built into `kubectl`.  It takes a set of manifests and changes them with patches, without editing the originals.  Here, the manifests are metrics-server's release file, and the patch adds the flag.

***Perform the following steps on the Control Plane node, as `ubuntu`.***

**Write a `kustomization.yaml` in its own folder:**

```bash
mkdir metrics-server
cat <<EOF > metrics-server/kustomization.yaml
resources:
  - https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.1/components.yaml
patches:
  - target:
      kind: Deployment
      name: metrics-server
    patch: |-
      - op: add
        path: /spec/template/spec/containers/0/args/-
        value: --kubelet-insecure-tls
EOF
```

The patch is a JSON patch: it adds (`op: add`) one entry to the end (`-`) of the first container's `args` list.

**Check what Kustomize builds, without applying it:**

```bash
kubectl kustomize metrics-server | grep -A7 "args:"
```

**SAMPLE OUTPUT:**

```bash
      - args:
        - --cert-dir=/tmp
        - --secure-port=10250
        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
        - --kubelet-use-node-status-port
        - --metric-resolution=15s
        - --kubelet-insecure-tls
        image: registry.k8s.io/metrics-server/metrics-server:v0.9.1
```

**Apply it, and check that it works:**

```bash
kubectl apply -k metrics-server
kubectl -n kube-system rollout status deployment metrics-server
kubectl top nodes
```

**SAMPLE OUTPUT:**

```bash
serviceaccount/metrics-server created
clusterrole.rbac.authorization.k8s.io/system:aggregated-metrics-reader created
clusterrole.rbac.authorization.k8s.io/system:metrics-server created
rolebinding.rbac.authorization.k8s.io/metrics-server-auth-reader created
clusterrolebinding.rbac.authorization.k8s.io/metrics-server:system:auth-delegator created
clusterrolebinding.rbac.authorization.k8s.io/system:metrics-server created
service/metrics-server created
deployment.apps/metrics-server created
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io created
Waiting for deployment "metrics-server" rollout to finish: 0 of 1 updated replicas are available...
deployment "metrics-server" successfully rolled out
NAME               CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
control-plane-01   301m         15%      1899Mi          49%
worker-node-01     156m         7%       932Mi           24%
worker-node-02     109m         5%       803Mi           21%
```

To remove it, run `kubectl delete -k metrics-server`.  Or leave it running: `kubectl top` comes in handy for the rest of your practice.
