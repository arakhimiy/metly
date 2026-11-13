import type { Lang } from '../i18n/lang';
import { CARD_PAGE_TEXT, type CardPageText, UNAVAILABLE_PAGE_TEXT } from '../i18n/web-page';
import type { CardDesign } from '../records/wire';
import { type ContactAction, contactAction, PHONE_KEYS } from './contact-links';
import { html, type SafeHtml, safeHttpUrl, trusted } from './html';
import { auroraColors, holographicFoil, metalFoil, type PageColors, pageColors } from './palette';
import type { PublicView } from './public-card.service';
import type { WebPlatform } from './visitor';

// Server-rendered tanishly.app pages (SPEC WEB_CARD / WEB_SHAREBACK_SHEET / WEB_CONFIRMATION /
// WEB_UNAVAILABLE). No framework: one HTML document, one nonce'd <style>, one nonce'd <script>.
// Every user value goes through `html` (escape-by-default); URLs through `safeUrl`.
// Texts come from src/i18n/web-page.ts in the page's language; the script's texts travel as JSON in
// the body's `data-t` attribute (escaped like any attribute), so the script itself stays constant.

export interface CardPageOptions {
  view: PublicView;
  nonce: string;
  platform: WebPlatform;
  lang: Lang;
  /** Smart App Banner; only once the App Store listing exists. */
  appStoreId?: string;
  /** Show "Get the app" (App Store or the pre-release TestFlight link). */
  appAvailable?: boolean;
  /** The visitor's device runs Android (in-app browsers included): the "Get the app" block's variant. */
  android?: boolean;
  /** Android visitors get "Notify me" (the Telegram bot's waitlist) instead of the App Store button. */
  androidWaitlistUrl?: string;
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
  whatsapp: trusted(
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill-rule="evenodd" d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2zm0 2a8 8 0 1 1-4.1 14.9l-.3-.2-2.9.8.8-2.8-.2-.3A8 8 0 0 1 12 4z"/><path d="M9.2 7.5c-.2-.5-.4-.5-.6-.5h-.5a1 1 0 0 0-.7.3 3 3 0 0 0-.9 2.2c0 1.3.9 2.5 1 2.7.1.2 1.8 2.9 4.5 3.9 2.2.9 2.7.7 3.2.7.5-.1 1.6-.7 1.8-1.3.2-.6.2-1.2.2-1.3-.1-.1-.3-.2-.6-.4l-1.8-.9c-.3-.1-.4-.1-.6.1l-.8 1c-.1.2-.3.2-.6.1a6.6 6.6 0 0 1-3.3-2.9c-.2-.4.2-.4.7-1.3.1-.2 0-.3 0-.4l-.9-2z"/></svg>',
  ),
  instagram: trusted(
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill-rule="evenodd" d="M7 2h10a5 5 0 0 1 5 5v10a5 5 0 0 1-5 5H7a5 5 0 0 1-5-5V7a5 5 0 0 1 5-5zm0 2a3 3 0 0 0-3 3v10a3 3 0 0 0 3 3h10a3 3 0 0 0 3-3V7a3 3 0 0 0-3-3H7zm5 3.5a4.5 4.5 0 1 1 0 9 4.5 4.5 0 0 1 0-9zm0 2a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5zM17.25 5.5a1.25 1.25 0 1 1 0 2.5 1.25 1.25 0 0 1 0-2.5z"/></svg>',
  ),
  linkedin: trusted(
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M19 3a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h14zM8.34 10H5.67v8.33h2.67V10zM7 5.67a1.55 1.55 0 1 0 0 3.1 1.55 1.55 0 0 0 0-3.1zM18.33 13.2c0-2.5-1.33-3.4-3.08-3.4-1.4 0-2.14.77-2.48 1.32V10h-2.6v8.33h2.67v-4.4c0-1.16.22-2.28 1.66-2.28 1.42 0 1.44 1.33 1.44 2.35v4.33h2.67l-.28-5.13z"/></svg>',
  ),
  address: trusted(
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2a7 7 0 0 1 7 7c0 5.25-7 13-7 13S5 14.25 5 9a7 7 0 0 1 7-7zm0 4.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5z"/></svg>',
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

/** The card owner's palette, for the card face only (`--c-*`). The page around it is Nameshake's (BRAND_CSS). */
function cssVariables(colors: PageColors): string {
  return [
    `--c-bg:${colors.background}`,
    `--c-fg:${colors.foreground}`,
    `--c-accent:${colors.accent}`,
    `--c-muted:${colors.muted}`,
    `--c-panel:${colors.panelTint}`,
    `--c-grad-end:${colors.gradientEnd}`,
    `--c-fg-rgb:${colors.foregroundRgb}`,
  ].join(';');
}

/**
 * Nameshake's colors: HIG system Blue (#007AFF light / #0A84FF dark, #0040DD / #409CFF with Increase
 * Contrast) on iOS grouped-background greys, following the visitor's light/dark setting.
 */
const BRAND_CSS = String.raw`
:root{color-scheme:light dark;--bg:#f2f2f7;--surface:#ffffff;--fg:#000000;--muted:#6c6c70;--line:rgba(60,60,67,.12);--fill:rgba(118,118,128,.12);--accent:#007aff;--accent-text:#007aff;--accent-soft:rgba(0,122,255,.12);--on-accent:#ffffff;--warn:#b42318;--shadow:rgba(0,0,0,.16)}
@media (prefers-color-scheme:dark){:root{--bg:#000000;--surface:#1c1c1e;--fg:#ffffff;--muted:#98989f;--line:rgba(235,235,245,.12);--fill:rgba(118,118,128,.24);--accent:#0a84ff;--accent-text:#0a84ff;--accent-soft:rgba(10,132,255,.18);--warn:#ff8a7a;--shadow:rgba(0,0,0,.6)}}
@media (prefers-contrast:more){:root{--accent:#0040dd;--accent-text:#0040dd}}
@media (prefers-contrast:more) and (prefers-color-scheme:dark){:root{--accent:#409cff;--accent-text:#409cff;--on-accent:#000000}}
`;

const BASE_CSS = String.raw`
*,*::before,*::after{box-sizing:border-box}
html{-webkit-text-size-adjust:100%;text-size-adjust:100%}
body{margin:0;min-height:100vh;min-height:100dvh;color:var(--fg);background:var(--bg);font:16px/1.4 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;-webkit-font-smoothing:antialiased;-webkit-tap-highlight-color:transparent}
a{color:inherit}
button{font:inherit;color:inherit}
svg{width:20px;height:20px;fill:currentColor;flex:none}
[hidden]{display:none!important}
.wrap{max-width:460px;margin:0 auto;padding:calc(16px + env(safe-area-inset-top)) 16px calc(28px + env(safe-area-inset-bottom))}
.btn{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;min-height:50px;padding:12px 18px;border:0;border-radius:14px;background:var(--fill);color:var(--fg);font-weight:600;font-size:17px;text-decoration:none;cursor:pointer;transition:transform .12s ease,opacity .12s ease}
.btn:active{transform:scale(.98)}
.btn:focus-visible,.copy:focus-visible,.field-link:focus-visible,.link:focus-visible,input:focus-visible{outline:2px solid var(--accent-text);outline-offset:2px}
.btn.primary{background:var(--accent);color:var(--on-accent)}
.btn.tinted{background:var(--accent-soft);color:var(--accent-text)}
.btn.plain{background:transparent;color:var(--muted);min-height:44px}
.btn[disabled]{opacity:.45;cursor:default;transform:none}
.link{border:0;background:none;padding:0;color:var(--accent-text);font-weight:600;cursor:pointer;text-decoration:underline;text-underline-offset:2px}
.foot{margin:28px 0 0;text-align:center;font-size:13px;color:var(--muted)}
.toast{position:fixed;left:50%;top:calc(16px + env(safe-area-inset-top));transform:translate(-50%,-20px);opacity:0;pointer-events:none;background:var(--fg);color:var(--bg);padding:10px 16px;border-radius:999px;font-size:15px;font-weight:600;transition:opacity .2s ease,transform .2s ease;z-index:10;max-width:calc(100% - 32px);text-align:center}
.toast.show{opacity:1;transform:translate(-50%,0)}
.offscreen,.hp{position:absolute!important;left:-10000px!important;top:auto;width:1px;height:1px;overflow:hidden}
@media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
`;

const CARD_CSS = String.raw`
.face{position:relative;container-type:inline-size;aspect-ratio:85/55;width:100%;overflow:hidden;border-radius:4.4cqw;background:var(--c-bg);color:var(--c-fg);border:1px solid rgba(var(--c-fg-rgb),.10);box-shadow:0 1px 2px rgba(0,0,0,.06),0 16px 40px -14px var(--shadow);font-size:2.8cqw;line-height:1.3}
.face.fill-gradient{background:linear-gradient(140deg,var(--c-bg) 22%,var(--c-grad-end))}
.face *{margin:0}
.face .in{position:absolute;inset:8cqw}
.face .name{font-size:6cqw;line-height:1.08;font-weight:600;letter-spacing:-.015em;overflow-wrap:anywhere}
.face .role{color:var(--c-muted);font-size:3cqw;margin-top:1.1cqw}
.face .caps{text-transform:uppercase;letter-spacing:.2em;font-weight:600;font-size:2.5cqw}
.face-contacts{list-style:none;padding:0;display:grid;gap:1cqw;font-size:2.7cqw;line-height:1.25;min-width:0;font-variant-numeric:tabular-nums}
.face-contacts li{display:flex;align-items:baseline;gap:2.2cqw;min-width:0}
.face-contacts i{font-style:normal;color:var(--c-muted);font-size:.86em;flex:none;min-width:4.6cqw}
.face-contacts svg{width:2.9cqw;height:2.9cqw;color:var(--c-accent);align-self:center}
.face-contacts span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.face .logo{display:block;max-height:6cqw;max-width:16cqw;object-fit:contain;object-position:left}
.face .avatar{width:15cqw;height:15cqw;border-radius:50%;object-fit:cover;display:flex;align-items:center;justify-content:center;font-weight:600;font-size:5cqw}
.font-rounded.face{font-family:ui-rounded,"SF Pro Rounded","Nunito",-apple-system,sans-serif}
.font-serif.face{font-family:ui-serif,"New York",Georgia,"Times New Roman",serif}
.font-mono.face{font-family:ui-monospace,"SF Mono",Menlo,Consolas,monospace}
.tpl-minimal .top{display:flex;align-items:center;gap:2.2cqw}
.tpl-minimal .bottom{position:absolute;left:0;right:0;bottom:0;display:flex;align-items:flex-end;justify-content:space-between;gap:4cqw}
.tpl-minimal .face-contacts{max-width:50cqw}
.tpl-professional .deboss{position:absolute;left:0;top:0;bottom:0;width:44cqw;display:flex;align-items:center;justify-content:center;font-size:34cqw;font-weight:800;line-height:1;color:var(--c-bg);text-shadow:-.35cqw -.35cqw .3cqw rgba(0,0,0,.6),.35cqw .35cqw .3cqw rgba(255,255,255,.12)}
.tpl-professional.light .deboss{text-shadow:-.35cqw -.35cqw .3cqw rgba(0,0,0,.18),.35cqw .35cqw .3cqw rgba(255,255,255,.9)}
.tpl-professional .deboss img{max-width:26cqw;max-height:30cqw;filter:drop-shadow(-.3cqw -.3cqw .25cqw rgba(0,0,0,.5)) drop-shadow(.3cqw .3cqw .25cqw rgba(255,255,255,.1))}
.tpl-professional .in{left:44cqw;display:flex;flex-direction:column;justify-content:center;inset-inline-end:7cqw}
.tpl-professional .name{font-size:4.6cqw;color:var(--c-accent)}
.tpl-professional .role{color:var(--c-fg);font-size:2.9cqw}
.tpl-professional .co{color:var(--c-muted);font-size:2.3cqw;letter-spacing:.16em;text-transform:uppercase;margin-top:.9cqw}
.tpl-professional .face-contacts{margin-top:4.5cqw}
.tpl-modern .bar{position:absolute;left:8cqw;top:8cqw;width:6.5cqw;height:26cqw;border-radius:.4cqw;background:var(--foil)}
.tpl-modern .in{left:19cqw;right:16cqw;display:flex;flex-direction:column}
.tpl-modern .name{font-size:4.2cqw;text-transform:uppercase;letter-spacing:.06em}
.tpl-modern .role{font-style:italic;color:var(--c-fg);opacity:.85}
.tpl-modern .face-contacts{margin-top:auto;font-weight:500;font-size:2.8cqw}
.tpl-modern .word{position:absolute;right:6cqw;top:8cqw;bottom:8cqw;writing-mode:vertical-rl;transform:rotate(180deg);font-size:6.2cqw;font-weight:800;letter-spacing:.1em;text-transform:uppercase;color:transparent;-webkit-text-stroke:.18cqw var(--c-fg);white-space:nowrap;overflow:hidden}
.tpl-bold .word{font-size:12cqw;font-weight:800;letter-spacing:-.03em;line-height:.95;text-transform:uppercase;white-space:nowrap;overflow:hidden;text-overflow:clip}
.tpl-bold .tag{font-size:2.3cqw;letter-spacing:.24em;text-transform:uppercase;font-weight:600;color:var(--c-muted);margin-top:2.2cqw}
.tpl-bold .who{position:absolute;left:0;bottom:0;display:grid;gap:.7cqw}
.tpl-bold .who b{font-size:3.1cqw}
.tpl-bold .mark{position:absolute;right:0;bottom:0;max-width:9cqw;max-height:9cqw}
.tpl-bold.align-center .in{text-align:center}
.tpl-bold.align-center .who{left:0;right:0;justify-items:center}
.tpl-gradient{background:linear-gradient(135deg,var(--a1),var(--a2) 55%,var(--a3))!important;color:var(--a-ink)}
.tpl-gradient::before{content:"";position:absolute;inset:0;background:repeating-radial-gradient(ellipse 140% 80% at 30% 120%,transparent 0 3.2cqw,rgba(255,255,255,.16) 3.2cqw calc(3.2cqw + 1px));mix-blend-mode:soft-light}
.tpl-gradient .word{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:6.6cqw;font-weight:500;letter-spacing:.3em;text-transform:uppercase;padding:0 8cqw;text-align:center}
.tpl-gradient .foot{position:absolute;left:8cqw;right:8cqw;bottom:7cqw;display:flex;justify-content:space-between;gap:4cqw;font-size:2.6cqw;letter-spacing:.06em;opacity:.92;white-space:nowrap}
.tpl-gradient .foot span{overflow:hidden;text-overflow:ellipsis}
.tpl-split .panel{position:absolute;left:0;top:0;bottom:0;width:36cqw;background:var(--c-accent);display:flex;align-items:center;justify-content:center;color:var(--c-on-panel)}
.tpl-split .panel img.logo{max-width:20cqw;max-height:15cqw;object-position:center}
.tpl-split .panel .avatar{background:rgba(255,255,255,.18)}
.tpl-split .in{left:42.5cqw;right:6cqw;display:flex;flex-direction:column;justify-content:center}
.tpl-split .name{font-size:5.2cqw}
.tpl-split .role{font-size:2.9cqw}
.tpl-split .rule{width:7cqw;height:.35cqw;background:var(--c-accent);margin:3.4cqw 0}
.tpl-split .face-contacts li{align-items:center;gap:1.8cqw}
.tpl-terminal .p{color:var(--c-muted);font-size:2.6cqw}
.tpl-terminal .p b,.tpl-terminal .face-contacts i{color:var(--c-accent);font-weight:400}
.tpl-terminal .name{font-size:5.2cqw;margin-top:1.2cqw}
.tpl-terminal .name::after{content:"";display:inline-block;width:2.4cqw;height:4.2cqw;background:var(--c-accent);margin-left:1cqw;vertical-align:-.4cqw}
.tpl-terminal .face-contacts{position:absolute;left:0;bottom:0;max-width:84cqw}
.tpl-stack .in{inset:6cqw 8cqw;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center}
.tpl-stack .logo{max-height:8.5cqw;max-width:24cqw;object-position:center;margin-bottom:2.6cqw}
.tpl-stack .avatar{width:11cqw;height:11cqw;margin-bottom:2.6cqw;background:var(--c-panel);font-size:4cqw}
.tpl-stack .name{font-size:5.4cqw}
.tpl-stack .rule{width:8cqw;height:.35cqw;background:var(--c-accent);margin:3cqw 0}
.tpl-stack .face-contacts{display:flex;flex-wrap:wrap;justify-content:center;gap:.9cqw 3.2cqw;font-size:2.6cqw}
.tpl-editorial .art{position:absolute;left:-8cqw;top:50%;width:44cqw;height:44cqw;transform:translateY(-50%);display:flex;align-items:center;justify-content:center;font:400 44cqw/1 ui-serif,"New York",Georgia,serif;background:var(--foil);-webkit-background-clip:text;background-clip:text;color:transparent}
.tpl-editorial .art.img{background:none}
.tpl-editorial .art img{max-width:36cqw;max-height:36cqw}
.tpl-editorial .in{left:44cqw;display:flex;flex-direction:column}
.tpl-editorial .name{font-weight:500;font-size:5.8cqw;letter-spacing:.01em}
.tpl-editorial .role{font-style:italic;font-size:3.1cqw}
.tpl-editorial .hr{height:max(.3cqw,1px);background:var(--foil);margin:3cqw 0}
.tpl-editorial .face-contacts{gap:.7cqw;font-size:2.8cqw}
.tpl-editorial .co{margin-top:auto;font-size:2.9cqw;letter-spacing:.24em;text-transform:uppercase}
.notice{display:flex;gap:10px;align-items:center;margin:16px 0 0;padding:12px 14px;border-radius:14px;background:var(--surface);font-size:14px}
.notice span{flex:1}
.notice .btn{width:auto;min-height:36px;padding:6px 12px;font-size:14px;white-space:nowrap}
.p-inapp .notice.inapp{display:flex}
.notice.inapp{display:none}
.fields{list-style:none;margin:20px 0 0;padding:0;border-radius:16px;background:var(--surface);overflow:hidden}
.field{display:flex;align-items:center;min-height:60px}
.field+.field{border-top:1px solid var(--line)}
.field-link{display:flex;align-items:center;gap:14px;flex:1;min-width:0;padding:10px 14px;text-decoration:none}
.field-link .icon{color:var(--accent-text);display:flex}
.field-text{display:flex;flex-direction:column;min-width:0}
.label{display:block;font-size:12px;color:var(--muted)}
.label::first-letter{text-transform:uppercase}
.value{font-size:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.copy{display:flex;align-items:center;justify-content:center;width:44px;height:44px;margin-right:6px;padding:0;border:0;border-radius:12px;background:transparent;color:var(--accent-text);cursor:pointer}
.copy:active{background:var(--accent-soft)}
.copy svg{width:18px;height:18px}
.with-bar{padding-bottom:calc(150px + env(safe-area-inset-bottom))}
.bar{position:fixed;left:0;right:0;bottom:0;z-index:6;padding:18px 16px calc(12px + env(safe-area-inset-bottom));background:linear-gradient(to top,var(--bg) 72%,transparent)}
.bar-in{display:flex;flex-direction:column;gap:8px;max-width:428px;margin:0 auto}
.saved #exchange{order:-1;background:var(--accent);color:var(--on-accent)}
.saved #save{background:var(--fill);color:var(--fg)}
.shared .bar{display:none}
.shared .with-bar{padding-bottom:calc(28px + env(safe-area-inset-bottom))}
.shared-note{display:flex;align-items:center;justify-content:center;gap:8px;flex-wrap:wrap;min-height:44px;margin:16px 0 0;font-size:15px;color:var(--muted)}
.shared-note svg{color:var(--accent-text)}
.cta{display:flex;flex-direction:column;gap:12px;margin-top:20px;padding:14px 16px;border-radius:16px;background:var(--surface)}
.cta-text{display:flex;flex-direction:column;gap:2px}
.cta strong{font-size:15px}
.cta-text span{font-size:13px;color:var(--muted)}
.cta .btn{min-height:44px;font-size:15px;background:var(--accent-soft);color:var(--accent-text)}
.acted .cta-footer{position:sticky;bottom:calc(12px + env(safe-area-inset-bottom));z-index:5;box-shadow:0 10px 30px -8px var(--shadow)}
.acted .cta-footer .cta-text .get{display:none}
.acted .cta-footer .btn.get,.acted .cta-footer .btn.android{background:var(--accent);color:var(--on-accent)}
.cta .android,.os-android .cta .get{display:none}
.os-android .cta-text .android{display:block}
.os-android .cta .btn.android{display:flex}
dialog{width:100%;max-width:460px;max-height:calc(100dvh - 24px);margin:auto auto 0;padding:10px 20px calc(20px + env(safe-area-inset-bottom));border:0;border-radius:22px 22px 0 0;background:var(--surface);color:var(--fg);overflow:auto;box-shadow:0 -8px 40px var(--shadow)}
dialog::backdrop{background:rgba(0,0,0,.45)}
dialog:not([open]){display:none}
@media (min-width:600px){dialog{margin:auto;border-radius:22px;padding-bottom:22px}}
.grabber{width:36px;height:5px;border-radius:3px;background:var(--line);margin:0 auto 14px}
dialog h2{margin:0;font-size:22px;line-height:1.2}
dialog h2:focus{outline:none}
.sub{margin:6px 0 16px;color:var(--muted);font-size:15px}
.input{display:block;margin-top:12px}
.input span{display:block;font-size:13px;color:var(--muted);margin:0 0 4px 2px}
input{width:100%;min-height:48px;padding:12px 14px;border-radius:12px;border:1px solid var(--line);background:var(--fill);color:var(--fg);font:inherit;font-size:17px}
input:focus{border-color:var(--accent-text);outline:none}
input::placeholder{color:var(--muted);opacity:.8}
.swap{display:inline-block;margin:8px 2px 0;font-size:14px;text-decoration:none}
.hint{min-height:20px;margin:14px 2px 0;font-size:14px;color:var(--muted)}
.hint.err{color:var(--warn)}
.private{display:flex;align-items:center;gap:6px;margin:4px 2px 14px;font-size:14px;color:var(--muted)}
.private svg{width:15px;height:15px;color:var(--accent-text)}
#sb-form .btn+.btn{margin-top:8px}
.done{text-align:center}
.done .btn{margin-top:10px}
.done h2+.btn{margin-top:18px}
.done .cta{margin-top:22px;background:var(--fill)}
.done .cta-text .get{display:none}
.done .cta .btn{margin-top:0}
.done .cta .btn.get,.done .cta .btn.android{min-height:50px;font-size:17px;background:var(--accent);color:var(--on-accent)}
.check{width:56px;height:56px;margin:8px auto 14px;border-radius:50%;background:var(--accent);color:var(--on-accent);display:flex;align-items:center;justify-content:center}
.check svg{width:30px;height:30px}
.saved-row{display:flex;align-items:center;justify-content:center;gap:6px;margin:14px 0 0;color:var(--muted)}
.saved-row svg{color:var(--accent-text)}
.mind{margin:18px 0 0;font-size:14px;color:var(--muted)}
@media (min-width:768px){.wrap{padding-top:56px}}
`;

const UNAVAILABLE_CSS = String.raw`
.empty{display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;min-height:calc(100dvh - 120px);gap:6px}
.empty .mark{width:64px;height:64px;border-radius:50%;background:var(--fill);display:flex;align-items:center;justify-content:center;color:var(--muted);margin-bottom:10px}
.empty .mark svg{width:30px;height:30px}
.empty h1{margin:0;font-size:22px;line-height:1.25}
.empty p{margin:0;color:var(--muted);max-width:320px}
`;

/** Page script: analytics beacon, copy buttons, share-back sheet, removal, "Get the app". */
const CARD_JS = String.raw`(function () {
  'use strict';
  var d = document, b = d.body;
  var slug = b.getAttribute('data-slug');
  var T = {};
  try { T = JSON.parse(b.getAttribute('data-t') || '{}'); } catch (e) {}
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
  if (/Android/i.test(navigator.userAgent || '')) b.classList.add('os-android');
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
  on('copy-link', 'click', function () { copy(location.href.split('#')[0], function () { toast(T.linkCopied); }); });

  function refresh() {
    var shared = !!get('localStorage', KEY), saved = !!get('localStorage', SAVED);
    if ($('shared')) $('shared').hidden = !shared;
    if ($('done-save')) $('done-save').hidden = saved;
    if ($('done-saved')) $('done-saved').hidden = !saved;
    // Saved: "Exchange" becomes the main button. Shared: the bar goes and "Want a card like this?" stays in view.
    b.classList.toggle('saved', saved);
    b.classList.toggle('shared', shared);
    b.classList.toggle('acted', shared);
  }
  function markSaved() { put('localStorage', SAVED, { at: Date.now() }); setTimeout(refresh, 500); }
  var offerAfterSave = null;
  function onSave(e) {
    if (platform === 'inapp') { e.preventDefault(); toast(T.openInBrowser); return; }
    markSaved();
    // Their contact is asked for only after they got what they came for — and only once per visit.
    if (offerAfterSave && !get('localStorage', KEY) && !get('sessionStorage', SKIP)) setTimeout(offerAfterSave, 1200);
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
  var tried = false, viaTelegram = false;
  function field(n) { return form.querySelector('[name="' + n + '"]'); }
  function openSheet(showDone, focusName) {
    form.hidden = !!showDone; done.hidden = !showDone;
    if (typeof sheet.showModal === 'function') { if (!sheet.open) sheet.showModal(); } else sheet.setAttribute('open', '');
    if (focusName) field('name').focus();
  }
  offerAfterSave = function () { if (!sheet.open) openSheet(false, false); };
  function useTelegram(on) {
    viaTelegram = on;
    $('sb-phone').hidden = on; $('sb-telegram').hidden = !on;
    $('sb-use-telegram').hidden = on; $('sb-use-phone').hidden = !on;
    field(on ? 'telegram' : 'phone').focus();
    if (tried) validate();
  }
  on('sb-use-telegram', 'click', function () { useTelegram(true); });
  on('sb-use-phone', 'click', function () { useTelegram(false); });
  function closeSheet() { if (typeof sheet.close === 'function') sheet.close(); else sheet.removeAttribute('open'); }
  function values() {
    return {
      name: field('name').value.trim(),
      phone: viaTelegram ? '' : field('phone').value.trim(), telegram: viaTelegram ? field('telegram').value.trim() : '',
      metAt: field('metAt').value.trim(), website: field('website').value
    };
  }
  function say(text, isError) { hint.textContent = text; hint.classList.toggle('err', !!isError); }
  // Nothing is flagged before they try to send; after that the message follows what they type.
  function validate() {
    var v = values();
    var msg = !v.name ? T.needName : (!v.phone && !v.telegram ? T.needContact : '');
    if (tried) say(msg, true);
    return !msg;
  }
  form.addEventListener('input', function () { if (tried) validate(); });
  on('exchange', 'click', function () { openSheet(false, true); });
  on('sb-skip', 'click', function () { put('sessionStorage', SKIP, true); closeSheet(); });
  on('done-back', 'click', closeSheet);
  sheet.addEventListener('click', function (e) { if (e.target === sheet) closeSheet(); });

  var sending = false;
  form.addEventListener('submit', function (e) {
    e.preventDefault();
    if (sending) return;
    tried = true;
    if (!validate()) {
      var v0 = values();
      field(!v0.name ? 'name' : (viaTelegram ? 'telegram' : 'phone')).focus();
      return;
    }
    var v = values();
    sending = true; send.disabled = true; say(T.sending, false);
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
        form.reset(); tried = false; say('', false); refresh(); openSheet(true);
        if (!get('localStorage', SAVED) && (platform === 'ios' || platform === 'android')) {
          markSaved(); location.href = $('save').getAttribute('href');
        }
        return;
      }
      // The API's validation messages are English: show the page's own text for the field instead.
      var details = (res.body && res.body.details) || {};
      say(res.status === 429 ? T.tooMany
        : details.name ? (v.name ? T.invalidName : T.needName)
        : details.phone ? (v.phone ? T.invalidPhone : T.needContact)
        : details.telegram ? T.invalidTelegram
        : details.metAt ? T.invalidMetAt
        : T.failed, true);
      send.disabled = false;
    }, function () { sending = false; send.disabled = false; say(T.offline, true); });
  });

  function removeContact() {
    var sb = get('localStorage', KEY);
    if (!sb) return;
    fetch('/api/public/sharebacks/' + encodeURIComponent(sb.id), {
      method: 'DELETE', credentials: 'omit', headers: { 'X-Removal-Token': sb.token }
    }).then(function (r) {
      if (r.status === 204 || r.status === 403) {
        put('localStorage', KEY, null); refresh(); closeSheet();
        toast(r.status === 204 ? T.removed : T.cannotRemove);
      } else toast(T.removeFailed);
    }, function () { toast(T.offline); });
  }
  on('done-remove', 'click', removeContact);
  on('remove-inline', 'click', removeContact);

  refresh();
})();`;

function head(opts: {
  nonce: string;
  title: string;
  description: string;
  ogLocale: string;
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
<meta name="theme-color" content="#f2f2f7" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#000000" media="(prefers-color-scheme: dark)">
<title>${opts.title}</title>
<meta name="description" content="${opts.description}">
<meta property="og:type" content="profile">
<meta property="og:site_name" content="Nameshake">
<meta property="og:title" content="${opts.title}">
<meta property="og:description" content="${opts.description}">
<meta property="og:locale" content="${opts.ogLocale}">
${opts.ogUrl ? html`<meta property="og:url" content="${opts.ogUrl}">` : ''}
${opts.ogImage ? html`<meta property="og:image" content="${opts.ogImage}">` : ''}
<meta name="twitter:card" content="summary">
${opts.appBanner ?? ''}
<style nonce="${opts.nonce}">${trusted(BRAND_CSS)}:root{${trusted(cssVariables(opts.colors))}}${trusted(BASE_CSS)}${trusted(opts.extraCss)}</style>
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
  return design.template === 'bold' ? design.alignment : 'leading';
}

function effectiveFont(design: CardDesign): string {
  if (design.template === 'terminal') return 'mono';
  if (design.template === 'editorial') return 'serif';
  return design.font;
}

/** Contacts printed on the face itself, like the app's card (the full list follows below it). */
const FACE_CONTACTS = 3;

/** Templates that print contacts with a text label (`tel`, `mail`) instead of an icon. */
const LABELLED = new Set(['minimal', 'terminal']);
/** Templates that print plain values. */
const PLAIN = new Set(['professional', 'modern', 'bold', 'stack', 'editorial']);

function faceContacts(template: string, actions: ContactAction[], limit = FACE_CONTACTS): SafeHtml | '' {
  if (actions.length === 0) return '';
  const row = (a: ContactAction) =>
    LABELLED.has(template)
      ? html`<li><i>${a.key}</i><span>${a.display}</span></li>`
      : PLAIN.has(template)
        ? html`<li><span>${a.display}</span></li>`
        : html`<li>${ICONS[a.kind] ?? ''}<span>${a.display}</span></li>`;
  return html`<ul class="face-contacts" aria-hidden="true">${actions.slice(0, limit).map(row)}</ul>`;
}

/**
 * The card face — an HTML mirror of the app's nine templates (MetlyCardKit `Face/Templates`, card templates v2).
 * Sizes are in `cqw` (percent of the card width), the same unit the app uses, so the layout matches at any width.
 */
function face(view: PublicView, actions: ContactAction[]): SafeHtml {
  const { design, profile } = view;
  const t = design.template;
  const classes = [
    'face',
    `tpl-${t}`,
    `font-${effectiveFont(design)}`,
    `align-${effectiveAlignment(design)}`,
    design.appearance === 'light' ? 'light' : 'dark',
    t !== 'gradient' && design.background === 'gradient' ? 'fill-gradient' : 'fill-solid',
  ].join(' ');
  const title = profile.jobTitle.trim();
  const company = profile.company.trim();
  const name = view.fullName;
  const logo = view.logoUrl;
  const img = (cls: string) => (logo ? html`<img class="${cls}" src="${logo}" alt="" referrerpolicy="no-referrer">` : '');
  const avatar = view.photoUrl
    ? html`<img class="avatar" src="${view.photoUrl}" alt="" referrerpolicy="no-referrer">`
    : html`<span class="avatar" aria-hidden="true">${initials(name)}</span>`;
  const monogram = ([...company][0] ?? [...name][0] ?? '?').toUpperCase();
  const contacts = faceContacts(t, actions);
  let body: SafeHtml;

  switch (t) {
    case 'professional':
      body = html`<div class="deboss" aria-hidden="true">${logo ? img('') : monogram}</div>
<div class="in"><h1 class="name">${name}</h1>${title ? html`<p class="role">${title}</p>` : ''}${company ? html`<p class="co">${company}</p>` : ''}${contacts}</div>`;
      break;
    case 'modern':
      body = html`<div class="bar" aria-hidden="true"></div>
<div class="in"><h1 class="name">${name}</h1>${title ? html`<p class="role">${title}</p>` : ''}${contacts}</div>
${company ? html`<div class="word" aria-hidden="true">${company}</div>` : ''}`;
      break;
    case 'bold': {
      const word = company || (name.trim().split(/\s+/)[0] ?? name);
      body = html`<div class="in"><p class="word" aria-hidden="true">${word}</p>${title ? html`<p class="tag">${title}</p>` : ''}
<div class="who"><h1 class="name"><b>${name}</b></h1>${faceContacts(t, actions, 2)}</div>${logo && effectiveAlignment(design) === 'leading' ? img('mark') : ''}</div>`;
      break;
    }
    case 'gradient': {
      const link = actions.find((a) => a.kind === 'website') ?? actions[0];
      const caption = [title, company].filter(Boolean).join(' · ');
      body = html`<h1 class="word">${name}</h1>
<div class="foot" aria-hidden="true"><span>${link?.display ?? ''}</span><span>${caption}</span></div>`;
      break;
    }
    case 'split':
      body = html`<div class="panel" aria-hidden="true">${logo ? img('logo') : avatar}</div>
<div class="in"><h1 class="name">${name}</h1>${title ? html`<p class="role">${title}</p>` : ''}${company ? html`<p class="role">${company}</p>` : ''}<div class="rule"></div>${contacts}</div>`;
      break;
    case 'terminal': {
      const folder = company.toLowerCase().replace(/[^\p{L}\p{N}]/gu, '') || 'nameshake';
      const comment = [title.toLowerCase(), company ? `@ ${company.toLowerCase()}` : ''].filter(Boolean).join(' ');
      body = html`<div class="in"><p class="p" aria-hidden="true">~/${folder} <b>$</b> whoami</p><h1 class="name">${name}</h1>${comment ? html`<p class="role"># ${comment}</p>` : ''}${contacts}</div>`;
      break;
    }
    case 'stack':
      body = html`<div class="in">${logo ? img('logo') : view.photoUrl ? avatar : ''}<h1 class="name">${name}</h1>${[title, company].filter(Boolean).length ? html`<p class="role">${[title, company].filter(Boolean).join(' · ')}</p>` : ''}${actions.length ? html`<div class="rule"></div>` : ''}${contacts}</div>`;
      break;
    case 'editorial':
      body = html`<div class="art${logo ? ' img' : ''}" aria-hidden="true">${logo ? img('') : monogram}</div>
<div class="in"><h1 class="name">${name}</h1>${title ? html`<p class="role">${title}</p>` : ''}<div class="hr"></div>${contacts}${company ? html`<p class="co">${company}</p>` : ''}</div>`;
      break;
    default:
      body = html`<div class="in"><div class="top">${img('logo')}${company ? html`<span class="caps">${company}</span>` : ''}</div>
<div class="bottom"><div><h1 class="name">${name}</h1>${title ? html`<p class="role">${title}</p>` : ''}</div>${contacts}</div></div>`;
  }
  return html`<section class="${classes}" aria-label="${name}">${body}</section>`;
}

/** Per-card finish colours (foil, Aurora stops, Duotone panel ink) for the nonce'd style block — the CSP
 * allows no inline `style` attributes. */
function faceVariables(design: CardDesign): string {
  const [a1, a2, a3] = auroraColors(design);
  return [
    `--foil:${design.template === 'editorial' ? metalFoil(design) : holographicFoil(design)}`,
    `--a1:${a1};--a2:${a2};--a3:${a3}`,
    `--a-ink:${design.appearance === 'light' ? 'var(--c-fg)' : '#ffffff'}`,
    `--c-on-panel:${pageColors(design).onAccent}`,
  ].join(';');
}

/**
 * Contact rows in the owner's order (the card's visible entries): phones tap-to-call with their label,
 * WhatsApp → wa.me, Instagram → instagram.com, the rest as before.
 */
function contactRows(view: PublicView): { actions: ContactAction[]; labelPhones: boolean } {
  const actions = view.contacts
    .map((entry) => {
      const action = contactAction(entry);
      return action && entry.kind === 'phone' ? { ...action, phoneLabel: entry.label ?? 'mobile' } : action;
    })
    .filter((a): a is ContactAction => a !== null);
  const phones = actions.filter((a) => a.kind === 'phone');
  // One mobile number keeps the plain "phone" label; several (or a Work/Home one) say which is which.
  const labelPhones = phones.length > 1 || phones.some((a) => a.phoneLabel !== 'mobile');
  return { actions, labelPhones };
}

function fieldRow(action: ContactAction, terminal: boolean, t: CardPageText, labelPhones: boolean): SafeHtml {
  const phoneLabel = labelPhones && action.kind === 'phone' ? action.phoneLabel : undefined;
  const name = phoneLabel ? t.phoneLabel[phoneLabel] : t.fieldLabel[action.kind];
  const label = terminal ? (phoneLabel ? PHONE_KEYS[phoneLabel] : action.key) : name;
  const body = html`<span class="icon">${ICONS[action.kind] ?? ''}</span><span class="field-text"><span class="label">${label}</span><span class="value">${action.display}</span></span>`;
  const external = action.kind !== 'phone' && action.kind !== 'email';
  const track = action.kind === 'telegram' ? 'telegram_open' : null;
  const link = action.href
    ? html`<a class="field-link" href="${action.href}"${external ? trusted(' target="_blank" rel="noopener noreferrer"') : ''}${track ? html` data-track="${track}"` : ''}>${body}</a>`
    : html`<div class="field-link">${body}</div>`;
  const copyable = action.kind === 'phone' || action.kind === 'email';
  const copied = action.kind === 'phone' ? t.phoneCopied : t.emailCopied;
  const copy = copyable
    ? html`<button class="copy" type="button" data-copy="${action.display}" data-kind="${action.kind}" data-copied="${copied}" aria-label="${t.copyAria(name)}" title="${t.copy}">${ICONS.copy}</button>`
    : '';
  return html`<li class="field">${link}${copy}</li>`;
}

/**
 * "Want a card like this?" — at the foot of the card and after a share-back (`from` tags the App Store
 * campaign). Android visitors see "iPhone only for now" and, with the bot's waitlist, "Notify me";
 * the `os-android` class (server user agent, then the page script) picks the variant.
 */
function cta(t: CardPageText, getAppHref: string, from: 'footer' | 'shareback', androidWaitlistUrl?: string): SafeHtml {
  return html`<section class="cta cta-${from}"><div class="cta-text"><strong>${t.ctaTitle}</strong><span class="get">${t.ctaSubtitle}</span><span class="android">${androidWaitlistUrl ? t.androidWaitlist : t.androidOnly}</span></div><a class="btn get" href="${getAppHref}?from=${from}" data-get-app>${t.ctaButton}</a>${
    androidWaitlistUrl ? html`<a class="btn android" href="${androidWaitlistUrl}" target="_blank" rel="noopener noreferrer">${t.notifyMe}</a>` : ''
  }</section>`;
}

export function renderCardPage(opts: CardPageOptions): string {
  const { view, nonce, platform, lang, appStoreId, appAvailable, androidWaitlistUrl } = opts;
  const t = CARD_PAGE_TEXT[lang];
  const colors = pageColors(view.design);
  const first = view.firstName.trim() || t.cardOwner;
  const role = [view.profile.jobTitle.trim(), view.profile.company.trim()].filter(Boolean).join(' · ');
  const { actions, labelPhones } = contactRows(view);
  const vcfHref = `/c/${view.slug}.vcf`;
  const getAppHref = `/c/${view.slug}/get-app`;
  const banner = appStoreId
    ? html`<meta name="apple-itunes-app" content="app-id=${appStoreId}, app-argument=${view.url}">`
    : undefined;
  const footerCta = appAvailable ? cta(t, getAppHref, 'footer', androidWaitlistUrl) : '';
  const sharebackCta = appAvailable ? cta(t, getAppHref, 'shareback', androidWaitlistUrl) : '';

  const doc = html`<!doctype html>
<html lang="${lang}">
${head({
  nonce,
  title: `${view.fullName} · Nameshake`,
  description: role || t.description,
  ogLocale: t.ogLocale,
  colors,
  extraCss: `${CARD_CSS}.face{${faceVariables(view.design)}}`,
  ogUrl: view.url,
  ogImage: view.photoUrl ? safeHttpUrl(view.photoUrl) : null,
  appBanner: banner,
})}
<body class="p-${platform}${opts.android ? ' os-android' : ''}" data-slug="${view.slug}" data-platform="${platform}" data-t="${JSON.stringify(t.script)}">
<main class="wrap with-bar">
${face(view, actions)}
<div class="notice inapp" role="note"><span>${t.inAppNotice}</span><button class="btn" type="button" id="copy-link">${t.copyLink}</button></div>
${actions.length > 0 ? html`<ul class="fields" aria-label="${t.contactDetails}">${actions.map((a) => fieldRow(a, view.design.template === 'terminal', t, labelPhones))}</ul>` : ''}
<p class="shared-note" id="shared" hidden>${ICONS.check}<span>${t.sent(first)}</span><button class="link" type="button" id="remove-inline">${t.removeMine}</button></p>
${footerCta}
<p class="foot">${t.foot}</p>
</main>
<div class="bar"><div class="bar-in">
<a class="btn primary" id="save" href="${vcfHref}">${t.saveToContacts}</a>
<button class="btn tinted" type="button" id="exchange">${t.exchange(first)}</button>
</div></div>
<dialog id="sheet" aria-labelledby="sheet-title">
<form id="sb-form" novalidate autocomplete="on">
<div class="grabber" aria-hidden="true"></div>
<h2 id="sheet-title" tabindex="-1" autofocus>${t.sheetTitle(first)}</h2>
<p class="sub">${t.sheetSubtitle(first)}</p>
<label class="input"><span>${t.name}</span><input name="name" autocomplete="name" maxlength="80" placeholder="${t.namePlaceholder}" required></label>
<label class="input" id="sb-phone"><span>${t.phone}</span><input name="phone" type="tel" inputmode="tel" autocomplete="tel" maxlength="40" placeholder="+998"></label>
<label class="input" id="sb-telegram" hidden><span>${t.telegram}</span><input name="telegram" autocomplete="off" autocapitalize="none" autocorrect="off" spellcheck="false" maxlength="64" placeholder="${t.telegramPlaceholder}"></label>
<button class="link swap" type="button" id="sb-use-telegram">${t.useTelegram}</button><button class="link swap" type="button" id="sb-use-phone" hidden>${t.usePhone}</button>
<label class="input"><span>${t.metAt}</span><input name="metAt" maxlength="120" placeholder="${t.metAtPlaceholder}"></label>
<div class="hp" aria-hidden="true"><label>Website <input name="website" tabindex="-1" autocomplete="off"></label></div>
<p class="hint" id="sb-hint" role="status" aria-live="polite"></p>
<p class="private">${ICONS.lock}<span>${t.sendsTo(first)}</span></p>
<button class="btn primary" id="sb-send" type="submit">${t.send}</button>
<button class="btn plain" id="sb-skip" type="button">${t.skip}</button>
</form>
<div class="done" id="sb-done" hidden>
<div class="check">${ICONS.check}</div>
<h2>${t.doneTitle(first)}</h2>
<a class="btn${appAvailable ? '' : ' primary'}" id="done-save" href="${vcfHref}">${t.doneSave(first)}</a>
<p class="saved-row" id="done-saved" hidden>${ICONS.check}<span>${t.doneSaved(first)}</span></p>
${sharebackCta}
<button class="btn plain" type="button" id="done-back">${t.doneBack(first)}</button>
<p class="mind">${t.changedMind} <button class="link" type="button" id="done-remove">${t.removeMine}</button></p>
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
export function renderUnavailablePage(opts: { nonce: string; kind: UnavailableKind; lang: Lang }): string {
  const colors = pageColors(null);
  const t = UNAVAILABLE_PAGE_TEXT[opts.lang];
  const copy = t[opts.kind];
  return html`<!doctype html>
<html lang="${opts.lang}">
${head({ nonce: opts.nonce, title: 'Nameshake', description: copy.title, ogLocale: CARD_PAGE_TEXT[opts.lang].ogLocale, colors, extraCss: UNAVAILABLE_CSS })}
<body>
<main class="wrap">
<div class="empty">
<div class="mark">${ICONS.linkBreak}</div>
<h1>${copy.title}</h1>
<p>${copy.body}</p>
</div>
<p class="foot">${t.foot}</p>
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
