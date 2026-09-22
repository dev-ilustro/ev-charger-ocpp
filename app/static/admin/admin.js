const API = "/api";
let lastUsers = [];

const TAB_TITLES = {
  "wallet-payments-tab": "Wallet Logs",
  "settings-tab": "ตั้งค่าระบบ",
  "changelog-tab": "Change Log",
  "users-tab": "ผู้ใช้งาน",
  "cards-tab": "RFID Cards",
  "charge-points-tab": "เครื่องชาร์จ",
  "card-taps-tab": "ประวัติแตะบัตร",
};

async function fetchJSON(url, options) {
  const res = await fetch(url, { credentials: "same-origin", ...options });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: res.statusText }));
    throw new Error(err.detail || "เกิดข้อผิดพลาด");
  }
  if (res.status === 204) return null;
  return res.json();
}

function fmtDate(value) {
  if (!value) return "-";
  const d = new Date(value + "Z".slice(value.endsWith("Z") ? 1 : 0));
  return d.toLocaleString("th-TH");
}

async function loadVersionBadge() {
  try {
    const s = await fetchJSON(`${API}/settings`);
    if (s.latest_version) {
      document.getElementById("version-badge").textContent = s.latest_version;
      document.getElementById("footer-version").textContent = s.latest_version;
    }
  } catch (err) {
    // เก็บค่า default ในหน้า HTML ไว้ถ้าโหลดไม่สำเร็จ
  }
}

async function init() {
  loadVersionBadge();

  let me;
  try {
    me = await fetchJSON(`${API}/auth/me`);
  } catch (err) {
    window.location.href = "/login.html?next=" + encodeURIComponent(window.location.pathname);
    return;
  }

  document.getElementById("user-avatar").textContent = me.username.charAt(0).toUpperCase();
  document.getElementById("user-username").textContent = me.username;
  document.getElementById("user-role").textContent = me.role;
  document.getElementById("sidebar-user").style.display = "flex";
  document.getElementById("logout-btn").style.display = "flex";

  if (me.role !== "admin") {
    document.getElementById("denied-section").style.display = "block";
    return;
  }

  document.getElementById("admin-section").style.display = "block";

  const requestedTab = new URLSearchParams(window.location.search).get("tab");
  if (requestedTab && TAB_TITLES[requestedTab]) {
    selectTab(requestedTab);
  }

  loadSettings();
  loadChangelog();
  await loadUsers();
  loadCards();
  loadBackups();
  loadChargePointsAdmin();
  loadCardTaps();
  loadWalletPayments();
}

document.getElementById("logout-btn").addEventListener("click", async () => {
  await fetchJSON(`${API}/auth/logout`, { method: "POST" });
  window.location.href = "/login.html";
});

// ---------- Mobile sidebar toggle ----------
const sidebarEl = document.getElementById("sidebar");
const sidebarOverlayEl = document.getElementById("sidebar-overlay");

function closeSidebar() {
  sidebarEl.classList.remove("open");
  sidebarOverlayEl.classList.remove("open");
}

document.getElementById("menu-toggle").addEventListener("click", () => {
  sidebarEl.classList.add("open");
  sidebarOverlayEl.classList.add("open");
});

sidebarOverlayEl.addEventListener("click", closeSidebar);

// ---------- Sidebar tab nav ----------
function selectTab(tabId) {
  document.querySelectorAll(".nav-item[data-tab]").forEach((b) => b.classList.remove("active"));
  document.querySelectorAll(".tab-panel").forEach((p) => (p.style.display = "none"));

  const btn = document.querySelector(`.nav-item[data-tab="${tabId}"]`);
  if (btn) btn.classList.add("active");
  const panel = document.getElementById(tabId);
  if (panel) panel.style.display = "block";

  document.getElementById("page-title").textContent = TAB_TITLES[tabId] || "Admin";
  closeSidebar();
}

document.querySelectorAll(".nav-item[data-tab]").forEach((btn) => {
  btn.addEventListener("click", () => selectTab(btn.dataset.tab));
});

// ---------- Settings ----------
async function loadSettings() {
  const s = await fetchJSON(`${API}/admin/settings`);
  document.getElementById("setting-system-name").value = s.system_name;
  document.getElementById("setting-heartbeat").value = s.heartbeat_interval;
  document.getElementById("setting-auto-accept").checked = s.auto_accept_authorize;
  document.getElementById("setting-lock-until-authorized").checked = s.lock_connector_until_authorized;
  document.getElementById("setting-price-per-kwh").value = s.price_per_kwh;
  document.getElementById("setting-allow-mock-topup").checked = s.allow_customer_mock_topup;
}

document.getElementById("settings-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const msgEl = document.getElementById("settings-msg");
  try {
    await fetchJSON(`${API}/admin/settings`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        system_name: document.getElementById("setting-system-name").value.trim(),
        heartbeat_interval: parseInt(document.getElementById("setting-heartbeat").value, 10),
        auto_accept_authorize: document.getElementById("setting-auto-accept").checked,
        lock_connector_until_authorized: document.getElementById("setting-lock-until-authorized").checked,
        price_per_kwh: parseFloat(document.getElementById("setting-price-per-kwh").value),
        allow_customer_mock_topup: document.getElementById("setting-allow-mock-topup").checked,
      }),
    });
    msgEl.textContent = "บันทึกสำเร็จ";
    msgEl.style.display = "block";
    setTimeout(() => (msgEl.style.display = "none"), 2000);
  } catch (err) {
    alert("บันทึกไม่สำเร็จ: " + err.message);
  }
});

// ---------- Changelog ----------
async function loadChangelog() {
  const rows = await fetchJSON(`${API}/admin/changelog`);
  const tbody = document.getElementById("changelog-body");

  if (rows.length === 0) {
    tbody.innerHTML = `<tr><td colspan="4">ยังไม่มีรายการ</td></tr>`;
    return;
  }

  tbody.innerHTML = rows
    .map(
      (r) => `
    <tr>
      <td><strong>${r.version}</strong></td>
      <td>${r.description}</td>
      <td>${fmtDate(r.created_at)}</td>
      <td><button class="danger" onclick="deleteChangelog(${r.id})">ลบ</button></td>
    </tr>`
    )
    .join("");
}

document.getElementById("changelog-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const version = document.getElementById("changelog-version").value.trim();
  const description = document.getElementById("changelog-description").value.trim();

  try {
    await fetchJSON(`${API}/admin/changelog`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ version, description }),
    });
    document.getElementById("changelog-form").reset();
    loadChangelog();
  } catch (err) {
    alert("เพิ่มไม่สำเร็จ: " + err.message);
  }
});

async function deleteChangelog(id) {
  if (!confirm("ยืนยันลบรายการนี้?")) return;
  try {
    await fetchJSON(`${API}/admin/changelog/${id}`, { method: "DELETE" });
    loadChangelog();
  } catch (err) {
    alert("ลบไม่สำเร็จ: " + err.message);
  }
}

// ---------- Users ----------
const USER_AVATAR_COLORS = ["#2563eb", "#7c3aed", "#db2777", "#d97706", "#16a34a", "#0891b2"];
let currentEditUserId = null;

function avatarColor(username) {
  let hash = 0;
  for (let i = 0; i < username.length; i++) hash = username.charCodeAt(i) + ((hash << 5) - hash);
  return USER_AVATAR_COLORS[Math.abs(hash) % USER_AVATAR_COLORS.length];
}

async function loadUsers() {
  const rows = await fetchJSON(`${API}/admin/users`);
  lastUsers = rows;
  renderUsersTable();
}

function renderUsersTable() {
  const tbody = document.getElementById("users-body");
  const search = document.getElementById("users-search").value.trim().toLowerCase();
  const role = document.getElementById("users-role-filter").value;

  document.getElementById("users-count").textContent = `${lastUsers.length} ผู้ใช้งานทั้งหมด`;

  const rows = lastUsers.filter((u) => {
    if (role && u.role !== role) return false;
    if (!search) return true;
    const hay = `${u.username} ${u.full_name || ""} ${u.email || ""}`.toLowerCase();
    return hay.includes(search);
  });

  if (rows.length === 0) {
    tbody.innerHTML = `<tr><td colspan="6">ไม่พบผู้ใช้งาน</td></tr>`;
    return;
  }

  tbody.innerHTML = rows
    .map((u) => {
      const initial = (u.full_name || u.username).charAt(0).toUpperCase();
      const contact = [u.email, u.phone].filter(Boolean).join("<br>") || "-";
      return `
    <tr>
      <td>
        <div class="user-cell">
          <div class="table-avatar" style="background:${avatarColor(u.username)}">${initial}</div>
          <div>
            <div class="user-cell-name">${u.full_name || u.username}</div>
            <div class="user-cell-handle">@${u.username}</div>
          </div>
        </div>
      </td>
      <td>${contact}</td>
      <td><span class="badge role-${u.role}">${u.role}</span></td>
      <td><span class="badge ${u.is_active ? "online" : "offline"}">${u.is_active ? "เปิดใช้งาน" : "ปิดใช้งาน"}</span></td>
      <td>฿${(u.wallet_balance ?? 0).toFixed(2)}</td>
      <td>
        <div class="row-actions">
          <button type="button" class="icon-btn-sm" title="เติมเงิน" onclick="openTopupDialog(${u.id})">💰</button>
          <button type="button" class="icon-btn-sm" title="แก้ไข" onclick="openEditUserDialog(${u.id})">✏️</button>
          ${u.is_active ? `<button type="button" class="icon-btn-sm danger" title="ปิดใช้งาน" onclick="deactivateUser(${u.id})">🚫</button>` : ""}
        </div>
      </td>
    </tr>`;
    })
    .join("");
}

document.getElementById("users-search").addEventListener("input", renderUsersTable);
document.getElementById("users-role-filter").addEventListener("change", renderUsersTable);

function openEditUserDialog(id) {
  const u = lastUsers.find((x) => x.id === id);
  if (!u) return;
  currentEditUserId = id;
  document.getElementById("edit-user-username").textContent = u.username;
  document.getElementById("edit-user-fullname").value = u.full_name || "";
  document.getElementById("edit-user-email").value = u.email || "";
  document.getElementById("edit-user-phone").value = u.phone || "";
  document.getElementById("edit-user-role").value = u.role;
  document.getElementById("edit-user-password").value = "";
  document.getElementById("edit-user-active").checked = u.is_active;
  document.getElementById("edit-user-dialog").showModal();
}

document.getElementById("edit-user-form").addEventListener("submit", async (e) => {
  if (!e.submitter || e.submitter.value !== "confirm" || !currentEditUserId) return;
  const password = document.getElementById("edit-user-password").value;
  try {
    await fetchJSON(`${API}/admin/users/${currentEditUserId}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        full_name: document.getElementById("edit-user-fullname").value.trim() || null,
        email: document.getElementById("edit-user-email").value.trim() || null,
        phone: document.getElementById("edit-user-phone").value.trim() || null,
        role: document.getElementById("edit-user-role").value,
        is_active: document.getElementById("edit-user-active").checked,
        password: password || null,
      }),
    });
    loadUsers();
  } catch (err) {
    alert("บันทึกไม่สำเร็จ: " + err.message);
  }
});

function openAddUserDialog() {
  document.getElementById("user-form").reset();
  document.getElementById("add-user-dialog").showModal();
}

document.getElementById("user-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  try {
    await fetchJSON(`${API}/admin/users`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        username: document.getElementById("user-username-input").value.trim(),
        password: document.getElementById("user-password").value,
        full_name: document.getElementById("user-fullname").value.trim() || null,
        email: document.getElementById("user-email").value.trim() || null,
        phone: document.getElementById("user-phone").value.trim() || null,
        role: document.getElementById("user-role-select").value,
      }),
    });
    document.getElementById("user-form").reset();
    document.getElementById("add-user-dialog").close();
    loadUsers();
  } catch (err) {
    alert("เพิ่ม user ไม่สำเร็จ: " + err.message);
  }
});

async function deactivateUser(id) {
  if (!confirm("ยืนยันปิดใช้งาน user นี้?")) return;
  try {
    await fetchJSON(`${API}/admin/users/${id}/deactivate`, { method: "PATCH" });
    loadUsers();
  } catch (err) {
    alert("ปิดใช้งานไม่สำเร็จ: " + err.message);
  }
}

let currentTopupUserId = null;

function openTopupDialog(id) {
  const u = lastUsers.find((x) => x.id === id);
  if (!u) return;
  currentTopupUserId = id;
  document.getElementById("topup-username").textContent = u.full_name || u.username;
  document.getElementById("topup-current-balance").textContent = `฿${(u.wallet_balance ?? 0).toFixed(2)}`;
  document.getElementById("topup-amount").value = "";
  document.getElementById("topup-note").value = "";
  document.getElementById("topup-msg").style.display = "none";
  document.getElementById("topup-wallet-dialog").showModal();
}

document.getElementById("topup-wallet-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  if (!currentTopupUserId) return;
  const msgEl = document.getElementById("topup-msg");
  msgEl.style.display = "none";
  try {
    await fetchJSON(`${API}/admin/users/${currentTopupUserId}/wallet/topup`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        amount: parseFloat(document.getElementById("topup-amount").value),
        note: document.getElementById("topup-note").value.trim() || null,
      }),
    });
    document.getElementById("topup-wallet-dialog").close();
    loadUsers();
  } catch (err) {
    msgEl.textContent = "เติมเงินไม่สำเร็จ: " + err.message;
    msgEl.style.display = "block";
  }
});

// ---------- RFID Cards ----------
let lastCards = [];
let currentEditCardId = null;

function userLabel(userId) {
  const u = lastUsers.find((u) => u.id === userId);
  if (!u) return `#${userId}`;
  return u.full_name ? `${u.username} (${u.full_name})` : u.username;
}

async function loadCards() {
  const rows = await fetchJSON(`${API}/admin/cards`);
  lastCards = rows;
  const tbody = document.getElementById("cards-body");

  if (rows.length === 0) {
    tbody.innerHTML = `<tr><td colspan="4">ยังไม่มีบัตร</td></tr>`;
    return;
  }

  tbody.innerHTML = rows
    .map(
      (c) => `
    <tr>
      <td><strong>${c.card_uid}</strong></td>
      <td>${userLabel(c.user_id)}</td>
      <td><span class="badge ${c.is_active ? "online" : "offline"}">${c.is_active ? "Active" : "Inactive"}</span></td>
      <td>
        <div class="row-actions">
          <button type="button" class="icon-btn-sm" title="แก้ไข" onclick="openEditCardDialog(${c.id})">✏️</button>
          <button class="danger" onclick="deleteCard(${c.id})">ลบ</button>
        </div>
      </td>
    </tr>`
    )
    .join("");
}

function openEditCardDialog(id) {
  const c = lastCards.find((x) => x.id === id);
  if (!c) return;
  currentEditCardId = id;
  document.getElementById("edit-card-uid").textContent = c.card_uid;
  editCardUserIdEl.value = c.user_id;
  editCardUserSearchEl.value = userLabel(c.user_id);
  document.getElementById("edit-card-active").checked = c.is_active;
  document.getElementById("edit-card-dialog").showModal();
}

const editCardUserSearchEl = document.getElementById("edit-card-user-search");
const editCardUserIdEl = document.getElementById("edit-card-user-id");
const editCardUserResultsEl = document.getElementById("edit-card-user-results");

function renderEditCardUserResults(query) {
  const q = query.trim().toLowerCase();
  if (!q) {
    editCardUserResultsEl.style.display = "none";
    return;
  }
  const matches = lastUsers
    .filter((u) => u.username.toLowerCase().includes(q) || (u.full_name || "").toLowerCase().includes(q))
    .slice(0, 8);

  if (matches.length === 0) {
    editCardUserResultsEl.innerHTML = `<div class="autocomplete-item muted">ไม่พบ user ที่ตรงกัน</div>`;
    editCardUserResultsEl.style.display = "block";
    return;
  }

  editCardUserResultsEl.innerHTML = matches
    .map(
      (u) => `
    <div class="autocomplete-item" onclick="selectEditCardUser(${u.id})">
      <strong>${u.username}</strong>${u.full_name ? ` <span class="muted">${u.full_name}</span>` : ""}
    </div>`
    )
    .join("");
  editCardUserResultsEl.style.display = "block";
}

function selectEditCardUser(userId) {
  const u = lastUsers.find((u) => u.id === userId);
  if (!u) return;
  editCardUserIdEl.value = u.id;
  editCardUserSearchEl.value = u.full_name ? `${u.username} (${u.full_name})` : u.username;
  editCardUserResultsEl.style.display = "none";
}

editCardUserSearchEl.addEventListener("input", () => {
  editCardUserIdEl.value = "";
  renderEditCardUserResults(editCardUserSearchEl.value);
});

document.addEventListener("click", (e) => {
  if (!e.target.closest("#edit-card-user-search") && !e.target.closest("#edit-card-user-results")) {
    editCardUserResultsEl.style.display = "none";
  }
});

document.getElementById("edit-card-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const msgEl = document.getElementById("edit-card-msg");

  if (!editCardUserIdEl.value) {
    msgEl.className = "form-error";
    msgEl.textContent = "กรุณาเลือก user จากรายการค้นหาก่อน";
    msgEl.style.display = "block";
    return;
  }

  const card = lastCards.find((x) => x.id === currentEditCardId);
  try {
    await fetchJSON(`${API}/admin/cards/${currentEditCardId}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        user_id: parseInt(editCardUserIdEl.value, 10),
        is_active: document.getElementById("edit-card-active").checked,
        balance: card ? card.balance : 0,
      }),
    });
    document.getElementById("edit-card-dialog").close();
    loadCards();
  } catch (err) {
    msgEl.className = "form-error";
    msgEl.textContent = "บันทึกไม่สำเร็จ: " + err.message;
    msgEl.style.display = "block";
  }
});

// ---------- User search (autocomplete สำหรับฟอร์มเพิ่มบัตร) ----------
const cardUserSearchEl = document.getElementById("card-user-search");
const cardUserIdEl = document.getElementById("card-user-id");
const cardUserResultsEl = document.getElementById("card-user-results");

function renderUserResults(query) {
  const q = query.trim().toLowerCase();
  if (!q) {
    cardUserResultsEl.style.display = "none";
    return;
  }
  const matches = lastUsers
    .filter((u) => u.username.toLowerCase().includes(q) || (u.full_name || "").toLowerCase().includes(q))
    .slice(0, 8);

  if (matches.length === 0) {
    cardUserResultsEl.innerHTML = `<div class="autocomplete-item muted">ไม่พบ user ที่ตรงกัน</div>`;
    cardUserResultsEl.style.display = "block";
    return;
  }

  cardUserResultsEl.innerHTML = matches
    .map(
      (u) => `
    <div class="autocomplete-item" onclick="selectCardUser(${u.id})">
      <strong>${u.username}</strong>${u.full_name ? ` <span class="muted">${u.full_name}</span>` : ""}
    </div>`
    )
    .join("");
  cardUserResultsEl.style.display = "block";
}

function selectCardUser(userId) {
  const u = lastUsers.find((u) => u.id === userId);
  if (!u) return;
  cardUserIdEl.value = u.id;
  cardUserSearchEl.value = u.full_name ? `${u.username} (${u.full_name})` : u.username;
  cardUserResultsEl.style.display = "none";
}

cardUserSearchEl.addEventListener("input", () => {
  cardUserIdEl.value = "";
  renderUserResults(cardUserSearchEl.value);
});

document.addEventListener("click", (e) => {
  if (!e.target.closest("#card-user-search") && !e.target.closest("#card-user-results")) {
    cardUserResultsEl.style.display = "none";
  }
});

document.getElementById("card-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const msgEl = document.getElementById("card-msg");

  if (!cardUserIdEl.value) {
    msgEl.className = "form-error";
    msgEl.textContent = "กรุณาเลือก user จากรายการค้นหาก่อน";
    msgEl.style.display = "block";
    return;
  }

  try {
    await fetchJSON(`${API}/admin/cards`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        card_uid: document.getElementById("card-uid").value.trim(),
        user_id: parseInt(cardUserIdEl.value, 10),
      }),
    });
    document.getElementById("card-form").reset();
    msgEl.className = "form-msg";
    msgEl.textContent = "เพิ่มบัตรสำเร็จ";
    msgEl.style.display = "block";
    setTimeout(() => (msgEl.style.display = "none"), 2000);
    loadCards();
  } catch (err) {
    msgEl.className = "form-error";
    msgEl.textContent = "เพิ่มบัตรไม่สำเร็จ: " + err.message;
    msgEl.style.display = "block";
  }
});

async function deleteCard(id) {
  if (!confirm("ยืนยันลบบัตรนี้?")) return;
  try {
    await fetchJSON(`${API}/admin/cards/${id}`, { method: "DELETE" });
    loadCards();
  } catch (err) {
    alert("ลบไม่สำเร็จ: " + err.message);
  }
}

// ---------- Charge Points ----------
async function loadChargePointsAdmin() {
  const tbody = document.getElementById("charge-points-body");
  try {
    const rows = await fetchJSON(`${API}/charge-points`);

    if (rows.length === 0) {
      tbody.innerHTML = `<tr><td colspan="6">ยังไม่มีเครื่องชาร์จเชื่อมต่อเข้ามา</td></tr>`;
      return;
    }

    tbody.innerHTML = rows
      .map(
        (r) => `
      <tr>
        <td><strong>${r.id}</strong></td>
        <td>
          <span class="badge ${r.is_online ? "online" : "offline"}">${r.is_online ? "Online" : "Offline"}</span>
          <span class="badge status-${r.status || ""}">${r.status || "Unknown"}</span>
        </td>
        <td>${r.vendor || "-"} / ${r.model || "-"}</td>
        <td>${r.connector_id ?? "-"}</td>
        <td>${fmtDate(r.last_heartbeat)}</td>
        <td><button class="danger" onclick="deleteChargePointAdmin('${r.id}')">ลบ</button></td>
      </tr>`
      )
      .join("");
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="6">โหลดรายการไม่สำเร็จ: ${err.message}</td></tr>`;
  }
}

async function deleteChargePointAdmin(id) {
  if (!confirm(`ยืนยันลบเครื่องชาร์จ ${id}? (ถ้าเครื่องนี้ยัง online อยู่ รายการจะถูกสร้างใหม่อัตโนมัติเมื่อได้รับข้อความถัดไปจากเครื่อง)`)) return;
  try {
    await fetchJSON(`${API}/admin/charge-points/${id}`, { method: "DELETE" });
    loadChargePointsAdmin();
  } catch (err) {
    alert("ลบไม่สำเร็จ: " + err.message);
  }
}

// ---------- Card Taps ----------
function statusBadgeClass(status) {
  return status === "Accepted" ? "online" : "offline";
}

async function loadCardTaps() {
  const tbody = document.getElementById("card-taps-body");
  try {
    const rows = await fetchJSON(`${API}/admin/card-taps`);

    if (rows.length === 0) {
      tbody.innerHTML = `<tr><td colspan="5">ยังไม่มีการแตะบัตร</td></tr>`;
      return;
    }

    tbody.innerHTML = rows
      .map(
        (r) => `
      <tr>
        <td>${fmtDate(r.created_at)}</td>
        <td>${r.charge_point_id}</td>
        <td>${r.card_uid}</td>
        <td>${r.user_id ? userLabel(r.user_id) : "-"}</td>
        <td><span class="badge ${statusBadgeClass(r.status)}">${r.status}</span></td>
      </tr>`
      )
      .join("");
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="5">โหลดรายการไม่สำเร็จ: ${err.message}</td></tr>`;
  }
}

// ---------- Wallet payment logs ----------
function walletPaymentStatusClass(status) {
  if (status === "successful") return "online";
  if (status === "pending") return "preparing";
  return "offline";
}

async function loadWalletPayments() {
  const tbody = document.getElementById("wallet-payments-body");
  if (!tbody) return;
  try {
    const rows = await fetchJSON(`${API}/admin/wallet/payments?limit=200`);
    if (rows.length === 0) {
      tbody.innerHTML = `<tr><td colspan="7">ยังไม่มีรายการเติมเงิน</td></tr>`;
      return;
    }
    tbody.innerHTML = rows.map((r) => `
      <tr>
        <td>${fmtDate(r.created_at)}</td>
        <td>${r.full_name || r.username || `User #${r.user_id}`}</td>
        <td><code>${r.reference || "-"}</code></td>
        <td><strong>฿${Number(r.amount || 0).toFixed(2)}</strong></td>
        <td>${r.method || "-"} / ${r.provider || "-"}</td>
        <td><span class="badge ${walletPaymentStatusClass(r.status)}">${r.status || "-"}</span></td>
        <td>${fmtDate(r.completed_at)}</td>
      </tr>`).join("");
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="7">โหลดรายการไม่สำเร็จ: ${err.message}</td></tr>`;
  }
}

// ---------- Backup ----------
function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

async function loadBackups() {
  const tbody = document.getElementById("backups-body");
  try {
    const rows = await fetchJSON(`${API}/admin/backup/list`);

    if (rows.length === 0) {
      tbody.innerHTML = `<tr><td colspan="4">ยังไม่มี backup</td></tr>`;
      return;
    }

    tbody.innerHTML = rows
      .map(
        (b) => `
      <tr>
        <td>${b.filename}</td>
        <td>${formatBytes(b.size_bytes)}</td>
        <td>${fmtDate(b.created_at)}</td>
        <td><a href="${API}/admin/backup/download/${encodeURIComponent(b.filename)}"><button type="button" class="secondary">ดาวน์โหลด</button></a></td>
      </tr>`
      )
      .join("");
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="4">โหลดรายการไม่สำเร็จ: ${err.message}</td></tr>`;
  }
}

document.getElementById("restore-confirm").addEventListener("input", (e) => {
  document.getElementById("restore-submit-btn").disabled = e.target.value !== "RESTORE";
});
document.getElementById("restore-submit-btn").disabled = true;

document.getElementById("restore-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const msgEl = document.getElementById("restore-msg");
  const fileInput = document.getElementById("restore-file");
  const file = fileInput.files[0];
  if (!file) return;

  if (!confirm("ยืนยันการ Restore ฐานข้อมูล? ข้อมูลปัจจุบันทั้งหมดจะถูกเขียนทับ")) return;

  const formData = new FormData();
  formData.append("file", file);

  msgEl.className = "form-msg";
  msgEl.textContent = "กำลัง restore...";
  msgEl.style.display = "block";

  try {
    const res = await fetchJSON(`${API}/admin/backup/restore`, {
      method: "POST",
      body: formData,
    });
    msgEl.textContent = `Restore สำเร็จ (สำรองข้อมูลเดิมไว้ที่: ${res.pre_restore_backup})`;
    document.getElementById("restore-form").reset();
    document.getElementById("restore-submit-btn").disabled = true;
    loadBackups();
  } catch (err) {
    msgEl.className = "form-error";
    msgEl.textContent = "Restore ไม่สำเร็จ: " + err.message;
  }
});

init();
