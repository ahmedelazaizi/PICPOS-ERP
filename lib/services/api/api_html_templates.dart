// ═══════════════════════════════════════════════════════════════════════════
// API HTML TEMPLATES — Digital Menu & Customer Facing Display
// ═══════════════════════════════════════════════════════════════════════════
//
// Extracted from ApiHandler for maintainability (PIR C-01).
// Contains the HTML/CSS/JS templates served by the embedded server.

import 'package:ural_erp/core/constants/app_constants.dart';

/// Digital Menu HTML — served at /menu
/// Fetches products/categories from /api/menu and renders a grid layout.
String get menuHtmlTemplate => _menuHtmlTemplateRaw.replaceAll('{{CURRENCY}}', AppConstants.currencySymbol);
const String _menuHtmlTemplateRaw = r'''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>القائمة الرقمية</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, sans-serif;
            background: linear-gradient(135deg, #0f0c29, #302b63, #24243e);
            color: #fff;
            min-height: 100vh;
        }
        .header {
            text-align: center;
            padding: 20px;
            background: rgba(0,0,0,0.3);
            border-bottom: 2px solid rgba(255,255,255,0.1);
        }
        .header h1 {
            font-size: 2em;
            background: linear-gradient(90deg, #f093fb, #f5576c);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .categories {
            display: flex;
            gap: 10px;
            padding: 15px 20px;
            overflow-x: auto;
            background: rgba(0,0,0,0.2);
        }
        .cat-btn {
            padding: 8px 20px;
            border: 1px solid rgba(255,255,255,0.2);
            border-radius: 20px;
            background: rgba(255,255,255,0.05);
            color: #fff;
            cursor: pointer;
            white-space: nowrap;
            transition: all 0.3s;
            font-size: 14px;
        }
        .cat-btn:hover, .cat-btn.active {
            background: linear-gradient(135deg, #667eea, #764ba2);
            border-color: transparent;
        }
        .products {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
            gap: 15px;
            padding: 20px;
        }
        .product-card {
            background: rgba(255,255,255,0.05);
            border: 1px solid rgba(255,255,255,0.1);
            border-radius: 12px;
            padding: 20px;
            transition: all 0.3s;
        }
        .product-card:hover {
            transform: translateY(-3px);
            border-color: rgba(255,255,255,0.3);
            box-shadow: 0 8px 25px rgba(0,0,0,0.3);
        }
        .product-name {
            font-size: 1.1em;
            font-weight: 600;
            margin-bottom: 8px;
        }
        .product-desc {
            font-size: 0.85em;
            color: rgba(255,255,255,0.6);
            margin-bottom: 12px;
            min-height: 20px;
        }
        .product-price {
            font-size: 1.3em;
            font-weight: 700;
            color: #4ade80;
        }
        .loading {
            text-align: center;
            padding: 40px;
            color: rgba(255,255,255,0.5);
        }
    </style>
</head>
<body>
    <div class="header"><h1>القائمة</h1></div>
    <div class="categories" id="categories"></div>
    <div class="products" id="products">
        <div class="loading">جاري التحميل...</div>
    </div>
    <script>
        let allProducts = [];
        let allCategories = [];
        let activeCat = null;

        async function init() {
            try {
                const res = await fetch('/api/menu');
                const data = await res.json();
                allCategories = data.categories || [];
                allProducts = data.products || [];
                renderCategories();
                renderProducts();
            } catch (e) {
                document.getElementById('products').innerHTML =
                    '<div class="loading">خطأ في التحميل</div>';
            }
        }

        function renderCategories() {
            const el = document.getElementById('categories');
            let html = '<button class="cat-btn active" onclick="filterCat(null)">الكل</button>';
            allCategories.forEach(c => {
                html += '<button class="cat-btn" onclick="filterCat(' + c.id + ')">' + c.name + '</button>';
            });
            el.innerHTML = html;
        }

        function filterCat(catId) {
            activeCat = catId;
            document.querySelectorAll('.cat-btn').forEach((b, i) => {
                b.classList.toggle('active', catId === null ? i === 0 : false);
            });
            if (catId !== null) {
                event.target.classList.add('active');
            }
            renderProducts();
        }

        function renderProducts() {
            const el = document.getElementById('products');
            const filtered = activeCat === null
                ? allProducts
                : allProducts.filter(p => p.categoryId === activeCat);

            if (filtered.length === 0) {
                el.innerHTML = '<div class="loading">لا توجد منتجات</div>';
                return;
            }

            el.innerHTML = filtered.map(p =>
                '<div class="product-card">' +
                '<div class="product-name">' + p.name + '</div>' +
                '<div class="product-desc">' + (p.description || '') + '</div>' +
                '<div class="product-price">' + Number(p.price).toFixed(2) + ' {{CURRENCY}}</div>' +
                '</div>'
            ).join('');
        }

        init();
        setInterval(init, 30000);
    </script>
</body>
</html>
''';

/// Customer Facing Display (CFD) HTML — served at /cfd
/// Connects to /api/cfd/stream via SSE to show real-time cart updates.
String get cfdHtmlTemplate => _cfdHtmlTemplateRaw.replaceAll('{{CURRENCY}}', AppConstants.currencySymbol);
const String _cfdHtmlTemplateRaw = r'''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>شاشة العميل</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, sans-serif;
            background: linear-gradient(135deg, #0a0a1a, #1a1a2e, #16213e);
            color: #fff;
            height: 100vh;
            overflow: hidden;
            display: flex;
            flex-direction: column;
        }
        .header {
            padding: 15px 25px;
            background: rgba(0,0,0,0.4);
            border-bottom: 2px solid rgba(99,102,241,0.3);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .header h1 { font-size: 1.4em; color: #a5b4fc; }
        .company-name { font-size: 0.9em; color: rgba(255,255,255,0.6); }
        .status {
            font-size: 0.8em; padding: 4px 12px;
            border-radius: 20px;
            background: rgba(34,197,94,0.2); color: #4ade80;
        }
        .status.disconnected { background: rgba(239,68,68,0.2); color: #f87171; }
        .table-header {
            display: flex; justify-content: space-between;
            padding: 10px 25px;
            background: rgba(99,102,241,0.1);
            border-bottom: 1px solid rgba(99,102,241,0.2);
            font-size: 0.85em; font-weight: 600;
            color: rgba(255,255,255,0.5);
        }
        .table-header .th-name { flex: 1; }
        .table-header .th-qty { min-width: 60px; text-align: center; }
        .table-header .th-price { min-width: 100px; text-align: center; }
        .table-header .th-total { min-width: 100px; text-align: left; }
        .items-container {
            flex: 1; overflow-y: auto; padding: 0 25px;
            scroll-behavior: smooth;
        }
        .item-row {
            display: flex; justify-content: space-between; align-items: center;
            padding: 12px 0; border-bottom: 1px solid rgba(255,255,255,0.05);
            animation: fadeIn 0.3s ease;
            transition: background 0.3s ease;
        }
        .item-row.last-item {
            animation: fadeIn 0.3s ease, glowPulse 1.5s ease-in-out 2;
            background: rgba(99,102,241,0.1);
            border-radius: 6px;
            padding: 12px 8px;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateX(-10px); }
            to { opacity: 1; transform: translateX(0); }
        }
        @keyframes glowPulse {
            0%, 100% { box-shadow: none; background: rgba(99,102,241,0.1); }
            50% { box-shadow: 0 0 15px rgba(99,102,241,0.3); background: rgba(99,102,241,0.2); }
        }
        .item-name { flex: 1; font-size: 1.1em; }
        .item-qty { min-width: 60px; text-align: center; color: rgba(255,255,255,0.6); }
        .item-price { min-width: 100px; text-align: center; color: rgba(255,255,255,0.7); }
        .item-total { min-width: 100px; text-align: left; color: #4ade80; font-weight: 600; }
        .totals {
            padding: 15px 25px;
            background: rgba(0,0,0,0.5);
            border-top: 2px solid rgba(99,102,241,0.3);
        }
        .total-row {
            display: flex; justify-content: space-between;
            padding: 5px 0; font-size: 1em;
            color: rgba(255,255,255,0.7);
        }
        .total-row.grand {
            font-size: 1.5em; font-weight: 700; color: #fff;
            padding-top: 10px; border-top: 1px solid rgba(255,255,255,0.1);
            margin-top: 5px;
        }
        .total-row.grand .amount { color: #4ade80; }
        .payment-section {
            margin-top: 8px; padding-top: 8px;
            border-top: 1px dashed rgba(255,255,255,0.15);
        }
        .payment-section .total-row { color: rgba(255,255,255,0.8); }
        .payment-section .change-row { color: #fbbf24; font-weight: 600; }
        .thank-you {
            text-align: center; padding: 8px 0 4px;
            font-size: 1.1em; color: #a5b4fc;
            animation: fadeIn 0.5s ease;
        }
        .idle-screen {
            display: none; flex: 1; justify-content: center;
            align-items: center; flex-direction: column;
            text-align: center; padding: 40px;
        }
        .idle-screen.active { display: flex; }
        .idle-screen h2 {
            font-size: 2.5em;
            background: linear-gradient(90deg, #667eea, #764ba2);
            -webkit-background-clip: text; -webkit-text-fill-color: transparent;
            margin-bottom: 15px;
        }
        .idle-screen p { color: rgba(255,255,255,0.5); font-size: 1.2em; }
        .cart-view { display: none; flex-direction: column; flex: 1; }
        .cart-view.active { display: flex; }
    </style>
</head>
<body>
    <div class="header">
        <div>
            <h1>شاشة العميل</h1>
            <span class="company-name" id="companyName"></span>
        </div>
        <span class="status" id="status">متصل</span>
    </div>
    <div class="idle-screen active" id="idle">
        <h2>مرحباً بكم</h2>
        <p>في انتظار الطلبات</p>
    </div>
    <div class="cart-view" id="cart">
        <div class="table-header">
            <span class="th-name">الصنف</span>
            <span class="th-qty">الكمية</span>
            <span class="th-price">السعر</span>
            <span class="th-total">الإجمالي</span>
        </div>
        <div class="items-container" id="items"></div>
        <div class="totals" id="totals"></div>
    </div>
    <script>
        const itemsEl = document.getElementById('items');
        const totalsEl = document.getElementById('totals');
        const idleEl = document.getElementById('idle');
        const cartEl = document.getElementById('cart');
        const statusEl = document.getElementById('status');

        function connect() {
            const es = new EventSource('/api/cfd/stream');
            es.onopen = () => {
                statusEl.textContent = 'متصل';
                statusEl.classList.remove('disconnected');
            };
            es.onmessage = (e) => {
                try {
                    const data = JSON.parse(e.data);
                    if (data.type === 'idle' || !data.items || data.items.length === 0) {
                        showIdle();
                    } else {
                        showCart(data);
                    }
                } catch (err) { console.error('Parse error:', err); }
            };
            es.onerror = () => {
                statusEl.textContent = 'غير متصل';
                statusEl.classList.add('disconnected');
                es.close();
                setTimeout(connect, 3000);
            };
        }

        function showIdle() {
            idleEl.classList.add('active');
            cartEl.classList.remove('active');
        }

        function showCart(data) {
            idleEl.classList.remove('active');
            cartEl.classList.add('active');

            const lastIndex = data.items.length - 1;
            itemsEl.innerHTML = data.items.map((i, idx) =>
                '<div class="item-row' + (idx === lastIndex ? ' last-item' : '') + '">' +
                '<span class="item-name">' + i.name + '</span>' +
                '<span class="item-qty">\u00d7' + i.qty + '</span>' +
                '<span class="item-price">' + Number(i.price || 0).toFixed(3) + '</span>' +
                '<span class="item-total">' + Number(i.total).toFixed(3) + '</span>' +
                '</div>'
            ).join('');

            // Auto-scroll to the latest item
            itemsEl.scrollTop = itemsEl.scrollHeight;

            let totalsHtml = '';
            if (data.customer) {
                totalsHtml += '<div class="total-row"><span>العميل</span><span>' + data.customer + '</span></div>';
            }
            if (data.subtotal !== undefined) {
                totalsHtml += '<div class="total-row"><span>المجموع</span><span>' + Number(data.subtotal).toFixed(3) + '</span></div>';
            }
            if (data.discount && data.discount > 0) {
                totalsHtml += '<div class="total-row"><span>الخصم</span><span>-' + Number(data.discount).toFixed(2) + '%</span></div>';
            }
            if (data.tax && data.tax > 0) {
                totalsHtml += '<div class="total-row"><span>الضريبة</span><span>' + Number(data.tax).toFixed(3) + '</span></div>';
            }
            totalsHtml += '<div class="total-row grand"><span>الإجمالي</span><span class="amount">' + Number(data.total).toFixed(3) + ' {{CURRENCY}}</span></div>';

            // Payment section
            if (data.paid && data.paid > 0) {
                totalsHtml += '<div class="payment-section">';
                totalsHtml += '<div class="total-row"><span>المدفوع</span><span>' + Number(data.paid).toFixed(3) + '</span></div>';
                const change = data.paid - data.total;
                if (change >= 0) {
                    totalsHtml += '<div class="total-row change-row"><span>الباقي</span><span>' + Number(change).toFixed(3) + '</span></div>';
                }
                totalsHtml += '</div>';
                totalsHtml += '<div class="thank-you">شكراً لتسوقكم</div>';
            }

            totalsEl.innerHTML = totalsHtml;
        }

        connect();
    </script>
</body>
</html>
''';
