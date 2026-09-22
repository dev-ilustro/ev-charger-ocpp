function getNextParam() {
  const params = new URLSearchParams(window.location.search);
  return params.get("next") || "/";
}

document.getElementById("login-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const username = document.getElementById("login-username").value.trim();
  const password = document.getElementById("login-password").value;
  const errorEl = document.getElementById("login-error");
  errorEl.style.display = "none";

  try {
    const res = await fetch("/api/auth/login", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password }),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ detail: res.statusText }));
      throw new Error(err.detail || "เข้าสู่ระบบไม่สำเร็จ");
    }
    window.location.href = getNextParam();
  } catch (err) {
    errorEl.textContent = err.message;
    errorEl.style.display = "block";
  }
});
