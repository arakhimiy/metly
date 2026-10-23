import { describe, expect, it } from 'vitest';
import { escapeHtml, html, safeHttpUrl, safeUrl, trusted } from './html';

describe('escapeHtml', () => {
  it('escapes every markup-significant character', () => {
    expect(escapeHtml(`<script>alert("x")</script>`)).toBe('&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;');
    expect(escapeHtml(`a & b ' \``)).toBe('a &amp; b &#39; &#96;');
  });

  it('does not double-escape-proof entities — it escapes them again', () => {
    expect(escapeHtml('&amp;')).toBe('&amp;amp;');
  });

  it('renders null/undefined as empty and drops control characters', () => {
    expect(escapeHtml(null)).toBe('');
    expect(escapeHtml(undefined)).toBe('');
    expect(escapeHtml('a\u0000b\u0007c\n')).toBe('abc\n');
  });

  it('keeps non-ASCII text', () => {
    expect(escapeHtml('Камола Юсупова — 日本')).toBe('Камола Юсупова — 日本');
  });
});

describe('html template', () => {
  it('escapes interpolations by default', () => {
    const name = '"><img src=x onerror=alert(1)>';
    expect(html`<p title="${name}">${name}</p>`.value).toBe(
      '<p title="&quot;&gt;&lt;img src=x onerror=alert(1)&gt;">&quot;&gt;&lt;img src=x onerror=alert(1)&gt;</p>',
    );
  });

  it('nests safe fragments and arrays without re-escaping', () => {
    const items = ['<a>', '<b>'].map((x) => html`<li>${x}</li>`);
    expect(html`<ul>${items}</ul>`.value).toBe('<ul><li>&lt;a&gt;</li><li>&lt;b&gt;</li></ul>');
    expect(html`${trusted('<br>')}`.value).toBe('<br>');
  });

  it('skips null, undefined and booleans', () => {
    expect(html`a${null}b${undefined}c${false}d${true}`.value).toBe('abcd');
  });
});

describe('safeUrl', () => {
  it('allows http(s), tel and mailto', () => {
    expect(safeUrl('https://metly.link/c/a')).toBe('https://metly.link/c/a');
    expect(safeUrl('tel:+998901234567')).toBe('tel:+998901234567');
    expect(safeUrl('mailto:a@b.uz')).toBe('mailto:a@b.uz');
  });

  it('rejects script-capable and malformed URLs', () => {
    expect(safeUrl('javascript:alert(1)')).toBeNull();
    expect(safeUrl('JaVaScRiPt:alert(1)')).toBeNull();
    expect(safeUrl('data:text/html,<script>')).toBeNull();
    expect(safeUrl('vbscript:x')).toBeNull();
    expect(safeUrl('java\nscript:alert(1)')).toBeNull();
    expect(safeUrl('/relative')).toBeNull();
    expect(safeUrl('')).toBeNull();
    expect(safeUrl(null)).toBeNull();
  });

  it('safeHttpUrl only allows http(s)', () => {
    expect(safeHttpUrl('tel:123')).toBeNull();
    expect(safeHttpUrl('https://cdn.metly.link/p.jpg')).toBe('https://cdn.metly.link/p.jpg');
  });
});
