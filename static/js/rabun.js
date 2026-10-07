(() => {
  const DEFAULT_ENDPOINT = "/submit";
  const DEFAULT_PUBKEY = "/pubkey";

  function yamlQuote(value) {
    if (value === true || value === false || value === null) {
      return String(value);
    }
    const text = String(value);
    if (text === "") {
      return '""';
    }
    if (/[\n\r]/.test(text)) {
      return (
        "|\n" +
        text
          .replace(/\r\n/g, "\n")
          .split("\n")
          .map((line) => "    " + line)
          .join("\n")
      );
    }
    if (/[:#\[\]{},&*!|>%@`]|^[-?]|^\s|\s$/.test(text) || text !== text.trim()) {
      return JSON.stringify(text);
    }
    return text;
  }

  function formToYaml(form, formName) {
    const data = new FormData(form);
    const lines = [
      "form: " + yamlQuote(formName),
      "submitted_at: " + yamlQuote(new Date().toISOString()),
      "fields:",
    ];
    let count = 0;
    for (const [name, value] of data.entries()) {
      if (name === "_gotcha" || name === "ciphertext" || name === "form") {
        continue;
      }
      if (typeof value !== "string") {
        continue;
      }
      const rendered = yamlQuote(value);
      if (rendered.startsWith("|\n")) {
        lines.push("  " + name + ": " + rendered);
      } else {
        lines.push("  " + name + ": " + rendered);
      }
      count += 1;
    }
    if (count === 0) {
      lines.push("  {}");
    }
    return lines.join("\n") + "\n";
  }

  const pubkeyCache = new Map();

  async function fetchPublicKey(url) {
    if (pubkeyCache.has(url)) {
      return pubkeyCache.get(url);
    }
    const pending = fetch(url, { headers: { Accept: "application/pgp-keys, text/plain" } }).then(
      async (response) => {
        if (!response.ok) {
          throw new Error("failed to fetch public key from " + url);
        }
        return response.text();
      }
    );
    pubkeyCache.set(url, pending);
    try {
      return await pending;
    } catch (error) {
      pubkeyCache.delete(url);
      throw error;
    }
  }

  async function encryptYaml(yaml, armoredKey) {
    if (!globalThis.openpgp) {
      throw new Error("OpenPGP.js is not loaded");
    }
    const publicKey = await openpgp.readKey({ armoredKey });
    const message = await openpgp.createMessage({ text: yaml });
    return openpgp.encrypt({
      message,
      encryptionKeys: publicKey,
      format: "armored",
    });
  }

  async function submitForm(form, options = {}) {
    const endpoint = options.endpoint || form.getAttribute("data-rabun-endpoint") || DEFAULT_ENDPOINT;
    const pubkeyUrl = options.pubkey || form.getAttribute("data-rabun-pubkey") || DEFAULT_PUBKEY;
    const formName = options.form || form.getAttribute("data-rabun-form") || form.getAttribute("name") || "form";
    const status = options.status || form.querySelector("[data-rabun-status]");
    const submit = form.querySelector("[type=submit]");

    const setStatus = (text, kind) => {
      if (!status) {
        return;
      }
      status.textContent = text;
      status.dataset.kind = kind || "";
    };

    const honeypot = form.querySelector("[name=_gotcha], [data-rabun-honeypot]");
    if (honeypot && honeypot.value) {
      setStatus("Sent.", "ok");
      return { ok: true, dropped: true };
    }

    try {
      if (submit) {
        submit.disabled = true;
      }
      setStatus("Encrypting…", "pending");
      const yaml = formToYaml(form, formName);
      const publicKey = await fetchPublicKey(pubkeyUrl);
      const ciphertext = await encryptYaml(yaml, publicKey);
      setStatus("Sending…", "pending");
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ form: formName, ciphertext }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok || body.ok === false) {
        throw new Error(body.error || "submit failed (" + response.status + ")");
      }
      form.reset();
      setStatus("Sent. Submission " + (body.id || "accepted") + ".", "ok");
      form.dispatchEvent(new CustomEvent("rabun:sent", { detail: body }));
      return body;
    } catch (error) {
      setStatus(error.message || String(error), "error");
      form.dispatchEvent(new CustomEvent("rabun:error", { detail: error }));
      throw error;
    } finally {
      if (submit) {
        submit.disabled = false;
      }
    }
  }

  function bind(form, options) {
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      submitForm(form, options).catch(() => {});
    });
  }

  function bindAll(root) {
    (root || document).querySelectorAll("form[data-rabun]").forEach((form) => {
      const pubkeyUrl = form.getAttribute("data-rabun-pubkey") || DEFAULT_PUBKEY;
      fetchPublicKey(pubkeyUrl).catch(() => {});
      bind(form);
    });
  }

  globalThis.Rabun = { bind, bindAll, submitForm, formToYaml, encryptYaml };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => bindAll(document));
  } else {
    bindAll(document);
  }
})();
