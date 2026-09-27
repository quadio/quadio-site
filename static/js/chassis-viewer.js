let threeLib = null;

function makeMeshTexture(THREE) {
  const size = 512;
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = "#7a838c";
  ctx.fillRect(0, 0, size, size);
  ctx.fillStyle = "#2a3036";
  const step = 7;
  for (let y = 0; y < size; y += step) {
    for (let x = 0; x < size; x += step) {
      const ox = (y / step) % 2 === 0 ? 0 : step / 2;
      ctx.beginPath();
      ctx.arc(x + ox, y, 2.15, 0, Math.PI * 2);
      ctx.fill();
    }
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 8;
  texture.wrapS = THREE.ClampToEdgeWrapping;
  texture.wrapT = THREE.ClampToEdgeWrapping;
  texture.repeat.set(1, 1);
  return texture;
}

function buildChassis(THREE, RoundedBoxGeometry) {
  const group = new THREE.Group();
  // NCASE T1 sandwich: 33.5 x 22 x 13.5 cm (length x height x thickness).
  const scale = 1 / 15;
  const width = 33.5 * scale;
  const height = 22 * scale;
  const depth = 13.5 * scale;
  const footRadius = 0.7 * scale;

  const gunmetal = new THREE.MeshStandardMaterial({
    color: 0x6a737d,
    metalness: 0.48,
    roughness: 0.36,
  });
  const gunmetalDark = new THREE.MeshStandardMaterial({
    color: 0x4a515a,
    metalness: 0.42,
    roughness: 0.44,
  });
  const gunmetalFront = new THREE.MeshStandardMaterial({
    color: 0x5c656f,
    metalness: 0.52,
    roughness: 0.3,
  });

  const body = new THREE.Mesh(new RoundedBoxGeometry(width, height, depth, 2, 0.006), gunmetal);
  group.add(body);

  const inner = new THREE.Mesh(
    new THREE.BoxGeometry(width * 0.94, height * 0.9, depth * 0.72),
    new THREE.MeshStandardMaterial({ color: 0x141618, roughness: 0.92, metalness: 0.12 })
  );
  group.add(inner);

  const mesh = new THREE.Mesh(
    new THREE.PlaneGeometry(width * 0.93, height * 0.88),
    new THREE.MeshStandardMaterial({
      color: 0xffffff,
      metalness: 0.32,
      roughness: 0.5,
      map: makeMeshTexture(THREE),
    })
  );
  mesh.position.z = depth / 2 + 0.003;
  group.add(mesh);

  const back = mesh.clone();
  back.position.z = -(depth / 2 + 0.003);
  back.rotation.y = Math.PI;
  group.add(back);

  const front = new THREE.Mesh(new THREE.BoxGeometry(0.018, height * 0.99, depth * 0.99), gunmetalFront);
  front.position.x = width / 2 + 0.001;
  group.add(front);

  const seam = new THREE.Mesh(new THREE.BoxGeometry(0.02, 0.008, depth * 0.9), gunmetalDark);
  seam.position.set(width / 2 + 0.01, -height * 0.12, 0);
  group.add(seam);

  const footGeo = new THREE.SphereGeometry(footRadius, 20, 12, 0, Math.PI * 2, 0, Math.PI / 2);
  const spanX = width * 0.36;
  const spanZ = depth * 0.32;
  for (const [x, z] of [
    [-spanX, -spanZ],
    [spanX, -spanZ],
    [-spanX, spanZ],
    [spanX, spanZ],
  ]) {
    const foot = new THREE.Mesh(footGeo, gunmetalDark);
    foot.rotation.x = Math.PI;
    foot.position.set(x, -height / 2, z);
    group.add(foot);
  }

  group.position.y = footRadius;
  group.rotation.y = -0.55;
  return group;
}

async function loadThree() {
  if (threeLib) {
    return threeLib;
  }
  const [THREE, controlsMod, roundedMod] = await Promise.all([
    import("https://esm.sh/three@0.170.0"),
    import("https://esm.sh/three@0.170.0/examples/jsm/controls/OrbitControls.js"),
    import("https://esm.sh/three@0.170.0/examples/jsm/geometries/RoundedBoxGeometry.js"),
  ]);
  threeLib = {
    THREE,
    OrbitControls: controlsMod.OrbitControls,
    RoundedBoxGeometry: roundedMod.RoundedBoxGeometry,
  };
  return threeLib;
}

function attachViewer(dialog) {
  const stage = dialog.querySelector("[data-chassis-stage]");
  const status = dialog.querySelector("[data-chassis-status]");
  let renderer;
  let camera;
  let controls;
  let frame = 0;
  let running = false;

  const stop = () => {
    running = false;
    cancelAnimationFrame(frame);
  };

  const tick = () => {
    if (!running) {
      return;
    }
    controls.update();
    renderer.render(renderer.__scene, camera);
    frame = requestAnimationFrame(tick);
  };

  const resize = () => {
    if (!renderer) {
      return;
    }
    const width = stage.clientWidth;
    const height = Math.max(stage.clientHeight, 1);
    renderer.setSize(width, height, false);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
  };

  const start = async () => {
    if (renderer) {
      running = true;
      resize();
      tick();
      return;
    }
    if (status) {
      status.hidden = false;
      status.textContent = "Loading 3D view…";
    }
    try {
      const { THREE, OrbitControls, RoundedBoxGeometry } = await loadThree();
      const scene = new THREE.Scene();
      scene.background = new THREE.Color(0x201a16);

      camera = new THREE.PerspectiveCamera(36, 1, 0.1, 24);
      camera.position.set(0.85, 1.15, 4.35);

      renderer = new THREE.WebGLRenderer({ antialias: true });
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
      renderer.outputColorSpace = THREE.SRGBColorSpace;
      renderer.toneMapping = THREE.ACESFilmicToneMapping;
      renderer.toneMappingExposure = 1.16;
      renderer.__scene = scene;
      stage.replaceChildren(renderer.domElement);
      renderer.domElement.setAttribute("aria-label", "3D view of the Burton Mk1 chassis. Drag to rotate.");

      scene.add(new THREE.AmbientLight(0xcfd5dc, 0.42));
      scene.add(new THREE.HemisphereLight(0xe4e8ee, 0x2a2e33, 0.85));
      const key = new THREE.DirectionalLight(0xf0f3f6, 1.7);
      key.position.set(1.4, 3.6, 4.4);
      scene.add(key);
      const rim = new THREE.DirectionalLight(0x4aa0e8, 0.22);
      rim.position.set(-3, 1.1, -1.2);
      scene.add(rim);
      const fill = new THREE.DirectionalLight(0xc5ccd3, 0.55);
      fill.position.set(-2.2, 1.6, 2.4);
      scene.add(fill);

      scene.add(buildChassis(THREE, RoundedBoxGeometry));

      const floor = new THREE.Mesh(
        new THREE.CircleGeometry(4.2, 48),
        new THREE.MeshStandardMaterial({ color: 0x16181b, metalness: 0.08, roughness: 1 })
      );
      floor.rotation.x = -Math.PI / 2;
      floor.position.y = -0.78;
      scene.add(floor);

      controls = new OrbitControls(camera, renderer.domElement);
      controls.enableDamping = true;
      controls.dampingFactor = 0.08;
      controls.enablePan = false;
      controls.minDistance = 2.2;
      controls.maxDistance = 7;
      controls.target.set(0, 0.08, 0);
      controls.update();

      const onResize = () => resize();
      window.addEventListener("resize", onResize);
      running = true;
      resize();
      requestAnimationFrame(() => {
        resize();
        tick();
      });
      if (status) {
        status.hidden = true;
      }
    } catch (error) {
      if (status) {
        status.hidden = false;
        status.textContent = "Unable to load the 3D view.";
      }
      throw error;
    }
  };

  dialog.addEventListener("close", stop);
  return { start, stop };
}

function initChassisViewers() {
  document.querySelectorAll("[data-chassis-open]").forEach((button) => {
    const dialog = document.getElementById(button.getAttribute("data-chassis-open"));
    if (!dialog) {
      return;
    }
    const viewer = attachViewer(dialog);
    button.addEventListener("click", async () => {
      dialog.showModal();
      try {
        await viewer.start();
      } catch {
        /* status text already updated */
      }
    });
    dialog.addEventListener("click", (event) => {
      if (event.target === dialog) {
        dialog.close();
      }
    });
    dialog.querySelector("[data-chassis-close]")?.addEventListener("click", () => {
      dialog.close();
    });
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initChassisViewers);
} else {
  initChassisViewers();
}
