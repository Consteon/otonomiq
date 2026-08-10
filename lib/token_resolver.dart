import 'global.dart'; // transactionStore (declared `dynamic` — no type import needed)
import 'widget/driver_home_support.dart'; // resolveDriverCurlyTokens

/// Unified entry point for the five token grammars in the SDUI pipeline.
///
/// ## Grammars (canonical reference)
///
/// | Syntax | Example | Resolver | Semantics |
/// |--------|---------|----------|-----------|
/// | `{token}` | `{userVid}`, `{activeTrip}` | [curly] → `resolveDriverCurlyTokens` | Empty resolution leaves literal (pending-safe) |
/// | `<KEY>` | `<APPROVAL_STATUS>` | [screenTxMarkers] | Absent key leaves literal; present-with-empty resolves to `''` |
/// | `{{POS(n)}}` / `{{DOC(n)}}` | `{{POS(3)}}` | `replacePlaceholders` (api.dart) — not wrapped here | Positional / doc-field substitution |
/// | `◁N▷` / `◀N▶` | `◁2▷` | `resolveValueTokens` (table_repository.dart) — not wrapped here | Form-ref / system-ref by 1-based index |
/// | `#KEY` reads | `#VID`, `#TX_LOCK` | Direct `transactionStore.state.screenTx` reads — not wrapped here | Session-long merged state |
///
/// ## Canonical composition order
///
/// As implemented in `saveSend` (api.dart, eventString block):
/// ```
/// curly → replacePlaceholders → screenTxMarkers
/// ```
///
/// ## Dialect difference (`<KEY>` vs `{token}`)
///
/// `<KEY>` treats empty-string as a valid resolution (`''`); an absent key
/// leaves the marker literal. `{token}` treats empty as unresolved and leaves
/// the literal — this is the pending-safe guard that lets
/// `filterByMultiClause`'s `value.contains('{')` detect unresolved state.
///
/// ## Side effects
///
/// [curly] delegates to `resolveDriverCurlyTokens`, which may trigger a
/// deferred `_deferActiveTripPublish` for the `{activeTrip}` token when a
/// compute-on-read fallback fires. This is load-bearing for the
/// custody-mode-toggle flow and must not be removed.
///
/// ## Adoption rule
///
/// New widgets use `TokenResolver`. Existing regex copies migrate on-touch
/// only (F2). The "unresolved token" production bug class (renderer never
/// called resolveDriverCurlyTokens) is the reason new widgets should go
/// through this module rather than hand-rolling token substitution.
class TokenResolver {
  TokenResolver._(); // no instantiation

  /// Resolve `<KEY>` markers against [transactionStore.state.screenTx].
  ///
  /// Semantics: `<FOO>` with key `FOO` present → `screenTx['FOO'].toString()`,
  /// even if empty. Key absent → literal `<FOO>` left in place.
  /// Regex accepts `[a-zA-Z_][a-zA-Z0-9_]*` (snake_case safe).
  static String screenTxMarkers(String text) {
    var screenTx = transactionStore.state.screenTx;
    return text.replaceAllMapped(RegExp(r'<([a-zA-Z_][a-zA-Z0-9_]*)>'), (m) {
      String key = m.group(1)!;
      return screenTx[key]?.toString() ?? m.group(0)!;
    });
  }

  /// Resolve `{token}` markers. Delegates to [resolveDriverCurlyTokens].
  ///
  /// Body is NOT moved in F1: it depends on private `_deferActiveTripPublish`,
  /// `computeActiveTripDocId`, `mapTableContent`, `getDriverHomeState` —
  /// moving it would drag driver domain internals and expose privates.
  /// The deferred activeTrip publish side effect stays inside, by design.
  static String curly(String raw, String scrName) =>
      resolveDriverCurlyTokens(raw, scrName);
}
