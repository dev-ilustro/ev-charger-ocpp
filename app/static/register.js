document.getElementById("register-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const errorEl = document.getElementById("reg-error");
  errorEl.style.display = "none";

  const body = {
    username: document.getElementById("reg-username").value.trim(),
    password: document.getElementById("reg-password").value,
    full_name: document.getElementById("reg-fullname").value.trim() || null,
    email: document.getElementById("reg-email").value.trim() || null,
    phone: document.getElementById("reg-phone").value.trim() || null,
  };

  try {
    const res = await fetch("/api/auth/register", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ detail: res.statusText }));
      throw new Error(err.detail || "สมัครสมาชิกไม่สำเร็จ");
    }
    window.location.href = "/";
  } catch (err) {
    errorEl.textContent = err.message;
    errorEl.style.display = "block";
  }
});
