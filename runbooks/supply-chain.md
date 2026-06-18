# Supply chain verification runbook

Image release flow:

1. GitHub Actions builds `src/api`.
2. Trivy fails the workflow on fixed HIGH or CRITICAL vulnerabilities.
3. The image is pushed to GHCR only after scan passes.
4. Cosign signs the versioned tag with GitHub Actions OIDC keyless signing.
5. Sigstore Policy Controller verifies signatures at admission.

Useful checks:

```powershell
kubectl get clusterimagepolicy
kubectl apply --dry-run=server -f policies/tests/unsigned-api-pod.yaml
kubectl get rollout api -n demo -o jsonpath="{.spec.template.spec.containers[0].image}"
```

The namespace label `policy.sigstore.dev/include=true` controls where signature admission is enforced.
