# Secret rotation runbook

Lab mode uses the External Secrets fake provider in `eso/secret-store.yaml`.

1. Change `spec.provider.fake.data[0].value` in `eso/secret-store.yaml`.
2. Commit and push the change.
3. Wait for ArgoCD `eso-config` to sync.
4. Verify the Kubernetes Secret updates:

```powershell
kubectl get secret db-secret -n demo -o jsonpath="{.data.password}" | %{ [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }
```

5. Verify API pods did not restart:

```powershell
kubectl get pods -n demo -l app=api
```

The API mounts the Secret as a volume at `/var/run/secrets/db/password`, so kubelet refreshes the projected file without restarting the pod.
