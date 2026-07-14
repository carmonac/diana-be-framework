(() => {
  'use strict';

  // ===== Elements =====
  const sidebar = document.getElementById('sidebar');
  const menuToggle = document.getElementById('menuToggle');
  const themeToggle = document.getElementById('themeToggle');
  const searchInput = document.getElementById('search');
  const searchResults = document.getElementById('searchResults');
  const breadcrumb = document.getElementById('breadcrumb');
  const content = document.getElementById('content');

  // ===== Page titles map =====
  const pageTitles = {
    'home': 'Overview',
    'getting-started': 'Getting Started',
    'tutorial': 'Tutorial: Build a Bookstore API',
    'architecture': 'Architecture',
    'di': 'Dependency Injection',
    'controllers': 'Controllers & Routing',
    'middleware': 'Middleware',
    'configuration': 'Configuration',
    'validation': 'Validation',
    'error-handling': 'Error Handling',
    'websockets': 'WebSockets',
    'lifecycle': 'Application Lifecycle',
    'events': 'Application Events',
    'cors-static': 'CORS & Static Files',
    'content-negotiation': 'Content Negotiation',
    'sse': 'Server-Sent Events',
    'grpc': 'gRPC',
    'auth': 'Authentication & Authorization',
    'persistence': 'Persistence',
    'openapi': 'OpenAPI',
    'observability': 'Observability',
    'operations': 'Operations',
    'json': 'JSON Serialization',
    'testing': 'Testing',
    'annotations': 'Annotations Reference',
    'runtime-api': 'Runtime API',
    'generated-code': 'Generated Code',
    'build-diagnostics': 'Build Diagnostics',
    'config-keys': 'Configuration Keys',
    'troubleshooting': 'Troubleshooting & FAQ',
  };

  // ===== Search index (built from page content) =====
  const searchIndex = [];

  function buildSearchIndex() {
    searchIndex.length = 0;
    document.querySelectorAll('.page').forEach(page => {
      const pageId = page.id.replace('page-', '');
      const title = pageTitles[pageId] || pageId;
      const text = page.textContent || '';
      // Chunk into sentences for context
      const chunks = text.split(/[.!?]\s+/).filter(s => s.trim().length > 20);
      chunks.forEach(chunk => {
        searchIndex.push({ page: pageId, title, text: chunk.trim().slice(0, 120) });
      });
    });
  }

  function doSearch(query) {
    if (!query || query.length < 2) {
      searchResults.classList.remove('visible');
      return;
    }
    const q = query.toLowerCase();
    const hits = searchIndex
      .filter(item => item.text.toLowerCase().includes(q))
      .slice(0, 10);

    if (hits.length === 0) {
      searchResults.innerHTML = '<div class="search-result-item"><span class="search-result-title">No results found</span></div>';
      searchResults.classList.add('visible');
      return;
    }

    searchResults.innerHTML = hits.map(hit =>
      `<div class="search-result-item" data-page="${hit.page}">
        <div class="search-result-title">${hit.title}</div>
        <div class="search-result-context">${highlightText(hit.text, query)}</div>
      </div>`
    ).join('');
    searchResults.classList.add('visible');

    searchResults.querySelectorAll('.search-result-item[data-page]').forEach(item => {
      item.addEventListener('click', () => {
        navigateTo(item.dataset.page);
        searchResults.classList.remove('visible');
        searchInput.value = '';
      });
    });
  }

  function highlightText(text, query) {
    const idx = text.toLowerCase().indexOf(query.toLowerCase());
    if (idx === -1) return escapeHtml(text);
    const before = text.slice(0, idx);
    const match = text.slice(idx, idx + query.length);
    const after = text.slice(idx + query.length);
    return `${escapeHtml(before)}<mark>${escapeHtml(match)}</mark>${escapeHtml(after)}`;
  }

  function escapeHtml(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  // ===== Navigation =====
  function navigateTo(pageId) {
    // Check if page exists
    const page = document.getElementById(`page-${pageId}`);
    if (!page) return;

    // Hide all pages
    document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));

    // Show target page
    page.classList.add('active');

    // Update nav links
    document.querySelectorAll('.nav-link').forEach(link => {
      link.classList.toggle('active', link.dataset.page === pageId);
    });

    // Update breadcrumb
    breadcrumb.textContent = pageTitles[pageId] || pageId;

    // Update URL hash
    window.location.hash = pageId;

    // Scroll to top
    window.scrollTo({ top: 0, behavior: 'smooth' });

    // Close mobile sidebar
    sidebar.classList.remove('open');
    document.querySelector('.sidebar-overlay')?.remove();
  }

  // Nav link clicks
  document.querySelectorAll('.nav-link').forEach(link => {
    link.addEventListener('click', e => {
      e.preventDefault();
      const pageId = link.dataset.page;
      navigateTo(pageId);
    });
  });

  // ===== Theme toggle =====
  function getTheme() {
    return localStorage.getItem('diana-docs-theme') || 'dark';
  }

  function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('diana-docs-theme', theme);
  }

  setTheme(getTheme());

  themeToggle.addEventListener('click', () => {
    const current = getTheme();
    setTheme(current === 'dark' ? 'light' : 'dark');
  });

  // ===== Mobile menu =====
  menuToggle.addEventListener('click', () => {
    const isOpen = sidebar.classList.toggle('open');
    if (isOpen) {
      const overlay = document.createElement('div');
      overlay.className = 'sidebar-overlay visible';
      overlay.addEventListener('click', () => {
        sidebar.classList.remove('open');
        overlay.remove();
      });
      document.body.appendChild(overlay);
    } else {
      document.querySelector('.sidebar-overlay')?.remove();
    }
  });

  // ===== Search =====
  buildSearchIndex();

  let searchTimeout;
  searchInput.addEventListener('input', () => {
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(() => doSearch(searchInput.value.trim()), 150);
  });

  searchInput.addEventListener('keydown', e => {
    if (e.key === 'Escape') {
      searchResults.classList.remove('visible');
      searchInput.blur();
    }
  });

  document.addEventListener('click', e => {
    if (!searchResults.contains(e.target) && e.target !== searchInput) {
      searchResults.classList.remove('visible');
    }
  });

  // ===== Tabs =====
  document.querySelectorAll('.tabs').forEach(tabGroup => {
    tabGroup.querySelectorAll('.tab').forEach(tab => {
      tab.addEventListener('click', () => {
        tabGroup.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        tab.classList.add('active');

        const tabId = tab.dataset.tab;
        const parent = tabGroup.parentElement;
        parent.querySelectorAll('.tab-content').forEach(tc => tc.classList.remove('active'));
        const target = parent.querySelector(`#tab-${tabId}`);
        if (target) target.classList.add('active');
      });
    });
  });

  // ===== Hash routing on load =====
  function handleHash() {
    const hash = window.location.hash.slice(1);
    if (hash && document.getElementById(`page-${hash}`)) {
      navigateTo(hash);
    } else {
      navigateTo('home');
    }
  }

  window.addEventListener('hashchange', handleHash);
  handleHash();

  // ===== Tokenizer-based syntax highlighter =====
  function tokenize(code) {
    const tokens = [];
    let pos = 0;
    const len = code.length;

    const keywords = new Set([
      'import', 'class', 'extends', 'implements', 'abstract', 'interface',
      'final', 'const', 'late', 'static', 'return', 'if', 'else', 'for', 'while', 'do',
      'switch', 'case', 'break', 'continue', 'new', 'this', 'super', 'void', 'async',
      'await', 'throw', 'try', 'catch', 'finally', 'required', 'override', 'as', 'is',
      'in', 'part', 'library', 'enum', 'sealed', 'mixin', 'with', 'on',
      'show', 'hide', 'typedef', 'factory', 'get', 'set', 'operator',
    ]);

    const types = new Set([
      'String', 'int', 'double', 'bool', 'num', 'List', 'Map', 'Set', 'Future',
      'Stream', 'dynamic', 'var', 'Object', 'Exception', 'DateTime', 'Uri', 'Duration',
      'Stopwatch', 'DianaConfig', 'DianaServer', 'DianaContext', 'DianaRequest',
      'DianaResponse', 'BodyCodec', 'HttpException', 'ValidationException', 'Next',
      'DianaHandler', 'Middleware', 'WebSocketSession', 'BodyCodecRegistry',
    ]);

    function charAt(i) { return i < len ? code[i] : ''; }

    while (pos < len) {
      // Block comments
      if (code[pos] === '/' && code[pos + 1] === '*') {
        let end = code.indexOf('*/', pos + 2);
        end = end === -1 ? len : end + 2;
        tokens.push({ type: 'comment', value: code.slice(pos, end) });
        pos = end;
        continue;
      }

      // Line comments
      if (code[pos] === '/' && code[pos + 1] === '/') {
        let end = code.indexOf('\n', pos);
        end = end === -1 ? len : end;
        tokens.push({ type: 'comment', value: code.slice(pos, end) });
        pos = end;
        continue;
      }

      // Triple-quoted strings
      if (code.slice(pos, pos + 3) === "'''" || code.slice(pos, pos + 3) === '"""') {
        const q = code.slice(pos, pos + 3);
        let end = code.indexOf(q, pos + 3);
        end = end === -1 ? len : end + 3;
        tokens.push({ type: 'string', value: code.slice(pos, end) });
        pos = end;
        continue;
      }

      // Single-quoted strings
      if (code[pos] === "'") {
        let i = pos + 1;
        while (i < len && code[i] !== "'" && code[i] !== '\n') {
          if (code[i] === '\\') i++;
          i++;
        }
        if (i < len && code[i] === "'") i++;
        tokens.push({ type: 'string', value: code.slice(pos, i) });
        pos = i;
        continue;
      }

      // Double-quoted strings
      if (code[pos] === '"') {
        let i = pos + 1;
        while (i < len && code[i] !== '"') {
          if (code[i] === '\\') i++;
          i++;
        }
        if (i < len && code[i] === '"') i++;
        tokens.push({ type: 'string', value: code.slice(pos, i) });
        pos = i;
        continue;
      }

      // Annotations
      if (code[pos] === '@' && /[a-zA-Z_]/.test(charAt(pos + 1))) {
        let i = pos + 1;
        while (i < len && /[a-zA-Z0-9_]/.test(code[i])) i++;
        tokens.push({ type: 'annotation', value: code.slice(pos, i) });
        pos = i;
        continue;
      }

      // Numbers (only at word start, not inside other tokens)
      if (/[0-9]/.test(code[pos]) && (pos === 0 || !/[a-zA-Z0-9_]/.test(code[pos - 1]))) {
        let i = pos;
        while (i < len && /[0-9.]/.test(code[i])) i++;
        tokens.push({ type: 'number', value: code.slice(pos, i) });
        pos = i;
        continue;
      }

      // Words (keywords, types, identifiers)
      if (/[a-zA-Z_]/.test(code[pos])) {
        let i = pos;
        while (i < len && /[a-zA-Z0-9_]/.test(code[i])) i++;
        const word = code.slice(pos, i);
        if (keywords.has(word)) tokens.push({ type: 'keyword', value: word });
        else if (types.has(word)) tokens.push({ type: 'type', value: word });
        else tokens.push({ type: 'plain', value: word });
        pos = i;
        continue;
      }

      // Everything else (operators, punctuation, whitespace, newlines)
      tokens.push({ type: 'plain', value: code[pos] });
      pos++;
    }

    return tokens;
  }

  function escapeHtml(str) {
    return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function renderTokens(tokens) {
    const classMap = {
      keyword: 'hl-keyword',
      type: 'hl-type',
      string: 'hl-string',
      comment: 'hl-comment',
      annotation: 'hl-annotation',
      number: 'hl-number',
      plain: null,
    };
    let out = '';
    for (const t of tokens) {
      const cls = classMap[t.type];
      const escaped = escapeHtml(t.value);
      if (cls) out += '<span class="' + cls + '">' + escaped + '</span>';
      else out += escaped;
    }
    return out;
  }

  function highlightDart(code) {
    return renderTokens(tokenize(code));
  }

  function highlightBash(code) {
    const tokens = [];
    let pos = 0;
    const len = code.length;

    while (pos < len) {
      // Comments
      if (code[pos] === '#') {
        let end = code.indexOf('\n', pos);
        end = end === -1 ? len : end;
        tokens.push({ type: 'comment', value: code.slice(pos, end) });
        pos = end;
        continue;
      }
      // Single-quoted strings
      if (code[pos] === "'") {
        let i = pos + 1;
        while (i < len && code[i] !== "'") { if (code[i] === '\\') i++; i++; }
        if (i < len) i++;
        tokens.push({ type: 'string', value: code.slice(pos, i) });
        pos = i;
        continue;
      }
      // Double-quoted strings
      if (code[pos] === '"') {
        let i = pos + 1;
        while (i < len && code[i] !== '"') { if (code[i] === '\\') i++; i++; }
        if (i < len) i++;
        tokens.push({ type: 'string', value: code.slice(pos, i) });
        pos = i;
        continue;
      }
      // Variables
      if (code[pos] === '$' && /[a-zA-Z{]/.test(code[pos + 1] || '')) {
        let i = pos + 1;
        if (code[i] === '{') { while (i < len && code[i] !== '}') i++; if (i < len) i++; }
        else { while (i < len && /[a-zA-Z0-9_]/.test(code[i])) i++; }
        tokens.push({ type: 'variable', value: code.slice(pos, i) });
        pos = i;
        continue;
      }
      tokens.push({ type: 'plain', value: code[pos] });
      pos++;
    }

    const classMap = { comment: 'hl-comment', string: 'hl-string', variable: 'hl-type', plain: null };
    let out = '';
    for (const t of tokens) {
      const cls = classMap[t.type];
      const escaped = escapeHtml(t.value);
      if (cls) out += '<span class="' + cls + '">' + escaped + '</span>';
      else out += escaped;
    }
    return out;
  }

  function highlightYaml(code) {
    const tokens = [];
    let pos = 0;
    const len = code.length;

    while (pos < len) {
      // Comments
      if (code[pos] === '#') {
        let end = code.indexOf('\n', pos);
        end = end === -1 ? len : end;
        tokens.push({ type: 'comment', value: code.slice(pos, end) });
        pos = end;
        continue;
      }
      // Newlines
      if (code[pos] === '\n') {
        tokens.push({ type: 'plain', value: '\n' });
        pos++;
        continue;
      }
      // Key: value pattern at start of logical position
      const lineMatch = code.slice(pos).match(/^(\s*)([\w.-]+)(\s*:\s*)/);
      if (lineMatch) {
        tokens.push({ type: 'plain', value: lineMatch[1] });
        tokens.push({ type: 'keyword', value: lineMatch[2] });
        tokens.push({ type: 'plain', value: lineMatch[3] });
        pos += lineMatch[0].length;
        // Now scan the rest of the line
        let end = code.indexOf('\n', pos);
        end = end === -1 ? len : end;
        const val = code.slice(pos, end);
        if (/^\s*\d+\.?\d*\s*$/.test(val)) {
          tokens.push({ type: 'number', value: val });
        } else if (/^\s*(true|false|yes|no|on|off|null|~)\s*$/i.test(val)) {
          tokens.push({ type: 'keyword', value: val });
        } else if (val.trim()) {
          tokens.push({ type: 'string', value: val });
        } else {
          tokens.push({ type: 'plain', value: val });
        }
        pos = end;
        continue;
      }
      tokens.push({ type: 'plain', value: code[pos] });
      pos++;
    }

    const classMap = { comment: 'hl-comment', string: 'hl-string', keyword: 'hl-keyword', number: 'hl-number', plain: null };
    let out = '';
    for (const t of tokens) {
      const cls = classMap[t.type];
      const escaped = escapeHtml(t.value);
      if (cls) out += '<span class="' + cls + '">' + escaped + '</span>';
      else out += escaped;
    }
    return out;
  }

  // Apply highlighting — use textContent to get raw decoded text
  // Only highlight <pre><code> blocks, not inline <code> elements
  function highlightBlock(el, fn) {
    // Skip if already highlighted
    if (el.dataset.highlighted) return;
    el.dataset.highlighted = 'true';
    // Only process if parent is <pre> (block code, not inline)
    if (el.parentElement && el.parentElement.tagName === 'PRE') {
      const code = el.textContent;
      el.innerHTML = fn(code);
    }
  }

  document.querySelectorAll('.language-dart').forEach(el => highlightBlock(el, highlightDart));
  document.querySelectorAll('.language-bash').forEach(el => highlightBlock(el, highlightBash));
  document.querySelectorAll('.language-yaml').forEach(el => highlightBlock(el, highlightYaml));

})();
