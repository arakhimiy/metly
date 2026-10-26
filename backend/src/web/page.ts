import type { CardDesign } from '../records/wire';
import { type ContactAction, contactAction } from './contact-links';
import { html, type SafeHtml, safeHttpUrl, trusted } from './html';
import { type PageColors, pageColors } from './palette';
import type { PublicView } from './public-card.service';
import type { WebPlatform } from './visitor';

// Server-rendered tanishly.app pages (SPEC WEB_CARD / WEB_SHAREBACK_SHEET / WEB_CONFIRMATION /
// WEB_UNAVAILABLE). No framework: one HTML document, one nonce'd <style>, one nonce'd <script>.
// Every user value goes through `html` (escape-by-default); URLs through `safeUrl`.

export interface CardPageOptions {
  view: PublicView;
  nonce: string;
  platform: WebPlatform;
  /** App Store id: Smart App Banner + "Get the app" (both hidden without it). */
  appStoreId?: string;
}

const ICONS: Record<string, SafeHtml> = {
  phone: trusted(
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6.6 10.8a15.1 15.1 0 0 0 6.6 6.6l2.2-2.2a1 1 0 0 1 1-.25 11.4 11.4 0 0 0 3.6.57 1 1 0 0 1 1 1V20a1 1 0 0 1-1 1A17 17 0 0 1 3 4a1 1 0 0 1 1-1h3.5a1 1 0 0 1 1 1c0 1.25.2 2.45.57 3.57a1 1 0 0 1-.25 1L6.6 10.8z"/></svg>',
  ),
  email: trusted(
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2zm0 2v.4l8 5.1 8-5.1V7H4zm16 2.8-7.46 4.75a1 1 0 0 1-1.08 0L4 9.8V17h16V9.8z"/></svg>',
  ),
  telegram: trusted(
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21.9 4.3 18.7 19.4c-.24 1.06-.87 1.32-1.76.82l-4.86-3.58-2.34 2.26c-.26.26-.48.48-.98.48l.35-4.94 9-8.13c.39-.35-.09-.54-.6-.2L6.4 13.1 1.6 11.6c-1.04-.33-1.06-1.04.22-1.54L20.5 2.9c.87-.32 1.63.2 1.4 1.4z"/></svg>',
  ),
  website: trusted(
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.9 6h-2.95a15.7 15.7 0 0 0-1.38-3.56A8.03 8.03 0 0 1 18.9 8zM12 4.04c.83 1.2 1.48 2.53 1.91 3.96h-3.82A13.6 13.6 0 0 1 12 4.04zM4.26 14a8.2 8.2 0 0 1 0-4h3.38a16.5 16.5 0 0 0 0 4H4.26zm.82 2h2.95c.32 1.25.78 2.45 1.38 3.56A7.99 7.99 0 0 1 5.08 16zM8.03 8H5.08a7.99 7.99 0 0 1 4.33-3.56A15.7 15.7 0 0 0 8.03 8zM12 19.96A14.1 14.1 0 0 1 10.09 16h3.82A14.1 14.1 0 0 1 12 19.96zM14.34 14H9.66a14.7 14.7 0 0 1 0-4h4.68a14.7 14.7 0 0 1 0 4zm.25 5.56c.6-1.11 1.06-2.31 1.38-3.56h2.95a8.03 8.03 0 0 1-4.33 3.56zM16.36 14a16.5 16.5 0 0 0 0-4h3.38a8.2 8.2 0 0 1 0 4h-3.38z"/></svg>',
  ),
  linkedin: trusted(
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M19 3a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h14zM8.34 10H5.67v8.33h2.67V10zM7 5.67a1.55 1.55 0 1 0 0 3.1 1.55 1.55 0 0 0 0-3.1zM18.33 13.2c0-2.5-1.33-3.4-3.08-3.4-1.4 0-2.14.77-2.48 1.32V10h-2.6v8.33h2.67v-4.4c0-1.16.22-2.28 1.66-2.28 1.42 0 1.44 1.33 1.44 2.35v4.33h2.67l-.28-5.13z"/></svg>',
  ),
  lock: trusted(
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a5 5 0 0 1 5 5v3h1a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2h1V7a5 5 0 0 1 5-5zm0 2a3 3 0 0 0-3 3v3h6V7a3 3 0 0 0-3-3z"/></svg>',
  ),
  check: trusted('<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9.5 16.2 5.3 12l-1.4 1.4 5.6 5.6 11-11-1.4-1.4z"/></svg>'),
  linkBreak: trusted(
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M17 7h-3v2h3a3 3 0 0 1 .9 5.86l1.47 1.47A5 5 0 0 0 17 7zm-1 4h-2.2l2 2H16v-2zM2 4.27l3.1 3.1A5 5 0 0 0 7 17h3v-2H7a3 3 0 0 1-1.06-5.8l2.07 2.07L8 11v2h1.73L12 15.27V17h1.73l4 4L19 19.73 3.27 4 2 4.27z"/></svg>',
  ),
  copy: trusted(
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16 1H6a2 2 0 0 0-2 2v12h2V3h10V1zm3 4H10a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h9a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2zm0 16H10V7h9v14z"/></svg>',
  ),
};

function cssVariables(colors: PageColors): string {
  return [
    `--bg:${colors.background}`,
    `--fg:${colors.foreground}`,
    `--accent:${colors.accent}`,
    `--muted:${colors.muted}`,
    `--panel:${colors.panelTint}`,
    `--grad-end:${colors.gradientEnd}`,
    `--fg-rgb:${colors.foregroundRgb}`,
    `--on-accent:${colors.onAccent}`,
    `color-scheme:${colors.dark ? 'dark' : 'light'}`,
  ].join(';');
}

const BASE_CSS = String.raw`
*,*::before,*::after{box-sizing:border-box}
html{-webkit-text-size-adjust:100%;text-size-adjust:100%}
body{margin:0;min-height:100vh;min-height:100dvh;color:var(--fg);background:var(--bg);background-image:linear-gradient(rgba(var(--fg-rgb),.035),rgba(var(--fg-rgb),.035));font:16px/1.4 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;-webkit-font-smoothing:antialiased;-webkit-tap-highlight-color:transparent}
a{color:inherit}
button{font:inherit;color:inherit}
svg{width:20px;height:20px;fill:currentColor;flex:none}
[hidden]{display:none!important}
.wrap{max-width:460px;margin:0 auto;padding:calc(16px + env(safe-area-inset-top)) 16px calc(28px + env(safe-area-inset-bottom))}
.btn{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;min-height:50px;padding:12px 18px;border:0;border-radius:14px;background:rgba(var(--fg-rgb),.08);color:var(--fg);font-weight:600;font-size:17px;text-decoration:none;cursor:pointer;transition:transform .12s ease,opacity .12s ease}
.btn:active{transform:scale(.98)}
.btn:focus-visible,.copy:focus-visible,.field-link:focus-visible,.link:focus-visible,input:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
.btn.primary{background:var(--accent);color:var(--on-accent)}
.btn.plain{background:transparent;color:var(--muted);min-height:44px}
.btn[disabled]{opacity:.45;cursor:default;transform:none}
.link{border:0;background:none;padding:0;color:var(--accent);font-weight:600;cursor:pointer;text-decoration:underline;text-underline-offset:2px}
.foot{margin:28px 0 0;text-align:center;font-size:13px;color:var(--muted)}
.toast{position:fixed;left:50%;bottom:calc(24px + env(safe-area-inset-bottom));transform:translate(-50%,20px);opacity:0;pointer-events:none;background:var(--fg);color:var(--bg);padding:10px 16px;border-radius:999px;font-size:15px;font-weight:600;transition:opacity .2s ease,transform .2s ease;z-index:10;max-width:calc(100% - 32px);text-align:center}
.toast.show{opacity:1;transform:translate(-50%,0)}
.offscreen,.hp{position:absolute!important;left:-10000px!important;top:auto;width:1px;height:1px;overflow:hidden}
@media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
`;

const CARD_CSS = String.raw`
.face{position:relative;display:flex;flex-direction:column;justify-content:space-between;gap:14px;aspect-ratio:1.586/1;width:100%;padding:22px 22px 20px;border-radius:20px;overflow:hidden;background:var(--bg);color:var(--fg);border:1px solid rgba(var(--fg-rgb),.10);box-shadow:0 1px 2px rgba(0,0,0,.06),0 16px 40px -12px rgba(0,0,0,.28)}
.face.fill-gradient{background:linear-gradient(140deg,var(--bg) 22%,var(--grad-end))}
.face-top{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;min-height:8px}
.face-text{min-width:0}
.name{margin:0;font-size:clamp(22px,6.6vw,30px);line-height:1.12;font-weight:700;letter-spacing:-.01em;overflow-wrap:anywhere}
.role{margin:6px 0 0;color:var(--muted);font-size:15px;line-height:1.3;overflow-wrap:anywhere}
.card-name{font-size:12px;font-weight:600;letter-spacing:.06em;text-transform:uppercase;color:var(--muted)}
.avatar{width:56px;height:56px;border-radius:50%;object-fit:cover;background:var(--panel);display:flex;align-items:center;justify-content:center;font-weight:700;font-size:20px;color:var(--fg);flex:none}
.logo{max-height:32px;max-width:96px;object-fit:contain}
.font-rounded .face-text,.font-rounded.face{font-family:ui-rounded,"SF Pro Rounded","Nunito",-apple-system,sans-serif}
.font-serif .face-text,.font-serif.face{font-family:ui-serif,"New York",Georgia,"Times New Roman",serif}
.font-mono .face-text,.font-mono.face{font-family:ui-monospace,"SF Mono",Menlo,Consolas,monospace}
.align-center .face-text{text-align:center}
.align-center .face-top{justify-content:center}
.tpl-professional .face-text{border-left:3px solid var(--accent);padding-left:12px}
.tpl-professional .role{text-transform:uppercase;letter-spacing:.06em;font-size:12px;font-weight:600}
.tpl-bold .name{font-size:clamp(28px,8.6vw,38px);font-weight:800;letter-spacing:-.025em}
.tpl-bold .face-top::before{content:"";display:block;width:36px;height:6px;border-radius:3px;background:var(--accent)}
.tpl-bold.align-center .face-top::before{margin:0 auto}
.tpl-modern .face-top,.tpl-stack .face-top{justify-content:flex-start}
.tpl-stack .avatar{width:64px;height:64px}
.tpl-split{display:grid;grid-template-columns:38% 1fr;padding:0;gap:0}
.tpl-split .face-top{background:var(--panel);align-items:center;justify-content:center;height:100%}
.tpl-split .face-text{align-self:end;padding:20px}
.tpl-split .avatar{width:72px;height:72px;background:var(--bg)}
.tpl-terminal .prompt{margin:0 0 6px;color:var(--accent);font-size:13px}
.tpl-terminal .name{font-size:clamp(20px,6vw,26px)}
.tpl-editorial .name{font-weight:500;letter-spacing:0}
.tpl-editorial .role{font-style:italic;border-top:1px solid rgba(var(--fg-rgb),.24);padding-top:8px;margin-top:10px}
.notice{display:flex;gap:10px;align-items:center;margin:16px 0 0;padding:12px 14px;border-radius:14px;background:rgba(var(--fg-rgb),.07);font-size:14px}
.notice span{flex:1}
.notice .btn{width:auto;min-height:36px;padding:6px 12px;font-size:14px;white-space:nowrap}
.p-inapp .notice.inapp{display:flex}
.notice.inapp{display:none}
.fields{list-style:none;margin:20px 0 0;padding:0;border-radius:16px;background:rgba(var(--fg-rgb),.06);overflow:hidden}
.field{display:flex;align-items:center;min-height:58px}
.field+.field{border-top:1px solid rgba(var(--fg-rgb),.08)}
.field-link{display:flex;align-items:center;gap:14px;flex:1;min-width:0;padding:10px 14px;text-decoration:none}
.field-link .icon{color:var(--accent);display:flex}
.field-text{display:flex;flex-direction:column;min-width:0}
.label{font-size:12px;color:var(--muted)}
.value{font-size:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.copy{display:flex;align-items:center;gap:6px;margin-right:10px;padding:8px 10px;border:0;border-radius:10px;background:transparent;color:var(--accent);font-size:14px;font-weight:600;cursor:pointer}
.copy svg{width:16px;height:16px}
.actions{display:grid;gap:10px;margin-top:20px}
.shared{display:flex;align-items:center;justify-content:center;gap:8px;flex-wrap:wrap;min-height:44px;font-size:15px;color:var(--muted)}
.shared svg{color:#16a34a}
.cta{display:flex;align-items:center;gap:14px;margin-top:20px;padding:14px 16px;border-radius:16px;border:1px solid rgba(var(--fg-rgb),.12)}
.cta div{flex:1;display:flex;flex-direction:column}
.cta strong{font-size:15px}
.cta span{font-size:13px;color:var(--muted)}
.cta .btn{width:auto;min-height:40px;font-size:15px}
dialog{width:100%;max-width:460px;max-height:calc(100dvh - 24px);margin:auto auto 0;padding:10px 20px calc(20px + env(safe-area-inset-bottom));border:0;border-radius:22px 22px 0 0;background:var(--bg);color:var(--fg);overflow:auto;box-shadow:0 -8px 40px rgba(0,0,0,.25)}
dialog::backdrop{background:rgba(0,0,0,.45)}
dialog:not([open]){display:none}
@media (min-width:600px){dialog{margin:auto;border-radius:22px;padding-bottom:22px}}
.grabber{width:36px;height:5px;border-radius:3px;background:rgba(var(--fg-rgb),.2);margin:0 auto 14px}
dialog h2{margin:0;font-size:22px;line-height:1.2}
.sub{margin:6px 0 16px;color:var(--muted);font-size:15px}
.input{display:block;margin-top:10px}
.input span{display:block;font-size:13px;color:var(--muted);margin:0 0 4px 2px}
input{width:100%;min-height:48px;padding:12px 14px;border-radius:12px;border:1px solid rgba(var(--fg-rgb),.16);background:rgba(var(--fg-rgb),.04);color:var(--fg);font:inherit;font-size:17px}
input::placeholder{color:var(--muted);opacity:.8}
.help{margin:6px 2px 0;font-size:13px;color:var(--muted)}
.hint{min-height:20px;margin:14px 2px 0;font-size:14px;color:var(--accent)}
.private{display:flex;align-items:center;gap:6px;margin:6px 2px 14px;font-size:14px;color:var(--muted)}
.private svg{width:15px;height:15px}
#sb-form .btn+.btn{margin-top:8px}
.done{text-align:center}
.done .btn{margin-top:10px}
.check{width:56px;height:56px;margin:8px auto 14px;border-radius:50%;background:#16a34a;color:#fff;display:flex;align-items:center;justify-content:center}
.check svg{width:30px;height:30px}
.saved-row{display:flex;align-items:center;justify-content:center;gap:6px;margin:14px 0 0;color:var(--muted)}
.mind{margin:18px 0 0;font-size:14px;color:var(--muted)}
@media (min-width:768px){.wrap{padding-top:56px}}
`;

const UNAVAILABLE_CSS = String.raw`
.empty{display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;min-height:calc(100dvh - 120px);gap:6px}
.empty .mark{width:64px;height:64px;border-radius:50%;background:rgba(var(--fg-rgb),.07);display:flex;align-items:center;justify-content:center;color:var(--muted);margin-bottom:10px}
.empty .mark svg{width:30px;height:30px}
.empty h1{margin:0;font-size:22px;line-height:1.25}
.empty p{margin:0;color:var(--muted);max-width:320px}
`;

/** Page script: analytics beacon, copy buttons, share-back sheet, removal, "Get the app". */
const CARD_JS = String.raw`(function () {
  'use strict';
  var d = document, b = d.body;
  var slug = b.getAttribute('data-slug');
  var api = '/api/public/cards/' + encodeURIComponent(slug);
  var KEY = 'metly:shareback:' + slug, SAVED = 'metly:saved:' + slug, SKIP = 'metly:skip:' + slug;
  function $(id) { return d.getElementById(id); }
  function on(id, type, fn) { var el = $(id); if (el) el.addEventListener(type, fn); }
  function get(store, k) { try { var v = window[store].getItem(k); return v ? JSON.parse(v) : null; } catch (e) { return null; } }
  function put(store, k, v) { try { if (v === null) window[store].removeItem(k); else window[store].setItem(k, JSON.stringify(v)); } catch (e) {} }
  function detect() {
    var ua = navigator.userAgent || '';
    if (/FBAN|FBAV|FB_IAB|Instagram|Line\/|MicroMessenger|Telegram|Twitter|LinkedInApp|Snapchat|TikTok|GSA\/|; wv\)/i.test(ua)) return 'inapp';
    if (/iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return 'ios';
    if (/Android/i.test(ua)) return 'android';
    return 'desktop';
  }
  var platform = b.getAttribute('data-platform') === 'inapp' ? 'inapp' : detect();
  b.className = b.className.replace(/\bp-[a-z]+\b/g, '') + ' p-' + platform;
  var source = /(?:^|[?&])src=qr(?:&|$)/.test(location.search) ? 'qr' : 'link';
  function referrer() { try { return d.referrer ? new URL(d.referrer).origin : null; } catch (e) { return null; } }
  function track(type) {
    try {
      fetch(api + '/events', {
        method: 'POST', credentials: 'omit', keepalive: true,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: type, platform: platform, source: source, referrer: referrer() })
      })['catch'](function () {});
    } catch (e) {}
  }
  var toastTimer;
  function toast(text) {
    var t = $('toast'); t.textContent = text; t.classList.add('show');
    clearTimeout(toastTimer); toastTimer = setTimeout(function () { t.classList.remove('show'); }, 2200);
  }
  function copy(text, done) {
    function fallback() {
      var ta = d.createElement('textarea'); ta.value = text; ta.setAttribute('readonly', ''); ta.className = 'offscreen';
      d.body.appendChild(ta); ta.select();
      try { if (d.execCommand('copy')) done(); } catch (e) {}
      d.body.removeChild(ta);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, fallback); else fallback();
  }
  function each(sel, fn) { Array.prototype.forEach.call(d.querySelectorAll(sel), fn); }

  track('view');

  each('[data-copy]', function (el) {
    el.addEventListener('click', function () {
      copy(el.getAttribute('data-copy'), function () { toast(el.getAttribute('data-copied')); });
      var kind = el.getAttribute('data-kind');
      if (kind === 'phone' || kind === 'email') track('copy_' + kind);
    });
  });
  each('[data-track]', function (el) {
    el.addEventListener('click', function () { track(el.getAttribute('data-track')); });
  });
  on('copy-link', 'click', function () { copy(location.href.split('#')[0], function () { toast('Link Copied'); }); });

  function refresh() {
    var shared = !!get('localStorage', KEY), saved = !!get('localStorage', SAVED);
    if ($('exchange')) $('exchange').hidden = shared;
    if ($('shared')) $('shared').hidden = !shared;
    if ($('done-save')) $('done-save').hidden = saved;
    if ($('done-saved')) $('done-saved').hidden = !saved;
  }
  function markSaved() { put('localStorage', SAVED, { at: Date.now() }); setTimeout(refresh, 500); }
  function onSave(e) {
    if (platform === 'inapp') { e.preventDefault(); toast('Open in browser to save'); return; }
    markSaved();
  }
  on('save', 'click', onSave);
  on('done-save', 'click', onSave);

  each('[data-get-app]', function (a) {
    a.addEventListener('click', function () {
      try {
        var u = new URL(a.getAttribute('href'), location.href);
        var tz = (window.Intl && Intl.DateTimeFormat().resolvedOptions().timeZone) || '';
        if (tz) u.searchParams.set('tz', tz);
        if (navigator.language) u.searchParams.set('lang', navigator.language);
        a.setAttribute('href', u.pathname + u.search);
      } catch (e) {}
    });
  });

  var sheet = $('sheet'), form = $('sb-form');
  if (!sheet || !form) { refresh(); return; }
  var done = $('sb-done'), send = $('sb-send'), hint = $('sb-hint');
  function field(n) { return form.querySelector('[name="' + n + '"]'); }
  function openSheet(showDone) {
    form.hidden = !!showDone; done.hidden = !showDone;
    if (typeof sheet.showModal === 'function') { if (!sheet.open) sheet.showModal(); } else sheet.setAttribute('open', '');
  }
  function closeSheet() { if (typeof sheet.close === 'function') sheet.close(); else sheet.removeAttribute('open'); }
  function values() {
    return {
      name: field('name').value.trim(), phone: field('phone').value.trim(), telegram: field('telegram').value.trim(),
      metAt: field('metAt').value.trim(), website: field('website').value
    };
  }
  function validate() {
    var v = values();
    var msg = !v.name ? 'Add your name to send.' : (!v.phone && !v.telegram ? 'Add a phone or Telegram to send.' : '');
    hint.textContent = msg; send.disabled = !!msg; return !msg;
  }
  form.addEventListener('input', validate);
  on('exchange', 'click', function () { openSheet(false); validate(); });
  on('sb-skip', 'click', function () { put('sessionStorage', SKIP, true); closeSheet(); });
  on('done-back', 'click', closeSheet);
  sheet.addEventListener('click', function (e) { if (e.target === sheet) closeSheet(); });

  var sending = false;
  form.addEventListener('submit', function (e) {
    e.preventDefault();
    if (sending || !validate()) return;
    var v = values();
    sending = true; send.disabled = true; hint.textContent = 'Sending…';
    var key = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2);
    fetch(api + '/shareback', {
      method: 'POST', credentials: 'omit',
      headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key },
      body: JSON.stringify({ name: v.name, phone: v.phone || null, telegram: v.telegram || null, metAt: v.metAt || null, platform: platform, website: v.website || null })
    }).then(function (r) {
      return r.json()['catch'](function () { return {}; }).then(function (j) { return { status: r.status, body: j }; });
    }).then(function (res) {
      sending = false;
      if (res.status === 201) {
        put('localStorage', KEY, { id: res.body.shareBackId, token: res.body.removalToken, at: Date.now() });
        form.reset(); hint.textContent = ''; refresh(); openSheet(true);
        if (!get('localStorage', SAVED) && (platform === 'ios' || platform === 'android')) {
          markSaved(); location.href = $('save').getAttribute('href');
        }
        return;
      }
      var details = (res.body && res.body.details) || {};
      hint.textContent = res.status === 429 ? 'Too many tries. Please try again later.'
        : (details.name || details.phone || details.telegram || details.metAt || 'Something went wrong. Please try again.');
      send.disabled = false;
    }, function () { sending = false; send.disabled = false; hint.textContent = 'You seem to be offline. Try again.'; });
  });

  function removeContact() {
    var sb = get('localStorage', KEY);
    if (!sb) return;
    fetch('/api/public/sharebacks/' + encodeURIComponent(sb.id), {
      method: 'DELETE', credentials: 'omit', headers: { 'X-Removal-Token': sb.token }
    }).then(function (r) {
      if (r.status === 204 || r.status === 403) {
        put('localStorage', KEY, null); refresh(); closeSheet();
        toast(r.status === 204 ? 'Your contact was removed' : 'This contact can no longer be removed here');
      } else toast('Could not remove your contact. Try again.');
    }, function () { toast('You seem to be offline. Try again.'); });
  }
  on('done-remove', 'click', removeContact);
  on('remove-inline', 'click', removeContact);

  refresh();
  if (!get('localStorage', KEY) && !get('sessionStorage', SKIP)) {
    setTimeout(function () { openSheet(false); validate(); }, 500);
  }
})();`;

function head(opts: {
  nonce: string;
  title: string;
  description: string;
  colors: PageColors;
  extraCss: string;
  ogUrl?: string;
  ogImage?: string | null;
  appBanner?: SafeHtml;
}): SafeHtml {
  return html`<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<meta name="referrer" content="strict-origin-when-cross-origin">
<meta name="format-detection" content="telephone=no">
<meta name="theme-color" content="${opts.colors.background}">
<title>${opts.title}</title>
<meta name="description" content="${opts.description}">
<meta property="og:type" content="profile">
<meta property="og:site_name" content="Tanishly">
<meta property="og:title" content="${opts.title}">
<meta property="og:description" content="${opts.description}">
${opts.ogUrl ? html`<meta property="og:url" content="${opts.ogUrl}">` : ''}
${opts.ogImage ? html`<meta property="og:image" content="${opts.ogImage}">` : ''}
<meta name="twitter:card" content="summary">
${opts.appBanner ?? ''}
<style nonce="${opts.nonce}">:root{${trusted(cssVariables(opts.colors))}}${trusted(BASE_CSS)}${trusted(opts.extraCss)}</style>
</head>`;
}

function initials(fullName: string): string {
  const words = fullName.trim().split(/\s+/).filter(Boolean);
  const letters = [words[0], words.length > 1 ? words[words.length - 1] : undefined]
    .map((w) => (w ? [...w][0]?.toUpperCase() : ''))
    .join('');
  return letters || '?';
}

function effectiveAlignment(design: CardDesign): 'leading' | 'center' {
  return ['minimal', 'bold', 'gradient'].includes(design.template) ? design.alignment : 'leading';
}

function effectiveFont(design: CardDesign): string {
  if (design.template === 'terminal') return 'mono';
  if (design.template === 'editorial') return 'serif';
  return design.font;
}

function face(view: PublicView): SafeHtml {
  const { design, profile } = view;
  const gradient = design.template === 'gradient' || design.background === 'gradient';
  const classes = [
    'face',
    `tpl-${design.template}`,
    `font-${effectiveFont(design)}`,
    `align-${effectiveAlignment(design)}`,
    gradient ? 'fill-gradient' : 'fill-solid',
  ].join(' ');
  const showsAvatar = ['modern', 'split', 'stack'].includes(design.template);
  const avatar = showsAvatar
    ? view.photoUrl
      ? html`<img class="avatar" src="${view.photoUrl}" alt="" width="56" height="56" referrerpolicy="no-referrer">`
      : html`<span class="avatar" aria-hidden="true">${initials(view.fullName)}</span>`
    : '';
  const logo =
    design.template === 'professional' && view.logoUrl
      ? html`<img class="logo" src="${view.logoUrl}" alt="" referrerpolicy="no-referrer">`
      : '';
  const role = [profile.jobTitle.trim(), profile.company.trim()].filter(Boolean).join(' · ');
  return html`<section class="${classes}" aria-label="${view.fullName}">
<div class="face-top">${avatar}${logo}</div>
<div class="face-text">
${design.template === 'terminal' ? html`<p class="prompt">$ whoami</p>` : ''}
<h1 class="name">${view.fullName}</h1>
${role ? html`<p class="role">${role}</p>` : ''}
</div>
</section>`;
}

function fieldRow(action: ContactAction, terminal: boolean): SafeHtml {
  const label = terminal ? action.key : action.label;
  const body = html`<span class="icon">${ICONS[action.kind] ?? ''}</span><span class="field-text"><span class="label">${label}</span><span class="value">${action.display}</span></span>`;
  const external = action.kind === 'website' || action.kind === 'linkedin' || action.kind === 'telegram';
  const track = action.kind === 'telegram' ? 'telegram_open' : null;
  const link = action.href
    ? html`<a class="field-link" href="${action.href}"${external ? trusted(' target="_blank" rel="noopener noreferrer"') : ''}${track ? html` data-track="${track}"` : ''}>${body}</a>`
    : html`<div class="field-link">${body}</div>`;
  const copyable = action.kind === 'phone' || action.kind === 'email';
  const copied = action.kind === 'phone' ? 'Phone Copied' : 'Email Copied';
  const copy = copyable
    ? html`<button class="copy" type="button" data-copy="${action.display}" data-kind="${action.kind}" data-copied="${copied}" aria-label="Copy ${action.label}">${ICONS.copy}<span>Copy</span></button>`
    : '';
  return html`<li class="field">${link}${copy}</li>`;
}

export function renderCardPage(opts: CardPageOptions): string {
  const { view, nonce, platform, appStoreId } = opts;
  const colors = pageColors(view.design);
  const first = view.firstName;
  const role = [view.profile.jobTitle.trim(), view.profile.company.trim()].filter(Boolean).join(' · ');
  const actions = view.fields.map(contactAction).filter((a): a is ContactAction => a !== null);
  const telegram = actions.find((a) => a.kind === 'telegram' && a.href);
  const vcfHref = `/c/${view.slug}.vcf`;
  const getAppHref = `/c/${view.slug}/get-app`;
  const banner = appStoreId
    ? html`<meta name="apple-itunes-app" content="app-id=${appStoreId}, app-argument=${view.url}">`
    : undefined;
  const cta = appStoreId
    ? html`<section class="cta"><div><strong>Want a card like this?</strong><span>Free, 30 seconds.</span></div><a class="btn primary" href="${getAppHref}" data-get-app>Get Tanishly</a></section>`
    : '';

  const doc = html`<!doctype html>
<html lang="en">
${head({
  nonce,
  title: `${view.fullName} · Tanishly`,
  description: role || 'Digital business card on Tanishly',
  colors,
  extraCss: CARD_CSS,
  ogUrl: view.url,
  ogImage: view.photoUrl ? safeHttpUrl(view.photoUrl) : null,
  appBanner: banner,
})}
<body class="p-${platform}" data-slug="${view.slug}" data-platform="${platform}">
<main class="wrap">
${face(view)}
<div class="notice inapp" role="note"><span>Open this page in your browser to save the contact.</span><button class="btn" type="button" id="copy-link">Copy link</button></div>
${actions.length > 0 ? html`<ul class="fields" aria-label="Contact details">${actions.map((a) => fieldRow(a, view.design.template === 'terminal'))}</ul>` : ''}
<div class="actions">
<a class="btn primary" id="save" href="${vcfHref}">Save to Contacts</a>
${telegram ? html`<a class="btn" href="${telegram.href}" target="_blank" rel="noopener noreferrer" data-track="telegram_open">${ICONS.telegram}Message on Telegram</a>` : ''}
<button class="btn" type="button" id="exchange">Exchange Contacts with ${first}</button>
<p class="shared" id="shared" hidden>${ICONS.check}<span>Your contact was sent to ${first}.</span><button class="link" type="button" id="remove-inline">Remove my contact</button></p>
</div>
${cta}
<p class="foot">Made with Tanishly · Only public details are shown</p>
</main>
<dialog id="sheet" aria-labelledby="sheet-title">
<form id="sb-form" novalidate autocomplete="on">
<div class="grabber" aria-hidden="true"></div>
<h2 id="sheet-title">Exchange contacts with ${first}</h2>
<p class="sub">Send yours and save ${first}’s in one step.</p>
<label class="input"><span>Name</span><input name="name" autocomplete="name" maxlength="80" placeholder="Your name" required></label>
<label class="input"><span>Phone</span><input name="phone" type="tel" inputmode="tel" autocomplete="tel" maxlength="40" placeholder="+998"></label>
<label class="input"><span>Telegram</span><input name="telegram" autocomplete="off" autocapitalize="none" autocorrect="off" spellcheck="false" maxlength="64" placeholder="@username"></label>
<p class="help">Add a phone or Telegram — at least one.</p>
<label class="input"><span>Met at</span><input name="metAt" maxlength="120" placeholder="Where did we meet? Optional"></label>
<div class="hp" aria-hidden="true"><label>Website <input name="website" tabindex="-1" autocomplete="off"></label></div>
<p class="hint" id="sb-hint" role="status" aria-live="polite"></p>
<p class="private">${ICONS.lock}<span>Only ${first} will see this.</span></p>
<button class="btn primary" id="sb-send" type="submit" disabled>Send &amp; Save ${first}’s Contact</button>
<button class="btn plain" id="sb-skip" type="button">Skip</button>
</form>
<div class="done" id="sb-done" hidden>
<div class="check">${ICONS.check}</div>
<h2>Done! ${first} got your contact.</h2>
<p class="sub">It arrives with where you met, so a follow-up is easy.</p>
<a class="btn primary" id="done-save" href="${vcfHref}">Save ${first}’s Contact</a>
<p class="saved-row" id="done-saved" hidden>${ICONS.check}<span>${first}’s contact is saved</span></p>
${cta}
<button class="btn" type="button" id="done-back">Back to ${first}’s Card</button>
<p class="mind">Changed your mind? <button class="link" type="button" id="done-remove">Remove my contact</button></p>
</div>
</dialog>
<div class="toast" id="toast" role="status" aria-live="polite"></div>
<script nonce="${nonce}">${trusted(CARD_JS)}</script>
</body>
</html>`;
  return doc.value;
}

export type UnavailableKind = 'unavailable' | 'notFound';

/** WEB_UNAVAILABLE (paused or deleted) and unknown links — never any personal data. */
export function renderUnavailablePage(opts: { nonce: string; kind: UnavailableKind }): string {
  const colors = pageColors(null);
  const copy =
    opts.kind === 'unavailable'
      ? { title: 'This card isn’t available right now.', body: 'The link may be paused or removed. Ask the person for a new one.' }
      : { title: 'We couldn’t find this card.', body: 'Check the link, or ask the person to share their card again.' };
  return html`<!doctype html>
<html lang="en">
${head({ nonce: opts.nonce, title: 'Tanishly', description: copy.title, colors, extraCss: UNAVAILABLE_CSS })}
<body>
<main class="wrap">
<div class="empty">
<div class="mark">${ICONS.linkBreak}</div>
<h1>${copy.title}</h1>
<p>${copy.body}</p>
</div>
<p class="foot">Made with Tanishly</p>
</main>
</body>
</html>`.value;
}

/** Content-Security-Policy for a page whose only script and style carry `nonce`. */
export function pageCsp(nonce: string): string {
  return [
    "default-src 'none'",
    `script-src 'nonce-${nonce}'`,
    `style-src 'nonce-${nonce}'`,
    'img-src https: data:',
    "connect-src 'self'",
    "form-action 'self'",
    "base-uri 'none'",
    "frame-ancestors 'none'",
    "manifest-src 'self'",
  ].join('; ');
}
