/// docs_to_html.dart
/// Converts Markdown docs from docs/ into a single-page HTML documentation site.
///
/// Usage:
///   dart run tool/docs_to_html.dart --docs docs --output html_doc/index.html --template html_doc/_template.html
library;

import 'dart:io';
import 'package:args/args.dart';

// ============================================================
// Page configuration: maps doc files to page IDs, titles, nav sections
// ============================================================

final List<NavSection> navSections = [
  NavSection('Getting Started', [
    PageRef('home', 'Overview', null),
    PageRef('getting-started', 'Getting Started', 'getting-started.md'),
    PageRef('tutorial', 'Tutorial', 'tutorial.md'),
    PageRef('architecture', 'Architecture', 'architecture.md'),
  ]),
  NavSection('Guides', [
    PageRef('di', 'Dependency Injection', 'guides/dependency-injection.md'),
    PageRef('controllers', 'Controllers & Routing', 'guides/controllers.md'),
    PageRef('middleware', 'Middleware', 'guides/middleware.md'),
    PageRef('configuration', 'Configuration', 'guides/configuration.md'),
    PageRef('validation', 'Validation', 'guides/validation.md'),
    PageRef('error-handling', 'Error Handling', 'guides/error-handling.md'),
    PageRef('websockets', 'WebSockets', 'guides/websockets.md'),
    PageRef('lifecycle', 'Application Lifecycle', 'guides/lifecycle.md'),
    PageRef('events', 'Application Events', 'guides/events.md'),
    PageRef('cors-static', 'CORS & Static Files', 'guides/cors-and-static.md'),
    PageRef('content-negotiation', 'Content Negotiation',
        'guides/content-negotiation.md'),
    PageRef('sse', 'Server-Sent Events', 'guides/server-sent-events.md'),
    PageRef('grpc', 'gRPC', 'guides/grpc.md'),
    PageRef('auth', 'Authentication', 'guides/auth.md'),
    PageRef('persistence', 'Persistence', 'guides/persistence.md'),
    PageRef('openapi', 'OpenAPI', 'guides/openapi.md'),
    PageRef('observability', 'Observability', 'guides/observability.md'),
    PageRef('operations', 'Operations', 'guides/operations.md'),
    PageRef('json', 'JSON Serialization', 'guides/json.md'),
    PageRef('testing', 'Testing', 'guides/testing.md'),
  ]),
  NavSection('Reference', [
    PageRef('annotations', 'Annotations', 'reference/annotations.md'),
    PageRef('runtime-api', 'Runtime API', 'reference/runtime.md'),
    PageRef('generated-code', 'Generated Code', 'reference/generated-code.md'),
    PageRef('build-diagnostics', 'Build Diagnostics',
        'reference/build-diagnostics.md'),
    PageRef('config-keys', 'Configuration Keys', 'reference/config-keys.md'),
  ]),
  NavSection('', [
    PageRef('troubleshooting', 'Troubleshooting & FAQ', 'troubleshooting.md'),
  ]),
];

// ============================================================
// Data classes
// ============================================================

class NavSection {
  final String title;
  final List<PageRef> pages;
  const NavSection(this.title, this.pages);
}

class PageRef {
  final String id;
  final String title;
  final String? docFile; // null for home page (custom content)
  const PageRef(this.id, this.title, this.docFile);
}

// ============================================================
// Markdown -> HTML converter
// ============================================================

class MdToHtml {
  /// Convert markdown text to HTML body content (no `<html>` wrapper).
  String convert(String md) {
    final lines = md.replaceAll('\r\n', '\n').split('\n');
    final buffer = StringBuffer();
    var i = 0;

    // Strip leading frontmatter (--- ... ---)
    if (lines.isNotEmpty && lines[0].trim() == '---') {
      i = 1;
      while (i < lines.length && lines[i].trim() != '---') {
        i++;
      }
      if (i < lines.length) i++; // skip closing ---
    }

    while (i < lines.length) {
      final line = lines[i];

      // Fenced code block
      if (line.startsWith('```')) {
        final lang = line.substring(3).trim();
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        i++; // skip closing ```
        final langClass = lang.isNotEmpty ? ' class="language-$lang"' : '';
        buffer.writeln(
            '<pre><code$langClass>${escapeHtml(codeLines.join('\n'))}</code></pre>');
        continue;
      }

      // Headings
      final headingMatch = RegExp(r'^(#{1,6})\s+(.*)').firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        final text = headingMatch.group(2)!;
        buffer.writeln('<h$level>${inlineMarkdown(text)}</h$level>');
        i++;
        continue;
      }

      // Horizontal rule
      if (RegExp(r'^-{3,}$').hasMatch(line.trim())) {
        buffer.writeln('<hr>');
        i++;
        continue;
      }

      // Blockquote
      if (line.startsWith('> ')) {
        final quoteLines = <String>[];
        while (i < lines.length && lines[i].startsWith('> ')) {
          quoteLines.add(lines[i].substring(2));
          i++;
        }
        buffer.writeln(
            '<blockquote>${inlineMarkdown(quoteLines.join('\n'))}</blockquote>');
        continue;
      }

      // Tables
      if (line.contains('|') &&
          i + 1 < lines.length &&
          lines[i + 1].contains('|---')) {
        final headerLine = line;
        i++; // skip separator line
        i++; // skip the |---|---| line
        final headers = parseTableRow(headerLine);
        buffer.writeln('<table><thead><tr>');
        for (final h in headers) {
          buffer.writeln('<th>${inlineMarkdown(h)}</th>');
        }
        buffer.writeln('</tr></thead><tbody>');
        while (i < lines.length && lines[i].contains('|')) {
          final cells = parseTableRow(lines[i]);
          buffer.writeln('<tr>');
          for (final c in cells) {
            buffer.writeln('<td>${inlineMarkdown(c)}</td>');
          }
          buffer.writeln('</tr>');
          i++;
        }
        buffer.writeln('</tbody></table>');
        continue;
      }

      // Unordered list
      if (RegExp(r'^\s*[-*]\s+').hasMatch(line)) {
        buffer.writeln('<ul>');
        while (i < lines.length && RegExp(r'^\s*[-*]\s+').hasMatch(lines[i])) {
          final content = lines[i].replaceFirst(RegExp(r'^\s*[-*]\s+'), '');
          buffer.writeln('<li>${inlineMarkdown(content)}</li>');
          i++;
        }
        buffer.writeln('</ul>');
        continue;
      }

      // Ordered list
      if (RegExp(r'^\s*\d+\.\s+').hasMatch(line)) {
        buffer.writeln('<ol>');
        while (i < lines.length && RegExp(r'^\s*\d+\.\s+').hasMatch(lines[i])) {
          final content = lines[i].replaceFirst(RegExp(r'^\s*\d+\.\s+'), '');
          buffer.writeln('<li>${inlineMarkdown(content)}</li>');
          i++;
        }
        buffer.writeln('</ol>');
        continue;
      }

      // Empty line
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // Paragraph
      final paraLines = <String>[];
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !lines[i].startsWith('#') &&
          !lines[i].startsWith('```') &&
          !lines[i].startsWith('> ') &&
          !lines[i].startsWith('|') &&
          !RegExp(r'^\s*[-*]\s+').hasMatch(lines[i]) &&
          !RegExp(r'^\s*\d+\.\s+').hasMatch(lines[i]) &&
          !RegExp(r'^-{3,}$').hasMatch(lines[i].trim())) {
        paraLines.add(lines[i]);
        i++;
      }
      if (paraLines.isNotEmpty) {
        buffer.writeln('<p>${inlineMarkdown(paraLines.join('\n'))}</p>');
      }
    }

    return buffer.toString();
  }

  List<String> parseTableRow(String line) {
    // Remove leading/trailing |, then split by |
    var s = line.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|')) s = s.substring(0, s.length - 1);
    return s.split('|').map((c) => c.trim()).toList();
  }

  String inlineMarkdown(String text) {
    // Process inline code first (protect from other transformations)
    final codeSpans = <String>[];
    text = text.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) {
      codeSpans.add(m.group(1)!);
      return '\x00CODE${codeSpans.length - 1}\x00';
    });

    // Bold
    text = text.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'),
        (m) => '<strong>${_inline(m.group(1)!)}</strong>');
    text = text.replaceAllMapped(RegExp(r'__(.+?)__'),
        (m) => '<strong>${_inline(m.group(1)!)}</strong>');

    // Italic
    text = text.replaceAllMapped(
        RegExp(r'\*(.+?)\*'), (m) => '<em>${_inline(m.group(1)!)}</em>');
    text = text.replaceAllMapped(
        RegExp(r'_(.+?)_'), (m) => '<em>${_inline(m.group(1)!)}</em>');

    // Links: [text](url)
    text = text.replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), (m) {
      final href = m.group(2)!;
      // Convert relative markdown links to hash links
      if (href.endsWith('.md')) {
        final base = href.split('/').last.replaceAll('.md', '');
        final pageId = _filePathToPageId(base);
        return '<a href="#$pageId">${m.group(1)!}</a>';
      }
      if (href.startsWith('#')) {
        return '<a href="${m.group(1)}">${m.group(1)}</a>';
      }
      return '<a href="$href" target="_blank" rel="noopener">${m.group(1)!}</a>';
    });

    // Inline code restoration
    for (var j = 0; j < codeSpans.length; j++) {
      text = text.replaceFirst(
          '\x00CODE$j\x00', '<code>${escapeHtml(codeSpans[j])}</code>');
    }

    // Line breaks within paragraphs: convert \n to <br> for multi-line plain text
    // (but not inside HTML tags we just generated)
    // Skip this for now; paragraphs should be single logical blocks.

    return text;
  }

  String _inline(String text) {
    // Handle inline code within bold/italic
    text = text.replaceAllMapped(
        RegExp(r'`([^`]+)`'), (m) => '<code>${escapeHtml(m.group(1)!)}</code>');
    return text;
  }

  String _filePathToPageId(String path) {
    // Map file paths/basenames to page IDs
    final map = {
      'getting-started': 'getting-started',
      'tutorial': 'tutorial',
      'architecture': 'architecture',
      'troubleshooting': 'troubleshooting',
      'dependency-injection': 'di',
      'controllers': 'controllers',
      'middleware': 'middleware',
      'configuration': 'configuration',
      'validation': 'validation',
      'error-handling': 'error-handling',
      'websockets': 'websockets',
      'lifecycle': 'lifecycle',
      'events': 'events',
      'cors-and-static': 'cors-static',
      'content-negotiation': 'content-negotiation',
      'server-sent-events': 'sse',
      'grpc': 'grpc',
      'auth': 'auth',
      'persistence': 'persistence',
      'openapi': 'openapi',
      'observability': 'observability',
      'operations': 'operations',
      'json': 'json',
      'testing': 'testing',
      'annotations': 'annotations',
      'runtime': 'runtime-api',
      'generated-code': 'generated-code',
      'build-diagnostics': 'build-diagnostics',
      'config-keys': 'config-keys',
    };
    final key = path.replaceAll('.md', '');
    return map[key] ?? key;
  }
}

String escapeHtml(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

// ============================================================
// HTML template builder
// ============================================================

String buildHtml({
  required String navHtml,
  required String homeContent,
  required Map<String, String> pageContents,
}) {
  final pages = <String>[];

  // Home page
  pages.add('<div class="page active" id="page-home">$homeContent</div>');

  // Other pages
  for (final entry in pageContents.entries) {
    pages.add('<div class="page" id="page-${entry.key}">${entry.value}</div>');
  }

  final pagesHtml = pages.join('\n\n          ');

  return '''<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Diana — Spring-inspired Dart Backend Framework</title>
  <link rel="stylesheet" href="styles.css">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
</head>
<body>
  <div class="app">
    <!-- Sidebar -->
    <aside class="sidebar" id="sidebar">
      <div class="sidebar-header">
        <a href="#home" class="logo">
          <span class="logo-icon">◆</span>
          <span class="logo-text">Diana</span>
          <span class="logo-version">v0.6.0</span>
        </a>
      </div>
      <div class="sidebar-search">
        <input type="text" id="search" placeholder="Search docs…" autocomplete="off">
        <div class="search-results" id="searchResults"></div>
      </div>
      <nav class="sidebar-nav" id="sidebarNav">
        $navHtml
      </nav>
    </aside>

    <!-- Main content -->
    <main class="main">
      <header class="topbar">
        <button class="menu-toggle" id="menuToggle" aria-label="Toggle menu">
          <span></span><span></span><span></span>
        </button>
        <div class="topbar-breadcrumb" id="breadcrumb">Overview</div>
        <div class="topbar-actions">
          <button class="theme-toggle" id="themeToggle" aria-label="Toggle theme">
            <svg class="icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/>
            </svg>
            <svg class="icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>
            </svg>
          </button>
          <a href="https://github.com" class="topbar-link" target="_blank" rel="noopener">
            <svg viewBox="0 0 24 24" fill="currentColor" width="20" height="20">
              <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0 0 24 12c0-6.63-5.37-12-12-12z"/>
            </svg>
          </a>
        </div>
      </header>

      <div class="content-wrapper">
        <div class="content" id="content">
          $pagesHtml
        </div>
      </div>
    </main>
  </div>

  <script src="app.js"></script>
</body>
</html>''';
}

String buildNavHtml() {
  final buffer = StringBuffer();
  for (final section in navSections) {
    if (section.title.isNotEmpty) {
      buffer.writeln('        <div class="nav-section">');
      buffer.writeln(
          '          <div class="nav-section-title">${section.title}</div>');
    } else {
      buffer.writeln('        <div class="nav-section">');
    }
    for (final page in section.pages) {
      final active = page.id == 'home' ? ' active' : '';
      buffer.writeln(
          '          <a href="#${page.id}" class="nav-link$active" data-page="${page.id}">${page.title}</a>');
    }
    buffer.writeln('        </div>');
  }
  return buffer.toString();
}

// ============================================================
// Home page content (custom, not from markdown)
// ============================================================

const String homeContent = '''<section class="hero">
              <div class="hero-badge">Spring-inspired · Compile-time DI · Zero reflection</div>
              <h1>Build Dart backends the <span class="gradient-text">right way</span></h1>
              <p class="hero-subtitle">Diana is a Spring-inspired, annotation-driven backend framework for Dart. Everything — dependency injection, routing, middleware wiring, validation — is resolved <strong>at compile time</strong>. No reflection, no runtime container. Configuration mistakes are build errors, and startup is instant.</p>
              <div class="hero-actions">
                <a href="#getting-started" class="btn btn-primary">Get Started</a>
                <a href="#tutorial" class="btn btn-secondary">Follow the Tutorial</a>
              </div>
            </section>

            <section class="features">
              <div class="feature-card">
                <div class="feature-icon">⚡</div>
                <h3>Compile-Time DI</h3>
                <p>Dependency resolution, routing, and validation checked at build time. The runtime contains no reflection, no type maps, no resolution logic.</p>
              </div>
              <div class="feature-card">
                <div class="feature-icon">🔒</div>
                <h3>Type-Safe by Design</h3>
                <p>Generated code is plain typed Dart. The DI container is a class with typed fields in dependency order — debuggable with any IDE.</p>
              </div>
              <div class="feature-card">
                <div class="feature-icon">🚀</div>
                <h3>Instant Startup</h3>
                <p>No container bootstrap, no runtime scanning, no reflection warm-up. The generated composition root wires everything before your first line runs.</p>
              </div>
              <div class="feature-card">
                <div class="feature-icon">🧩</div>
                <h3>Feature-Rich</h3>
                <p>Controllers, middleware, validation, WebSockets, SSE, gRPC, authentication, persistence, OpenAPI, CORS — all with the same annotation-driven model.</p>
              </div>
              <div class="feature-card">
                <div class="feature-icon">📦</div>
                <h3>Modular Packages</h3>
                <p>Core runtime, generator, gRPC, auth, and persistence live in separate packages. You depend only on what you use.</p>
              </div>
              <div class="feature-card">
                <div class="feature-icon">🔧</div>
                <h3>Hot Reload</h3>
                <p>Watch mode regenerates on save. Handler bodies hot-reload with the VM service. DI-graph changes need a restart — clearly documented.</p>
              </div>
            </section>

            <section class="code-preview">
              <h2>See it in action</h2>
              <div class="tabs">
                <button class="tab active" data-tab="controller">Controller</button>
                <button class="tab" data-tab="di">Dependency Injection</button>
                <button class="tab" data-tab="config">Configuration</button>
              </div>
              <div class="tab-content active" id="tab-controller">
<pre><code class="language-dart">import 'package:diana/diana.dart';

part 'hello_controller.diana.dart';

@RestController('/hello')
class HelloController {
  @Get()
  Map&lt;String, dynamic&gt; hello() =&gt;
      {'message': 'Hello from Diana!'};

  @Get('/:name')
  String greet(@PathParam() String name) =&gt;
      'Hello, \$name!';
}</code></pre>
              </div>
              <div class="tab-content" id="tab-di">
<pre><code class="language-dart">import 'package:diana/diana.dart';

@Service()
class BookService {
  final BookRepository repo;
  BookService(this.repo);

  List&lt;BookDto&gt; list(int limit) =&gt;
      repo.findAll(limit: limit);
}

@Repository()
class InMemoryBookRepository
    implements BookRepository {
  // ... implementation
}</code></pre>
              </div>
              <div class="tab-content" id="tab-config">
<pre><code class="language-dart">import 'package:diana/diana.dart';

part 'app_info.diana.dart';

@ConfigurationProperties('app.info')
class AppInfo {
  final String name;
  final String version;

  const AppInfo({
    required this.name,
    required this.version,
  });
}</code></pre>
              </div>
            </section>

            <section class="quick-start">
              <h2>Quick start</h2>
              <div class="steps">
                <div class="step">
                  <div class="step-number">1</div>
                  <div class="step-content">
                    <h4>Create a project</h4>
<pre><code class="language-bash">dart create -t console my_api
cd my_api</code></pre>
                  </div>
                </div>
                <div class="step">
                  <div class="step-number">2</div>
                  <div class="step-content">
                    <h4>Add dependencies</h4>
<pre><code class="language-yaml">dependencies:
  diana: ^0.6.0
dev_dependencies:
  build_runner: ^2.12.0
  diana_generator: ^0.6.0</code></pre>
                  </div>
                </div>
                <div class="step">
                  <div class="step-number">3</div>
                  <div class="step-content">
                    <h4>Generate &amp; run</h4>
<pre><code class="language-bash">dart run build_runner build
dart run bin/server.dart
# [diana] Listening on http://0.0.0.0:8080</code></pre>
                  </div>
                </div>
              </div>
            </section>

            <section class="requirements">
              <h2>Requirements</h2>
              <ul>
                <li>Dart SDK <strong>3.6 or later</strong></li>
                <li><code>build_runner</code> for code generation</li>
              </ul>
              <p class="muted">Currently at version 0.6.0 — APIs may change before 1.0.0.</p>
            </section>''';

// ============================================================
// Main
// ============================================================

void main(List<String> args) {
  final parser = ArgParser()
    ..addOption('docs', defaultsTo: 'docs', help: 'Path to docs directory')
    ..addOption('output',
        defaultsTo: 'html_doc/index.html', help: 'Output HTML file')
    ..addOption('template',
        defaultsTo: '', help: 'Path to HTML template (optional)');

  final result = parser.parse(args);
  final docsDir = result['docs'] as String;
  final outputPath = result['output'] as String;
  // template is optional; we build the full HTML ourselves

  // Read all doc files
  final converter = MdToHtml();
  final pageContents = <String, String>{};

  for (final section in navSections) {
    for (final page in section.pages) {
      if (page.docFile == null) continue; // home page is custom
      final filePath = '$docsDir/${page.docFile}';
      final file = File(filePath);
      if (!file.existsSync()) {
        stderr.writeln(
            'Warning: ${page.docFile} not found, skipping page "${page.title}"');
        continue;
      }
      final md = file.readAsStringSync();
      pageContents[page.id] = converter.convert(md);
    }
  }

  // Build navigation
  final navHtml = buildNavHtml();

  // Build full HTML
  final html = buildHtml(
    navHtml: navHtml,
    homeContent: homeContent,
    pageContents: pageContents,
  );

  // Write output
  final outputFile = File(outputPath);
  outputFile.createSync(recursive: true);
  outputFile.writeAsStringSync(html);

  stdout.writeln('Generated ${pageContents.length} pages + home → $outputPath');
}
