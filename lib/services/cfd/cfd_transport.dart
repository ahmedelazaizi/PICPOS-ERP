// ═══════════════════════════════════════════════════════════════════════════
// CFD TRANSPORT — Abstract interface for Customer Facing Display transports
// ═══════════════════════════════════════════════════════════════════════════

/// Connection type for customer-facing displays
enum CfdConnectionType {
  /// Network/WiFi — HTTP SSE stream (existing)
  network,

  /// Serial/COM — RS-232 for VFD pole displays
  serial,

  /// USB — Virtual COM port (same protocol as serial)
  usb,

  /// HDMI — Second monitor via extended desktop
  hdmi,
}

/// Human-readable labels for connection types
extension CfdConnectionTypeLabel on CfdConnectionType {
  String get label {
    switch (this) {
      case CfdConnectionType.network:
        return 'شبكة (Network/WiFi)';
      case CfdConnectionType.serial:
        return 'Serial / COM Port (VFD)';
      case CfdConnectionType.usb:
        return 'USB (Virtual COM)';
      case CfdConnectionType.hdmi:
        return 'HDMI / شاشة ثانية';
    }
  }

  String get description {
    switch (this) {
      case CfdConnectionType.network:
        return 'تابلت أو شاشة على نفس الشبكة';
      case CfdConnectionType.serial:
        return 'شاشة VFD عبر كابل Serial RS-232';
      case CfdConnectionType.usb:
        return 'شاشة VFD عبر كابل USB';
      case CfdConnectionType.hdmi:
        return 'شاشة ثانية متصلة بكابل HDMI';
    }
  }
}

/// Configuration for what content is displayed on the customer-facing display.
class CfdDisplayConfig {
  /// Show individual item names in the list
  final bool showItemName;

  /// Show item quantity
  final bool showItemQuantity;

  /// Show item unit price
  final bool showItemPrice;

  /// Show item line total
  final bool showItemTotal;

  /// Show subtotal before discount/tax
  final bool showSubtotal;

  /// Show discount percentage/amount
  final bool showDiscount;

  /// Show tax amount
  final bool showTax;

  /// Show grand total
  final bool showTotal;

  /// Show customer name
  final bool showCustomerName;

  /// Welcome/idle message line 1
  final String welcomeMessage;

  /// Welcome/idle message line 2
  final String welcomeSubMessage;

  const CfdDisplayConfig({
    this.showItemName = true,
    this.showItemQuantity = true,
    this.showItemPrice = true,
    this.showItemTotal = true,
    this.showSubtotal = true,
    this.showDiscount = true,
    this.showTax = true,
    this.showTotal = true,
    this.showCustomerName = true,
    this.welcomeMessage = 'مرحباً بكم',
    this.welcomeSubMessage = 'Welcome',
  });

  /// Default config — everything visible
  static const defaultConfig = CfdDisplayConfig();

  Map<String, dynamic> toJson() => {
        'showItemName': showItemName,
        'showItemQuantity': showItemQuantity,
        'showItemPrice': showItemPrice,
        'showItemTotal': showItemTotal,
        'showSubtotal': showSubtotal,
        'showDiscount': showDiscount,
        'showTax': showTax,
        'showTotal': showTotal,
        'showCustomerName': showCustomerName,
        'welcomeMessage': welcomeMessage,
        'welcomeSubMessage': welcomeSubMessage,
      };

  factory CfdDisplayConfig.fromJson(Map<String, dynamic> json) {
    return CfdDisplayConfig(
      showItemName: json['showItemName'] as bool? ?? true,
      showItemQuantity: json['showItemQuantity'] as bool? ?? true,
      showItemPrice: json['showItemPrice'] as bool? ?? true,
      showItemTotal: json['showItemTotal'] as bool? ?? true,
      showSubtotal: json['showSubtotal'] as bool? ?? true,
      showDiscount: json['showDiscount'] as bool? ?? true,
      showTax: json['showTax'] as bool? ?? true,
      showTotal: json['showTotal'] as bool? ?? true,
      showCustomerName: json['showCustomerName'] as bool? ?? true,
      welcomeMessage: json['welcomeMessage'] as String? ?? 'مرحباً بكم',
      welcomeSubMessage: json['welcomeSubMessage'] as String? ?? 'Welcome',
    );
  }

  CfdDisplayConfig copyWith({
    bool? showItemName,
    bool? showItemQuantity,
    bool? showItemPrice,
    bool? showItemTotal,
    bool? showSubtotal,
    bool? showDiscount,
    bool? showTax,
    bool? showTotal,
    bool? showCustomerName,
    String? welcomeMessage,
    String? welcomeSubMessage,
  }) {
    return CfdDisplayConfig(
      showItemName: showItemName ?? this.showItemName,
      showItemQuantity: showItemQuantity ?? this.showItemQuantity,
      showItemPrice: showItemPrice ?? this.showItemPrice,
      showItemTotal: showItemTotal ?? this.showItemTotal,
      showSubtotal: showSubtotal ?? this.showSubtotal,
      showDiscount: showDiscount ?? this.showDiscount,
      showTax: showTax ?? this.showTax,
      showTotal: showTotal ?? this.showTotal,
      showCustomerName: showCustomerName ?? this.showCustomerName,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      welcomeSubMessage: welcomeSubMessage ?? this.welcomeSubMessage,
    );
  }
}

/// Cart data structure for display transports
class CfdCartData {
  final List<CfdCartItem> items;
  final double subtotal;
  final double discountPercent;
  final double taxAmount;
  final double total;
  final String? customerName;

  const CfdCartData({
    required this.items,
    required this.subtotal,
    required this.discountPercent,
    required this.taxAmount,
    required this.total,
    this.customerName,
  });

  /// Convert to JSON, optionally filtered by display config
  Map<String, dynamic> toJson([CfdDisplayConfig? config]) {
    final c = config ?? CfdDisplayConfig.defaultConfig;
    return {
      'items': items
          .map((i) => {
                if (c.showItemName) 'name': i.name,
                if (c.showItemQuantity) 'qty': i.quantity,
                if (c.showItemPrice) 'price': i.price,
                if (c.showItemTotal) 'total': i.total,
              })
          .toList(),
      if (c.showSubtotal) 'subtotal': subtotal,
      if (c.showDiscount) 'discount': discountPercent,
      if (c.showTax) 'tax': taxAmount,
      if (c.showTotal) 'total': total,
      if (c.showCustomerName && customerName != null)
        'customer': customerName,
      // Pass config for HTML rendering
      'displayConfig': c.toJson(),
    };
  }
}

class CfdCartItem {
  final String name;
  final double quantity;
  final double price;
  final double total;

  const CfdCartItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.total,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'qty': quantity,
        'price': price,
        'total': total,
      };
}

/// Abstract transport interface for customer-facing displays.
///
/// Each connection type (Network, Serial, USB, HDMI) implements this interface.
/// The [CfdService] delegates to the active transport.
abstract class CfdTransport {
  /// Connect to the display with the given configuration.
  Future<bool> connect(Map<String, dynamic> config);

  /// Send a cart update to the display.
  void sendCartUpdate(CfdCartData cartData);

  /// Send an idle/welcome screen to the display.
  void sendIdle();

  /// Disconnect from the display.
  Future<void> disconnect();

  /// Whether the transport is currently connected.
  bool get isConnected;

  /// Human-readable status text.
  String get statusText;

  /// The connection type this transport handles.
  CfdConnectionType get type;
}
