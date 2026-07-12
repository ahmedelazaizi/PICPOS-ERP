import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Reporting Engine - Data Aggregation', () {
    test('Calculate gross profit from sales and costs', () {
      final sales = [100.0, 200.0, 150.0];
      final costs = [70.0, 140.0, 100.0];
      
      final totalSales = sales.reduce((a, b) => a + b);
      final totalCosts = costs.reduce((a, b) => a + b);
      final profit = totalSales - totalCosts;
      final margin = (totalSales > 0) ? (profit / totalSales) * 100 : 0.0;
      
      expect(totalSales, equals(450.0));
      expect(totalCosts, equals(310.0));
      expect(profit, equals(140.0));
      expect(margin, closeTo(31.11, 0.01));
    });

    test('Aggregate category sales correctly', () {
      final items = [
        {'category': 'Drinks', 'total': 50.0},
        {'category': 'Food', 'total': 100.0},
        {'category': 'Drinks', 'total': 30.0},
      ];
      
      final categoryTotals = <String, double>{};
      for (final item in items) {
        final cat = item['category'] as String;
        final total = item['total'] as double;
        categoryTotals[cat] = (categoryTotals[cat] ?? 0) + total;
      }
      
      expect(categoryTotals['Drinks'], equals(80.0));
      expect(categoryTotals['Food'], equals(100.0));
    });

    test('Identify low stock items accurately', () {
      final inventory = [
        {'name': 'Item A', 'stock': 5, 'min': 10},
        {'name': 'Item B', 'stock': 15, 'min': 10},
        {'name': 'Item C', 'stock': 10, 'min': 10},
      ];
      
      final lowStock = inventory.where((i) => (i['stock'] as int) <= (i['min'] as int)).toList();
      
      expect(lowStock.length, equals(2));
      expect(lowStock[0]['name'], equals('Item A'));
      expect(lowStock[1]['name'], equals('Item C'));
    });
  });

  group('Search Engine - FTS Query Processing', () {
    test('Prefix search query processing', () {
      String processQuery(String query) {
        if (query.trim().isEmpty) return '';
        return query.trim().split(RegExp(r'\s+')).map((e) => '$e*').join(' ');
      }
      
      expect(processQuery('apple'), equals('apple*'));
      expect(processQuery('apple juice'), equals('apple* juice*'));
      expect(processQuery('  bread  '), equals('bread*'));
      expect(processQuery(''), equals(''));
    });
  });
}
