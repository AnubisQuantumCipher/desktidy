# DeskTidy website source

This Next.js site is the public truth surface for DeskTidy. It currently states
the bounded local-deployment result and directs readers to repository evidence;
it does not offer an installer, waitlist, payment flow, or public native release.

## Local verification

```bash
npm ci
npm run lint
npm run build
```

The site has no database dependency or email-collection API. It sets no
application cookies and includes no analytics or tracking script. Hosting
infrastructure may still process ordinary request logs as described on the
privacy page.

## Deployment boundary

Source verification is not deployment evidence. Before deploying, bind the
deployment to an exact repository commit, run the commands above from a clean
checkout, and confirm the rendered copy still matches `README.md`,
`SECURITY.md`, and `docs/evidence/R2_LOCAL_PRODUCTION_DEPLOYMENT.md`.
