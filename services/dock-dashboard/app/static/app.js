const state = { csrf: null, authenticated: false, history: { cpu: [], ram: [] }, pendingAction: null };
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
const statusClass = (status) => status === "healthy" || status === "running" || status === "online" || status === "passed" || status === "good" ? "good" : status === "warning" || status === "unknown" ? "warning" : "bad";
function drawSparkline(canvas, values, color) {
  const ctx = canvas.getContext("2d"), width = canvas.clientWidth * devicePixelRatio, height = canvas.clientHeight * devicePixelRatio;
  if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
  ctx.clearRect(0, 0, width, height); if (values.length < 2) return;
  ctx.beginPath(); values.forEach((value, index) => {
    const x = (index / (values.length - 1)) * width, y = height - (Math.max(0, Math.min(100, value)) / 100) * height;
    index ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
  });
  ctx.strokeStyle = color; ctx.lineWidth = 2 * devicePixelRatio; ctx.stroke();
}
function setDot(id, value) { $(id).className = `state-dot ${statusClass(value)}`; }
function renderDisks(disks = []) {
  $("storage-summary").textContent = `${disks.length} devices`;
  $("disk-list").replaceChildren(...disks.map((disk) => {
    const row = document.createElement("article"); row.className = "disk-row";
    const usage = Number.isFinite(disk.usage_percent) ? disk.usage_percent : 0;
    row.innerHTML = `<div class="disk-top"><div><div class="disk-name"></div><div class="disk-meta"></div></div><span class="disk-health ${statusClass(disk.smart_status)}"></span></div><div class="progress"><span></span></div><div class="disk-bottom"><span class="disk-space"></span><span class="disk-temp"></span></div>`;
    row.querySelector(".disk-name").textContent = safe(disk.label || disk.model || disk.device);
    row.querySelector(".disk-meta").textContent = [disk.device, disk.mountpoint].filter(Boolean).join(" · ");
    row.querySelector(".disk-health").textContent = disk.smart_status === "passed" ? "SMART OK" : safe(disk.smart_status, "SMART —").toUpperCase();
    row.querySelector(".progress span").style.setProperty("--value", `${Math.min(100, usage)}%`);
    row.querySelector(".disk-space").textContent = disk.total_bytes ? `${fmtBytes(disk.used_bytes)} / ${fmtBytes(disk.total_bytes)} · ${usage.toFixed(0)}%` : safe(disk.size_human);
    row.querySelector(".disk-temp").textContent = Number.isFinite(disk.temperature_c) ? `${disk.temperature_c}°C` : "temp —";
    return row;
  }));
}
function renderApps(apps = [], containers = []) {
  $("app-grid").replaceChildren(...apps.map((item) => {
    const card = document.createElement("article"); card.className = "app-card";
    card.innerHTML = `<div class="app-card-top"><strong></strong><span class="state-dot"></span></div><span></span>`;
    card.querySelector("strong").textContent = item.name;
    card.querySelector(".state-dot").className = `state-dot ${statusClass(item.status)}`;
    card.querySelector("span:last-child").textContent = safe(item.detail, item.status);
    return card;
  }));
  const running = containers.filter((c) => c.state === "running").length;
  $("container-summary").textContent = `${running}/${containers.length} up`; $("container-count").textContent = containers.length;
  $("container-list").replaceChildren(...containers.map((container) => {
    const line = document.createElement("div"); line.className = "container-line";
    const dot = document.createElement("span"); dot.className = `state-dot ${statusClass(container.health || container.state)}`;
    const name = document.createElement("span"); name.textContent = container.name;
    const detail = document.createElement("span"); detail.textContent = container.health || container.state;
    line.append(dot, name, detail); return line;
  }));
}
function render(payload) {
  const summary = payload.summary || {}, cpu = payload.cpu || {}, memory = payload.memory || {}, network = payload.network || {}, timers = payload.timers || {};
  const overall = payload.stale ? "unknown" : safe(summary.state, "unknown"); setDot("overall-dot", overall);
  $("overall-label").textContent = payload.stale ? "Дані застаріли" : overall === "good" ? "Усе працює" : overall === "warning" ? "Потрібна увага" : "Є проблема";
  $("last-update").textContent = payload.generated_at ? new Date(payload.generated_at).toLocaleTimeString("uk-UA", {hour:"2-digit", minute:"2-digit", second:"2-digit"}) : "немає даних";
  $("cpu-value").textContent = Number.isFinite(cpu.usage_percent) ? `${cpu.usage_percent.toFixed(0)}%` : "—";
  $("cpu-temp").textContent = Number.isFinite(cpu.temperature_c) ? `${cpu.temperature_c.toFixed(0)}°C` : "temp —";
  $("cpu-detail").textContent = `load ${safe(cpu.load_1, "—")} · ${safe(cpu.model, "host")}`;
  $("ram-value").textContent = Number.isFinite(memory.usage_percent) ? `${memory.usage_percent.toFixed(0)}%` : "—";
  $("ram-total").textContent = fmtBytes(memory.total_bytes); $("ram-detail").textContent = `${fmtBytes(memory.used_bytes)} used · ${fmtBytes(memory.available_bytes)} free`;
  state.history.cpu.push(cpu.usage_percent || 0); state.history.ram.push(memory.usage_percent || 0);
  state.history.cpu = state.history.cpu.slice(-60); state.history.ram = state.history.ram.slice(-60);
  drawSparkline($("cpu-chart"), state.history.cpu, "#70a7ff"); drawSparkline($("ram-chart"), state.history.ram, "#a889ff");
  $("lan-address").textContent = safe(network.lan_ipv4); $("tail-state").textContent = network.tailscale_online ? "TS online" : "TS offline";
  $("network-detail").textContent = `TS ${safe(network.tailscale_ipv4)} · ${safe(network.interface)}`;
  setDot("phone-dot", network.phone_online ? "online" : "down"); $("phone-state").textContent = network.phone_online ? "GT Neo online" : "GT Neo offline";
  $("uptime-value").textContent = fmtUptime(summary.uptime_seconds); $("kernel-value").textContent = safe(summary.kernel);
  const backupOk = timers.backup?.result === "success" || timers.backup?.result === "done"; setDot("backup-dot", backupOk ? "good" : "warning");
  $("backup-state").textContent = backupOk ? "Backup OK" : `Backup ${safe(timers.backup?.result)}`;
  const alerts = payload.alerts || []; const strip = $("alert-strip");
  if (alerts.length) { strip.classList.remove("hidden"); strip.classList.toggle("bad", alerts.some((a) => a.level === "critical")); strip.textContent = alerts.slice(0, 3).map((a) => a.message).join(" · "); }
  else { strip.classList.add("hidden"); }
  renderDisks(payload.disks || []); renderApps(payload.apps || [], payload.containers || []);
  $("footer-version").textContent = `collector ${safe(payload.collector_version, "—")}`;
}
async function refresh() {
  try { const response = await fetch("/api/v1/status", {cache: "no-store"}); if (!response.ok) throw new Error(); render(await response.json()); }
  catch { setDot("overall-dot", "bad"); $("overall-label").textContent = "Dashboard offline"; }
}
async function refreshSession() {
  try { const data = await (await fetch("/api/v1/auth/session", {cache:"no-store"})).json(); state.authenticated = data.authenticated; state.csrf = data.csrf || null; }
  catch { state.authenticated = false; state.csrf = null; }
  $("auth-button").textContent = state.authenticated ? "Вийти" : "Увійти";
  $("auth-hint").textContent = state.authenticated ? "Керування активне. Сесія автоматично завершиться після бездіяльності." : "Статус доступний без входу. Керування потребує захищеної сесії.";
}
function openLogin() { $("login-error").textContent = ""; $("login-password").value = ""; $("login-dialog").showModal(); setTimeout(() => $("login-password").focus(), 50); }
async function logout() {
  await fetch("/api/v1/auth/logout", {method:"POST", headers:{"X-CSRF-Token": state.csrf || ""}}); state.authenticated = false; state.csrf = null; await refreshSession();
}
async function submitLogin(event) {
  event.preventDefault(); $("login-error").textContent = "";
  const response = await fetch("/api/v1/auth/login", {method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify({username:$("login-user").value,password:$("login-password").value})});
  const data = await response.json().catch(() => ({}));
  if (!response.ok) { $("login-error").textContent = data.detail || "Не вдалося увійти"; return; }
  state.authenticated = true; state.csrf = data.csrf; $("login-dialog").close(); await refreshSession();
}
function requestAction(action, target = null) {
  if (!state.authenticated) { openLogin(); return; }
  state.pendingAction = {action, target}; const power = action === "reboot" || action === "shutdown";
  const names = {backup:"Backup", "smart-short":"SMART short test", restart:`Restart ${target}`, reboot:"Reboot HPServer", shutdown:"Shutdown HPServer"};
  $("confirm-title").textContent = names[action]; $("confirm-copy").textContent = power ? "Ця дія перерве роботу всіх сервісів. Для підтвердження повторіть пароль і назву сервера." : "Дія запускається тільки для заздалегідь дозволеної цілі та буде записана в журнал.";
  $("confirm-text-wrap").classList.toggle("hidden", !power); $("confirm-password-wrap").classList.toggle("hidden", !power);
  $("confirm-text").value = ""; $("confirm-password").value = ""; $("confirm-error").textContent = ""; $("confirm-dialog").showModal();
}
async function submitAction(event) {
  event.preventDefault(); const pending = state.pendingAction; if (!pending) return;
  const power = pending.action === "reboot" || pending.action === "shutdown";
  const body = {target: pending.target, confirmation: power ? $("confirm-text").value : "CONFIRM", password: power ? $("confirm-password").value : null};
  const response = await fetch(`/api/v1/actions/${pending.action}`, {method:"POST", headers:{"Content-Type":"application/json","X-CSRF-Token":state.csrf || ""}, body:JSON.stringify(body)});
  const data = await response.json().catch(() => ({})); if (!response.ok) { $("confirm-error").textContent = data.detail || "Дію відхилено"; return; }
  $("confirm-dialog").close(); showJob(data.job_id); state.pendingAction = null;
}
async function showJob(jobId) {
  const toast = $("job-toast"); toast.classList.remove("hidden", "bad"); toast.textContent = "Дію поставлено в чергу…";
  for (let attempt = 0; attempt < 40; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    const response = await fetch(`/api/v1/jobs/${jobId}`); if (!response.ok) break; const job = await response.json();
    toast.textContent = job.state === "running" ? "Дія виконується…" : job.message || job.state;
    if (job.state === "succeeded" || job.state === "failed") { toast.classList.toggle("bad", job.state === "failed"); setTimeout(refresh, 1500); return; }
  }
  toast.classList.add("bad"); toast.textContent = "Не вдалося отримати фінальний стан job";
}
document.querySelectorAll("[data-close]").forEach((button) => button.addEventListener("click", () => button.closest("dialog").close()));
document.querySelectorAll("[data-action]").forEach((button) => button.addEventListener("click", () => requestAction(button.dataset.action, button.dataset.target || null)));
$("auth-button").addEventListener("click", () => state.authenticated ? logout() : openLogin());
$("restart-button").addEventListener("click", () => requestAction("restart", $("restart-target").value));
$("login-form").addEventListener("submit", submitLogin); $("confirm-form").addEventListener("submit", submitAction);
refresh(); refreshSession(); setInterval(refresh, 5000); setInterval(refreshSession, 60000);
