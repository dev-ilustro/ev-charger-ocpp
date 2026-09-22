const API = "/api";
let currentStartCpId = null;
let currentDetailCpId = null;
let currentDetailCp = null;
let currentUserRole = null;
let currentPricePerKwh = null;
let mockTopupEnabled = false;
let activeMockPayment = null;
let mockPaymentCountdownTimer = null;
let mockPaymentExpiresAt = null;
let lastChargePoints = [];

function fmtDate(value) {
  if (!value) return "-";
  const d = new Date(value + "Z".slice(value.endsWith("Z") ? 1 : 0));
  return d.toLocaleString("th-TH");
}

function fmtDuration(startTime) {
  if (!startTime) return "-";
  const start = new Date(startTime + "Z".slice(startTime.endsWith("Z") ? 1 : 0));
  const seconds = Math.max(0, Math.floor((Date.now() - start.getTime()) / 1000));
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  return h > 0 ? `${h} ชม. ${m} นาที` : `${m} นาที`;
}

async function fetchJSON(url, options = {}) {
  const { timeoutMs, ...fetchOptions } = options;
  const controller = timeoutMs ? new AbortController() : null;
  const timer = timeoutMs ? setTimeout(() => controller.abort(), timeoutMs) : null;

  let res;
  try {
    res = await fetch(url, {
      credentials: "same-origin",
      ...fetchOptions,
      ...(controller ? { signal: controller.signal } : {}),
    });
  } catch (err) {
    if (err.name === "AbortError") {
      throw new Error(`หมดเวลารอการตอบกลับ (เกิน ${Math.round(timeoutMs / 1000)} วินาที)`);
    }
    throw err;
  } finally {
    if (timer) clearTimeout(timer);
  }

  if (res.status === 401) {
    const next = window.location.pathname + window.location.search + window.location.hash;
    window.location.href = "/login.html?next=" + encodeURIComponent(next);
    throw new Error("กรุณาเข้าสู่ระบบ");
  }
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(err.detail || "เกิดข้อผิดพลาด");
  }
  return res.json();
}

// ---------- Screen navigation ----------
function pathForScreen(name) {
  if (name === "home") return "/app";
  if (name === "transactions") return "/transactions";
  if (name === "events") return "/events";
  if (name === "settings") return currentUserRole === "customer" ? "/wallet" : "/settings";
  if (name === "detail" && currentDetailCpId) return `/charger/${encodeURIComponent(currentDetailCpId)}`;
  return "/app";
}

function routeFromLocation() {
  const path = window.location.pathname.replace(/\/+$/, "") || "/";
  if (path === "/" || path === "/app" || path === "/home") return { screen: "home" };
  if (path === "/wallet" || path === "/settings") return { screen: "settings" };
  if (path === "/transactions") return { screen: "transactions" };
  if (path === "/events") return { screen: "events" };
  if (path.startsWith("/charger/") && path.length > "/charger/".length) {
    return { screen: "detail", chargePointId: decodeURIComponent(path.slice("/charger/".length)) };
  }
  return null;
}

function clearDetailState() {
  if (detailRefreshTimer) {
    clearInterval(detailRefreshTimer);
    detailRefreshTimer = null;
  }
  currentDetailCpId = null;
  currentDetailCp = null;
}

function applyRoute() {
  const route = routeFromLocation();
  if (!route) {
    clearDetailState();
    history.replaceState({}, "", "/app");
    switchScreen("home", { fromRoute: true });
    return;
  }
  if (route.screen === "home" && window.location.pathname === "/") {
    history.replaceState({}, "", "/app");
  }
  if (route.screen === "detail") {
    openDetailScreen(route.chargePointId, { fromRoute: true });
    return;
  }
  clearDetailState();
  switchScreen(route.screen, { fromRoute: true });
}

window.addEventListener("popstate", applyRoute);

function switchScreen(name, options = {}) {
  if (name !== "detail" && currentDetailCpId) {
    clearDetailState();
  }
  document.querySelectorAll(".screen").forEach((el) => el.classList.remove("active"));
  const target = document.getElementById(`screen-${name}`);
  if (target) target.classList.add("active");
  document.querySelectorAll(".bottom-nav-item").forEach((el) => {
    el.classList.toggle("active", el.dataset.screen === name);
  });
  if (!options.fromRoute) {
    const nextPath = pathForScreen(name);
    if (window.location.pathname !== nextPath) {
      history.pushState({}, "", nextPath);
    }
  }
  window.scrollTo(0, 0);
  if (name === "transactions") loadTransactionsScreen();
  if (name === "events") loadEventsScreen();
}

function renderChipGroup(containerId, options, activeValue, onSelect) {
  const el = document.getElementById(containerId);
  el.innerHTML = options
    .map(
      (opt) =>
        `<button type="button" class="chip ${opt.value === activeValue ? "active" : ""}" data-value="${opt.value}">${opt.label}</button>`
    )
    .join("");
  el.querySelectorAll(".chip").forEach((chip) => {
    chip.addEventListener("click", () => onSelect(chip.dataset.value));
  });
}

// ---------- Auth ----------
async function initAuth() {
  const me = await fetchJSON(`${API}/auth/me`);
  currentUserRole = me.role;

  document.getElementById("user-avatar").textContent = me.username.charAt(0).toUpperCase();
  document.getElementById("user-username").textContent = me.username;
  document.getElementById("user-role").textContent = me.role;
  document.getElementById("sidebar-user").style.display = "flex";
  document.getElementById("logout-btn").style.display = "";

  if (me.role === "admin" || me.role === "staff") {
    document.getElementById("admin-nav-section").style.display = "block";
    document.getElementById("nav-events-btn").style.display = "";
  }

  if (me.role === "customer") {
    document.getElementById("wallet-card").style.display = "block";
    document.getElementById("wallet-home-summary").style.display = "grid";
    renderWalletCard(me.wallet_balance, me.next_session_budget);
  }
}

document.getElementById("logout-btn").addEventListener("click", async () => {
  await fetch(`${API}/auth/logout`, { method: "POST", credentials: "same-origin" });
  window.location.href = "/login.html";
});

document.getElementById("refresh-btn").addEventListener("click", refreshAll);

// ---------- Wallet ----------
function renderWalletCard(walletBalance, nextSessionBudget) {
  const balanceText = `฿${(walletBalance ?? 0).toFixed(2)}`;
  document.getElementById("wallet-balance-value").textContent = balanceText;
  document.getElementById("wallet-home-chip-value").textContent = balanceText;
  document.getElementById("wallet-current-budget").textContent =
    nextSessionBudget != null
      ? `งบที่ตั้งไว้สำหรับรอบถัดไป: ฿${nextSessionBudget.toFixed(2)}`
      : "ยังไม่ได้ตั้งงบ (ชาร์จได้จนกว่าเงินใน wallet จะหมด)";
}

async function saveMyBudget() {
  const input = document.getElementById("wallet-budget-input");
  const budget = parseFloat(input.value);
  if (!budget || budget <= 0) {
    showToast("กรุณาใส่จำนวนเงินให้ถูกต้อง", "error");
    return;
  }
  try {
    const res = await fetchJSON(`${API}/me/budget`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ budget }),
    });
    document.getElementById("wallet-current-budget").textContent = `งบที่ตั้งไว้สำหรับรอบถัดไป: ฿${res.next_session_budget.toFixed(2)}`;
    showToast("บันทึกงบสำเร็จ", "success");
  } catch (err) {
    showToast("บันทึกไม่สำเร็จ: " + err.message, "error");
  }
}

async function clearMyBudget() {
  try {
    await fetchJSON(`${API}/me/budget`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ budget: null }),
    });
    document.getElementById("wallet-current-budget").textContent = "ยังไม่ได้ตั้งงบ (ชาร์จได้จนกว่าเงินใน wallet จะหมด)";
    document.getElementById("wallet-budget-input").value = "";
    showToast("ล้างงบสำเร็จ", "success");
  } catch (err) {
    showToast("ล้างงบไม่สำเร็จ: " + err.message, "error");
  }
}

async function topUpMyWallet() {
  const input = document.getElementById("wallet-topup-input");
  const amount = parseFloat(input.value);
  if (!amount || amount <= 0) {
    showToast("กรุณาใส่จำนวนเงินให้ถูกต้อง", "error");
    return;
  }
  try {
    const res = await fetchJSON(`${API}/me/wallet/topup`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ amount }),
    });
    document.getElementById("wallet-balance-value").textContent = `฿${res.wallet_balance.toFixed(2)}`;
    input.value = "";
    showToast("เติมเงิน (ทดสอบ) สำเร็จ", "success");
  } catch (err) {
    showToast("เติมเงินไม่สำเร็จ: " + err.message, "error");
  }
}

// ---------- Mock payment flow (replace the provider calls with Omise later) ----------
function setMockPaymentAmount(amount) {
  document.getElementById("mock-payment-amount").value = amount;
}

function setMockPaymentStep(step) {
  ["amount", "scan", "success"].forEach((name) => {
    document.getElementById(`mock-payment-step-${name}`).style.display = name === step ? "block" : "none";
  });
  const dialog = document.getElementById("mock-payment-dialog");
  dialog?.classList.toggle("mock-payment-scan-mode", step === "scan");
  dialog?.classList.toggle("mock-payment-success-mode", step === "success");
  const order = ["amount", "scan", "success"];
  document.querySelectorAll("[data-payment-step-indicator]").forEach((indicator) => {
    indicator.classList.toggle("active", order.indexOf(indicator.dataset.paymentStepIndicator) <= order.indexOf(step));
  });
}

function resetMockPaymentDialog() {
  if (mockPaymentCountdownTimer) {
    clearTimeout(mockPaymentCountdownTimer);
    mockPaymentCountdownTimer = null;
  }
  mockPaymentExpiresAt = null;
  activeMockPayment = null;
  document.getElementById("mock-payment-amount").value = "500";
  document.getElementById("mock-payment-amount-error").style.display = "none";
  document.getElementById("mock-payment-scan-error").style.display = "none";
  document.getElementById("mock-payment-scan-button").disabled = false;
  document.getElementById("mock-payment-scan-button").textContent = "จำลองชำระสำเร็จ";
  document.getElementById("mock-payment-countdown").textContent = "10:00";
  document.getElementById("mock-payment-qr-credit").textContent = "ยอดเข้า Wallet: ฿0.00";
  document.getElementById("mock-payment-scan-button").textContent = "จำลองสแกนสำเร็จ";
  setMockPaymentStep("amount");
  document.getElementById("mock-payment-scan-button").textContent = "Simulate payment success";
}

function openMockPaymentDialog() {
  const dialog = document.getElementById("mock-payment-dialog");
  if (!dialog) return;
  resetMockPaymentDialog();
  dialog.showModal();
}

function closeMockPaymentDialog() {
  const dialog = document.getElementById("mock-payment-dialog");
  if (dialog?.open) dialog.close();
}

function mockQrMatrix(reference, size = 29) {
  const seed = [...reference].reduce((sum, char) => sum + char.charCodeAt(0), 0);
  const inFinder = (x, y, ox, oy) => {
    const dx = x - ox;
    const dy = y - oy;
    if (dx < 0 || dx > 6 || dy < 0 || dy > 6) return null;
    return dx === 0 || dx === 6 || dy === 0 || dy === 6 || (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4);
  };
  return Array.from({ length: size }, (_, y) =>
    Array.from({ length: size }, (_, x) => {
      const finder = inFinder(x, y, 0, 0) ?? inFinder(x, y, size - 7, 0) ?? inFinder(x, y, 0, size - 7);
      return finder === null ? (x * 17 + y * 31 + seed) % 9 < 4 : finder;
    })
  );
}

function renderMockQr(reference) {
  const qr = document.getElementById("mock-payment-qr");
  if (!qr) return;
  qr.innerHTML = mockQrMatrix(reference)
    .flat()
    .map((on) => `<span class="${on ? "on" : ""}"></span>`)
    .join("");
}

function downloadMockQr() {
  if (!activeMockPayment) return;
  const matrix = mockQrMatrix(activeMockPayment.reference);
  const canvas = document.createElement("canvas");
  const padding = 24;
  const cellSize = 16;
  canvas.width = canvas.height = padding * 2 + matrix.length * cellSize;
  const context = canvas.getContext("2d");
  context.fillStyle = "#ffffff";
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.fillStyle = "#000000";
  matrix.forEach((row, y) => row.forEach((on, x) => {
    if (on) context.fillRect(padding + x * cellSize, padding + y * cellSize, cellSize, cellSize);
  }));
  const link = document.createElement("a");
  link.download = `promptpay-${activeMockPayment.reference}.png`;
  link.href = canvas.toDataURL("image/png");
  link.click();
}

function startMockPaymentCountdown() {
  if (mockPaymentCountdownTimer) clearTimeout(mockPaymentCountdownTimer);
  mockPaymentExpiresAt = Date.now() + 10 * 60 * 1000;
  const tick = () => {
    const remaining = Math.max(0, mockPaymentExpiresAt - Date.now());
    const seconds = Math.floor(remaining / 1000);
    const minutes = Math.floor(seconds / 60);
    const countdown = document.getElementById("mock-payment-countdown");
    const button = document.getElementById("mock-payment-scan-button");
    if (countdown) countdown.textContent = `${String(minutes).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
    if (remaining <= 0) {
      if (button) {
        button.disabled = true;
        button.textContent = "QR หมดอายุ";
      }
      return;
    }
    mockPaymentCountdownTimer = setTimeout(tick, 1000);
  };
  tick();
}

async function createMockPayment() {
  const amount = parseFloat(document.getElementById("mock-payment-amount").value);
  const errorEl = document.getElementById("mock-payment-amount-error");
  if (!amount || amount <= 0 || amount > 100000) {
    errorEl.textContent = "กรุณาระบุยอดเงินระหว่าง 0.01 ถึง 100,000 บาท";
    errorEl.style.display = "block";
    return;
  }

  try {
    const payment = await fetchJSON(`${API}/me/wallet/mock-payment`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ amount }),
    });
    activeMockPayment = payment;
    document.getElementById("mock-payment-qr-credit").textContent = `ยอดเข้า Wallet: ฿${payment.amount.toFixed(2)}`;
    document.getElementById("mock-payment-pending-amount").textContent = `฿${payment.amount.toFixed(2)}`;
    document.getElementById("mock-payment-reference").textContent = payment.reference;
    renderMockQr(payment.reference);
    setMockPaymentStep("scan");
    document.getElementById("mock-payment-pending-amount").textContent = `฿${payment.amount.toFixed(2)} THB`;
    startMockPaymentCountdown();
  } catch (err) {
    errorEl.textContent = `สร้างรายการไม่สำเร็จ: ${err.message}`;
    errorEl.style.display = "block";
  }
}

async function completeMockPayment() {
  if (!activeMockPayment) return;
  const button = document.getElementById("mock-payment-scan-button");
  const errorEl = document.getElementById("mock-payment-scan-error");
  button.disabled = true;
  button.textContent = "กำลังตรวจสอบ...";
  errorEl.style.display = "none";
  try {
    const result = await fetchJSON(`${API}/me/wallet/mock-payment/${activeMockPayment.id}/complete`, { method: "POST" });
    if (mockPaymentCountdownTimer) {
      clearTimeout(mockPaymentCountdownTimer);
      mockPaymentCountdownTimer = null;
    }
    document.getElementById("mock-payment-success-amount").textContent = `+ ฿${result.amount.toFixed(2)}`;
    document.getElementById("mock-payment-success-balance").textContent = `฿${result.wallet_balance.toFixed(2)}`;
    setMockPaymentStep("success");
    await refreshWalletCard();
  } catch (err) {
    button.disabled = false;
    button.textContent = "จำลองสแกนสำเร็จ";
    errorEl.textContent = `ตรวจสอบรายการไม่สำเร็จ: ${err.message}`;
    errorEl.style.display = "block";
  }
}

async function refreshWalletCard() {
  const me = await fetchJSON(`${API}/auth/me`);
  renderWalletCard(me.wallet_balance, me.next_session_budget);
}

// ---------- Toast notifications ----------
function showToast(message, kind = "info") {
  const container = document.getElementById("toast-container");
  const toast = document.createElement("div");
  toast.className = `toast toast-${kind}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => toast.remove(), 4000);
}

// ---------- หน้าแรก: overview + รายการเครื่องชาร์จ ----------
function statusClassFor(r) {
  if (!r.is_online) return "offline";
  if (r.status === "Charging") return "charging";
  if (r.status === "Faulted") return "faulted";
  if (r.status === "Preparing" || r.status === "Reserved") return "preparing";
  return "available";
}

function renderOverviewStrip() {
  const counts = { available: 0, charging: 0, faulted: 0, offline: 0 };
  lastChargePoints.forEach((r) => {
    const cls = statusClassFor(r);
    if (cls === "preparing") counts.available++;
    else counts[cls] = (counts[cls] || 0) + 1;
  });
  document.getElementById("overview-strip").innerHTML = `
    <div class="overview-chip"><span class="status-dot available"></span><strong>${counts.available}</strong> พร้อมใช้</div>
    <div class="overview-chip"><span class="status-dot charging pulse"></span><strong>${counts.charging}</strong> กำลังชาร์จ</div>
    <div class="overview-chip"><span class="status-dot faulted"></span><strong>${counts.faulted}</strong> ขัดข้อง</div>
    <div class="overview-chip"><span class="status-dot offline"></span><strong>${counts.offline}</strong> ออฟไลน์</div>
  `;
}

function updateStatusPill() {
  const total = lastChargePoints.length;
  const online = lastChargePoints.filter((r) => r.is_online).length;
  const pill = document.getElementById("status-pill");
  if (total === 0) {
    pill.textContent = "รอการเชื่อมต่อ...";
    pill.className = "badge offline";
  } else {
    pill.textContent = `${online}/${total} online`;
    pill.className = `badge ${online > 0 ? "online" : "offline"}`;
  }
}

function lockStatusBadges(r) {
  if (r.status === "Unavailable") {
    return `<span class="badge status-Faulted" title="เครื่องถูกสั่ง Inoperative ผ่าน ChangeAvailability">🔒 ล็อคเครื่อง (Inoperative)</span>`;
  }
  return "";
}

function deviceLiveStrip(r) {
  if (!r.active_transaction) return "";
  if (currentUserRole === "customer" && !r.active_transaction.is_mine) return "";
  const live = r.live || {};
  const energyKwhNum =
    live.energy_wh != null ? (live.energy_wh - r.active_transaction.meter_start) / 1000 : null;
  const energyKwh = energyKwhNum != null ? energyKwhNum.toFixed(2) : "-";
  const powerKw = live.power_w != null ? (live.power_w / 1000).toFixed(2) : "-";
  const budget = r.active_transaction.budget;

  let costHtml = "";
  if (energyKwhNum != null && currentPricePerKwh != null) {
    const costSoFar = energyKwhNum * currentPricePerKwh;
    costHtml = `<div><span class="metric-label">ค่าไฟ</span>฿${costSoFar.toFixed(2)}${budget != null ? ` / ${budget.toFixed(2)}` : ""}</div>`;
  }

  return `
    <div class="device-live-strip">
      <div><span class="metric-label">พลังงาน</span>${energyKwh} kWh</div>
      <div><span class="metric-label">เวลา</span>${fmtDuration(r.active_transaction.start_time)}</div>
      <div><span class="metric-label">แรงดัน</span>${live.voltage_v != null ? live.voltage_v + " V" : "-"}</div>
      <div><span class="metric-label">กระแส</span>${live.current_a != null ? live.current_a + " A" : "-"}</div>
      <div><span class="metric-label">กำลัง</span>${powerKw} kW</div>
      ${costHtml}
    </div>`;
}

function deviceCardHtml(r) {
  const isCustomer = currentUserRole === "customer";
  const hasActiveSession = !!r.active_transaction;
  const ownsActiveSession = !!(r.active_transaction && r.active_transaction.is_mine);
  const statusClass = statusClassFor(r);
  const pulse = statusClass === "charging" ? "pulse" : "";

  const stopBtn =
    hasActiveSession && (!isCustomer || ownsActiveSession)
      ? `<button class="danger" onclick="stopTransaction('${r.id}', ${r.active_transaction_id})" ${r.is_online ? "" : "disabled"}>หยุดชาร์จ</button>`
      : "";

  return `
    <div class="device-card" onclick="openDetailScreen('${r.id}')">
      <div class="device-card-header">
        <span class="status-dot ${statusClass} ${pulse}"></span>
        <span class="device-id">${r.id}</span>
        <span class="badge ${r.is_online ? "online" : "offline"}">${r.is_online ? "Online" : "Offline"}</span>
        <span class="badge status-${r.status || ""}">${r.status || "Unknown"}</span>
      </div>
      <div class="device-card-meta">
        <div>ยี่ห้อ/รุ่น <b>${r.vendor || "-"} / ${r.model || "-"}</b></div>
        <div>Heartbeat <b>${fmtDate(r.last_heartbeat)}</b></div>
      </div>
      ${deviceLiveStrip(r)}
      ${lockStatusBadges(r)}
      ${stopBtn ? `<div class="device-card-actions" onclick="event.stopPropagation()">${stopBtn}</div>` : ""}
    </div>`;
}

async function loadChargePoints() {
  const listEl = document.getElementById("cp-list");
  let rows;
  try {
    rows = await fetchJSON(`${API}/charge-points`);
  } catch (err) {
    listEl.innerHTML = `
      <div class="state-block">
        <div class="state-icon">⚠️</div>
        <div>โหลดข้อมูลไม่สำเร็จ: ${err.message}</div>
        <button class="secondary" style="margin-top:12px" onclick="loadChargePoints()">ลองใหม่</button>
      </div>`;
    return;
  }

  lastChargePoints = rows;
  renderOverviewStrip();
  updateStatusPill();

  if (rows.length === 0) {
    listEl.innerHTML = `
      <div class="state-block">
        <div class="state-icon">🔌</div>
        <div>ยังไม่มีเครื่องชาร์จเชื่อมต่อเข้ามา</div>
        <div>ตั้งค่าเครื่องชาร์จให้เชื่อมต่อมาที่</div>
        <code>wss://${window.location.host}/ocpp/&lt;ChargePointID&gt;</code>
      </div>`;
    return;
  }

  listEl.innerHTML = rows.map((r) => deviceCardHtml(r)).join("");

  // ถ้ากำลังเปิดหน้ารายละเอียดเครื่องนี้อยู่ อัพเดทปุ่ม action ให้ตรงสถานะล่าสุดด้วย
  if (currentDetailCpId) {
    const cp = rows.find((r) => r.id === currentDetailCpId);
    if (cp) updateDetailActionButtons(cp);
  }
}

async function startChargingSelf(cpId) {
  if (!confirm(`ยืนยันเริ่มชาร์จเครื่อง ${cpId}? ระบบจะหักเงินจาก wallet ของคุณอัตโนมัติเมื่อชาร์จเสร็จ`)) return;
  try {
    const res = await fetchJSON(`${API}/charge-points/${cpId}/self-start`, { method: "POST" });
    showToast(`ผลลัพธ์จากเครื่องชาร์จ: ${res.status}`, "success");
    refreshAll();
  } catch (err) {
    showToast("เริ่มชาร์จไม่สำเร็จ: " + err.message, "error");
  }
}

function openStartDialog(cpId) {
  currentStartCpId = cpId;
  document.getElementById("start-cp-id").textContent = cpId;
  document.getElementById("start-dialog").showModal();
}

document.getElementById("start-form").addEventListener("submit", async (e) => {
  const idTag = document.getElementById("start-id-tag").value.trim();
  const connectorId = parseInt(document.getElementById("start-connector-id").value, 10) || 1;
  const budgetValue = document.getElementById("start-budget").value;
  const budget = budgetValue ? parseFloat(budgetValue) : null;

  if (e.submitter && e.submitter.value === "confirm" && idTag) {
    try {
      const res = await fetchJSON(`${API}/charge-points/${currentStartCpId}/remote-start`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id_tag: idTag, connector_id: connectorId, budget }),
      });
      showToast(`ผลลัพธ์จากเครื่องชาร์จ: ${res.status}`, "success");
      refreshAll();
    } catch (err) {
      showToast("สั่งเริ่มชาร์จไม่สำเร็จ: " + err.message, "error");
    }
  }
});

async function stopTransaction(cpId, transactionId) {
  if (!transactionId) return;
  if (!confirm(`ยืนยันหยุดชาร์จเครื่อง ${cpId}?`)) return;
  try {
    const res = await fetchJSON(`${API}/charge-points/${cpId}/remote-stop`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ transaction_id: transactionId }),
    });
    showToast(`ผลลัพธ์จากเครื่องชาร์จ: ${res.status}`, "success");
    refreshAll();
  } catch (err) {
    showToast("หยุดชาร์จไม่สำเร็จ: " + err.message, "error");
  }
}

async function unlockConnector(cpId) {
  try {
    const res = await fetchJSON(`${API}/charge-points/${cpId}/unlock`, { method: "POST" });
    showToast(`ผลลัพธ์จากเครื่องชาร์จ: ${res.status}`, "success");
  } catch (err) {
    showToast("ปลดล็อคไม่สำเร็จ: " + err.message, "error");
  }
}

async function resetCp(cpId, type = "Soft") {
  const label = type === "Hard" ? "Reboot (Hard Reset)" : "Reset (Soft)";
  const warning =
    type === "Hard"
      ? " เครื่องจะรีบูตทั้งตัว การชาร์จที่กำลังทำอยู่ (ถ้ามี) จะถูกตัดทันที"
      : " เครื่องจะ restart เฉพาะ software (ตัดการชาร์จที่ทำอยู่ก่อนแล้วค่อย restart)";
  if (!confirm(`ยืนยัน ${label} เครื่อง ${cpId}?${warning}`)) return;
  try {
    const res = await fetchJSON(`${API}/charge-points/${cpId}/reset`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ type }),
    });
    showToast(`ผลลัพธ์จากเครื่องชาร์จ: ${res.status}`, "success");
  } catch (err) {
    showToast(`${label} ไม่สำเร็จ: ` + err.message, "error");
  }
}

// ---------- รายละเอียดเครื่องชาร์จ ----------
let detailRefreshTimer = null;

function detailStartCharging() {
  if (currentUserRole === "customer") {
    startChargingSelf(currentDetailCpId);
  } else {
    openStartDialog(currentDetailCpId);
  }
}

function detailStopCharging() {
  if (!currentDetailCp || !currentDetailCp.active_transaction) return;
  stopTransaction(currentDetailCpId, currentDetailCp.active_transaction.id);
}

function updateDetailActionButtons(cp) {
  const isCustomer = currentUserRole === "customer";
  const hasActive = !!cp.active_transaction;
  const ownsActive = hasActive && (!isCustomer || cp.active_transaction.is_mine);

  const startBtn = document.getElementById("detail-start-btn");
  const stopBtn = document.getElementById("detail-stop-btn");
  const unlockBtn = document.getElementById("detail-unlock-btn");
  const resetBtn = document.getElementById("detail-reset-btn");

  if (isCustomer) {
    startBtn.style.display = hasActive ? "none" : "";
    stopBtn.style.display = ownsActive ? "" : "none";
    unlockBtn.style.display = "none";
    resetBtn.style.display = "none";
  } else {
    startBtn.style.display = "";
    stopBtn.style.display = hasActive ? "" : "none";
    unlockBtn.style.display = "";
    resetBtn.style.display = "";
  }
  startBtn.disabled = !cp.is_online;
  stopBtn.disabled = !cp.is_online;
  unlockBtn.disabled = !cp.is_online || cp.status === "Charging";
  resetBtn.disabled = !cp.is_online;
}

function renderLiveChargingInfo(cp) {
  const section = document.getElementById("live-charging-section");
  const grid = document.getElementById("live-charging-grid");

  if (!cp.active_transaction) {
    section.style.display = "none";
    return;
  }
  section.style.display = "block";

  const live = cp.live || {};
  const sessionEnergyKwh =
    live.energy_wh != null ? ((live.energy_wh - cp.active_transaction.meter_start) / 1000).toFixed(2) : "-";

  grid.innerHTML = `
    <div class="stat-card blue">
      <div class="stat-label">🔋 พลังงาน (kWh)</div>
      <div class="stat-value">${sessionEnergyKwh}</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">⏱️ เวลาที่ชาร์จ</div>
      <div class="stat-value">${fmtDuration(cp.active_transaction.start_time)}</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">Voltage</div>
      <div class="stat-value">${live.voltage_v != null ? live.voltage_v + " V" : "-"}</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">Current</div>
      <div class="stat-value">${live.current_a != null ? live.current_a + " A" : "-"}</div>
    </div>
    <div class="stat-card green">
      <div class="stat-label">Power</div>
      <div class="stat-value">${live.power_w != null ? (live.power_w / 1000).toFixed(2) + " kW" : "-"}</div>
    </div>
    <div class="stat-card">
      <div class="stat-label">Temperature</div>
      <div class="stat-value">${live.temperature_c != null ? live.temperature_c + " °C" : "-"}</div>
    </div>
  `;
}

async function refreshDetailInfoGrid(cpId) {
  let cp;
  try {
    cp = await fetchJSON(`${API}/charge-points/${cpId}`);
  } catch (err) {
    document.getElementById("detail-info-grid").innerHTML = `เกิดข้อผิดพลาด: ${err.message}`;
    return null;
  }

  currentDetailCp = cp;
  document.getElementById("detail-status-badges").innerHTML = `
    <span class="badge ${cp.is_online ? "online" : "offline"}">${cp.is_online ? "Online" : "Offline"}</span>
    <span class="badge status-${cp.status || ""}">${cp.status || "Unknown"}</span>
  `;
  document.getElementById("detail-info-grid").innerHTML = `
    <div><span class="label">ยี่ห้อ / รุ่น</span>${cp.vendor || "-"} / ${cp.model || "-"}</div>
    <div><span class="label">Firmware</span>${cp.firmware_version || "-"}</div>
    <div><span class="label">Connector</span>${cp.connector_id ?? "-"} ${cp.error_code ? `(${cp.error_code})` : ""}</div>
    <div><span class="label">Heartbeat ล่าสุด</span>${fmtDate(cp.last_heartbeat)}</div>
    <div><span class="label">พบเห็นล่าสุด</span>${fmtDate(cp.last_seen)}</div>
  `;
  renderLiveChargingInfo(cp);
  updateDetailActionButtons(cp);
  return cp;
}

async function openDetailScreen(cpId, options = {}) {
  currentDetailCpId = cpId;
  currentDetailCp = null;
  document.getElementById("detail-cp-id").textContent = cpId;
  document.getElementById("detail-status-badges").innerHTML = "";
  document.getElementById("detail-info-grid").innerHTML = "กำลังโหลด...";
  document.getElementById("live-charging-section").style.display = "none";

  const isCustomer = currentUserRole === "customer";
  document.querySelectorAll(".admin-only-section").forEach((el) => {
    el.style.display = isCustomer ? "none" : "";
  });

  const configStatus = document.getElementById("config-status");
  const configTable = document.getElementById("config-table");
  configTable.style.display = "none";
  configStatus.style.display = "none";
  document.getElementById("config-body").innerHTML = "";
  document.getElementById("availability-status").style.display = "none";

  switchScreen("detail", options);

  if (detailRefreshTimer) clearInterval(detailRefreshTimer);
  detailRefreshTimer = setInterval(() => refreshDetailInfoGrid(cpId), 5000);

  const cp = await refreshDetailInfoGrid(cpId);
  if (!cp) return;

  const loadBtn = document.getElementById("config-load-btn");
  const opBtn = document.getElementById("availability-operative-btn");
  const inopBtn = document.getElementById("availability-inoperative-btn");
  if (currentUserRole !== "admin") {
    loadBtn.disabled = true;
    opBtn.disabled = true;
    inopBtn.disabled = true;
    configStatus.style.display = "block";
    configStatus.className = "form-msg";
    configStatus.textContent = "ต้องเป็น Admin เท่านั้นจึงจะดู/แก้ไข OCPP Configuration ได้";
  } else if (!cp.is_online) {
    loadBtn.disabled = true;
    opBtn.disabled = true;
    inopBtn.disabled = true;
    configStatus.style.display = "block";
    configStatus.className = "form-msg";
    configStatus.textContent = "เครื่องชาร์จ Offline อยู่ ไม่สามารถอ่าน/แก้ไข Configuration ได้";
  } else {
    loadBtn.disabled = false;
    opBtn.disabled = false;
    inopBtn.disabled = false;
  }

  if (cp.status === "Charging") {
    opBtn.disabled = true;
    inopBtn.disabled = true;
    const availabilityStatus = document.getElementById("availability-status");
    availabilityStatus.style.display = "block";
    availabilityStatus.className = "form-error";
    availabilityStatus.textContent =
      "กำลังชาร์จอยู่ ห้ามสั่งล็อค/ปลดล็อคเครื่องหรือปลดล็อคหัวชาร์จตอนนี้ (จะทำให้เครื่องหลุด session แล้วชาร์จไม่เข้าอีก) กรุณารอให้ชาร์จเสร็จก่อน";
  }
}

function closeDetailScreen() {
  clearDetailState();
  switchScreen("home");
}

async function setAvailability(type) {
  const label = type === "Operative" ? "ปลดล็อค (Operative)" : "ล็อค (Inoperative)";
  if (!confirm(`ยืนยันบังคับสถานะเครื่อง ${currentDetailCpId} เป็น ${label}?`)) return;
  const statusEl = document.getElementById("availability-status");
  statusEl.style.display = "block";
  statusEl.className = "form-msg";
  statusEl.textContent = "กำลังส่งคำสั่ง...";
  try {
    const res = await fetchJSON(`${API}/charge-points/${currentDetailCpId}/change-availability`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ connector_id: 1, type }),
      timeoutMs: 35000,
    });
    statusEl.textContent = `ผลลัพธ์: ${res.status} (สถานะที่แสดงจะอัพเดทเมื่อเครื่องส่ง StatusNotification เข้ามา อาจใช้เวลาสักครู่)`;
    refreshAll();
    setTimeout(() => {
      if (currentDetailCpId) refreshDetailInfoGrid(currentDetailCpId);
    }, 2000);
  } catch (err) {
    statusEl.textContent = "สั่งงานไม่สำเร็จ: " + err.message;
  }
}

async function disableAutoUnlock(cpId) {
  const statusEl = document.getElementById("auto-unlock-status");
  statusEl.style.display = "block";
  statusEl.className = "form-msg";
  statusEl.textContent = "กำลังส่งคำสั่งไปยังเครื่องชาร์จ...";
  try {
    const res = await fetchJSON(`${API}/charge-points/${cpId}/configuration`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: "UnlockConnectorOnEVSideDisconnect", value: "false" }),
      timeoutMs: 35000,
    });
    if (res.status === "Accepted" || res.status === "RebootRequired") {
      statusEl.className = "form-msg";
      statusEl.textContent =
        res.status === "RebootRequired"
          ? "ตั้งค่าสำเร็จ แต่เครื่องต้อง Reboot ก่อนถึงจะมีผล"
          : "ปิด Auto-unlock สำเร็จ เครื่องจะรอคำสั่งปลดล็อคจาก Server เท่านั้น";
    } else {
      statusEl.className = "form-error";
      statusEl.textContent =
        res.status === "NotSupported"
          ? "เครื่องชาร์จรุ่นนี้ไม่รองรับ configuration key นี้ ต้องเช็ค setting ที่ตัวเครื่องเอง"
          : `เครื่องปฏิเสธการตั้งค่า (${res.status})`;
    }
  } catch (err) {
    statusEl.className = "form-error";
    statusEl.textContent = "ตั้งค่าไม่สำเร็จ: " + err.message;
  }
}

async function loadConfiguration() {
  const configStatus = document.getElementById("config-status");
  const configTable = document.getElementById("config-table");
  configStatus.style.display = "block";
  configStatus.className = "form-msg";
  configStatus.textContent = "กำลังโหลดค่า configuration จากเครื่องชาร์จ...";

  try {
    const data = await fetchJSON(`${API}/charge-points/${currentDetailCpId}/configuration`, {
      timeoutMs: 35000,
    });
    const rows = data.configuration_key || [];

    if (rows.length === 0) {
      configStatus.textContent = "เครื่องชาร์จไม่คืนค่า configuration ใดๆ กลับมา";
      configTable.style.display = "none";
      return;
    }

    configStatus.style.display = "none";
    configTable.style.display = "";
    document.getElementById("config-body").innerHTML = rows
      .map(
        (row, idx) => `
      <tr>
        <td>${row.key}</td>
        <td><input type="text" id="config-value-${idx}" value="${(row.value ?? "").replace(/"/g, "&quot;")}" ${row.readonly ? "disabled" : ""} /></td>
        <td>${row.readonly ? '<span class="badge offline">readonly</span>' : ""}</td>
        <td>${row.readonly ? "" : `<button onclick="saveConfigValue('${row.key}', ${idx})">Save</button>`}</td>
      </tr>`
      )
      .join("");
  } catch (err) {
    configTable.style.display = "none";
    configStatus.innerHTML = "";
    configStatus.append("โหลด configuration ไม่สำเร็จ: " + err.message + " ");
    const retryBtn = document.createElement("button");
    retryBtn.textContent = "ลองใหม่";
    retryBtn.onclick = loadConfiguration;
    configStatus.appendChild(retryBtn);
  }
}

async function saveConfigValue(key, idx) {
  const input = document.getElementById(`config-value-${idx}`);
  const value = input.value;
  try {
    const res = await fetchJSON(`${API}/charge-points/${currentDetailCpId}/configuration`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key, value }),
      timeoutMs: 35000,
    });
    const kindByStatus = {
      Accepted: "success",
      RebootRequired: "warning",
      Rejected: "error",
      NotSupported: "error",
    };
    showToast(`${key}: ${res.status}`, kindByStatus[res.status] || "info");
  } catch (err) {
    showToast(`บันทึก ${key} ไม่สำเร็จ: ${err.message}`, "error");
  }
}

// ---------- ประวัติการชาร์จ ----------
let txnFilterCpId = "";
let txnFilterRange = "7d";
let lastTransactionsFull = [];

function txnBadgeClass(status) {
  if (status === "Active") return "status-Charging";
  if (status === "Cancelled") return "offline";
  return "online";
}

function fmtTxnDuration(t) {
  if (!t.start_time) return "-";
  const start = new Date(t.start_time + "Z".slice(t.start_time.endsWith("Z") ? 1 : 0));
  const end = t.stop_time ? new Date(t.stop_time + "Z".slice(t.stop_time.endsWith("Z") ? 1 : 0)) : new Date();
  const seconds = Math.max(0, Math.floor((end.getTime() - start.getTime()) / 1000));
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h} ชม. ${m} นาที`;
  if (m > 0) return `${m} นาที ${s} วิ`;
  return `${s} วิ`;
}

function txnAdminActions(t) {
  if (currentUserRole !== "admin") return "";
  const stopBtn =
    t.status === "Active"
      ? `<button class="secondary" onclick="forceStopTransaction(${t.id})">หยุด (Force)</button>`
      : "";
  return `<div class="device-card-actions" style="margin-top:8px">${stopBtn}<button class="danger" onclick="deleteTransaction(${t.id})">ลบ</button></div>`;
}

function rangeStartDate(range) {
  const now = new Date();
  if (range === "today") {
    const d = new Date(now);
    d.setHours(0, 0, 0, 0);
    return d;
  }
  if (range === "7d") return new Date(now.getTime() - 7 * 24 * 3600 * 1000);
  if (range === "30d") return new Date(now.getTime() - 30 * 24 * 3600 * 1000);
  return null;
}

function renderTxnChips() {
  const cpOptions = [{ value: "", label: "ทุกเครื่อง" }, ...lastChargePoints.map((r) => ({ value: r.id, label: r.id }))];
  renderChipGroup("txn-cp-chips", cpOptions, txnFilterCpId, (val) => {
    txnFilterCpId = val;
    loadTransactionsScreen();
  });
  const rangeOptions = [
    { value: "today", label: "วันนี้" },
    { value: "7d", label: "7 วัน" },
    { value: "30d", label: "30 วัน" },
    { value: "all", label: "ทั้งหมด" },
  ];
  renderChipGroup("txn-range-chips", rangeOptions, txnFilterRange, (val) => {
    txnFilterRange = val;
    renderTxnChips();
    renderTransactionsList();
  });
}

function renderTransactionsList() {
  const listEl = document.getElementById("txn-list");
  const start = rangeStartDate(txnFilterRange);
  const rows = lastTransactionsFull.filter((t) => {
    if (!start || !t.start_time) return true;
    const st = new Date(t.start_time + "Z".slice(t.start_time.endsWith("Z") ? 1 : 0));
    return st >= start;
  });

  if (rows.length === 0) {
    listEl.innerHTML = `<div class="state-block"><div class="state-icon">📭</div><div>ไม่มี transaction ในช่วงที่เลือก</div></div>`;
    return;
  }

  listEl.innerHTML = rows
    .map(
      (t) => `
    <div class="timeline-item">
      <div class="timeline-item-top">
        <strong>${t.charge_point_id}</strong>
        <span class="badge ${txnBadgeClass(t.status)}">${t.status}</span>
      </div>
      <div class="timeline-item-meta">
        <span>ID Tag: <span class="mono">${t.id_tag}</span></span>
        <span>ผู้ใช้: ${t.user_name || "-"}</span>
        <span>เริ่ม: ${fmtDate(t.start_time)}</span>
        <span>สิ้นสุด: ${fmtDate(t.stop_time)}</span>
        <span>ระยะเวลา: ${fmtTxnDuration(t)}</span>
        <span>พลังงาน: <span class="mono">${t.energy_kwh ?? "-"}</span> kWh</span>
        ${t.amount_due != null ? `<span>หักจาก Wallet: <span class="mono">฿${t.amount_due}</span></span>` : ""}
      </div>
      ${txnAdminActions(t)}
    </div>`
    )
    .join("");
}

async function loadTransactionsScreen() {
  const listEl = document.getElementById("txn-list");
  renderTxnChips();
  try {
    const params = new URLSearchParams({ limit: "200" });
    if (txnFilterCpId) params.set("charge_point_id", txnFilterCpId);
    const rows = await fetchJSON(`${API}/transactions?${params}`);
    lastTransactionsFull = rows;
    renderTransactionsList();
  } catch (err) {
    listEl.innerHTML = `
      <div class="state-block">
        <div class="state-icon">⚠️</div>
        <div>โหลดข้อมูลไม่สำเร็จ: ${err.message}</div>
        <button class="secondary" style="margin-top:12px" onclick="loadTransactionsScreen()">ลองใหม่</button>
      </div>`;
  }
}

async function forceStopTransaction(id) {
  if (!confirm(`ยืนยันปิด transaction #${id} แบบ Force? (ใช้เมื่อ transaction ค้างสถานะ Active โดยไม่มีเครื่องชาร์จเชื่อมต่ออยู่แล้ว ข้อมูลพลังงานจะไม่ถูกบันทึกเพราะไม่มี meter reading จริง)`)) return;
  try {
    await fetchJSON(`${API}/admin/transactions/${id}/force-stop`, { method: "POST" });
    loadTransactionsScreen();
  } catch (err) {
    showToast("Force stop ไม่สำเร็จ: " + err.message, "error");
  }
}

async function deleteTransaction(id) {
  if (!confirm(`ยืนยันลบ transaction #${id}? ลบแล้วกู้คืนไม่ได้`)) return;
  try {
    await fetchJSON(`${API}/admin/transactions/${id}`, { method: "DELETE" });
    loadTransactionsScreen();
  } catch (err) {
    showToast("ลบไม่สำเร็จ: " + err.message, "error");
  }
}

// ---------- Log เหตุการณ์ ----------
let eventsFilterCpId = "";
let lastEventsFull = [];

function eventBadgeClass(action) {
  if (action.includes("Stop")) return "offline";
  if (action.includes("Start") || action === "StatusNotification") return "status-Charging";
  if (action.includes("Unlock") || action.includes("Configuration") || action.includes("Availability")) return "online";
  return "offline";
}

function renderEventsChips() {
  const cpOptions = [{ value: "", label: "ทุกเครื่อง" }, ...lastChargePoints.map((r) => ({ value: r.id, label: r.id }))];
  renderChipGroup("events-cp-chips", cpOptions, eventsFilterCpId, (val) => {
    eventsFilterCpId = val;
    loadEventsScreen();
  });
}

function renderEventsList() {
  const listEl = document.getElementById("events-list");
  if (lastEventsFull.length === 0) {
    listEl.innerHTML = `<div class="state-block"><div class="state-icon">📭</div><div>ยังไม่มี event</div></div>`;
    return;
  }
  listEl.innerHTML = lastEventsFull
    .map((e) => {
      let pretty = e.payload || "";
      try {
        pretty = JSON.stringify(JSON.parse(e.payload), null, 2);
      } catch (err) {
        // ไม่ใช่ JSON ที่ parse ได้ ก็แสดงดิบๆ ไป
      }
      return `
    <div class="timeline-item">
      <div class="timeline-item-top">
        <strong>${e.charge_point_id}</strong>
        <span class="badge ${eventBadgeClass(e.action)}">${e.action}</span>
      </div>
      <div class="timeline-item-meta"><span>${fmtDate(e.timestamp)}</span></div>
      <details class="payload-details">
        <summary>ดู payload</summary>
        <pre>${pretty.replace(/</g, "&lt;")}</pre>
      </details>
    </div>`;
    })
    .join("");
}

async function loadEventsScreen() {
  const listEl = document.getElementById("events-list");
  renderEventsChips();
  try {
    const params = new URLSearchParams({ limit: "100" });
    if (eventsFilterCpId) params.set("charge_point_id", eventsFilterCpId);
    const rows = await fetchJSON(`${API}/events?${params}`);
    lastEventsFull = rows;
    renderEventsList();
  } catch (err) {
    listEl.innerHTML = `
      <div class="state-block">
        <div class="state-icon">⚠️</div>
        <div>โหลดข้อมูลไม่สำเร็จ: ${err.message}</div>
        <button class="secondary" style="margin-top:12px" onclick="loadEventsScreen()">ลองใหม่</button>
      </div>`;
  }
}

// ---------- Refresh loop ----------
async function refreshAll() {
  try {
    const tasks = [loadChargePoints()];
    if (currentUserRole === "customer") tasks.push(refreshWalletCard());
    await Promise.all(tasks);
  } catch (err) {
    document.getElementById("status-pill").textContent = "เชื่อมต่อ API ไม่ได้";
  }
}

async function loadVersionBadge() {
  try {
    const s = await fetchJSON(`${API}/settings`);
    if (s.latest_version) {
      document.getElementById("version-badge").textContent = s.latest_version;
    }
    currentPricePerKwh = s.price_per_kwh;
    mockTopupEnabled = !!s.allow_customer_mock_topup;
    if (currentUserRole === "customer") {
      document.getElementById("wallet-topup-section").style.display = mockTopupEnabled ? "block" : "none";
      document.querySelectorAll(".wallet-home-action").forEach((el) => {
        el.style.display = mockTopupEnabled ? "" : "none";
      });
    }
  } catch (err) {
    // เก็บค่า default ในหน้า HTML ไว้ถ้าโหลดไม่สำเร็จ
  }
}

(async function start() {
  await initAuth();
  applyRoute();
  loadVersionBadge();
  refreshAll();
  setInterval(refreshAll, 5000);
})();
