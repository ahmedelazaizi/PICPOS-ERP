(function () {
  const SERVICES = [
    {id:1, name:'قص شعر', dur:45, buf:10, price:120, color:'#0250D3', icon:'ph-scissors'},
    {id:2, name:'صبغة شعر', dur:120, buf:15, price:850, color:'#8B5CF6', icon:'ph-paint-bucket'},
    {id:3, name:'تنظيف بشرة', dur:45, buf:10, price:400, color:'#14B8A6', icon:'ph-sparkle'},
    {id:4, name:'مساج', dur:60, buf:15, price:550, color:'#F59E0B', icon:'ph-hand-heart'},
    {id:5, name:'جلسة ليزر', dur:30, buf:10, price:900, color:'#EF4444', icon:'ph-lightning'},
    {id:6, name:'حلاقة ذقن', dur:20, buf:5, price:80, color:'#0250D3', icon:'ph-user-focus'},
    {id:7, name:'باديكير ومانيكير', dur:50, buf:10, price:300, color:'#22C55E', icon:'ph-hand-soap'},
    {id:8, name:'بروتين شعر', dur:150, buf:20, price:1800, color:'#8B5CF6', icon:'ph-drop'},
  ];
  const RESOURCES = [
    {id:1, name:'محمد علي', role:'حلاق أول', kind:'staff', initials:'م.ع', color:'#0250D3', shift:'10:00 ص — 08:00 م'},
    {id:2, name:'ريم أحمد', role:'مصممة شعر', kind:'staff', initials:'ر.أ', color:'#8B5CF6', shift:'11:00 ص — 09:00 م'},
    {id:3, name:'نورا حسين', role:'خبيرة بشرة', kind:'staff', initials:'ن.ح', color:'#14B8A6', shift:'10:00 ص — 06:00 م'},
    {id:4, name:'سيف الدين', role:'أخصائي مساج', kind:'staff', initials:'س.د', color:'#F59E0B', shift:'02:00 م — 10:00 م'},
    {id:5, name:'كابينة الليزر', role:'مورد — جهاز', kind:'device', initials:'ك.ل', color:'#EF4444', shift:'10:00 ص — 08:00 م'},
  ];
  // status: confirmed | pending | in_service | seated | cancelled | no_show
  const B = (t, min, cust, phone, sid, rid, status, dep, paid) =>
    ({time:t, min, cust, phone, service:sid, res:rid, status, dep, depPaid:!!paid});
  const TODAY = [
    B('10:00 ص', 600, 'أحمد محمد', '0791234567', 1, 1, 'seated', 100, true),
    B('10:30 ص', 630, 'منى صلاح', '0781119922', 3, 3, 'seated', 0, false),
    B('11:00 ص', 660, 'يوسف كامل', '0790004455', 6, 1, 'seated', 0, false),
    B('11:30 ص', 690, 'سارة محمود', '0798765432', 2, 2, 'seated', 250, true),
    B('12:00 م', 720, 'هالة رشدي', '0795551188', 7, 3, 'seated', 50, true),
    B('12:30 م', 750, 'كريم عبد الله', '0791230099', 1, 1, 'seated', 0, false),
    B('01:00 م', 780, 'محمد خالد', '0795554433', 3, 3, 'pending', 0, false),
    B('01:30 م', 810, 'داليا فؤاد', '0797778866', 5, 5, 'seated', 300, true),
    B('02:00 م', 840, 'عمر الشريف', '0791112200', 6, 1, 'no_show', 0, false),
    B('02:30 م', 870, 'نهى سامي', '0793334477', 4, 4, 'seated', 150, true),
    B('03:00 م', 900, 'طارق منير', '0796665511', 1, 1, 'seated', 0, false),
    B('03:30 م', 930, 'ليلى جمال', '0792223344', 4, 4, 'in_service', 200, true),
    B('04:00 م', 960, 'رانيا وحيد', '0794448833', 3, 3, 'pending', 0, false),
    B('05:00 م', 1020, 'خالد يوسف', '0791112233', 5, 5, 'confirmed', 350, true),
    B('05:30 م', 1050, 'إيمان حسن', '0797771144', 2, 2, 'pending', 0, false),
    B('06:00 م', 1080, 'وليد صابر', '0796662299', 8, 2, 'confirmed', 500, true),
    B('06:30 م', 1110, 'هند نزار', '0799998877', 3, 3, 'cancelled', 0, false),
    B('07:00 م', 1140, 'مروة عادل', '0795553322', 4, 4, 'no_show', 100, true),
  ];
  const UPCOMING = [
    {time:'07:00 م', cust:'محمود سعيد', service:5, res:5},
    {time:'08:30 م', cust:'أمل محمد', service:2, res:2},
    {time:'09:00 م', cust:'جمال عبد الله', service:1, res:1},
  ];
  const WAITLIST = [
    {cust:'ياسمين طلعت', phone:'0791455667', service:2, want:'اليوم بعد 06:00 م', since:'منذ ساعتين', note:'تقبل أي مصممة شعر'},
    {cust:'باسم إبراهيم', phone:'0798112244', service:5, want:'غدًا صباحًا', since:'منذ 35 دقيقة', note:'يفضّل كابينة الليزر'},
    {cust:'شيماء عمر', phone:'0793668899', service:3, want:'اليوم أي وقت', since:'منذ 12 دقيقة', note:'—'},
    {cust:'أنس فتحي', phone:'0790227744', service:8, want:'خلال الأسبوع', since:'أمس', note:'استفسر عن السعر'},
  ];
  const REMINDERS = [
    {cust:'خالد يوسف', phone:'0791112233', at:'05:00 م', channel:'واتساب', when:'قبل ساعة', state:'due'},
    {cust:'وليد صابر', phone:'0796662299', at:'06:00 م', channel:'واتساب', when:'قبل ساعتين', state:'due'},
    {cust:'محمود سعيد', phone:'0795553322', at:'07:00 م', channel:'SMS', when:'قبل ٣ ساعات', state:'due'},
    {cust:'سارة محمود', phone:'0798765432', at:'11:30 ص', channel:'واتساب', when:'قبل ساعة', state:'sent'},
    {cust:'ليلى جمال', phone:'0792223344', at:'03:30 م', channel:'SMS', when:'قبل ساعة', state:'sent'},
  ];
  const CUSTOMERS = [
    {name:'أحمد محمد', phone:'0791234567', visits:14, spend:4820, last:'اليوم', fav:'قص شعر', tier:'ذهبي'},
    {name:'سارة محمود', phone:'0798765432', visits:26, spend:18450, last:'اليوم', fav:'صبغة شعر', tier:'بلاتيني'},
    {name:'ليلى جمال', phone:'0792223344', visits:9, spend:3900, last:'اليوم', fav:'مساج', tier:'فضي'},
    {name:'خالد يوسف', phone:'0791112233', visits:31, spend:24600, last:'اليوم', fav:'جلسة ليزر', tier:'بلاتيني'},
    {name:'محمد خالد', phone:'0795554433', visits:4, spend:1250, last:'قبل شهر', fav:'تنظيف بشرة', tier:'برونزي'},
    {name:'هند نزار', phone:'0799998877', visits:2, spend:600, last:'قبل أسبوع', fav:'تنظيف بشرة', tier:'برونزي'},
    {name:'وليد صابر', phone:'0796662299', visits:11, spend:9800, last:'قبل ٣ أيام', fav:'بروتين شعر', tier:'ذهبي'},
    {name:'داليا فؤاد', phone:'0797778866', visits:18, spend:14200, last:'اليوم', fav:'جلسة ليزر', tier:'ذهبي'},
  ];
  window.PICPOS_BK = {services:SERVICES, resources:RESOURCES, today:TODAY, upcoming:UPCOMING, waitlist:WAITLIST, reminders:REMINDERS, customers:CUSTOMERS};
  try { window.dispatchEvent(new Event('picpos-bk-ready')); } catch (e) {}
})();
