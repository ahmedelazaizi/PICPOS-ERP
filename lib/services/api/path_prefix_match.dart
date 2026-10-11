// مطابقة بادئة مسار بحدٍّ فاصل (بند الأمن 2.2).
//
// `startsWith('/ws')` كانت تُعفي `/wsfoo` و`/menu-admin`… أيضًا. المطابقة
// الصحيحة: المسار نفسه، أو المسار يتبعه `/`. (الاستعلام ليس جزءًا من
// `request.url.path` أصلًا.)

bool matchesPathPrefix(String path, String prefix) =>
    path == prefix || path.startsWith('$prefix/');

bool matchesAnyPathPrefix(String path, Iterable<String> prefixes) =>
    prefixes.any((p) => matchesPathPrefix(path, p));
