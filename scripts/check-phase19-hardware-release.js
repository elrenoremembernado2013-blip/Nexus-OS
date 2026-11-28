#!/usr/bin/env node
// Phase 19 tests: Hardware Compatibility Centre, Diagnostics Privacy, Beta Tester Centre,
// Installation Preflight, Recovery Guides, Release Checksums/Provenance, and Cross-Edition checks.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");
const { execFileSync } = require("node:child_process");

function makeNode(tag = "div") {
  const listeners = new Map();
  const children = [];
  const attrs = {};
  const classSet = new Set();
  const el = {
    tagName: tag.toUpperCase(),
    id: "",
    type: "",
    value: "",
    placeholder: "",
    rows: 2,
    checked: false,
    disabled: false,
    href: "",
    download: "",
    textContent: "",
    dataset: {},
    style: {},
    children,
    _listeners: listeners,
    setAttribute(k, v) { attrs[k] = String(v); },
    getAttribute(k) { return Object.prototype.hasOwnProperty.call(attrs, k) ? attrs[k] : null; },
    classList: {
      add: (...c) => c.forEach(x => classSet.add(x)),
      remove: (...c) => c.forEach(x => classSet.delete(x)),
      toggle: (c, f) => {
        if (f === undefined) {
          if (classSet.has(c)) classSet.delete(c);
          else classSet.add(c);
        } else if (f) classSet.add(c);
        else classSet.delete(c);
      },
      contains: c => classSet.has(c)
    },
    set className(v) {
      classSet.clear();
      String(v || "").split(/\s+/).filter(Boolean).forEach(c => classSet.add(c));
    },
    get className() {
      return [...classSet].join(" ");
    },
    append(...nodes) {
      for (const n of nodes) {
        if (n && typeof n === "object") {
          n.parentNode = el;
          children.push(n);
        }
      }
    },
    replaceChildren(...nodes) {
      children.length = 0;
      el.append(...nodes);
    },
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, new Set());
      listeners.get(type).add(fn);
    },
    removeEventListener(type, fn) {
      listeners.get(type)?.delete(fn);
    },
    querySelector(sel) {
      return el.querySelectorAll(sel)[0] || null;
    },
    querySelectorAll(sel) {
      const out = [];
      const visit = node => {
        for (const ch of node.children || []) {
          if (matches(ch, sel)) out.push(ch);
          visit(ch);
        }
      };
      visit(el);
      return out;
    },
    closest(sel) {
      let cur = el;
      while (cur) {
        if (matches(cur, sel)) return cur;
        cur = cur.parentNode || null;
      }
      return null;
    },
    click() {
      const event = { target: el, preventDefault() {} };
      let cur = el;
      while (cur) {
        for (const fn of cur._listeners?.get("click") || []) fn(event);
        cur = cur.parentNode || null;
      }
    }
  };
  return el;
}

function matches(node, sel) {
  if (!node || typeof node !== "object") return false;
  if (sel.startsWith("#")) return node.id === sel.slice(1);
  if (sel.startsWith(".")) return node.classList?.contains(sel.slice(1));
  const attrMatch = sel.match(/^\[([a-z0-9-]+)(?:="([^"]*)")?\]$/i);
  if (attrMatch) {
    const raw = attrMatch[1];
    const val = attrMatch[2];
    const camel = raw.replace(/^data-/, "").replace(/-([a-z])/g, (_, ch) => ch.toUpperCase());
    const actual = raw.startsWith("data-") ? node.dataset?.[camel] : node.getAttribute?.(raw);
    return val === undefined ? actual !== undefined && actual !== null : String(actual) === val;
  }
  return false;
}

function collectText(node) {
  return [node.textContent || "", ...(node.children || []).map(collectText)].join(" ");
}

function writeFile(p, content) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content);
}

async function run() {
  const tmpBase = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-phase19-"));

  try {
    // 1. Missing hardware detection (empty /proc and /sys) must not crash or fake Working status
    {
      const emptyProc = path.join(tmpBase, "empty-proc");
      const emptySys = path.join(tmpBase, "empty-sys");
      fs.mkdirSync(emptyProc, { recursive: true });
      fs.mkdirSync(emptySys, { recursive: true });
      const out = execFileSync("bash", ["linux/hardware/nexus-hw-inventory.sh", "--json"], {
        env: { ...process.env, NEXUS_PROC_ROOT: emptyProc, NEXUS_SYS_ROOT: emptySys },
        encoding: "utf8"
      });
      const inv = JSON.parse(out);
      assert.equal(inv.cpu.model, "unavailable");
      assert.equal(inv.memory.ram_total_mib, null);
      const map = Object.fromEntries(inv.compatibility_report.map(r => [r.component, r.status]));
      assert.equal(map["CPU & Architecture"], "Unable to test");
      assert.equal(map["Memory (RAM)"], "Unable to test");
      assert.equal(map["Graphics (GPU)"], "Unable to test");
      assert.equal(map["Wi-Fi"], "Unable to test");
      assert.equal(map["Bluetooth"], "Unable to test");
      assert.equal(map["Audio Hardware"], "Unable to test");
    }

    // 2. Mocked hardware environments (laptop + unsupported arch/low RAM/virtual GPU)
    {
      const mockProc = path.join(tmpBase, "mock1-proc");
      const mockSys = path.join(tmpBase, "mock1-sys");
      writeFile(path.join(mockProc, "cpuinfo"), [
        "vendor_id\t: GenuineIntel",
        "model name\t: Intel(R) Core(TM) i5-1235U",
        "cpu cores\t: 10",
        "flags\t\t: vmx sse4_2"
      ].join("\n") + "\n");
      writeFile(path.join(mockProc, "meminfo"), "MemTotal:       16384000 kB\nMemAvailable:   12000000 kB\n");
      writeFile(path.join(mockProc, "asound/cards"), " 0 [sofhdadsp      ]: sof-hda-dsp - sof-hda-dsp\n");
      writeFile(path.join(mockProc, "bus/input/devices"), "N: Name=\"ELAN0678:00 Touchpad\"\nH: Handlers=mouse0 event5\n\n");

      // PCI devices + symlinks for driver names
      const drvI915 = path.join(mockSys, "bus/pci/drivers/i915");
      const drvIwl = path.join(mockSys, "bus/pci/drivers/iwlwifi");
      fs.mkdirSync(drvI915, { recursive: true });
      fs.mkdirSync(drvIwl, { recursive: true });
      const gpuDev = path.join(mockSys, "bus/pci/devices/0000:00:02.0");
      writeFile(path.join(gpuDev, "class"), "0x030000\n");
      writeFile(path.join(gpuDev, "vendor"), "0x8086\n");
      writeFile(path.join(gpuDev, "device"), "0x46a8\n");
      fs.symlinkSync(drvI915, path.join(gpuDev, "driver"));

      const wifiIf = path.join(mockSys, "class/net/wlp0s20f3");
      fs.mkdirSync(path.join(wifiIf, "wireless"), { recursive: true });
      writeFile(path.join(wifiIf, "operstate"), "up\n");
      fs.mkdirSync(path.join(wifiIf, "device"), { recursive: true });
      fs.symlinkSync(drvIwl, path.join(wifiIf, "device/driver"));

      fs.mkdirSync(path.join(mockSys, "class/bluetooth/hci0"), { recursive: true });
      fs.mkdirSync(path.join(mockSys, "firmware/efi/efivars"), { recursive: true });
      fs.writeFileSync(path.join(mockSys, "firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"), Buffer.from([6, 0, 0, 0, 1]));

      const out1 = execFileSync("bash", ["linux/hardware/nexus-hw-inventory.sh", "--json"], {
        env: { ...process.env, NEXUS_PROC_ROOT: mockProc, NEXUS_SYS_ROOT: mockSys, NEXUS_ARCH_OVERRIDE: "x86_64" },
        encoding: "utf8"
      });
      const inv1 = JSON.parse(out1);
      assert.equal(inv1.cpu.vendor, "GenuineIntel");
      assert.equal(inv1.cpu.physical_cores, 10);
      const map1 = Object.fromEntries(inv1.compatibility_report.map(r => [r.component, r.status]));
      assert.equal(map1["Wi-Fi"], "Working");
      assert.equal(map1["Bluetooth"], "Detected"); // Never falsely marked Working without interactive test!
      assert.equal(map1["Graphics (GPU)"], "Detected"); // Bound i915, requires interactive test

      // Unsupported architecture + low RAM + virtual GPU
      const mockProc2 = path.join(tmpBase, "mock2-proc");
      const mockSys2 = path.join(tmpBase, "mock2-sys");
      writeFile(path.join(mockProc2, "cpuinfo"), "vendor_id\t: ARM\nmodel name\t: Mock ARM\n");
      writeFile(path.join(mockProc2, "meminfo"), "MemTotal:         393216 kB\nMemAvailable:     200000 kB\n");
      const drvBochs = path.join(mockSys2, "bus/pci/drivers/bochs-drm");
      fs.mkdirSync(drvBochs, { recursive: true });
      const gpu2 = path.join(mockSys2, "bus/pci/devices/0000:00:02.0");
      writeFile(path.join(gpu2, "class"), "0x030000\n");
      writeFile(path.join(gpu2, "vendor"), "0x1234\n");
      writeFile(path.join(gpu2, "device"), "0x1111\n");
      fs.symlinkSync(drvBochs, path.join(gpu2, "driver"));

      const out2 = execFileSync("bash", ["linux/hardware/nexus-hw-inventory.sh", "--json"], {
        env: { ...process.env, NEXUS_PROC_ROOT: mockProc2, NEXUS_SYS_ROOT: mockSys2, NEXUS_ARCH_OVERRIDE: "aarch64" },
        encoding: "utf8"
      });
      const inv2 = JSON.parse(out2);
      const map2 = Object.fromEntries(inv2.compatibility_report.map(r => [r.component, r.status]));
      assert.equal(map2["CPU & Architecture"], "Unsupported");
      assert.equal(map2["Memory (RAM)"], "Unsupported");
      assert.equal(map2["Graphics (GPU)"], "Limited support");
    }

    // 3. Diagnostic report privacy & export
    {
      const exportDir = path.join(tmpBase, "diag-export");
      const out = execFileSync("bash", ["linux/hardware/nexus-hw-diagnostics.sh", "--json", "--export", exportDir], {
        encoding: "utf8"
      });
      const diag = JSON.parse(out);
      assert.equal(diag.privacy_audit.passed, true);
      assert.equal(diag.privacy_audit.auto_upload, false);
      assert.ok(Array.isArray(diag.failed_systemd_services));
      assert.ok(Array.isArray(diag.storage_availability) && diag.storage_availability.length >= 1);
      assert.ok(diag.package_manager && "dpkg_audit_status" in diag.package_manager);
      assert.ok(diag.security_updates && "status" in diag.security_updates);
      assert.ok(diag.boot_recovery && "uefi_active" in diag.boot_recovery);
      assert.ok(fs.existsSync(path.join(exportDir, "nexus-diagnostics.json")));
      assert.ok(fs.existsSync(path.join(exportDir, "nexus-diagnostics.md")));
    }

    // 4. Bridge registers `hardware` & UI handles unavailable, permission error, and async connected modes + Beta export
    {
      // Disconnected mode
      let hwApp = null;
      const downloads = [];
      const makeCtx = (adapter) => ({
        window: {
          NexusAppRegistry: { register(def) { hwApp = def; } },
          NexusNativeServices: {
            status: id => ({ available: Boolean(adapter) && id === "hardware" }),
            call: (id, method) => adapter[method]()
          },
          setTimeout: fn => fn()
        },
        document: { createElement: tag => makeNode(tag) },
        Blob: class MockBlob { constructor(parts, opts) { this.text = parts.join(""); this.type = opts.type; } },
        URL: {
          createObjectURL(blob) { downloads.push(blob); return "blob:test-1"; },
          revokeObjectURL() {}
        }
      });

      const ctxOff = makeCtx(null);
      vm.createContext(ctxOff);
      vm.runInContext(fs.readFileSync("apps/hardware-centre.js", "utf8"), ctxOff);
      const rootOff = makeNode("div");
      const panelOff = makeNode("div"); panelOff.id = "hardwarePanel";
      const statusOff = makeNode("p"); statusOff.id = "hardwareStatus";
      const tabsOff = ["compatibility", "diagnostics", "beta"].map(id => {
        const b = makeNode("button");
        b.dataset.hwTab = id;
        return b;
      });
      rootOff.append(...tabsOff, panelOff, statusOff);
      hwApp.mount(rootOff);
      assert.ok(collectText(panelOff).includes("Unable to test"), "Disconnected Compatibility must show Unable to test");

      // Switch to Beta tab & export bug report locally
      tabsOff[2].click();
      rootOff.querySelector("#betaSteps").value = "1. Open Store\n2. Click Info";
      rootOff.querySelector("#betaExpected").value = "Shows deps";
      rootOff.querySelector("#betaActual").value = "Works";
      rootOff.querySelector('[data-hw-action="export-bug-json"]').click();
      const bugJson = JSON.parse(downloads[downloads.length - 1].text);
      assert.equal(bugJson.submitted_to_server, false);
      assert.equal(bugJson.local_export_only, true);
      assert.equal(bugJson.steps_to_reproduce, "1. Open Store\n2. Click Info");

      // Async Promise rejection (permission/service failure)
      const ctxErr = makeCtx({
        inventory: () => Promise.reject(new Error("Permission denied reading sysfs")),
        diagnostics: () => Promise.reject(new Error("Service unavailable"))
      });
      vm.createContext(ctxErr);
      vm.runInContext(fs.readFileSync("apps/hardware-centre.js", "utf8"), ctxErr);
      const rootErr = makeNode("div");
      const panelErr = makeNode("div"); panelErr.id = "hardwarePanel";
      const statusErr = makeNode("p"); statusErr.id = "hardwareStatus";
      rootErr.append(panelErr, statusErr);
      hwApp.mount(rootErr);
      await new Promise(r => setTimeout(r, 15));
      assert.ok(statusErr.textContent.includes("Permission denied"), "Async error must surface cleanly");

      // Async Promise success
      const ctxOk = makeCtx({
        inventory: () => Promise.resolve({
          environment: { label: "bare_metal_or_host" },
          cpu: { vendor: "AuthenticAMD", model: "Ryzen 7", physical_cores: 8, logical_threads: 16 },
          memory: { ram_total_mib: 16384, ram_used_mib: 4096, ram_available_mib: 12288 },
          firmware: { mode: "UEFI", secure_boot: "enabled" },
          gpus: [{ vendor_name: "AMD/ATI", device: "0x164e", driver: "amdgpu" }],
          graphics_qualification: { hardware_acceleration: "genuine_hardware_gpu_driver_bound" },
          network: { wifi: [], ethernet: [] },
          bluetooth: [],
          audio: { cards: [], audio_server: "PipeWire" },
          storage: [],
          displays: [{ connector: "card0-eDP-1", status: "connected", modes: ["1920x1080"], refresh_hz: "60.00" }],
          touchpads: [],
          input_devices: [],
          usb_devices: [],
          compatibility_report: [{ component: "CPU & Architecture", status: "Working", evidence: "AuthenticAMD Ryzen 7" }]
        })
      });
      vm.createContext(ctxOk);
      vm.runInContext(fs.readFileSync("apps/hardware-centre.js", "utf8"), ctxOk);
      const rootOk = makeNode("div");
      const panelOk = makeNode("div"); panelOk.id = "hardwarePanel";
      const statusOk = makeNode("p"); statusOk.id = "hardwareStatus";
      rootOk.append(panelOk, statusOk);
      hwApp.mount(rootOk);
      await new Promise(r => setTimeout(r, 15));
      assert.ok(collectText(panelOk).includes("Ryzen 7"));
      assert.ok(collectText(panelOk).includes("1920x1080 @ 60.00Hz"));
    }

    // 5. Preflight + Recovery + Release Engineering (checksums, provenance, no fake signatures, 4 editions)
    {
      for (const ed of ["cinnamon", "xfce", "lite-lxqt", "lite"]) {
        const pre = JSON.parse(execFileSync("bash", ["linux/installer/nexus-install-preflight.sh", "--edition", ed, "--json"], { encoding: "utf8" }));
        assert.equal(pre.edition, ed);
        assert.ok(pre.network_requirements && pre.network_requirements.offline_iso_install_supported === true);
        assert.ok(Array.isArray(pre.installation_risks));

        const relDry = execFileSync("bash", ["linux/build/prepare-release.sh", "--dry-run", "--stage", "beta", "--edition", ed], { encoding: "utf8" });
        assert.ok(relDry.includes("signature: unsigned"));
      }

      for (const topic of ["drivers", "network", "desktop", "storage", "recovery"]) {
        const g = execFileSync("bash", ["linux/installer/nexus-recovery.sh", "--guide", topic], { encoding: "utf8" });
        assert.ok(g.length > 40, `Recovery guide topic ${topic} must emit content`);
      }

      const relDir = path.join(tmpBase, "rel");
      fs.mkdirSync(relDir, { recursive: true });
      const fakeIso = path.join(relDir, "nexus-os-22.3-xfce-amd64.iso");
      fs.writeFileSync(fakeIso, "nexus-test-iso-bytes\n");
      const isoSha = execFileSync("sha256sum", [path.basename(fakeIso)], { cwd: relDir, encoding: "utf8" }).split(/\s+/)[0];
      const buildInfo = path.join(relDir, "build-info.json");
      fs.writeFileSync(buildInfo, JSON.stringify({
        name: "NEXUS OS",
        base_distro: "linuxmint",
        base_version: "22.3",
        edition: "xfce",
        arch: "amd64",
        output_iso: path.basename(fakeIso),
        output_iso_sha256: isoSha
      }));
      const outManifest = path.join(relDir, "nexus-release-manifest.json");
      const outChecksums = path.join(relDir, "SHA256SUMS");
      execFileSync("bash", [
        "linux/build/prepare-release.sh",
        "--stage", "beta",
        "--edition", "xfce",
        "--build-info", buildInfo,
        "--out", outManifest,
        "--checksums-out", outChecksums
      ], { encoding: "utf8" });

      execFileSync("sha256sum", ["-c", "SHA256SUMS"], { cwd: relDir });
      const manifest = JSON.parse(fs.readFileSync(outManifest, "utf8"));
      assert.equal(manifest.signature_status, "unsigned");
      assert.equal(manifest.provenance.security_and_package_audit_passed, true);
      assert.ok(manifest.provenance.package_manifest_sha256["linux/config/mint-packages.list"]);

      // Stable gate must still reject unverified builds
      let stableFailed = false;
      try {
        execFileSync("bash", ["linux/build/prepare-release.sh", "--stage", "stable", "--dry-run"], { stdio: "pipe" });
      } catch {
        stableFailed = true;
      }
      assert.equal(stableFailed, true, "stable stage without --vm-verified must fail");
    }

    // 6. Real loopback bridge HTTP endpoints (/api/hardware/inventory, /api/hardware/diagnostics, /api/recovery/diagnose) + 401 guard
    {
      const rtFile = path.join(tmpBase, "bridge-rt.json");
      const bridgeCode = `
import json, subprocess, time, urllib.request, urllib.error, sys
proc = subprocess.Popen(
    ["python3", "linux/mint/nexus-system-bridge.py", "--serve", "--port", "0", "--runtime-file", sys.argv[1]],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
)
try:
    line = proc.stdout.readline().strip()
    info = json.loads(line)
    url, token = info["url"], info["token"]
    # 1. Unauthorized must fail with 401
    try:
        urllib.request.urlopen(url + "/api/hardware/inventory", timeout=5)
        raise AssertionError("Expected 401 without token")
    except urllib.error.HTTPError as err:
        assert err.code == 401

    # 2. Authorized requests
    for ep, key in (
        ("/api/hardware/inventory", "compatibility_report"),
        ("/api/hardware/diagnostics", "privacy_audit"),
        ("/api/recovery/diagnose", "read_only"),
    ):
        req = urllib.request.Request(url + ep, headers={"X-Nexus-Token": token})
        with urllib.request.urlopen(req, timeout=15) as resp:
            assert resp.status == 200
            data = json.loads(resp.read().decode("utf-8"))
            assert key in data, f"Missing {key} in {ep}"
finally:
    proc.terminate()
    proc.wait(timeout=5)
`;
      execFileSync("python3", ["-c", bridgeCode, rtFile], { encoding: "utf8" });

      // Also verify apps/native-services.js registers hardware when __NEXUS_BRIDGE__ is set
      const bridgeCtx = {
        fetch: async () => ({ ok: true, status: 200, async json() { return {}; } }),
        window: { __NEXUS_BRIDGE__: { url: "http://127.0.0.1:47899", token: "t1" } },
        console
      };
      vm.createContext(bridgeCtx);
      vm.runInContext(fs.readFileSync("apps/native-services.js", "utf8"), bridgeCtx);
      assert.equal(bridgeCtx.window.NexusNativeServices.status("hardware").available, true);
    }

    console.log("PASS Phase 19 hardware compatibility, mocked envs, diagnostics privacy, beta UI, recovery, bridge HTTP, and release checksum tests");
  } finally {
    fs.rmSync(tmpBase, { recursive: true, force: true });
  }
}

run().catch(err => {
  console.error(err);
  process.exit(1);
});
