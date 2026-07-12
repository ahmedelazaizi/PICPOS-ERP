UPDATE products SET current_stock = 0;
UPDATE parties SET balance = 0;
UPDATE safes SET balance = 0;
UPDATE accounts SET balance = 0;
UPDATE product_batches SET quantity = 0, status = 'depleted';
DELETE FROM inventory_balances;
