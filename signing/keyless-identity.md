# Cosign keyless signing identity

This lab uses Sigstore keyless signing instead of committing a static public key.

- Issuer: `https://token.actions.githubusercontent.com`
- Subject: `https://github.com/ptduong04/temp/.github/workflows/build-push.yml@refs/heads/main`
- Signed image: `ghcr.io/ptduong04/w10-api:<version>`

The workflow gets an OIDC token from GitHub Actions and `cosign sign --yes` records the signature in the registry and transparency log. No private key is committed and no long-lived signing secret is required.
