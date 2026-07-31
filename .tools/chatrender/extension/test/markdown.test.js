// Run: `node --test .tools/chatrender/extension/test/markdown.test.js`.
// Input: synthetic text/math spans.
// Output: assertions for ChatRender's safe Markdown block model.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { parse } = require('../media/markdown');

test('markdown: headings retain inline math', () => {
  assert.deepEqual(
    parse([
      { t: 'text', s: '## Result for ' },
      { t: 'math', m: 'inline', s: 'x' },
    ]),
    [
      {
        type: 'heading',
        level: 2,
        content: [
          { t: 'text', s: 'Result for ' },
          { t: 'math', m: 'inline', s: 'x' },
        ],
      },
    ],
  );
});

test('markdown: unordered and ordered outlines form separate lists', () => {
  assert.deepEqual(
    parse([{ t: 'text', s: '- first\n- second\n\n1. one\n2. two' }]),
    [
      {
        type: 'list',
        ordered: false,
        items: [[{ t: 'text', s: 'first' }], [{ t: 'text', s: 'second' }]],
      },
      {
        type: 'list',
        ordered: true,
        items: [[{ t: 'text', s: 'one' }], [{ t: 'text', s: 'two' }]],
      },
    ],
  );
});

test('markdown: quotes, rules, paragraphs, and fenced code', () => {
  assert.deepEqual(
    parse([
      {
        t: 'text',
        s: '> quoted\n> again\n\n---\n\nplain\nline\n\n```js\n<b>inert</b>\n```',
      },
    ]),
    [
      {
        type: 'blockquote',
        lines: [[{ t: 'text', s: 'quoted' }], [{ t: 'text', s: 'again' }]],
      },
      { type: 'rule' },
      {
        type: 'paragraph',
        lines: [[{ t: 'text', s: 'plain' }], [{ t: 'text', s: 'line' }]],
      },
      { type: 'code', language: 'js', text: '<b>inert</b>' },
    ],
  );
});

test('markdown: raw HTML remains ordinary paragraph text', () => {
  assert.deepEqual(parse([{ t: 'text', s: '<img src=x onerror=alert(1)>' }]), [
    {
      type: 'paragraph',
      lines: [[{ t: 'text', s: '<img src=x onerror=alert(1)>' }]],
    },
  ]);
});
