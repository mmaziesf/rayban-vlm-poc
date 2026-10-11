/* Glance VLM — Milestone 1 mock loop (no hardware, no network).
 * States: idle → listening → capturing → processing → answer | logged | error
 * The MockBrain stands in for the phone companion app (DAT capture + Gemma 4 E4B).
 */
(function () {
  'use strict';

  var $ = function (id) { return document.getElementById(id); };
  var ui = { label: $('stateLabel'), prompt: $('prompt'), answer: $('answer'), meta: $('meta') };
  var focusables = Array.prototype.slice.call(document.querySelectorAll('.focusable'));
  var busy = false;
  var voiceOn = localStorage.getItem('glance.voice') !== 'off';

  // ---- Mock phone "brain" -------------------------------------------------
  // Contract mirrors what the real phone app will return over the bridge.
  var MockBrain = {
    scenes: [
      { desc: 'A desk with a laptop, a coffee mug and a notebook. Light from a window on the left.',
        meal: null },
      { desc: 'A plate with grilled salmon, rice and steamed broccoli on a wooden table.',
        meal: { name: 'Grilled salmon, rice, broccoli', kcal: 620, protein_g: 42 } },
      { desc: 'A street crossing with a green pedestrian signal and two parked cars.',
        meal: null }
    ],
    i: 0,
    // Preferred: latest frame from the phone's rolling buffer (DAT stream @ 2 fps). Instant.
    // Fallback: on-demand still (DAT Photo / Stream.capturePhoto). Slow: transfer over the glasses link.
    captureFrame: function () {
      var f = LiveBuffer.select(Date.now(), 1500);
      if (f) return delay(30).then(function () { return f; });
      return delay(1800).then(function () {
        var s = MockBrain.scenes[MockBrain.i++ % MockBrain.scenes.length];
        return { id: 'p' + Date.now(), t: Date.now(), width: 1280, height: 720, source: 'capture', scene: s };
      });
    },
    infer: function (frame, command) {     // Gemma 4 E4B via LiteRT-LM on phone
      return delay(900).then(function () {
        if (command === 'log') {
          var m = frame.scene.meal;
          if (!m) return { kind: 'log', ok: false, text: 'No meal detected. Nothing logged.' };
          return { kind: 'log', ok: true, entry: { ts: new Date().toISOString(), frameId: frame.id, name: m.name,
                   kcal: m.kcal, protein_g: m.protein_g },
                   text: 'Logged: ' + m.name + ', about ' + m.kcal + ' calories.' };
        }
        return { kind: 'describe', text: frame.scene.desc };
      });
    }
  };

  // ---- Mock rolling frame buffer (mirrors phone/core FrameRingBuffer) -----
  var LiveBuffer = {
    fps: 2, cap: 6, frames: [], timer: null,
    start: function () {
      if (LiveBuffer.timer) return;
      LiveBuffer.timer = setInterval(LiveBuffer.tick, 1000 / LiveBuffer.fps);
      LiveBuffer.tick();
    },
    stop: function () { clearInterval(LiveBuffer.timer); LiveBuffer.timer = null; },
    tick: function () {
      // Scene changes every ~4 s of "head movement".
      var s = MockBrain.scenes[Math.floor(Date.now() / 4000) % MockBrain.scenes.length];
      LiveBuffer.frames.push({ id: 'b' + Date.now(), t: Date.now(), width: 896, height: 504, source: 'buffer', scene: s });
      if (LiveBuffer.frames.length > LiveBuffer.cap) LiveBuffer.frames.shift();
    },
    latest: function () { return LiveBuffer.frames[LiveBuffer.frames.length - 1] || null; },
    select: function (now, maxAge) { var f = LiveBuffer.latest(); return f && now - f.t <= maxAge ? f : null; },
    live: function () { return !!LiveBuffer.timer; }
  };

  function delay(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  // ---- UI state -----------------------------------------------------------
  var LABELS = { idle: 'Ready', listening: 'Listening', capturing: 'Capturing', processing: 'Thinking',
                 answer: 'Answer', logged: 'Logged', error: 'Error' };
  function setState(s, prompt) {
    document.body.setAttribute('data-state', s);
    ui.label.textContent = LABELS[s] || s;
    if (prompt !== undefined) ui.prompt.textContent = prompt;
    focusables.slice(0, 2).forEach(function (b) { b.setAttribute('aria-disabled', String(busy)); }); // keep focusable: no focus jumps
  }

  function speak(text) {
    if (!voiceOn || !('speechSynthesis' in window)) return;
    try {
      speechSynthesis.cancel();
      var u = new SpeechSynthesisUtterance(text);
      u.lang = 'en-US';
      u.onerror = function (e) { ui.meta.textContent += ' · voice unavailable (' + e.error + ')'; };
      speechSynthesis.speak(u);
    } catch (e) { /* text stays on screen */ }
  }

  function saveLog(entry) {               // M1 stand-in; real log lives in phone SQLite (Room/GRDB)
    var key = 'glance.log.v1';
    var arr = [];
    try { arr = JSON.parse(localStorage.getItem(key) || '[]'); if (!Array.isArray(arr)) arr = []; } catch (e) {}
    arr.push(entry); if (arr.length > 50) arr = arr.slice(-50);
    localStorage.setItem(key, JSON.stringify(arr));
    return arr.length;
  }

  var lastActionBtn = null;
  function restoreFocus() { if (lastActionBtn && !lastActionBtn.disabled) lastActionBtn.focus(); }

  function run(command) {
    if (busy) return;
    busy = true;
    lastActionBtn = command === 'log' ? $('btnLog') : $('btnSee');
    var spoken = command === 'log' ? '“Log this meal”' : '“What am I seeing?”';
    var t0 = performance.now();
    ui.answer.textContent = ''; ui.meta.textContent = '';
    setState('listening', spoken);
    delay(300)
      .then(function () { setState('capturing', spoken); return MockBrain.captureFrame(); })
      .then(function (frame) {
        var age = Date.now() - frame.t;
        setState('processing', spoken);
        return MockBrain.infer(frame, command).then(function (res) { res.frame = frame; res.frameAgeMs = age; return res; });
      })
      .then(function (res) {
        busy = false;
        var ms = Math.round(performance.now() - t0);
        var src = res.frame ? res.frame.source + ' · frame ' + Math.max(0, Math.round(res.frameAgeMs)) + ' ms · ' : '';
        ui.answer.textContent = res.text;
        if (res.kind === 'log' && res.ok) {
          var n = saveLog(res.entry);
          setState('logged', spoken);
          ui.meta.textContent = src + 'saved · ' + n + ' · ' + ms + ' ms';
        } else {
          setState('answer', spoken);
          ui.meta.textContent = src + ms + ' ms (mock)';
        }
        restoreFocus();
        speak(res.text);
      })
      .catch(function (err) {
        busy = false;
        setState('error', 'Something went wrong');
        ui.answer.textContent = String(err && err.message || err);
        restoreFocus();
      });
  }

  function toggleVoice(btn) {
    voiceOn = !voiceOn;
    localStorage.setItem('glance.voice', voiceOn ? 'on' : 'off');
    btn.textContent = voiceOn ? '🔊 Voice on' : '🔇 Voice off';
    btn.setAttribute('aria-pressed', String(voiceOn));
    if (!voiceOn && 'speechSynthesis' in window) speechSynthesis.cancel();
  }

  function toggleCam(btn) {
    if (LiveBuffer.live()) LiveBuffer.stop(); else LiveBuffer.start();
    var on = LiveBuffer.live();
    btn.textContent = on ? '📷 Live cam on' : '📷 Live cam off';
    btn.setAttribute('aria-pressed', String(on));
    renderChip();
  }

  var chip = $('bufChip');
  function renderChip() {
    var f = LiveBuffer.latest();
    if (!LiveBuffer.live()) { chip.textContent = 'Camera off'; chip.className = 'chip off'; return; }
    var age = f ? (Date.now() - f.t) / 1000 : null;
    chip.textContent = age === null ? 'Live · waiting' : 'Live ' + LiveBuffer.fps + ' fps · ' + age.toFixed(1) + ' s';
    chip.className = 'chip' + (age !== null && age > 1.5 ? ' stale' : '');
  }

  // ---- Input: D-pad = arrow keys, Select = Enter -------------------------
  focusables.forEach(function (b) {
    b.addEventListener('click', function () {
      var a = b.getAttribute('data-action');
      if (a === 'speak') toggleVoice(b); else if (a === 'cam') toggleCam(b); else run(a);
    });
  });

  function enabled() { return focusables.filter(function (b) { return !b.disabled; }); }
  function moveFocus(step) {
    var list = enabled(); if (!list.length) return;
    var i = list.indexOf(document.activeElement);
    var n = i === -1 ? 0 : (i + step + list.length) % list.length;
    list[n].focus();
  }
  document.addEventListener('keydown', function (e) {
    switch (e.key) {
      case 'ArrowUp': case 'ArrowLeft': moveFocus(-1); break;
      case 'ArrowDown': case 'ArrowRight': moveFocus(1); break;
      case 'Enter':
        if (document.activeElement && document.activeElement.classList.contains('focusable')) {
          document.activeElement.click();
        }
        break;
      case 'Escape': case 'Backspace':
        if (busy) return;
        if (document.body.getAttribute('data-state') !== 'idle') {
          ui.answer.textContent = ''; ui.meta.textContent = '';
          setState('idle', 'Say or pick a command');
          break;
        }
        return; // let the system handle Back at the root (native menu)
      default: return;
    }
    e.preventDefault();
  });

  // Keep focus on an enabled button if the focused one becomes disabled
  document.addEventListener('focusout', function () {
    setTimeout(function () { if (!document.activeElement || document.activeElement === document.body) moveFocus(0); }, 0);
  });

  if (!voiceOn) { var s = $('btnSpeak'); s.textContent = '🔇 Voice off'; s.setAttribute('aria-pressed', 'false'); }
  setState('idle');
  LiveBuffer.start();
  renderChip();
  setInterval(renderChip, 500);
  focusables[0].focus();

  // Expose for automated checks
  window.__glance = { run: run, MockBrain: MockBrain, LiveBuffer: LiveBuffer };
})();
