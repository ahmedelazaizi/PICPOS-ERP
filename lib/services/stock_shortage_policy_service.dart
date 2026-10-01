/// Stock-Shortage Policy Service
///
/// Controls what happens when an auto-deplete sale needs more raw material
/// than is currently in stock. Resolved via a three-tier lookup
/// (FR-016, FR-017):
///
///   policy = perTerminalMap[shift.posTerminalId]
///         ?? perBranchMap[warehouse.branchId]
///         ?? globalDefault                            (default = allowNegative)
///
/// Settings keys (all stored in the existing app_settings table — no schema
/// change to the settings table itself):
///   - `stock_shortage_policy`               TEXT
///   - `stock_shortage_policy_per_branch`    TEXT (JSON map, branchId -> policy)
///   - `stock_shortage_policy_per_terminal`  TEXT (JSON map, terminalId -> policy)
///
/// Feature 009 / Phase 2 Foundational (T008).
library;

import 'dart:convert';

import '../core/i18n/tr.dart';
import '../domain/repositories/settings_repository.dart';

enum StockShortagePolicy {
  /// Raise InsufficientStockException; the sale transaction rolls back.
  block,

  /// Log a warning and proceed; the raw material's stock can go negative.
  /// Default — minimizes friction at upgrade time per RD-1 spirit.
  allowNegative,

  /// Log a warning, deduct only what's available so the resulting stock
  /// is exactly 0. The remainder of the required qty is NOT charged to
  /// COGS (asymmetric — accepted trade-off, documented in tasks.md).
  clampToZero,
}

extension StockShortagePolicyName on StockShortagePolicy {
  /// Stable lowercase wire string. Stored in settings JSON maps and parsed
  /// back via [StockShortagePolicyService.fromName].
  String get wireName {
    switch (this) {
      case StockShortagePolicy.block:
        return 'block';
      case StockShortagePolicy.allowNegative:
        return 'allow_negative';
      case StockShortagePolicy.clampToZero:
        return 'clamp_to_zero';
    }
  }

  /// Localized label for UI display. The stable [wireName] remains unchanged.
  String get displayLabel {
    switch (this) {
      case StockShortagePolicy.block:
        return tr('منع البيع');
      case StockShortagePolicy.allowNegative:
        return tr('تحذير مع السماح بالسالب');
      case StockShortagePolicy.clampToZero:
        return tr('تحذير وإيقاف الخصم عند صفر');
    }
  }
}

class StockShortagePolicyService {
  static const _globalKey = 'stock_shortage_policy';
  static const _perBranchKey = 'stock_shortage_policy_per_branch';
  static const _perTerminalKey = 'stock_shortage_policy_per_terminal';

  /// Default when nothing is configured. Per FR-016 / RD-1 spirit.
  static const StockShortagePolicy defaultPolicy = StockShortagePolicy.allowNegative;

  // In-memory cache of the parsed JSON maps. Invalidated on save.
  static StockShortagePolicy? _cachedGlobal;
  static Map<int, StockShortagePolicy>? _cachedPerBranch;
  static Map<int, StockShortagePolicy>? _cachedPerTerminal;

  /// Convert a wire string back to enum. Returns null for unknown strings
  /// so callers can fall back to the default rather than crash.
  static StockShortagePolicy? fromName(String? raw) {
    if (raw == null) return null;
    switch (raw) {
      case 'block':
        return StockShortagePolicy.block;
      case 'allow_negative':
        return StockShortagePolicy.allowNegative;
      case 'clamp_to_zero':
        return StockShortagePolicy.clampToZero;
      default:
        return null;
    }
  }

  /// Load all three tiers from settings (with caching). Call once per
  /// orchestrator invocation, not per line.
  // ignore: unused_element
  static Future<void> _ensureLoaded(ISettingsRepository settings) =>
      _ensureLoadedWith(settings.getSetting);

  /// Variant of [_ensureLoaded] that takes a raw setting-getter, so callers
  /// without an [ISettingsRepository] in scope (e.g. the sales orchestrator
  /// holding only an [AppDatabase]) can drive the cache. Feature 009 / T025.
  static Future<void> _ensureLoadedWith(
    Future<String?> Function(String) get,
  ) async {
    if (_cachedGlobal != null &&
        _cachedPerBranch != null &&
        _cachedPerTerminal != null) {
      return;
    }
    _cachedGlobal = fromName(await get(_globalKey)) ?? defaultPolicy;
    _cachedPerBranch = await _loadMapWith(get, _perBranchKey);
    _cachedPerTerminal = await _loadMapWith(get, _perTerminalKey);
  }

  // ignore: unused_element
  static Future<Map<int, StockShortagePolicy>> _loadMap(
    ISettingsRepository settings,
    String key,
  ) =>
      _loadMapWith(settings.getSetting, key);

  static Future<Map<int, StockShortagePolicy>> _loadMapWith(
    Future<String?> Function(String) get,
    String key,
  ) async {
    final raw = await get(key);
    if (raw == null || raw.isEmpty) return const <int, StockShortagePolicy>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <int, StockShortagePolicy>{};
      final out = <int, StockShortagePolicy>{};
      decoded.forEach((k, v) {
        final id = int.tryParse(k.toString());
        final p = fromName(v?.toString());
        if (id != null && p != null) out[id] = p;
      });
      return out;
    } catch (_) {
      // Corrupted JSON — fall back gracefully to no overrides.
      return const <int, StockShortagePolicy>{};
    }
  }

  /// Resolve the active policy for a sale context.
  ///
  /// Priority (FR-017):
  ///   1. Per-terminal override   (terminalId may be null for non-POS sales)
  ///   2. Per-branch override     (branchId may be null for warehouse-less rows)
  ///   3. Global default
  static Future<StockShortagePolicy> resolve(
    ISettingsRepository settings, {
    int? terminalId,
    int? branchId,
  }) =>
      resolveWith(
        get: settings.getSetting,
        terminalId: terminalId,
        branchId: branchId,
      );

  /// Variant of [resolve] that takes a raw setting-getter — used by callers
  /// that don't carry an [ISettingsRepository] (e.g. the sales orchestrator
  /// holding only an [AppDatabase]). Feature 009 / T025.
  static Future<StockShortagePolicy> resolveWith({
    required Future<String?> Function(String) get,
    int? terminalId,
    int? branchId,
  }) async {
    await _ensureLoadedWith(get);
    if (terminalId != null) {
      final t = _cachedPerTerminal![terminalId];
      if (t != null) return t;
    }
    if (branchId != null) {
      final b = _cachedPerBranch![branchId];
      if (b != null) return b;
    }
    return _cachedGlobal!;
  }

  /// The policy a SALE actually runs under — [resolveWith] plus the legacy
  /// `enable_negative_sales` fallback for installs that never configured any
  /// shortage-policy tier (Feature 009 / T025, Constitution I).
  ///
  /// Single source for the sales orchestrator (which passes the allowance down
  /// to the sold item's own stock deduction) and the POS "out of stock" guard
  /// (`enableNegativeSalesProvider`), so the till never warns about — or the
  /// save never rejects — a sale the configured policy allows.
  static Future<StockShortagePolicy> resolveForSaleWith({
    required Future<String?> Function(String) get,
    int? terminalId,
    int? branchId,
  }) async {
    final resolved = await resolveWith(
      get: get,
      terminalId: terminalId,
      branchId: branchId,
    );
    return await _legacyFallbackWith(get) ?? resolved;
  }

  /// The global-tier policy the settings picker must DISPLAY — the value
  /// [resolveForSaleWith] actually applies to a sale with no branch/terminal
  /// override.
  ///
  /// The picker used to show [defaultPolicy] (`allowNegative`) whenever
  /// `stock_shortage_policy` was unsaved, while a fresh install's sales fall
  /// back to `enable_negative_sales` (false → `block`): the screen said
  /// "allow" and the till blocked. Reads settings directly (no cache) so the
  /// screen never shows a stale value.
  static Future<StockShortagePolicy> effectiveGlobalWith(
    Future<String?> Function(String) get,
  ) async {
    return await _legacyFallbackWith(get) ??
        fromName(await get(_globalKey)) ??
        defaultPolicy;
  }

  /// Legacy `enable_negative_sales` policy when NO shortage-policy tier was
  /// ever configured; `null` once any tier is saved.
  static Future<StockShortagePolicy?> _legacyFallbackWith(
    Future<String?> Function(String) get,
  ) async {
    for (final key in const [_globalKey, _perBranchKey, _perTerminalKey]) {
      final raw = await get(key);
      if (raw != null && raw.isNotEmpty) return null;
    }
    final legacy = await get('enable_negative_sales');
    return legacy == 'true'
        ? StockShortagePolicy.allowNegative
        : StockShortagePolicy.block;
  }

  /// Save the global default. Invalidates cache.
  static Future<void> saveGlobal(
    ISettingsRepository settings,
    StockShortagePolicy policy,
  ) async {
    await settings.saveSetting(_globalKey, policy.wireName);
    _cachedGlobal = null; // force reload
  }

  /// Save the per-branch JSON map. Invalidates cache.
  static Future<void> savePerBranch(
    ISettingsRepository settings,
    Map<int, StockShortagePolicy> map,
  ) async {
    final encoded = jsonEncode(
      map.map((k, v) => MapEntry(k.toString(), v.wireName)),
    );
    await settings.saveSetting(_perBranchKey, encoded);
    _cachedPerBranch = null;
  }

  /// Save the per-terminal JSON map. Invalidates cache.
  static Future<void> savePerTerminal(
    ISettingsRepository settings,
    Map<int, StockShortagePolicy> map,
  ) async {
    final encoded = jsonEncode(
      map.map((k, v) => MapEntry(k.toString(), v.wireName)),
    );
    await settings.saveSetting(_perTerminalKey, encoded);
    _cachedPerTerminal = null;
  }

  /// Force-clear the cache. Used by tests; production code calls
  /// `save*` which invalidates implicitly.
  static void resetCacheForTest() {
    _cachedGlobal = null;
    _cachedPerBranch = null;
    _cachedPerTerminal = null;
  }
}
