/// Canonical strings for the `stock_movements.movement_type` column.
///
/// The column itself is plain TEXT — these constants exist for
/// **grep-ability and refactor safety**. Use them in DAO writes and
/// report queries instead of raw string literals.
///
/// Existing values (left as raw literals throughout the codebase):
///   - 'manufacturing_out'   raw materials consumed by a production order
///   - 'manufacturing_in'    finished products produced by a production order
///   - 'sale'                normal sale of a finished product
///   - 'purchase'            stock receipt from a purchase invoice
///   - 'return'              sale return (raw stock back in)
///   - 'transfer_in/out'     warehouse-to-warehouse transfers
///   - 'adjustment'          manual stock corrections
///
/// Feature 009 (Auto-Deplete BOM on Sale) introduces:
library;

/// Raw materials consumed at sale time by an auto-deplete BOM
/// (T015 — `applyAutoDepleteForSale` writes one row per leaf raw material).
const String stockMovementSaleAutoDeplete = 'sale_auto_deplete';

/// Raw materials returned to stock when a sale with auto-deplete consumption
/// is fully or partially returned (T030 — `reverseSaleConsumption`).
const String stockMovementSaleAutoDepleteReturn = 'sale_auto_deplete_return';
