const state = {
  csrf: null, authenticated: false, pendingAction: null, targetKind: null,
  catalog: { restart_targets: [], smart_targets: [] },
  telemetry: { generated: null, cpu: [], rx: [], tx: [], lastNetwork: null }
};
const $ = (id) => document.getElementById(id);
const safe = (value, fallback = "—") => value === null || value === undefined || value === "" ? fallback : value;
const fmtBytes = (bytes) => {
  if (!Number.isFinite(bytes)) return "—";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let value = bytes, index = 0;
  while (value >= 1024 && index < units.length - 1) { value /= 1024; index += 1; }
  return `${value >= 10 || index === 0 ? value.toFixed(0) : value.toFixed(1)} ${units[index]}`;
};
const fmtUptime = (seconds) => {
  if (!Number.isFinite(seconds)) return "—";
  const days = Math.floor(seconds / 86400), hours = Math.floor((seconds % 86400) / 3600);
  return days ? `${days}д ${hours}г` : `${hours}г ${Math.floor((seconds % 3600) / 60)}хв`;
};
const healthClass = (value) => ["healthy", "running", "online", "passed", "good", "success", "done"].includes(value) ? "good" : ["warning", "unknown", "none"].includes(value) ? "warning" : "bad";
const icon = (name) => `<svg class="icon"><use href="/static/vendor/bootstrap-icons.svg#${name}"></use></svg>`;
const fmtRate = (bytes) => bytes >= 1048576 ? `${(bytes / 1048576).toFixed(1)} MB/s` : bytes >= 1024 ? `${(bytes / 1024).toFixed(0)} KB/s` : `${Math.round(bytes)} B/s`;

function drawLines(canvas, series, colors, maximum = null, fill = false) {
  const width = Math.max(1, Math.floor(canvas.clientWidth * devicePixelRatio));
  const height = Math.max(1, Math.floor(canvas.clientHeight * devicePixelRatio));
  if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
  const context = canvas.getContext("2d"); context.clearRect(0, 0, width, height);
  const values = series.flat(); const maxValue = maximum || Math.max(1, ...values) * 1.12;
  series.forEach((points, seriesIndex) => {
    if (points.length < 2) return;
    const plot = () => points.forEach((value, index) => {
      const x = index / Math.max(1, points.length - 1) * width;
      const y = height - Math.min(1, Math.max(0, value / maxValue)) * (height - 2 * devicePixelRatio) - devicePixelRatio;
      index ? context.lineTo(x, y) : context.moveTo(x, y);
    });
    if (fill && seriesIndex === 0) { context.beginPath(); plot(); context.lineTo(width, height); context.lineTo(0, height); context.closePath(); context.fillStyle = "rgba(104,164,255,.13)"; context.fill(); }
    context.beginPath(); plot();
    context.strokeStyle = colors[seriesIndex]; context.lineWidth = 2 * devicePixelRatio; context.lineJoin = "round"; context.lineCap = "round"; context.stroke();
  });
}

function updateTelemetry(payload) {
  const generated = payload.generated_at_epoch, telemetry = state.telemetry;
  if (!Number.isFinite(generated) || generated === telemetry.generated) return;
  telemetry.cpu.push(Number(payload.cpu?.usage_percent || 0)); telemetry.cpu = telemetry.cpu.slice(-40);
  const network = payload.network || {}, previous = telemetry.lastNetwork;
  let rxRate = 0, txRate = 0;
  if (previous && Number.isFinite(previous.rx) && Number.isFinite(previous.tx) && Number.isFinite(network.rx_bytes) && Number.isFinite(network.tx_bytes)) {
    const seconds = generated - previous.generated;
    if (seconds > 0) { rxRate = Math.max(0, (network.rx_bytes - previous.rx) / seconds); txRate = Math.max(0, (network.tx_bytes - previous.tx) / seconds); }
  }
  telemetry.rx.push(rxRate); telemetry.tx.push(txRate); telemetry.rx = telemetry.rx.slice(-40); telemetry.tx = telemetry.tx.slice(-40);
  telemetry.lastNetwork = { generated, rx: network.rx_bytes, tx: network.tx_bytes }; telemetry.generated = generated;
  $("rx-rate").textContent = `↓ ${fmtRate(rxRate)}`; $("tx-rate").textContent = `↑ ${fmtRate(txRate)}`;
  requestAnimationFrame(() => { drawLines($("cpu-chart"), [telemetry.cpu], ["#68a4ff"], 100, true); drawLines($("network-chart"), [telemetry.rx, telemetry.tx], ["#56d5b0", "#ab8cff"]); });
}

function renderProcess(id, process, metric) {
  const row = $(id), name = row.querySelector("span"), value = row.querySelector("b");
  name.textContent = safe(process?.name); value.textContent = metric === "cpu" ? `${Number(process?.cpu_percent || 0).toFixed(1)}%` : fmtBytes(process?.memory_bytes);
}

function renderRamStack(memory) {
  const used = Math.max(0, Math.min(100, Number(memory.usage_percent || 0)));
  const segment = (width, kind, label) => {
    const wrapper = document.createElement("div"); wrapper.className = "progress"; wrapper.style.width = `${width}%`;
    wrapper.setAttribute("role", "progressbar"); wrapper.setAttribute("aria-label", label); wrapper.setAttribute("aria-valuenow", width); wrapper.setAttribute("aria-valuemin", "0"); wrapper.setAttribute("aria-valuemax", "100");
    const bar = document.createElement("div"); bar.className = `progress-bar ${kind}`; wrapper.append(bar); return wrapper;
  };
  $("ram-stack").replaceChildren(segment(used, "used", "RAM used"), segment(100 - used, "free", "RAM available"));
}

function renderDisks(disks = []) {
  $("storage-summary").textContent = `${disks.length}×`;
  $("disk-list").replaceChildren(...disks.map((disk) => {
    const row = document.createElement("article"); row.className = "disk-row";
    row.innerHTML = `<span class="disk-icon ${disk.external ? "external" : ""}">${icon(disk.external ? "usb-symbol" : "device-hdd")}</span><div class="disk-main"><div class="disk-name"></div></div><span class="disk-health"></span><div class="disk-usage"><div class="disk-progress"><span></span></div><span class="disk-detail"></span></div>`;
    const usage = Number.isFinite(disk.usage_percent) ? disk.usage_percent : null;
    row.querySelector(".disk-name").textContent = safe(disk.label || disk.model || disk.device);
    const smart = safe(disk.smart_status, "unknown"); const health = row.querySelector(".disk-health");
    health.className = `disk-health ${healthClass(smart)}`; health.textContent = smart === "passed" ? "✓ SMART" : smart === "failed" ? "! SMART" : "? SMART";
    row.querySelector(".disk-progress span").style.setProperty("--value", `${Math.min(100, usage || 0)}%`);
    const space = usage === null ? fmtBytes(disk.total_bytes) : `${usage.toFixed(0)}% · ${fmtBytes(disk.free_bytes)} free`;
    const temp = Number.isFinite(disk.temperature_c) ? ` · ${disk.temperature_c}°C` : "";
    row.querySelector(".disk-detail").textContent = `${space}${temp}`;
    return row;
  }));
}

function render(payload) {
  const summary = payload.summary || {}, cpu = payload.cpu || {}, memory = payload.memory || {}, network = payload.network || {}, timers = payload.timers || {}, processes = payload.top_processes || {};
  const overall = payload.stale ? "unknown" : safe(summary.state, "unknown");
  $("overall-pill").className = `health-pill ${healthClass(overall)}`;
  $("overall-label").textContent = payload.stale ? "…" : overall === "good" ? "OK" : overall === "warning" ? "!" : "×";
  $("last-update").textContent = payload.generated_at ? new Date(payload.generated_at).toLocaleTimeString("uk-UA", {hour:"2-digit", minute:"2-digit", second:"2-digit"}) : "немає даних";
  $("cpu-value").textContent = Number.isFinite(cpu.usage_percent) ? `${cpu.usage_percent.toFixed(0)}%` : "—";
  $("cpu-temp").textContent = Number.isFinite(cpu.temperature_c) ? `${cpu.temperature_c.toFixed(0)}°` : "—";
  $("cpu-detail").textContent = `L ${safe(cpu.load_1)}`;
  $("ram-value").textContent = Number.isFinite(memory.usage_percent) ? `${memory.usage_percent.toFixed(0)}%` : "—";
  $("ram-total").textContent = fmtBytes(memory.total_bytes);
  $("ram-detail").textContent = `${fmtBytes(memory.used_bytes)} USED`;
  renderRamStack(memory); renderProcess("cpu-process", processes.cpu, "cpu"); renderProcess("ram-process", processes.memory, "memory"); updateTelemetry(payload);
  $("lan-address").textContent = network.lan_ipv4 ? `LAN .${network.lan_ipv4.split(".").pop()}` : "LAN —";
  $("tail-state").textContent = network.tailscale_online ? "TS ✓" : "TS ×";
  $("phone-state").textContent = network.phone_online ? "GT · TS ✓" : "GT · TS ×";
  $("network-detail").textContent = safe(network.tailscale_ipv4, safe(network.interface));
  $("uptime-value").textContent = `UP ${fmtUptime(summary.uptime_seconds)}`;
  const backupOk = ["success", "done"].includes(timers.backup?.result);
  $("backup-state").textContent = backupOk ? "BKP ✓" : "BKP !";
  const alerts = payload.alerts || [], strip = $("alert-strip");
  if (alerts.length) { strip.classList.remove("hidden"); strip.classList.toggle("bad", alerts.some((a) => a.level === "critical")); $("alert-text").textContent = alerts.slice(0, 3).map((a) => a.message.replace("App endpoint attention:", "APP:").replace("Container attention:", "CTR:")).join(" · "); }
  else { strip.classList.add("hidden"); }
  renderDisks(payload.disks || []);
}

async function refresh() {
  try { const response = await fetch("/api/v1/status", {cache: "no-store"}); if (!response.ok) throw new Error(); render(await response.json()); }
  catch { $("overall-pill").className = "health-pill bad"; $("overall-label").textContent = "offline"; }
}
async function refreshCatalog() {
  try { const response = await fetch("/api/v1/catalog", {cache:"no-store"}); if (response.ok) state.catalog = await response.json(); } catch { /* keep fail-closed empty lists */ }
}
async function refreshSession() {
  try { const data = await (await fetch("/api/v1/auth/session", {cache:"no-store"})).json(); state.authenticated = data.authenticated; state.csrf = data.csrf || null; }
  catch { state.authenticated = false; state.csrf = null; }
  $("auth-button").classList.toggle("authenticated", state.authenticated);
  $("auth-button").setAttribute("aria-label", state.authenticated ? "Вийти" : "Увійти");
}
function openLogin() { $("login-error").textContent = ""; $("login-password").value = ""; $("login-dialog").showModal(); setTimeout(() => $("login-password").focus(), 50); }
async function logout() { await fetch("/api/v1/auth/logout", {method:"POST", headers:{"X-CSRF-Token":state.csrf || ""}}); state.authenticated = false; state.csrf = null; await refreshSession(); }
async function submitLogin(event) {
  event.preventDefault(); $("login-error").textContent = "";
  const response = await fetch("/api/v1/auth/login", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify({username:$("login-user").value,password:$("login-password").value})});
  const data = await response.json().catch(() => ({}));
  if (!response.ok) { $("login-error").textContent = data.detail || "Не вдалося увійти"; return; }
  state.authenticated = true; state.csrf = data.csrf; $("login-dialog").close(); await refreshSession();
}
function openTarget(kind) {
  if (!state.authenticated) { openLogin(); return; }
  const targets = kind === "restart" ? state.catalog.restart_targets : state.catalog.smart_targets;
  if (!targets?.length) { showToast("Список дозволених цілей недоступний", true); return; }
  state.targetKind = kind; $("target-title").textContent = kind === "restart" ? "Restart service" : "SMART short test";
  $("action-target").replaceChildren(...targets.map((item) => { const option = document.createElement("option"); option.value = item.id; option.textContent = item.label; return option; }));
  $("target-dialog").showModal();
}
function submitTarget(event) { event.preventDefault(); const kind = state.targetKind; const target = $("action-target").value; $("target-dialog").close(); requestAction(kind === "restart" ? "restart" : "smart-short", target); }
function requestAction(action, target = null) {
  if (!state.authenticated) { openLogin(); return; }
  state.pendingAction = {action, target}; const power = action === "reboot" || action === "shutdown";
  const names = {backup:"Backup", "smart-short":`SMART · ${target}`, restart:`Restart · ${target}`, reboot:"Reboot HPServer", shutdown:"Shutdown HPServer"};
  $("confirm-title").textContent = names[action]; $("confirm-copy").textContent = power ? "Дія перерве роботу всіх сервісів. Повторіть пароль і назву сервера." : "Буде виконано лише заздалегідь дозволену дію; результат записується в журнал.";
  $("confirm-text-wrap").classList.toggle("hidden", !power); $("confirm-password-wrap").classList.toggle("hidden", !power);
  $("confirm-text").value = ""; $("confirm-password").value = ""; $("confirm-error").textContent = ""; $("confirm-dialog").showModal();
}
async function submitAction(event) {
  event.preventDefault(); const pending = state.pendingAction; if (!pending) return;
  const power = pending.action === "reboot" || pending.action === "shutdown";
  const body = {target:pending.target, confirmation:power ? $("confirm-text").value : "CONFIRM", password:power ? $("confirm-password").value : null};
  const response = await fetch(`/api/v1/actions/${pending.action}`, {method:"POST", headers:{"Content-Type":"application/json","X-CSRF-Token":state.csrf || ""}, body:JSON.stringify(body)});
  const data = await response.json().catch(() => ({})); if (!response.ok) { $("confirm-error").textContent = data.detail || "Дію відхилено"; return; }
  $("confirm-dialog").close(); showJob(data.job_id); state.pendingAction = null;
}
function showToast(message, bad = false) { const toast = $("job-toast"); toast.classList.remove("hidden"); toast.classList.toggle("bad", bad); toast.textContent = message; setTimeout(() => toast.classList.add("hidden"), 7000); }
async function showJob(jobId) {
  const toast = $("job-toast"); toast.classList.remove("hidden", "bad"); toast.textContent = "Дію поставлено в чергу…";
  for (let attempt = 0; attempt < 40; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 1000)); const response = await fetch(`/api/v1/jobs/${jobId}`); if (!response.ok) break; const job = await response.json();
    toast.textContent = job.state === "running" ? "Дія виконується…" : job.message || job.state;
    if (["succeeded", "failed"].includes(job.state)) { toast.classList.toggle("bad", job.state === "failed"); setTimeout(refresh, 1500); setTimeout(() => toast.classList.add("hidden"), 9000); return; }
  }
  toast.classList.add("bad"); toast.textContent = "Не вдалося отримати фінальний стан job";
}

document.querySelectorAll("[data-close]").forEach((button) => button.addEventListener("click", () => button.closest("dialog").close()));
document.querySelectorAll("[data-action]").forEach((button) => button.addEventListener("click", () => requestAction(button.dataset.action)));
$("restart-action").addEventListener("click", () => openTarget("restart")); $("smart-action").addEventListener("click", () => openTarget("smart"));
$("auth-button").addEventListener("click", () => state.authenticated ? logout() : openLogin());
$("login-form").addEventListener("submit", submitLogin); $("target-form").addEventListener("submit", submitTarget); $("confirm-form").addEventListener("submit", submitAction);
refresh(); refreshCatalog(); refreshSession(); setInterval(refresh, 5000); setInterval(refreshSession, 60000);
