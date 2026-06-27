/* dashboard live data — fetches data/progress.json + data/updates.json, renders, animates.
   Falls back gracefully (page ships with baked values in the JSON). */
(function () {
  "use strict";
  var fmt = function (n) { return (n || 0).toLocaleString("en-US"); };
  var reduce = window.matchMedia && matchMedia("(prefers-reduced-motion:reduce)").matches;

  function countUp(el, to) {
    if (reduce || !el) { if (el) el.textContent = fmt(to); return; }
    var from = 0, t0 = null, dur = 1100;
    function step(ts) {
      if (!t0) t0 = ts;
      var p = Math.min((ts - t0) / dur, 1), e = 1 - Math.pow(1 - p, 3);
      el.textContent = fmt(Math.round(from + (to - from) * e));
      if (p < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  }

  function timeAgo(iso) {
    var d = new Date(iso), s = (Date.now() - d) / 1000;
    if (s < 90) return "just now";
    if (s < 3600) return Math.round(s / 60) + " min ago";
    if (s < 86400) return Math.round(s / 3600) + " h ago";
    return d.toLocaleDateString();
  }

  function renderProgress(p) {
    var b = p.backfill || {}, w = p.warehouse || {};
    var set = function (id, v) { var e = document.getElementById(id); if (e) countUp(e, v); };
    set("m-rows", b.rows); set("m-nodes", b.nodes);
    set("w-tariffs", w.business_tariffs); set("w-domestic", w.domestic_rates);
    set("w-tou", w.tou_bands); set("w-cp", w.cp_mapped); set("w-pml", w.pml_zona_rows);
    // job progress bar
    var pct = b.jobs_total ? Math.round((b.jobs_total - b.jobs_left) / b.jobs_total * 100) : 0;
    var bar = document.getElementById("bar-jobs"); if (bar) setTimeout(function () { bar.style.width = pct + "%"; }, 200);
    var pl = document.getElementById("pct-jobs"); if (pl) pl.textContent = pct + "%";
    var et = document.getElementById("eta"); if (et) et.textContent = b.eta || "";
    var mk = document.getElementById("markets"); if (mk) mk.textContent = (b.markets_done || 0) + " / " + (b.markets_total || 2);
    var up = document.getElementById("updated"); if (up && p.updated_at) up.textContent = "Updated " + timeAgo(p.updated_at);
    var dot = document.getElementById("live-dot");
    if (dot) dot.className = "live-dot " + (b.status === "running" ? "on" : "");
    var st = document.getElementById("live-text");
    if (st) st.textContent = b.status === "running" ? "Collecting · live" : (b.status === "done" ? "Complete" : "Idle");
  }

  function renderFeed(list) {
    var wrap = document.getElementById("feed"); if (!wrap || !list) return;
    wrap.innerHTML = "";
    list.sort(function (a, b) { return new Date(b.ts) - new Date(a.ts); }).forEach(function (u, i) {
      var el = document.createElement("article");
      el.className = "update"; el.setAttribute("data-reveal", "");
      el.innerHTML =
        '<span class="tag">CEO Update' + (typeof u.n === "number" ? " #" + u.n : "") + '</span>' +
        '<div class="meta"><h3>' + u.title + '</h3><time>' + timeAgo(u.ts) + '</time></div>' +
        '<p>' + u.body + '</p>';
      wrap.appendChild(el);
    });
  }

  function load() {
    fetch("data/progress.json?t=" + Date.now()).then(function (r) { return r.json(); })
      .then(renderProgress).catch(function () {});
    fetch("data/updates.json?t=" + Date.now()).then(function (r) { return r.json(); })
      .then(renderFeed).catch(function () {});
  }

  document.addEventListener("DOMContentLoaded", function () {
    load();
    setInterval(load, 60000); // refresh every minute
  });
})();
