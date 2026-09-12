// ═══════════════════════════════════════════════════════════════════════════
// TABLE BILL — صفحةُ حسابِ الطاولة على هاتف الزبون
// ═══════════════════════════════════════════════════════════════════════════
//
// تُخدَم على `/t/<token>` ويقرأ جافاسكربتُها `/api/table-bill/<token>`.
//
// ⚠️ **كلُّ نصٍّ من القاعدة يُكتَب بـ`textContent` لا بـ`innerHTML`.** أسماءُ
// الأصناف وملاحظاتُ البنود يكتبها موظّفٌ في شاشة الأصناف، وصنفٌ اسمُه
// `<img src=x onerror=...>` كان يُنفَّذ في متصفّح **كلِّ زبونٍ يمسح الرمز**.
// وهذه أوّلُ صفحةٍ في المنتج يكتب فيها مستخدمٌ محتوىً يقرؤه غريب.
//
// ⚠️ **ولا زرَّ دفعٍ.** «يسدّد» في طلب المالك = `bill_requested` أي مناداةُ
// النادل. والدفعُ الإلكترونيُّ قرارٌ آخرُ له تبعاتُ تسويةٍ ومحاسبة.

import 'package:ural_erp/core/constants/app_constants.dart';

/// صفحةُ حسابِ الطاولة — تُبنى مرّةً ويُستبدَل فيها رمزُ العملة وخاناتُ الكسر.
///
/// ⚠️ **وخاناتُ الكسر تُحقَن ولا تُكتَب `2`**: المنتجُ يُشحَن بعملاتٍ تختلف
/// خاناتُها، و`toFixed(2)` صلبةً كانت تعرض على هاتف الزبون رقماً يخالف ما
/// يطبعه الإيصالُ في يده. وهي عائلةُ عطبٍ لها سابقةٌ موثَّقةٌ في هذا المستودع.
String get tableBillHtmlTemplate => _tableBillHtmlRaw
    .replaceAll('{{CURRENCY}}', AppConstants.currencySymbol)
    .replaceAll('{{DECIMALS}}', '${AppConstants.decimalPlaces}');

const String _tableBillHtmlRaw = r'''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1">
<title>حسابك</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{
    font-family:'Segoe UI',Tahoma,sans-serif;
    background:#f4f6fa;color:#16233a;
    min-height:100vh;padding:12px;
  }
  .wrap{max-width:520px;margin:0 auto}
  .card{
    background:#fff;border-radius:16px;padding:16px;
    box-shadow:0 2px 12px rgba(16,35,68,.07);margin-bottom:12px;
  }
  .head{display:flex;align-items:center;justify-content:space-between;gap:10px}
  .head h1{font-size:1.05rem;font-weight:800}
  .tbl{
    background:#0250D3;color:#fff;border-radius:10px;
    padding:6px 12px;font-weight:800;font-size:.9rem;white-space:nowrap;
  }
  .muted{color:#6b7a90;font-size:.78rem}
  .lines{margin-top:6px}
  .line{
    display:flex;justify-content:space-between;gap:10px;
    padding:10px 0;border-bottom:1px solid #eef1f6;
  }
  .line:last-child{border-bottom:0}
  .nm{font-weight:600;font-size:.92rem}
  .qt{color:#6b7a90;font-size:.76rem;margin-top:2px}
  .amt{font-weight:700;white-space:nowrap;font-size:.92rem}
  .sum{display:flex;justify-content:space-between;padding:6px 0;font-size:.87rem}
  .sum.total{
    border-top:2px solid #0250D3;margin-top:8px;padding-top:10px;
    font-size:1.12rem;font-weight:800;color:#0250D3;
  }
  .btn{
    display:block;width:100%;border:0;border-radius:12px;
    background:#0250D3;color:#fff;font-size:1rem;font-weight:800;
    padding:14px;cursor:pointer;font-family:inherit;
  }
  .btn:disabled{background:#9db4dd;cursor:default}
  .state{text-align:center;padding:40px 16px;color:#6b7a90}
  .ok{
    background:#e8f7ee;color:#1a7f45;border-radius:12px;
    padding:12px;text-align:center;font-weight:700;font-size:.9rem;
  }
  .err{
    background:#fdecec;color:#b3261e;border-radius:12px;
    padding:12px;text-align:center;font-weight:700;font-size:.9rem;
  }
  .note{
    text-align:center;font-size:.72rem;color:#8b98ab;margin-top:10px;
  }
</style>
</head>
<body>
<div class="wrap">
  <div id="root"><div class="state">جارٍ تحميل حسابك…</div></div>
  <div class="note" id="note"></div>
</div>
<script>
// الرمزُ من المسار `/t/<token>` — ولا يُقرأ من المعاملات كي لا يُسرَّب في
// سجلّات الوسطاء ولا في `Referer`.
var TOKEN = decodeURIComponent(location.pathname.replace(/^\/t\//, ''));
var CUR = '{{CURRENCY}}';
var session = null;
var requested = false;
var timer = null;

function money(v){
  return (Number(v)||0).toFixed({{DECIMALS}}) + ' ' + CUR;
}

// ⚠️ كلُّ نصٍّ يمرّ من هنا. الأسماءُ تأتي من القاعدة ويكتبها موظّف.
function el(tag, cls, text){
  var n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined && text !== null) n.textContent = String(text);
  return n;
}

function stateBox(cls, msg){
  var root = document.getElementById('root');
  root.innerHTML = '';
  var c = el('div','card');
  c.appendChild(el('div', cls || 'state', msg));
  root.appendChild(c);
}

function sumRow(label, value, cls){
  var r = el('div', cls ? ('sum ' + cls) : 'sum');
  r.appendChild(el('span', null, label));
  r.appendChild(el('span', null, money(value)));
  return r;
}

function render(d){
  var root = document.getElementById('root');
  root.innerHTML = '';

  var card = el('div','card');
  var head = el('div','head');
  var left = el('div');
  left.appendChild(el('h1', null, d.shopName || 'حسابك'));
  if (d.guestCount) left.appendChild(el('div','muted', d.guestCount + ' ضيف'));
  head.appendChild(left);
  head.appendChild(el('div','tbl', d.tableName));
  card.appendChild(head);

  var lines = el('div','lines');
  (d.items || []).forEach(function(it){
    var row = el('div','line');
    var info = el('div');
    info.appendChild(el('div','nm', it.name));
    var q = it.qty + ' × ' + money(it.unitPrice);
    if (it.notes) q += ' — ' + it.notes;
    info.appendChild(el('div','qt', q));
    row.appendChild(info);
    row.appendChild(el('div','amt', money(it.total)));
    lines.appendChild(row);
  });
  if (!(d.items || []).length) {
    lines.appendChild(el('div','state','لا أصناف على الطاولة بعد'));
  }
  card.appendChild(lines);

  card.appendChild(sumRow('المجموع', d.subtotal));
  if (d.discount > 0) card.appendChild(sumRow('الخصم', -d.discount));
  if (d.taxAmount > 0) card.appendChild(sumRow('الضريبة', d.taxAmount));
  card.appendChild(sumRow('المستحقّ', d.total, 'total'));
  if (d.paidAmount > 0) {
    card.appendChild(sumRow('المدفوع', d.paidAmount));
    card.appendChild(sumRow('المتبقّي', d.remaining));
  }
  root.appendChild(card);

  var act = el('div','card');
  if (d.billRequested || requested) {
    act.appendChild(el('div','ok','تمّ إبلاغ النادل — الحساب في الطريق'));
  } else {
    var b = el('button','btn','اطلب الحساب');
    b.onclick = function(){ requestBill(b); };
    act.appendChild(b);
  }
  root.appendChild(act);

  document.getElementById('note').textContent =
    'هذه شاشةُ عرضٍ — الحسابُ النهائيُّ ما يسلّمه لك النادل';
}

function requestBill(btn){
  btn.disabled = true;
  btn.textContent = 'جارٍ الإرسال…';
  fetch('/api/table-bill/' + encodeURIComponent(TOKEN) + '/request', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({session: session})
  }).then(function(r){ return r.json(); }).then(function(j){
    if (j && j.success) { requested = true; load(); }
    else {
      btn.disabled = false;
      btn.textContent = 'اطلب الحساب';
      stateBoxAppend(j && j.error ? j.error : 'تعذّر الإرسال — نادِ النادل');
    }
  }).catch(function(){
    btn.disabled = false;
    btn.textContent = 'اطلب الحساب';
    stateBoxAppend('تعذّر الاتصال — نادِ النادل');
  });
}

function stateBoxAppend(msg){
  var root = document.getElementById('root');
  var c = el('div','card');
  c.appendChild(el('div','err', msg));
  root.appendChild(c);
}

function load(){
  fetch('/api/table-bill/' + encodeURIComponent(TOKEN))
    .then(function(r){ return r.json(); })
    .then(function(j){
      if (!j || j.success === false) {
        stateBox('state', (j && j.error) || 'تعذّر عرض الحساب');
        return;
      }
      if (!j.open) {
        stateBox('state','لا حساب مفتوحاً على هذه الطاولة');
        return;
      }
      session = j.session || null;
      render(j);
    })
    .catch(function(){ stateBox('state','تعذّر الاتصال بالمحلّ'); });
}

load();
// الطلبُ ينمو والنادلُ يضيف أصنافاً والضيفُ جالس، فالصفحةُ تتابع.
timer = setInterval(load, 15000);
document.addEventListener('visibilitychange', function(){
  if (!document.hidden) load();
});
</script>
</body>
</html>
''';
