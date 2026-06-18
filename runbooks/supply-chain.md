# Supply chain verification runbook

Image release flow:

1. GitHub Actions builds `src/api`.
2. Trivy fails the workflow on fixed HIGH or CRITICAL vulnerabilities.
3. The image is pushed to GHCR only after scan passes.
4. Cosign signs the versioned tag with GitHub Actions OIDC keyless signing.
5. Sigstore Policy Controller verifies signatures at admission with the GitHub Actions issuer/subject in `policies/cluster-image-policy.yaml`.

Useful checks:

```powershell
kubectl get clusterimagepolicy
kubectl apply --dry-run=server -f policies/tests/unsigned-api-pod.yaml
kubectl get rollout api -n demo -o jsonpath="{.spec.template.spec.containers[0].image}"
```

The namespace label `policy.sigstore.dev/include=true` controls where signature admission is enforced.
Add that label only after the API image tag in `app-api/rollout.yaml` has been signed by the workflow:

```powershell
kubectl label namespace demo policy.sigstore.dev/include=true --overwrite
```

This lab uses keyless signing, so there is no `cosign.pub` file and no long-lived private signing key in GitHub Secrets.
