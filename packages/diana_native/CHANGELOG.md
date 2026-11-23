# Changelog

## 0.16.0

- Initial release: `DianaNativeEngine`, a `DianaHttpEngine` that serves a
  Diana app through relic_native's Zig HTTP server. HTTPS from
  `server.ssl.*` (TLS 1.3 only), multi-isolate serving on one native
  server, `NativeOptions` re-exported for tuning.
