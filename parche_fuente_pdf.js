// Hace que TODOS los PDFs usen DejaVu Sans, para que el simbolo del euro
// deje de salir como un cuadradito.
//
// Busca `pw.Document()` en todo lib/ y lo cambia por
// `await FuentesPdf.documento()`, añadiendo el import donde haga falta.
//
// Uso:  node parche_fuente_pdf.js
//
// No toca ningun archivo hasta haber revisado todos. Si alguno no encaja,
// aborta entero y no deja nada a medias.

const fs = require('fs');
const path = require('path');

const RAIZ = 'lib';
const VIEJO = 'pw.Document()';
const NUEVO = 'await FuentesPdf.documento()';

function morir(msg) {
  console.error('\n  ABORTADO: ' + msg + '\n  No se ha tocado ningun archivo.\n');
  process.exit(1);
}

if (!fs.existsSync(RAIZ)) {
  morir('no encuentro la carpeta lib. Ejecuta esto desde la raiz del proyecto.');
}

// Recorrer lib/ buscando .dart
function buscar(dir, salida) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) buscar(p, salida);
    else if (e.name.endsWith('.dart')) salida.push(p);
  }
  return salida;
}

const todos = buscar(RAIZ, []);
const pendientes = [];

for (const archivo of todos) {
  const txt = fs.readFileSync(archivo, 'utf8').replace(/\r\n/g, '\n');
  if (!txt.includes(VIEJO)) continue;

  // Contar cuantas veces aparece, para avisar
  let n = 0, i = 0;
  while ((i = txt.indexOf(VIEJO, i)) !== -1) { n++; i += VIEJO.length; }

  // La linea que lo contiene debe estar dentro de una funcion async, o el
  // await no vale. Se comprueba mirando hacia atras la firma mas cercana.
  const pos = txt.indexOf(VIEJO);
  const antes = txt.slice(0, pos);
  const ultimaAsync = antes.lastIndexOf('async');
  const ultimaLlaveFn = antes.lastIndexOf('\n  Future');
  if (ultimaAsync === -1) {
    morir(archivo + ': el pw.Document() no esta dentro de una funcion async. '
        + 'Hay que revisarlo a mano.');
  }
  void ultimaLlaveFn;

  pendientes.push({ archivo, veces: n });
}

if (pendientes.length === 0) {
  console.log('\n  No hay ningun pw.Document() que cambiar.');
  console.log('  O ya estaba hecho, o los PDFs se crean de otra forma.\n');
  process.exit(0);
}

console.log('\n  Archivos a cambiar:');
for (const p of pendientes) {
  console.log('   - ' + p.archivo + '  (' + p.veces + ')');
}

// Aplicar
let total = 0;
for (const { archivo } of pendientes) {
  const original = fs.readFileSync(archivo, 'utf8');
  const eraCRLF = original.includes('\r\n');
  let txt = original.replace(/\r\n/g, '\n');

  txt = txt.split(VIEJO).join(NUEVO);

  // El import, si no estaba. La ruta depende de si el archivo vive en
  // lib/services o en lib/ui.
  if (!txt.includes('fuentes_pdf.dart')) {
    const enServices = archivo.replace(/\\/g, '/').includes('lib/services/');
    const ruta = enServices ? 'fuentes_pdf.dart' : '../services/fuentes_pdf.dart';
    const linea = "import '" + ruta + "';";

    // Detras del ultimo import del archivo.
    const imports = [...txt.matchAll(/^import .*;$/gm)];
    if (imports.length === 0) morir(archivo + ': no tiene ningun import.');
    const ultimo = imports[imports.length - 1];
    const corte = ultimo.index + ultimo[0].length;
    txt = txt.slice(0, corte) + '\n' + linea + txt.slice(corte);
  }

  if (txt.includes(VIEJO)) morir(archivo + ': ha quedado algun pw.Document() sin cambiar.');
  if (!txt.includes('FuentesPdf.documento()')) morir(archivo + ': no se ha escrito la llamada.');

  fs.writeFileSync(archivo + '.bak', original, 'utf8');
  fs.writeFileSync(archivo, eraCRLF ? txt.replace(/\n/g, '\r\n') : txt, 'utf8');
  total++;
}

console.log('\n  Listo. ' + total + ' archivos cambiados.');
console.log('  Cada uno tiene su copia en .bak\n');
console.log('  Si el analyze se queja de "await in non-async", dime en que');
console.log('  archivo y linea: ese hay que arreglarlo a mano.\n');
