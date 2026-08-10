export const LIMITS = { singleFileBytes: 2 * 1024 * 1024, totalBytes: 8 * 1024 * 1024 };

const JS_RE = /\.js$/;

export function resolveRelPath(fromRel, spec) {
  if (!spec || spec.startsWith('/')) return null;
  if (spec.startsWith('http:') || spec.startsWith('https:') || spec.startsWith('blob:')) return null;
  const baseDir = fromRel.includes('/') ? fromRel.slice(0, fromRel.lastIndexOf('/')) : '';
  const baseDepth = baseDir ? baseDir.split('/').length : 0;
  let leading = 0;
  for (const seg of spec.split('/')) {
    if (seg === '..') leading++;
    else if (seg && seg !== '.') break;
  }
  if (leading > baseDepth + 1) return null;
  const parts = [];
  for (const seg of `${baseDir ? baseDir + '/' : ''}${spec}`.split('/')) {
    if (!seg || seg === '.') continue;
    if (seg === '..') {
      if (parts.length > 0) parts.pop();
    } else {
      parts.push(seg);
    }
  }
  const out = parts.join('/');
  if (!JS_RE.test(out)) return null;
  return out;
}

// 正则字面量起点启发式：`/` 前一个非空白字符属于该集合（或行首/文件首，
// 或紧跟 return/typeof 等关键字）时视为正则字面量开始，否则是除号。
const REGEX_PREFIX_RE = /[(=:,[!&|?{};+\-*%<>~^]/;
const REGEX_KEYWORDS = new Set([
  'return', 'typeof', 'delete', 'void', 'throw', 'case',
  'in', 'of', 'instanceof', 'yield', 'await', 'do', 'else',
]);

function isRegexStart(source, i) {
  let j = i - 1;
  while (j >= 0 && /\s/.test(source[j])) j--;
  if (j < 0) return true;
  const prev = source[j];
  if (/[A-Za-z0-9_$]/.test(prev)) {
    let k = j;
    while (k >= 0 && /[A-Za-z0-9_$]/.test(source[k])) k--;
    return REGEX_KEYWORDS.has(source.slice(k + 1, j + 1));
  }
  return REGEX_PREFIX_RE.test(prev);
}

// 逐字符扫描实现：维护注释/字符串/正则字面量状态，保证 import 识别不误伤。
// 注释与正则字面量置空生成 clean 串用于正则定位（长度不变，位置映射有效）；
// 字符串内容保留并记录区间，匹配落在字符串区间内的跳过。
function scanSource(source) {
  const n = source.length;
  const clean = new Array(n);
  const strings = [];
  let i = 0;
  while (i < n) {
    const c = source[i];
    if (c === '/' && source[i + 1] === '/') {
      const end = source.indexOf('\n', i);
      const stop = end === -1 ? n : end;
      for (let j = i; j < stop; j++) clean[j] = ' ';
      i = stop;
    } else if (c === '/' && source[i + 1] === '*') {
      const end = source.indexOf('*/', i + 2);
      const stop = end === -1 ? n : end + 2;
      for (let j = i; j < stop; j++) clean[j] = ' ';
      i = stop;
    } else if (c === '"' || c === "'" || c === '`') {
      // 字符串：`\` 转义跳过下一字符，避免 `\'` 提前截断字符串区间
      let end = i + 1;
      while (end < n) {
        if (source[end] === '\\') { end += 2; continue; }
        if (source[end] === c) break;
        end++;
      }
      const stop = end >= n ? n : end + 1;
      for (let j = i; j < stop; j++) clean[j] = source[j];
      strings.push([i, stop]);
      i = stop;
    } else if (c === '/' && isRegexStart(source, i)) {
      // 正则字面量：`\` 转义跳过，字符类 `[...]` 内 `/` 不结束
      let end = i + 1;
      let inClass = false;
      while (end < n) {
        const ch = source[end];
        if (ch === '\\') { end += 2; continue; }
        if (ch === '[') inClass = true;
        else if (ch === ']') inClass = false;
        else if (ch === '/' && !inClass) break;
        end++;
      }
      const stop = end >= n ? n : end + 1;
      for (let j = i; j < stop; j++) clean[j] = ' ';
      i = stop;
    } else {
      clean[i] = c;
      i++;
    }
  }
  return { clean: clean.join(''), strings };
}

// 静态 import ... from 'spec' / import 'spec'（rewriteModule 与 extractImports 共用同一套边界规则）
const staticRe = /((?:^|[^\w$.])\s*)import\s+(?:[^'"]*?\s+from\s+)?(['"])([^'"]*)\2/g;
// 动态 import('literal')
const dynamicRe = /((?:^|[^\w$.])\s*)import\(\s*['"]([^'"]*)['"]\s*\)/g;
// 任意 import( 出现位置（用于检测非字面量动态 import）
const anyDynamicRe = /((?:^|[^\w$.])\s*)import\(\s*/g;
// 动态 import 参数必须是纯字符串字面量（允许转义），其后到 ) 只能有空白
const literalArgRe = /^\s*(['"])(?:\\[\s\S]|(?!\1)[\s\S])*\1\s*\)/;

export function rewriteModule(source, resolveImport) {
  const { clean, strings } = scanSource(source);
  const inString = (pos) => strings.some(([s, e]) => pos >= s && pos < e);

  const matches = [];
  const collect = (re, specGroup) => {
    let m;
    while ((m = re.exec(clean)) !== null) {
      const start = m.index + m[1].length;
      if (inString(start)) continue;
      matches.push({ start, end: start + m[0].length - m[1].length, spec: m[specGroup] });
    }
  };
  collect(staticRe, 3);
  collect(dynamicRe, 2);

  let m;
  while ((m = anyDynamicRe.exec(clean)) !== null) {
    const start = m.index + m[1].length;
    if (inString(start)) continue;
    const rest = clean.slice(m.index + m[0].length);
    if (!literalArgRe.test(rest)) {
      const close = rest.indexOf(')');
      const spec = (close === -1 ? rest : rest.slice(0, close)).trim();
      throw new Error(`dynamic import must be a string literal: ${spec}`);
    }
  }

  let out = source;
  matches.sort((a, b) => b.start - a.start);
  for (const hit of matches) {
    const resolved = resolveImport(hit.spec);
    if (!resolved) throw new Error(`cannot resolve import: ${hit.spec}`);
    const specStart = out.indexOf(`'${hit.spec}'`, hit.start);
    const quote = specStart === -1 ? '"' : "'";
    const realStart = specStart === -1 ? out.indexOf(`"${hit.spec}"`, hit.start) : specStart;
    if (realStart === -1) continue;
    out = out.slice(0, realStart) + quote + resolved.url + quote + out.slice(realStart + hit.spec.length + 2);
  }
  return out;
}

export function extractImports(source) {
  const { clean, strings } = scanSource(source);
  const inString = (pos) => strings.some(([s, e]) => pos >= s && pos < e);
  const specs = [];
  let m;
  while ((m = staticRe.exec(clean)) !== null) {
    const start = m.index + m[1].length;
    if (inString(start)) continue;
    specs.push(m[3]);
  }
  while ((m = dynamicRe.exec(clean)) !== null) {
    const start = m.index + m[1].length;
    if (inString(start)) continue;
    specs.push(m[2]);
  }
  return specs;
}

export async function collectModuleGraph(entryPath, readFile) {
  const modules = [];
  const seen = new Set();
  const stack = [];
  let total = 0;

  async function visit(path) {
    if (seen.has(path)) return null;
    if (stack.includes(path)) return { error: `circular: ${[...stack, path].join(' -> ')}` };
    const file = await readFile(path);
    if (!file) return { error: `missing file: ${path}` };
    if (file.bytes > LIMITS.singleFileBytes) return { error: `size limit: ${path}` };
    total += file.bytes;
    if (total > LIMITS.totalBytes) return { error: 'size limit: total' };
    stack.push(path);
    for (const spec of extractImports(file.source)) {
      const rel = resolveRelPath(path, spec);
      if (!rel) return { error: `cannot resolve import: ${spec} (in ${path})` };
      const sub = await visit(rel);
      if (sub && sub.error) return sub;
    }
    stack.pop();
    seen.add(path);
    modules.push({ path, source: file.source });
    return null;
  }

  const err = await visit(entryPath);
  if (err) return err;
  return { modules };
}
