// Arregla inventario_pdf_service.dart: _construir crea el documento con
// await, asi que tiene que ser async. Sus dos llamadas ya estan dentro de
// funciones async, asi que solo hay que ponerles el await.
//
// Uso:  node parche_inventario.js

const fs = require('fs');
const path = require('path');

const ARCHIVO = path.join('lib', 'services', 'inventario_pdf_service.dart');

function morir(msg) {
  console.error('\n  ABORTADO: ' + msg + '\n  El archivo NO se ha tocado.\n');
  process.exit(1);
}

if (!fs.existsSync(ARCHIVO)) morir('no encuentro ' + ARCHIVO);

const original = fs.readFileSync(ARCHIVO, 'utf8');
const eraCRLF = original.includes('\r\n');
let txt = original.replace(/\r\n/g, '\n');

if (txt.includes('static Future<pw.Document> _construir')) {
  console.log('\n  Ya estaba arreglado.\n');
  process.exit(0);
}

function veces(aguja) {
  let n = 0, i = 0;
  while ((i = txt.indexOf(aguja, i)) !== -1) { n++; i += aguja.length; }
  return n;
}

// 1) la firma: una sola vez
const FIRMA = 'static pw.Document _construir({';
if (veces(FIRMA) !== 1) morir('la firma de _construir aparece ' + veces(FIRMA) + ' veces.');

// 2) las llamadas: exactamente dos
const LLAMADA = 'final doc = _construir(porFamilia: porFamilia, titulo: titulo);';
if (veces(LLAMADA) !== 2) morir('esperaba 2 llamadas a _construir y hay ' + veces(LLAMADA) + '.');

// 3) el cierre de parametros seguido del cuerpo sin async
const CIERRE = '    required String titulo,\n  }) {';
if (veces(CIERRE) !== 1) morir('no encuentro el cierre de parametros de _construir.');

txt = txt.replace(FIRMA, 'static Future<pw.Document> _construir({');
txt = txt.replace(CIERRE, '    required String titulo,\n  }) async {');
txt = txt.split(LLAMADA).join(
  'final doc = await _construir(porFamilia: porFamilia, titulo: titulo);');

// comprobaciones
if (!txt.includes('static Future<pw.Document> _construir({')) morir('no se cambio la firma.');
if (!txt.includes('}) async {')) morir('no se marco el cuerpo como async.');
if (veces('final doc = await _construir(') !== 2) morir('no se pusieron los dos await.');
if (txt.includes('final doc = _construir(porFamilia')) morir('ha quedado una llamada sin await.');

fs.writeFileSync(ARCHIVO + '.bak', original, 'utf8');
fs.writeFileSync(ARCHIVO, eraCRLF ? txt.replace(/\n/g, '\r\n') : txt, 'utf8');

console.log('\n  Listo.');
console.log('  - _construir ahora devuelve Future<pw.Document>');
console.log('  - cuerpo marcado como async');
console.log('  - await puesto en sus 2 llamadas');
console.log('  - copia en ' + ARCHIVO + '.bak\n');
