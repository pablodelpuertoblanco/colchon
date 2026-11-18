import 'models.dart';

// ---------------------------------------------------------------------------
// Patrimonio: lo que tienes (planes, acciones, cuentas de ahorro...) menos
// lo que debes. Es el bloque "INMOVILIZADO" del Excel: cada mes se anota el
// valor de cada cosa y el último valor se arrastra hasta que se anota otro.
// ---------------------------------------------------------------------------

/// Un bien o una deuda.
class AssetInfo {
  const AssetInfo({
    required this.id,
    required this.name,
    required this.emoji,
    required this.kind,
    this.sortOrder = 0,
    this.isArchived = false,
  });
  final String id;
  final String name;
  final String emoji;
  final AssetKind kind;
  final int sortOrder;
  final bool isArchived;

  bool get isLiability => kind == AssetKind.liability;
}

/// Valor anotado de un bien o deuda en un mes.
class AssetValue {
  const AssetValue({required this.assetId, required this.year, required this.month, required this.cents});
  final String assetId;
  final int year;
  final int month;
  final int cents;

  int get monthIndex => monthIndexOf(year, month);
}

/// Mes como número correlativo para comparar (año * 12 + mes − 1).
int monthIndexOf(int year, int month) => year * 12 + month - 1;

/// Un bien o deuda en un mes concreto.
class AssetPosition {
  const AssetPosition({required this.asset, this.valueCents, this.previousCents, this.recordedThisMonth = false});
  final AssetInfo asset;

  /// Último valor conocido hasta ese mes (null si nunca se anotó).
  final int? valueCents;

  /// Valor que tenía el mes anterior.
  final int? previousCents;

  /// Si el valor se anotó ese mismo mes (si no, viene de un mes anterior).
  final bool recordedThisMonth;

  int? get changeCents => valueCents == null || previousCents == null ? null : valueCents! - previousCents!;
}

/// Patrimonio en un mes.
class NetWorth {
  const NetWorth({required this.month, required this.positions});
  final DateTime month;
  final List<AssetPosition> positions;

  int get assetsCents =>
      positions.where((p) => !p.asset.isLiability).fold(0, (s, p) => s + (p.valueCents ?? 0));
  int get liabilitiesCents =>
      positions.where((p) => p.asset.isLiability).fold(0, (s, p) => s + (p.valueCents ?? 0));
  int get netCents => assetsCents - liabilitiesCents;

  int get _previousNet => positions.fold(0, (s, p) {
        final v = p.previousCents ?? 0;
        return p.asset.isLiability ? s - v : s + v;
      });

  /// Variación del patrimonio respecto al mes anterior.
  int get changeCents => netCents - _previousNet;

  /// Bienes o deudas sin valor anotado este mes.
  int get pendingUpdates => positions.where((p) => !p.recordedThisMonth).length;
}

/// Último valor de [assetId] hasta el mes [index] incluido.
int? _valueAt(Map<String, List<AssetValue>> byAsset, String assetId, int index) {
  final list = byAsset[assetId];
  if (list == null) return null;
  int? best;
  var bestIndex = -1;
  for (final v in list) {
    final i = v.monthIndex;
    if (i <= index && i > bestIndex) {
      best = v.cents;
      bestIndex = i;
    }
  }
  return best;
}

Map<String, List<AssetValue>> _group(List<AssetValue> values) {
  final out = <String, List<AssetValue>>{};
  for (final v in values) {
    out.putIfAbsent(v.assetId, () => []).add(v);
  }
  return out;
}

/// Patrimonio en [month] (día 1 del mes contable). Los bienes archivados solo
/// cuentan si tenían valor.
NetWorth netWorthAt(DateTime month, List<AssetInfo> assets, List<AssetValue> values) {
  final byAsset = _group(values);
  final index = monthIndexOf(month.year, month.month);
  final positions = <AssetPosition>[];
  for (final a in assets) {
    final value = _valueAt(byAsset, a.id, index);
    if (a.isArchived && (value ?? 0) == 0) continue;
    positions.add(AssetPosition(
      asset: a,
      valueCents: value,
      previousCents: _valueAt(byAsset, a.id, index - 1),
      recordedThisMonth: byAsset[a.id]?.any((v) => v.monthIndex == index) ?? false,
    ));
  }
  positions.sort((a, b) {
    final k = a.asset.kind.index.compareTo(b.asset.kind.index);
    return k != 0 ? k : a.asset.sortOrder.compareTo(b.asset.sortOrder);
  });
  return NetWorth(month: month, positions: positions);
}

/// Patrimonio neto de los [count] meses que terminan en [lastMonth].
List<int> netWorthSeries(DateTime lastMonth, int count, List<AssetInfo> assets, List<AssetValue> values) {
  final byAsset = _group(values);
  final last = monthIndexOf(lastMonth.year, lastMonth.month);
  return [
    for (var i = last - count + 1; i <= last; i++)
      assets.fold<int>(0, (s, a) {
        final v = _valueAt(byAsset, a.id, i) ?? 0;
        return a.isLiability ? s - v : s + v;
      }),
  ];
}
