# UPGRADE ROLLBACK GUIDE

Use this if the runtime upgrade causes regressions.

## Known Good Baseline

- Image tag: `openclaw:local`
- Current digest (after upgrade): `sha256:17b0be1e43702b6fd83c9af9455b2f19274150aa0ad1aa02c9955596e32b544c`
- Previous digest (before upgrade): `sha256:867baf0be96d051d3f9c70d82f044c2a936e3a832cb80e0b1f0eaf2177987481`
- Containers:
  - `hungreo-openclaw-openclaw-gateway-1`
  - `openclaw-suckhoe-openclaw-gateway-1`

## Fast Rollback (same host)

1. Re-tag previous known-good image (if it still exists locally):

```bash
docker image inspect sha256:867baf0be96d051d3f9c70d82f044c2a936e3a832cb80e0b1f0eaf2177987481 >/dev/null \
  && docker tag sha256:867baf0be96d051d3f9c70d82f044c2a936e3a832cb80e0b1f0eaf2177987481 openclaw:local
```

2. Restart both gateways:

```bash
/Users/hungdinh/bin/openclaw-restart-gateways.sh
```

3. Verify:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | grep -E "openclaw|suckhoe"
docker exec hungreo-openclaw-openclaw-gateway-1 node -p "require('./package.json').version"
docker exec openclaw-suckhoe-openclaw-gateway-1 node -p "require('./package.json').version"
tail -n 80 /tmp/openclaw-restart-gateways.err.log
```

## If old digest is missing locally

Rebuild old image from prior source snapshot (or use pinned stable tag previously verified),
tag it as `openclaw:local`, then run the same restart + verify commands above.

Current note:

- The pre-upgrade digest `sha256:867baf0be96d...` is no longer present locally on this host.
- Rollback now requires rebuilding/tagging a known-good image first.

## Config Safety Note

Ensure both `.env` and `.env.suckhoe` contain `OPENCLAW_GATEWAY_TOKEN` before restarting containers.
