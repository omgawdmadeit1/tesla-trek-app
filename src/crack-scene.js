import {
  AmbientLight,
  BoxGeometry,
  BufferAttribute,
  BufferGeometry,
  Clock,
  Color,
  DirectionalLight,
  Euler,
  Group,
  Mesh,
  MeshStandardMaterial,
  PerspectiveCamera,
  PointLight,
  Points,
  PointsMaterial,
  Quaternion,
  Raycaster,
  Scene,
  SphereGeometry,
  SRGBColorSpace,
  TorusGeometry,
  Vector3,
  WebGLRenderer,
} from "three";
import { rarityColor } from "./rarity.js";

const COOKIE = 0xe2b15a;

export function mountCrackScene(canvas, { reward, transparent, orientation }) {
  const renderer = new WebGLRenderer({
    canvas,
    alpha: true,
    antialias: true,
    powerPreference: "high-performance",
  });
  if (!renderer.getContext()) {
    renderer.dispose();
    throw new Error("WebGL is unavailable");
  }
  renderer.setClearColor(0x000000, transparent ? 0 : 1);
  renderer.outputColorSpace = SRGBColorSpace;
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));

  const scene = new Scene();
  if (!transparent) scene.background = new Color(0x1a1410);

  const camera = new PerspectiveCamera(50, 1, 0.05, 20);
  camera.position.set(0, orientation ? 0 : 0.05, orientation ? 0 : 0.85);

  const world = new Group();
  scene.add(world);
  scene.add(new AmbientLight(0xfff4e0, 0.85));
  const sun = new DirectionalLight(0xfff1d0, 1.4);
  sun.position.set(0.4, 1.2, 0.8);
  scene.add(sun);

  const burst = new PointLight(0xfff6d8, 0, 2.4);
  world.add(burst);

  const shellMat = new MeshStandardMaterial({ color: COOKIE, roughness: 0.55, metalness: 0.05 });
  const shellGeo = new SphereGeometry(0.13, 32, 20);
  const left = new Mesh(shellGeo, shellMat);
  const right = new Mesh(shellGeo, shellMat.clone());
  left.scale.set(1.15, 0.42, 0.95);
  right.scale.set(1.15, 0.42, 0.95);
  left.position.set(-0.02, 0.01, 0);
  right.position.set(0.02, -0.01, 0);
  right.rotation.z = Math.PI;
  const cookie = new Group();
  cookie.position.set(0, 0, -0.65);
  cookie.add(left, right);
  world.add(cookie);

  const rewardRoot = buildReward(reward);
  rewardRoot.visible = false;
  cookie.add(rewardRoot);

  const particles = buildParticles();
  particles.visible = false;
  cookie.add(particles);

  const raycaster = new Raycaster();
  const pointer = new Vector3();
  const ndc = { x: 0, y: 0 };
  const clock = new Clock();
  const euler = new Euler();
  const deviceQuat = new Quaternion();
  const tilt = new Quaternion(-Math.sqrt(0.5), 0, 0, Math.sqrt(0.5));
  const zee = new Vector3(0, 0, 1);
  const forward = new Vector3();
  let phase = "idle";
  let elapsed = 0;
  let frame = 0;
  let placed = !orientation;
  let onCracked = () => {};

  function onOrientation(event) {
    if (!orientation || event.alpha == null || event.beta == null || event.gamma == null) return;
    const alpha = (event.alpha * Math.PI) / 180;
    const beta = (event.beta * Math.PI) / 180;
    const gamma = (event.gamma * Math.PI) / 180;
    const screen = ((Number(window.orientation) || 0) * Math.PI) / 180;
    euler.set(beta, alpha, -gamma, "YXZ");
    deviceQuat.setFromEuler(euler);
    deviceQuat.multiply(tilt);
    deviceQuat.multiply(new Quaternion().setFromAxisAngle(zee, -screen));
    camera.quaternion.copy(deviceQuat);
    if (!placed) {
      forward.set(0, 0, -1).applyQuaternion(camera.quaternion);
      cookie.position.copy(forward.multiplyScalar(0.65));
      cookie.lookAt(camera.position);
      placed = true;
    }
  }

  if (orientation) window.addEventListener("deviceorientation", onOrientation);

  function resize() {
    const width = canvas.clientWidth || 320;
    const height = canvas.clientHeight || 480;
    camera.aspect = width / Math.max(height, 1);
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
  }

  function tick() {
    frame = requestAnimationFrame(tick);
    const dt = Math.min(clock.getDelta(), 0.05);
    if (phase !== "idle") elapsed += dt;
    if (phase === "cracking") stepCrack(elapsed);
    if (phase === "revealed") {
      rewardRoot.rotation.y += dt * 1.4;
      rewardRoot.position.y = 0.16 + Math.sin(elapsed * 1.6) * 0.012;
    }
    if (phase === "idle" && !orientation) cookie.rotation.y += dt * 0.35;
    driftParticles(dt);
    renderer.render(scene, camera);
  }

  function stepCrack(t) {
    const open = Math.min(t / 0.55, 1);
    left.position.x = -0.02 - open * 0.16;
    right.position.x = 0.02 + open * 0.16;
    left.position.y = 0.01 + open * 0.05;
    right.position.y = -0.01 + open * 0.04;
    left.rotation.z = open * 0.7;
    right.rotation.z = Math.PI - open * 0.8;
    burst.intensity = t < 0.35 ? (1 - t / 0.35) * 18 : 0;
    if (t > 0.25 && !rewardRoot.visible) {
      rewardRoot.visible = true;
      rewardRoot.scale.setScalar(0.05);
    }
    if (rewardRoot.visible && t < 1.1) {
      const rise = Math.min(Math.max(t - 0.25, 0) / 0.7, 1);
      const eased = 1 - (1 - rise) ** 3;
      rewardRoot.scale.setScalar(0.05 + eased * 0.95);
      rewardRoot.position.y = eased * 0.16;
      rewardRoot.rotation.y = eased * Math.PI;
    }
    if (t >= 1.15 && phase === "cracking") {
      phase = "revealed";
      onCracked();
    }
  }

  function driftParticles(dt) {
    if (!particles.visible) return;
    const pos = particles.geometry.attributes.position;
    const vel = particles.geometry.attributes.velocity;
    for (let i = 0; i < pos.count; i += 1) {
      pos.setXYZ(i, pos.getX(i) + vel.getX(i) * dt, pos.getY(i) + vel.getY(i) * dt, pos.getZ(i) + vel.getZ(i) * dt);
      vel.setY(i, vel.getY(i) - dt * 0.35);
    }
    pos.needsUpdate = true;
  }

  function crack() {
    if (phase !== "idle") return false;
    phase = "cracking";
    elapsed = 0;
    particles.visible = true;
    return true;
  }

  function pointerCrack(event) {
    const rect = canvas.getBoundingClientRect();
    ndc.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    ndc.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
    pointer.set(ndc.x, ndc.y, 0.5);
    raycaster.setFromCamera(pointer, camera);
    if (raycaster.intersectObjects([left, right], false).length > 0) crack();
  }

  canvas.addEventListener("pointerdown", pointerCrack);
  resize();
  tick();

  return {
    crack,
    setOnCracked(fn) {
      onCracked = fn;
    },
    resize,
    destroy() {
      cancelAnimationFrame(frame);
      canvas.removeEventListener("pointerdown", pointerCrack);
      window.removeEventListener("deviceorientation", onOrientation);
      renderer.dispose();
      shellGeo.dispose();
      shellMat.dispose();
      right.material.dispose();
      particles.geometry.dispose();
      particles.material.dispose();
    },
  };
}

function buildReward(reward) {
  const group = new Group();
  const color = new Color(rarityColor(reward.rarity));
  const material = new MeshStandardMaterial({
    color,
    metalness: reward.kind === "keychain" ? 0.75 : 0.25,
    roughness: reward.kind === "keychain" ? 0.28 : 0.45,
    emissive: color,
    emissiveIntensity: 0.18,
  });
  if (reward.kind === "keychain") {
    const ring = new Mesh(new TorusGeometry(0.07, 0.012, 16, 32), material);
    const charm = new Mesh(new SphereGeometry(0.035, 20, 16), material);
    charm.position.y = -0.09;
    group.add(ring, charm);
  } else if (reward.kind === "skin") {
    group.add(new Mesh(new BoxGeometry(0.16, 0.1, 0.02), material));
  } else {
    const unknown = reward.kind;
    throw new Error(`Unknown reward kind: ${String(unknown)}`);
  }
  return group;
}

function buildParticles() {
  const count = 70;
  const positions = new Float32Array(count * 3);
  const velocities = new Float32Array(count * 3);
  for (let i = 0; i < count; i += 1) {
    const theta = Math.random() * Math.PI * 2;
    const lift = Math.random() * 0.6 + 0.15;
    velocities[i * 3] = Math.cos(theta) * lift;
    velocities[i * 3 + 1] = Math.random() * 0.55 + 0.05;
    velocities[i * 3 + 2] = Math.sin(theta) * lift * 0.6;
  }
  const geometry = new BufferGeometry();
  geometry.setAttribute("position", new BufferAttribute(positions, 3));
  geometry.setAttribute("velocity", new BufferAttribute(velocities, 3));
  const material = new PointsMaterial({
    color: 0xfff1c9,
    size: 0.018,
    transparent: true,
    opacity: 0.9,
    depthWrite: false,
  });
  return new Points(geometry, material);
}
