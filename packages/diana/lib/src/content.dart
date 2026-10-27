/// Minimal content negotiation: an always-on `Accept` guard.
///
/// Diana does not negotiate representations — routes produce what they
/// produce. The pipeline only rejects requests whose `Accept` header
/// excludes the produced MIME type with an empty 406. `*/*` (every
/// browser's default) always passes.
library;

/// Whether [acceptHeader] accepts [mime] (`type/subtype`).
///
/// Understands `*/*` and `type/*` wildcards, and treats `q=0` entries as
/// exclusions; other quality values are ignored (no ranking).
bool acceptsMime(String acceptHeader, String mime) {
  final parts = mime.split('/');
  if (parts.length != 2) return true;
  final (type, subtype) = (parts[0].trim(), parts[1].trim());

  for (final entry in acceptHeader.split(',')) {
    final segments = entry.split(';');
    final pattern = segments.first.trim().toLowerCase();
    final rejected = segments.skip(1).any((param) {
      final p = param.trim().replaceAll(' ', '');
      return p == 'q=0' || p == 'q=0.0' || p == 'q=0.00' || p == 'q=0.000';
    });
    final matches =
        pattern == '*/*' || pattern == '$type/*' || pattern == '$type/$subtype';
    if (matches && !rejected) return true;
  }
  return false;
}
