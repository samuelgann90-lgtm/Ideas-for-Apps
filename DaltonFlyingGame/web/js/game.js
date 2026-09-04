/* Dalton Flyer — WW2 first-person P-51 combat */
(function () {
  "use strict";

  if (typeof THREE === "undefined") {
    document.body.innerHTML = "<p style='color:#fff;padding:24px'>Could not load the 3D engine.</p>";
    return;
  }

  var canvas = document.getElementById("view");
  var overlay = document.getElementById("overlay");
  var btnStart = document.getElementById("btn-start");
  var btnGuns = document.getElementById("btn-guns");
  var btnRockets = document.getElementById("btn-rockets");
  var stickBase = document.getElementById("stick-base");
  var stickKnob = document.getElementById("stick-knob");
  var toastEl = document.getElementById("toast");
  var hitmark = document.getElementById("hitmark");
  var damageFlash = document.getElementById("damage-flash");
  var hpBar = document.getElementById("hp-bar");

  var mats = {};
  function mat(color, extra) {
    var key = String(color) + (extra ? JSON.stringify(extra) : "");
    if (!mats[key]) {
      mats[key] = new THREE.MeshLambertMaterial(Object.assign({ color: color }, extra || {}));
    }
    return mats[key];
  }

  function boxMesh(w, h, d, color, extra) {
    return new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat(color, extra));
  }

  function cylMesh(rt, rb, h, segs, color) {
    return new THREE.Mesh(new THREE.CylinderGeometry(rt, rb, h, segs), mat(color));
  }

  function addAt(parent, mesh, x, y, z, rx, ry, rz) {
    mesh.position.set(x || 0, y || 0, z || 0);
    if (rx) mesh.rotation.x = rx;
    if (ry) mesh.rotation.y = ry;
    if (rz) mesh.rotation.z = rz;
    parent.add(mesh);
    return mesh;
  }

  function rand(a, b) {
    return a + Math.random() * (b - a);
  }

  function clamp(v, a, b) {
    return Math.max(a, Math.min(b, v));
  }

  var tmpV = new THREE.Vector3();
  var tmpV2 = new THREE.Vector3();
  var tmpQ = new THREE.Quaternion();
  var up = new THREE.Vector3(0, 1, 0);

  /* ---------- audio ---------- */
  var audio = {
    ctx: null,
    master: null,
    engine: null,
    engineGain: null,
    ready: false
  };

  function unlockAudio() {
    if (audio.ready) return;
    var AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    audio.ctx = new AC();
    audio.master = audio.ctx.createGain();
    audio.master.gain.value = 0.22;
    audio.master.connect(audio.ctx.destination);

    var osc = audio.ctx.createOscillator();
    osc.type = "sawtooth";
    osc.frequency.value = 72;
    var filter = audio.ctx.createBiquadFilter();
    filter.type = "lowpass";
    filter.frequency.value = 420;
    var g = audio.ctx.createGain();
    g.gain.value = 0.08;
    osc.connect(filter);
    filter.connect(g);
    g.connect(audio.master);
    osc.start();
    audio.engine = osc;
    audio.engineFilter = filter;
    audio.engineGain = g;
    audio.ready = true;
  }

  function beep(freq, dur, type, vol) {
    if (!audio.ready) return;
    var t = audio.ctx.currentTime;
    var o = audio.ctx.createOscillator();
    var g = audio.ctx.createGain();
    o.type = type || "square";
    o.frequency.setValueAtTime(freq, t);
    g.gain.setValueAtTime(vol || 0.08, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g);
    g.connect(audio.master);
    o.start(t);
    o.stop(t + dur + 0.02);
  }

  function noiseBurst(dur, vol) {
    if (!audio.ready) return;
    var n = audio.ctx.sampleRate * dur;
    var buf = audio.ctx.createBuffer(1, n, audio.ctx.sampleRate);
    var data = buf.getChannelData(0);
    for (var i = 0; i < n; i++) data[i] = Math.random() * 2 - 1;
    var src = audio.ctx.createBufferSource();
    src.buffer = buf;
    var g = audio.ctx.createGain();
    var t = audio.ctx.currentTime;
    g.gain.setValueAtTime(vol || 0.12, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    var f = audio.ctx.createBiquadFilter();
    f.type = "bandpass";
    f.frequency.value = 1800;
    src.connect(f);
    f.connect(g);
    g.connect(audio.master);
    src.start();
  }

  /* ---------- input ---------- */
  var stick = { x: 0, y: 0, active: false, id: null };
  var keys = {};
  var gunsHeld = false;
  var rocketQueued = false;
  var pointerStickId = null;

  function setKnob(x, y) {
    var r = 36;
    stickKnob.style.transform = "translate(calc(-50% + " + x * r + "px), calc(-50% + " + y * r + "px))";
  }

  function updateStickFromEvent(e, el) {
    var rect = el.getBoundingClientRect();
    var cx = rect.left + rect.width / 2;
    var cy = rect.top + rect.height / 2;
    var dx = (e.clientX - cx) / (rect.width * 0.5);
    var dy = (e.clientY - cy) / (rect.height * 0.5);
    var mag = Math.hypot(dx, dy);
    if (mag > 1) {
      dx /= mag;
      dy /= mag;
    }
    stick.x = clamp(dx, -1, 1);
    stick.y = clamp(dy, -1, 1);
    setKnob(stick.x, stick.y);
  }

  function clearStick() {
    stick.x = 0;
    stick.y = 0;
    stick.active = false;
    pointerStickId = null;
    setKnob(0, 0);
  }

  stickBase.addEventListener("pointerdown", function (e) {
    e.preventDefault();
    stickBase.setPointerCapture(e.pointerId);
    pointerStickId = e.pointerId;
    stick.active = true;
    updateStickFromEvent(e, stickBase);
  });
  stickBase.addEventListener("pointermove", function (e) {
    if (pointerStickId !== e.pointerId) return;
    updateStickFromEvent(e, stickBase);
  });
  function endStick(e) {
    if (pointerStickId !== e.pointerId) return;
    clearStick();
  }
  stickBase.addEventListener("pointerup", endStick);
  stickBase.addEventListener("pointercancel", endStick);

  btnGuns.addEventListener("pointerdown", function (e) {
    e.preventDefault();
    btnGuns.setPointerCapture(e.pointerId);
    gunsHeld = true;
    btnGuns.classList.add("held");
    if (state.mode === "play") {
      fireGuns();
      gunCd = 0.075;
    }
  });
  function endGuns() {
    gunsHeld = false;
    btnGuns.classList.remove("held");
  }
  btnGuns.addEventListener("pointerup", endGuns);
  btnGuns.addEventListener("pointercancel", endGuns);

  btnRockets.addEventListener("pointerdown", function (e) {
    e.preventDefault();
    rocketQueued = true;
    btnRockets.classList.add("held");
    if (state.mode === "play" && rocketCd <= 0) {
      rocketQueued = false;
      rocketCd = 0.55;
      fireRocket();
    }
  });
  btnRockets.addEventListener("pointerup", function () {
    btnRockets.classList.remove("held");
  });
  btnRockets.addEventListener("pointercancel", function () {
    btnRockets.classList.remove("held");
  });

  window.addEventListener("keydown", function (e) {
    keys[e.code] = true;
    if (e.code === "Space") {
      e.preventDefault();
      gunsHeld = true;
      if (state.mode === "play") {
        fireGuns();
        gunCd = 0.075;
      }
    }
    if (e.code === "KeyF" || e.code === "ControlLeft") {
      rocketQueued = true;
      if (state.mode === "play" && rocketCd <= 0) {
        rocketQueued = false;
        rocketCd = 0.55;
        fireRocket();
      }
    }
  });
  window.addEventListener("keyup", function (e) {
    keys[e.code] = false;
    if (e.code === "Space") gunsHeld = false;
  });
  window.addEventListener("blur", function () {
    gunsHeld = false;
    clearStick();
  });

  function keyboardStick() {
    var x = 0, y = 0;
    if (keys.KeyA || keys.ArrowLeft) x -= 1;
    if (keys.KeyD || keys.ArrowRight) x += 1;
    if (keys.KeyW || keys.ArrowUp) y -= 1;
    if (keys.KeyS || keys.ArrowDown) y += 1;
    if (!stick.active) {
      stick.x = x;
      stick.y = y;
      setKnob(x, y);
    }
  }

  /* ---------- scene ---------- */
  var renderer = new THREE.WebGLRenderer({
    canvas: canvas,
    antialias: false,
    powerPreference: "high-performance"
  });
  renderer.setClearColor(0x6fb7d6);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));

  var scene = new THREE.Scene();
  scene.fog = new THREE.Fog(0x8ec8dc, 320, 1400);

  var camera = new THREE.PerspectiveCamera(68, 1, 0.15, 1400);
  var player = new THREE.Group();
  scene.add(player);
  player.add(camera);
  camera.position.set(0, 0.62, 0.18);

  scene.add(new THREE.HemisphereLight(0xb8dfff, 0x3d4a28, 0.85));
  var sun = new THREE.DirectionalLight(0xfff1c8, 0.95);
  sun.position.set(-200, 260, 80);
  scene.add(sun);
  scene.add(new THREE.AmbientLight(0x8899aa, 0.25));

  /* ---------- models ---------- */
  function makeMustangCockpit() {
    var g = new THREE.Group();
    var silver = 0xc5cdd4;
    var stripeW = 0xf2f2f2;
    var stripeB = 0x1a1a1a;

    var nose = cylMesh(0.42, 0.55, 1.8, 8, 0x2b2b2b);
    addAt(g, nose, 0, -0.55, -2.0, Math.PI / 2);

    var spinner = cylMesh(0.16, 0.28, 0.4, 8, 0xe2b43a);
    addAt(g, spinner, 0, -0.55, -3.05, Math.PI / 2);

    var prop = boxMesh(0.06, 1.8, 0.14, 0x222222);
    prop.position.set(0, -0.55, -3.3);
    g.add(prop);
    g.userData.prop = prop;

    function wing(side) {
      var w = boxMesh(4.2, 0.12, 1.2, silver);
      w.position.set(side * 2.9, -1.05, -0.7);
      g.add(w);
      var s1 = boxMesh(0.38, 0.14, 1.22, stripeW);
      s1.position.set(side * 2.0, -1.04, -0.7);
      g.add(s1);
      var s2 = boxMesh(0.38, 0.14, 1.22, stripeB);
      s2.position.set(side * 2.45, -1.04, -0.7);
      g.add(s2);
      var s3 = boxMesh(0.38, 0.14, 1.22, stripeW);
      s3.position.set(side * 2.9, -1.04, -0.7);
      g.add(s3);
      var gun = cylMesh(0.045, 0.045, 0.7, 6, 0x222222);
      addAt(g, gun, side * 1.35, -0.95, -1.25, Math.PI / 2);
    }
    wing(-1);
    wing(1);

    var dash = boxMesh(1.5, 0.22, 0.55, 0x2a2418);
    dash.position.set(0, 0.18, -0.55);
    g.add(dash);

    var glass = boxMesh(1.35, 0.02, 0.7, 0x87b8c8, { transparent: true, opacity: 0.12 });
    glass.position.set(0, 0.78, -0.15);
    g.add(glass);

    return g;
  }

  function makeEnemyFighter() {
    var g = new THREE.Group();
    var body = 0x6e7a55;
    var yellow = 0xddb430;
    addAt(g, cylMesh(0.32, 0.42, 4.4, 8, body), 0, 0, 0, Math.PI / 2);
    addAt(g, cylMesh(0.18, 0.32, 1.1, 8, yellow), 0, 0, 2.5, Math.PI / 2);
    addAt(g, boxMesh(5.6, 0.12, 1.15, body), 0, -0.08, 0.3);
    addAt(g, boxMesh(0.12, 1.35, 0.9, 0x5a6348), 0, 0.7, -1.85);
    addAt(g, boxMesh(1.7, 0.1, 0.55, 0x5a6348), 0, 0.15, -2.05);
    var prop = boxMesh(0.06, 1.8, 0.12, 0x222);
    prop.position.set(0, 0, 3.15);
    g.add(prop);
    g.userData.prop = prop;
    var canopy = new THREE.Mesh(new THREE.SphereGeometry(0.32, 8, 6), mat(0x223344));
    canopy.position.set(0, 0.32, 0.35);
    g.add(canopy);
    g.scale.set(2.1, 2.1, 2.1);
    return g;
  }

  function makeTrainCar(kind) {
    var g = new THREE.Group();
    if (kind === "loco") {
      addAt(g, boxMesh(2.2, 2.1, 6.2, 0x3b3f45), 0, 1.4, 0);
      addAt(g, cylMesh(0.55, 0.55, 2.4, 8, 0x2e3238), 0, 2.1, 1.4, Math.PI / 2);
      addAt(g, cylMesh(0.28, 0.34, 1.3, 8, 0x4a4e55), 0, 3.0, 1.6);
      addAt(g, boxMesh(2.2, 2.0, 2.2, 0x5a2a1e), 0, 2.15, -2.1);
    } else {
      var colors = [0x6b3a22, 0x3d4d38, 0x5c4a2e, 0x4a3b28];
      addAt(g, boxMesh(2.15, 1.9, 4.6, colors[kind % colors.length]), 0, 1.45, 0);
    }
    addAt(g, cylMesh(0.38, 0.38, 0.28, 8, 0x222), -0.85, 0.4, 1.4, 0, 0, Math.PI / 2);
    addAt(g, cylMesh(0.38, 0.38, 0.28, 8, 0x222), 0.85, 0.4, 1.4, 0, 0, Math.PI / 2);
    addAt(g, cylMesh(0.38, 0.38, 0.28, 8, 0x222), -0.85, 0.4, -1.4, 0, 0, Math.PI / 2);
    addAt(g, cylMesh(0.38, 0.38, 0.28, 8, 0x222), 0.85, 0.4, -1.4, 0, 0, Math.PI / 2);
    return g;
  }

  function makeBoat(kind) {
    var g = new THREE.Group();
    var hull = kind === "cargo" ? 0x4a4538 : 0x3e4a3a;
    var hullMesh = boxMesh(3.4, 1.1, kind === "cargo" ? 9.5 : 7.2, hull);
    hullMesh.position.y = 0.2;
    g.add(hullMesh);
    var bow = boxMesh(2.2, 0.9, 2.2, hull);
    bow.position.set(0, 0.25, kind === "cargo" ? 5.2 : 4.1);
    bow.rotation.x = 0.2;
    g.add(bow);
    addAt(g, boxMesh(2.2, 1.4, 2.6, 0xcfc6ae), 0, 1.4, -0.6);
    if (kind === "cargo") {
      addAt(g, boxMesh(2.4, 1.6, 2.4, 0x6a5a3a), 0, 1.5, 2.2);
      addAt(g, boxMesh(2.4, 1.3, 2.2, 0x5a4a32), 0, 1.35, -2.8);
    } else {
      addAt(g, cylMesh(0.12, 0.12, 2.4, 6, 0x888), 0.6, 2.4, 0.8);
    }
    return g;
  }

  /* ---------- world ---------- */
  var world = new THREE.Group();
  scene.add(world);

  var ocean = new THREE.Mesh(
    new THREE.PlaneGeometry(3500, 3500),
    mat(0x2e8cb8)
  );
  ocean.rotation.x = -Math.PI / 2;
  world.add(ocean);

  var sand = new THREE.Mesh(new THREE.CircleGeometry(310, 40), mat(0xc9b57a));
  sand.rotation.x = -Math.PI / 2;
  sand.position.y = 0.15;
  world.add(sand);

  var island = new THREE.Mesh(new THREE.CircleGeometry(268, 40), mat(0x4f9a40));
  island.rotation.x = -Math.PI / 2;
  island.position.y = 0.35;
  world.add(island);

  var field = new THREE.Mesh(new THREE.CircleGeometry(90, 24), mat(0x6b8f3a));
  field.rotation.x = -Math.PI / 2;
  field.position.set(-40, 0.42, 20);
  world.add(field);

  var strip = boxMesh(18, 0.2, 140, 0x6e6a62);
  strip.position.set(-30, 0.5, -20);
  world.add(strip);

  var bed = boxMesh(5.4, 0.35, 430, 0x3a2a18);
  bed.position.set(42, 0.55, 10);
  world.add(bed);
  var railL = boxMesh(0.18, 0.12, 430, 0x8a8e94);
  railL.position.set(40.4, 0.78, 10);
  world.add(railL);
  var railR = boxMesh(0.18, 0.12, 430, 0x8a8e94);
  railR.position.set(43.6, 0.78, 10);
  world.add(railR);

  var i;
  for (i = 0; i < 18; i++) {
    var hill = new THREE.Mesh(new THREE.SphereGeometry(rand(10, 22), 8, 6), mat(i % 2 ? 0x3f6a34 : 0x507a3c));
    hill.scale.y = 0.35;
    hill.position.set(rand(-180, 40), 0, rand(-140, 160));
    world.add(hill);
  }

  for (i = 0; i < 28; i++) {
    var tree = new THREE.Group();
    addAt(tree, cylMesh(0.28, 0.34, 1.6, 5, 0x5a3a22), 0, 0.8, 0);
    addAt(tree, new THREE.Mesh(new THREE.ConeGeometry(1.6, 3.2, 6), mat(0x2f5c2a)), 0, 3.0, 0);
    var tx = rand(-200, 200);
    var tz = rand(-180, 180);
    if (Math.abs(tx - 42) < 18) tx += 30;
    if (Math.abs(tx + 30) < 20 && Math.abs(tz + 20) < 80) tx += 40;
    tree.position.set(tx, 0.35, tz);
    world.add(tree);
  }

  for (i = 0; i < 7; i++) {
    var mt = new THREE.Mesh(new THREE.ConeGeometry(rand(40, 80), rand(50, 110), 5), mat(0x6d7a6a));
    mt.position.set(rand(-420, 420), 10, rand(380, 620) * (Math.random() < 0.5 ? 1 : -1));
    if (Math.abs(mt.position.x) < 220) mt.position.x += 260 * (mt.position.x < 0 ? -1 : 1);
    world.add(mt);
  }

  for (i = 0; i < 16; i++) {
    var cloud = new THREE.Mesh(new THREE.SphereGeometry(rand(12, 22), 8, 6), mat(0xf4f7fa));
    cloud.scale.set(rand(1.4, 2.4), 0.45, rand(1, 1.6));
    cloud.position.set(rand(-500, 500), rand(70, 140), rand(-500, 500));
    cloud.userData.drift = rand(1.5, 4);
    world.add(cloud);
    cloud.userData.isCloud = true;
  }

  var cockpit = makeMustangCockpit();
  player.add(cockpit);

  /* ---------- entities ---------- */
  var targets = [];
  var fx = [];
  var tracers = [];
  var rockets = [];
  var enemyBullets = [];

  function addTarget(mesh, type, hp, radius, points) {
    var t = {
      mesh: mesh,
      type: type,
      hp: hp,
      maxHp: hp,
      radius: radius,
      points: points,
      alive: true,
      smoke: 0,
      extra: null
    };
    targets.push(t);
    scene.add(mesh);
    return t;
  }

  function spawnWorldTargets() {
    targets.forEach(function (t) {
      scene.remove(t.mesh);
    });
    targets = [];

    var carKinds = ["loco", 1, 2, 3, 4, 5];
    var trainZ = -90;
    carKinds.forEach(function (kind, idx) {
      var car = makeTrainCar(kind);
      car.scale.set(1.7, 1.7, 1.7);
      var z = trainZ - idx * 10.4;
      car.position.set(42, 1.4, z);
      car.rotation.y = Math.PI;
      var t = addTarget(car, "rail", kind === "loco" ? 70 : 45, kind === "loco" ? 5.2 : 4.2, kind === "loco" ? 150 : 80);
      t.extra = { railIndex: idx, baseZ: z };
    });

    var boatSpots = [
      { x: -55, z: 20, kind: "patrol" },
      { x: -80, z: -25, kind: "cargo" },
      { x: -48, z: 70, kind: "patrol" },
      { x: -95, z: 50, kind: "cargo" }
    ];
    boatSpots.forEach(function (s) {
      var b = makeBoat(s.kind);
      b.scale.set(1.8, 1.8, 1.8);
      b.position.set(s.x, 1.1, s.z);
      var t = addTarget(b, "boat", s.kind === "cargo" ? 80 : 55, 6.5, 120);
      t.extra = { phase: rand(0, Math.PI * 2), x: s.x, z: s.z, kind: s.kind };
    });

    var planeSpawns = [
      { x: 6, y: 34, z: -40 },
      { x: -18, y: 40, z: 30 },
      { x: 55, y: 36, z: 20 },
      { x: 20, y: 48, z: 90 },
      { x: -40, y: 42, z: 70 },
      { x: 90, y: 50, z: 50 }
    ];
    planeSpawns.forEach(function (s, idx) {
      var p = makeEnemyFighter();
      p.position.set(s.x, s.y, s.z);
      var t = addTarget(p, "plane", 35, 7.2, 200);
      t.extra = {
        heading: rand(0, Math.PI * 2),
        climb: 0,
        orbit: 36 + idx * 10,
        origin: new THREE.Vector3(s.x, s.y, s.z),
        fireCd: rand(1, 3)
      };
    });
  }

  /* ---------- combat ---------- */
  var gunCd = 0;
  var rocketCd = 0;
  var gunToggle = 0;
  var tracerGeo = new THREE.BoxGeometry(0.16, 0.16, 22);
  var tracerMat = new THREE.MeshBasicMaterial({ color: 0xfff2a1 });
  var rocketGeo = new THREE.CylinderGeometry(0.22, 0.32, 2.4, 6);
  var rocketMat = new THREE.MeshLambertMaterial({ color: 0xe8c07a, emissive: 0x662200 });

  function playerForward() {
    camera.getWorldDirection(tmpV);
    return tmpV;
  }

  function playerPos() {
    camera.getWorldPosition(tmpV2);
    return tmpV2;
  }

  function assistAim(dir) {
    var best = null;
    var bestDot = 0.975;
    var origin = playerPos().clone();
    targets.forEach(function (t) {
      if (!t.alive) return;
      var to = t.mesh.position.clone().sub(origin).normalize();
      var dot = to.dot(dir);
      if (dot > bestDot) {
        bestDot = dot;
        best = to;
      }
    });
    if (best) dir.lerp(best, 0.45).normalize();
    return dir;
  }

  function damageTarget(t, amount, impact) {
    if (!t.alive) return;
    t.hp -= amount;
    t.smoke = Math.min(1, t.smoke + 0.2);
    spawnSpark(impact || t.mesh.position);
    showHit();
    beep(420, 0.05, "square", 0.05);
    try { navigator.vibrate && navigator.vibrate(18); } catch (e) {}
    if (t.hp <= 0) destroyTarget(t);
  }

  function destroyTarget(t) {
    t.alive = false;
    state.score += t.points;
    explode(t.mesh.position.clone(), t.type === "plane" ? 6 : 8);
    noiseBurst(0.28, 0.18);
    beep(140, 0.2, "sawtooth", 0.1);
    toast(
      t.type === "plane" ? "BANDIT DOWN" :
      t.type === "rail" ? "RAIL CAR DESTROYED" :
      "SHIP DESTROYED"
    );
    t.mesh.visible = false;
    refreshCounts();
    checkWin();
  }

  function hitScan(origin, dir, range) {
    var hit = null;
    var hitT = range;
    targets.forEach(function (t) {
      if (!t.alive) return;
      var to = t.mesh.position.clone().sub(origin);
      var along = to.dot(dir);
      if (along < 2 || along > range) return;
      var closest = origin.clone().addScaledVector(dir, along);
      if (closest.distanceTo(t.mesh.position) <= t.radius) {
        if (along < hitT) {
          hitT = along;
          hit = t;
        }
      }
    });
    return hit ? { target: hit, point: origin.clone().addScaledVector(dir, hitT) } : null;
  }

  function fireGuns() {
    var origin = playerPos().clone();
    var dir = assistAim(playerForward().clone());
    gunToggle = 1 - gunToggle;
    var right = new THREE.Vector3();
    right.crossVectors(dir, up).normalize();
    var muzzle = origin.clone()
      .addScaledVector(right, gunToggle ? 1.1 : -1.1)
      .addScaledVector(dir, 3.2)
      .add(new THREE.Vector3(0, -0.35, 0));

    var tracer = new THREE.Mesh(tracerGeo, tracerMat);
    tracer.position.copy(muzzle).addScaledVector(dir, 14);
    tracer.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), dir);
    scene.add(tracer);
    tracers.push({ mesh: tracer, life: 0.22, dir: dir.clone(), speed: 420 });

    var hit = hitScan(muzzle, dir, 420);
    if (hit) damageTarget(hit.target, 8, hit.point);
    noiseBurst(0.045, 0.07);
    camera.position.y = 0.62 + rand(-0.03, 0.03);
  }

  function fireRocket() {
    var origin = playerPos().clone();
    var dir = assistAim(playerForward().clone());
    var mesh = new THREE.Mesh(rocketGeo, rocketMat);
    mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir);
    mesh.position.copy(origin).addScaledVector(dir, 3);
    scene.add(mesh);
    rockets.push({
      mesh: mesh,
      vel: dir.multiplyScalar(78),
      life: 4.2
    });
    beep(180, 0.12, "sawtooth", 0.1);
    noiseBurst(0.1, 0.1);
  }

  function explode(pos, size) {
    var ball = new THREE.Mesh(
      new THREE.SphereGeometry(size * 0.35, 8, 6),
      new THREE.MeshBasicMaterial({ color: 0xff9140, transparent: true, opacity: 0.9 })
    );
    ball.position.copy(pos);
    scene.add(ball);
    fx.push({ mesh: ball, life: 0.55, grow: size });
    var j;
    for (j = 0; j < 7; j++) {
      var bit = boxMesh(rand(0.3, 0.8), rand(0.2, 0.5), rand(0.3, 0.7), 0x333);
      bit.position.copy(pos);
      scene.add(bit);
      fx.push({
        mesh: bit,
        life: 0.8,
        vel: new THREE.Vector3(rand(-18, 18), rand(6, 22), rand(-18, 18))
      });
    }
  }

  function spawnSpark(pos) {
    var s = new THREE.Mesh(
      new THREE.SphereGeometry(0.35, 6, 4),
      new THREE.MeshBasicMaterial({ color: 0xfff1a8 })
    );
    s.position.copy(pos);
    scene.add(s);
    fx.push({ mesh: s, life: 0.12 });
  }

  function showHit() {
    hitmark.classList.add("show");
    setTimeout(function () { hitmark.classList.remove("show"); }, 90);
  }

  var toastTimer = 0;
  function toast(msg) {
    toastEl.textContent = msg;
    toastEl.classList.add("show");
    toastTimer = 1.6;
  }

  /* ---------- flight / game state ---------- */
  var state = {
    mode: "menu",
    score: 0,
    hp: 100,
    heading: 0,
    pitch: 0,
    roll: 0,
    speed: 48,
    time: 0
  };

  function resetFlight() {
    state.heading = Math.PI;
    state.pitch = 0.02;
    state.roll = 0;
    state.speed = 48;
    state.hp = 100;
    state.score = 0;
    state.time = 0;
    player.position.set(8, 30, -130);
    player.rotation.set(0.02, Math.PI, 0);
    camera.position.set(0, 0.62, 0.18);
    rockets.forEach(function (r) { scene.remove(r.mesh); });
    tracers.forEach(function (t) { scene.remove(t.mesh); });
    enemyBullets.forEach(function (b) { scene.remove(b.mesh); });
    fx.forEach(function (f) { scene.remove(f.mesh); });
    rockets = [];
    tracers = [];
    enemyBullets = [];
    fx = [];
    spawnWorldTargets();
    refreshCounts();
    hpBar.style.width = "100%";
    document.getElementById("score").textContent = "0";
  }

  function refreshCounts() {
    var p = 0, r = 0, b = 0;
    targets.forEach(function (t) {
      if (!t.alive) return;
      if (t.type === "plane") p++;
      else if (t.type === "rail") r++;
      else b++;
    });
    document.getElementById("c-planes").textContent = String(p);
    document.getElementById("c-rail").textContent = String(r);
    document.getElementById("c-boats").textContent = String(b);
  }

  function checkWin() {
    var left = targets.filter(function (t) { return t.alive; }).length;
    if (left === 0 && state.mode === "play") {
      state.mode = "win";
      showEnd("MISSION COMPLETE", "Every target is down. Score " + state.score + ".", "FLY AGAIN");
    }
  }

  function crash(reason) {
    if (state.mode !== "play") return;
    state.mode = "dead";
    explode(player.position.clone(), 10);
    noiseBurst(0.4, 0.22);
    showEnd("SHOT DOWN", reason + "  Score " + state.score + ".", "RETRY");
  }

  function showEnd(title, body, cta) {
    overlay.classList.add("show");
    overlay.querySelector("h1").textContent = title;
    overlay.querySelector("h2").textContent = "P-51 MUSTANG";
    overlay.querySelector(".blurb").textContent = body;
    overlay.querySelector(".how").style.display = "none";
    overlay.querySelector(".theater").textContent = "DALTON FLYER";
    btnStart.textContent = cta;
  }

  function showMenu() {
    overlay.classList.add("show");
    overlay.querySelector("h1").textContent = "DALTON FLYER";
    overlay.querySelector("h2").textContent = "P-51 MUSTANG";
    overlay.querySelector(".blurb").textContent = "First-person WW2 fighter combat. Fly the Red Tail Mustang and knock out enemy planes, rail cars, and boats.";
    overlay.querySelector(".how").style.display = "block";
    overlay.querySelector(".theater").textContent = "1944 · WESTERN FRONT";
    btnStart.textContent = "START MISSION";
  }

  btnStart.addEventListener("click", function () {
    unlockAudio();
    overlay.classList.remove("show");
    resetFlight();
    state.mode = "play";
    toast("WEAPONS FREE — GET THE TRAINS AND SHIPS");
    try { navigator.vibrate && navigator.vibrate(30); } catch (e) {}
  });

  function hurtPlayer(amount) {
    if (state.mode !== "play") return;
    state.hp -= amount;
    hpBar.style.width = clamp(state.hp, 0, 100) + "%";
    damageFlash.style.opacity = "1";
    setTimeout(function () { damageFlash.style.opacity = "0"; }, 90);
    if (state.hp <= 0) crash("Enemy fire tore up the Mustang.");
  }

  /* ---------- updates ---------- */
  function updateFlight(dt) {
    keyboardStick();
    var ix = stick.x;
    var iy = stick.y;

    if (Math.abs(ix) < 0.06) state.roll *= Math.exp(-3 * dt);
    else state.roll = clamp(state.roll + ix * 2.3 * dt, -0.85, 0.85);

    if (Math.abs(iy) < 0.06) state.pitch *= Math.exp(-2.2 * dt);
    else state.pitch = clamp(state.pitch - iy * 1.5 * dt, -0.62, 0.55);

    state.heading -= state.roll * 1.15 * dt;
    state.speed = clamp(state.speed + (-iy) * 18 * dt, 32, 72);

    player.rotation.order = "YXZ";
    player.rotation.y = state.heading;
    player.rotation.x = state.pitch;
    player.rotation.z = -state.roll;

    camera.getWorldDirection(tmpV);
    player.position.addScaledVector(tmpV, state.speed * dt);
    camera.position.x *= 0.6;
    camera.position.y += (0.62 - camera.position.y) * 8 * dt;
    camera.position.z += (0.18 - camera.position.z) * 8 * dt;

    if (player.position.y < 4.2) crash("You hit the ground.");
    if (player.position.y > 160) state.pitch = Math.min(state.pitch, 0);

    if (cockpit.userData.prop) cockpit.userData.prop.rotation.z += dt * 28;

    if (audio.engine) {
      audio.engine.frequency.value = 64 + state.speed * 0.9;
      audio.engineFilter.frequency.value = 350 + state.speed * 6;
    }
  }

  function updateEnemies(dt) {
    targets.forEach(function (t) {
      if (!t.alive || t.type !== "plane") return;
      var e = t.extra;
      e.heading += dt * 0.35;
      var ox = e.origin.x + Math.cos(e.heading) * e.orbit;
      var oz = e.origin.z + Math.sin(e.heading) * e.orbit;
      var oy = e.origin.y + Math.sin(e.heading * 1.4) * 8;
      t.mesh.position.set(ox, oy, oz);
      t.mesh.lookAt(
        ox + Math.cos(e.heading + Math.PI / 2) * 12,
        oy,
        oz + Math.sin(e.heading + Math.PI / 2) * 12
      );
      t.mesh.rotateY(Math.PI);
      if (t.mesh.userData.prop) t.mesh.userData.prop.rotation.x += dt * 25;

      e.fireCd -= dt;
      var toPlayer = player.position.clone().sub(t.mesh.position);
      var dist = toPlayer.length();
      if (e.fireCd <= 0 && dist < 140) {
        e.fireCd = rand(1.6, 2.8);
        toPlayer.normalize();
        var fwd = new THREE.Vector3();
        t.mesh.getWorldDirection(fwd);
        if (fwd.dot(toPlayer) > 0.55) {
          var bolt = new THREE.Mesh(tracerGeo, new THREE.MeshBasicMaterial({ color: 0xff5a3a }));
          bolt.position.copy(t.mesh.position);
          bolt.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), toPlayer);
          scene.add(bolt);
          enemyBullets.push({ mesh: bolt, vel: toPlayer.multiplyScalar(90), life: 1.6 });
        }
      }
    });
  }

  function updateGround(dt) {
    targets.forEach(function (t) {
      if (!t.alive) return;
      if (t.type === "rail") {
        t.mesh.position.z += 18 * dt;
        if (t.mesh.position.z > 200) t.mesh.position.z = -200;
      }
      if (t.type === "boat") {
        t.extra.phase += dt * 0.25;
        t.mesh.position.z = t.extra.z + Math.sin(t.extra.phase) * 18;
        t.mesh.rotation.y = Math.sin(t.extra.phase) * 0.2 + Math.PI / 2;
        t.mesh.position.y = 0.7 + Math.sin(t.extra.phase * 2) * 0.15;
      }
    });
    world.children.forEach(function (c) {
      if (c.userData && c.userData.isCloud) {
        c.position.x += c.userData.drift * dt;
        if (c.position.x > 600) c.position.x = -600;
      }
    });
  }

  function updateProjectiles(dt) {
    gunCd -= dt;
    rocketCd -= dt;
    if (state.mode === "play" && gunsHeld && gunCd <= 0) {
      gunCd = 0.075;
      fireGuns();
    }
    if (state.mode === "play" && rocketQueued && rocketCd <= 0) {
      rocketQueued = false;
      rocketCd = 0.55;
      fireRocket();
    } else {
      rocketQueued = false;
    }

    var k;
    for (k = tracers.length - 1; k >= 0; k--) {
      tracers[k].life -= dt;
      if (tracers[k].dir) {
        tracers[k].mesh.position.addScaledVector(tracers[k].dir, tracers[k].speed * dt);
      }
      if (tracers[k].life <= 0) {
        scene.remove(tracers[k].mesh);
        tracers.splice(k, 1);
      }
    }

    for (k = rockets.length - 1; k >= 0; k--) {
      var rk = rockets[k];
      rk.life -= dt;
      rk.mesh.position.addScaledVector(rk.vel, dt);
      var hitR = null;
      targets.forEach(function (t) {
        if (!t.alive || hitR) return;
        if (t.mesh.position.distanceTo(rk.mesh.position) < t.radius + 1.4) hitR = t;
      });
      if (hitR) {
        damageTarget(hitR, 55, rk.mesh.position);
        explode(rk.mesh.position.clone(), 5);
        scene.remove(rk.mesh);
        rockets.splice(k, 1);
      } else if (rk.life <= 0 || rk.mesh.position.y < 0.5) {
        if (rk.mesh.position.y < 0.5) explode(rk.mesh.position.clone(), 4);
        scene.remove(rk.mesh);
        rockets.splice(k, 1);
      }
    }

    for (k = enemyBullets.length - 1; k >= 0; k--) {
      var eb = enemyBullets[k];
      eb.life -= dt;
      eb.mesh.position.addScaledVector(eb.vel, dt);
      if (eb.mesh.position.distanceTo(player.position) < 3.2) {
        hurtPlayer(9);
        scene.remove(eb.mesh);
        enemyBullets.splice(k, 1);
      } else if (eb.life <= 0) {
        scene.remove(eb.mesh);
        enemyBullets.splice(k, 1);
      }
    }

    for (k = fx.length - 1; k >= 0; k--) {
      var f = fx[k];
      f.life -= dt;
      if (f.grow) f.mesh.scale.multiplyScalar(1 + dt * 4);
      if (f.mesh.material && f.mesh.material.opacity !== undefined) {
        f.mesh.material.opacity = Math.max(0, f.life * 2);
      }
      if (f.vel) {
        f.mesh.position.addScaledVector(f.vel, dt);
        f.vel.y -= 28 * dt;
      }
      if (f.life <= 0) {
        scene.remove(f.mesh);
        fx.splice(k, 1);
      }
    }
  }

  function updateHud() {
    document.getElementById("score").textContent = String(state.score);
    document.getElementById("alt").textContent = String(Math.round(player.position.y * 32));
    document.getElementById("spd").textContent = String(Math.round(state.speed * 7.2));
    if (toastTimer > 0) {
      toastTimer -= 0.016;
      if (toastTimer <= 0) toastEl.classList.remove("show");
    }
  }

  /* ---------- loop ---------- */
  var clock = new THREE.Clock();
  function resize() {
    var w = window.innerWidth;
    var h = window.innerHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / Math.max(1, h);
    camera.updateProjectionMatrix();
  }
  window.addEventListener("resize", resize);
  resize();

  spawnWorldTargets();
  player.position.set(8, 30, -130);
  player.rotation.order = "YXZ";
  player.rotation.set(0.02, Math.PI, 0);
  state.heading = Math.PI;

  function tick() {
    var dt = Math.min(0.045, clock.getDelta());
    state.time += dt;
    if (state.mode === "play") {
      updateFlight(dt);
      updateEnemies(dt);
      updateGround(dt);
      updateProjectiles(dt);
      updateHud();
    } else {
      player.position.y = 30 + Math.sin(state.time) * 1.2;
      if (cockpit.userData.prop) cockpit.userData.prop.rotation.z += dt * 18;
      updateGround(dt);
      updateEnemies(dt);
    }
    renderer.render(scene, camera);
    requestAnimationFrame(tick);
  }
  tick();
})();
