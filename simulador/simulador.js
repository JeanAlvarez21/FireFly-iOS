#!/usr/bin/env node
// Simulador de la batería FireFly.
// Se hace pasar por el ESP32: escribe en Firestore el estado de la batería y registra los cortes,
// igual que lo hará el equipo real. Así la app se puede probar sin el hardware.
//
// Uso (desde esta carpeta, con clave-servicio.json de Firebase):
//   node simulador.js crear FF-0231      crea la batería y su código QR
//   node simulador.js historial FF-0231  agrega 60 días de cortes de prueba
//   node simulador.js correr FF-0231     simula en vivo (c = corte, l = luz, q = salir)
//   node simulador.js correr FF-0231 --rapido   cada segundo cuenta como un minuto
//   node simulador.js liberar FF-0231    quita el dueño para volver a vincularla

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const admin = require('firebase-admin');
const QRCode = require('qrcode');

const KEY_FILE = process.env.GOOGLE_APPLICATION_CREDENTIALS || path.join(__dirname, 'clave-servicio.json');
if (!fs.existsSync(KEY_FILE)) {
  console.error(`No encuentro ${KEY_FILE}.\nDescárgala en Firebase → Configuración del proyecto → Cuentas de servicio → Generar nueva clave privada,\ny guárdala en esta carpeta como clave-servicio.json.`);
  process.exit(1);
}
admin.initializeApp({ credential: admin.credential.cert(require(KEY_FILE)) });
const db = admin.firestore();
const { Timestamp, FieldValue } = admin.firestore;

// Batería LiFePO4 12,8 V × 12 Ah, se usa hasta el 80 %.
const CAPACITY_WH = 153.6 * 0.8;
const ROUTER_W = 9.8;
const GRID_CHARGER_W = 30;

const [, , command = 'ayuda', deviceId = 'FF-0231', ...flags] = process.argv;
const ref = db.collection('devices').doc(deviceId.toUpperCase());

function solarWatts(date = new Date()) {
  const h = date.getHours() + date.getMinutes() / 60;
  return Math.round(Math.max(0, Math.sin(((h - 6) / 12) * Math.PI)) * 22);
}

async function crear() {
  const key = crypto.randomBytes(4).toString('hex').toUpperCase();
  const id = ref.id;
  await ref.set({
    name: `FireFly ${id}`,
    pairingKey: key,
    claimKey: null,
    ownerUid: null,
    batteryPercent: 75,
    state: 'grid',
    charging: true,
    solarWatts: solarWatts(),
    routerWatts: ROUTER_W,
    minutesToFull: 120,
    minutesRemaining: null,
    gridChargingEnabled: true,
    outageStart: null,
    lastBatteryUse: null,
    firmware: '1.0.3-sim',
    wifi: 'Casa',
    simulated: true,
    updatedAt: FieldValue.serverTimestamp(),
  });
  const payload = `firefly://pair?id=${id}&k=${key}`;
  const outDir = path.join(__dirname, '..', 'QR');
  fs.mkdirSync(outDir, { recursive: true });
  const file = path.join(outDir, `${id}.png`);
  await QRCode.toFile(file, payload, { width: 600, margin: 2 });
  console.log(`Batería ${id} creada.`);
  console.log(`QR:      ${file}`);
  console.log(`Código:  ${id} ${key}   (para escribirlo a mano en la app)`);
}

async function historial() {
  const batch = db.batch();
  const now = Date.now();
  let count = 0;
  for (let d = 1; d <= 60; d++) {
    if (Math.random() > 0.35) continue;
    const start = new Date(now - d * 86400000);
    start.setHours(7 + Math.floor(Math.random() * 14), Math.floor(Math.random() * 60), 0, 0);
    const minutes = 40 + Math.floor(Math.random() * 200);
    const end = new Date(start.getTime() + minutes * 60000);
    batch.set(ref.collection('outages').doc(), {
      start: Timestamp.fromDate(start),
      end: Timestamp.fromDate(end),
      energyWh: Math.round((ROUTER_W * minutes) / 60),
      simulated: true,
    });
    count++;
  }
  await batch.commit();
  console.log(`Se agregaron ${count} cortes de prueba a ${ref.id}.`);
}

async function liberar() {
  await ref.update({ ownerUid: null, claimKey: null });
  console.log(`${ref.id} ya se puede vincular otra vez.`);
}

async function correr() {
  const snap = await ref.get();
  if (!snap.exists) { console.error(`No existe ${ref.id}. Primero: node simulador.js crear ${ref.id}`); process.exit(1); }
  const fast = flags.includes('--rapido');
  const tickSeconds = 5;
  const simMinutesPerTick = fast ? tickSeconds : tickSeconds / 60;

  let s = snap.data();
  let percent = s.batteryPercent ?? 75;
  let state = s.state ?? 'grid';
  let outageStart = s.outageStart ? s.outageStart.toDate() : null;
  let simClock = new Date();
  let gridCharging = s.gridChargingEnabled ?? true;

  // La app puede cambiar «Cargar también con la corriente».
  ref.onSnapshot(doc => { const d = doc.data(); if (d) gridCharging = d.gridChargingEnabled ?? true; });

  async function publish(extra = {}) {
    const solar = solarWatts(simClock);
    let charging = false, minutesToFull = null, minutesRemaining = null;
    if (state === 'battery') {
      // Estimación conservadora: solo el consumo del router (el sol, si hay, la alarga).
      minutesRemaining = Math.round((CAPACITY_WH * percent / 100 / ROUTER_W) * 60);
    } else {
      const chargeW = solar + (gridCharging ? GRID_CHARGER_W : 0);
      charging = chargeW > 0 && percent < 100;
      if (charging) minutesToFull = Math.round((CAPACITY_WH * (100 - percent) / 100 / chargeW) * 60);
    }
    await ref.update({
      batteryPercent: Math.round(percent), state, charging, solarWatts: solar, routerWatts: ROUTER_W,
      minutesToFull, minutesRemaining, outageStart: outageStart ? Timestamp.fromDate(outageStart) : null,
      updatedAt: FieldValue.serverTimestamp(), ...extra,
    });
    const label = state === 'battery' ? `CORTE  · quedan ${minutesRemaining} min` : `CON LUZ · ${charging ? `carga completa en ${minutesToFull} min` : 'llena'}`;
    process.stdout.write(`\r${ref.id}  ${String(Math.round(percent)).padStart(3)} %  ${label}  · solar ${solar} W        `);
  }

  async function tick() {
    simClock = new Date(simClock.getTime() + simMinutesPerTick * 60000);
    const solar = solarWatts(simClock);
    if (state === 'battery') percent -= (Math.max(0, ROUTER_W - solar) * simMinutesPerTick / 60) / CAPACITY_WH * 100;
    else percent += ((solar + (gridCharging ? GRID_CHARGER_W : 0)) * simMinutesPerTick / 60) / CAPACITY_WH * 100;
    percent = Math.min(100, Math.max(0, percent));
    await publish();
  }

  async function corte() {
    if (state === 'battery') return;
    state = 'battery'; outageStart = new Date(simClock);
    console.log(`\nSe fue la luz (${outageStart.toLocaleTimeString('es-EC')}).`);
    await publish();
  }

  async function luz() {
    if (state === 'grid') return;
    const end = new Date(simClock);
    const minutes = Math.max(1, (end - outageStart) / 60000);
    await ref.collection('outages').add({
      start: Timestamp.fromDate(outageStart), end: Timestamp.fromDate(end),
      energyWh: Math.round((ROUTER_W * minutes) / 60), simulated: true,
    });
    console.log(`\nVolvió la luz. El corte duró ${Math.round(minutes)} min.`);
    state = 'grid'; outageStart = null;
    await publish({ lastBatteryUse: Timestamp.fromDate(end) });
  }

  console.log(`Simulando ${ref.id}${fast ? ' (rápido: 1 s = 1 min)' : ''}. Teclas: c = corte de luz, l = volvió la luz, q = salir.`);
  await publish();
  const timer = setInterval(() => tick().catch(e => console.error(e.message)), tickSeconds * 1000);

  process.stdin.setRawMode?.(true);
  process.stdin.resume();
  process.stdin.on('data', async buf => {
    const k = buf.toString().toLowerCase();
    if (k === 'c') await corte();
    if (k === 'l') await luz();
    if (k === 'q' || k === '\u0003') { clearInterval(timer); console.log('\nListo.'); process.exit(0); }
  });
}

const commands = { crear, historial, correr, liberar };
if (!commands[command]) {
  console.log('Comandos: crear | historial | correr [--rapido] | liberar   (ej.: node simulador.js crear FF-0231)');
  process.exit(0);
}
commands[command]().catch(e => { console.error(e.message); process.exit(1); });
