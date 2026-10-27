import { html, type SafeHtml } from '../html';
import { LEGAL, LEGAL_UPDATED, type LegalDocKind, type LegalLang, SUPPORT_EMAIL, UI } from './legal-content';

const LANGS: LegalLang[] = ['uz', 'ru', 'en'];
const LANG_LABEL: Record<LegalLang, string> = { uz: 'O‘zbekcha', ru: 'Русский', en: 'English' };

/** `?lang=` wins, then the browser's Accept-Language, then Uzbek (the launch market). */
export function pickLang(query: unknown, acceptLanguage: string | undefined): LegalLang {
  if (typeof query === 'string' && (LANGS as string[]).includes(query)) return query as LegalLang;
  const tags = (acceptLanguage ?? '')
    .split(',')
    .map((part) => part.split(';')[0]?.trim().toLowerCase().slice(0, 2))
    .filter(Boolean);
  for (const tag of tags) if ((LANGS as string[]).includes(tag!)) return tag as LegalLang;
  return 'uz';
}

/** Static pages carry no script: no nonce needed, nothing loads from elsewhere. */
export const STATIC_PAGE_CSP =
  "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

const STYLE = `
:root{color-scheme:light dark;--bg:#fff;--fg:#111114;--muted:#5f6368;--line:#e6e6ea;--accent:#0d9488}
@media (prefers-color-scheme:dark){:root{--bg:#0b0b0c;--fg:#f5f5f7;--muted:#a1a1aa;--line:#26262b;--accent:#2dd4bf}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.6 system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
main{max-width:720px;margin:0 auto;padding:32px 20px 64px}
header{display:flex;flex-wrap:wrap;gap:12px;align-items:center;justify-content:space-between;margin-bottom:28px}
.brand{font-weight:700;font-size:20px;color:var(--fg);text-decoration:none}.brand span{color:var(--accent)}
nav a,.langs a{color:var(--muted);text-decoration:none;margin-right:14px;font-size:15px}nav a[aria-current],.langs a[aria-current]{color:var(--accent);font-weight:600}
h1{font-size:32px;line-height:1.2;margin:8px 0 4px}h2{font-size:20px;margin:32px 0 8px}
.updated{color:var(--muted);font-size:14px;margin:0 0 20px}.intro{font-size:18px}
ul{padding-left:22px}li{margin:6px 0}a{color:var(--accent)}
footer{border-top:1px solid var(--line);margin-top:48px;padding-top:20px;color:var(--muted);font-size:14px}
.hero{padding:40px 0 8px}.hero p{font-size:20px;color:var(--muted)}.cta{display:inline-block;margin-top:16px;padding:12px 20px;border-radius:999px;background:var(--accent);color:#fff;text-decoration:none;font-weight:600}
.soon{display:inline-block;margin-top:16px;color:var(--muted)}`;

function shell(lang: LegalLang, title: string, current: LegalDocKind | 'home', path: string, content: SafeHtml): string {
  const ui = UI[lang];
  const nav: [LegalDocKind, string][] = [
    ['help', ui.help],
    ['privacy', ui.privacy],
    ['terms', ui.terms],
  ];
  return html`<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>${STYLE}</style>
</head>
<body>
<main>
<header>
  <a class="brand" href="/?lang=${lang}">Tanish<span>ly</span></a>
  <nav>${nav.map(([kind, label]) => html`<a href="/${kind}?lang=${lang}"${current === kind ? html` aria-current="page"` : ''}>${label}</a>`)}</nav>
</header>
${content}
<footer>
  <div class="langs">${LANGS.map((l) => html`<a href="${path}?lang=${l}"${l === lang ? html` aria-current="true"` : ''}>${LANG_LABEL[l]}</a>`)}</div>
  <p>${ui.contact}: <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a></p>
</footer>
</main>
</body>
</html>`.toString();
}

export function renderLegalPage(kind: LegalDocKind, lang: LegalLang): string {
  const doc = LEGAL[kind][lang];
  const body = html`
<h1>${doc.title}</h1>
${kind === 'help' ? '' : html`<p class="updated">${UI[lang].updated}: ${LEGAL_UPDATED}</p>`}
<p class="intro">${doc.intro}</p>
${doc.sections.map(
  (section) => html`<h2>${section.heading}</h2>
${section.body.map((part) => (Array.isArray(part) ? html`<ul>${part.map((item) => html`<li>${item}</li>`)}</ul>` : html`<p>${part}</p>`))}`,
)}`;
  return shell(lang, `${doc.title} · Tanishly`, kind, `/${kind}`, body);
}

/** `download`: the App Store listing, or before it exists the beta (TestFlight) link. */
export function renderHomePage(lang: LegalLang, download?: { url: string; beta: boolean }): string {
  const ui = UI[lang];
  const body = html`
<section class="hero">
  <h1>Tanishly</h1>
  <p>${ui.tagline}</p>
  ${download
    ? html`<a class="cta" href="${download.url}">${download.beta ? ui.tryBeta : ui.getApp}</a>`
    : html`<span class="soon">${ui.soon}</span>`}
</section>`;
  return shell(lang, `Tanishly — ${ui.tagline}`, 'home', '/', body);
}
