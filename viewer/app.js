/* 语文课本阅读器：阅读 struct.json，并用 polyphone.json 专题校正多音字 */
(function () {
  "use strict";

  var STORE_KEY = "zh-textbook:data";
  var POLY_KEY = "zh-textbook:polyphone";
  var PREF_KEY = "zh-textbook:prefs";
  var FIX_KEY = "zh-textbook:fixes";

  var SENTENCE_END = "。！？…";
  var CLOSERS = "”’」』）》";
  var CLAUSE_END = "。！？…；，";

  var el = {
    body: document.body,
    sidebar: document.getElementById("sidebar"),
    backdrop: document.getElementById("backdrop"),
    toc: document.getElementById("toc"),
    search: document.getElementById("search"),
    reader: document.getElementById("reader"),
    pager: document.getElementById("pager"),
    prev: document.getElementById("prevBtn"),
    next: document.getElementById("nextBtn"),
    crumb: document.getElementById("crumb"),
    error: document.getElementById("error"),
    bookTitle: document.getElementById("bookTitle"),
    bookMeta: document.getElementById("bookMeta"),
    pinyinBtn: document.getElementById("pinyinBtn"),
    fontBtn: document.getElementById("fontBtn"),
    polyphoneInput: document.getElementById("polyphoneInput"),
    commonBtn: document.getElementById("commonBtn"),
    exitTopic: document.getElementById("exitTopic")
  };

  var root = null;     // 载入的 struct.json 原对象（下载用）
  var polyRoot = null; // 多音字表原对象
  var polyphones = {}; // 字 → [{ py, group, words, context, quickRule }]，多音字表全量
  var topic = {};      // 实际标记为待核对的字，受“只核对常用”开关过滤
  var mode = "reading";
  var fixes = [];      // 修正记录，用于计数 / 撤销 / 明细
  var items = [];      // 目录条目（含渲染所需数据）
  var current = -1;
  var prefs = { sidebar: "on", pinyin: "on", font: "kai", size: 21, last: 0, width: 268 , polyCommon: true };
  var WIDTH_MIN = 180, WIDTH_MAX = 520, WIDTH_DEFAULT = 268;

  /* ---------------- 偏好 ---------------- */

  function loadPrefs() {
    try {
      var saved = JSON.parse(localStorage.getItem(PREF_KEY) || "{}");
      for (var k in saved) if (k in prefs) prefs[k] = saved[k];
    } catch (e) { /* 忽略 */ }
    if (window.matchMedia("(max-width: 860px)").matches) prefs.sidebar = "off";
    applyPrefs();
  }

  function applyPrefs() {
    el.body.dataset.sidebar = prefs.sidebar;
    el.body.dataset.pinyin = prefs.pinyin;
    el.body.dataset.font = prefs.font;
    document.documentElement.style.setProperty("--reading", prefs.size + "px");
    document.documentElement.style.setProperty("--sidebar-w", prefs.width + "px");
    el.pinyinBtn.setAttribute("aria-pressed", prefs.pinyin === "on");
    if (el.commonBtn) el.commonBtn.setAttribute("aria-pressed", String(!!prefs.polyCommon));
    el.fontBtn.textContent = { kai: "楷体", song: "宋体", hei: "黑体" }[prefs.font];
    el.backdrop.hidden = !(prefs.sidebar === "on" &&
      window.matchMedia("(max-width: 860px)").matches);
    try { localStorage.setItem(PREF_KEY, JSON.stringify(prefs)); } catch (e) { /* 忽略 */ }
  }

  /* ---------------- 载入数据 ---------------- */

  function readFile(file) {
    var reader = new FileReader();
    reader.onload = function () {
      try {
        var data = JSON.parse(reader.result);
        if (isPolyphoneData(data)) {
          if (!root) {
            showError("请先加载 struct.json 课文，再加载多音字表。");
            return;
          }
          usePolyphoneData(data);
          try { localStorage.setItem(POLY_KEY, reader.result); } catch (e) { /* 太大就不存 */ }
        } else {
          useData(data);
          try {
            localStorage.setItem(STORE_KEY, reader.result);
            localStorage.removeItem(POLY_KEY);
            localStorage.removeItem(FIX_KEY);
          } catch (e) { /* 太大就不存 */ }
        }
      } catch (err) {
        showError("解析失败：" + err.message);
      }
    };
    reader.onerror = function () { showError("读取文件失败"); };
    reader.readAsText(file, "utf-8");
  }

  function showError(msg) {
    el.error.textContent = msg;
    el.error.hidden = false;
  }

  function isPolyphoneData(data) {
    return !!(data && Array.isArray(data["多音字"]) &&
      data["多音字"].some(function (row) {
        return row && row["字"] &&
          (Array.isArray(row["本册出现"]) || Array.isArray(row["常用"]) || Array.isArray(row["不常用"]));
      }));
  }

  function useData(data) {
    if (!data || (!data["课文"] && !data["园地"] && !data["附录"])) {
      showError("这不像 struct.json —— 需要 课文 / 园地 / 附录 三块。");
      return;
    }
    if (data["课文"] && data["课文"][0] && data["课文"][0]["正文"]) {
      showError("这是完整版 all.json。请用 --struct 生成的 struct.json。");
      return;
    }
    el.error.hidden = true;
    root = data;
    polyRoot = null;
    polyphones = {};
    mode = "reading";
    el.body.dataset.mode = mode;
    el.exitTopic.hidden = true;
    fixes = [];
    renderFixbar();
    items = buildItems(data);
    el.bookTitle.textContent = data["文件"] || "语文课本";
    el.bookMeta.textContent = items.length + " 篇 · 课文 " +
      count(items, "课文") + " · 园地 " + count(items, "园地") +
      " · 附录 " + count(items, "附录");
    buildToc("");
    el.body.dataset.state = "loaded";
    el.search.placeholder = "搜索课文 / 园地…";
    el.reader.hidden = false;
    el.pager.hidden = false;
    show(prefs.last < items.length ? prefs.last : 0);
  }

  function usePolyphoneData(data) {
    if (!root) {
      showError("请先加载 struct.json 课文，再加载多音字表。");
      return;
    }
    if (!isPolyphoneData(data)) {
      showError("这不像 polyphone.json —— 需要逐字的 本册出现 / 常用 / 不常用 三组读音。");
      return;
    }
    var map = {};
    data["多音字"].forEach(function (row) {
      var ch = row["字"];
      if (!ch) return;
      var readings = [];
      ["本册出现", "常用", "不常用"].forEach(function (group) {
        (row[group] || []).forEach(function (entry) {
          var pronunciation = entry && (entry["读音"] || entry["拼音"]);
          if (!pronunciation) return;
          if (readings.some(function (x) { return x.py === pronunciation; })) return;
          readings.push({
            py: pronunciation,
            group: group,
            words: entry["例子"] || entry["组词"] || [],
            context: entry["语境"] || "",
            quickRule: entry["快速判断"] || ""
          });
        });
      });
      if (readings.length) map[ch] = readings;
    });
    if (!Object.keys(map).length) {
      showError("多音字表里没有可用的读音。");
      return;
    }
    var previousMap = polyphones;
    polyphones = map;
    if (!collectTopicItems().length) {
      polyphones = previousMap;
      rebuildTopic();
      showError("课文中没有找到多音字表里的汉字。");
      return;
    }
    polyRoot = data;
    mode = "polyphone";
    el.body.dataset.mode = mode;
    el.exitTopic.hidden = false;
    el.error.hidden = true;
    el.search.value = "";
    el.search.placeholder = "搜索课文 / 多音字…";
    el.body.dataset.state = "loaded";
    el.reader.hidden = false;
    el.pager.hidden = false;
    applyTopicMode();
  }

  // 按当前过滤开关重算待核对集合与目录
  function collectTopicItems() {
    rebuildTopic();
    return buildItems(root).filter(function (item) {
      item.topicCount = topicHitCount(item);
      return item.topicCount > 0;
    });
  }

  function applyTopicMode(preferTitle) {
    var list = collectTopicItems();
    if (!list.length) return false;
    items = list;
    var marked = Object.keys(topic).length;
    var all = Object.keys(polyphones).length;
    el.bookTitle.textContent = "多音字专题校正";
    el.bookMeta.textContent = (prefs.polyCommon ? marked + " / " + all : String(all)) +
      " 个多音字 · " +
      items.reduce(function (sum, item) { return sum + item.topicCount; }, 0) + " 处待核对";
    buildToc(el.search.value);
    var index = 0;
    if (preferTitle) {
      for (var i = 0; i < items.length; i++) {
        if (items[i].title === preferTitle) { index = i; break; }
      }
    }
    show(index);
    return true;
  }

  function leavePolyphoneMode() {
    if (!root) return;
    polyRoot = null;
    polyphones = {};
    mode = "reading";
    el.body.dataset.mode = mode;
    el.exitTopic.hidden = true;
    try { localStorage.removeItem(POLY_KEY); } catch (e) { /* 忽略 */ }
    items = buildItems(root);
    el.bookTitle.textContent = root["文件"] || "语文课本";
    el.bookMeta.textContent = items.length + " 篇 · 课文 " +
      count(items, "课文") + " · 园地 " + count(items, "园地") +
      " · 附录 " + count(items, "附录");
    el.search.value = "";
    el.search.placeholder = "搜索课文 / 园地…";
    buildToc("");
    show(0);
  }

  function count(list, kind) {
    return list.filter(function (x) { return x.kind === kind; }).length;
  }

  function buildItems(data) {
    var out = [];
    (data["课文"] || []).forEach(function (x) {
      out.push({
        kind: "课文",
        unit: x["单元"],
        title: x["标题"] || "（无题）",
        num: x["课号"],
        tag: x["栏目"],
        pages: x["页码"] || [],
        data: x
      });
    });
    (data["园地"] || []).forEach(function (x) {
      out.push({
        kind: "园地",
        unit: x["单元"],
        title: x["标题"] || "语文园地",
        num: null,
        tag: null,
        pages: x["页码"] || [],
        data: x
      });
    });
    var tables = {};
    (data["附录"] || []).forEach(function (row) {
      var name = row["模块"] || "附录";
      if (!tables[name]) {
        tables[name] = { kind: "附录", unit: null, title: name, num: null, tag: null, pages: [], rows: [] };
        out.push(tables[name]);
      }
      tables[name].rows.push(row);
    });
    out.sort(function (a, b) {
      var pa = a.pages[0] || 9999, pb = b.pages[0] || 9999;
      if (a.kind === "附录") pa = 10000 + out.indexOf(a);
      if (b.kind === "附录") pb = 10000 + out.indexOf(b);
      return pa - pb;
    });
    return out;
  }

  // 本册出现 + 常用 = 这个字在小学阶段真正可能读错的读音。
  // 只剩一个时，另一些读音全是生僻音，没有核对价值。
  function usefulReadings(readings) {
    return (readings || []).filter(function (r) { return r.group !== "不常用"; });
  }

  function rebuildTopic() {
    topic = {};
    Object.keys(polyphones).forEach(function (ch) {
      var readings = polyphones[ch];
      if (!prefs.polyCommon || usefulReadings(readings).length >= 2) topic[ch] = readings;
    });
  }

  function countPolyphones(text) {
    var total = 0;
    String(text || "").split("").forEach(function (ch) {
      if (topic[ch]) total++;
    });
    return total;
  }

  function topicHitCount(item) {
    if (item.kind === "课文") return countPolyphones(item.data["全文"]);
    if (item.kind === "园地") {
      return (item.data["栏目"] || []).reduce(function (sum, sec) {
        return sum + countPolyphones(sec["全文"]);
      }, 0);
    }
    if (item.kind === "附录") {
      return item.rows.reduce(function (sum, row) {
        return sum + (row["字"] || []).reduce(function (n, ch) {
          return n + (topic[ch] ? 1 : 0);
        }, 0);
      }, 0);
    }
    return 0;
  }

  /* ---------------- 目录 ---------------- */

  function buildToc(filter) {
    var q = (filter || "").trim();
    el.toc.textContent = "";
    var groups = [];
    var byKey = {};
    items.forEach(function (item, i) {
      if (q && !matches(item, q)) return;
      var key = item.kind === "附录" ? "附录" :
        (item.unit ? "第 " + item.unit + " 单元" : "其他");
      if (!byKey[key]) { byKey[key] = { name: key, list: [] }; groups.push(byKey[key]); }
      byKey[key].list.push({ item: item, index: i });
    });

    if (!groups.length) {
      var none = document.createElement("p");
      none.className = "toc-item";
      none.style.color = "var(--ink-faint)";
      none.textContent = "没有匹配的条目";
      el.toc.appendChild(none);
      return;
    }

    groups.forEach(function (group) {
      var box = document.createElement("details");
      box.className = "toc-group";
      box.open = true;
      var head = document.createElement("summary");
      head.textContent = group.name;
      box.appendChild(head);

      group.list.forEach(function (entry) {
        var btn = document.createElement("button");
        btn.className = "toc-item";
        btn.dataset.index = entry.index;
        if (entry.index === current) btn.setAttribute("aria-current", "true");

        var num = document.createElement("span");
        num.className = "toc-num";
        num.textContent = entry.item.num || (entry.item.kind === "课文" ? "·" : "");
        btn.appendChild(num);

        var title = document.createElement("span");
        title.className = "toc-title";
        title.textContent = entry.item.title;
        btn.appendChild(title);

        var label = mode === "polyphone" ? entry.item.topicCount + " 处" :
          (entry.item.tag || (entry.item.kind === "课文" ? null : entry.item.kind));
        if (label) {
          var tag = document.createElement("span");
          tag.className = "toc-tag";
          tag.textContent = label;
          btn.appendChild(tag);
        }
        btn.addEventListener("click", function () {
          show(entry.index);
          if (window.matchMedia("(max-width: 860px)").matches) toggleSidebar(false);
        });
        box.appendChild(btn);
      });
      el.toc.appendChild(box);
    });
  }

  function matches(item, q) {
    if (item.title.indexOf(q) >= 0) return true;
    if (item.num && item.num.indexOf(q) === 0) return true;
    if (mode === "polyphone" && q.length === 1 && topic[q]) {
      if (item.kind === "课文") return (item.data["全文"] || "").indexOf(q) >= 0;
      if (item.kind === "园地") return (item.data["栏目"] || []).some(function (sec) {
        return (sec["全文"] || "").indexOf(q) >= 0;
      });
      return item.rows.some(function (row) { return (row["字"] || []).indexOf(q) >= 0; });
    }
    if (q.length < 2) return false;
    var d = item.data;
    if (!d) return false;
    if (d["全文"] && d["全文"].indexOf(q) >= 0) return true;
    if (Array.isArray(d["栏目"])) {          // 园地：栏目是数组；课文的栏目是字符串
      return d["栏目"].some(function (sec) {
        return (sec["名称"] || "").indexOf(q) >= 0 || (sec["全文"] || "").indexOf(q) >= 0;
      });
    }
    return false;
  }

  function markActive() {
    Array.prototype.forEach.call(el.toc.querySelectorAll(".toc-item"), function (b) {
      if (Number(b.dataset.index) === current) {
        b.setAttribute("aria-current", "true");
        if (b.scrollIntoView) b.scrollIntoView({ block: "nearest" });
      } else {
        b.removeAttribute("aria-current");
      }
    });
  }

  /* ---------------- 数字声调 ⇄ 带调拼音 ---------------- */

  var TONE_ROWS = {
    a: "āáǎà", o: "ōóǒò", e: "ēéěè",
    i: "īíǐì", u: "ūúǔù", "ü": "ǖǘǚǜ"
  };

  // "bi4" / "lu:3" / "lv3" → "bì" / "lǚ"；非法返回 null，轻声返回无调
  function toMark(raw) {
    var s = String(raw == null ? "" : raw).trim().toLowerCase();
    if (!s) return "";
    s = s.replace(/u:/g, "ü").replace(/v/g, "ü");
    var m = s.match(/^([a-zü]+)([1-5])?$/);
    if (!m) return null;
    var body = m[1], tone = m[2] ? Number(m[2]) : 0;
    if (!tone || tone === 5) return body;
    var idx = body.indexOf("a");
    if (idx < 0) idx = body.indexOf("o");
    if (idx < 0) idx = body.indexOf("e");
    if (idx < 0) {
      for (var i = body.length - 1; i >= 0; i--) {
        if ("iuü".indexOf(body.charAt(i)) >= 0) { idx = i; break; }
      }
    }
    if (idx < 0) return body;
    var row = TONE_ROWS[body.charAt(idx)];
    return body.slice(0, idx) + row.charAt(tone - 1) + body.slice(idx + 1);
  }

  // "bì" → "bi4"，方便回填到输入框
  function toNumber(py) {
    var s = String(py == null ? "" : py), out = "", tone = "";
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i), hit = false;
      for (var base in TONE_ROWS) {
        var k = TONE_ROWS[base].indexOf(ch);
        if (k >= 0) { out += base === "ü" ? "v" : base; tone = String(k + 1); hit = true; break; }
      }
      if (!hit) out += ch === "ü" ? "v" : ch;
    }
    return out + tone;
  }

  // 一串（可能多音节）："chang2 jing3" → "cháng jǐng"
  function toMarkPhrase(raw) {
    var parts = String(raw == null ? "" : raw).trim().split(/\s+/).filter(Boolean);
    var out = [];
    for (var i = 0; i < parts.length; i++) {
      var one = toMark(parts[i]);
      if (one === null) return null;
      out.push(one);
    }
    return out.join(" ");
  }

  function toNumberPhrase(py) {
    return String(py == null ? "" : py).trim().split(/\s+/).filter(Boolean)
      .map(toNumber).join(" ");
  }

  /* ---------------- 注音渲染 ---------------- */

  // 拼音串按 " " 切开后与全文逐字对应
  function pair(text, pinyin) {
    var py = pinyin ? pinyin.split(" ") : [];
    var out = [];
    for (var i = 0; i < text.length; i++) {
      out.push({ ch: text.charAt(i), py: py.length === text.length ? py[i] : "" });
    }
    return out;
  }

  // 按句号断句；诗词按逗号也断
  function splitLines(chars, poem) {
    var stops = poem ? CLAUSE_END : SENTENCE_END;
    var lines = [], buf = [];
    for (var i = 0; i < chars.length; i++) {
      var c = chars[i];
      if (c.ch === " ") {                       // 园地条目之间的空格 = 换行
        // 练习中的全角括号会用空格留出填写位置，如“忄（ ）”。
        // 这个空格属于当前条目，不能被当作园地条目的分隔符。
        var prev = i > 0 ? chars[i - 1].ch : "";
        var next = i + 1 < chars.length ? chars[i + 1].ch : "";
        if (prev === "（" && next === "）") {
          buf.push(c);
          continue;
        }
        if (buf.length) { lines.push(buf); buf = []; }
        continue;
      }
      buf.push(c);
      if (stops.indexOf(c.ch) >= 0) {
        var nxt = i + 1 < chars.length ? chars[i + 1].ch : "";
        if (stops.indexOf(nxt) >= 0 || CLOSERS.indexOf(nxt) >= 0) continue;
        lines.push(buf); buf = [];
      }
    }
    if (buf.length) lines.push(buf);
    return lines;
  }

  function renderText(text, pinyin, poem, ctx) {
    var box = document.createElement("div");
    box.className = "text" + (poem ? " poem" : "");
    if (ctx) { box.dataset.editable = "1"; box._ctx = ctx; }
    var chars = pair(text || "", pinyin);
    var index = 0;
    splitLines(chars.map(function (c, i) { c.i = i; return c; }), poem).forEach(function (line) {
      var p = document.createElement("p");
      line.forEach(function (c) {
        var span = document.createElement("span");
        span.className = "ch";
        span.dataset.i = c.i;
        if (ctx && ctx.isFixed && ctx.isFixed(c.i)) span.classList.add("fixed");
        if (c.py && c.py !== c.ch) {
          var ruby = document.createElement("ruby");
          ruby.appendChild(document.createTextNode(c.ch));
          var rt = document.createElement("rt");
          rt.textContent = c.py;
          ruby.appendChild(rt);
          span.appendChild(ruby);
        } else {
          span.appendChild(document.createTextNode(c.ch));
        }
        p.appendChild(span);
        index++;
      });
      box.appendChild(p);
    });
    return box;
  }

  function renderTopicText(text, pinyin, poem, ctx) {
    var box = document.createElement("div");
    box.className = "topic-text";
    box.dataset.editable = "1";
    box._ctx = ctx;
    var chars = pair(text || "", pinyin);
    splitLines(chars.map(function (c, i) { c.i = i; return c; }), poem)
      .filter(function (line) {
        return line.some(function (c) { return !!topic[c.ch]; });
      })
      .forEach(function (line) {
        var p = document.createElement("p");
        p.className = "topic-line";
        line.forEach(function (c) {
          var span = document.createElement("span");
          span.className = "ch";
          span.dataset.i = c.i;
          if (topic[c.ch]) {
            span.classList.add("polyphone");
            span.title = "点击选择“" + c.ch + "”的读音";
            if (ctx.isFixed && ctx.isFixed(c.i)) span.classList.add("fixed");
            var ruby = document.createElement("ruby");
            ruby.appendChild(document.createTextNode(c.ch));
            var rt = document.createElement("rt");
            rt.textContent = c.py || "?";
            ruby.appendChild(rt);
            span.appendChild(ruby);
          } else {
            span.appendChild(document.createTextNode(c.ch));
          }
          p.appendChild(span);
        });
        box.appendChild(p);
      });
    return box;
  }

  function topicSummary(count) {
    var p = document.createElement("p");
    p.className = "topic-summary";
    p.textContent = "已省略不含多音字的正文，仅显示需要核对的 " + count +
      " 处。点击高亮字选择正确读音。";
    return p;
  }

  function renderTopicDoc(item) {
    var frag = document.createDocumentFragment();
    var d = item.data;
    frag.appendChild(head(item, {
      eyebrow: "多音字专题",
      meta: [item.topicCount + " 处待核对"]
    }));
    frag.appendChild(topicSummary(item.topicCount));

    if (item.kind === "课文") {
      var key = "课文:" + item.title;
      frag.appendChild(renderTopicText(d["全文"], d["拼音"], !!d["年代"], {
        key: key,
        path: ["课文", (root["课文"] || []).indexOf(d)],
        label: item.title,
        charAt: function (i) { return (d["全文"] || "").charAt(i); },
        getTokens: function () { return String(d["拼音"] || "").split(" "); },
        setTokens: function (arr) { d["拼音"] = arr.join(" "); },
        isFixed: isFixed(key)
      }));
      return frag;
    }

    (d["栏目"] || []).forEach(function (sec) {
      var hits = countPolyphones(sec["全文"]);
      if (!hits) return;
      var section = document.createElement("section");
      section.className = "sec";
      var title = document.createElement("div");
      title.className = "sec-title";
      title.textContent = (sec["名称"] || "（未命名栏目）") + " · " + hits + " 处";
      section.appendChild(title);
      var key = "园地:" + item.title + "/" + (sec["名称"] || "");
      section.appendChild(renderTopicText(sec["全文"], sec["拼音"], false, {
        key: key,
        path: ["园地", (root["园地"] || []).indexOf(d), "栏目", (d["栏目"] || []).indexOf(sec)],
        label: item.title + " · " + (sec["名称"] || ""),
        charAt: function (i) { return (sec["全文"] || "").charAt(i); },
        getTokens: function () { return String(sec["拼音"] || "").split(" "); },
        setTokens: function (arr) { sec["拼音"] = arr.join(" "); },
        isFixed: isFixed(key)
      }));
      frag.appendChild(section);
    });
    return frag;
  }

  function renderTopicRow(row, table) {
    var ctx = rowCtx(row, table);
    var box = document.createElement("div");
    box.className = "row topic-row";
    box._ctx = ctx;
    var label = document.createElement("div");
    label.className = "row-label";
    label.textContent = row["序号"] || "·";
    box.appendChild(label);
    var cards = document.createElement("div");
    cards.className = "cards";
    (row["字"] || []).forEach(function (ch, i) {
      if (!topic[ch]) return;
      var card = document.createElement("div");
      card.className = "card polyphone" + (ctx.isFixed(i) ? " fixed" : "");
      card.dataset.i = i;
      card.title = "点击选择“" + ch + "”的读音";
      var py = document.createElement("div");
      py.className = "py";
      py.textContent = (row["拼音"] || [])[i] || "?";
      var zi = document.createElement("div");
      zi.className = "zi";
      zi.textContent = ch;
      card.appendChild(py);
      card.appendChild(zi);
      cards.appendChild(card);
    });
    box.appendChild(cards);
    return box;
  }

  function renderTopicTable(item) {
    var frag = document.createDocumentFragment();
    frag.appendChild(head(item, {
      eyebrow: "多音字专题 · 附录单字",
      meta: [item.topicCount + " 处待核对"]
    }));
    frag.appendChild(topicSummary(item.topicCount));
    var rows = document.createElement("div");
    rows.className = "topic-rows";
    item.rows.forEach(function (row) {
      if ((row["字"] || []).some(function (ch) { return !!topic[ch]; })) {
        rows.appendChild(renderTopicRow(row, item.title));
      }
    });
    frag.appendChild(rows);
    return frag;
  }

  function renderTopicItem(item) {
    return item.kind === "附录" ? renderTopicTable(item) : renderTopicDoc(item);
  }

  /* ---------------- 页面渲染 ---------------- */

  function show(index) {
    if (index < 0 || index >= items.length) return;
    current = index;
    var item = items[index];
    el.reader.textContent = "";
    el.reader.appendChild(mode === "polyphone" ? renderTopicItem(item) :
      (item.kind === "附录" ? renderTable(item) : renderDoc(item)));
    el.crumb.textContent = crumbOf(item);
    el.prev.disabled = index === 0;
    el.next.disabled = index === items.length - 1;
    el.prev.textContent = index > 0 ? "‹ " + items[index - 1].title : "‹ 上一篇";
    el.next.textContent = index < items.length - 1 ? items[index + 1].title + " ›" : "下一篇 ›";
    markActive();
    prefs.last = index;
    applyPrefs();
    window.scrollTo({ top: 0, behavior: "auto" });
    el.reader.parentNode.scrollTop = 0;
  }

  function crumbOf(item) {
    var bits = [];
    if (mode === "polyphone") bits.push("多音字专题");
    if (item.unit) bits.push("第 " + item.unit + " 单元");
    if (item.kind !== "课文") bits.push(item.kind);
    if (item.pages.length) {
      bits.push("第 " + item.pages[0] +
        (item.pages.length > 1 ? "–" + item.pages[item.pages.length - 1] : "") + " 页");
    }
    return bits.join(" · ");
  }

  function head(item, extra) {
    var box = document.createElement("header");
    box.className = "doc-head";

    var eyebrow = document.createElement("div");
    eyebrow.className = "doc-eyebrow";
    eyebrow.textContent = extra.eyebrow || "";
    if (extra.eyebrow) box.appendChild(eyebrow);

    var h1 = document.createElement("h1");
    h1.className = "doc-title";
    h1.textContent = item.title;
    box.appendChild(h1);

    if (extra.sub) {
      var sub = document.createElement("div");
      sub.className = "doc-sub";
      sub.textContent = extra.sub;
      box.appendChild(sub);
    }
    if (extra.meta && extra.meta.length) {
      var meta = document.createElement("div");
      meta.className = "doc-meta";
      extra.meta.forEach(function (t) {
        var s = document.createElement("span");
        s.textContent = t;
        meta.appendChild(s);
      });
      box.appendChild(meta);
    }
    return box;
  }

  function renderDoc(item) {
    var frag = document.createDocumentFragment();
    var d = item.data;

    if (item.kind === "课文") {
      var eyebrow = [];
      if (d["课号"]) eyebrow.push("第 " + d["课号"] + " 课");
      if (d["课题"]) eyebrow.push(d["课题"]);
      if (d["栏目"]) eyebrow.push(d["栏目"]);
      var author = [];
      if (d["年代"]) author.push("〔" + d["年代"] + "〕");
      if (d["作者"]) author.push(d["作者"]);
      if (d["出处"]) author.push(d["出处"]);
      var meta = [];
      if (item.pages.length) meta.push("第 " + item.pages.join("、") + " 页");
      if (d["全文"]) meta.push(d["全文"].length + " 字");
      frag.appendChild(head(item, {
        eyebrow: eyebrow.join(" · "),
        sub: author.join(" "),
        meta: meta
      }));
      frag.appendChild(renderText(d["全文"], d["拼音"], !!d["年代"], {
        key: "课文:" + item.title,
        path: ["课文", (root["课文"] || []).indexOf(d)],
        label: item.title,
        charAt: function (i) { return (d["全文"] || "").charAt(i); },
        getTokens: function () { return String(d["拼音"] || "").split(" "); },
        setTokens: function (arr) { d["拼音"] = arr.join(" "); },
        isFixed: isFixed("课文:" + item.title)
      }));
      return frag;
    }

    // 语文园地
    frag.appendChild(head(item, {
      eyebrow: item.unit ? "第 " + item.unit + " 单元" : "",
      meta: item.pages.length ? ["第 " + item.pages.join("、") + " 页"] : []
    }));
    (d["栏目"] || []).forEach(function (sec) {
      var box = document.createElement("section");
      box.className = "sec";
      var title = document.createElement("div");
      title.className = "sec-title";
      title.textContent = sec["名称"] || "（未命名栏目）";
      box.appendChild(title);
      var key = "园地:" + item.title + "/" + (sec["名称"] || "");
      box.appendChild(renderText(sec["全文"], sec["拼音"], false, {
        key: key,
        path: ["园地", (root["园地"] || []).indexOf(d), "栏目", (d["栏目"] || []).indexOf(sec)],
        label: item.title + " · " + (sec["名称"] || ""),
        charAt: function (i) { return (sec["全文"] || "").charAt(i); },
        getTokens: function () { return String(sec["拼音"] || "").split(" "); },
        setTokens: function (arr) { sec["拼音"] = arr.join(" "); },
        isFixed: isFixed(key)
      }));
      frag.appendChild(box);
    });
    return frag;
  }

  function renderTable(item) {
    var frag = document.createDocumentFragment();
    var pages = [];
    item.rows.forEach(function (r) { if (r["页码"]) pages.push(r["页码"]); });
    frag.appendChild(head(item, {
      eyebrow: "附录",
      meta: [item.rows.length + " 组"]
    }));

    // “分组”在附录中是一个连续区段标签，不是全表范围内的分类。
    // 同名分组可能在后面再次出现（例如“阅读 → 识字 → 阅读”）；
    // 只合并相邻行，才能保留 PDF / JSON 中原有的穿插顺序。
    var groups = [];
    item.rows.forEach(function (row) {
      var name = row["分组"] || "";
      var group = groups[groups.length - 1];
      if (!group || group.name !== name) {
        group = { name: name, rows: [] };
        groups.push(group);
      }
      group.rows.push(row);
    });

    groups.forEach(function (group) {
      var sec = document.createElement("section");
      sec.className = "sec";
      if (group.name) {
        var title = document.createElement("div");
        title.className = "sec-title";
        title.textContent = group.name;
        sec.appendChild(title);
      }
      var rows = document.createElement("div");
      rows.className = "rows";
      group.rows.forEach(function (row) {
        rows.appendChild(renderRow(row, item.title));
      });
      sec.appendChild(rows);
      frag.appendChild(sec);
    });
    return frag;
  }

  function rowCtx(row, table) {
    var key = "附录:" + table + "/" + (row["分组"] || "") + "/" + (row["序号"] || "");
    var list = (row["字"] && row["字"].length) ? row["字"] : (row["词"] || []);
    return {
      key: key,
      path: ["附录", (root["附录"] || []).indexOf(row)],
      label: table + " " + (row["序号"] || ""),
      word: !(row["字"] && row["字"].length),
      charAt: function (i) { return list[i]; },
      getTokens: function () { return (row["拼音"] || []).slice(); },
      setTokens: function (arr) { row["拼音"] = arr; },
      isFixed: isFixed(key)
    };
  }

  function renderRow(row, table) {
    var ctx = rowCtx(row, table);
    var box = document.createElement("div");
    box.className = "row";
    box._ctx = ctx;
    var label = document.createElement("div");
    label.className = "row-label";
    label.textContent = row["序号"] || "·";
    box.appendChild(label);

    var cards = document.createElement("div");
    cards.className = "cards";
    var list = (row["字"] && row["字"].length) ? row["字"] : (row["词"] || []);
    var isWord = !(row["字"] && row["字"].length);
    list.forEach(function (text, i) {
      var card = document.createElement("div");
      card.className = "card" + (isWord ? " word" : "") + (ctx.isFixed(i) ? " fixed" : "");
      card.dataset.i = i;
      card.title = "点击修改注音";
      var py = document.createElement("div");
      py.className = "py";
      py.textContent = (row["拼音"] || [])[i] || "";
      var zi = document.createElement("div");
      zi.className = "zi";
      zi.textContent = text;
      card.appendChild(py);
      card.appendChild(zi);
      cards.appendChild(card);
    });
    box.appendChild(cards);
    return box;
  }

  /* ---------------- 注音修正 ---------------- */

  var MAX_CELLS = 24;
  var pop = {
    box: document.getElementById("popover"),
    backdrop: document.getElementById("popBackdrop"),
    title: document.getElementById("popTitle"),
    hint: document.getElementById("popHint"),
    body: document.getElementById("popBody"),
    err: document.getElementById("popErr"),
    ok: document.getElementById("popOk")
  };
  var editing = null;   // { ctx, indices }

  // 用 path 在 root 里定位到那条拼音，读写都走它 —— 这样修正记录能存盘
  function accessor(path) {
    var node = root;
    for (var i = 0; i < path.length; i++) node = node[path[i]];
    if (Array.isArray(node["拼音"])) {
      return {
        get: function () { return node["拼音"].slice(); },
        set: function (arr) { node["拼音"] = arr; }
      };
    }
    return {
      get: function () { return String(node["拼音"] || "").split(" "); },
      set: function (arr) { node["拼音"] = arr.join(" "); }
    };
  }

  function restoreFix(f) {
    try {
      var acc = accessor(f.path);
      var t = acc.get();
      t[f.i] = f.from;
      acc.set(t);
    } catch (e) { /* 数据换了就跳过 */ }
  }

  function isFixed(key) {
    return function (i) {
      for (var n = 0; n < fixes.length; n++) {
        if (fixes[n].key === key && fixes[n].i === i) return true;
      }
      return false;
    };
  }

  function openEditor(ctx, indices, rect) {
    if (!indices.length) return;
    if (indices.length > MAX_CELLS) indices = indices.slice(0, MAX_CELLS);
    editing = { ctx: ctx, indices: indices };
    pop.title.textContent = "修改注音 · " + ctx.label +
      (indices.length > 1 ? "（" + indices.length + " 处）" : "");
    pop.err.textContent = "";
    pop.body.textContent = "";
    pop.hint.hidden = false;
    pop.ok.hidden = false;

    var tokens = ctx.getTokens();
    indices.forEach(function (i) {
      var cell = document.createElement("label");
      cell.className = "pop-cell" + (ctx.word ? " wide" : "");
      var zi = document.createElement("span");
      zi.className = "zi";
      zi.textContent = ctx.charAt(i);
      var input = document.createElement("input");
      input.type = "text";
      input.spellcheck = false;
      input.dataset.i = i;
      input.value = toNumberPhrase(tokens[i] || "");
      cell.appendChild(zi);
      cell.appendChild(input);
      pop.body.appendChild(cell);
    });

    pop.box.hidden = false;
    pop.backdrop.hidden = false;
    place(rect);
    var first = pop.body.querySelector("input");
    if (first) { first.focus(); first.select(); }
  }

  function openChoiceEditor(ctx, index, rect) {
    var ch = ctx.charAt(index);
    var readings = polyphones[ch] || [];
    if (!readings.length) return;
    editing = { ctx: ctx, indices: [index], choice: true };
    pop.title.textContent = "选择读音 · " + ch + " · " + ctx.label;
    pop.err.textContent = "";
    pop.hint.hidden = true;
    pop.ok.hidden = true;
    pop.body.textContent = "";
    var list = document.createElement("div");
    list.className = "choice-list";
    var currentPy = ctx.getTokens()[index] || "";
    readings.forEach(function (reading) {
      var button = document.createElement("button");
      button.type = "button";
      button.className = "choice-btn";
      if (reading.py === currentPy) button.setAttribute("aria-current", "true");
      var py = document.createElement("span");
      py.className = "choice-py";
      py.textContent = reading.py;
      var group = document.createElement("span");
      group.className = "choice-group";
      group.textContent = reading.group;
      var words = document.createElement("span");
      words.className = "choice-words";
      words.textContent = reading.words.length ? reading.words.join(" · ") : "暂无例子";
      var context = document.createElement("span");
      context.className = "choice-context";
      context.textContent = reading.context;
      context.hidden = !reading.context;
      var quickRule = document.createElement("span");
      quickRule.className = "choice-rule";
      quickRule.textContent = reading.quickRule ? "判断：" + reading.quickRule : "";
      quickRule.hidden = !reading.quickRule;
      button.appendChild(py);
      button.appendChild(group);
      button.appendChild(words);
      button.appendChild(context);
      button.appendChild(quickRule);
      button.addEventListener("click", function () {
        applyChoice(ctx, index, reading.py);
      });
      list.appendChild(button);
    });
    pop.body.appendChild(list);
    pop.box.hidden = false;
    pop.backdrop.hidden = false;
    place(rect);
    var active = list.querySelector('[aria-current="true"]') || list.querySelector("button");
    if (active) active.focus();
  }

  function applyChoice(ctx, index, py) {
    var tokens = ctx.getTokens();
    var from = tokens[index] == null ? "" : tokens[index];
    if (from !== py) {
      tokens[index] = py;
      fixes.push({
        key: ctx.key, path: ctx.path, label: ctx.label,
        i: index, ch: ctx.charAt(index), from: from, to: py
      });
      ctx.setTokens(tokens);
      persist();
      renderFixbar();
    }
    closeEditor();
    if (from !== py) refresh();
  }

  function place(rect) {
    var w = pop.box.offsetWidth, h = pop.box.offsetHeight;
    var left = rect ? rect.left + rect.width / 2 - w / 2 : (window.innerWidth - w) / 2;
    var top = rect ? rect.bottom + 10 : (window.innerHeight - h) / 2;
    if (rect && top + h > window.innerHeight - 12) top = Math.max(12, rect.top - h - 10);
    pop.box.style.left = Math.max(12, Math.min(left, window.innerWidth - w - 12)) + "px";
    pop.box.style.top = Math.max(12, top) + "px";
  }

  function closeEditor() {
    editing = null;
    pop.box.hidden = true;
    pop.backdrop.hidden = true;
  }

  function submitEditor() {
    if (!editing) return;
    var ctx = editing.ctx;
    var tokens = ctx.getTokens();
    var inputs = pop.body.querySelectorAll("input");
    var edits = [], bad = null;

    Array.prototype.forEach.call(inputs, function (input) {
      input.classList.remove("bad");
      var py = toMarkPhrase(input.value);
      if (py === null) { input.classList.add("bad"); bad = bad || input; return; }
      edits.push({ i: Number(input.dataset.i), py: py });
    });
    if (bad) {
      pop.err.textContent = "格式不对：只能是字母加 1–5，如 bi4、lu:3";
      bad.focus();
      return;
    }

    var changed = 0;
    edits.forEach(function (e) {
      var from = tokens[e.i] == null ? "" : tokens[e.i];
      if (from === e.py) return;
      tokens[e.i] = e.py;
      fixes.push({
        key: ctx.key, path: ctx.path, label: ctx.label,
        i: e.i, ch: ctx.charAt(e.i), from: from, to: e.py
      });
      changed++;
    });
    if (changed) {
      ctx.setTokens(tokens);
      persist();
      renderFixbar();
      refresh();
    }
    closeEditor();
  }

  function persist() {
    try {
      localStorage.setItem(STORE_KEY, JSON.stringify(root));
      localStorage.setItem(FIX_KEY, JSON.stringify(fixes));
    } catch (e) { /* 太大就算了 */ }
  }

  function refresh() {
    var y = window.scrollY;
    show(current);
    window.scrollTo(0, y);
  }

  function renderFixbar() {
    var bar = document.getElementById("fixbar");
    var log = document.getElementById("fixlog");
    document.getElementById("fixCount").textContent = "已修正 " + fixes.length + " 处";
    bar.hidden = fixes.length === 0;
    if (fixes.length === 0) log.hidden = true;
    if (!log.hidden) renderFixLog();
  }

  function renderFixLog() {
    var log = document.getElementById("fixlog");
    log.textContent = "";
    fixes.slice().reverse().forEach(function (f) {
      var line = document.createElement("div");
      var b = document.createElement("b"); b.textContent = f.ch;
      var from = document.createElement("s"); from.textContent = f.from || "（无）";
      var to = document.createElement("em"); to.textContent = f.to || "（无）";
      line.appendChild(b);
      line.appendChild(document.createTextNode("  "));
      line.appendChild(from);
      line.appendChild(document.createTextNode(" → "));
      line.appendChild(to);
      line.appendChild(document.createTextNode("　" + f.label));
      log.appendChild(line);
    });
  }

  // 选中正文 → 弹窗
  function pickFromSelection() {
    var sel = window.getSelection();
    if (!sel || sel.rangeCount === 0) return false;
    var range = sel.getRangeAt(0);
    var node = range.startContainer;
    var box = (node.nodeType === 1 ? node : node.parentNode);
    box = box && box.closest ? box.closest("[data-editable]") : null;
    if (!box || !box._ctx) return false;

    var picked = [];
    Array.prototype.forEach.call(box.querySelectorAll(".ch"), function (cell) {
      if (range.intersectsNode(cell)) picked.push(Number(cell.dataset.i));
    });
    if (!picked.length) return false;
    openEditor(box._ctx, picked, range.getBoundingClientRect());
    sel.removeAllRanges();
    return true;
  }

  el.reader.addEventListener("mouseup", function (e) {
    if (!pop.box.hidden) return;
    var target = e.target;
    var card = target.closest ? target.closest(".card") : null;
    if (card) {
      var row = card.closest(".row");
      if (row && row._ctx) {
        if (mode === "polyphone") {
          openChoiceEditor(row._ctx, Number(card.dataset.i), card.getBoundingClientRect());
        } else {
          openEditor(row._ctx, [Number(card.dataset.i)], card.getBoundingClientRect());
        }
        return;
      }
    }
    if (mode === "polyphone") {
      var topicCell = target.closest ? target.closest(".ch.polyphone") : null;
      var topicBox = topicCell && topicCell.closest ? topicCell.closest("[data-editable]") : null;
      if (topicCell && topicBox && topicBox._ctx) {
        openChoiceEditor(topicBox._ctx, Number(topicCell.dataset.i), topicCell.getBoundingClientRect());
      }
      return;
    }
    setTimeout(function () {
      var sel = window.getSelection();
      if (sel && sel.rangeCount && !sel.isCollapsed) { pickFromSelection(); return; }
      // 单击：直接用点到的那个字（ruby 让盒子变高，光标位置不可靠）
      var cell = target.closest ? target.closest(".ch") : null;
      var box = cell && cell.closest ? cell.closest("[data-editable]") : null;
      if (cell && box && box._ctx) {
        openEditor(box._ctx, [Number(cell.dataset.i)], cell.getBoundingClientRect());
      }
    }, 0);
  });

  pop.backdrop.addEventListener("mousedown", closeEditor);
  document.getElementById("popCancel").addEventListener("click", closeEditor);
  document.getElementById("popOk").addEventListener("click", submitEditor);
  pop.body.addEventListener("keydown", function (e) {
    if (e.key === "Enter") { e.preventDefault(); submitEditor(); }
    else if (e.key === "Escape") { e.preventDefault(); closeEditor(); }
  });

  document.getElementById("fixUndo").addEventListener("click", function () {
    var last = fixes.pop();
    if (!last) return;
    restoreFix(last);
    persist();
    renderFixbar();
    refresh();
  });

  document.getElementById("fixReset").addEventListener("click", function () {
    while (fixes.length) restoreFix(fixes.pop());
    persist();
    renderFixbar();
    refresh();
  });

  document.getElementById("fixList").addEventListener("click", function () {
    var log = document.getElementById("fixlog");
    log.hidden = !log.hidden;
    if (!log.hidden) renderFixLog();
  });

  document.getElementById("fixDownload").addEventListener("click", function () {
    var blob = new Blob([JSON.stringify(root, null, 2)], { type: "application/json" });
    var url = URL.createObjectURL(blob);
    var link = document.createElement("a");
    link.href = url;
    link.download = "struct.json";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  });

  /* ---------------- 交互 ---------------- */

  function toggleSidebar(on) {
    prefs.sidebar = (typeof on === "boolean" ? on : prefs.sidebar !== "on") ? "on" : "off";
    applyPrefs();
  }

  /* 拖动侧栏边缘改变宽度 */
  (function () {
    var handle = document.getElementById("resizer");
    if (!handle) return;
    var dragging = false;

    handle.addEventListener("pointerdown", function (e) {
      dragging = true;
      handle.setPointerCapture(e.pointerId);
      el.body.dataset.resizing = "1";
      e.preventDefault();
    });

    handle.addEventListener("pointermove", function (e) {
      if (!dragging) return;
      var w = Math.round(Math.min(WIDTH_MAX, Math.max(WIDTH_MIN, e.clientX)));
      prefs.width = w;
      document.documentElement.style.setProperty("--sidebar-w", w + "px");
    });

    function stop(e) {
      if (!dragging) return;
      dragging = false;
      if (e && e.pointerId !== undefined && handle.hasPointerCapture(e.pointerId)) {
        handle.releasePointerCapture(e.pointerId);
      }
      delete el.body.dataset.resizing;
      applyPrefs();
    }
    handle.addEventListener("pointerup", stop);
    handle.addEventListener("pointercancel", stop);

    handle.addEventListener("dblclick", function () {
      prefs.width = WIDTH_DEFAULT;
      applyPrefs();
    });
  })();

  document.getElementById("collapseBtn").addEventListener("click", function () { toggleSidebar(false); });
  document.getElementById("railBtn").addEventListener("click", function () { toggleSidebar(true); });
  document.getElementById("menuBtn").addEventListener("click", function () { toggleSidebar(true); });
  el.exitTopic.addEventListener("click", leavePolyphoneMode);
  el.backdrop.addEventListener("click", function () { toggleSidebar(false); });

  if (el.commonBtn) {
    el.commonBtn.addEventListener("click", function () {
      if (mode !== "polyphone") return;
      var keep = items[current] ? items[current].title : null;
      prefs.polyCommon = !prefs.polyCommon;
      if (!applyTopicMode(keep)) {           // 过滤后没有要核对的了，退回上一档
        prefs.polyCommon = !prefs.polyCommon;
        applyTopicMode(keep);
        showError("按“只核对常用”过滤后没有需要核对的字了。");
      }
      applyPrefs();
    });
  }

  el.pinyinBtn.addEventListener("click", function () {
    prefs.pinyin = prefs.pinyin === "on" ? "off" : "on";
    applyPrefs();
  });

  el.fontBtn.addEventListener("click", function () {
    var order = ["kai", "song", "hei"];
    prefs.font = order[(order.indexOf(prefs.font) + 1) % order.length];
    applyPrefs();
  });

  document.getElementById("bigger").addEventListener("click", function () {
    prefs.size = Math.min(34, prefs.size + 2); applyPrefs();
  });
  document.getElementById("smaller").addEventListener("click", function () {
    prefs.size = Math.max(15, prefs.size - 2); applyPrefs();
  });

  el.prev.addEventListener("click", function () { show(current - 1); });
  el.next.addEventListener("click", function () { show(current + 1); });

  el.search.addEventListener("input", function () { buildToc(el.search.value); });

  document.addEventListener("keydown", function (e) {
    if (e.target.tagName === "INPUT") {
      if (e.key === "Escape") { e.target.value = ""; buildToc(""); e.target.blur(); }
      return;
    }
    if (!pop.box.hidden) {
      if (e.key === "Escape") closeEditor();
      return;
    }
    if (e.key === "ArrowLeft") show(current - 1);
    else if (e.key === "ArrowRight") show(current + 1);
    else if (e.key === "[") toggleSidebar();
    else if (e.key === "/") { e.preventDefault(); toggleSidebar(true); el.search.focus(); }
    else if (e.key === "p") { prefs.pinyin = prefs.pinyin === "on" ? "off" : "on"; applyPrefs(); }
  });

  ["fileInput", "fileInput2", "polyphoneInput"].forEach(function (id) {
    var input = document.getElementById(id);
    if (input) {
      input.addEventListener("change", function () {
        if (input.files && input.files[0]) readFile(input.files[0]);
        input.value = "";
      });
    }
  });

  ["dragenter", "dragover"].forEach(function (type) {
    document.addEventListener(type, function (e) {
      e.preventDefault();
      el.body.classList.add("dragging");
    });
  });
  ["dragleave", "drop"].forEach(function (type) {
    document.addEventListener(type, function (e) {
      e.preventDefault();
      if (type === "drop" && e.dataTransfer && e.dataTransfer.files[0]) {
        readFile(e.dataTransfer.files[0]);
      }
      if (type === "drop" || e.relatedTarget === null) el.body.classList.remove("dragging");
    });
  });

  window.addEventListener("resize", function () { applyPrefs(); });

  /* ---------------- 启动 ---------------- */

  loadPrefs();
  try {
    var cached = localStorage.getItem(STORE_KEY);
    if (cached) {
      useData(JSON.parse(cached));
      var cachedPolyphone = localStorage.getItem(POLY_KEY);
      if (cachedPolyphone && root) usePolyphoneData(JSON.parse(cachedPolyphone));
      var log = localStorage.getItem(FIX_KEY);
      if (log && root) {
        fixes = JSON.parse(log) || [];
        renderFixbar();
        if (current >= 0) refresh();
      }
    }
  } catch (e) { /* 忽略缓存问题 */ }
})();
