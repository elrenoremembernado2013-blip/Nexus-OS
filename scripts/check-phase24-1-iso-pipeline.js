#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");

function runExpectFail(cmd, args, opts = {}) {
  try {
    execFileSync(cmd, args, { stdio: "pipe", ...opts });
  } catch (err) {
    return {
      status: err.status ?? 1,
      stdout: (err.stdout || "").toString("utf8"),
      stderr: (err.stderr || "").toString("utf8"),
    };
  }
  assert.fail(`Expected command to fail: ${cmd} ${args.join(" ")}`);
}

function testFourEditionEntryPointsAndDifferences() {
  const cases = [
    {
      edition: "cinnamon",
      script: "linux/build/build-nexus-iso.sh",
      args: ["--edition", "cinnamon", "--dry-run"],
      expectedIso: "nexus-os-22.3-cinnamon-amd64.iso",
      expectedWork: "work-cinnamon",
      expectedConf: "nexus-standard-cinnamon.conf",
      expectedManifest: "cinnamon-packages.list",
    },
    {
      edition: "xfce",
      script: "linux/build/build-nexus-iso.sh",
      args: ["--edition", "xfce", "--dry-run"],
      expectedIso: "nexus-os-22.3-xfce-amd64.iso",
      expectedWork: "work-xfce",
      expectedConf: "nexus-system.conf",
      expectedManifest: "mint-packages.list",
    },
    {
      edition: "lite",
      script: "linux/lite/build-nexus-lite-iso.sh",
      args: ["--dry-run"],
      expectedIso: "nexus-os-22.3-lite-amd64.iso",
      expectedWork: "work-lite",
      expectedManifest: "lite-packages.list",
    },
    {
      edition: "lite-lxqt",
      script: "linux/lite/scripts/build-nexus-lite-lxqt-iso.sh",
      args: ["--dry-run"],
      expectedIso: "nexus-os-22.3-lite-lxqt-amd64.iso",
      expectedWork: "work-lite-lxqt",
      expectedManifest: "lite-lxqt-packages.list",
    },
  ];

  for (const c of cases) {
    const out = execFileSync("bash", [path.join(ROOT, c.script), ...c.args], { encoding: "utf8" });
    assert(out.includes(c.expectedIso), `${c.script} dry-run missing expected ISO ${c.expectedIso}`);
    assert(out.includes(c.expectedWork), `${c.script} dry-run missing expected work dir ${c.expectedWork}`);
    assert(out.includes(c.expectedManifest), `${c.script} dry-run missing expected manifest ${c.expectedManifest}`);
    if (c.expectedConf) {
      assert(out.includes(c.expectedConf), `${c.script} dry-run missing expected config ${c.expectedConf}`);
    }
  }

  // Edition-specific package & config isolation checks
  const cinPkg = fs.readFileSync(path.join(ROOT, "linux/config/cinnamon-packages.list"), "utf8");
  const xfcePkg = fs.readFileSync(path.join(ROOT, "linux/config/mint-packages.list"), "utf8");
  const obPkg = fs.readFileSync(path.join(ROOT, "linux/lite/lite-packages.list"), "utf8");
  const lxqtPkg = fs.readFileSync(path.join(ROOT, "linux/lite/manifests/lite-lxqt-packages.list"), "utf8");
  assert(!obPkg.includes("cinnamon") && !obPkg.includes("lxqt-session"), "Lite Openbox manifest must exclude Cinnamon and LXQt");
  assert(lxqtPkg.includes("lxqt-panel") && !lxqtPkg.includes("cinnamon"), "Lite LXQt manifest must include LXQt and exclude Cinnamon");
  assert(cinPkg !== xfcePkg, "Cinnamon and XFCE package manifests must stay distinct");

  console.log("PASS 4-edition build entry points, expected ISO filenames, work dirs, and manifest isolation");
}

function testChrootRepoStagingCompleteness() {
  // Parse staged entries from build-nexus-iso.sh and ensure every $REPO_ROOT path
  // referenced by all three provisioners is present inside the staged chroot repo.
  const buildScript = fs.readFileSync(path.join(ROOT, "linux/build/build-nexus-iso.sh"), "utf8");
  const cpMatches = [...buildScript.matchAll(/cp -a "\$REPO_ROOT\/([^"]+)" "\$squash_root\/tmp\/nexus-repo\/\1"/g)];
  const stagedRoots = new Set(cpMatches.map(m => m[1]));
  for (const required of ["linux", "LICENSE", "docs", "index.html", "app.js", "styles.css", "apps", "assets"]) {
    assert(stagedRoots.has(required), `build-nexus-iso.sh must stage ${required} into $squash_root/tmp/nexus-repo`);
  }
  assert(buildScript.includes("BUILD STAGE FAILED:"), "build-nexus-iso.sh must report structured BUILD STAGE FAILED diagnostics");
  assert(buildScript.includes("set -eEuo pipefail"), "build-nexus-iso.sh must enable errtrace (-E) for ERR diagnostics");

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-p241-chroot-"));
  try {
    const stagedRepo = path.join(tmp, "nexus-repo");
    fs.mkdirSync(stagedRepo, { recursive: true });
    for (const entry of stagedRoots) {
      fs.cpSync(path.join(ROOT, entry), path.join(stagedRepo, entry), { recursive: true });
    }

    const provisioners = [
      {
        rel: "linux/mint/provision-nexus-guest.sh",
        args: ["--dry-run", "--skip-ufw", "--autostart-firstboot", "--force"],
        extraEnv: {
          NEXUS_SYSTEM_CONF: path.join(stagedRepo, "linux/config/nexus-standard-cinnamon.conf"),
          NEXUS_PKG_MANIFEST: path.join(stagedRepo, "linux/config/cinnamon-packages.list"),
        },
      },
      {
        rel: "linux/mint/provision-nexus-guest.sh",
        args: ["--dry-run", "--skip-ufw", "--autostart-firstboot", "--force"],
        extraEnv: {
          NEXUS_SYSTEM_CONF: path.join(stagedRepo, "linux/config/nexus-system.conf"),
          NEXUS_PKG_MANIFEST: path.join(stagedRepo, "linux/config/mint-packages.list"),
        },
      },
      {
        rel: "linux/lite/provision-nexus-lite.sh",
        args: ["--dry-run", "--skip-ufw", "--purge-bloat", "--force"],
        extraEnv: {},
      },
      {
        rel: "linux/lite/scripts/provision-nexus-lite-lxqt.sh",
        args: ["--dry-run", "--skip-ufw", "--purge-bloat", "--force"],
        extraEnv: {},
      },
    ];

    for (const prov of provisioners) {
      const content = fs.readFileSync(path.join(ROOT, prov.rel), "utf8");
      const refs = [...content.matchAll(/"\$REPO_ROOT"\/([A-Za-z0-9_./-]+)|\$REPO_ROOT\/([A-Za-z0-9_./-]+)/g)]
        .map(m => m[1] || m[2])
        .filter(r => !r.includes("*"));
      for (const relPath of refs) {
        const candidate = path.join(stagedRepo, relPath);
        assert(
          fs.existsSync(candidate),
          `Provisioner ${prov.rel} references $REPO_ROOT/${relPath}, which was missing from staged chroot repo!`
        );
      }
      execFileSync("bash", [path.join(stagedRepo, prov.rel), ...prov.args], {
        env: { ...process.env, ...prov.extraEnv },
        stdio: "pipe",
      });
    }
    console.log("PASS chroot repo staging completeness & all 4 edition provisioners verified inside isolated staged repo");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

function testApplyIsoBrandingAllEditions() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-p241-brand-"));
  try {
    for (const ed of ["cinnamon", "xfce", "lite", "lite-lxqt"]) {
      const isoRoot = path.join(tmp, ed, "iso");
      const squashRoot = path.join(tmp, ed, "squash");
      fs.mkdirSync(path.join(isoRoot, "boot/grub"), { recursive: true });
      fs.mkdirSync(path.join(isoRoot, "isolinux"), { recursive: true });
      fs.mkdirSync(squashRoot, { recursive: true });
      fs.writeFileSync(path.join(isoRoot, "boot/grub/grub.cfg"), 'menuentry "Start Linux Mint" {}\n');
      fs.writeFileSync(path.join(isoRoot, "isolinux/txt.cfg"), "label live\n  menu label ^Start Linux Mint\n");

      execFileSync(
        "bash",
        [
          path.join(ROOT, "linux/build/apply-iso-branding.sh"),
          "--iso-root",
          isoRoot,
          "--squash-root",
          squashRoot,
          "--edition",
          ed,
        ],
        { stdio: "pipe" }
      );

      for (const rel of [
        "usr/local/share/nexus-os/ui/index.html",
        "usr/local/share/nexus-os/ui/app.js",
        "usr/local/share/nexus-os/ui/styles.css",
        "usr/local/share/nexus-os/ui/apps/terminal.js",
        "usr/local/share/nexus-os/branding/nexus-logo.svg",
        "usr/local/share/nexus-os/LICENSE",
        "etc/skel/Desktop/nexus-installer.desktop",
      ]) {
        assert(fs.existsSync(path.join(squashRoot, rel)), `${ed} branding missing ${rel}`);
      }
      const grub = fs.readFileSync(path.join(isoRoot, "boot/grub/grub.cfg"), "utf8");
      assert(grub.includes("Start NEXUS OS"), `${ed} GRUB label not branded`);
      if (ed === "lite") {
        assert(fs.existsSync(path.join(squashRoot, "usr/local/share/nexus-os/lite/openbox/rc.xml")));
      } else if (ed === "lite-lxqt") {
        assert(fs.existsSync(path.join(squashRoot, "usr/local/share/nexus-os/lite-lxqt/lxqt/panel.conf")));
      } else {
        assert(fs.existsSync(path.join(squashRoot, "usr/local/share/nexus-os/cinnamon/themes.json")));
      }
    }
    console.log("PASS shared apply-iso-branding.sh stages UI bundle, boot labels, and edition assets for all 4 editions");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

function testVerificationAndFailurePropagation() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-p241-verify-"));
  try {
    const verifyScript = path.join(ROOT, "linux/build/verify-nexus-iso.sh");
    const prereqScript = path.join(ROOT, "linux/build/check-build-prereqs.sh");
    const buildScript = path.join(ROOT, "linux/build/build-nexus-iso.sh");

    // 1. Missing ISO fails
    const missingRes = runExpectFail("bash", [verifyScript, "--edition", "lite-lxqt"], {
      env: { ...process.env, NEXUS_ISO_OUT_DIR: tmp },
    });
    assert(missingRes.stderr.includes("ISO file not found"));

    // 2. Undersized ISO fails (even with matching sha256)
    const isoPath = path.join(tmp, "nexus-os-22.3-lite-lxqt-amd64.iso");
    fs.writeFileSync(isoPath, Buffer.alloc(1024, 0));
    const smallSha = crypto.createHash("sha256").update(fs.readFileSync(isoPath)).digest("hex");
    fs.writeFileSync(`${isoPath}.sha256`, `${smallSha}  nexus-os-22.3-lite-lxqt-amd64.iso\n`);
    const smallRes = runExpectFail("bash", [verifyScript, "--edition", "lite-lxqt"], {
      env: { ...process.env, NEXUS_ISO_OUT_DIR: tmp },
    });
    assert(smallRes.stderr.includes("ISO unexpectedly small"));

    // 3. Sparse >= 500 MiB ISO with bad checksum fails
    const bigIso = path.join(tmp, "nexus-os-22.3-cinnamon-amd64.iso");
    const fd = fs.openSync(bigIso, "w");
    fs.ftruncateSync(fd, 530 * 1024 * 1024);
    fs.closeSync(fd);
    fs.writeFileSync(`${bigIso}.sha256`, `${"0".repeat(64)}  nexus-os-22.3-cinnamon-amd64.iso\n`);
    const badShaRes = runExpectFail("bash", [verifyScript, "--edition", "cinnamon"], {
      env: { ...process.env, NEXUS_ISO_OUT_DIR: tmp },
    });
    assert(badShaRes.status !== 0);

    // 4. Edition mismatch in build-info.json fails (use fast zero-filled >=500MiB sha256)
    const actualBigSha = execFileSync("sha256sum", [bigIso], { encoding: "utf8" }).split(/\s+/)[0];
    fs.writeFileSync(`${bigIso}.sha256`, `${actualBigSha}  nexus-os-22.3-cinnamon-amd64.iso\n`);
    fs.writeFileSync(
      `${bigIso}.build-info.json`,
      JSON.stringify({
        name: "NEXUS OS",
        base_distro: "linuxmint",
        base_version: "22.3",
        edition: "xfce",
        arch: "amd64",
        output_iso: "nexus-os-22.3-cinnamon-amd64.iso",
        output_iso_sha256: actualBigSha,
      })
    );
    const mismatchRes = runExpectFail("bash", [verifyScript, "--edition", "cinnamon"], {
      env: { ...process.env, NEXUS_ISO_OUT_DIR: tmp },
    });
    assert(mismatchRes.stderr.includes("Edition mismatch"), `Expected edition mismatch error, got: ${mismatchRes.stderr}`);

    // 5. Missing host dependencies fails check-build-prereqs --strict
    const emptyBin = path.join(tmp, "empty-bin");
    fs.mkdirSync(emptyBin, { recursive: true });
    const prereqRes = runExpectFail("/bin/bash", [prereqScript, "--edition", "lite-lxqt", "--strict"], {
      env: { PATH: emptyBin },
    });
    assert(prereqRes.status !== 0);

    // 6. Unprivileged live build fails cleanly
    if (process.getuid && process.getuid() !== 0) {
      const nonRootRes = runExpectFail("bash", [buildScript, "--edition", "xfce"]);
      assert(nonRootRes.stderr.includes("requires root privileges"));
    }

    // 7. Workflow gating & diagnostics checks
    const wf = fs.readFileSync(path.join(ROOT, ".github/workflows/iso-and-qemu-validation.yml"), "utf8");
    assert(wf.includes("NEXUS-ISO-BUILD-FAIL-") && wf.includes("NEXUS-ISO-VERIFY-FAIL-"));
    const cmpBlock = wf.slice(wf.indexOf("compare-lite-report:"));
    assert(
      cmpBlock.includes("if: ${{ success()"),
      "compare-lite-report must be gated on upstream iso-and-qemu success()"
    );
    assert(!cmpBlock.includes("if: always()"), "compare-lite-report artifact upload must not run with if: always()");

    console.log("PASS ISO verification guards, missing dependency failure propagation, and workflow diagnostics checks");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

testFourEditionEntryPointsAndDifferences();
testChrootRepoStagingCompleteness();
testApplyIsoBrandingAllEditions();
testVerificationAndFailurePropagation();
