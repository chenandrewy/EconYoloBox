// Run: loaded by media/index.html; test with `node --test test/*.test.js`.
// Input: ordered transcript spans shaped as {t:'text',s} or {t:'math',m,s}.
// Output: a small Markdown block model; raw HTML is never interpreted.
(function (root, factory) {
  'use strict';
  var api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.MathPanelMarkdown = api;
})(typeof globalThis === 'object' ? globalThis : this, function () {
  'use strict';

  function pushText(tokens, text) {
    if (!text) return;
    var last = tokens[tokens.length - 1];
    if (last && last.t === 'text') last.s += text;
    else tokens.push({ t: 'text', s: text });
  }

  function spansToLines(spans) {
    var lines = [[]];
    for (var i = 0; i < spans.length; i++) {
      var span = spans[i];
      if (span.t === 'math') {
        lines[lines.length - 1].push({ t: 'math', m: span.m, s: span.s });
        continue;
      }
      var parts = span.s.split('\n');
      for (var j = 0; j < parts.length; j++) {
        pushText(lines[lines.length - 1], parts[j]);
        if (j < parts.length - 1) lines.push([]);
      }
    }
    return lines;
  }

  function lineText(line) {
    var out = '';
    for (var i = 0; i < line.length; i++) {
      out += line[i].t === 'text' ? line[i].s : '\ufffc';
    }
    return out;
  }

  function stripPrefix(line, count) {
    var out = [];
    for (var i = 0; i < line.length; i++) {
      var token = line[i];
      if (token.t === 'text' && count > 0) {
        if (token.s.length <= count) {
          count -= token.s.length;
          continue;
        }
        pushText(out, token.s.slice(count));
        count = 0;
      } else if (token.t === 'text') {
        pushText(out, token.s);
      } else {
        out.push({ t: 'math', m: token.m, s: token.s });
      }
    }
    return out;
  }

  function marker(line) {
    var text = lineText(line);
    var match = text.match(/^ {0,3}(#{1,6})[ \t]+/);
    if (match && text.slice(match[0].length).trim()) {
      return { type: 'heading', level: match[1].length, prefix: match[0].length };
    }
    if (/^ {0,3}((\*[ \t]*){3,}|(-[ \t]*){3,}|(_[ \t]*){3,})$/.test(text)) {
      return { type: 'rule' };
    }
    match = text.match(/^ {0,3}([-+*])[ \t]+/);
    if (match) return { type: 'list', ordered: false, prefix: match[0].length };
    match = text.match(/^ {0,3}\d+[.)][ \t]+/);
    if (match) return { type: 'list', ordered: true, prefix: match[0].length };
    match = text.match(/^ {0,3}>[ \t]?/);
    if (match) return { type: 'blockquote', prefix: match[0].length };
    match = text.match(/^ {0,3}```[ \t]*([A-Za-z0-9_-]+)?[ \t]*$/);
    if (match) return { type: 'fence', language: match[1] || '' };
    return { type: 'paragraph' };
  }

  function isBlank(line) {
    return lineText(line).trim() === '';
  }

  function literalLine(line) {
    var out = '';
    for (var i = 0; i < line.length; i++) out += line[i].s;
    return out;
  }

  function parse(spans) {
    var lines = spansToLines(spans);
    var blocks = [];
    var i = 0;
    while (i < lines.length) {
      if (isBlank(lines[i])) {
        i++;
        continue;
      }

      var kind = marker(lines[i]);
      if (kind.type === 'fence') {
        var code = [];
        i++;
        while (i < lines.length && marker(lines[i]).type !== 'fence') {
          code.push(literalLine(lines[i]));
          i++;
        }
        if (i < lines.length) i++;
        blocks.push({ type: 'code', language: kind.language, text: code.join('\n') });
        continue;
      }
      if (kind.type === 'heading') {
        blocks.push({
          type: 'heading',
          level: kind.level,
          content: stripPrefix(lines[i], kind.prefix),
        });
        i++;
        continue;
      }
      if (kind.type === 'rule') {
        blocks.push({ type: 'rule' });
        i++;
        continue;
      }
      if (kind.type === 'list') {
        var list = { type: 'list', ordered: kind.ordered, items: [] };
        while (i < lines.length) {
          var itemKind = marker(lines[i]);
          if (itemKind.type !== 'list' || itemKind.ordered !== kind.ordered) break;
          list.items.push(stripPrefix(lines[i], itemKind.prefix));
          i++;
        }
        blocks.push(list);
        continue;
      }
      if (kind.type === 'blockquote') {
        var quote = { type: 'blockquote', lines: [] };
        while (i < lines.length) {
          var quoteKind = marker(lines[i]);
          if (quoteKind.type !== 'blockquote') break;
          quote.lines.push(stripPrefix(lines[i], quoteKind.prefix));
          i++;
        }
        blocks.push(quote);
        continue;
      }

      var paragraph = { type: 'paragraph', lines: [] };
      while (i < lines.length && !isBlank(lines[i]) && marker(lines[i]).type === 'paragraph') {
        paragraph.lines.push(lines[i]);
        i++;
      }
      blocks.push(paragraph);
    }
    return blocks;
  }

  return { parse: parse };
});
