/// The page the bridge serves itself, over plain HTTP on the relay port.
///
/// A published page lives on `https://`, and a browser refuses to open a
/// `ws://` socket from an `https://` document: the mixed content rule blocks it
/// before the bridge ever sees a connection. That made the phone route
/// unusable — the QR code opened the hosted page, the hosted page could not
/// reach the bridge, and the only feedback was a message blaming the code.
///
/// Serving the console from the bridge itself removes the problem at its root:
/// the document and the socket share the same origin, port and host, so nothing
/// is mixed. It also means the address to open is the one the bridge already
/// knows, and the code travels in the QR URL exactly as before.
///
/// This is not a second implementation of the application. It is the console a
/// rider needs while standing next to the bike: the gear, two buttons, and the
/// link state. Everything else — the gear engine, the protocol, the trainer —
/// stays on the bridge, which is what makes this page small enough to be one
/// file with no dependency and no build step.
library;

/// HTML of the console, with [token] prefilled when the bridge knows it.
///
/// The token ends up in an attribute, so it is escaped. It comes from
/// [WebSocketRelayTransport.generateToken] — four letters of an alphabet without
/// `0`/`O` and `1`/`I` — and a wrong one is refused by the relay itself, not by
/// this page.
String consolePageHtml({String? token}) {
  final String safeToken = _escapeAttribute(token ?? '');
  return _template.replaceAll('__TOKEN__', safeToken);
}

/// Escapes the five characters that would end an attribute or an element.
String _escapeAttribute(String value) {
  if (value.isEmpty) return '';
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

/// The document. `__TOKEN__` is replaced by [consolePageHtml].
///
/// Deliberately dependency free: no font, no script from a CDN, no framework.
/// A phone reaching a bridge on a home network may have no internet at all, and
/// a page that needs the network to draw two buttons is a page that fails
/// exactly when it is needed.
const String _template = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#101418">
<meta name="apple-mobile-web-app-capable" content="yes">
<title>openzclick</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  body {
    margin: 0; min-height: 100vh; display: flex; flex-direction: column;
    background: #101418; color: #e8eaed;
    font: 400 17px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    padding: env(safe-area-inset-top) 16px calc(16px + env(safe-area-inset-bottom));
    gap: 16px; justify-content: center;
  }
  header { display: flex; align-items: center; justify-content: space-between; }
  h1 { font-size: 15px; font-weight: 600; letter-spacing: .04em; text-transform: uppercase; color: #9aa4b2; margin: 0; }
  #link { font-size: 13px; padding: 4px 10px; border-radius: 999px; background: #2a3038; color: #c8ced8; }
  #link.ok { background: #17351f; color: #8fe0a8; }
  #link.bad { background: #3a1d1d; color: #ffb4b4; }
  .card { background: #1a2027; border-radius: 20px; padding: 22px; }
  .gear { display: flex; align-items: baseline; gap: 10px; }
  #number { font-size: 88px; font-weight: 700; line-height: 1; letter-spacing: -.03em; font-variant-numeric: tabular-nums; }
  #of { font-size: 22px; color: #9aa4b2; }
  #mode { margin-left: auto; font-size: 13px; color: #9aa4b2; text-transform: uppercase; letter-spacing: .06em; }
  .row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-top: 22px; }
  button {
    appearance: none; border: 0; border-radius: 16px; padding: 22px 12px;
    font: inherit; font-weight: 600; color: #0b1014; background: #b8c8ff;
    display: flex; flex-direction: column; align-items: center; gap: 4px;
  }
  button:active { transform: scale(.985); background: #a3b7ff; }
  button[disabled] { background: #2a3038; color: #6b7481; }
  button small { font-weight: 500; font-size: 13px; opacity: .75; }
  .arrow { font-size: 24px; line-height: 1; }
  #code { display: flex; gap: 10px; }
  #code input {
    flex: 1; min-width: 0; font: inherit; font-size: 24px; letter-spacing: .35em;
    text-transform: lowercase; text-align: center; padding: 14px;
    border-radius: 16px; border: 1px solid #2f3742; background: #101418; color: #e8eaed;
  }
  #code button { flex: 0 0 auto; padding: 14px 20px; font-size: 16px; }
  #setup { display: none; }
  #setup.shown { display: block; }
  #hint { font-size: 13px; color: #9aa4b2; margin: 12px 0 0; }
  #last { font-size: 13px; color: #6b7481; text-align: center; min-height: 18px; }
  code { background: #242b34; padding: 2px 6px; border-radius: 6px; font-size: .92em; }
</style>
</head>
<body data-token="__TOKEN__">
<header>
  <h1>openzclick</h1>
  <span id="link">connecting…</span>
</header>

<section class="card">
  <div class="gear">
    <span id="number">–</span><span id="of"></span><span id="mode"></span>
  </div>
  <div class="row">
    <button id="up"><span class="arrow">▲</span><small>Shift up</small></button>
    <button id="down"><span class="arrow">▼</span><small>Shift down</small></button>
  </div>
</section>

<section class="card" id="setup">
  <div id="code">
    <input id="token" maxlength="8" autocapitalize="none" autocomplete="off"
           spellcheck="false" placeholder="code">
    <button id="connect">Connect</button>
  </div>
  <p id="hint">Type the four letters the bridge shows on its screen.</p>
</section>

<p id="last"></p>

<script>
(function () {
  var body = document.body;
  var link = document.getElementById('link');
  var number = document.getElementById('number');
  var of = document.getElementById('of');
  var mode = document.getElementById('mode');
  var last = document.getElementById('last');
  var up = document.getElementById('up');
  var down = document.getElementById('down');
  var setup = document.getElementById('setup');
  var input = document.getElementById('token');
  var connectButton = document.getElementById('connect');
  var socket = null;
  var retry = null;
  var gear = null;
  var count = null;
  var asked = false;

  function setLink(text, kind) {
    link.textContent = text;
    link.className = kind || '';
  }

  function paint() {
    var known = typeof gear === 'number';
    number.textContent = known ? String(gear) : '–';
    of.textContent = (known && count) ? '/ ' + count : '';
    var atTop = known && count && gear >= count;
    var atBottom = known && gear <= 1;
    up.disabled = !socket || atTop;
    down.disabled = !socket || atBottom;
  }

  function token() {
    return (body.getAttribute('data-token') || input.value || '').trim().toLowerCase();
  }

  function open() {
    var code = token();
    if (!code) { setup.classList.add('shown'); setLink('not connected', 'bad'); return; }
    asked = true;
    setLink('connecting…');
    var scheme = location.protocol === 'https:' ? 'wss:' : 'ws:';
    var url = scheme + '//' + location.host + '/console?token=' + encodeURIComponent(code);
    try { socket = new WebSocket(url); } catch (e) { failed('browser refused the address'); return; }
    socket.onopen = function () {
      setLink('connected', 'ok');
      // The code has done its job; leaving the field on screen next to a working
      // console reads as if something is still missing.
      setup.classList.remove('shown');
    };
    socket.onmessage = function (event) {
      var message;
      try { message = JSON.parse(event.data); } catch (e) { return; }
      if (message.type === 'state' || message.type === 'welcome') {
        var state = message.type === 'welcome' ? message.state : message;
        if (state && typeof state.gearNumber === 'number') {
          gear = state.gearNumber;
          count = state.gearCount;
          mode.textContent = state.mode ? String(state.mode).toUpperCase() : '';
          paint();
        }
      } else if (message.type === 'action' && message.label) {
        last.textContent = 'Controller: ' + message.label;
      }
    };
    socket.onclose = function () {
      socket = null;
      paint();
      if (!asked) return;
      setLink('reconnecting…', 'bad');
      setup.classList.add('shown');
      clearTimeout(retry);
      retry = setTimeout(open, 3000);
    };
    socket.onerror = function () { failed('the bridge refused this code'); };
  }

  function failed(reason) {
    asked = false;
    socket = null;
    paint();
    setLink('not connected', 'bad');
    setup.classList.add('shown');
    last.textContent = reason + '. Check the four letters on the bridge screen.';
  }

  function send(action) {
    if (!socket || socket.readyState !== 1) return;
    socket.send(JSON.stringify({ action: action }));
  }

  up.addEventListener('click', function () { send('shiftUp'); });
  down.addEventListener('click', function () { send('shiftDown'); });
  connectButton.addEventListener('click', function () {
    body.removeAttribute('data-token');
    open();
  });
  input.addEventListener('keydown', function (event) {
    if (event.key === 'Enter') { body.removeAttribute('data-token'); open(); }
  });

  // A phone on the same network reaches this page without internet; the code is
  // the only thing it needs, so the field is shown straight away when the URL
  // carries none.
  if (!token()) setup.classList.add('shown');
  paint();
  open();
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden && !socket) { clearTimeout(retry); open(); }
  });
})();
</script>
</body>
</html>
''';
